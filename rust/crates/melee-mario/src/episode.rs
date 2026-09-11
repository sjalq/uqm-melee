//! Running one fight and scoring it.
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
}

pub const WIN_WEIGHT: f64 = 1.0;
pub const CREW_WEIGHT: f64 = 0.2;
pub const SPEED_WEIGHT: f64 = 0.02;

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
}
