//! The `/api/status` and `/api/network` documents.
//!
//! Two rules the dashboard depends on:
//!
//!   * The graded question is the balanced AGGREGATE in `overall`, and it is
//!     stated there ONCE. The `matchups` list carries training exposure and
//!     per-hull diagnostics; no number in it gates anything, and none of it may
//!     be read as per-matchup mastery.
//!   * A measurement that has not been made is `null`, never zero. Zero means
//!     "measured, and it was zero".

use crate::broad::{self, Cell, Evaluation, Source};
use crate::genome::{Genome, N_MEMORY};
use crate::phases::Spent;
use crate::trainer::{iso8601, Mode, Trainer};
use serde_json::{json, Value};

/// Bumped when the shape of the published documents changes. Version 2 dropped
/// the staged ladder: there is no `curriculum` object, no `regression` object
/// and no per-matchup audit evidence, because none of those measurements
/// exists any more. Version 3 dropped what was left over from it: the `audit`
/// object and the champion's `validated_*` figures, which restated `overall`
/// word for word, the combat-win window, and a handful of constants that a
/// reader could only ever read back unchanged. A reader that wants an earlier
/// version is asking for numbers this engine does not produce, and should be
/// told so rather than shown zeroes.
pub const SCHEMA_VERSION: i64 = 3;

/// The phase the SERVER reports, which includes the two states the trainer
/// itself has no opinion about: paused by an operator, and stopped.
///
/// Every variant has a producer. A start that fails never publishes at all, it
/// exits with the reason on stderr, so there is no "error" phase to report and
/// none is representable.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Phase {
    Initializing,
    Training,
    Auditing,
    Paused,
    Stopped,
}

impl Phase {
    pub fn as_str(self) -> &'static str {
        match self {
            Phase::Initializing => "initializing",
            Phase::Training => "training",
            Phase::Auditing => "auditing",
            Phase::Paused => "paused",
            Phase::Stopped => "stopped",
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
            // Null, not an empty string: there is no candidate to name yet.
            "champion_id": champion.clone(),
            "passed": cleared_by.is_some() && cleared_by == champion,
            "passed_by": cleared_by,
            "audit": summary(self.broad_audit.as_ref()),
            "confirm": summary(self.broad_confirm.as_ref()),
            "attempt": self.audit_attempt
        })
    }

    pub fn status(&self, phase: Phase, message: &str, checkpoint: &str, stale: bool) -> Value {
        let board = broad::board();
        let per_second = if self.elapsed > 0.0 {
            self.episodes as f64 / self.elapsed
        } else {
            0.0
        };
        // What this session spent, on both clocks. A process that has burned
        // no CPU has not measured zero nanoseconds per tick, it has measured
        // nothing, so an unmeasured CPU total is None and every rate built on
        // it comes out null.
        let session = Spent::new(
            self.session_compute,
            (self.session_cpu > 0.0).then_some(self.session_cpu),
        );

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
            // FACTUAL combat victories over the whole run, whatever the
            // configured gate counts. Under the crew-lead criterion every
            // other success number in this document means a crew lead rather
            // than a win, and this is the only field that may be labelled a
            // combat win.
            "episodes_combat_wins": self.combat_wins,
            "elapsed_seconds": self.elapsed,
            "episodes_per_second": per_second,
            "updated_at": iso8601(unix_now()),
            "stale": stale,
            // What the population is RANKED by, what a gate, an audit, a
            // probe and the sampler COUNT as a success, and what a fight that
            // did the enemy no net harm is worth. Always present: a run that
            // predates any of the three cannot be resumed by this build at all.
            //
            // `gate` is what every other success number here means. When it is
            // "crew-lead", each wins/games/win_rate/lower_bound field below,
            // and both history rates, counts fights we ENDED AHEAD ON CREW,
            // not fights we won; a reader that labels them wins is claiming
            // kills that did not happen.
            "scoring": self.config.scoring.to_json(),
            // The board every generation trains on, in full, from generation
            // one. There is no schedule to report and nothing here is earned:
            // `total_matchups` is what is ACTIVE, never what is mastered. The
            // target it is judged against is stated in `overall`, beside the
            // numbers it judges.
            "board": {
                "total_matchups": board.len()
            },
            // What the champion IS. What it has been shown to do is `overall`
            // and nothing here restates it: the held-out numbers were reported
            // in both places, word for word, off the same evidence.
            //
            // No champion means no topology, so every figure is null rather
            // than zero: a zero here would read as a graph with no nodes.
            "champion": match self.champion.as_ref() {
                None => json!({"id": Value::Null, "nodes": Value::Null,
                               "connections": Value::Null, "hidden_nodes": Value::Null}),
                Some(genome) => json!({
                    "id": genome.fingerprint(),
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
                // Extension: what the cap actually came to.
                "measured_duty": number((self.elapsed > 0.0)
                    .then(|| self.compute / self.elapsed)),
                "compute_seconds": self.compute,
                "episode_ticks": self.config.ticks,
                "nice": self.nice
            },
            // Machine independent work THIS process has done, and where its
            // compute seconds went. Both are session figures and both say so:
            // they are never checkpointed, because averaging a week of one
            // machine's load into this afternoon's nanoseconds-per-tick would
            // be a lie rather than a summary.
            //
            // `episodes_per_second` above is unchanged and still wall-clock,
            // so nothing that reads this document breaks; it is simply not the
            // number to optimise against on a machine whose load nobody
            // controls. These are.
            //
            // Both are null, not zero, when this process has not computed:
            // reading a checkpoint from disk is such a process, and a document
            // full of zeroes would claim a measurement of no work rather than
            // no measurement.
            "work": match session.measured() {
                true => self.work.to_json(session),
                false => Value::Null,
            },
            "phases": match session.measured() {
                true => self.phases.to_json(session),
                false => Value::Null,
            },
            // The round in flight is `overall.round`, and how far it has got is
            // `overall.wins` over `overall.games`. There is no second place
            // that says it.
            "readiness": {
                "threshold": self.config.readiness_threshold,
                "games": self.config.readiness_games,
                "last_rate": number(self.last_validation),
                "period": self.config.readiness_period
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
    /// anything, so no row carries a verdict: a cell with no games reads as a
    /// null win rate over zero games, which is the whole of what is known
    /// about it.
    fn matchups(&self, board: &[Cell]) -> Vec<Value> {
        board
            .iter()
            .map(|cell| {
                let stat = self.stats.cells.get(cell).copied().unwrap_or_default();
                json!({
                    "us": cell.our_ship().name(),
                    "them": cell.their_ship().name(),
                    "opponent_type": cell.foe.as_str(),
                    "sample_weight": broad::weight(&stat),
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

/// Stable names for the input slots, so a topology diagram can say what a link
/// actually reads. The observation names come straight from the encoder rather
/// than being restated here; this function only adds the explicit feedback the
/// contract fixes after them.
pub fn input_labels() -> Vec<String> {
    let mut labels = melee_neat::encode::slot_names();
    for name in ["left", "right", "thrust", "weapon", "special"] {
        labels.push(format!("previous {name}"));
    }
    for channel in 0..N_MEMORY {
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
    use crate::brain::{BIAS_SLOT, CONTROL_BASE, MEMORY_BASE};
    use crate::genome::{N_INPUT, N_OBS};

    #[test]
    fn the_label_lists_match_the_fixed_slot_counts() {
        let inputs = input_labels();
        assert_eq!(inputs.len(), N_INPUT as usize);
        assert_eq!(inputs[N_OBS - 1], "their hull bit 4");
        assert_eq!(inputs[CONTROL_BASE], "previous left");
        assert_eq!(inputs[MEMORY_BASE], "previous memory 0");
        assert_eq!(inputs[BIAS_SLOT], "bias");
        let outputs = output_labels();
        assert_eq!(outputs.len(), 13);
        assert_eq!(outputs[4], "special");
        assert_eq!(outputs[5], "memory 0");
    }
}
