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
use melee_mario::broad::BroadConfig;
use melee_mario::episode::Scoring;
use melee_mario::neat::NeatConfig;
use melee_mario::sampler::SamplerConfig;
use melee_mario::trainer::{Config, Trainer};
use melee_sim::input::CyborgRating;
use serde_json::Value;

/// A run small enough to finish quickly and large enough to exercise panels,
/// species turnover, champion replacement, readiness probes and an audit.
fn config(run: &str) -> Config {
    scored_config(run, Scoring::default())
}

/// The same run under a named scorer, so resume equivalence can be checked for
/// each of them on the real simulator rather than only for the default.
fn scored_config(run: &str, scoring: Scoring) -> Config {
    Config {
        scoring,
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
        broad: BroadConfig {
            panel: 4,
            // One matching, so a held-out round is fifty games.
            pairs: 25,
            ..BroadConfig::default()
        },
        duty: 1.0,
        readiness_games: 4,
        // Deliberately reachable, so the probe and the gate really run.
        readiness_threshold: 0.0,
        readiness_period: 2,
        regression_budget: 30,
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

#[test]
fn a_crew_ratio_run_resumes_identically_on_the_real_simulator() {
    // Same shape as the default-scorer test above, on real fights, so the new
    // scorer is shown to be as reproducible across a stop as the old one.
    let mut straight = Trainer::fresh(scored_config("ratio", Scoring::CrewRatio));
    run_units(&mut straight, 60);

    let mut stitched = Trainer::fresh(scored_config("ratio", Scoring::CrewRatio));
    run_units(&mut stitched, 20);
    let saved = stitched.to_json();
    let mut stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
    assert_eq!(stitched.config.scoring, Scoring::CrewRatio);
    run_units(&mut stitched, 40);

    assert_eq!(
        trajectory(&straight.to_json()),
        trajectory(&stitched.to_json()),
        "a crew-ratio run diverged after the restart point"
    );
    assert!(straight.episodes > 100, "expected real fights");
    assert!(straight.population.generation >= 2, "expected generations");
    assert!(
        straight.champion.is_some(),
        "a champion must be promotable under the crew-ratio scorer"
    );
}

#[test]
fn the_scorer_actually_changes_the_trajectory_and_keeps_every_number_finite() {
    let mut combat = Trainer::fresh(scored_config("split", Scoring::Combat));
    let mut ratio = Trainer::fresh(scored_config("split", Scoring::CrewRatio));
    run_units(&mut combat, 60);
    run_units(&mut ratio, 60);

    // Identical run id, salt, seeds and fights: the ONLY difference is which
    // scorer ranks the population, and it has to be able to reach a different
    // champion, or the selector would be decorative.
    assert_eq!(combat.episodes, ratio.episodes);
    assert_ne!(
        trajectory(&combat.to_json()),
        trajectory(&ratio.to_json()),
        "the scorer made no difference to selection at all"
    );

    let status = ratio.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["scoring"]["fitness"], "crew-ratio");
    assert_eq!(status["scoring"]["speed_bonus"], false);
    assert_eq!(status["scoring"]["zero_opponent"], 1000.0);
    assert_eq!(status["scoring"]["mutual_zero"], 1.0);
    // The gate is reported separately from the scorer and is unchanged.
    assert_eq!(status["scoring"]["gate"], "combat-wins");
    // An average of ratios, with 1000 among them, still has to be finite.
    let mut stack = vec![&status];
    while let Some(node) = stack.pop() {
        match node {
            Value::Number(n) => assert!(n.as_f64().is_some_and(f64::is_finite), "non-finite {n}"),
            Value::Array(items) => stack.extend(items.iter()),
            Value::Object(fields) => stack.extend(fields.values()),
            _ => {}
        }
    }
}

#[test]
fn a_configuration_round_trips_its_scorer_and_a_legacy_one_reads_as_combat() {
    for scoring in [Scoring::Combat, Scoring::CrewRatio] {
        let document = scored_config("saved", scoring).to_json();
        assert_eq!(document["scoring"]["fitness"], scoring.as_str());
        let back = Config::from_json(&document).expect("a written config must decode");
        assert_eq!(back.scoring, scoring);
    }

    // A configuration written before the selector existed has no block at all,
    // and must decode as the exact scorer it was in fact trained under.
    let mut legacy = scored_config("legacy", Scoring::CrewRatio).to_json();
    legacy.as_object_mut().unwrap().remove("scoring");
    let back = Config::from_json(&legacy).expect("a legacy config must still decode");
    assert_eq!(back.scoring, Scoring::Combat);

    // A block naming a scorer this build does not have is refused outright.
    let mut unknown = scored_config("unknown", Scoring::Combat).to_json();
    unknown["scoring"]["fitness"] = Value::String("kills".into());
    assert!(Config::from_json(&unknown).is_none());

    // So is one whose metadata contradicts the scorer it names.
    let mut lying = scored_config("lying", Scoring::CrewRatio).to_json();
    lying["scoring"]["speed_bonus"] = Value::Bool(true);
    assert!(Config::from_json(&lying).is_none());
}
