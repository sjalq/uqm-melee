//! The `/api/status` and `/api/network` documents.
//!
//! Two rules the dashboard depends on:
//!
//!   * `matchups[].wins/games` is CHAMPION AUDIT evidence only. Training
//!     results from a whole population are a different measurement with a
//!     different denominator and never appear there; `sample_weight` is the
//!     only sampling-derived number in the list.
//!   * A measurement that has not been made is `null`, never zero. Zero means
//!     "measured, and it was zero".

use crate::audit::{wilson_lower, Round, Tally};
use crate::curriculum::{self, Cell, Opponent};
use crate::sampler::{self, CellStat};
use crate::trainer::{iso8601, Ladder, Mode, Trainer};
use serde_json::{json, Value};
use std::collections::BTreeMap;

pub const SCHEMA_VERSION: i64 = 1;

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
    /// Aggregate champion audit evidence. Reported because the schema asks for
    /// it, but never used to decide mastery: `mastered_matchups` is the number
    /// that matters and it is counted cell by cell.
    pub fn champion_evidence(&self) -> Tally {
        self.all_evidence()
            .values()
            .fold(Tally::default(), |total, tally| Tally {
                wins: total.wins + tally.wins,
                games: total.games + tally.games,
            })
    }

    /// Confirmed evidence merged with whatever the live gate has gathered so
    /// far, so the board updates while an audit is running.
    pub fn all_evidence(&self) -> BTreeMap<Cell, Tally> {
        let mut merged = self.evidence.clone();
        if let Mode::Auditing { gate } = &self.mode {
            for (cell, tally) in gate.evidence() {
                merged.insert(*cell, *tally);
            }
        }
        merged
    }

    fn auditing_now(&self) -> Option<(Round, u32, u32)> {
        match &self.mode {
            Mode::Auditing { gate } => Some((gate.round, gate.spent, gate.config.budget)),
            _ => None,
        }
    }

    pub fn status(&self, phase: Phase, message: &str, checkpoint: &str, stale: bool) -> Value {
        let target = self.config.audit.target;
        let evidence = self.all_evidence();
        let (mine, yours) = curriculum::counts(self.stage);
        let (next_side, next_ship) = curriculum::next_addition(self.stage);
        let active = self.cyborg_cells();
        let models = self.model_cells();
        let mastered = evidence
            .iter()
            .filter(|(cell, tally)| {
                cell.foe == Opponent::Cyborg
                    && tally.lower_bound().is_some_and(|bound| bound > target)
            })
            .count();
        let worst = active
            .iter()
            .map(|cell| evidence.get(cell).and_then(|t| t.lower_bound()))
            .min_by(|a, b| {
                a.unwrap_or(-1.0)
                    .total_cmp(&b.unwrap_or(-1.0))
            })
            .flatten();
        let aggregate = self.champion_evidence();
        let per_second = if self.elapsed > 0.0 {
            self.episodes as f64 / self.elapsed
        } else {
            0.0
        };
        let opponent_types: Vec<&str> = if models.is_empty() {
            vec!["cyborg"]
        } else {
            vec!["cyborg", "model"]
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
            "elapsed_seconds": self.elapsed,
            "episodes_per_second": per_second,
            "updated_at": iso8601(unix_now()),
            "stale": stale,
            "curriculum": {
                "stage": self.stage,
                "our_roster": curriculum::roster_names(&curriculum::ours(), mine),
                "opponent_roster": curriculum::roster_names(&curriculum::theirs(), yours),
                "opponent_types": opponent_types,
                "next_side": if self.ladder == Ladder::Mixed { "complete" } else { next_side },
                "next_ship": next_ship.map(|s| s.name()),
                "target": target,
                "mastered_matchups": mastered,
                "total_matchups": active.len(),
                // Extensions: the ladder phase and the frozen opponent it plays.
                "ladder": self.ladder.as_str(),
                "opponent_revision": self.opponent_revision,
                "opponent_fingerprint": self.frozen_opponent.as_ref().map(|g| g.fingerprint()),
                // A policy is never asked to beat an identical copy of itself
                // 80% of the time, so self play is never a mastery criterion.
                "self_play_is_gated": false
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
                    // Extension: the honest gating number. A pooled rate can sit
                    // above the target while one matchup is still losing.
                    "worst_cell_lower_bound": number(worst),
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
                "generation": self.population.generation,
                "resumable": self.saved_at.is_some(),
                "path": checkpoint
            },
            "resources": {
                "workers": 1,
                "duty_cycle": self.config.duty,
                // Extensions: what the cap covers, and what it actually came to.
                "covers": ["training", "readiness", "audit", "self_play"],
                "measured_duty": number((self.elapsed > 0.0)
                    .then(|| self.compute / self.elapsed)),
                "compute_seconds": self.compute,
                "episode_ticks": self.config.ticks,
                "nice": self.nice
            },
            "audit": match self.auditing_now() {
                None => json!({"round": Value::Null, "spent": 0,
                               "budget": self.config.audit.budget,
                               "panel": self.config.audit.panel,
                               "max_losses": max_losses(self.config.audit.panel, target)}),
                Some((round, spent, budget)) => json!({
                    "round": round.as_str(), "spent": spent, "budget": budget,
                    "panel": self.config.audit.panel,
                    "max_losses": max_losses(self.config.audit.panel, target)
                }),
            },
            "readiness": {
                "threshold": self.config.readiness_threshold,
                "games": self.config.readiness_games,
                "last_rate": number(self.last_validation),
                "period": self.config.readiness_period,
                // What the probe means depends on the phase, so say which.
                "purpose": if self.ladder == Ladder::Mixed {
                    "cyborg regression alarm"
                } else {
                    "audit readiness"
                }
            },
            "regression": {
                // Mixed-phase only. A sweep gates nothing; these numbers say
                // whether a policy training against a frozen copy of itself
                // still beats the original Awesome cyborgs.
                "active": self.ladder == Ladder::Mixed,
                "budget": self.config.regression_budget,
                "last_swept": self.regression_swept,
                "last_failed": self.regression_failed,
                "rehearsing": self.priority.len(),
                "sweeping": self.round() == Some(Round::Regression)
            },
            "history": self.history.iter().map(|row| json!({
                "generation": row.generation,
                "stage": row.stage,
                "training_win_rate": number(row.training_win_rate),
                "validation_win_rate": number(row.validation_win_rate),
                "species": row.species,
                "nodes": row.nodes,
                "episodes": row.episodes
            })).collect::<Vec<_>>(),
            "matchups": self.matchups(&evidence, &active, &models, target),
            "events": self.events.iter().rev().map(|e| json!({
                "at": e.at, "message": e.message
            })).collect::<Vec<_>>()
        })
    }

    fn matchups(
        &self,
        evidence: &BTreeMap<Cell, Tally>,
        active: &[Cell],
        models: &[Cell],
        target: f64,
    ) -> Vec<Value> {
        let auditing = match &self.mode {
            Mode::Auditing { gate } => gate.order.clone(),
            _ => Vec::new(),
        };
        let generation = self.population.generation;
        active
            .iter()
            .chain(models.iter())
            .map(|cell| {
                let tally = evidence.get(cell).copied().unwrap_or_default();
                let stat = self.stats.cells.get(cell).copied().unwrap_or(CellStat {
                    wins: 0.0,
                    games: 0.0,
                    added: generation,
                });
                let status = if cell.foe == Opponent::Model {
                    // Frozen-model cells are never gated, so they are never
                    // "mastered"; they are rehearsal, not evidence.
                    "learning"
                } else if tally.lower_bound().is_some_and(|b| b > target) {
                    "mastered"
                } else if auditing.contains(cell) && tally.games > 0 {
                    "auditing"
                } else if tally.games > 0 || stat.games > 0.0 {
                    "learning"
                } else {
                    "unseen"
                };
                json!({
                    "us": cell.our_ship().name(),
                    "them": cell.their_ship().name(),
                    "opponent_type": cell.foe.as_str(),
                    "wins": tally.wins,
                    "games": tally.games,
                    "win_rate": number(tally.rate()),
                    "lower_bound": number(tally.lower_bound()),
                    "status": status,
                    "sample_weight": sampler::weight(&self.config.sampler, &stat, generation,
                                                     self.priority.contains(cell)),
                    // Extension: decayed training evidence, kept clearly apart
                    // from the audit numbers above.
                    "training_games": stat.games,
                    "training_win_rate": number(stat.games.gt(&0.0).then(|| stat.wins / stat.games))
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

/// How many losses a cell may take on a panel and still clear the bound. The
/// dashboard shows this next to the target because "lower bound above 0.8" is
/// a much harder demand than "win rate above 0.8".
pub fn max_losses(panel: u32, target: f64) -> u32 {
    (0..=panel)
        .filter(|losses| wilson_lower(panel - losses, panel).is_some_and(|b| b > target))
        .max()
        .unwrap_or(0)
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

    #[test]
    fn the_reported_loss_allowance_matches_the_bound() {
        assert_eq!(max_losses(64, 0.8), 6);
        assert_eq!(max_losses(32, 0.8), 1);
        assert_eq!(max_losses(8, 0.8), 0);
    }
}
