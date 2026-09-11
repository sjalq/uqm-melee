//! Stopping and resuming must be indistinguishable from never stopping.
//!
//! These tests drive the REAL simulator: every unit of work below runs actual
//! UQM melee fights through `melee_neat::eval`, evolves a real population and
//! opens a real audit gate. The budgets are small so the whole file finishes in
//! a few seconds, but nothing about the code path is a stand-in.
//!
//! Run just this file with:
//!
//!   cargo test -j 2 -p melee-mario --test restart_equivalence -- --test-threads=2

use melee_mario::audit::AuditConfig;
use melee_mario::neat::NeatConfig;
use melee_mario::sampler::SamplerConfig;
use melee_mario::trainer::{Config, Trainer};
use melee_sim::input::CyborgRating;
use serde_json::Value;

/// A run small enough to finish quickly and large enough to exercise panels,
/// species turnover, champion replacement, readiness probes and an audit.
fn config(run: &str) -> Config {
    Config {
        run_id: run.to_string(),
        salt: 0x5eed_1234,
        // Short fights, but still the whole countdown, combat, round-over and
        // victory path; a fight that does not resolve is a timeout, not a win.
        ticks: 420,
        rating: CyborgRating::AwesomeCyborg,
        neat: NeatConfig {
            population: 8,
            stale_species: 3,
            ..NeatConfig::default()
        },
        sampler: SamplerConfig {
            panel: 3,
            ..SamplerConfig::default()
        },
        audit: AuditConfig {
            panel: 6,
            budget: 40,
            max_failures: 1,
            target: 0.80,
        },
        duty: 1.0,
        readiness_games: 4,
        // Deliberately reachable, so the probe and the gate really run.
        readiness_threshold: 0.0,
        readiness_period: 2,
    }
}

/// Wall-clock facts differ between a run that paused and one that did not, and
/// they are metadata rather than trajectory. Everything else must match.
fn trajectory(document: &Value) -> Value {
    let mut stripped = document.clone();
    let object = stripped.as_object_mut().expect("checkpoint is an object");
    object.remove("saved_at");
    object.remove("elapsed_seconds");
    // Event text is trajectory; the timestamps on it are not.
    if let Some(events) = object.get_mut("events").and_then(Value::as_array_mut) {
        for event in events.iter_mut() {
            if let Some(entry) = event.as_object_mut() {
                entry.remove("at");
            }
        }
    }
    stripped
}

fn run_units(trainer: &mut Trainer, units: usize) {
    for _ in 0..units {
        trainer.step();
    }
}

#[test]
fn a_resumed_run_follows_the_same_trajectory_as_an_uninterrupted_one() {
    const UNITS: usize = 90;

    let mut straight = Trainer::fresh(config("straight"));
    run_units(&mut straight, UNITS);

    // The same run, stopped at every eighth unit, serialised, restored and
    // continued. Each restore goes through the real checkpoint decoder.
    let mut restarts = 0;
    let mut stitched = Trainer::fresh(config("straight"));
    let mut done = 0;
    while done < UNITS {
        let chunk = (UNITS - done).min(8);
        run_units(&mut stitched, chunk);
        done += chunk;
        let saved = stitched.to_json();
        stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
        restarts += 1;
        assert_eq!(
            trajectory(&stitched.to_json()),
            trajectory(&saved),
            "restoring changed the state at unit {done}"
        );
    }

    assert!(restarts >= 10, "the test did not actually restart much");
    assert!(
        straight.episodes > 200,
        "expected real fights, saw {}",
        straight.episodes
    );
    assert!(
        straight.population.generation >= 3,
        "expected several generations, saw {}",
        straight.population.generation
    );

    let expected = trajectory(&straight.to_json());
    let actual = trajectory(&stitched.to_json());
    if expected != actual {
        // Point at the first field that diverged rather than dumping megabytes.
        let (left, right) = (
            expected.as_object().unwrap(),
            actual.as_object().unwrap(),
        );
        let differing: Vec<&String> = left
            .keys()
            .filter(|key| left.get(*key) != right.get(*key))
            .collect();
        panic!("resumed trajectory diverged in fields: {differing:?}");
    }
}

#[test]
fn a_resumed_run_keeps_evolving_identically_after_the_restart() {
    // Divergence can hide until the next panel is drawn or the next generation
    // turns over, so both halves keep running well past the restart point.
    let mut straight = Trainer::fresh(config("after"));
    run_units(&mut straight, 70);

    let mut stitched = Trainer::fresh(config("after"));
    run_units(&mut stitched, 25);
    let saved = stitched.to_json();
    let mut stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
    run_units(&mut stitched, 45);

    assert_eq!(
        trajectory(&straight.to_json()),
        trajectory(&stitched.to_json()),
        "state diverged only after the restart point"
    );
    assert_eq!(straight.episodes, stitched.episodes);
    assert_eq!(
        straight.champion.as_ref().map(|g| g.fingerprint()),
        stitched.champion.as_ref().map(|g| g.fingerprint())
    );
}

#[test]
fn the_real_loop_reaches_an_audit_and_the_status_document_stays_well_formed() {
    let mut trainer = Trainer::fresh(config("audited"));
    let mut saw_audit = false;
    for _ in 0..260 {
        trainer.step();
        if trainer.phase() == "auditing" {
            saw_audit = true;
        }
    }
    assert!(saw_audit, "the readiness probe never opened an audit");

    let status = trainer.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["schema_version"], 1);
    assert!(status["matchups"].as_array().unwrap().len() >= 1);
    assert!(status["history"].as_array().unwrap().len() >= 1);
    assert!(status["champion"]["id"].as_str().is_some());
    // Every number in the document has to be finite or explicitly absent.
    let mut stack = vec![&status];
    while let Some(node) = stack.pop() {
        match node {
            Value::Number(n) => assert!(n.as_f64().is_some_and(f64::is_finite), "non-finite {n}"),
            Value::Array(items) => stack.extend(items.iter()),
            Value::Object(fields) => stack.extend(fields.values()),
            _ => {}
        }
    }

    let network = trainer.network();
    assert_eq!(network["input_labels"].as_array().unwrap().len(), 57);
    assert_eq!(network["output_labels"].as_array().unwrap().len(), 13);
    assert_eq!(network["genome"]["schema_version"], 1);
}
