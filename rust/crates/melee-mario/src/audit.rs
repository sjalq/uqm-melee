//! Fresh-evidence gating for a stage promotion.
//!
//! The design is deliberately conservative and fully predeclared:
//!
//!   * A gate is opened against ONE frozen candidate (its genome fingerprint)
//!     and one opponent revision. Any change to either throws the gate away;
//!     evidence is never pooled across candidates or across revisions.
//!   * Every active ordered cell gets its own fixed-size panel, half the games
//!     in each seat. There is no optional extra sampling and no stopping early
//!     because the numbers happen to look good, so the Wilson bound below is
//!     not inflated by peeking.
//!   * A cell passes on its own Wilson lower bound, not on a pooled rate, so a
//!     strong cell cannot hide a weak one.
//!   * A cell is abandoned the moment winning every remaining game could no
//!     longer clear the bound, and the whole attempt is abandoned after a few
//!     such cells or when the episode budget runs out. That is what keeps an
//!     audit affordable on one low-priority core.
//!   * Passing the audit panel is not promotion: a disjoint confirmation panel
//!     must pass as well.

use crate::curriculum::Cell;
use serde_json::{json, Value};
use std::collections::BTreeMap;

/// Two-sided 95% normal quantile; the resulting one-sided bound is the number
/// the dashboard shows next to the target.
pub const Z: f64 = 1.959_963_984_540_054;

/// Wilson score interval, lower end. `None` when there is no evidence at all.
pub fn wilson_lower(wins: u32, games: u32) -> Option<f64> {
    if games == 0 {
        return None;
    }
    let n = games as f64;
    let p = wins as f64 / n;
    let z2 = Z * Z;
    let denominator = 1.0 + z2 / n;
    let center = p + z2 / (2.0 * n);
    let margin = Z * (p * (1.0 - p) / n + z2 / (4.0 * n * n)).sqrt();
    Some(((center - margin) / denominator).clamp(0.0, 1.0))
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Verdict {
    Pending,
    Passed,
    Failed,
}

impl Verdict {
    fn as_str(self) -> &'static str {
        match self {
            Verdict::Pending => "pending",
            Verdict::Passed => "passed",
            Verdict::Failed => "failed",
        }
    }

    fn parse(raw: &str) -> Option<Verdict> {
        match raw {
            "pending" => Some(Verdict::Pending),
            "passed" => Some(Verdict::Passed),
            "failed" => Some(Verdict::Failed),
            _ => None,
        }
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct Tally {
    pub wins: u32,
    pub games: u32,
}

impl Tally {
    pub fn rate(self) -> Option<f64> {
        (self.games > 0).then(|| self.wins as f64 / self.games as f64)
    }

    pub fn lower_bound(self) -> Option<f64> {
        wilson_lower(self.wins, self.games)
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Round {
    /// The gate's first fixed panel.
    Audit,
    /// The disjoint panel that must also pass before a stage is promoted.
    Confirm,
    /// A bounded cyborg-only sweep run during the mixed phase. It promotes
    /// nothing and gates nothing; its only job is to notice that a policy which
    /// has been training against a frozen copy of itself has started losing to
    /// the original Awesome cyborgs again.
    Regression,
}

impl Round {
    pub fn as_str(self) -> &'static str {
        match self {
            Round::Audit => "audit",
            Round::Confirm => "confirm",
            Round::Regression => "regression",
        }
    }

    /// Whether passing this round can move the curriculum forward.
    pub fn promotes(self) -> bool {
        matches!(self, Round::Audit | Round::Confirm)
    }

    pub fn parse(raw: &str) -> Option<Round> {
        match raw {
            "audit" => Some(Round::Audit),
            "confirm" => Some(Round::Confirm),
            "regression" => Some(Round::Regression),
            _ => None,
        }
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Progress {
    /// More episodes are owed on this panel.
    Running,
    /// Every cell cleared its bound on this round.
    Passed,
    /// A cell cannot clear its bound, or too many cells failed.
    Failed,
    /// The attempt ran out of episodes before deciding.
    Exhausted,
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct AuditConfig {
    /// Games per cell per round. Half are played in each seat.
    pub panel: u32,
    /// Episode ceiling for one attempt, across all cells.
    pub budget: u32,
    /// Give up the attempt after this many cells fail.
    pub max_failures: u32,
    pub target: f64,
}

impl Default for AuditConfig {
    fn default() -> Self {
        // Panel size is the whole conservatism dial. A Wilson lower bound above
        // 0.8 is a far stronger demand than an observed rate above 0.8, and how
        // much stronger depends entirely on the panel:
        //
        //   16 games: bound clears only at 16/16   (100% observed)
        //   32 games: bound clears at 31/32        (96.9% observed)
        //   64 games: bound clears at 58/64        (90.6% observed)
        //  100 games: bound clears at 88/100       (88.0% observed)
        //
        // 100 keeps the implied bar closest to the intended "a bit over 80%"
        // while still clearing a genuine lower bound. The full 625-cell board
        // then costs 62,500 fights per round; measured at roughly 220 fights a
        // second on one core, that is about nine minutes of compute at the
        // default half-core duty, and fail-fast abandons a weak candidate long
        // before it gets that far.
        AuditConfig {
            panel: 100,
            budget: 200_000,
            max_failures: 3,
            target: 0.80,
        }
    }
}

impl AuditConfig {
    pub fn to_json(self) -> Value {
        json!({"panel": self.panel, "budget": self.budget,
               "max_failures": self.max_failures, "target": self.target})
    }

    pub fn from_json(value: &Value) -> Option<AuditConfig> {
        Some(AuditConfig {
            panel: value.get("panel")?.as_u64()? as u32,
            budget: value.get("budget")?.as_u64()? as u32,
            max_failures: value.get("max_failures")?.as_u64()? as u32,
            target: value.get("target")?.as_f64()?,
        })
    }
}

/// One attempt at one round of evidence for one frozen candidate.
#[derive(Clone, Debug)]
pub struct Gate {
    pub champion: String,
    pub stage: usize,
    pub opponent_revision: u32,
    pub round: Round,
    pub config: AuditConfig,
    /// Cells in the order they will be audited: cells that failed a previous
    /// attempt come first, so a still-weak candidate is rejected cheaply.
    pub order: Vec<Cell>,
    pub tallies: BTreeMap<Cell, Tally>,
    pub verdicts: BTreeMap<Cell, Verdict>,
    pub spent: u32,
    pub cursor: usize,
}

impl Gate {
    pub fn open(
        champion: String,
        stage: usize,
        opponent_revision: u32,
        round: Round,
        config: AuditConfig,
        cells: &[Cell],
        priority: &[Cell],
    ) -> Gate {
        let mut order: Vec<Cell> = priority
            .iter()
            .copied()
            .filter(|c| cells.contains(c))
            .collect();
        for cell in cells {
            if !order.contains(cell) {
                order.push(*cell);
            }
        }
        let verdicts = order.iter().map(|c| (*c, Verdict::Pending)).collect();
        Gate {
            champion,
            stage,
            opponent_revision,
            round,
            config,
            order,
            tallies: BTreeMap::new(),
            verdicts,
            spent: 0,
            cursor: 0,
        }
    }

    /// The next episode owed: which cell, and which slot of that cell's panel.
    /// Slot parity is the seat, so both seats are always represented.
    pub fn next_task(&self) -> Option<(Cell, u32)> {
        if self.spent >= self.config.budget {
            return None;
        }
        let cell = *self.order.get(self.cursor)?;
        let played = self.tallies.get(&cell).copied().unwrap_or_default().games;
        (played < self.config.panel).then_some((cell, played))
    }

    pub fn record(&mut self, cell: Cell, won: bool) {
        let tally = self.tallies.entry(cell).or_default();
        tally.games += 1;
        tally.wins += won as u32;
        self.spent += 1;
        let tally = *tally;
        let remaining = self.config.panel.saturating_sub(tally.games);
        // Fail fast: even a perfect run of the remaining games would not clear
        // the bound, so nothing is learned by playing them.
        let best_case = wilson_lower(tally.wins + remaining, tally.games + remaining);
        let decided = if best_case.is_some_and(|b| b <= self.config.target) {
            Verdict::Failed
        } else if remaining > 0 {
            Verdict::Pending
        } else if tally.lower_bound().is_some_and(|b| b > self.config.target) {
            Verdict::Passed
        } else {
            Verdict::Failed
        };
        self.verdicts.insert(cell, decided);
        if decided != Verdict::Pending {
            self.cursor += 1;
        }
    }

    pub fn failures(&self) -> u32 {
        self.verdicts
            .values()
            .filter(|v| **v == Verdict::Failed)
            .count() as u32
    }

    pub fn failed_cells(&self) -> Vec<Cell> {
        self.order
            .iter()
            .copied()
            .filter(|c| self.verdicts.get(c) == Some(&Verdict::Failed))
            .collect()
    }

    pub fn progress(&self) -> Progress {
        if self.failures() >= self.config.max_failures.max(1) {
            return Progress::Failed;
        }
        if self.cursor >= self.order.len() {
            return if self.failures() > 0 {
                Progress::Failed
            } else {
                Progress::Passed
            };
        }
        if self.spent >= self.config.budget {
            return Progress::Exhausted;
        }
        Progress::Running
    }

    /// Cells decided so far; the dashboard shows these as audit evidence.
    pub fn evidence(&self) -> impl Iterator<Item = (&Cell, &Tally)> {
        self.tallies.iter()
    }

    pub fn to_json(&self) -> Value {
        let tallies: Vec<Value> = self
            .order
            .iter()
            .filter_map(|cell| {
                let tally = self.tallies.get(cell)?;
                Some(json!([cell.encode(), tally.wins, tally.games,
                            self.verdicts.get(cell).copied().unwrap_or(Verdict::Pending).as_str()]))
            })
            .collect();
        json!({"champion": self.champion, "stage": self.stage,
               "opponent_revision": self.opponent_revision, "round": self.round.as_str(),
               "config": self.config.to_json(), "spent": self.spent, "cursor": self.cursor,
               "order": self.order.iter().map(|c| c.encode()).collect::<Vec<_>>(),
               "tallies": tallies})
    }

    pub fn from_json(value: &Value) -> Option<Gate> {
        let order = value
            .get("order")?
            .as_array()?
            .iter()
            .map(Cell::decode)
            .collect::<Option<Vec<_>>>()?;
        let mut tallies = BTreeMap::new();
        let mut verdicts: BTreeMap<Cell, Verdict> =
            order.iter().map(|c| (*c, Verdict::Pending)).collect();
        for raw in value.get("tallies")?.as_array()? {
            let row = raw.as_array()?;
            let cell = Cell::decode(row.first()?)?;
            tallies.insert(
                cell,
                Tally {
                    wins: row.get(1)?.as_u64()? as u32,
                    games: row.get(2)?.as_u64()? as u32,
                },
            );
            verdicts.insert(cell, Verdict::parse(row.get(3)?.as_str()?)?);
        }
        Some(Gate {
            champion: value.get("champion")?.as_str()?.to_string(),
            stage: value.get("stage")?.as_u64()? as usize,
            opponent_revision: value.get("opponent_revision")?.as_u64()? as u32,
            round: Round::parse(value.get("round")?.as_str()?)?,
            config: AuditConfig::from_json(value.get("config")?)?,
            spent: value.get("spent")?.as_u64()? as u32,
            cursor: value.get("cursor")?.as_u64()? as usize,
            order,
            tallies,
            verdicts,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::curriculum::{cells, Opponent};

    #[test]
    fn wilson_needs_a_real_panel_before_it_can_clear_the_target() {
        assert_eq!(wilson_lower(0, 0), None);
        // A pooled-looking rate of 1.0 on one game proves nothing.
        assert!(wilson_lower(1, 1).unwrap() < 0.30);
        // Sixteen is the smallest perfect panel that clears the target at all.
        assert!(wilson_lower(15, 15).unwrap() < 0.80);
        assert!(wilson_lower(16, 16).unwrap() > 0.80);
        // Monotone in wins, and always below the observed rate.
        for games in 1..60u32 {
            for wins in 0..=games {
                let bound = wilson_lower(wins, games).unwrap();
                assert!((0.0..=1.0).contains(&bound));
                assert!(bound <= wins as f64 / games as f64 + 1e-12);
            }
        }
    }

    #[test]
    fn the_bound_demands_much_more_than_an_eighty_percent_observed_rate() {
        // This is the cost of refusing lucky promotions, spelled out: on the
        // default panel a cell may lose six of sixty-four and no more.
        let losses = |panel: u32| {
            (0..=panel)
                .filter(|l| wilson_lower(panel - l, panel).unwrap() > 0.80)
                .max()
                .unwrap()
        };
        assert_eq!(losses(32), 1);
        assert_eq!(losses(64), 6);
        assert_eq!(losses(100), 12);
        assert_eq!(AuditConfig::default().panel, 100);
        // An observed 80% never clears the bound at any practical panel size.
        for panel in [32u32, 64, 100, 400] {
            assert!(wilson_lower(panel * 8 / 10, panel).unwrap() <= 0.80);
        }
    }

    fn gate(cells: &[Cell]) -> Gate {
        Gate::open(
            "gtest".into(),
            0,
            0,
            Round::Audit,
            AuditConfig::default(),
            cells,
            &[],
        )
    }

    #[test]
    fn a_perfect_candidate_passes_every_cell_exactly_once() {
        let board = cells(2);
        let mut g = gate(&board);
        let mut played = 0;
        while let Some((cell, slot)) = g.next_task() {
            assert!(slot < g.config.panel);
            g.record(cell, true);
            played += 1;
        }
        assert_eq!(played, board.len() as u32 * g.config.panel);
        assert_eq!(g.progress(), Progress::Passed);
        assert!(g.failed_cells().is_empty());
    }

    #[test]
    fn one_weak_cell_fails_the_gate_even_when_the_rest_are_perfect() {
        let board = cells(2);
        let weak = board[2];
        let mut g = gate(&board);
        while let Some((cell, _)) = g.next_task() {
            g.record(cell, cell != weak);
        }
        assert_eq!(g.progress(), Progress::Failed);
        assert_eq!(g.failed_cells(), vec![weak]);
        // A pooled rate would have looked like three quarters wins and hidden it.
        let wins: u32 = g.tallies.values().map(|t| t.wins).sum();
        let games: u32 = g.tallies.values().map(|t| t.games).sum();
        assert!(wins as f64 / games as f64 > 0.7);
    }

    #[test]
    fn a_hopeless_cell_is_abandoned_long_before_its_panel_ends() {
        let board = vec![Cell {
            foe: Opponent::Cyborg,
            us: 0,
            them: 0,
        }];
        let mut g = gate(&board);
        while let Some((cell, _)) = g.next_task() {
            g.record(cell, false);
        }
        let tally = g.tallies[&board[0]];
        assert!(
            tally.games < g.config.panel,
            "played {} of {}",
            tally.games,
            g.config.panel
        );
        assert_eq!(g.progress(), Progress::Failed);
    }

    #[test]
    fn previously_failed_cells_are_audited_first() {
        let board = cells(4);
        let late = board[board.len() - 1];
        let g = Gate::open(
            "g".into(),
            4,
            0,
            Round::Audit,
            AuditConfig::default(),
            &board,
            &[late],
        );
        assert_eq!(g.order[0], late);
        assert_eq!(g.order.len(), board.len());
    }

    #[test]
    fn the_attempt_stops_when_the_episode_budget_runs_out() {
        let board = cells(6);
        let mut g = Gate::open(
            "g".into(),
            6,
            0,
            Round::Audit,
            AuditConfig {
                budget: 40,
                ..AuditConfig::default()
            },
            &board,
            &[],
        );
        while let Some((cell, _)) = g.next_task() {
            g.record(cell, true);
        }
        assert_eq!(g.spent, 40);
        assert_eq!(g.progress(), Progress::Exhausted);
    }

    #[test]
    fn a_gate_survives_a_checkpoint_round_trip_mid_panel() {
        let board = cells(2);
        let mut g = gate(&board);
        for _ in 0..37 {
            let (cell, _) = g.next_task().unwrap();
            g.record(cell, true);
        }
        let saved = g.to_json();
        let restored = Gate::from_json(&saved).expect("round trip");
        assert_eq!(restored.to_json(), saved);
        assert_eq!(restored.next_task(), g.next_task());
        assert_eq!(restored.spent, 37);
    }
}
