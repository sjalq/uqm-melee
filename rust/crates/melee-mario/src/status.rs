//! The `/api/status` and `/api/network` documents.
//!
//! Two rules the dashboard depends on:
//!
//!   * The graded question is the balanced AGGREGATE in `overall`. The
//!     `matchups` list carries training exposure and per-hull diagnostics; no
//!     number in it gates anything, and none of it may be read as per-matchup
//!     mastery.
//!   * A measurement that has not been made is `null`, never zero. Zero means
//!     "measured, and it was zero".

use crate::audit::{max_losses, Round};
use crate::broad::{self, Cell, Evaluation, Source};
use crate::genome::Genome;
use crate::trainer::{iso8601, Mode, Trainer};
use serde_json::{json, Value};

/// Bumped when the shape of the published documents changes. Version 2 dropped
/// the staged ladder: there is no `curriculum` object, no `regression` object
/// and no per-matchup audit evidence, because none of those measurements
/// exists any more. A reader that still wants version 1 is asking for numbers
/// this engine does not produce, and should be told so rather than shown
/// zeroes.
pub const SCHEMA_VERSION: i64 = 2;

/// The phase the SERVER reports, which includes states the trainer itself has
/// no opinion about (paused by an operator, stopped, failed to start).
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Phase {
    Initializing,
    Training,
    Auditing,
    Paused,
    Stopped,
    Error,
}

impl Phase {
    pub fn as_str(self) -> &'static str {
        match self {
            Phase::Initializing => "initializing",
            Phase::Training => "training",
            Phase::Auditing => "auditing",
            Phase::Paused => "paused",
            Phase::Stopped => "stopped",
            Phase::Error => "error",
        }
    }
}

fn number(value: Option<f64>) -> Value {
    match value {
        Some(n) if n.is_finite() => json!(n),
        _ => Value::Null,
    }
}

impl Trainer {
    /// The round in flight, as (round, games played, games declared).
    fn auditing_now(&self) -> Option<(Round, u32, u32)> {
        match &self.mode {
            Mode::Overall { gate } => Some((
                gate.round,
                gate.evaluation.games,
                gate.tasks.len() as u32,
            )),
            _ => None,
        }
    }

    /// The champion's HELD-OUT evidence: the round in flight if there is one,
    /// otherwise the most recent finished gate round. A readiness probe is
    /// deliberately not among them, because it is a cheap diagnostic on its own
    /// stream and reporting it as validated evidence would flatter the
    /// champion with numbers that never gated anything.
    fn shown_gate_evidence(&self) -> Option<&Evaluation> {
        if let Mode::Overall { gate } = &self.mode {
            return Some(&gate.evaluation);
        }
        self.broad_confirm.as_ref().or(self.broad_audit.as_ref())
    }

    /// The balanced evaluation the per-hull diagnostics table should show: the
    /// round in flight if there is one, otherwise whichever finished reading
    /// `broad_shown` names. All of them belong to the current champion.
    fn shown_evaluation(&self) -> Option<&Evaluation> {
        if let Mode::Overall { gate } = &self.mode {
            return Some(&gate.evaluation);
        }
        match self.broad_shown? {
            Source::Ready => self.broad_ready.as_ref(),
            Source::Audit => self.broad_audit.as_ref(),
            Source::Confirm => self.broad_confirm.as_ref(),
        }
    }

    /// The `overall` object: the one graded question this run answers.
    fn overall_json(&self) -> Value {
        let config = self.config.broad;
        let champion = self.champion.as_ref().map(Genome::fingerprint);
        let live = match &self.mode {
            Mode::Overall { gate } => Some(gate),
            _ => None,
        };
        // The headline numbers describe the round in flight, or the most recent
        // finished one, never a pool of several.
        let current = live.map(|gate| &gate.evaluation).or(self
            .broad_confirm
            .as_ref()
            .or(self.broad_audit.as_ref()));
        let tally = current.map(Evaluation::tally).unwrap_or_default();
        let summary = |reading: Option<&Evaluation>| match reading {
            None => json!({"wins": 0, "games": 0, "win_rate": Value::Null,
                           "lower_bound": Value::Null, "passed": false}),
            Some(reading) => {
                let tally = reading.tally();
                json!({"wins": tally.wins, "games": tally.games,
                       "win_rate": number(tally.rate()),
                       "lower_bound": number(tally.lower_bound()),
                       "passed": tally.lower_bound()
                           .is_some_and(|bound| bound > config.target)})
            }
        };
        // "Passed" means the CURRENT champion cleared both rounds. A gate
        // cleared by an earlier champion is reported by name, not inherited.
        let cleared_by = self.broad_gate.as_ref().map(|e| e.champion.clone());
        json!({
            "scope": "balanced-any-any",
            "target": config.target,
            "panel": config.games(),
            "pairs": config.pairs,
            "round": live.map(|gate| gate.round.as_str()),
            "wins": tally.wins,
            "games": tally.games,
            "win_rate": number(tally.rate()),
            "lower_bound": number(tally.lower_bound()),
            "champion_id": champion.clone().unwrap_or_default(),
            "passed": cleared_by.is_some() && cleared_by == champion,
            "passed_by": cleared_by,
            "audit": summary(self.broad_audit.as_ref()),
            "confirm": summary(self.broad_confirm.as_ref()),
            "attempt": self.audit_attempt
        })
    }

    pub fn status(&self, phase: Phase, message: &str, checkpoint: &str, stale: bool) -> Value {
        let target = self.config.broad.target;
        let board = broad::board();
        // The champion's validated numbers are its HELD-OUT balanced evidence,
        // which is the only evidence in the run that was withheld from
        // training. Training exposure is reported per matchup and never here.
        let aggregate = self
            .shown_gate_evidence()
            .map(Evaluation::tally)
            .unwrap_or_default();
        let per_second = if self.elapsed > 0.0 {
            self.episodes as f64 / self.elapsed
        } else {
            0.0
        };

        json!({
            "schema_version": SCHEMA_VERSION,
            "run_id": self.config.run_id,
            "phase": phase.as_str(),
            "message": message,
            "generation": self.population.generation,
            "episodes": self.episodes,
            // Extension: fights that reached no victory, the tick ceiling and
            // the evaluator's Selecting phase alike. Never counted as wins.
            "episodes_unresolved": self.unresolved,
            // FACTUAL combat victories, whatever the configured gate counts.
            // Under the crew-lead criterion every other success number in this
            // document means a crew lead rather than a win, and these three
            // fields are the only ones that may be labelled combat wins.
            //
            // The count covers the window that opens at `counted_since`, which
            // is zero, and therefore all time, for any run that started under
            // a build with this counter. `all_time` is the same number when
            // the window is the whole run and NULL otherwise, so a resumed
            // legacy checkpoint cannot have its partial post-resume count read
            // against its all-time episode total.
            "episodes_combat_wins": self.combat_wins,
            "episodes_combat_counted_since": self.combat_counted_since,
            "episodes_combat_wins_all_time": match self.combat_counted_since {
                0 => json!(self.combat_wins),
                _ => Value::Null,
            },
            "elapsed_seconds": self.elapsed,
            "episodes_per_second": per_second,
            "updated_at": iso8601(unix_now()),
            "stale": stale,
            // What the population is RANKED by, what a gate, an audit, a
            // probe and the sampler COUNT as a success, and what a fight that
            // did the enemy no net harm is worth. A run whose configuration
            // predates any of the three reads back as the combat scorer gated
            // on combat wins with no penalty, which is what it was in fact
            // trained under; the block is absent only when the binary serving
            // the document predates the field entirely.
            //
            // `gate` is what every other success number here means. When it is
            // "crew-lead", each wins/games/win_rate/lower_bound field below,
            // and both history rates, counts fights we ENDED AHEAD ON CREW,
            // not fights we won; a reader that labels them wins is claiming
            // kills that did not happen.
            "scoring": self.config.scoring.to_json(),
            // The board every generation trains on, in full, from generation
            // one. There is no schedule to report and nothing here is earned:
            // `total_matchups` is what is ACTIVE, never what is mastered.
            "board": {
                "total_matchups": board.len(),
                "target": target,
                "evaluation_scope": "overall-balanced"
            },
            "champion": match self.champion.as_ref() {
                None => json!({"id": "", "validated_wins": 0, "validated_games": 0,
                               "win_rate": Value::Null, "lower_bound": Value::Null,
                               "nodes": 0, "connections": 0}),
                Some(genome) => json!({
                    "id": genome.fingerprint(),
                    "validated_wins": aggregate.wins,
                    "validated_games": aggregate.games,
                    "win_rate": number(aggregate.rate()),
                    "lower_bound": number(aggregate.lower_bound()),
                    "nodes": genome.nodes.len(),
                    "connections": genome.enabled_count(),
                    "hidden_nodes": genome.hidden_count()
                }),
            },
            "population": {
                "size": self.population.size(),
                "species": self.population.species.len(),
                "mean_nodes": self.population.mean_nodes(),
                "mean_connections": self.population.mean_connections()
            },
            "checkpoint": {
                "saved_at": self.saved_at,
                // The generation a resume would start from. With a save cadence
                // this trails the generation in memory, and reporting the
                // in-memory one would tell the operator a crash costs nothing.
                "generation": self.saved_generation,
                "resumable": self.saved_at.is_some(),
                "path": checkpoint
            },
            "resources": {
                // The ACTUAL size of the evaluation pool, not a request: one
                // means no worker threads exist at all. `measured_duty` stays
                // the scheduler's active WALL fraction, so it describes when
                // the evaluator was computing and never how many cores were
                // busy while it did; `workers` times `duty_cycle` is a
                // capacity ceiling, not an observation.
                "workers": self.pool.workers(),
                "duty_cycle": self.config.duty,
                // Extensions: what the cap covers, and what it actually came to.
                "covers": ["training", "readiness", "audit", "confirm"],
                "measured_duty": number((self.elapsed > 0.0)
                    .then(|| self.compute / self.elapsed)),
                "compute_seconds": self.compute,
                "episode_ticks": self.config.ticks,
                "nice": self.nice
            },
            // The round in flight, if one is. `spent` and `panel` are games,
            // not matchups: the gate is one number over a distribution.
            "audit": match self.auditing_now() {
                None => json!({"round": Value::Null, "spent": 0,
                               "panel": self.config.broad.games(),
                               "max_losses": max_losses(self.config.broad.games() as u32, target)}),
                Some((round, spent, panel)) => json!({
                    "round": round.as_str(), "spent": spent,
                    "panel": panel,
                    "max_losses": max_losses(panel, target)
                }),
            },
            "readiness": {
                "threshold": self.config.readiness_threshold,
                "games": self.config.readiness_games,
                "last_rate": number(self.last_validation),
                "period": self.config.readiness_period,
                // One meaning only: is this champion worth spending a held-out
                // balanced round on. It is never evidence for one.
                "purpose": "balanced readiness"
            },
            "history": self.history.iter().map(|row| json!({
                "generation": row.generation,
                "training_win_rate": number(row.training_win_rate),
                "validation_win_rate": number(row.validation_win_rate),
                "species": row.species,
                "nodes": row.nodes,
                "episodes": row.episodes
            })).collect::<Vec<_>>(),
            // The aggregate gate: the one graded question.
            "overall": self.overall_json(),
            // Per-hull blind-spot diagnostics from the balanced evaluation
            // currently being shown. `wins` is always OUR policy's wins:
            // side "ours" groups by the hull it piloted, side "opponent" by the
            // hull it faced. Empty until a balanced reading has been taken.
            "ship_performance": match self.shown_evaluation() {
                Some(reading) => Value::Array(broad::ship_rows(reading)),
                None => Value::Array(Vec::new()),
            },
            // How the training panel is built. `coverage` is the SHARE of the
            // panel reserved for the balanced rotation, not how much of the
            // board has been seen.
            "sampler": json!({"panel": self.config.broad.panel,
                              "coverage": self.config.broad.coverage,
                              "cursor": self.coverage_cursor,
                              "tour": self.coverage_cursor / broad::BOARD as u64}),
            "matchups": self.matchups(&board),
            "events": self.events.iter().rev().map(|e| json!({
                "at": e.at, "message": e.message
            })).collect::<Vec<_>>()
        })
    }

    /// One row per ordered matchup. Every number here is TRAINING exposure:
    /// how much of the panel a cell attracts, how many decayed games it has
    /// and how they went. None of it is held-out evidence and none of it gates
    /// anything, so no row is ever "mastered".
    fn matchups(&self, board: &[Cell]) -> Vec<Value> {
        board
            .iter()
            .map(|cell| {
                let stat = self.stats.cells.get(cell).copied().unwrap_or_default();
                json!({
                    "us": cell.our_ship().name(),
                    "them": cell.their_ship().name(),
                    "opponent_type": cell.foe.as_str(),
                    "status": if stat.games > 0.0 { "learning" } else { "unseen" },
                    "sample_weight": broad::weight(&self.config.broad, &stat),
                    "training_games": stat.games,
                    "training_win_rate": number(
                        stat.games.gt(&0.0).then(|| stat.wins / stat.games)
                    )
                })
            })
            .collect()
    }

    pub fn network(&self) -> Value {
        match self.champion.as_ref() {
            None => json!({"schema_version": SCHEMA_VERSION, "champion_id": Value::Null,
                           "genome": Value::Null, "input_labels": input_labels(),
                           "output_labels": output_labels()}),
            Some(genome) => json!({
                "schema_version": SCHEMA_VERSION,
                "champion_id": genome.fingerprint(),
                "genome": genome.to_json(),
                "input_labels": input_labels(),
                "output_labels": output_labels()
            }),
        }
    }
}

fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Stable names for the 57 input slots, so a topology diagram can say what a
/// link actually reads. Slots 33..42 are the two five-bit hull identifiers and
/// slots 43..55 are the explicit feedback the contract fixes.
pub fn input_labels() -> Vec<String> {
    const SENSORS: [&str; 33] = [
        "our energy",
        "our crew",
        "our facing cos",
        "our facing sin",
        "our speed",
        "our travel cos",
        "our travel sin",
        "weapon ready",
        "special ready",
        "turn ready",
        "thrust ready",
        "delta x",
        "delta y",
        "distance",
        "closing speed",
        "their facing cos",
        "their facing sin",
        "their energy",
        "their crew",
        "their speed",
        "we are cloaked",
        "our shot hits soon",
        "our shot hits in range",
        "turn toward them",
        "their shot hits soon",
        "their shot hits in range",
        "planet delta x",
        "planet delta y",
        "planet impact",
        "incoming impact",
        "incoming angle cos",
        "incoming angle sin",
        "constant one",
    ];
    let mut labels: Vec<String> = SENSORS.iter().map(|s| s.to_string()).collect();
    for bit in 0..5 {
        labels.push(format!("our hull bit {bit}"));
    }
    for bit in 0..5 {
        labels.push(format!("their hull bit {bit}"));
    }
    for name in ["left", "right", "thrust", "weapon", "special"] {
        labels.push(format!("previous {name}"));
    }
    for channel in 0..8 {
        labels.push(format!("previous memory {channel}"));
    }
    labels.push("bias".to_string());
    labels
}

pub fn output_labels() -> Vec<String> {
    let mut labels: Vec<String> = ["left", "right", "thrust", "weapon", "special"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    for channel in 0..8 {
        labels.push(format!("memory {channel}"));
    }
    labels
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_label_lists_match_the_fixed_slot_counts() {
        let inputs = input_labels();
        assert_eq!(inputs.len(), 57);
        assert_eq!(inputs[32], "constant one");
        assert_eq!(inputs[33], "our hull bit 0");
        assert_eq!(inputs[38], "their hull bit 0");
        assert_eq!(inputs[43], "previous left");
        assert_eq!(inputs[48], "previous memory 0");
        assert_eq!(inputs[56], "bias");
        let outputs = output_labels();
        assert_eq!(outputs.len(), 13);
        assert_eq!(outputs[4], "special");
        assert_eq!(outputs[5], "memory 0");
    }

}
