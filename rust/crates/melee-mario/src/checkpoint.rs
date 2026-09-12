//! Serialising a run so that resuming it is indistinguishable from never
//! having stopped.
//!
//! Decoding is strict on purpose. A checkpoint that does not describe THIS
//! engine version, this configuration, this schema or a self-consistent panel
//! is rejected outright rather than repaired, because a repaired checkpoint
//! would quietly resume a different experiment.
//!
//! Schema 2 dropped the staged ladder and renumbered the board onto
//! `ALL_SHIPS`, so the same cell indices name different hulls than they did
//! under schema 1. Schema 3 dropped the combat-win WINDOW, which only ever
//! held anything for a document written before that counter existed, and with
//! it every "this field may be missing" branch the decoder carried: a
//! schema 3 document is written by [`Trainer::to_json`] and therefore has
//! every field that function writes.
//!
//! There is no migration between any two of them and none is possible. An
//! older document is refused BY VERSION, with a message that names both
//! versions, rather than half loaded as a run about matchups that were never
//! played.

use crate::broad::{Cell, Evaluation, Opponent, Overall, Source};
use crate::episode::Task;
use crate::genome::Genome;
use crate::neat::{MutationRates, Population};
use crate::rng::Stream;
use crate::sampler::{Panel, SamplerStats};
use crate::trainer::{Config, Event, HistoryRow, Mode, Trainer, ENGINE_VERSION};
use serde_json::{json, Value};
use std::collections::VecDeque;

/// Bumped when the meaning of a stored field changes. Schema 1 described the
/// staged ladder and numbered cells by an expansion order that no longer
/// exists; schema 2 still carried the combat-win window and the optional
/// fields that went with the era before it. Both are refused rather than
/// reinterpreted.
pub const SCHEMA_VERSION: i64 = 3;

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
        "overall" => Some(Mode::Overall {
            gate: Overall::from_json(value.get("gate")?, salt, ticks)?,
        }),
        _ => None,
    }
}

fn history_json(row: &HistoryRow) -> Value {
    json!({"generation": row.generation,
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
        json!({
            "schema_version": SCHEMA_VERSION,
            "version": ENGINE_VERSION,
            "evaluator": self.evaluator,
            "config": self.config.to_json(),
            "saved_at": self.saved_at,
            "rng": {"evolution": self.evolution.to_json(), "sampling": self.sampling.to_json()},
            "population": self.population.to_json(),
            "champion": self.champion.as_ref().map(Genome::to_json),
            "champion_rates": self.champion_rates.to_json(),
            "stats": self.stats.to_json(),
            "panel": self.panel.as_ref().map(Panel::to_json),
            "mode": mode_json(&self.mode),
            "coverage_cursor": self.coverage_cursor,
            "broad_ready": self.broad_ready.as_ref().map(Evaluation::to_json),
            "broad_audit": self.broad_audit.as_ref().map(Evaluation::to_json),
            "broad_confirm": self.broad_confirm.as_ref().map(Evaluation::to_json),
            "broad_gate": self.broad_gate.as_ref().map(Evaluation::to_json),
            "broad_shown": self.broad_shown.map(Source::as_str),
            "episodes": self.episodes,
            "unresolved": self.unresolved,
            "combat_wins": self.combat_wins,
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

    /// A version mismatch is reported on its own terms, naming both versions,
    /// because it is the one failure an operator can act on: there is no
    /// migration, so the answer is to start a new run rather than to look for
    /// corruption that is not there. Everything else the decoder refuses is a
    /// document that claims to be this schema and is not self-consistent.
    pub fn from_json(value: &Value) -> Result<Trainer, String> {
        let schema = value.get("schema_version").and_then(Value::as_i64);
        let engine = value.get("version").and_then(Value::as_str);
        if schema != Some(SCHEMA_VERSION) || engine != Some(ENGINE_VERSION) {
            return Err(format!(
                "this checkpoint is {} schema {}, and this build reads {ENGINE_VERSION} \
                 schema {SCHEMA_VERSION}. Its fields do not mean what this build would read \
                 them as, there is no migration, and half loading one would resume a \
                 different experiment. Start a new run instead.",
                engine.unwrap_or("an unnamed engine"),
                schema.map_or_else(|| "(none)".to_string(), |n| n.to_string())
            ));
        }
        decode(value).ok_or_else(|| {
            format!(
                "this checkpoint claims {ENGINE_VERSION} schema {SCHEMA_VERSION} but is not a \
                 self-consistent run of it, so it is refused rather than repaired"
            )
        })
    }
}

/// Decodes a document whose version [`Trainer::from_json`] has already
/// checked. Every field [`Trainer::to_json`] writes is therefore present, so
/// an absent one is a malformed document and not an older era to be tolerated.
fn decode(value: &Value) -> Option<Trainer> {
    let config = Config::from_json(value.get("config")?)?;
    let rng = value.get("rng")?;
    let population = Population::from_json(value.get("population")?)?;
    // Read before the population is moved into the trainer below.
    let restored_generation = population.generation;
    // A population evolved under different settings is a different experiment.
    if population.config != config.neat {
        return None;
    }
    let genome = |key: &str| -> Option<Option<Genome>> {
        match value.get(key) {
            None | Some(Value::Null) => Some(None),
            Some(other) => Genome::from_json(other).ok().map(Some),
        }
    };
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
    let champion = genome("champion")?;
    let mode = mode_from_json(value.get("mode")?, config.salt, config.ticks)?;
    // A round or probe caught mid-flight carries its OWN idea of which
    // candidate it is measuring. If that disagrees with the run being resumed,
    // the in-flight evidence describes something else and the checkpoint is
    // not resumable.
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
        Mode::Overall { gate } => {
            // The gate is a fixed balanced panel against the ORIGINAL cyborgs
            // on the whole board, measuring one frozen candidate under THIS
            // run's settings. A different candidate, a different target or a
            // differently sized panel would all make the numbers describe
            // something else. And a confirmation round may only be in flight
            // if the audit before it cleared.
            if fingerprint.as_deref() != Some(gate.evaluation.champion.as_str())
                || gate.target != config.broad.target
                || gate.tasks.len() != config.broad.games()
                || gate.tasks.iter().any(|task| task.cell.foe != Opponent::Cyborg)
                || (gate.round == crate::audit::Round::Confirm && !audit_cleared)
            {
                return None;
            }
        }
    }
    // The factual combat-win counter covers the whole run, always: there is no
    // window field any more, because the only value a window ever held that
    // was not zero came from a document written before the counter existed,
    // and such a document is now refused by version.
    //
    // A null, a negative, a fraction, more victories than the run has
    // episodes, or more victories than it has RESOLVED fights to give them,
    // is a corrupt counter. Reading one of those as a known zero would publish
    // a lie quietly, so it is rejected as loudly as any other unreadable
    // field.
    //
    // Every bound below is written as a SUBTRACTION from the episode total,
    // never as a sum of two decoded counts: a malformed checkpoint may carry
    // numbers near `u64::MAX`, and a sum of those would wrap to something
    // small and pass a check it should have failed.
    let episodes = value.get("episodes")?.as_u64()?;
    let unresolved = value.get("unresolved")?.as_u64()?;
    let combat_wins = value.get("combat_wins")?.as_u64()?;
    if unresolved > episodes || combat_wins > episodes - unresolved {
        return None;
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
        evaluator: value.get("evaluator")?.as_str()?.to_string(),
        evolution: Stream::from_json(rng.get("evolution")?)?,
        sampling: Stream::from_json(rng.get("sampling")?)?,
        population,
        champion,
        champion_rates: MutationRates::from_json(value.get("champion_rates")?)?,
        stats: SamplerStats::from_json(value.get("stats")?)?,
        panel,
        mode,
        coverage_cursor: value.get("coverage_cursor")?.as_u64()?,
        broad_ready,
        broad_audit,
        broad_confirm,
        broad_gate,
        broad_shown,
        episodes,
        unresolved,
        combat_wins,
        elapsed: value
            .get("elapsed_seconds")?
            .as_f64()
            .filter(|n| n.is_finite() && *n >= 0.0)?,
        compute: value
            .get("compute_seconds")?
            .as_f64()
            .filter(|n| n.is_finite() && *n >= 0.0)?,
        // Phase timers and work counters describe THIS process, so a decoded
        // run starts them at zero exactly as it does `nice` and the pool.
        // Restoring them would average a week of one machine's load into this
        // afternoon's nanoseconds-per-tick and present the result as a
        // property of the build.
        phases: crate::phases::Phases::default(),
        work: crate::phases::Work::default(),
        session_compute: 0.0,
        session_cpu: 0.0,
        audit_attempt: value.get("audit_attempt")?.as_u64()?,
        last_validation: match value.get("last_validation") {
            None | Some(Value::Null) => None,
            Some(other) => Some(other.as_f64().filter(|n| n.is_finite())?),
        },
        nice: 0,
        pool: crate::pool::Pool::new(1),
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
        // Taken from the population this document actually carried, not from
        // any field in it: what is on disk is, by definition, the generation
        // just decoded from disk.
        saved_generation: Some(restored_generation),
        cache: None,
        config,
    })
}
