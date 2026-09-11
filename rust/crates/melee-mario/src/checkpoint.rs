//! Serialising a run so that resuming it is indistinguishable from never
//! having stopped.
//!
//! Decoding is strict on purpose. A checkpoint that does not describe THIS
//! engine version, this configuration, this stage's board or a self-consistent
//! panel is rejected outright rather than repaired, because a repaired
//! checkpoint would quietly resume a different experiment.

use crate::audit::{Gate, Tally};
use crate::broad::{Evaluation, Overall, Source};
use crate::curriculum::{self, Cell};
use crate::episode::Task;
use crate::genome::Genome;
use crate::neat::{MutationRates, Population};
use crate::rng::Stream;
use crate::sampler::{Panel, SamplerStats};
use crate::trainer::{
    Config, Event, HistoryRow, Ladder, Mode, Origin, Trainer, ENGINE_VERSION,
};
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
        Mode::Overall { gate } => json!({"kind": "overall", "gate": gate.to_json()}),
    }
}

fn mode_from_json(value: &Value, salt: u64, ticks: i64) -> Option<Mode> {
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
        "overall" => Some(Mode::Overall {
            gate: Overall::from_json(value.get("gate")?, salt, ticks)?,
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
            "champion_rates": self.champion_rates.to_json(),
            "evidence": evidence,
            "priority": self.priority.iter().map(|c| c.encode()).collect::<Vec<_>>(),
            "stats": self.stats.to_json(),
            "panel": self.panel.as_ref().map(Panel::to_json),
            "mode": mode_json(&self.mode),
            "origin": self.origin.as_ref().map(Origin::to_json),
            "coverage_cursor": self.coverage_cursor,
            "broad_ready": self.broad_ready.as_ref().map(Evaluation::to_json),
            "broad_audit": self.broad_audit.as_ref().map(Evaluation::to_json),
            "broad_confirm": self.broad_confirm.as_ref().map(Evaluation::to_json),
            "broad_gate": self.broad_gate.as_ref().map(Evaluation::to_json),
            "broad_shown": self.broad_shown.map(Source::as_str),
            "episodes": self.episodes,
            "unresolved": self.unresolved,
            "elapsed_seconds": self.elapsed,
            "compute_seconds": self.compute,
            "audit_attempt": self.audit_attempt,
            "last_validation": self.last_validation,
            "last_training_wins": self.last_training_wins,
            "regression_swept": self.regression_swept,
            "regression_failed": self.regression_failed,
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
    // Broad mode is defined by the whole board being active. A checkpoint that
    // claimed broad scope on a narrower stage would sample and gate two
    // different distributions.
    if ladder == Ladder::Broad && stage != curriculum::FINAL_STAGE {
        return None;
    }
    let champion = genome("champion")?;
    let opponent_revision = value.get("opponent_revision")?.as_u64()? as u32;
    let mode = mode_from_json(value.get("mode")?, config.salt, config.ticks)?;
    // The evidence map is checked against the active board above, but a gate or
    // probe caught mid-flight carries its OWN idea of which candidate, stage and
    // opponent revision it is measuring. If any of those disagree with the run
    // being resumed, the in-flight evidence describes something else and the
    // checkpoint is not resumable.
    let fingerprint = champion.as_ref().map(Genome::fingerprint);
    // Broad evidence, in flight or finished, belongs to the champion it was
    // measured on and to the round that produced it. `broad_gate` is the
    // exception on the champion: it NAMES the champion that cleared the target,
    // which may since have been replaced, and the status document compares that
    // name against the current champion rather than assuming they are the same.
    let evaluation = |key: &str, source: Source| -> Option<Option<Evaluation>> {
        match value.get(key) {
            None | Some(Value::Null) => Some(None),
            Some(other) => {
                let decoded = Evaluation::from_json(other)?;
                (decoded.source == source
                    && fingerprint.as_deref() == Some(decoded.champion.as_str()))
                .then_some(Some(decoded))
            }
        }
    };
    let broad_ready = evaluation("broad_ready", Source::Ready)?;
    let broad_audit = evaluation("broad_audit", Source::Audit)?;
    let broad_confirm = evaluation("broad_confirm", Source::Confirm)?;
    let broad_gate = match value.get("broad_gate") {
        None | Some(Value::Null) => None,
        Some(other) => {
            let decoded = Evaluation::from_json(other)?;
            // Only a confirmation round can be the round that passed.
            (decoded.source == Source::Confirm).then_some(decoded)?.into()
        }
    };
    let broad_shown = match value.get("broad_shown") {
        None | Some(Value::Null) => None,
        Some(other) => Some(Source::parse(other.as_str()?)?),
    };
    // A confirmation exists only as the second half of a gate whose first half
    // cleared the target. Without that, a document could present a confirmation
    // round as a pass while the audit that is supposed to precede it never
    // happened or failed.
    let passed = |reading: &Evaluation| {
        reading
            .tally()
            .lower_bound()
            .is_some_and(|bound| bound > config.broad.target)
    };
    // `broad_audit` and `broad_confirm` are evidence about the CURRENT
    // champion and are discarded together the moment it is replaced, so they
    // can be checked against each other: a confirmation only ever exists as
    // the second half of a gate whose audit cleared.
    let audit_cleared = broad_audit.as_ref().is_some_and(&passed);
    if broad_confirm.is_some() && !audit_cleared {
        return None;
    }
    // `broad_gate` is not that kind of evidence. It is the finished proof for
    // ONE named champion and it deliberately outlives that champion, so by the
    // first promotion afterwards `broad_confirm` is already gone. Tying it to
    // the current confirmation made every such checkpoint unresumable. It
    // carries its own numbers, so it is checked on its own: a confirmation
    // round, for a named champion, whose bound actually clears the target.
    if broad_gate.as_ref().is_some_and(|gate| !passed(gate)) {
        return None;
    }
    match &mode {
        Mode::Training => {}
        Mode::Probing {
            champion: measured, ..
        } => {
            if fingerprint.as_deref() != Some(measured.as_str()) {
                return None;
            }
        }
        Mode::Auditing { gate } => {
            if fingerprint.as_deref() != Some(gate.champion.as_str())
                || gate.stage != stage
                || gate.opponent_revision != opponent_revision
                || !gate.order.iter().all(|cell| active.contains(cell))
            {
                return None;
            }
        }
        Mode::Overall { gate } => {
            // The broad gate is a fixed panel against the ORIGINAL cyborgs on
            // the whole board, measuring one frozen candidate under THIS run's
            // settings. A different candidate, a narrower scope, a frozen-model
            // cell, a different target or a differently sized panel would all
            // make the numbers describe something else. And a confirmation
            // round may only be in flight if the audit before it cleared.
            if fingerprint.as_deref() != Some(gate.evaluation.champion.as_str())
                || ladder != Ladder::Broad
                || gate.target != config.broad.target
                || gate.tasks.len() != config.broad.games()
                || gate
                    .tasks
                    .iter()
                    .any(|task| task.cell.foe != crate::curriculum::Opponent::Cyborg)
                || (gate.round == crate::audit::Round::Confirm && !audit_cleared)
            {
                return None;
            }
        }
    }
    // The reading the dashboard is told to show has to exist.
    let shown_exists = match broad_shown {
        None => true,
        Some(Source::Ready) => broad_ready.is_some(),
        Some(Source::Audit) => broad_audit.is_some(),
        Some(Source::Confirm) => broad_confirm.is_some(),
    };
    if !shown_exists && !matches!(mode, Mode::Overall { .. }) {
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
        opponent_revision,
        frozen_opponent,
        champion,
        champion_rates: match value.get("champion_rates") {
            None | Some(Value::Null) => config.neat.seed_rates,
            Some(other) => MutationRates::from_json(other)?,
        },
        evidence,
        priority,
        stats: SamplerStats::from_json(value.get("stats")?)?,
        panel,
        mode,
        origin: match value.get("origin") {
            None | Some(Value::Null) => None,
            Some(other) => Some(Origin::from_json(other)?),
        },
        coverage_cursor: value
            .get("coverage_cursor")
            .and_then(Value::as_u64)
            .unwrap_or(0),
        broad_ready,
        broad_audit,
        broad_confirm,
        broad_gate,
        broad_shown,
        episodes: value.get("episodes")?.as_u64()?,
        unresolved: value.get("unresolved").and_then(Value::as_u64).unwrap_or(0),
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
        nice: 0,
        regression_swept: value
            .get("regression_swept")
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize,
        regression_failed: value
            .get("regression_failed")
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize,
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
