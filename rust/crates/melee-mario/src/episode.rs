//! Running one fight and scoring it.
//!
//! There are two scorers, chosen per run by [`Scoring`] and recorded in that
//! run's configuration: [`Scoring::Combat`], the original win-plus-advantage
//! -plus-speed fitness that every run written before the selector existed used,
//! and [`Scoring::CrewRatio`], which is purely our surviving fraction of our
//! starting crew over theirs. Neither changes what the stage GATE counts: that
//! is still actual won-and-resolved fights, reported separately.
//!
//! Every fight goes through `melee_neat::eval`, which is the authoritative
//! display-tick, physics-pump and round-transition path the Elm evaluator
//! follows. Nothing here touches physics, forces a death or shortens a round:
//! a policy that fails to finish simply runs out of ticks, and running out of
//! ticks is NOT a win.
//!
//! KNOWN UNRESOLVED CASE. The evaluator's round transition can land in
//! `Phase::Selecting` rather than `Phase::Victory` when both singleton slots
//! are still occupied at the end of a round, which the Pkunk's resurrection
//! can produce. That is pre-existing Local/evaluator phase semantics shared
//! with the original dense path, and it is deliberately NOT reinterpreted
//! here: such an episode is counted as UNRESOLVED, exactly like a timeout, and
//! never as a win for either seat. Turning it into a win, or resuming combat
//! artificially, would change game semantics to make a number look better. The
//! trainer counts these episodes separately and the status document reports
//! the count, so the conservatism is visible rather than hidden.

use crate::curriculum::Cell;
use crate::graph::Network;
use melee_core::units::Side;
use melee_neat::eval::{self, Job};
use melee_sim::input::CyborgRating;
use serde_json::{json, Value};
use std::sync::Arc;

/// The default display-tick ceiling. At 60 display ticks per second this is a
/// full minute of melee, which is long enough for every original ship pairing
/// to resolve when a policy is actually trying to win.
pub const DEFAULT_TICKS: i64 = 3600;

/// One fight, fully determined by its fields. Two runs of the same task with
/// the same policy produce the same result, which is what makes stop/resume
/// equivalent to an uninterrupted run.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Task {
    pub cell: Cell,
    /// False puts our policy in the bottom seat, true in the top seat.
    pub swap: bool,
    pub seed: i64,
    pub ticks: i64,
}

impl Task {
    pub fn our_seat(&self) -> Side {
        if self.swap {
            Side::Top
        } else {
            Side::Bottom
        }
    }
}

#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Outcome {
    /// The round reached a victory. False for a tick-limit timeout AND for the
    /// Pkunk resurrection case described at the top of this module; neither is
    /// a win for anybody.
    pub resolved: bool,
    pub won: bool,
    pub ticks: i64,
    pub our_crew: i64,
    pub their_crew: i64,
    pub our_start: i64,
    pub their_start: i64,
}

impl Outcome {
    /// Crew advantage mapped to `0.0 ..= 1.0`, where a half is parity.
    pub fn crew_advantage(&self) -> f64 {
        let ours = self.our_crew as f64 / self.our_start.max(1) as f64;
        let theirs = self.their_crew as f64 / self.their_start.max(1) as f64;
        ((ours - theirs).clamp(-1.0, 1.0) + 1.0) / 2.0
    }

    /// How quickly a win arrived, `1.0` being instant. Zero unless we won.
    pub fn promptness(&self, ticks: i64) -> f64 {
        if !self.won {
            return 0.0;
        }
        (1.0 - self.ticks as f64 / ticks.max(1) as f64).clamp(0.0, 1.0)
    }

    /// Fitness of a single fight. The weights are a strict ordering, not a
    /// tuned shaping term: any win (>= 1.0) beats any non-win (<= 0.2), and
    /// among wins the crew advantage (<= 0.2) outranks speed (<= 0.02). There
    /// are no large legacy constants and nothing rewards a timeout.
    pub fn fitness(&self, ticks: i64) -> f64 {
        (self.won as u8 as f64) + 0.2 * self.crew_advantage() + 0.02 * self.promptness(ticks)
    }

    /// Our surviving fraction of OUR starting crew. Not a fraction of maximum
    /// crew and not an absolute count, so hulls of different sizes compare on
    /// the same scale. A ship that gains crew legitimately goes above `1.0`.
    pub fn our_fraction(&self) -> f64 {
        self.our_crew.max(0) as f64 / self.our_start.max(1) as f64
    }

    /// Their surviving fraction of THEIR starting crew, on the same terms.
    pub fn their_fraction(&self) -> f64 {
        self.their_crew.max(0) as f64 / self.their_start.max(1) as f64
    }

    /// Our surviving crew fraction divided by theirs.
    ///
    /// `1.0` means both sides kept the same PERCENTAGE of the crew they
    /// started with; it is a raw ratio, not a win rate and not a health bar.
    /// The three cases the division cannot express are named rather than
    /// approximated, and the ordinary case is never clamped to `1.0`:
    ///
    ///   * we have crew and they have none: [`RATIO_WIPEOUT`];
    ///   * neither side has crew: [`RATIO_MUTUAL`], a neutral tie;
    ///   * we have none and they do: `0.0`.
    ///
    /// Nothing here depends on how long the fight took or on whether the round
    /// was resolved, so this scorer pays nothing for a fast kill or a timeout.
    pub fn crew_ratio(&self) -> f64 {
        let ours = self.our_fraction();
        let theirs = self.their_fraction();
        match (ours > 0.0, theirs > 0.0) {
            (true, true) => (ours / theirs).min(RATIO_CAP),
            (true, false) => RATIO_WIPEOUT,
            (false, false) => RATIO_MUTUAL,
            (false, true) => 0.0,
        }
    }

    /// Fitness under the run's configured scorer. This is the ONLY entry point
    /// the trainer uses, so population members, the rescored incumbent and the
    /// species references it feeds all come from the same definition.
    pub fn score(&self, scoring: Scoring, ticks: i64) -> f64 {
        match scoring {
            Scoring::Combat => self.fitness(ticks),
            Scoring::CrewRatio => self.crew_ratio(),
        }
    }
}

pub const WIN_WEIGHT: f64 = 1.0;
pub const CREW_WEIGHT: f64 = 0.2;
pub const SPEED_WEIGHT: f64 = 0.02;

/// Score when we still have crew and the enemy has none. The exact ratio is
/// undefined there, so a finite stand-in is used rather than an infinity that
/// would poison every average it enters.
pub const RATIO_WIPEOUT: f64 = 1000.0;

/// Score for a mutual wipeout. Both sides kept the same fraction of their
/// starting crew, namely none, so the fight is a neutral tie.
pub const RATIO_MUTUAL: f64 = 1.0;

/// Upper guard on a ratio that IS defined. A legitimate ratio is never clamped
/// to one; this only stops an enemy clinging to a sliver of a large complement
/// from outscoring an actual wipeout, and keeps every average finite.
pub const RATIO_CAP: f64 = 1000.0;

/// Which scorer turns an [`Outcome`] into the fitness the trainer selects on.
///
/// This is a per-run choice recorded in the run's own configuration, never a
/// global default that changes underneath an existing run: a configuration
/// that names no scorer means [`Scoring::Combat`], the exact behaviour every
/// run written before this existed was trained under.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub enum Scoring {
    /// The original scorer: a win, plus crew advantage, plus speed.
    #[default]
    Combat,
    /// Our surviving fraction of our starting crew divided by theirs. No win
    /// term, no kill term, no survival term and no time term whatsoever, so
    /// the same end state scores the same however long it took to reach.
    CrewRatio,
}

impl Scoring {
    pub fn as_str(self) -> &'static str {
        match self {
            Scoring::Combat => "combat",
            Scoring::CrewRatio => "crew-ratio",
        }
    }

    /// Rejects anything that is not one of the named scorers rather than
    /// falling back to a default the operator did not ask for.
    pub fn parse(name: &str) -> Option<Scoring> {
        match name {
            "combat" => Some(Scoring::Combat),
            "crew-ratio" => Some(Scoring::CrewRatio),
            _ => None,
        }
    }

    /// True when this scorer pays anything for finishing sooner.
    pub fn rewards_speed(self) -> bool {
        matches!(self, Scoring::Combat)
    }

    /// The scorer as the dashboard reads it. `zero_opponent` and `mutual_zero`
    /// are null under a scorer that has no such special case, so a reader can
    /// tell "not applicable" from "happens to be one".
    pub fn to_json(self) -> Value {
        let (zero_opponent, mutual_zero) = match self {
            Scoring::Combat => (Value::Null, Value::Null),
            Scoring::CrewRatio => (json!(RATIO_WIPEOUT), json!(RATIO_MUTUAL)),
        };
        json!({
            "fitness": self.as_str(),
            "zero_opponent": zero_opponent,
            "mutual_zero": mutual_zero,
            "speed_bonus": self.rewards_speed(),
            // The GATE is not the scorer. Stage promotion still counts actual
            // resolved victories, whatever fitness the population is ranked by.
            "gate": GATE_CRITERION
        })
    }

    /// Reads back [`Scoring::to_json`]. An absent block means the scorer that
    /// predates this field; a block naming an unknown scorer is rejected.
    ///
    /// `fitness` is the only authoritative field: everything beside it is a
    /// FACT ABOUT that scorer, not a setting. A stored block that disagrees
    /// with the scorer it names, `speed_bonus: true` under `crew-ratio`, say,
    /// or a `gate` this build does not implement, describes a run this build
    /// cannot honour, so it is rejected rather than quietly rewritten into
    /// agreement with itself.
    pub fn from_json(value: Option<&Value>) -> Option<Scoring> {
        let Some(block) = value else {
            return Some(Scoring::default());
        };
        let scoring = Scoring::parse(block.get("fitness")?.as_str()?)?;
        let derived = scoring.to_json();
        for field in ["zero_opponent", "mutual_zero", "speed_bonus", "gate"] {
            if let Some(stored) = block.get(field) {
                if stored != &derived[field] {
                    return None;
                }
            }
        }
        Some(scoring)
    }
}

/// What stage promotion actually measures. Unchanged by this work: fitness
/// selects the population, actual won-and-resolved fights open the gate.
pub const GATE_CRITERION: &str = "combat-wins";

impl std::str::FromStr for Scoring {
    type Err = String;

    fn from_str(name: &str) -> Result<Scoring, String> {
        Scoring::parse(name).ok_or_else(|| format!("unknown scorer {name}"))
    }
}

/// Who sits in the other seat. A model opponent is a frozen snapshot: its
/// weights never change inside a generation or an audit.
pub enum Rival<'a> {
    Cyborg(CyborgRating),
    Model(&'a Arc<Network>),
}

pub fn run(task: &Task, ours: &Arc<Network>, rival: Rival<'_>) -> Outcome {
    let job = Job {
        seed: task.seed,
        ticks: task.ticks,
        swap: task.swap,
        rating: match rival {
            Rival::Cyborg(rating) => rating,
            // Unused: with two model brains no cyborg ever pilots a seat.
            Rival::Model(_) => CyborgRating::AwesomeCyborg,
        },
        us: task.cell.our_ship(),
        them: task.cell.their_ship(),
        self_play: matches!(rival, Rival::Model(_)),
    };
    let seat = task.our_seat();
    let report = match rival {
        Rival::Cyborg(_) => {
            eval::run_with(&job, crate::brain::SeatPilot::new(seat, ours.clone()))
        }
        Rival::Model(theirs) => eval::run_with(
            &job,
            crate::brain::DuelPilot::new(seat, ours.clone(), theirs.clone()),
        ),
    };
    let seat_name = if task.swap { "top" } else { "bottom" };
    Outcome {
        resolved: report.completed,
        won: report.completed && report.winner == seat_name,
        ticks: report.ticks,
        our_crew: *report.crew.get(seat),
        their_crew: *report.crew.get(seat.other()),
        our_start: task.cell.our_ship().stock().starting_crew,
        their_start: task.cell.their_ship().stock().starting_crew,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outcome(won: bool, resolved: bool, ours: i64, theirs: i64, ticks: i64) -> Outcome {
        Outcome {
            resolved,
            won,
            ticks,
            our_crew: ours,
            their_crew: theirs,
            our_start: 20,
            their_start: 20,
        }
    }

    #[test]
    fn a_win_always_outranks_any_non_win() {
        let worst_win = outcome(true, true, 1, 0, 3600).fitness(3600);
        let best_loss = outcome(false, true, 20, 0, 1).fitness(3600);
        let best_timeout = outcome(false, false, 20, 0, 3600).fitness(3600);
        assert!(worst_win > best_loss);
        assert!(worst_win > best_timeout);
        assert!(worst_win >= WIN_WEIGHT);
        assert!(best_loss <= WIN_WEIGHT);
    }

    #[test]
    fn crew_advantage_outranks_speed_among_wins() {
        let slow_and_intact = outcome(true, true, 20, 0, 3600).fitness(3600);
        let fast_and_battered = outcome(true, true, 1, 0, 1).fitness(3600);
        assert!(slow_and_intact > fast_and_battered);
        let fast = outcome(true, true, 10, 0, 100).fitness(3600);
        let slow = outcome(true, true, 10, 0, 3000).fitness(3600);
        assert!(fast > slow);
    }

    #[test]
    fn a_timeout_is_never_rewarded_as_a_win() {
        let timeout = outcome(false, false, 20, 1, 3600);
        assert!(!timeout.won);
        assert_eq!(timeout.promptness(3600), 0.0);
        assert!(timeout.fitness(3600) < WIN_WEIGHT);
    }

    #[test]
    fn a_mutual_kill_scores_as_parity_and_not_as_a_win() {
        let draw = outcome(false, true, 0, 0, 2000);
        assert_eq!(draw.crew_advantage(), 0.5);
        assert!((draw.fitness(3600) - 0.1).abs() < 1e-12);
    }

    /// A fight between hulls of different sizes, so that a ratio of raw counts
    /// and a ratio of fractions cannot be confused for one another.
    fn fight(ours: i64, our_start: i64, theirs: i64, their_start: i64) -> Outcome {
        Outcome {
            resolved: true,
            won: false,
            ticks: 1200,
            our_crew: ours,
            their_crew: theirs,
            our_start,
            their_start,
        }
    }

    #[test]
    fn the_ratio_is_of_starting_fractions_not_of_raw_crew() {
        // Eight of a twelve-crew hull against twenty of a forty-crew hull:
        // two thirds against a half, so four thirds. On raw counts it would
        // have been 0.4, which is the wrong side of parity.
        let end = fight(8, 12, 20, 40);
        assert!((end.crew_ratio() - (2.0 / 3.0) / 0.5).abs() < 1e-12);
        assert!(end.crew_ratio() > 1.0);
    }

    #[test]
    fn the_ratio_ignores_how_long_the_fight_took_and_whether_it_resolved() {
        let quick = Outcome {
            ticks: 1,
            ..fight(10, 20, 5, 20)
        };
        let slow = Outcome {
            ticks: 1200,
            ..fight(10, 20, 5, 20)
        };
        let unresolved = Outcome {
            resolved: false,
            ..slow
        };
        assert_eq!(quick.crew_ratio(), slow.crew_ratio());
        assert_eq!(unresolved.crew_ratio(), slow.crew_ratio());
        // And the configured scorer passes no tick budget through either.
        assert_eq!(
            quick.score(Scoring::CrewRatio, 1200),
            slow.score(Scoring::CrewRatio, 3600)
        );
    }

    #[test]
    fn wiping_them_out_scores_the_finite_stand_in() {
        assert_eq!(fight(1, 20, 0, 20).crew_ratio(), RATIO_WIPEOUT);
        assert!(fight(1, 20, 0, 20).crew_ratio().is_finite());
        // A sliver of a large complement must not outscore a real wipeout.
        assert!(fight(20, 20, 1, 42).crew_ratio() < RATIO_WIPEOUT);
    }

    #[test]
    fn a_mutual_wipeout_is_a_neutral_tie_and_our_own_death_scores_zero() {
        assert_eq!(fight(0, 20, 0, 42).crew_ratio(), RATIO_MUTUAL);
        assert_eq!(fight(0, 20, 1, 42).crew_ratio(), 0.0);
        assert_eq!(fight(0, 20, 42, 42).crew_ratio(), 0.0);
    }

    #[test]
    fn a_losing_ratio_is_reported_exactly_and_never_floored_at_parity() {
        let end = fight(5, 20, 20, 20);
        assert!((end.crew_ratio() - 0.25).abs() < 1e-12);
        assert!(end.crew_ratio() < RATIO_MUTUAL);
    }

    #[test]
    fn a_crew_gain_is_allowed_to_score_above_one_hundred_percent() {
        // The Pkunk's resurrection and the Shofixti's bay can leave a hull
        // holding more crew than it started with; that is a real advantage and
        // the fraction is deliberately not clamped to one.
        let end = fight(30, 20, 20, 20);
        assert!(end.our_fraction() > 1.0);
        assert!((end.crew_ratio() - 1.5).abs() < 1e-12);
    }

    #[test]
    fn every_defined_ratio_stays_finite_so_averages_stay_finite() {
        let cases = [
            fight(20, 20, 1, 20),
            fight(1, 20, 0, 20),
            fight(0, 20, 0, 20),
            fight(0, 20, 20, 20),
            fight(0, 1, 0, 1),
        ];
        let total: f64 = cases.iter().map(Outcome::crew_ratio).sum();
        assert!(total.is_finite());
        assert!((total / cases.len() as f64).is_finite());
    }

    #[test]
    fn the_crew_ratio_scorer_pays_nothing_for_a_win_or_for_speed() {
        let lost_fast = Outcome {
            won: false,
            ticks: 1,
            ..fight(10, 20, 10, 20)
        };
        let won_slow = Outcome {
            won: true,
            ticks: 1200,
            ..fight(10, 20, 10, 20)
        };
        assert_eq!(
            lost_fast.score(Scoring::CrewRatio, 1200),
            won_slow.score(Scoring::CrewRatio, 1200)
        );
        // The combat scorer still separates them, unchanged.
        assert!(won_slow.score(Scoring::Combat, 1200) > lost_fast.score(Scoring::Combat, 1200));
    }

    #[test]
    fn the_default_scorer_is_the_exact_original_fitness() {
        let end = outcome(true, true, 7, 3, 900);
        assert_eq!(Scoring::default(), Scoring::Combat);
        assert_eq!(end.score(Scoring::default(), 3600), end.fitness(3600));
        assert!(Scoring::Combat.rewards_speed());
        assert!(!Scoring::CrewRatio.rewards_speed());
    }

    #[test]
    fn a_scorer_round_trips_and_an_unknown_name_is_rejected() {
        for scoring in [Scoring::Combat, Scoring::CrewRatio] {
            let block = scoring.to_json();
            assert_eq!(Scoring::from_json(Some(&block)), Some(scoring));
            assert_eq!(Scoring::parse(scoring.as_str()), Some(scoring));
            assert_eq!(block["gate"], GATE_CRITERION);
            assert_eq!(block["speed_bonus"], scoring.rewards_speed());
        }
        assert_eq!(Scoring::parse("crew_ratio"), None);
        assert_eq!(Scoring::parse("ratio"), None);
        assert_eq!(Scoring::parse(""), None);
        assert_eq!(Scoring::from_json(Some(&json!({"fitness": "kills"}))), None);
        assert_eq!(Scoring::from_json(Some(&json!({}))), None);
        // An absent block is the one thing that means the legacy scorer.
        assert_eq!(Scoring::from_json(None), Some(Scoring::Combat));
    }

    #[test]
    fn a_block_that_contradicts_the_scorer_it_names_is_rejected() {
        // Each of these describes a run this build does not implement, so
        // reading it as "crew-ratio, and never mind the rest" would misreport
        // what produced the checkpoint's fitness numbers.
        for bad in [
            json!({"fitness": "crew-ratio", "speed_bonus": true}),
            json!({"fitness": "crew-ratio", "zero_opponent": 7}),
            json!({"fitness": "crew-ratio", "mutual_zero": 0}),
            json!({"fitness": "crew-ratio", "gate": "crew-lead"}),
            json!({"fitness": "combat", "speed_bonus": false}),
            json!({"fitness": "combat", "zero_opponent": 1000}),
            json!({"fitness": "combat", "gate": "crew-lead"}),
        ] {
            assert_eq!(Scoring::from_json(Some(&bad)), None, "{bad}");
        }
        // A block carrying only the authoritative field is still valid, and so
        // is one carrying metadata that agrees with it.
        assert_eq!(
            Scoring::from_json(Some(&json!({"fitness": "crew-ratio"}))),
            Some(Scoring::CrewRatio)
        );
        assert_eq!(
            Scoring::from_json(Some(&json!({"fitness": "crew-ratio", "speed_bonus": false,
                                            "gate": GATE_CRITERION}))),
            Some(Scoring::CrewRatio)
        );
    }

    #[test]
    fn the_json_names_the_special_cases_only_where_they_exist() {
        let ratio = Scoring::CrewRatio.to_json();
        assert_eq!(ratio["zero_opponent"], json!(RATIO_WIPEOUT));
        assert_eq!(ratio["mutual_zero"], json!(RATIO_MUTUAL));
        let combat = Scoring::Combat.to_json();
        assert!(combat["zero_opponent"].is_null());
        assert!(combat["mutual_zero"].is_null());
    }
}
