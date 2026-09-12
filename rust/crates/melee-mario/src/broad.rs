//! The board, any-versus-any training on it, and the overall balanced gate.
//!
//! Every one of the 625 ordered matchups is active from the first generation,
//! and the graded question is ONE question: does the frozen champion win more
//! than the target share of a balanced any-versus-any distribution against the
//! Awesome cyborg? That is an aggregate claim over a distribution, not a claim
//! about any individual matchup, and everything here is written so the
//! difference stays visible:
//!
//!   * The gate is an AGGREGATE over a balanced held-out panel. Per-hull
//!     numbers are reported next to it as DIAGNOSTICS, with their sample
//!     counts, so a blind spot is legible. No per-hull minimum gates anything.
//!   * Paired seat outcomes are correlated, so the Wilson bound on the
//!     aggregate is an operational confidence check, not a formal guarantee
//!     over the whole board. The dashboard is told to say so.
//!   * Training panels stay small and shared. Coverage is earned over
//!     generations by a checkpointed rotation, not by enumerating the board
//!     every generation.
//!
//! Held-out seeds reuse the existing AUDIT and CONFIRM stream partitions. The
//! stream partition is the only thing that guarantees anything: seeds from two
//! different [`StreamTag`]s provably cannot be equal, which is what keeps
//! held-out fights disjoint from training. Inside one stream there is no such
//! guarantee, only a distinct logical namespace (see [`TRIAL_BASE`]).

use crate::audit::{wilson_lower, Round, Tally};
use crate::episode::Task;
use crate::rng::{episode_seed, Stream, StreamTag};
use crate::sampler::{CellStat, SamplerStats};
use melee_sim::catalog::{ShipKind, ALL_SHIPS, MELEE_SHIP_COUNT};
use serde_json::{json, Value};

/// Ordered pairs on the full board.
pub const BOARD: usize = MELEE_SHIP_COUNT * MELEE_SHIP_COUNT;

/// Base of the trial-index namespace a held-out round uses inside the AUDIT and
/// CONFIRM seed partitions. Every held-out trial index has the top bit set, so
/// it can never collide with an index any other caller of [`episode_seed`]
/// would form from a plain counter.
///
/// This separates logical NAMESPACES. It is NOT a disjointness proof for the
/// seeds themselves: `episode_seed` hashes into a finite partition of about
/// 5.4e8 members, so two different indices inside one stream can collide and
/// produce the same battle. Only distinct [`StreamTag`]s guarantee seeds cannot
/// be equal, which is why training, readiness, audit and confirmation each have
/// their own stream rather than four index ranges of one. A collision within a
/// stream costs one repeated battle; it cannot leak a withheld fight into
/// training.
pub const TRIAL_BASE: u64 = 1 << 63;

/// How a generation's training panel is drawn, and what the gate demands.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct BroadConfig {
    /// Fights each population member plays per generation.
    pub panel: usize,
    /// Share of that panel drawn by the balanced coverage rotation. The rest
    /// is drawn adaptively, on the weights [`weight`] assigns.
    pub coverage: f64,
    /// How fast older training evidence fades out of a cell's statistics. The
    /// adaptive weight is computed over decayed counts, so this constant is
    /// part of the sampler's memory rather than of the gate.
    pub decay: f64,
    /// Ordered pairs in one held-out round. Each is played in BOTH seats, so
    /// the round is twice this many games. Must be a positive multiple of the
    /// roster size so every hull appears equally often on both sides.
    pub pairs: usize,
    /// Aggregate win rate the Wilson lower bound must clear.
    pub target: f64,
}

impl Default for BroadConfig {
    fn default() -> Self {
        BroadConfig {
            // 32 fights per genome per generation against a population of 300
            // is 9,600 fights a generation, spread over 625 cells. Coverage is
            // earned over generations, not bought every generation: enumerating
            // the board every generation would cost 625 fights per genome.
            panel: 32,
            coverage: 0.5,
            decay: 0.90,
            // 500 pairs is 1,000 games and exactly 20 appearances of every hull
            // on each side.
            pairs: 500,
            target: 0.80,
        }
    }
}

impl BroadConfig {
    /// Games in one held-out round.
    pub fn games(&self) -> usize {
        self.pairs * 2
    }

    pub fn coverage_slots(&self) -> usize {
        ((self.panel as f64 * self.coverage).round() as usize).min(self.panel)
    }

    pub fn to_json(self) -> Value {
        json!({"panel": self.panel, "coverage": self.coverage, "decay": self.decay,
               "pairs": self.pairs, "target": self.target})
    }

    /// Rejects settings the algorithm cannot honour rather than clamping into
    /// something the operator did not ask for. In particular a pair count that
    /// is not a multiple of the roster size could not be balanced.
    pub fn from_json(value: &Value) -> Option<BroadConfig> {
        let panel = value.get("panel")?.as_u64().filter(|n| *n > 0)? as usize;
        let coverage = value
            .get("coverage")?
            .as_f64()
            .filter(|c| (0.0..=1.0).contains(c))?;
        let pairs = value.get("pairs")?.as_u64().filter(|p| {
            *p > 0 && *p % MELEE_SHIP_COUNT as u64 == 0
        })? as usize;
        let target = value
            .get("target")?
            .as_f64()
            .filter(|t| (0.0..1.0).contains(t))?;
        // A decay of one never forgets and a decay above one would amplify old
        // evidence without bound, so neither is a memory this can honour.
        let decay = value
            .get("decay")?
            .as_f64()
            .filter(|d| (0.0..=1.0).contains(d))?;
        Some(BroadConfig {
            panel,
            coverage,
            decay,
            pairs,
            target,
        })
    }
}

/// Who sits in the other seat. One variant, and an enum rather than nothing at
/// all, so a cell always says which opponent produced its evidence and a
/// document naming an opponent this build does not implement is refused rather
/// than read as the one it does.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub enum Opponent {
    /// The original Awesome cyborg, which is what the run is graded on.
    Cyborg,
}

impl Opponent {
    pub fn as_str(self) -> &'static str {
        match self {
            Opponent::Cyborg => "cyborg",
        }
    }

    pub fn parse(raw: &str) -> Option<Opponent> {
        match raw {
            "cyborg" => Some(Opponent::Cyborg),
            _ => None,
        }
    }
}

/// One ordered matchup. `us` and `them` index [`ALL_SHIPS`], which is the hull
/// order the policy network's five-bit identifiers already use, so a cell index
/// means the same hull everywhere in the workspace.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub struct Cell {
    pub foe: Opponent,
    pub us: u8,
    pub them: u8,
}

impl Cell {
    pub fn our_ship(self) -> ShipKind {
        ALL_SHIPS[self.us as usize]
    }

    pub fn their_ship(self) -> ShipKind {
        ALL_SHIPS[self.them as usize]
    }

    /// Stable identity used to derive episode seeds.
    pub fn key(self) -> u64 {
        (self.foe as u64) * 1_000_000 + self.us as u64 * 100 + self.them as u64
    }

    pub fn encode(self) -> Value {
        json!([self.foe.as_str(), self.us, self.them])
    }

    /// Strict inverse of [`Cell::encode`]. The shape must be exactly a triple
    /// and both indices must name a hull that exists, so a malformed or
    /// foreign checkpoint is rejected instead of narrowing into a wrong
    /// matchup or panicking later on a roster lookup.
    pub fn decode(value: &Value) -> Option<Cell> {
        let triple = value.as_array()?;
        if triple.len() != 3 {
            return None;
        }
        let index = |at: usize| -> Option<u8> {
            let raw = triple.get(at)?.as_u64()?;
            (raw < MELEE_SHIP_COUNT as u64).then_some(raw as u8)
        };
        Some(Cell {
            foe: Opponent::parse(triple.first()?.as_str()?)?,
            us: index(1)?,
            them: index(2)?,
        })
    }
}

/// Every ordered cyborg matchup on the full board.
pub fn board() -> Vec<Cell> {
    let mut out = Vec::with_capacity(BOARD);
    for us in 0..MELEE_SHIP_COUNT as u8 {
        for them in 0..MELEE_SHIP_COUNT as u8 {
            out.push(Cell {
                foe: Opponent::Cyborg,
                us,
                them,
            });
        }
    }
    out
}

fn shuffled(rng: &mut Stream) -> [u8; MELEE_SHIP_COUNT] {
    let mut order = [0u8; MELEE_SHIP_COUNT];
    for (at, slot) in order.iter_mut().enumerate() {
        *slot = at as u8;
    }
    for at in (1..MELEE_SHIP_COUNT).rev() {
        order.swap(at, rng.below(at + 1));
    }
    order
}

/// The balanced coverage rotation.
///
/// `cursor` counts coverage fights issued, ever, and is the ONLY state the
/// schedule needs: a tour is `cursor / 625`, the block inside it is
/// `(cursor % 625) / 25` and the lane is `cursor % 25`. Each tour draws two
/// fresh permutations of the rosters from `(salt, tour)`; inside a tour our
/// hull is `ours[lane]` and theirs is `theirs[(lane + block) % 25]`.
///
/// Because the offset is constant within a block, every ALIGNED block of 25
/// fights, meaning `cursor / 25` held fixed, contains each of our hulls exactly
/// once and each opponent hull exactly once, and a full tour of 625 contains
/// every ordered pair exactly once. A sliding window of 25 that straddles a
/// block boundary carries no such guarantee and none is claimed; the balance
/// this schedule promises is per aligned block and per tour.
///
/// The cursor is a pure argument, so resuming from a checkpointed value
/// reproduces the identical schedule, mid-tour included.
pub fn coverage_cell(salt: u64, cursor: u64) -> Cell {
    let tour = cursor / BOARD as u64;
    let within = (cursor % BOARD as u64) as usize;
    let block = within / MELEE_SHIP_COUNT;
    let lane = within % MELEE_SHIP_COUNT;
    let mut rng = Stream::seeded(
        salt ^ tour.wrapping_mul(0x9e37_79b9_7f4a_7c15) ^ 0x62_726f_6164,
    );
    let ours = shuffled(&mut rng);
    let theirs = shuffled(&mut rng);
    Cell {
        foe: Opponent::Cyborg,
        us: ours[lane],
        them: theirs[(lane + block) % MELEE_SHIP_COUNT],
    }
}

/// Rehearsal floor in the adaptive weight, so no cell is ever abandoned.
const REHEARSAL_FLOOR: f64 = 1.0;
/// Weight on the bounded "how little do we know about this cell" term.
const UNCERTAINTY_WEIGHT: f64 = 3.0;
/// Weight on the bounded "how much is still learnable here" term.
const POTENTIAL_WEIGHT: f64 = 4.0;
/// Decayed games at which the uncertainty term has halved.
const EVIDENCE_SCALE: f64 = 24.0;

/// How much attention the adaptive half of a panel gives one cell.
///
/// Constants rather than configuration: these four numbers shape the search
/// itself, no flag has ever set them, and a run that stored them would be
/// storing the algorithm it was compiled with. What IS configuration is how
/// much of the panel reaches this function at all ([`BroadConfig::coverage`])
/// and how fast the evidence it reads fades ([`BroadConfig::decay`]).
///
/// Two bounded terms and a floor, and deliberately NO unbounded "still losing,
/// try harder" term:
///
///   * uncertainty = `1 / (1 + games / scale)`, one for a cell never played and
///     falling towards zero as evidence accumulates. This is what pulls the
///     sampler onto cells it does not yet know anything about.
///   * potential = `4 p (1 - p)` on the smoothed win rate: maximal at a coin
///     flip, zero at both ends. A cell already won is not worth grinding, and
///     neither is one being lost 98% of the time; effort goes where the policy
///     is near a decision boundary and can actually still move.
///
/// Both terms live in `[0, 1]`, so a cell's weight is bounded above by
/// `REHEARSAL_FLOOR + UNCERTAINTY_WEIGHT + POTENTIAL_WEIGHT` however bad it
/// gets, and bounded below by
/// [`REHEARSAL_FLOOR`]. The floor and the coverage rotation together are what
/// keep a hopeless cell rehearsed rather than abandoned, while the bound is
/// what stops it eating the panel forever.
pub fn weight(stat: &CellStat) -> f64 {
    let p = stat.smoothed();
    let uncertainty = 1.0 / (1.0 + stat.games / EVIDENCE_SCALE);
    let potential = (4.0 * p * (1.0 - p)).clamp(0.0, 1.0);
    REHEARSAL_FLOOR + UNCERTAINTY_WEIGHT * uncertainty + POTENTIAL_WEIGHT * potential
}

fn pick(stats: &SamplerStats, rng: &mut Stream, pool: &[Cell]) -> Cell {
    let weights: Vec<f64> = pool
        .iter()
        .map(|cell| weight(stats.cells.get(cell).unwrap_or(&CellStat::default())))
        .collect();
    let total: f64 = weights.iter().sum();
    if !(total > 0.0) {
        return pool[rng.below(pool.len())];
    }
    let mut target = rng.unit() * total;
    for (cell, weight) in pool.iter().zip(&weights) {
        target -= weight;
        if target <= 0.0 {
            return *cell;
        }
    }
    pool[pool.len() - 1]
}

/// The generation's training panel. Coverage slots come first so a short panel
/// never loses its balance guarantee; seats alternate by slot parity so both
/// orientations are always represented. `cursor` is advanced by the number of
/// coverage fights drawn and belongs to the caller's checkpoint.
pub fn draw(
    config: &BroadConfig,
    stats: &mut SamplerStats,
    rng: &mut Stream,
    salt: u64,
    ticks: i64,
    cursor: &mut u64,
) -> Vec<Task> {
    let pool = board();
    let covered = config.coverage_slots();
    let mut tasks = Vec::with_capacity(config.panel);
    for slot in 0..config.panel {
        let cell = if slot < covered {
            let cell = coverage_cell(salt, *cursor);
            *cursor += 1;
            cell
        } else {
            pick(stats, rng, &pool)
        };
        let swap = slot % 2 == 1;
        stats.issued += 1;
        tasks.push(Task {
            cell,
            swap,
            seed: episode_seed(
                StreamTag::Train,
                salt,
                cell.key(),
                swap as u64,
                stats.issued,
            ),
            ticks,
        });
    }
    tasks
}

/// Where a balanced evaluation's numbers came from. Reported so a cheap
/// readiness diagnostic can never be displayed as gate evidence.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Source {
    /// The gate's first held-out round.
    Audit,
    /// The disjoint round that must also pass.
    Confirm,
    /// The cheap periodic probe. Diagnostic only; it gates nothing.
    Ready,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Audit => "audit",
            Source::Confirm => "confirm",
            Source::Ready => "ready",
        }
    }

    pub fn parse(raw: &str) -> Option<Source> {
        match raw {
            "audit" => Some(Source::Audit),
            "confirm" => Some(Source::Confirm),
            "ready" => Some(Source::Ready),
            _ => None,
        }
    }

    pub fn of_round(round: Round) -> Source {
        match round {
            Round::Audit => Source::Audit,
            Round::Confirm => Source::Confirm,
        }
    }
}

/// One balanced evaluation of ONE frozen policy.
///
/// `wins` is always OUR policy's wins, on both sides of the split: `ours[i]` is
/// how it did WHILE PILOTING hull `i`, `theirs[i]` is how it did WHILE FACING
/// hull `i`. Neither is an enemy win count and neither is an inverse. Evidence
/// from two different champions is never pooled: a new champion opens a new
/// evaluation.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Evaluation {
    pub source: Source,
    pub champion: String,
    pub wins: u32,
    pub games: u32,
    pub ours: Vec<Tally>,
    pub theirs: Vec<Tally>,
}

impl Evaluation {
    pub fn open(source: Source, champion: String) -> Evaluation {
        Evaluation {
            source,
            champion,
            wins: 0,
            games: 0,
            ours: vec![Tally::default(); MELEE_SHIP_COUNT],
            theirs: vec![Tally::default(); MELEE_SHIP_COUNT],
        }
    }

    pub fn record(&mut self, cell: Cell, won: bool) {
        self.games += 1;
        self.wins += won as u32;
        for (slot, tally) in [
            (cell.our_ship().index(), &mut self.ours),
            (cell.their_ship().index(), &mut self.theirs),
        ] {
            if let Some(entry) = tally.get_mut(slot) {
                entry.games += 1;
                entry.wins += won as u32;
            }
        }
    }

    pub fn tally(&self) -> Tally {
        Tally {
            wins: self.wins,
            games: self.games,
        }
    }

    pub fn to_json(&self) -> Value {
        let list = |tallies: &[Tally]| -> Vec<Value> {
            tallies.iter().map(|t| json!([t.wins, t.games])).collect()
        };
        json!({"source": self.source.as_str(), "champion": self.champion,
               "wins": self.wins, "games": self.games,
               "ours": list(&self.ours), "theirs": list(&self.theirs)})
    }

    pub fn from_json(value: &Value) -> Option<Evaluation> {
        // Every count is converted and added with checked arithmetic. A cast
        // would let a count above `u32::MAX` wrap into a small plausible number
        // and a plain sum would let 25 large counts overflow into one, either
        // of which would turn a malformed document into a believable result.
        let count = |raw: Option<&Value>| -> Option<u32> {
            u32::try_from(raw?.as_u64()?).ok()
        };
        let list = |key: &str| -> Option<Vec<Tally>> {
            let rows = value.get(key)?.as_array()?;
            if rows.len() != MELEE_SHIP_COUNT {
                return None;
            }
            rows.iter()
                .map(|raw| {
                    let row = raw.as_array()?;
                    if row.len() != 2 {
                        return None;
                    }
                    let wins = count(row.first())?;
                    let games = count(row.get(1))?;
                    (wins <= games).then_some(Tally { wins, games })
                })
                .collect()
        };
        let wins = count(value.get("wins"))?;
        let games = count(value.get("games"))?;
        if wins > games {
            return None;
        }
        let evaluation = Evaluation {
            source: Source::parse(value.get("source")?.as_str()?)?,
            champion: value.get("champion")?.as_str()?.to_string(),
            wins,
            games,
            ours: list("ours")?,
            theirs: list("theirs")?,
        };
        // Each fight contributes to exactly one hull on each side, so the two
        // splits must both add up to the total. A document where they do not
        // describes something that never happened.
        (checked_sum(&evaluation.ours)? == (wins, games)
            && checked_sum(&evaluation.theirs)? == (wins, games))
        .then_some(evaluation)
    }
}

/// Totals a per-hull split, refusing to overflow rather than wrapping into a
/// number that would then agree with a forged aggregate.
pub fn checked_sum(tallies: &[Tally]) -> Option<(u32, u32)> {
    tallies.iter().try_fold((0u32, 0u32), |(wins, games), t| {
        Some((wins.checked_add(t.wins)?, games.checked_add(t.games)?))
    })
}

/// Rows for the dashboard's per-hull blind-spot table.
pub fn ship_rows(evaluation: &Evaluation) -> Vec<Value> {
    let row = |side: &str, ship: ShipKind, tally: Tally| {
        json!({"side": side, "ship": ship.name(), "wins": tally.wins, "games": tally.games,
               "win_rate": tally.rate(), "lower_bound": tally.lower_bound(),
               "source": evaluation.source.as_str()})
    };
    let mut rows = Vec::with_capacity(MELEE_SHIP_COUNT * 2);
    for (at, ship) in ALL_SHIPS.iter().enumerate() {
        rows.push(row("ours", *ship, evaluation.ours[at]));
    }
    for (at, ship) in ALL_SHIPS.iter().enumerate() {
        rows.push(row("opponent", *ship, evaluation.theirs[at]));
    }
    rows
}

fn trial(attempt: u64, games: usize, slot: usize) -> u64 {
    TRIAL_BASE
        | (attempt
            .wrapping_mul(games as u64)
            .wrapping_add(slot as u64)
            % TRIAL_BASE)
}

/// A fixed balanced panel of ordered pairs, each played in BOTH seats.
///
/// `pairs / 25` independent random perfect matchings are laid between the two
/// rosters, so each hull appears exactly `pairs / 25` times on each side and
/// the pairings themselves are randomised rather than enumerated: the panel
/// covers the distribution without having to visit all 625 cells. The seat
/// duplicate is what stops a seat advantage flattering or punishing the
/// aggregate.
///
/// Seeds come from `stream`, which is the AUDIT or CONFIRM partition, at trial
/// indices that only broad rounds ever use.
pub fn balanced_panel(
    stream: StreamTag,
    salt: u64,
    attempt: u64,
    pairs: usize,
    ticks: i64,
) -> Vec<Task> {
    let rounds = pairs / MELEE_SHIP_COUNT;
    let games = pairs * 2;
    let mut rng = Stream::seeded(
        salt ^ attempt.wrapping_mul(0x27d4_eb2f_1656_67c5)
            ^ (stream.residue() + 1).wrapping_mul(0xff51_afd7_ed55_8ccd),
    );
    let mut tasks = Vec::with_capacity(games);
    for _ in 0..rounds {
        let ours = shuffled(&mut rng);
        let theirs = shuffled(&mut rng);
        for lane in 0..MELEE_SHIP_COUNT {
            let cell = Cell {
                foe: Opponent::Cyborg,
                us: ours[lane],
                them: theirs[lane],
            };
            for swap in [false, true] {
                let slot = tasks.len();
                tasks.push(Task {
                    cell,
                    swap,
                    seed: episode_seed(
                        stream,
                        salt,
                        cell.key(),
                        swap as u64,
                        trial(attempt, games, slot),
                    ),
                    ticks,
                });
            }
        }
    }
    tasks
}

/// The cheap periodic probe: a balanced panel on the READY stream, sized to
/// roughly `games` fights. Diagnostic only. It decides whether an expensive
/// held-out round is worth opening and is never evidence for one.
pub fn readiness_panel(salt: u64, attempt: u64, games: usize, ticks: i64) -> Vec<Task> {
    let pairs = (games / 2 / MELEE_SHIP_COUNT).max(1) * MELEE_SHIP_COUNT;
    balanced_panel(StreamTag::Ready, salt, attempt, pairs, ticks)
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Progress {
    Running,
    Passed,
    Failed,
}

/// One held-out round against one frozen champion.
#[derive(Clone, Debug)]
pub struct Overall {
    pub attempt: u64,
    pub round: Round,
    pub target: f64,
    pub tasks: Vec<Task>,
    pub cursor: usize,
    pub evaluation: Evaluation,
}

impl Overall {
    pub fn open(
        attempt: u64,
        round: Round,
        target: f64,
        champion: String,
        tasks: Vec<Task>,
    ) -> Overall {
        Overall {
            attempt,
            round,
            target,
            cursor: 0,
            evaluation: Evaluation::open(Source::of_round(round), champion),
            tasks,
        }
    }

    pub fn next_task(&self) -> Option<Task> {
        self.tasks.get(self.cursor).copied()
    }

    pub fn record(&mut self, won: bool) {
        let Some(task) = self.next_task() else {
            return;
        };
        self.evaluation.record(task.cell, won);
        self.cursor += 1;
    }

    /// The whole panel is predeclared and played to the end unless the result
    /// is already arithmetically settled, so the bound is never inflated by
    /// stopping when the numbers happen to look good. The only early exit is
    /// downward: once winning every remaining game could not clear the bound,
    /// nothing is learned by playing them.
    pub fn progress(&self) -> Progress {
        let total = self.tasks.len() as u32;
        let remaining = total - self.evaluation.games.min(total);
        let best_case = wilson_lower(self.evaluation.wins + remaining, total);
        if best_case.is_some_and(|bound| bound <= self.target) {
            return Progress::Failed;
        }
        if self.cursor < self.tasks.len() {
            return Progress::Running;
        }
        if self
            .evaluation
            .tally()
            .lower_bound()
            .is_some_and(|bound| bound > self.target)
        {
            Progress::Passed
        } else {
            Progress::Failed
        }
    }

    /// The stream partition this round's seeds are withheld in.
    pub fn stream(round: Round) -> StreamTag {
        match round {
            Round::Audit => StreamTag::Audit,
            Round::Confirm => StreamTag::Confirm,
        }
    }

    /// A round records the panel it declares rather than the panel it plays:
    /// the round, attempt and pair count, from which the task list is REBUILT
    /// on decode. A stored task list could be edited into a friendlier set of
    /// fights and still be self-consistent; one that has to reproduce
    /// [`balanced_panel`] from the declared parameters cannot.
    pub fn to_json(&self) -> Value {
        json!({"attempt": self.attempt, "round": self.round.as_str(), "target": self.target,
               "pairs": self.tasks.len() / 2, "cursor": self.cursor,
               "evaluation": self.evaluation.to_json()})
    }

    pub fn from_json(value: &Value, salt: u64, ticks: i64) -> Option<Overall> {
        let round = Round::parse(value.get("round")?.as_str()?)?;
        let attempt = value.get("attempt")?.as_u64()?;
        let pairs = value
            .get("pairs")?
            .as_u64()
            .filter(|p| *p > 0 && *p % MELEE_SHIP_COUNT as u64 == 0)? as usize;
        let evaluation = Evaluation::from_json(value.get("evaluation")?)?;
        // The source is part of what the numbers mean, so it has to be the
        // source this round actually is, not whatever the file says.
        if evaluation.source != Source::of_round(round) {
            return None;
        }
        let tasks = balanced_panel(Overall::stream(round), salt, attempt, pairs, ticks);
        let cursor = value.get("cursor")?.as_u64()? as usize;
        // A cursor and a game count that disagree would resume a round that
        // never happened.
        if cursor > tasks.len() || evaluation.games as usize != cursor {
            return None;
        }
        Some(Overall {
            attempt,
            round,
            target: value
                .get("target")?
                .as_f64()
                .filter(|t| (0.0..1.0).contains(t))?,
            cursor,
            evaluation,
            tasks,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::{BTreeMap, BTreeSet};

    #[test]
    fn the_coverage_rotation_is_balanced_per_aligned_block_and_exhausts_a_tour() {
        for salt in [1u64, 7, 0xdead_beef] {
            // Every ALIGNED block of 25 uses each hull once on each side. No
            // claim is made about a window straddling a block boundary.
            for block in 0..40u64 {
                let mut ours = BTreeSet::new();
                let mut theirs = BTreeSet::new();
                for lane in 0..MELEE_SHIP_COUNT as u64 {
                    let cell = coverage_cell(salt, block * 25 + lane);
                    ours.insert(cell.us);
                    theirs.insert(cell.them);
                }
                assert_eq!(ours.len(), MELEE_SHIP_COUNT, "block {block} repeated our hull");
                assert_eq!(theirs.len(), MELEE_SHIP_COUNT, "block {block} repeated theirs");
            }
            // And a full tour visits every ordered pair exactly once.
            let tour: BTreeSet<(u8, u8)> = (0..BOARD as u64)
                .map(|at| {
                    let cell = coverage_cell(salt, at);
                    (cell.us, cell.them)
                })
                .collect();
            assert_eq!(tour.len(), BOARD, "a tour missed a matchup");
            // Consecutive tours are different schedules, not a repeat.
            let second: Vec<(u8, u8)> = (0..25u64)
                .map(|at| {
                    let cell = coverage_cell(salt, BOARD as u64 + at);
                    (cell.us, cell.them)
                })
                .collect();
            let first: Vec<(u8, u8)> = (0..25u64)
                .map(|at| {
                    let cell = coverage_cell(salt, at);
                    (cell.us, cell.them)
                })
                .collect();
            assert_ne!(first, second);
        }
    }

    fn stat(wins: f64, games: f64) -> CellStat {
        CellStat { wins, games }
    }

    #[test]
    fn the_adaptive_weight_is_bounded_and_abandons_neither_end() {
        // The ceiling both bounded terms can reach at once, which is what
        // makes the draw a bounded preference rather than a takeover.
        let ceiling = REHEARSAL_FLOOR + UNCERTAINTY_WEIGHT + POTENTIAL_WEIGHT;
        let unseen = weight(&stat(0.0, 0.0));
        let hopeless = weight(&stat(1.0, 200.0));
        let mastered = weight(&stat(199.0, 200.0));
        let contested = weight(&stat(100.0, 200.0));
        for w in [unseen, hopeless, mastered, contested] {
            assert!(w >= REHEARSAL_FLOOR, "a cell fell below the rehearsal floor");
            assert!(w <= ceiling + 1e-9, "a cell's weight was unbounded");
        }
        // A cell being lost almost always must NOT out-draw a contested one:
        // that is the "grind a hopeless cell forever" failure this replaces.
        assert!(contested > hopeless * 2.0);
        // A mastered cell and a hopeless cell are both cheap, for the same
        // reason: neither is where the policy can still move.
        assert!((hopeless - mastered).abs() < 0.5);
        // And a cell nobody has played yet is the most attractive of all.
        assert!(unseen > contested);
    }

    #[test]
    fn a_training_panel_is_balanced_over_generations_and_covers_both_seats() {
        let config = BroadConfig::default();
        let mut stats = SamplerStats::default();
        let mut rng = Stream::seeded(4);
        let mut cursor = 0u64;
        let mut seen: BTreeSet<i64> = BTreeSet::new();
        let mut ours: BTreeMap<u8, usize> = BTreeMap::new();
        let mut seats = (0usize, 0usize);
        // Forty generations of sixteen coverage fights is 640: one full tour
        // and a little more, so coverage alone must have visited every cell.
        let mut covered: BTreeSet<(u8, u8)> = BTreeSet::new();
        for _ in 0..40 {
            let tasks = draw(&config, &mut stats, &mut rng, 21, 3600, &mut cursor);
            assert_eq!(tasks.len(), config.panel);
            for (at, task) in tasks.iter().enumerate() {
                assert!(seen.insert(task.seed), "a training seed was reused");
                if at < config.coverage_slots() {
                    covered.insert((task.cell.us, task.cell.them));
                }
                *ours.entry(task.cell.us).or_default() += 1;
                if task.swap {
                    seats.1 += 1;
                } else {
                    seats.0 += 1;
                }
            }
        }
        assert_eq!(cursor, 40 * config.coverage_slots() as u64);
        assert_eq!(covered.len(), BOARD, "coverage did not span the board");
        assert!(seats.0 > 0 && seats.1 > 0, "a seat was never played");
        assert_eq!(ours.len(), MELEE_SHIP_COUNT, "a hull was never piloted");
    }

    #[test]
    fn a_held_out_round_represents_every_hull_equally_on_both_sides() {
        let config = BroadConfig::default();
        let tasks = balanced_panel(StreamTag::Audit, 5, 0, config.pairs, 3600);
        assert_eq!(tasks.len(), 1000);
        let mut ours = [0usize; MELEE_SHIP_COUNT];
        let mut theirs = [0usize; MELEE_SHIP_COUNT];
        let mut seats = (0usize, 0usize);
        for task in &tasks {
            ours[task.cell.us as usize] += 1;
            theirs[task.cell.them as usize] += 1;
            if task.swap {
                seats.1 += 1;
            } else {
                seats.0 += 1;
            }
        }
        // 500 pairs over 25 hulls, each pair played twice.
        assert!(ours.iter().all(|n| *n == 40), "our hulls were not balanced");
        assert!(theirs.iter().all(|n| *n == 40), "their hulls were not balanced");
        assert_eq!(seats, (500, 500), "the two seats were not played equally");
        // Pairings are RANDOM matchings, so a pair may be drawn more than once
        // across the twenty of them. What must hold is that whenever a pair is
        // drawn it is played in both seats the same number of times, which is
        // what stops a seat advantage leaking into the aggregate.
        let mut seated: BTreeMap<(u8, u8), (usize, usize)> = BTreeMap::new();
        for task in &tasks {
            let entry = seated.entry((task.cell.us, task.cell.them)).or_default();
            if task.swap {
                entry.1 += 1;
            } else {
                entry.0 += 1;
            }
        }
        assert!(
            seated.values().all(|(bottom, top)| bottom == top),
            "a pair was played more often in one seat than the other"
        );
        // The panel is a sample of the distribution, not an enumeration of it.
        assert!(seated.len() < BOARD, "the panel enumerated the whole board");
    }

    /// Across streams this is a guarantee of the seed partitioning. WITHIN a
    /// stream it is only a property of these particular fixed salts and
    /// attempts, because `episode_seed` hashes into a finite pool; the
    /// assertions that compare two panels from the same stream are checks on
    /// these fixtures, not proofs.
    #[test]
    fn held_out_seeds_are_withheld_from_training_and_from_each_other() {
        let config = BroadConfig::default();
        let audit: BTreeSet<i64> =
            balanced_panel(StreamTag::Audit, 3, 0, config.pairs, 3600)
                .iter()
                .map(|t| t.seed)
                .collect();
        let confirm: BTreeSet<i64> =
            balanced_panel(StreamTag::Confirm, 3, 0, config.pairs, 3600)
                .iter()
                .map(|t| t.seed)
                .collect();
        let ready: BTreeSet<i64> = readiness_panel(3, 0, 250, 3600)
            .iter()
            .map(|t| t.seed)
            .collect();
        assert_eq!(audit.len(), 1000);
        assert_eq!(confirm.len(), 1000);
        assert_eq!(ready.len(), 250);
        assert!(audit.is_disjoint(&confirm));
        assert!(audit.is_disjoint(&ready));
        assert!(confirm.is_disjoint(&ready));

        let mut stats = SamplerStats::default();
        let mut rng = Stream::seeded(2);
        let mut cursor = 0;
        let mut train: BTreeSet<i64> = BTreeSet::new();
        for _ in 0..200 {
            train.extend(
                draw(&config, &mut stats, &mut rng, 3, 3600, &mut cursor)
                    .iter()
                    .map(|t| t.seed),
            );
        }
        // These three ARE guaranteed: the streams own disjoint residue classes.
        assert!(train.is_disjoint(&audit));
        assert!(train.is_disjoint(&confirm));
        assert!(train.is_disjoint(&ready));

        // A later attempt is a fresh panel rather than a replay of the first.
        // Same stream, so this is a fixture check, not a proof.
        let again: BTreeSet<i64> = balanced_panel(StreamTag::Audit, 3, 1, config.pairs, 3600)
            .iter()
            .map(|t| t.seed)
            .collect();
        assert!(again.is_disjoint(&audit));
    }

    #[test]
    fn the_held_out_trial_namespace_is_separate_from_every_plain_counter() {
        // `stats.issued`, the only other index any caller forms, is a count of
        // fights actually played. It cannot reach the top bit.
        for issued in [0u64, 1, 1_000, 1_000_000, 1_000_000_000_000] {
            assert!(issued < TRIAL_BASE, "a training index reached the gate space");
        }
        for attempt in [0u64, 1, 9_999, u64::MAX] {
            for slot in [0usize, 1, 999] {
                assert!(trial(attempt, 1000, slot) >= TRIAL_BASE);
            }
        }
        // Separate INDICES, which is all this buys. The seeds they hash to live
        // in the same finite partition and are not provably distinct; that is
        // exactly why audit, confirm, readiness and training use four different
        // streams rather than four index ranges of one.
    }

    fn round(target: f64, pairs: usize) -> Overall {
        Overall::open(
            0,
            Round::Audit,
            target,
            "btest".into(),
            balanced_panel(StreamTag::Audit, 1, 0, pairs, 3600),
        )
    }

    #[test]
    fn the_aggregate_gate_needs_more_than_the_bare_target_rate() {
        // Exactly the target rate can never clear a lower bound ABOVE it, at
        // any panel size, so the arithmetic settles it early and the round is
        // abandoned rather than played out. That early exit is downward only.
        let mut gate = round(0.80, 50);
        let mut played = 0;
        while gate.progress() == Progress::Running {
            gate.record(played % 5 != 4);
            played += 1;
        }
        assert_eq!(gate.progress(), Progress::Failed);
        assert!(gate.evaluation.games < 100, "a settled round kept playing");
        assert!(
            gate.evaluation.tally().rate().unwrap() <= 0.81,
            "the observed rate was never near the target"
        );

        // Over the real 1000-game panel, 84% does clear it and 82% does not.
        for (rate, expected) in [(84u32, Progress::Passed), (82, Progress::Failed)] {
            let mut gate = round(0.80, 500);
            let mut at = 0u32;
            while gate.progress() == Progress::Running {
                gate.record(at % 100 < rate);
                at += 1;
            }
            assert_eq!(gate.progress(), expected, "{rate}% was judged wrongly");
        }
    }

    #[test]
    fn a_hopeless_candidate_is_abandoned_without_playing_the_whole_panel() {
        let mut gate = round(0.80, 500);
        while gate.progress() == Progress::Running {
            gate.record(false);
        }
        assert_eq!(gate.progress(), Progress::Failed);
        assert!(
            gate.evaluation.games < gate.tasks.len() as u32,
            "played all {} games on a hopeless candidate",
            gate.tasks.len()
        );
        // Nothing is lost by the early exit: the panel was already decided.
        assert!(gate.evaluation.games > 0);
    }

    #[test]
    fn per_hull_splits_always_add_up_to_the_aggregate() {
        let mut gate = round(0.80, 500);
        let mut at = 0u32;
        while gate.progress() == Progress::Running {
            gate.record(at % 3 != 0);
            at += 1;
        }
        let evaluation = &gate.evaluation;
        let sum = |tallies: &[Tally]| -> (u32, u32) {
            tallies.iter().fold((0, 0), |(w, g), t| (w + t.wins, g + t.games))
        };
        assert_eq!(sum(&evaluation.ours), (evaluation.wins, evaluation.games));
        assert_eq!(sum(&evaluation.theirs), (evaluation.wins, evaluation.games));
        // Fifty rows, every one carrying its own sample count and its source.
        let rows = ship_rows(evaluation);
        assert_eq!(rows.len(), 50);
        assert!(rows.iter().all(|r| r["source"] == "audit"));
        assert_eq!(rows.iter().filter(|r| r["side"] == "ours").count(), 25);
    }

    #[test]
    fn an_evaluation_with_splits_that_do_not_add_up_is_refused() {
        let mut gate = round(0.80, 25);
        for _ in 0..20 {
            gate.record(true);
        }
        let saved = gate.evaluation.to_json();
        assert_eq!(
            Evaluation::from_json(&saved).as_ref(),
            Some(&gate.evaluation)
        );
        let mut tampered = saved.clone();
        tampered["wins"] = json!(50);
        assert!(Evaluation::from_json(&tampered).is_none());
        let mut tampered = saved.clone();
        tampered["ours"][0] = json!([9, 3]);
        assert!(Evaluation::from_json(&tampered).is_none());
        // A count above u32 must be refused, not wrapped into a small one.
        let mut tampered = saved.clone();
        tampered["wins"] = json!(u64::MAX);
        assert!(Evaluation::from_json(&tampered).is_none());
        let mut tampered = saved.clone();
        tampered["games"] = json!(4_294_967_296u64);
        assert!(Evaluation::from_json(&tampered).is_none());
        // And a split that would only add up by overflowing must be refused.
        let mut tampered = saved.clone();
        tampered["wins"] = json!(20);
        tampered["games"] = json!(20);
        for at in 0..MELEE_SHIP_COUNT {
            tampered["ours"][at] = json!([u32::MAX, u32::MAX]);
        }
        assert!(Evaluation::from_json(&tampered).is_none());
    }

    #[test]
    fn a_round_survives_a_checkpoint_round_trip_and_refuses_a_redescribed_panel() {
        let mut gate = round(0.80, 25);
        for at in 0..17 {
            gate.record(at % 2 == 0);
        }
        let saved = gate.to_json();
        let restored = Overall::from_json(&saved, 1, 3600).expect("round trip");
        assert_eq!(restored.to_json(), saved);
        // The panel itself was rebuilt from the declared parameters, so this
        // is the real check: the same fights, in the same order.
        assert_eq!(restored.tasks, gate.tasks);
        assert_eq!(restored.next_task(), gate.next_task());
        assert_eq!(restored.cursor, 17);

        // A different salt describes a different panel, so the same document
        // cannot be replayed into another run.
        let foreign = Overall::from_json(&saved, 2, 3600).expect("decodes");
        assert_ne!(foreign.tasks, gate.tasks);

        let mut tampered = saved.clone();
        tampered["cursor"] = json!(3);
        assert!(Overall::from_json(&tampered, 1, 3600).is_none());
        let mut tampered = saved.clone();
        tampered["round"] = json!("sweep");
        assert!(Overall::from_json(&tampered, 1, 3600).is_none());
        // Round and source must describe the same measurement.
        let mut tampered = saved.clone();
        tampered["round"] = json!("confirm");
        assert!(Overall::from_json(&tampered, 1, 3600).is_none());
        let mut tampered = saved.clone();
        tampered["pairs"] = json!(26);
        assert!(Overall::from_json(&tampered, 1, 3600).is_none());
    }

    #[test]
    fn broad_settings_reject_a_panel_that_could_not_be_balanced() {
        let config = BroadConfig::default();
        assert_eq!(BroadConfig::from_json(&config.to_json()), Some(config));
        assert_eq!(config.games(), 1000);
        assert_eq!(config.coverage_slots(), 16);
        let mut bad = config.to_json();
        bad["pairs"] = json!(501);
        assert!(BroadConfig::from_json(&bad).is_none());
        let mut bad = config.to_json();
        bad["panel"] = json!(0);
        assert!(BroadConfig::from_json(&bad).is_none());
        let mut bad = config.to_json();
        bad["coverage"] = json!(1.5);
        assert!(BroadConfig::from_json(&bad).is_none());
        let mut bad = config.to_json();
        bad["target"] = json!(1.0);
        assert!(BroadConfig::from_json(&bad).is_none());
        // A memory that never forgets, or one that grows without bound, is not
        // a decay this can honour.
        for impossible in [json!(1.5), json!(-0.1)] {
            let mut bad = config.to_json();
            bad["decay"] = impossible;
            assert!(BroadConfig::from_json(&bad).is_none());
        }
    }

    #[test]
    fn the_board_is_every_ordered_pair_and_a_cell_round_trips() {
        let board = board();
        assert_eq!(board.len(), BOARD);
        let mut keys = BTreeSet::new();
        for cell in &board {
            assert!(keys.insert(cell.key()), "key collision at {cell:?}");
            assert_eq!(Cell::decode(&cell.encode()), Some(*cell));
        }
        assert_eq!(keys.len(), BOARD);
        // Cell indices are ALL_SHIPS indices, which is the same five-bit hull
        // identifier the policy network reads.
        assert_eq!(board[0].our_ship(), ALL_SHIPS[0]);
        assert_eq!(board[0].our_ship().index(), 0);
        assert_eq!(board[BOARD - 1].their_ship(), ALL_SHIPS[MELEE_SHIP_COUNT - 1]);
    }

    #[test]
    fn decoding_rejects_shapes_that_could_resume_the_wrong_matchup() {
        let first = Cell {
            foe: Opponent::Cyborg,
            us: 0,
            them: 0,
        };
        assert_eq!(Cell::decode(&json!(["cyborg", 0, 0])), Some(first));
        // Out of range, so `ALL_SHIPS[index]` can never be reached with it.
        assert_eq!(Cell::decode(&json!(["cyborg", 25, 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", 0, 25])), None);
        // 256 must not wrap to hull zero.
        assert_eq!(Cell::decode(&json!(["cyborg", 256, 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", -1, 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", 0, 0, 0])), None);
        assert_eq!(Cell::decode(&json!(["model", 0, 0])), None);
        assert_eq!(Cell::decode(&json!({"us": 0})), None);
    }
}
