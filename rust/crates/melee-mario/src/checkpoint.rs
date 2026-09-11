//! Serialising a run so that resuming it is indistinguishable from never
//! having stopped.
//!
//! Decoding is strict on purpose. A checkpoint that does not describe THIS
//! engine version, this configuration, this stage's board or a self-consistent
//! panel is rejected outright rather than repaired, because a repaired
//! checkpoint would quietly resume a different experiment.

use crate::audit::{Gate, Tally};
use crate::curriculum::{self, Cell};
use crate::episode::Task;
use crate::genome::Genome;
use crate::neat::Population;
use crate::rng::Stream;
use crate::sampler::{Panel, SamplerStats};
use crate::trainer::{Config, Event, HistoryRow, Ladder, Mode, Trainer, ENGINE_VERSION};
use serde_json::{json, Value};
use std::collections::{BTreeMap, VecDeque};

pub fn task_json(task: &Task) -> Value {
    json!([task.cell.encode(), task.swap, task.seed, task.ticks])
}

pub fn task_from_json(value: &Value) -> Option<Task> {
    let row = value.as_array()?;
    if row.len() != 4 {
        return None;
    }
    Some(Task {
        cell: Cell::decode(row.first()?)?,
        swap: row.get(1)?.as_bool()?,
        seed: row
            .get(2)?
            .as_i64()
            .filter(|s| (1..=2_147_483_646).contains(s))?,
        ticks: row.get(3)?.as_i64().filter(|t| *t > 0)?,
    })
}

fn mode_json(mode: &Mode) -> Value {
    match mode {
        Mode::Training => json!({"kind": "training"}),
        Mode::Probing {
            attempt,
            champion,
            tasks,
            cursor,
            wins,
        } => json!({"kind": "probing", "attempt": attempt, "champion": champion,
                    "cursor": cursor, "wins": wins,
                    "tasks": tasks.iter().map(task_json).collect::<Vec<_>>()}),
        Mode::Auditing { gate } => json!({"kind": "auditing", "gate": gate.to_json()}),
    }
}

fn mode_from_json(value: &Value) -> Option<Mode> {
    match value.get("kind")?.as_str()? {
        "training" => Some(Mode::Training),
        "probing" => {
            let tasks = value
                .get("tasks")?
                .as_array()?
                .iter()
                .map(task_from_json)
                .collect::<Option<Vec<_>>>()?;
            let cursor = value.get("cursor")?.as_u64()? as usize;
            let wins = value.get("wins")?.as_u64()? as u32;
            // A cursor past the end, or more wins than games played, would
            // resume a probe that never happened.
            if cursor > tasks.len() || wins as usize > cursor {
                return None;
            }
            Some(Mode::Probing {
                attempt: value.get("attempt")?.as_u64()?,
                champion: value.get("champion")?.as_str()?.to_string(),
                tasks,
                cursor,
                wins,
            })
        }
        "auditing" => Some(Mode::Auditing {
            gate: Gate::from_json(value.get("gate")?)?,
        }),
        _ => None,
    }
}

fn history_json(row: &HistoryRow) -> Value {
    json!({"generation": row.generation, "stage": row.stage,
           "training_win_rate": row.training_win_rate,
           "validation_win_rate": row.validation_win_rate,
           "species": row.species, "nodes": row.nodes, "episodes": row.episodes})
}

fn history_from_json(value: &Value) -> Option<HistoryRow> {
    let rate = |key: &str| match value.get(key) {
        None | Some(Value::Null) => Some(None),
        Some(other) => other.as_f64().filter(|n| n.is_finite()).map(Some),
    };
    Some(HistoryRow {
        generation: value.get("generation")?.as_u64()? as u32,
        stage: curriculum::valid_stage(value.get("stage")?.as_u64()?)?,
        training_win_rate: rate("training_win_rate")?,
        validation_win_rate: rate("validation_win_rate")?,
        species: value.get("species")?.as_u64()? as usize,
        nodes: value.get("nodes")?.as_u64()? as usize,
        episodes: value.get("episodes")?.as_u64()?,
    })
}

impl Trainer {
    /// The complete resumable state, including the exact position inside a
    /// half-finished panel, probe or audit round.
    pub fn to_json(&self) -> Value {
        let evidence: Vec<Value> = self
            .evidence
            .iter()
            .map(|(cell, tally)| json!([cell.encode(), tally.wins, tally.games]))
            .collect();
        json!({
            "schema_version": 1,
            "version": ENGINE_VERSION,
            "evaluator": self.evaluator,
            "config": self.config.to_json(),
            "saved_at": self.saved_at,
            "rng": {"evolution": self.evolution.to_json(), "sampling": self.sampling.to_json()},
            "population": self.population.to_json(),
            "stage": self.stage,
            "ladder": self.ladder.as_str(),
            "opponent_revision": self.opponent_revision,
            "frozen_opponent": self.frozen_opponent.as_ref().map(Genome::to_json),
            "champion": self.champion.as_ref().map(Genome::to_json),
            "evidence": evidence,
            "priority": self.priority.iter().map(|c| c.encode()).collect::<Vec<_>>(),
            "stats": self.stats.to_json(),
            "panel": self.panel.as_ref().map(Panel::to_json),
            "mode": mode_json(&self.mode),
            "episodes": self.episodes,
            "elapsed_seconds": self.elapsed,
            "compute_seconds": self.compute,
            "audit_attempt": self.audit_attempt,
            "last_validation": self.last_validation,
            "last_training_wins": self.last_training_wins,
            "history": self.history.iter().map(history_json).collect::<Vec<_>>(),
            "events": self.events.iter()
                .map(|e| json!({"at": e.at, "message": e.message})).collect::<Vec<_>>(),
        })
    }

    pub fn from_json(value: &Value) -> Result<Trainer, String> {
        decode(value).ok_or_else(|| {
            "checkpoint does not describe a resumable run of this engine version".into()
        })
    }
}

fn decode(value: &Value) -> Option<Trainer> {
    if value.get("schema_version")?.as_i64()? != 1
        || value.get("version")?.as_str()? != ENGINE_VERSION
    {
        return None;
    }
    let config = Config::from_json(value.get("config")?)?;
    let rng = value.get("rng")?;
    let population = Population::from_json(value.get("population")?)?;
    // A population evolved under different settings is a different experiment.
    if population.config != config.neat {
        return None;
    }
    let stage = curriculum::valid_stage(value.get("stage")?.as_u64()?)?;
    let ladder = Ladder::parse(value.get("ladder")?.as_str()?)?;
    let genome = |key: &str| -> Option<Option<Genome>> {
        match value.get(key) {
            None | Some(Value::Null) => Some(None),
            Some(other) => Genome::from_json(other).ok().map(Some),
        }
    };
    let active = curriculum::cells(stage);
    let mut evidence = BTreeMap::new();
    for raw in value.get("evidence")?.as_array()? {
        let row = raw.as_array()?;
        if row.len() != 3 {
            return None;
        }
        let cell = Cell::decode(row.first()?)?;
        let wins = row.get(1)?.as_u64()? as u32;
        let games = row.get(2)?.as_u64()? as u32;
        // Evidence for a cell outside this stage's board would inflate the
        // mastered count, and more wins than games is impossible.
        if wins > games || !active.contains(&cell) {
            return None;
        }
        evidence.insert(cell, Tally { wins, games });
    }
    let priority = value
        .get("priority")?
        .as_array()?
        .iter()
        .map(Cell::decode)
        .collect::<Option<Vec<_>>>()?;
    let panel = match value.get("panel") {
        None | Some(Value::Null) => None,
        Some(other) => Some(Panel::from_json(other)?),
    };
    let history = value
        .get("history")?
        .as_array()?
        .iter()
        .map(history_from_json)
        .collect::<Option<VecDeque<_>>>()?;
    let events = value
        .get("events")?
        .as_array()?
        .iter()
        .map(|e| {
            Some(Event {
                at: e.get("at")?.as_str()?.to_string(),
                message: e.get("message")?.as_str()?.to_string(),
            })
        })
        .collect::<Option<VecDeque<_>>>()?;
    let frozen_opponent = genome("frozen_opponent")?;
    // The mixed phase is defined by having a frozen opponent to play.
    if ladder == Ladder::Mixed && frozen_opponent.is_none() {
        return None;
    }
    Some(Trainer {
        evaluator: value
            .get("evaluator")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_string(),
        evolution: Stream::from_json(rng.get("evolution")?)?,
        sampling: Stream::from_json(rng.get("sampling")?)?,
        population,
        stage,
        ladder,
        opponent_revision: value.get("opponent_revision")?.as_u64()? as u32,
        frozen_opponent,
        champion: genome("champion")?,
        evidence,
        priority,
        stats: SamplerStats::from_json(value.get("stats")?)?,
        panel,
        mode: mode_from_json(value.get("mode")?)?,
        episodes: value.get("episodes")?.as_u64()?,
        elapsed: value
            .get("elapsed_seconds")?
            .as_f64()
            .filter(|n| n.is_finite() && *n >= 0.0)?,
        compute: match value.get("compute_seconds") {
            None | Some(Value::Null) => 0.0,
            Some(other) => other.as_f64().filter(|n| n.is_finite() && *n >= 0.0)?,
        },
        audit_attempt: value.get("audit_attempt")?.as_u64()?,
        last_validation: match value.get("last_validation") {
            None | Some(Value::Null) => None,
            Some(other) => Some(other.as_f64().filter(|n| n.is_finite())?),
        },
        last_training_wins: match value.get("last_training_wins") {
            None | Some(Value::Null) => None,
            Some(other) => Some(other.as_f64().filter(|n| n.is_finite())?),
        },
        history,
        events,
        saved_at: value
            .get("saved_at")
            .and_then(Value::as_str)
            .map(str::to_string),
        cache: None,
        opponent_cache: None,
        config,
    })
}
