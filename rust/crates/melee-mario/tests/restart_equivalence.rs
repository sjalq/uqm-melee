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
use melee_mario::episode::{GateCriterion, Scoring, ScoringConfig};
use melee_mario::neat::NeatConfig;
use melee_mario::sampler::SamplerConfig;
use melee_mario::trainer::{Config, Trainer};
use melee_sim::input::CyborgRating;
use serde_json::Value;

/// A run small enough to finish quickly and large enough to exercise panels,
/// species turnover, champion replacement, readiness probes and an audit.
fn config(run: &str) -> Config {
    scored_config(run, ScoringConfig::default())
}

/// The same run under named settings, so resume equivalence can be checked for
/// each of them on the real simulator rather than only for the default.
///
/// The crew-ratio scorer with otherwise legacy settings: the combat-wins gate
/// and no penalty, so a test that names it is testing the SCORER alone.
fn ratio() -> ScoringConfig {
    ScoringConfig::of(Scoring::CrewRatio)
}

/// The crew-ratio scorer gated on crew leads and penalising a fight that did
/// the enemy no net harm: every one of the three settings away from legacy.
fn staged() -> ScoringConfig {
    ScoringConfig {
        fitness: Scoring::CrewRatio,
        gate: GateCriterion::CrewLead,
        no_damage_penalty: 1000.0,
    }
}

fn scored_config(run: &str, scoring: ScoringConfig) -> Config {
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
    let mut straight = Trainer::fresh(scored_config("ratio", ratio()));
    run_units(&mut straight, 60);

    let mut stitched = Trainer::fresh(scored_config("ratio", ratio()));
    run_units(&mut stitched, 20);
    let saved = stitched.to_json();
    let mut stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
    assert_eq!(stitched.config.scoring, ratio());
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
    let mut combat = Trainer::fresh(scored_config("split", ScoringConfig::default()));
    let mut ratio = Trainer::fresh(scored_config("split", ratio()));
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
    for scoring in [ScoringConfig::default(), ratio()] {
        let document = scored_config("saved", scoring).to_json();
        assert_eq!(document["scoring"]["fitness"], scoring.fitness.as_str());
        let back = Config::from_json(&document).expect("a written config must decode");
        assert_eq!(back.scoring, scoring);
    }

    // A configuration written before the selector existed has no block at all,
    // and must decode as the exact scorer it was in fact trained under.
    let mut legacy = scored_config("legacy", ratio()).to_json();
    legacy.as_object_mut().unwrap().remove("scoring");
    let back = Config::from_json(&legacy).expect("a legacy config must still decode");
    assert_eq!(back.scoring, ScoringConfig::default());

    // A block naming a scorer this build does not have is refused outright.
    let mut unknown = scored_config("unknown", ScoringConfig::default()).to_json();
    unknown["scoring"]["fitness"] = Value::String("kills".into());
    assert!(Config::from_json(&unknown).is_none());

    // So is one whose metadata contradicts the scorer it names.
    let mut lying = scored_config("lying", ratio()).to_json();
    lying["scoring"]["speed_bonus"] = Value::Bool(true);
    assert!(Config::from_json(&lying).is_none());
}

// ===========================================================================
// The gate criterion, the no-damage penalty, and the factual combat counter.
//
// Every test below drives the real simulator through the same `Trainer::step`
// loop the supervisor runs. None of them injects an outcome or shortens a
// fight.
// ===========================================================================

/// Walks a whole status document and fails on any non-finite number. Negative
/// fitness is expected under the penalty; infinity and NaN never are.
fn every_number_is_finite(document: &Value) {
    let mut stack = vec![document];
    while let Some(node) = stack.pop() {
        match node {
            Value::Number(n) => assert!(n.as_f64().is_some_and(f64::is_finite), "non-finite {n}"),
            Value::Array(items) => stack.extend(items.iter()),
            Value::Object(fields) => stack.extend(fields.values()),
            _ => {}
        }
    }
}

fn status_of(trainer: &Trainer) -> Value {
    trainer.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    )
}

#[test]
fn the_gate_criterion_is_carried_through_config_and_reported_to_the_dashboard() {
    let document = scored_config("gated", staged()).to_json();
    assert_eq!(document["scoring"]["fitness"], "crew-ratio");
    assert_eq!(document["scoring"]["gate"], "crew-lead");
    assert_eq!(document["scoring"]["no_damage_penalty"], 1000.0);
    let back = Config::from_json(&document).expect("a written config must decode");
    assert_eq!(back.scoring, staged());

    // A legacy configuration, with the scorer block but neither of the newer
    // settings inside it, still reads back as the exact legacy behaviour.
    let mut older = scored_config("older", ratio()).to_json();
    let block = older["scoring"].as_object_mut().unwrap();
    block.remove("gate");
    block.remove("no_damage_penalty");
    let back = Config::from_json(&older).expect("an older config must still decode");
    assert_eq!(back.scoring.gate, GateCriterion::CombatWins);
    assert_eq!(back.scoring.no_damage_penalty, 0.0);
    assert_eq!(back.scoring.fitness, Scoring::CrewRatio);
}

#[test]
fn a_contradictory_or_unhonourable_configuration_is_refused() {
    for (field, bad) in [
        ("gate", Value::String("crew_lead".into())),
        ("gate", Value::String("kills".into())),
        ("gate", Value::Null),
        ("no_damage_penalty", Value::from(-1.0)),
        ("no_damage_penalty", Value::from(1e308)),
        ("no_damage_penalty", Value::String("1000".into())),
        ("no_damage_penalty", Value::Null),
        // A fact about the scorer that disagrees with the scorer named.
        ("speed_bonus", Value::Bool(true)),
    ] {
        let mut document = scored_config("bad", staged()).to_json();
        document["scoring"][field] = bad.clone();
        assert!(
            Config::from_json(&document).is_none(),
            "scoring.{field} = {bad} should have been refused"
        );
    }
}

/// Everything the two criteria disagreed about over one batch of REAL fights,
/// counted from the same outcomes so the two tallies cannot differ for any
/// reason but the criterion itself.
struct Disagreement {
    fights: usize,
    lead_not_win: usize,
    win_not_lead: usize,
    unresolved_lead: usize,
    combat_wins: usize,
}

/// Replays a fixed batch of real fights with one network and tallies them
/// under both criteria. No outcome is injected and no fight is shortened.
fn disagreement(trainer: &Trainer, cells: &[melee_mario::curriculum::Cell]) -> Disagreement {
    use melee_mario::episode::{self, Rival, Task};
    use melee_mario::graph::Network;
    use std::sync::Arc;

    let genome = trainer
        .champion
        .clone()
        .expect("a champion is needed to fly the fights");
    let network = Arc::new(Network::compile(&genome));
    let mut found = Disagreement {
        fights: 0,
        lead_not_win: 0,
        win_not_lead: 0,
        unresolved_lead: 0,
        combat_wins: 0,
    };
    for (at, cell) in cells.iter().enumerate() {
        for slot in 0..12 {
            let task = Task {
                cell: *cell,
                swap: slot % 2 == 1,
                seed: 900_000 + (at as i64) * 1_000 + slot as i64,
                ticks: 420,
            };
            let end = episode::run(&task, &network, Rival::Cyborg(CyborgRating::AwesomeCyborg));
            let won = end.succeeded(GateCriterion::CombatWins);
            let led = end.succeeded(GateCriterion::CrewLead);
            found.fights += 1;
            found.combat_wins += end.won as usize;
            // The factual field is what CombatWins reports, always.
            assert_eq!(won, end.won);
            if led && !won {
                found.lead_not_win += 1;
                found.unresolved_lead += !end.resolved as usize;
            }
            if won && !led {
                found.win_not_lead += 1;
            }
        }
    }
    found
}

#[test]
fn the_two_criteria_really_disagree_about_real_fights() {
    // The heart of it, and deliberately free of any trainer state: one
    // network, one batch of real fights, both criteria applied to the SAME
    // outcomes. If the routing were removed and everything counted wins, the
    // disagreement count would be zero and this fails.
    let mut trainer = Trainer::fresh(scored_config("disagree", staged()));
    run_units(&mut trainer, 60);
    // Stage 0 is now the Arilou mirror, and a fresh network flying Arilou
    // against the Awesome cyborg flying Arilou is wiped out without landing a
    // hit: it ends every fight at nought crew against six, so it never leads
    // and the two criteria have nothing to disagree about, at any tick budget.
    // The cell the curriculum unlocks next is a fight it survives, so the
    // batch replays the stage's own cells AND that one.
    let mut cells = trainer.cyborg_cells();
    cells.push(melee_mario::curriculum::Cell {
        foe: melee_mario::curriculum::Opponent::Cyborg,
        us: 0,
        them: 1,
    });
    let found = disagreement(&trainer, &cells);

    assert!(found.fights > 0, "expected real fights");
    let disagreed = found.lead_not_win + found.win_not_lead;
    assert!(
        disagreed > 0,
        "the two criteria agreed about all {} fights, so nothing distinguishes them",
        found.fights
    );
    // The interesting half of the difference: fights nobody won, which the
    // crew-lead criterion counts and the combat-wins criterion cannot.
    assert!(
        found.unresolved_lead > 0,
        "expected at least one unresolved fight we led on crew"
    );
    // And those successes are emphatically not victories.
    assert_eq!(
        found.combat_wins, 0,
        "a fight counted as a crew lead must not also be reported as a win here"
    );
}

#[test]
fn the_gate_criterion_really_changes_which_fights_count_as_successes() {
    // Identical run id, salt, seeds and fights. The ONLY difference is what
    // counts as a success.
    let gated_on_wins = ScoringConfig {
        fitness: Scoring::CrewRatio,
        gate: GateCriterion::CombatWins,
        no_damage_penalty: 0.0,
    };
    let gated_on_leads = ScoringConfig {
        gate: GateCriterion::CrewLead,
        ..gated_on_wins
    };
    // Every stage's board contains the Arilou mirror, which a fresh network
    // always loses under both criteria, and an audit that gives up after one
    // failure therefore stops on that game with a single counted game in hand,
    // identically in both runs. Letting the panel play on is what gives the
    // audit fights the criteria can disagree about; it is the same allowance
    // in both runs, so the comparison below is still like for like.
    let patient = |scoring| Config {
        audit: AuditConfig {
            max_failures: 6,
            ..scored_config("criterion", scoring).audit
        },
        ..scored_config("criterion", scoring)
    };
    let mut wins = Trainer::fresh(patient(gated_on_wins));
    let mut leads = Trainer::fresh(patient(gated_on_leads));
    // Both runs start one stage in, identically. On stage 0, the Arilou
    // mirror, a fresh network never lands a hit on the Awesome cyborg, so
    // every fight is a loss under BOTH criteria and the two runs would count
    // the same successes however long they ran: the mirror also never promotes
    // itself off stage 0, because a gate needs successes to pass. Stage 1 adds
    // the Androsynth opponent, which is a fight the criteria disagree about.
    wins.stage = 1;
    leads.stage = 1;
    run_units(&mut wins, 60);
    run_units(&mut leads, 60);
    assert!(wins.episodes > 100, "expected real fights");

    // Each assertion below names a place the criterion is routed to, and each
    // compares COUNTED SUCCESSES rather than configuration. Comparing whole
    // trajectories would pass on the stored `scoring` block alone, even with
    // every one of these call sites reverted to counting wins.

    // 1. The sampler's own weakness statistics.
    let sampler_successes = |t: &Trainer| -> f64 { t.stats.cells.values().map(|c| c.wins).sum() };
    assert!(
        sampler_successes(&wins) != sampler_successes(&leads),
        "the sampler recorded the same successes under both criteria: {} against {}",
        sampler_successes(&wins),
        sampler_successes(&leads)
    );

    // 2. The training success rate written into every history row.
    let training: fn(&Trainer) -> Vec<Option<f64>> =
        |t| t.history.iter().map(|r| r.training_win_rate).collect();
    assert!(
        training(&wins).iter().any(Option::is_some),
        "expected training rates to have been recorded at all"
    );
    assert_ne!(
        training(&wins),
        training(&leads),
        "the recorded training success rate did not depend on the criterion"
    );

    // 3. The readiness probe. Its rate is recorded on the history row, and it
    //    is checked separately from the audit below because a probe whose
    //    trigger is already cleared would open the audit either way.
    let validation: fn(&Trainer) -> Vec<Option<f64>> =
        |t| t.history.iter().map(|r| r.validation_win_rate).collect();
    assert!(
        validation(&wins).iter().any(Option::is_some),
        "expected a readiness probe to have run and recorded its rate"
    );
    assert_ne!(
        validation(&wins),
        validation(&leads),
        "the readiness probe rate did not depend on the criterion"
    );

    // 4. The audit the probe opens.
    assert!(
        wins.champion_evidence().games > 0 && leads.champion_evidence().games > 0,
        "expected the readiness probe to have opened an audit in both runs"
    );
    assert_ne!(
        wins.champion_evidence(),
        leads.champion_evidence(),
        "audit evidence did not depend on the criterion"
    );

    // 5. What must NOT depend on it: the factual combat counters.
    assert_eq!(
        wins.combat_wins, leads.combat_wins,
        "the factual combat-win count must not depend on the gate criterion"
    );
    assert_eq!(wins.unresolved, leads.unresolved);
    assert_eq!(wins.episodes, leads.episodes);

    // 6. And the checkpoint really does diverge, with the stored settings
    //    themselves removed from the comparison so the difference cannot be
    //    the `scoring` block reading back what it was told.
    let without_config = |t: &Trainer| -> Value {
        let mut document = trajectory(&t.to_json());
        document.as_object_mut().expect("a checkpoint").remove("config");
        document
    };
    assert_ne!(
        without_config(&wins),
        without_config(&leads),
        "nothing outside the stored configuration changed"
    );

    let document = status_of(&leads);
    assert_eq!(document["scoring"]["gate"], "crew-lead");
    every_number_is_finite(&document);
}

#[test]
fn crew_lead_successes_are_never_published_as_combat_wins() {
    let mut trainer = Trainer::fresh(scored_config("honest", staged()));
    run_units(&mut trainer, 80);
    let document = status_of(&trainer);

    // The factual counter is exact for a fresh run, and is the only number
    // here that may be called a combat win.
    assert_eq!(document["scoring"]["gate"], "crew-lead");
    assert_eq!(document["episodes_combat_counted_since"], 0);
    assert_eq!(document["episodes_combat_wins"], trainer.combat_wins);
    assert_eq!(document["episodes_combat_wins_all_time"], trainer.combat_wins);
    assert_eq!(document["episodes_unresolved"], trainer.unresolved);

    // A combat win is a subset of the episodes, and every episode that was not
    // resolved cannot have been one.
    assert!(trainer.combat_wins <= trainer.episodes - trainer.unresolved);
    every_number_is_finite(&document);
}

#[test]
fn a_gated_and_penalised_run_resumes_identically_on_the_real_simulator() {
    // The exact settings the staged run uses, across a real checkpoint decode.
    let mut straight = Trainer::fresh(scored_config("staged", staged()));
    run_units(&mut straight, 60);

    let mut stitched = Trainer::fresh(scored_config("staged", staged()));
    run_units(&mut stitched, 20);
    let saved = stitched.to_json();
    let mut stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
    assert_eq!(stitched.config.scoring, staged());
    run_units(&mut stitched, 40);

    assert_eq!(
        trajectory(&straight.to_json()),
        trajectory(&stitched.to_json()),
        "a gated and penalised run diverged after the restart point"
    );
    assert!(straight.episodes > 100, "expected real fights");
    assert!(straight.population.generation >= 2, "expected generations");
    assert_eq!(straight.combat_wins, stitched.combat_wins);
    assert_eq!(straight.combat_counted_since, 0);
    every_number_is_finite(&status_of(&straight));
}

#[test]
fn the_penalty_really_reaches_fitness_and_leaves_every_number_finite() {
    let unpenalised = ScoringConfig {
        fitness: Scoring::CrewRatio,
        gate: GateCriterion::CrewLead,
        no_damage_penalty: 0.0,
    };
    let penalised = ScoringConfig {
        no_damage_penalty: 1000.0,
        ..unpenalised
    };
    let mut off = Trainer::fresh(scored_config("penalty", unpenalised));
    let mut on = Trainer::fresh(scored_config("penalty", penalised));
    run_units(&mut off, 60);
    run_units(&mut on, 60);

    assert_ne!(
        trajectory(&off.to_json()),
        trajectory(&on.to_json()),
        "the penalty made no difference to selection at all"
    );
    // A run whose panels can score -1000 must still round-trip and still
    // publish finite numbers everywhere.
    let saved = on.to_json();
    let back = Trainer::from_json(&saved).expect("a penalised run must restore");
    assert_eq!(trajectory(&back.to_json()), trajectory(&saved));
    every_number_is_finite(&status_of(&on));
    every_number_is_finite(&saved);
}

#[test]
fn a_legacy_checkpoint_without_the_combat_counter_reports_no_all_time_figure() {
    let mut trainer = Trainer::fresh(config("legacy-counter"));
    run_units(&mut trainer, 40);
    let mut saved = trainer.to_json();
    let episodes = saved["episodes"].as_u64().unwrap();
    assert!(episodes > 0, "expected real fights");

    // Exactly what a checkpoint written before the counter existed looks like.
    let object = saved.as_object_mut().unwrap();
    object.remove("combat_wins");
    object.remove("combat_counted_since");

    let restored = Trainer::from_json(&saved).expect("a legacy checkpoint must still restore");
    // The window opens HERE rather than claiming the missing history was zero
    // victories, and no all-time figure is published for it.
    assert_eq!(restored.combat_wins, 0);
    assert_eq!(restored.combat_counted_since, episodes);
    let document = status_of(&restored);
    assert_eq!(document["episodes_combat_wins"], 0);
    assert_eq!(document["episodes_combat_counted_since"], episodes);
    assert_eq!(document["episodes_combat_wins_all_time"], Value::Null);
}

#[test]
fn a_malformed_combat_counter_is_refused_rather_than_read_as_a_known_zero() {
    let mut trainer = Trainer::fresh(config("corrupt-counter"));
    run_units(&mut trainer, 40);
    let good = trainer.to_json();
    let episodes = good["episodes"].as_u64().unwrap();
    assert!(episodes > 2, "expected real fights");

    // The honest checkpoint restores, so every rejection below is about the
    // tampering and not about the rest of the document.
    assert!(Trainer::from_json(&good).is_ok());

    let strip = |field: &str| {
        let mut document = good.clone();
        document.as_object_mut().unwrap().remove(field);
        document
    };
    let set = |field: &str, value: Value| {
        let mut document = good.clone();
        document[field] = value;
        document
    };

    for (why, bad) in [
        // Half a pair says nothing about the other half.
        ("wins present without its window", strip("combat_counted_since")),
        ("window present without its wins", strip("combat_wins")),
        // A null is not a count, and neither is a string or a fraction.
        ("null wins", set("combat_wins", Value::Null)),
        ("null window", set("combat_counted_since", Value::Null)),
        ("string wins", set("combat_wins", Value::String("3".into()))),
        ("fractional wins", set("combat_wins", Value::from(1.5))),
        // as_u64 refuses a negative, which is what makes this a rejection
        // rather than a silent wrap to an enormous positive.
        ("negative wins", set("combat_wins", Value::from(-1))),
        ("negative window", set("combat_counted_since", Value::from(-1))),
        // A window that opens after the run ended describes no episodes.
        ("window past the end", set("combat_counted_since", Value::from(episodes + 1))),
        // More victories than the window can hold.
        ("more wins than episodes", set("combat_wins", Value::from(episodes + 1))),
    ] {
        assert!(
            Trainer::from_json(&bad).is_err(),
            "{why} should have been refused"
        );
    }

    // More victories than the run has resolved fights to give them. The bound
    // holds whatever window the count covers, so it is checked both ways.
    for since in [0, 1] {
        let mut overclaimed = good.clone();
        overclaimed["combat_counted_since"] = Value::from(since);
        overclaimed["combat_wins"] = Value::from(episodes - since);
        // One more unresolved fight than the window leaves room for, so the
        // claim exceeds the resolved bound in both cases rather than only the
        // whole-run one.
        overclaimed["unresolved"] = Value::from(since + 1);
        assert!(
            Trainer::from_json(&overclaimed).is_err(),
            "more victories than resolved fights should have been refused \
             for a window opening at {since}"
        );
    }

    // Counts near the top of the range. Every bound is a subtraction from the
    // episode total rather than a sum of two decoded counts, so none of these
    // can wrap into looking reasonable.
    for (why, wins, since, unresolved) in [
        ("max wins", u64::MAX, 0, 0),
        ("max window", 0, u64::MAX, 0),
        ("both at max", u64::MAX, u64::MAX, 0),
        ("max unresolved", 0, 0, u64::MAX),
        // The pair that a sum would wrap to zero and wave through.
        ("wins and unresolved summing past the range", u64::MAX, 0, 1),
        ("wins and window summing past the range", u64::MAX, 1, 0),
    ] {
        let mut tampered = good.clone();
        tampered["combat_wins"] = Value::from(wins);
        tampered["combat_counted_since"] = Value::from(since);
        tampered["unresolved"] = Value::from(unresolved);
        assert!(
            Trainer::from_json(&tampered).is_err(),
            "{why} should have been refused"
        );
    }

    // And the boundary case that is merely unusual, not impossible, is kept:
    // a window covering the whole run with every resolved fight won.
    let mut perfect = good.clone();
    perfect["combat_counted_since"] = Value::from(0);
    perfect["unresolved"] = Value::from(0);
    perfect["combat_wins"] = Value::from(episodes);
    assert_eq!(perfect["episodes"].as_u64(), Some(episodes));
    let back = Trainer::from_json(&perfect).expect("a perfect record is possible, not malformed");
    assert_eq!(back.combat_wins, episodes);
    assert_eq!(back.combat_counted_since, 0);
}


/// The dashboard's checkpoint generation must be the generation a resume would
/// actually start from, not the one the trainer happens to have reached.
#[test]
fn the_reported_checkpoint_generation_is_the_one_on_disk() {
    let mut trainer = Trainer::fresh(config("saved-generation"));
    let status = |t: &Trainer| {
        t.status(
            melee_mario::status::Phase::Training,
            "test",
            "checkpoint.json",
            false,
        )
    };

    // Nothing saved yet, so there is no checkpoint generation to report and
    // the run is not resumable.
    assert_eq!(trainer.saved_generation, None);
    assert_eq!(status(&trainer)["checkpoint"]["generation"], Value::Null);
    assert_eq!(
        status(&trainer)["checkpoint"]["resumable"],
        Value::Bool(false)
    );

    // A save that happened at generation zero, then several generations of
    // work on top of it: the document still describes the saved one.
    trainer.saved_at = Some("1970-01-01T00:00:00Z".to_string());
    trainer.saved_generation = Some(trainer.population.generation);
    let saved = trainer.population.generation;
    while trainer.population.generation < saved + 2 {
        trainer.step();
    }
    assert!(trainer.population.generation > saved);
    assert_eq!(
        status(&trainer)["checkpoint"]["generation"],
        Value::from(saved)
    );
    assert_eq!(
        status(&trainer)["checkpoint"]["resumable"],
        Value::Bool(true)
    );

    // And a decoded checkpoint takes it from the population it restored,
    // never from a field of its own, so a copied document cannot carry a
    // stale claim about what is on disk.
    let document = trainer.to_json();
    assert!(
        document.get("saved_generation").is_none(),
        "the saved generation is derived, not persisted"
    );
    let restored = Trainer::from_json(&document).expect("the checkpoint must decode");
    assert_eq!(
        restored.saved_generation,
        Some(restored.population.generation)
    );
}
