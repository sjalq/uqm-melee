//! Running one fight and scoring it.
//!
//! There are two scorers, chosen per run by [`Scoring`] and recorded in that
//! run's configuration: [`Scoring::Combat`], the original win-plus-advantage
//! -plus-speed fitness that every run written before the selector existed used,
//! and [`Scoring::CrewRatio`], which is purely our surviving fraction of our
//! starting crew over theirs.
//!
//! What the scorer ranks and what the stage GATE counts are separate run-owned
//! choices. [`GateCriterion`] says which fights count as successes:
//! [`GateCriterion::CombatWins`], the original actual-won-and-resolved rule
//! that every run written before this existed used and that a configuration
//! naming no criterion still means, or [`GateCriterion::CrewLead`], a strict
//! lead in surviving fraction of starting crew, for which an unresolved fight
//! is eligible. A crew-lead success is NOT a combat win and is never reported
//! as one: [`Outcome::won`] stays the factual combat result either way, and
//! the trainer counts actual victories separately from gate successes.
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
//!
//! Under [`GateCriterion::CrewLead`] such an episode can still be a gate
//! SUCCESS, because that criterion asks who is ahead on crew rather than who
//! won. That is a deliberate difference and not a reinterpretation of the
//! phase: [`Outcome::resolved`] and [`Outcome::won`] are untouched, so the
//! unresolved count and the factual combat-win count stay exactly as honest as
//! they were before.

use crate::broad::Cell;
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
        WIN_WEIGHT * self.won as u8 as f64
            + CREW_WEIGHT * self.crew_advantage()
            + SPEED_WEIGHT * self.promptness(ticks)
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

    /// True when the enemy ended with at least as much crew as it started
    /// with, so the fight produced no NET loss on their side.
    ///
    /// An endpoint comparison, not an attribution of damage. Crew that was
    /// lost and later regained leaves no net loss and is treated as none, and
    /// crew they lost to something other than us still counts as lost. Both
    /// figures are the same ship's own complement, so nothing needs
    /// normalising.
    pub fn no_net_enemy_loss(&self) -> bool {
        self.their_crew >= self.their_start
    }

    /// Fitness under the run's configured scorer and penalty. This is the ONLY
    /// entry point the trainer uses, so population members, the rescored
    /// incumbent and the species references it feeds all come from the same
    /// definition.
    ///
    /// The penalty is a floor-breaking constant, not a shaping term: when it
    /// is armed and the enemy took no net loss, the whole fight scores
    /// `-magnitude` whatever the scorer would otherwise have said. A run that
    /// did not ask for it (magnitude zero, which is the default and what every
    /// configuration written before it existed means) never reaches that
    /// branch at all.
    pub fn score(&self, scoring: ScoringConfig, ticks: i64) -> f64 {
        if scoring.no_damage_penalty > 0.0 && self.no_net_enemy_loss() {
            return -scoring.no_damage_penalty;
        }
        match scoring.fitness {
            Scoring::Combat => self.fitness(ticks),
            Scoring::CrewRatio => self.crew_ratio(),
        }
    }

    /// Whether this fight counts as a SUCCESS for the run's configured gate.
    ///
    /// Never confuse this with [`Outcome::won`], which stays the factual
    /// combat result under either criterion. Under
    /// [`GateCriterion::CrewLead`] a fight that nobody won can still be a
    /// success, and a fight we did win can still fail.
    pub fn succeeded(&self, gate: GateCriterion) -> bool {
        match gate {
            GateCriterion::CombatWins => self.won,
            GateCriterion::CrewLead => self.leads_on_crew(),
        }
    }

    /// A STRICT lead in surviving fraction of starting crew.
    ///
    /// Compared as an integer cross product rather than as two divisions, so
    /// the answer is exact: `ours/our_start > theirs/their_start` becomes
    /// `ours * their_start > theirs * our_start`, with both starting
    /// complements positive. No floating point is involved, so equal fractions
    /// that a division would round apart cannot be read as a lead.
    ///
    /// Every tie fails, including the both-sides-wiped-out tie, because the
    /// criterion asks for a LEAD and neither side has one. Whether the round
    /// resolved is not consulted: a fight that hit the tick ceiling while we
    /// were ahead on crew is a success, which is exactly the difference
    /// between this criterion and counting victories.
    pub fn leads_on_crew(&self) -> bool {
        let ours = self.our_crew.max(0) as i128 * self.their_start.max(1) as i128;
        let theirs = self.their_crew.max(0) as i128 * self.our_start.max(1) as i128;
        ours > theirs
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

    /// Facts about this scorer, for the dashboard. `zero_opponent` and
    /// `mutual_zero` are null under a scorer that has no such special case, so
    /// a reader can tell "not applicable" from "happens to be one".
    ///
    /// Everything here is DERIVED from the scorer. None of it is a setting,
    /// which is why [`ScoringConfig::from_json`] rejects a stored block whose
    /// values disagree with the scorer it names rather than obeying them.
    fn facts(self) -> Value {
        let (zero_opponent, mutual_zero) = match self {
            Scoring::Combat => (Value::Null, Value::Null),
            Scoring::CrewRatio => (json!(RATIO_WIPEOUT), json!(RATIO_MUTUAL)),
        };
        json!({
            "zero_opponent": zero_opponent,
            "mutual_zero": mutual_zero,
            "speed_bonus": self.rewards_speed(),
        })
    }
}

/// What an audit round, a confirmation round, a readiness probe and the
/// sampler's own weakness statistics all count as a SUCCESS. A per-run choice recorded in the run's configuration, exactly like
/// the scorer and entirely independent of it: a run may rank its population on
/// crew ratio while still gating on actual victories, or the reverse.
///
/// A configuration naming no criterion means [`GateCriterion::CombatWins`],
/// which is what every run written before this existed was gated on.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub enum GateCriterion {
    /// The original criterion: an actual won-and-resolved fight. A timeout is
    /// not a win and never opens a gate.
    #[default]
    CombatWins,
    /// A strict lead in surviving fraction of starting crew, whether or not
    /// the round resolved. See [`Outcome::leads_on_crew`].
    CrewLead,
}

impl GateCriterion {
    pub fn as_str(self) -> &'static str {
        match self {
            GateCriterion::CombatWins => "combat-wins",
            GateCriterion::CrewLead => "crew-lead",
        }
    }

    /// Rejects anything that is not one of the named criteria rather than
    /// falling back to a default the operator did not ask for.
    pub fn parse(name: &str) -> Option<GateCriterion> {
        match name {
            "combat-wins" => Some(GateCriterion::CombatWins),
            "crew-lead" => Some(GateCriterion::CrewLead),
            _ => None,
        }
    }

    /// True when a success under this criterion IS an actual combat victory,
    /// so a reader may honestly call the resulting rates win rates. False
    /// under [`GateCriterion::CrewLead`], where they are lead rates and saying
    /// "wins" would claim kills that did not happen.
    pub fn successes_are_combat_wins(self) -> bool {
        matches!(self, GateCriterion::CombatWins)
    }
}

impl std::str::FromStr for GateCriterion {
    type Err = String;

    fn from_str(name: &str) -> Result<GateCriterion, String> {
        GateCriterion::parse(name).ok_or_else(|| format!("unknown gate criterion {name}"))
    }
}

/// Everything a run decides about scoring: what ranks the population, what
/// opens a gate, and what a fight that did the enemy no net harm is worth.
///
/// The three are deliberately independent. They travel together only because
/// they are all run-owned, all recorded in one block of the run's
/// configuration, and all needed to say what a stored fitness number means.
#[derive(Copy, Clone, PartialEq, Debug, Default)]
pub struct ScoringConfig {
    /// What the population is RANKED by.
    pub fitness: Scoring,
    /// What a gate, an audit, a probe and the sampler COUNT as a success.
    pub gate: GateCriterion,
    /// Magnitude of the no-net-damage penalty. Zero, the default and what
    /// every configuration written before it existed means, disables it
    /// entirely; a positive magnitude makes a fight that left the enemy no
    /// worse off score `-magnitude`. Always in `0 ..= MAX_PENALTY`:
    /// [`ScoringConfig::from_json`] rejects a stored value that is not.
    pub no_damage_penalty: f64,
}

/// What [`ScoringConfig::no_damage_penalty`] holds when the penalty is off,
/// which is the default and the exact legacy behaviour.
pub const NO_PENALTY: f64 = 0.0;

/// The largest penalty magnitude this build accepts.
///
/// Deliberately the same number as [`RATIO_CAP`], which is the largest score
/// the scorer itself can produce: a penalty is meant to sit below the whole
/// defined range of the thing it overrides, and nothing is gained by letting
/// it be more extreme than that range is wide. The bound is also what keeps
/// fitness arithmetic finite. A panel's fitness is a SUM over its fights
/// before it is divided by their count, so an unbounded magnitude near
/// [`f64::MAX`] would overflow that sum to negative infinity, and an infinite
/// fitness cannot be compared, averaged or round-tripped through a
/// checkpoint. At this bound a sum stays finite for any panel size that fits
/// in memory.
pub const MAX_PENALTY: f64 = RATIO_CAP;

impl ScoringConfig {
    /// A configuration with the given scorer and otherwise legacy settings.
    pub fn of(fitness: Scoring) -> ScoringConfig {
        ScoringConfig {
            fitness,
            gate: GateCriterion::default(),
            no_damage_penalty: NO_PENALTY,
        }
    }

    /// True when the penalty is armed at all.
    pub fn penalises_no_damage(&self) -> bool {
        self.no_damage_penalty > 0.0
    }

    /// A magnitude this build can honour: finite, not negative, and no larger
    /// than [`MAX_PENALTY`].
    ///
    /// A negative magnitude would REWARD doing the enemy no harm, which is the
    /// opposite of what the flag means. One above the bound would let a panel
    /// of penalised fights sum past what a float can hold. Both are rejected
    /// rather than clamped into something the operator did not ask for.
    pub fn valid_penalty(magnitude: f64) -> bool {
        magnitude.is_finite() && (NO_PENALTY..=MAX_PENALTY).contains(&magnitude)
    }

    /// The run's scoring settings as the dashboard reads them. `fitness`,
    /// `gate` and `no_damage_penalty` are SETTINGS and round-trip exactly;
    /// the rest are facts about `fitness`.
    pub fn to_json(self) -> Value {
        let mut block = self.fitness.facts();
        let object = block.as_object_mut().expect("facts is an object");
        object.insert("fitness".into(), json!(self.fitness.as_str()));
        object.insert("gate".into(), json!(self.gate.as_str()));
        object.insert("no_damage_penalty".into(), json!(self.no_damage_penalty));
        block
    }

    /// Reads back [`ScoringConfig::to_json`].
    ///
    /// An absent block is the one thing that means the legacy settings: the
    /// combat scorer, the combat-wins gate and no penalty. Inside a block that
    /// IS present, an absent `gate` or `no_damage_penalty` means the legacy
    /// value of that one field, so a configuration written by the build that
    /// had the scorer but neither of the others still reads back exactly.
    ///
    /// Everything beside the three settings is a FACT ABOUT the scorer, not a
    /// setting. A stored block that disagrees with the scorer it names,
    /// `speed_bonus: true` under `crew-ratio`, say, describes a run this build
    /// cannot honour, so it is rejected rather than quietly rewritten into
    /// agreement with itself. So is an unknown scorer or criterion, and so is
    /// a penalty magnitude that is negative or not finite.
    pub fn from_json(value: Option<&Value>) -> Option<ScoringConfig> {
        let Some(block) = value else {
            return Some(ScoringConfig::default());
        };
        let fitness = Scoring::parse(block.get("fitness")?.as_str()?)?;
        let gate = match block.get("gate") {
            None => GateCriterion::default(),
            Some(stored) => GateCriterion::parse(stored.as_str()?)?,
        };
        let no_damage_penalty = match block.get("no_damage_penalty") {
            None => NO_PENALTY,
            Some(stored) => stored
                .as_f64()
                .filter(|p| ScoringConfig::valid_penalty(*p))?,
        };
        let derived = fitness.facts();
        for field in ["zero_opponent", "mutual_zero", "speed_bonus"] {
            if let Some(stored) = block.get(field) {
                if stored != &derived[field] {
                    return None;
                }
            }
        }
        Some(ScoringConfig {
            fitness,
            gate,
            no_damage_penalty,
        })
    }
}

impl std::str::FromStr for Scoring {
    type Err = String;

    fn from_str(name: &str) -> Result<Scoring, String> {
        Scoring::parse(name).ok_or_else(|| format!("unknown scorer {name}"))
    }
}

/// Who sits in the other seat. Always the graded cyborg: the aggregate this
/// run is judged on is defined against the original opponents, so there is no
/// other rival a fight could be counted against.
pub enum Rival {
    Cyborg(CyborgRating),
}

pub fn run(task: &Task, ours: &Arc<Network>, rival: Rival) -> Outcome {
    let Rival::Cyborg(rating) = rival;
    let job = Job {
        seed: task.seed,
        ticks: task.ticks,
        swap: task.swap,
        rating,
        us: task.cell.our_ship(),
        them: task.cell.their_ship(),
        // Nothing here ever flies both seats from a network, so the evaluator
        // always puts a cyborg in the other one.
        self_play: false,
    };
    let seat = task.our_seat();
    let report = eval::run_with(&job, crate::brain::SeatPilot::new(seat, ours.clone()));
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
            quick.score(ScoringConfig::of(Scoring::CrewRatio), 1200),
            slow.score(ScoringConfig::of(Scoring::CrewRatio), 3600)
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
        // A hull can end a fight holding more crew than it started with;
        // that is a real advantage and the fraction is deliberately not
        // clamped to one.
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
            lost_fast.score(ratio(), 1200),
            won_slow.score(ratio(), 1200)
        );
        // The combat scorer still separates them, unchanged.
        assert!(won_slow.score(legacy(), 1200) > lost_fast.score(legacy(), 1200));
    }

    #[test]
    fn the_default_scorer_is_the_exact_original_fitness() {
        let end = outcome(true, true, 7, 3, 900);
        assert_eq!(Scoring::default(), Scoring::Combat);
        assert_eq!(end.score(ScoringConfig::default(), 3600), end.fitness(3600));
        assert!(Scoring::Combat.rewards_speed());
        assert!(!Scoring::CrewRatio.rewards_speed());
    }

    /// The exact legacy settings: what a configuration naming none of the
    /// three means, and what every run written before them was trained under.
    fn legacy() -> ScoringConfig {
        ScoringConfig::default()
    }

    /// The crew-ratio scorer with the other two settings still legacy, so a
    /// test that names it is testing the SCORER alone.
    fn ratio() -> ScoringConfig {
        ScoringConfig::of(Scoring::CrewRatio)
    }

    #[test]
    fn the_default_settings_are_legacy_in_all_three_places() {
        let settings = ScoringConfig::default();
        assert_eq!(settings.fitness, Scoring::Combat);
        assert_eq!(settings.gate, GateCriterion::CombatWins);
        assert_eq!(settings.no_damage_penalty, NO_PENALTY);
        assert!(!settings.penalises_no_damage());
        // And naming only a scorer leaves the other two alone.
        assert_eq!(ScoringConfig::of(Scoring::CrewRatio).gate, GateCriterion::CombatWins);
        assert_eq!(ScoringConfig::of(Scoring::CrewRatio).no_damage_penalty, NO_PENALTY);
    }

    // ---------------------------------------------------------------- gate

    #[test]
    fn the_combat_wins_criterion_is_exactly_the_factual_win() {
        for won in [false, true] {
            for resolved in [false, true] {
                let end = Outcome {
                    won,
                    resolved,
                    ..fight(20, 20, 0, 20)
                };
                assert_eq!(end.succeeded(GateCriterion::CombatWins), end.won);
            }
        }
        assert!(GateCriterion::CombatWins.successes_are_combat_wins());
        assert!(!GateCriterion::CrewLead.successes_are_combat_wins());
    }

    #[test]
    fn a_crew_lead_is_of_starting_fractions_not_of_raw_crew() {
        // Eight of twelve against twenty of forty: two thirds against a half,
        // so we lead. On raw counts, 8 against 20, we would trail.
        assert!(fight(8, 12, 20, 40).leads_on_crew());
        assert!(!fight(20, 40, 8, 12).leads_on_crew());
    }

    #[test]
    fn every_crew_tie_fails_the_lead_criterion_including_a_mutual_wipeout() {
        // Equal fractions of unequal hulls: a lead is asked for, not parity.
        assert!(!fight(10, 20, 21, 42).leads_on_crew());
        assert!(!fight(20, 20, 42, 42).leads_on_crew());
        // Both wiped out. Neither side leads, so neither side succeeds.
        assert!(!fight(0, 20, 0, 42).leads_on_crew());
        assert!(!fight(0, 20, 0, 20).leads_on_crew());
        // And the one-sided cases still resolve the obvious way.
        assert!(fight(1, 20, 0, 42).leads_on_crew());
        assert!(!fight(0, 20, 1, 42).leads_on_crew());
    }

    #[test]
    fn a_crew_lead_is_exact_where_a_division_would_round() {
        // 1/3 against 1/3 expressed as fractions no binary float holds
        // exactly. The cross product settles it without rounding either side.
        let tie = fight(1, 3, 7, 21);
        assert!(!tie.leads_on_crew());
        assert!(!fight(7, 21, 1, 3).leads_on_crew());
        // And a lead of a single crew member is still a lead.
        assert!(fight(2, 3, 7, 21).leads_on_crew());
    }

    #[test]
    fn an_unresolved_fight_is_eligible_for_a_crew_lead_but_never_for_a_win() {
        let timeout = Outcome {
            resolved: false,
            won: false,
            ..fight(18, 20, 4, 20)
        };
        assert!(timeout.succeeded(GateCriterion::CrewLead));
        assert!(!timeout.succeeded(GateCriterion::CombatWins));
        // The factual fields are untouched by either criterion.
        assert!(!timeout.won);
        assert!(!timeout.resolved);
    }

    #[test]
    fn a_fight_we_won_can_still_fail_the_crew_lead_criterion() {
        // Winning on the last round while holding a smaller fraction of our
        // own complement than they hold of theirs. A criterion that quietly
        // fell back to the win would hide this.
        let won = Outcome {
            won: true,
            resolved: true,
            ..fight(2, 20, 30, 42)
        };
        assert!(won.succeeded(GateCriterion::CombatWins));
        assert!(!won.succeeded(GateCriterion::CrewLead));
    }

    #[test]
    fn a_gate_criterion_round_trips_and_an_unknown_name_is_rejected() {
        for gate in [GateCriterion::CombatWins, GateCriterion::CrewLead] {
            assert_eq!(GateCriterion::parse(gate.as_str()), Some(gate));
        }
        for bad in ["crew_lead", "crew-wins", "lead", "wins", ""] {
            assert_eq!(GateCriterion::parse(bad), None, "{bad}");
        }
        assert_eq!(GateCriterion::default(), GateCriterion::CombatWins);
    }

    // ------------------------------------------------- no-damage penalty

    fn penalised(magnitude: f64) -> ScoringConfig {
        ScoringConfig {
            fitness: Scoring::CrewRatio,
            gate: GateCriterion::CrewLead,
            no_damage_penalty: magnitude,
        }
    }

    #[test]
    fn no_net_enemy_loss_is_an_endpoint_comparison() {
        assert!(fight(20, 20, 20, 20).no_net_enemy_loss());
        assert!(!fight(20, 20, 19, 20).no_net_enemy_loss());
        assert!(!fight(20, 20, 0, 20).no_net_enemy_loss());
        // Crew they regained past their own start is still no net loss.
        assert!(fight(20, 20, 25, 20).no_net_enemy_loss());
        // What WE ended with never enters the question.
        assert!(fight(0, 20, 20, 20).no_net_enemy_loss());
    }

    #[test]
    fn the_penalty_replaces_the_score_outright_rather_than_shading_it() {
        let untouched = fight(20, 20, 20, 20);
        assert_eq!(untouched.score(penalised(1000.0), 1200), -1000.0);
        // And it beats nothing: the worst ordinary ratio, our own wipeout
        // against a full enemy, is still enormously better than the penalty.
        let wiped = fight(0, 20, 20, 20);
        assert_eq!(wiped.crew_ratio(), 0.0);
        assert!(wiped.score(penalised(1000.0), 1200) < 0.0);
        assert!(fight(0, 20, 19, 20).score(penalised(1000.0), 1200) > -1000.0);
    }

    #[test]
    fn a_penalty_of_zero_is_off_and_reproduces_the_scorer_exactly() {
        // Every shape of fight, including the one the penalty targets.
        for end in [
            fight(20, 20, 20, 20),
            fight(20, 20, 25, 20),
            fight(10, 20, 5, 20),
            fight(0, 20, 0, 20),
        ] {
            assert_eq!(end.score(penalised(NO_PENALTY), 1200), end.crew_ratio());
            assert_eq!(end.score(legacy(), 1200), end.fitness(1200));
        }
    }

    #[test]
    fn the_penalty_is_independent_of_the_scorer_and_of_the_gate() {
        let untouched = Outcome {
            won: true,
            ..fight(20, 20, 20, 20)
        };
        // It fires under the combat scorer exactly as under crew-ratio, and
        // overrides even a won fight, whose combat fitness exceeds one.
        let combat_penalised = ScoringConfig {
            fitness: Scoring::Combat,
            gate: GateCriterion::CombatWins,
            no_damage_penalty: 1000.0,
        };
        assert!(untouched.score(legacy(), 1200) > WIN_WEIGHT);
        assert_eq!(untouched.score(combat_penalised, 1200), -1000.0);
        // And the gate is decided without reference to the penalty at all.
        assert!(untouched.succeeded(GateCriterion::CombatWins));
        assert!(!untouched.succeeded(GateCriterion::CrewLead));
    }

    #[test]
    fn a_panel_of_penalised_fights_still_averages_to_a_finite_number() {
        // The trainer SUMS a panel before dividing by its size, so the bound
        // on the magnitude is what keeps that sum representable. A panel far
        // larger than any real one, at the largest magnitude allowed.
        let worst = fight(20, 20, 20, 20);
        let settings = penalised(MAX_PENALTY);
        let mut total = 0.0;
        for _ in 0..100_000 {
            total += worst.score(settings, 1200);
        }
        assert!(total.is_finite());
        assert!((total / 100_000.0).is_finite());
        assert_eq!(total / 100_000.0, -MAX_PENALTY);
    }

    #[test]
    fn a_penalty_magnitude_must_be_finite_non_negative_and_bounded() {
        assert!(ScoringConfig::valid_penalty(NO_PENALTY));
        assert!(ScoringConfig::valid_penalty(1000.0));
        assert!(ScoringConfig::valid_penalty(MAX_PENALTY));
        // A negative magnitude would REWARD leaving the enemy untouched.
        assert!(!ScoringConfig::valid_penalty(-1.0));
        // An unbounded one would overflow a summed panel to minus infinity.
        assert!(!ScoringConfig::valid_penalty(MAX_PENALTY + 1.0));
        assert!(!ScoringConfig::valid_penalty(f64::MAX));
        assert!(!ScoringConfig::valid_penalty(f64::INFINITY));
        assert!(!ScoringConfig::valid_penalty(f64::NEG_INFINITY));
        assert!(!ScoringConfig::valid_penalty(f64::NAN));
        assert_eq!(MAX_PENALTY, RATIO_CAP);
    }

    // ------------------------------------------------------- serialisation

    #[test]
    fn every_setting_round_trips_and_an_unknown_name_is_rejected() {
        for fitness in [Scoring::Combat, Scoring::CrewRatio] {
            for gate in [GateCriterion::CombatWins, GateCriterion::CrewLead] {
                for no_damage_penalty in [NO_PENALTY, 1000.0] {
                    let settings = ScoringConfig {
                        fitness,
                        gate,
                        no_damage_penalty,
                    };
                    let block = settings.to_json();
                    assert_eq!(ScoringConfig::from_json(Some(&block)), Some(settings));
                    assert_eq!(block["fitness"], fitness.as_str());
                    assert_eq!(block["gate"], gate.as_str());
                    assert_eq!(block["no_damage_penalty"], no_damage_penalty);
                    assert_eq!(block["speed_bonus"], fitness.rewards_speed());
                }
            }
        }
        assert_eq!(Scoring::parse("crew_ratio"), None);
        assert_eq!(Scoring::parse("ratio"), None);
        assert_eq!(Scoring::parse(""), None);
        for bad in [
            json!({"fitness": "kills"}),
            json!({}),
            json!({"fitness": "combat", "gate": "crew_lead"}),
            json!({"fitness": "combat", "gate": "kills"}),
            json!({"fitness": "combat", "gate": 7}),
        ] {
            assert_eq!(ScoringConfig::from_json(Some(&bad)), None, "{bad}");
        }
    }

    #[test]
    fn an_absent_block_and_absent_fields_mean_exactly_the_legacy_settings() {
        // The whole block absent: a configuration older than any of the three.
        assert_eq!(ScoringConfig::from_json(None), Some(legacy()));
        // The block present but naming only the scorer: written by the build
        // that had the scorer and neither of the others. It must still read
        // back as that scorer gated on wins with no penalty.
        assert_eq!(
            ScoringConfig::from_json(Some(&json!({"fitness": "crew-ratio"}))),
            Some(ratio())
        );
        assert_eq!(
            ScoringConfig::from_json(Some(&json!({"fitness": "crew-ratio",
                                                  "speed_bonus": false,
                                                  "zero_opponent": RATIO_WIPEOUT,
                                                  "mutual_zero": RATIO_MUTUAL,
                                                  "gate": "combat-wins"}))),
            Some(ratio())
        );
        // One setting named, the other still absent, either way round.
        assert_eq!(
            ScoringConfig::from_json(Some(&json!({"fitness": "combat", "gate": "crew-lead"}))),
            Some(ScoringConfig {
                fitness: Scoring::Combat,
                gate: GateCriterion::CrewLead,
                no_damage_penalty: NO_PENALTY
            })
        );
        assert_eq!(
            ScoringConfig::from_json(Some(&json!({"fitness": "combat",
                                                  "no_damage_penalty": 1000.0}))),
            Some(ScoringConfig {
                fitness: Scoring::Combat,
                gate: GateCriterion::CombatWins,
                no_damage_penalty: 1000.0
            })
        );
    }

    #[test]
    fn a_stored_penalty_this_build_cannot_honour_is_rejected() {
        for bad in [
            json!({"fitness": "crew-ratio", "no_damage_penalty": -1.0}),
            json!({"fitness": "crew-ratio", "no_damage_penalty": MAX_PENALTY + 1.0}),
            json!({"fitness": "crew-ratio", "no_damage_penalty": "1000"}),
            json!({"fitness": "crew-ratio", "no_damage_penalty": Value::Null}),
        ] {
            assert_eq!(ScoringConfig::from_json(Some(&bad)), None, "{bad}");
        }
    }

    #[test]
    fn a_block_that_contradicts_the_scorer_it_names_is_rejected() {
        // Each of these describes a run this build does not implement, so
        // reading it as "crew-ratio, and never mind the rest" would misreport
        // what produced the checkpoint's fitness numbers. Only the DERIVED
        // facts are checked this way; gate and penalty are settings and may
        // legitimately be anything this build implements.
        for bad in [
            json!({"fitness": "crew-ratio", "speed_bonus": true}),
            json!({"fitness": "crew-ratio", "zero_opponent": 7}),
            json!({"fitness": "crew-ratio", "mutual_zero": 0}),
            json!({"fitness": "combat", "speed_bonus": false}),
            json!({"fitness": "combat", "zero_opponent": 1000}),
        ] {
            assert_eq!(ScoringConfig::from_json(Some(&bad)), None, "{bad}");
        }
        // A gate that disagrees with nothing is NOT a contradiction: it is a
        // setting, and this is exactly the combination the staged run uses.
        assert_eq!(
            ScoringConfig::from_json(Some(&json!({"fitness": "crew-ratio",
                                                  "gate": "crew-lead",
                                                  "no_damage_penalty": 1000.0}))),
            Some(ScoringConfig {
                fitness: Scoring::CrewRatio,
                gate: GateCriterion::CrewLead,
                no_damage_penalty: 1000.0
            })
        );
    }

    #[test]
    fn the_json_names_the_special_cases_only_where_they_exist() {
        let ratio = ratio().to_json();
        assert_eq!(ratio["zero_opponent"], json!(RATIO_WIPEOUT));
        assert_eq!(ratio["mutual_zero"], json!(RATIO_MUTUAL));
        let combat = legacy().to_json();
        assert!(combat["zero_opponent"].is_null());
        assert!(combat["mutual_zero"].is_null());
    }
}
