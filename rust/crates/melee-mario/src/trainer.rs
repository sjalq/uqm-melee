//! The training state machine.
//!
//! Work is done in small units so that a pause, a stop, a checkpoint or an API
//! request never has to wait for a whole generation. Every unit is a pure
//! function of the checkpointed state, so stopping and resuming reproduces the
//! same trajectory as running straight through, and a process killed mid-batch
//! simply replays that batch deterministically.
//!
//! Three rules run through the whole file:
//!
//!   * Fitness numbers are comparable only inside one panel. Champion
//!     replacement rescores the incumbent on the challenger's own panel.
//!   * Gate evidence belongs to one candidate fingerprint, one stage and one
//!     opponent revision. Any change throws it away rather than pooling it.
//!   * The frozen self-play opponent changes only at a recorded champion
//!     promotion, never inside a generation or an audit.

use crate::audit::{AuditConfig, Gate, Progress, Round, Tally};
use crate::curriculum::{self, Cell, Opponent};
use crate::episode::{self, Rival, Task};
use crate::genome::Genome;
use crate::graph::Network;
use crate::neat::{NeatConfig, Population};
use crate::rng::{episode_seed, Stream, StreamTag};
use crate::sampler::{self, Panel, SamplerConfig, SamplerStats};
use melee_sim::input::CyborgRating;
use serde_json::{json, Value};
use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;

pub const ENGINE_VERSION: &str = "melee-mario/1";
const MAX_HISTORY: usize = 4000;
const MAX_EVENTS: usize = 200;

#[derive(Clone, Debug)]
pub struct Config {
    pub run_id: String,
    pub salt: u64,
    pub ticks: i64,
    pub rating: CyborgRating,
    pub neat: NeatConfig,
    pub sampler: SamplerConfig,
    pub audit: AuditConfig,
    /// Fraction of wall time the evaluator is allowed to compute.
    pub duty: f64,
    pub readiness_games: usize,
    pub readiness_threshold: f64,
    pub readiness_period: u32,
}

impl Config {
    pub fn to_json(&self) -> Value {
        json!({"version": ENGINE_VERSION, "run_id": self.run_id, "salt": self.salt.to_string(),
               "ticks": self.ticks, "rating": rating_name(self.rating),
               "neat": self.neat.to_json(), "sampler": self.sampler.to_json(),
               "audit": self.audit.to_json(), "duty": self.duty,
               "readiness_games": self.readiness_games,
               "readiness_threshold": self.readiness_threshold,
               "readiness_period": self.readiness_period})
    }

    /// Rejects a configuration document from a different engine version or with
    /// values the trainer cannot honour, rather than clamping into something
    /// the operator did not ask for.
    pub fn from_json(value: &Value) -> Option<Config> {
        if value.get("version")?.as_str()? != ENGINE_VERSION {
            return None;
        }
        let ticks = value.get("ticks")?.as_i64().filter(|t| *t > 0)?;
        let duty = value.get("duty")?.as_f64().filter(|d| *d > 0.0 && *d <= 1.0)?;
        let threshold = value
            .get("readiness_threshold")?
            .as_f64()
            .filter(|t| (0.0..=1.0).contains(t))?;
        Some(Config {
            run_id: value.get("run_id")?.as_str()?.to_string(),
            salt: value.get("salt")?.as_str()?.parse().ok()?,
            ticks,
            rating: parse_rating(value.get("rating")?.as_str()?)?,
            neat: NeatConfig::from_json(value.get("neat")?)?,
            sampler: SamplerConfig::from_json(value.get("sampler")?)?,
            audit: AuditConfig::from_json(value.get("audit")?)?,
            duty,
            readiness_games: value
                .get("readiness_games")?
                .as_u64()
                .filter(|g| *g > 0)? as usize,
            readiness_threshold: threshold,
            readiness_period: value.get("readiness_period")?.as_u64()?.max(1) as u32,
        })
    }
}

/// Hash of the running executable. Read once; a rebuild of any crate in the
/// workspace changes the bytes and therefore this value.
pub fn build_fingerprint() -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in ENGINE_VERSION.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    if let Ok(path) = std::env::current_exe() {
        if let Ok(bytes) = std::fs::read(path) {
            for chunk in bytes.chunks(8) {
                let mut word = 0u64;
                for (at, byte) in chunk.iter().enumerate() {
                    word |= (*byte as u64) << (at * 8);
                }
                hash ^= word;
                hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
            }
        }
    }
    format!("b{hash:016x}")
}

pub fn rating_name(rating: CyborgRating) -> &'static str {
    match rating {
        CyborgRating::StandardCyborg => "standard",
        CyborgRating::GoodCyborg => "good",
        CyborgRating::AwesomeCyborg => "awesome",
    }
}

pub fn parse_rating(raw: &str) -> Option<CyborgRating> {
    match raw {
        "standard" => Some(CyborgRating::StandardCyborg),
        "good" => Some(CyborgRating::GoodCyborg),
        "awesome" => Some(CyborgRating::AwesomeCyborg),
        _ => None,
    }
}

/// Where the curriculum is. The ladder is graded; the mixed phase is not.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Ladder {
    /// Climbing the cyborg stages. A stage promotion needs a full gate.
    Climbing,
    /// Every cyborg matchup has been gated. Training now mixes the Awesome
    /// cyborg distribution with a frozen champion snapshot and runs
    /// indefinitely; beating a copy of yourself is not a mastery criterion.
    Mixed,
}

impl Ladder {
    pub fn as_str(self) -> &'static str {
        match self {
            Ladder::Climbing => "climbing",
            Ladder::Mixed => "mixed",
        }
    }

    pub fn parse(raw: &str) -> Option<Ladder> {
        match raw {
            "climbing" => Some(Ladder::Climbing),
            "mixed" => Some(Ladder::Mixed),
            _ => None,
        }
    }
}

/// The one piece of work the trainer is currently doing.
#[derive(Clone, Debug)]
pub enum Mode {
    Training,
    /// A cheap fixed probe on its own seed stream, used only to decide whether
    /// an expensive audit is worth opening. It is not evidence for promotion.
    Probing {
        attempt: u64,
        champion: String,
        tasks: Vec<Task>,
        cursor: usize,
        wins: u32,
    },
    Auditing {
        gate: Gate,
    },
}

#[derive(Clone, Debug)]
pub struct HistoryRow {
    pub generation: u32,
    pub stage: usize,
    pub training_win_rate: Option<f64>,
    pub validation_win_rate: Option<f64>,
    pub species: usize,
    pub nodes: usize,
    pub episodes: u64,
}

#[derive(Clone, Debug)]
pub struct Event {
    pub at: String,
    pub message: String,
}

pub struct Trainer {
    pub config: Config,
    /// Fingerprint of the executable that produced this state. A rebuild
    /// changes it, and a changed evaluator may not silently continue someone
    /// else's trajectory: the operator has to say so explicitly.
    pub evaluator: String,
    pub evolution: Stream,
    pub sampling: Stream,
    pub population: Population,
    pub stage: usize,
    pub ladder: Ladder,
    /// Bumped only when the frozen self-play opponent is replaced, at a
    /// recorded champion promotion. Audit evidence is versioned by it.
    pub opponent_revision: u32,
    pub frozen_opponent: Option<Genome>,
    pub champion: Option<Genome>,
    /// Confirmed audit evidence for the current champion at the current stage.
    pub evidence: BTreeMap<Cell, Tally>,
    /// Cells that failed the most recent gate attempt; audited first next time.
    pub priority: Vec<Cell>,
    pub stats: SamplerStats,
    pub panel: Option<Panel>,
    pub mode: Mode,
    pub episodes: u64,
    /// Wall-clock seconds spent inside the run loop, work and governor rest
    /// together, accumulated across every resume.
    pub elapsed: f64,
    /// Of those, the seconds actually spent simulating. The ratio is the
    /// MEASURED duty cycle, which is what the dashboard shows next to the cap.
    pub compute: f64,
    pub audit_attempt: u64,
    pub last_validation: Option<f64>,
    /// The champion's win rate on the panel currently being evaluated. Derived
    /// from the live panel, so it is rebuilt rather than restored.
    pub last_training_wins: Option<f64>,
    pub history: VecDeque<HistoryRow>,
    pub events: VecDeque<Event>,
    pub saved_at: Option<String>,
    /// Compiled graphs are cached here for the length of a panel so the
    /// strongly-connected-component pass is paid once per genome, not once per
    /// fight.
    pub(crate) cache: Option<(String, Arc<Network>)>,
    pub(crate) opponent_cache: Option<(String, Arc<Network>)>,
}

/// What one unit of work accomplished, so the caller can pace itself.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Unit {
    pub episodes: u64,
    /// A generation, probe or gate round finished, so this is a safe point to
    /// write a checkpoint.
    pub boundary: bool,
}

impl Trainer {
    pub fn fresh(config: Config) -> Trainer {
        let mut evolution = Stream::seeded(config.salt ^ 0xe0_1u64);
        let sampling = Stream::seeded(config.salt ^ 0x5a_2u64);
        let population = Population::seed(config.neat, &mut evolution);
        let mut trainer = Trainer {
            config,
            evaluator: build_fingerprint(),
            evolution,
            sampling,
            population,
            stage: 0,
            ladder: Ladder::Climbing,
            opponent_revision: 0,
            frozen_opponent: None,
            champion: None,
            evidence: BTreeMap::new(),
            priority: Vec::new(),
            stats: SamplerStats::default(),
            panel: None,
            mode: Mode::Training,
            episodes: 0,
            elapsed: 0.0,
            compute: 0.0,
            audit_attempt: 0,
            last_validation: None,
            last_training_wins: None,
            history: VecDeque::new(),
            events: VecDeque::new(),
            saved_at: None,
            cache: None,
            opponent_cache: None,
        };
        trainer.note(format!(
            "run {} seeded: population {}, stage 0, {} vs {}",
            trainer.config.run_id,
            trainer.config.neat.population,
            curriculum::ours()[0].name(),
            curriculum::theirs()[0].name()
        ));
        trainer
    }

    pub fn note(&mut self, message: String) {
        self.events.push_back(Event {
            at: now(),
            message,
        });
        while self.events.len() > MAX_EVENTS {
            self.events.pop_front();
        }
    }

    /// Cyborg cells of the current stage.
    pub fn cyborg_cells(&self) -> Vec<Cell> {
        curriculum::cells(self.stage)
    }

    /// Frozen-model cells, empty until the ladder has been fully gated.
    pub fn model_cells(&self) -> Vec<Cell> {
        if self.ladder == Ladder::Mixed && self.frozen_opponent.is_some() {
            curriculum::model_cells()
        } else {
            Vec::new()
        }
    }

    fn compiled(&mut self, genome: &Genome) -> Arc<Network> {
        let fingerprint = genome.fingerprint();
        if let Some((cached, network)) = &self.cache {
            if *cached == fingerprint {
                return network.clone();
            }
        }
        let network = Arc::new(Network::compile(genome));
        self.cache = Some((fingerprint, network.clone()));
        network
    }

    fn compiled_opponent(&mut self) -> Option<Arc<Network>> {
        let genome = self.frozen_opponent.clone()?;
        let fingerprint = genome.fingerprint();
        if let Some((cached, network)) = &self.opponent_cache {
            if *cached == fingerprint {
                return Some(network.clone());
            }
        }
        let network = Arc::new(Network::compile(&genome));
        self.opponent_cache = Some((fingerprint, network.clone()));
        Some(network)
    }

    fn play(&mut self, task: &Task, network: &Arc<Network>) -> episode::Outcome {
        let outcome = match task.cell.foe {
            Opponent::Cyborg => episode::run(task, network, Rival::Cyborg(self.config.rating)),
            Opponent::Model => match self.compiled_opponent() {
                Some(theirs) => episode::run(task, network, Rival::Model(&theirs)),
                // No snapshot yet: fall back to the graded opponent rather than
                // inventing an opponent the evidence would not describe.
                None => episode::run(task, network, Rival::Cyborg(self.config.rating)),
            },
        };
        self.episodes += 1;
        outcome
    }

    /// One bounded unit of work.
    pub fn step(&mut self) -> Unit {
        match std::mem::replace(&mut self.mode, Mode::Training) {
            Mode::Training => self.step_training(),
            Mode::Probing {
                attempt,
                champion,
                tasks,
                cursor,
                wins,
            } => self.step_probe(attempt, champion, tasks, cursor, wins),
            Mode::Auditing { gate } => self.step_audit(gate),
        }
    }

    fn step_training(&mut self) -> Unit {
        self.mode = Mode::Training;
        if self.panel.is_none() {
            self.open_panel();
        }
        let ticks = self.config.ticks;
        let panel = self.panel.clone().expect("panel opened above");
        let order: Vec<Genome> = self
            .population
            .members()
            .map(|m| m.genome.clone())
            .collect();
        if panel.cursor >= order.len() {
            return self.close_panel();
        }
        let genome = order[panel.cursor].clone();
        let fingerprint = genome.fingerprint();
        let network = self.compiled(&genome);
        let champion = self.champion.as_ref().map(Genome::fingerprint);
        // Sampler evidence follows the champion, because the sampler's job is
        // to find where the policy we actually gate on is still weak. Before a
        // champion exists the first member stands in for it.
        let record = champion.map_or(panel.cursor == 0, |c| c == fingerprint);
        let mut total = 0.0;
        let mut wins = 0u32;
        for task in &panel.tasks {
            let outcome = self.play(task, &network);
            total += outcome.fitness(ticks);
            wins += outcome.won as u32;
            if record {
                self.stats
                    .record(task.cell, outcome.won, self.config.sampler.decay);
            }
        }
        let fitness = total / panel.tasks.len().max(1) as f64;
        if let Some(member) = self
            .population
            .members_mut()
            .nth(panel.cursor)
        {
            member.fitness = Some(fitness);
        }
        if record {
            self.last_training_wins = Some(wins as f64 / panel.tasks.len().max(1) as f64);
        }
        if let Some(live) = self.panel.as_mut() {
            live.cursor += 1;
        }
        Unit {
            episodes: panel.tasks.len() as u64,
            boundary: false,
        }
    }

    fn open_panel(&mut self) {
        if let Some(champion) = self.champion.clone() {
            self.population.ensure_elite(&champion);
        }
        self.population.open_panel();
        let cyborg = self.cyborg_cells();
        let model = self.model_cells();
        let generation = self.population.generation;
        self.stats.admit(&cyborg, generation);
        self.stats.admit(&model, generation);
        let panel = sampler::draw(
            &self.config.sampler,
            &mut self.stats,
            &mut self.sampling,
            self.config.salt,
            generation,
            self.config.ticks,
            &cyborg,
            &model,
        );
        self.panel = Some(panel);
        self.last_training_wins = None;
    }

    fn close_panel(&mut self) -> Unit {
        let generation = self.population.generation;
        let challenger = self
            .population
            .best()
            .map(|m| (m.genome.clone(), m.score()));
        // Paired comparison: the incumbent was rescored on this same panel.
        let incumbent = self.champion.as_ref().and_then(|genome| {
            let fingerprint = genome.fingerprint();
            self.population
                .members()
                .find(|m| m.genome.fingerprint() == fingerprint)
                .and_then(|m| m.fitness)
        });
        if let Some((genome, score)) = challenger {
            let better = match (self.champion.as_ref(), incumbent) {
                (None, _) => true,
                (Some(_), None) => false,
                (Some(_), Some(previous)) => score > previous,
            };
            if better {
                self.promote(genome);
            }
        }
        self.history.push_back(HistoryRow {
            generation,
            stage: self.stage,
            training_win_rate: self.last_training_wins,
            validation_win_rate: self.last_validation.take(),
            species: self.population.species.len(),
            nodes: self
                .champion
                .as_ref()
                .map_or(0, |g| g.nodes.len()),
            episodes: self.episodes,
        });
        while self.history.len() > MAX_HISTORY {
            self.history.pop_front();
        }
        self.population.advance(&mut self.evolution);
        self.panel = None;
        if self.should_probe() {
            self.begin_probe();
        }
        Unit {
            episodes: 0,
            boundary: true,
        }
    }

    /// Records a new champion. This is the ONLY place the frozen self-play
    /// opponent may change, and it always discards the previous candidate's
    /// gate evidence rather than pooling it.
    fn promote(&mut self, genome: Genome) {
        let fingerprint = genome.fingerprint();
        let nodes = genome.nodes.len();
        let links = genome.enabled_count();
        self.champion = Some(genome.clone());
        self.evidence.clear();
        self.priority.clear();
        if matches!(self.mode, Mode::Auditing { .. } | Mode::Probing { .. }) {
            self.mode = Mode::Training;
        }
        if self.ladder == Ladder::Mixed {
            self.frozen_opponent = Some(genome);
            self.opponent_revision += 1;
            self.note(format!(
                "champion {fingerprint} promoted; frozen self-play opponent is now revision {}",
                self.opponent_revision
            ));
        } else {
            self.note(format!(
                "champion {fingerprint} promoted ({nodes} nodes, {links} links); gate evidence reset"
            ));
        }
    }

    fn should_probe(&self) -> bool {
        self.ladder == Ladder::Climbing
            && self.champion.is_some()
            && self.population.generation % self.config.readiness_period == 0
    }

    fn begin_probe(&mut self) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            return;
        };
        let cells = self.cyborg_cells();
        let attempt = self.audit_attempt;
        let tasks = sampler::readiness_probe(
            self.config.salt,
            attempt,
            self.config.readiness_games,
            self.config.ticks,
            &cells,
        );
        self.mode = Mode::Probing {
            attempt,
            champion,
            tasks,
            cursor: 0,
            wins: 0,
        };
    }

    fn step_probe(
        &mut self,
        attempt: u64,
        champion: String,
        tasks: Vec<Task>,
        cursor: usize,
        wins: u32,
    ) -> Unit {
        let Some(genome) = self.champion.clone() else {
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        };
        if genome.fingerprint() != champion || cursor >= tasks.len() {
            let played = cursor.max(1);
            let rate = wins as f64 / played as f64;
            self.last_validation = Some(rate);
            if genome.fingerprint() == champion && rate >= self.config.readiness_threshold {
                self.note(format!(
                    "readiness {:.1}% over {} probe games: opening an audit",
                    rate * 100.0,
                    cursor
                ));
                self.begin_gate(Round::Audit);
            } else {
                self.mode = Mode::Training;
            }
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        let network = self.compiled(&genome);
        let batch = tasks.len().min(cursor + 8);
        let mut played = 0;
        let mut won = wins;
        for task in &tasks[cursor..batch] {
            won += self.play(task, &network).won as u32;
            played += 1;
        }
        self.mode = Mode::Probing {
            attempt,
            champion,
            tasks,
            cursor: batch,
            wins: won,
        };
        Unit {
            episodes: played,
            boundary: false,
        }
    }

    fn begin_gate(&mut self, round: Round) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            self.mode = Mode::Training;
            return;
        };
        let cells = self.cyborg_cells();
        let priority = self.priority.clone();
        self.mode = Mode::Auditing {
            gate: Gate::open(
                champion,
                self.stage,
                self.opponent_revision,
                round,
                self.config.audit,
                &cells,
                &priority,
            ),
        };
    }

    fn step_audit(&mut self, mut gate: Gate) -> Unit {
        let Some(genome) = self.champion.clone() else {
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        };
        // The candidate is frozen for the whole panel. If it moved, the
        // evidence describes a policy that no longer exists.
        if genome.fingerprint() != gate.champion
            || gate.stage != self.stage
            || gate.opponent_revision != self.opponent_revision
        {
            self.note("audit abandoned: the candidate or opponent changed".into());
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        match gate.progress() {
            Progress::Running => {}
            finished => return self.finish_gate(gate, finished),
        }
        let network = self.compiled(&genome);
        let stream = match gate.round {
            Round::Audit => StreamTag::Audit,
            Round::Confirm => StreamTag::Confirm,
        };
        let attempt = self.audit_attempt;
        let ticks = self.config.ticks;
        let mut played = 0u64;
        for _ in 0..8 {
            let Some((cell, slot)) = gate.next_task() else {
                break;
            };
            let swap = slot % 2 == 1;
            let task = Task {
                cell,
                swap,
                seed: episode_seed(
                    stream,
                    self.config.salt,
                    cell.key(),
                    swap as u64,
                    attempt * 1_000_000 + self.stage as u64 * 1_000 + slot as u64,
                ),
                ticks,
            };
            let outcome = self.play(&task, &network);
            gate.record(cell, outcome.won);
            played += 1;
            if gate.progress() != Progress::Running {
                break;
            }
        }
        let progress = gate.progress();
        if progress == Progress::Running {
            self.mode = Mode::Auditing { gate };
            return Unit {
                episodes: played,
                boundary: false,
            };
        }
        let mut unit = self.finish_gate(gate, progress);
        unit.episodes += played;
        unit
    }

    fn finish_gate(&mut self, gate: Gate, progress: Progress) -> Unit {
        match progress {
            Progress::Passed if gate.round == Round::Audit => {
                for (cell, tally) in gate.evidence() {
                    self.evidence.insert(*cell, *tally);
                }
                self.note(format!(
                    "audit panel passed for {} at stage {}: confirming on a disjoint panel",
                    gate.champion, self.stage
                ));
                self.begin_gate(Round::Confirm);
            }
            Progress::Passed => {
                for (cell, tally) in gate.evidence() {
                    self.evidence.insert(*cell, *tally);
                }
                self.advance_stage(&gate.champion);
            }
            Progress::Failed | Progress::Exhausted => {
                self.priority = gate.failed_cells();
                self.audit_attempt += 1;
                for (cell, tally) in gate.evidence() {
                    self.evidence.insert(*cell, *tally);
                }
                let reason = if progress == Progress::Exhausted {
                    "budget exhausted"
                } else {
                    "a matchup could not clear the bound"
                };
                self.note(format!(
                    "{} round ended at stage {}: {reason}; {} cell(s) flagged",
                    gate.round.as_str(),
                    self.stage,
                    self.priority.len()
                ));
                self.mode = Mode::Training;
            }
            Progress::Running => {
                self.mode = Mode::Auditing { gate };
            }
        }
        Unit {
            episodes: 0,
            boundary: true,
        }
    }

    fn advance_stage(&mut self, champion: &str) {
        self.audit_attempt += 1;
        self.priority.clear();
        if self.stage < curriculum::FINAL_STAGE {
            let (side, ship) = curriculum::next_addition(self.stage);
            self.stage += 1;
            self.note(format!(
                "stage {} mastered by {champion}; adding {} hull {}",
                self.stage - 1,
                side,
                ship.map(|s| s.name()).unwrap_or("none")
            ));
            self.evidence.clear();
        } else {
            self.ladder = Ladder::Mixed;
            self.frozen_opponent = self.champion.clone();
            self.opponent_revision += 1;
            self.note(format!(
                "every ordered cyborg matchup is gated by {champion}; entering the mixed phase \
                 with frozen opponent revision {} alongside continued Awesome cyborg rehearsal",
                self.opponent_revision
            ));
        }
        self.mode = Mode::Training;
    }

    pub fn phase(&self) -> &'static str {
        match self.mode {
            Mode::Training | Mode::Probing { .. } => "training",
            Mode::Auditing { .. } => "auditing",
        }
    }

    pub fn mastered(&self) -> usize {
        self.evidence
            .values()
            .filter(|t| {
                t.lower_bound()
                    .is_some_and(|b| b > self.config.audit.target)
            })
            .count()
    }
}

fn now() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    iso8601(seconds)
}

/// Days are counted from the Unix epoch with the civil-calendar algorithm, so
/// no dependency is needed for a timestamp the dashboard can parse.
pub fn iso8601(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let rest = seconds % 86_400;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { year + 1 } else { year };
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        rest / 3600,
        (rest % 3600) / 60,
        rest % 60
    )
}
