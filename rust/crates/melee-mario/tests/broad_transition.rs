//! Forking a staged run into any-versus-any, and training and gating in it.
//!
//! Like `restart_equivalence`, every unit of work here drives the REAL
//! simulator through `melee_neat::eval`: real fights, a real population, real
//! readiness probes and a real held-out round. The budgets are small so the
//! file finishes in seconds, but no code path is stood in for.
//!
//! Run just this file with:
//!
//!   cargo test -j 2 -p melee-mario --test broad_transition -- --test-threads=2

use melee_mario::audit::AuditConfig;
use melee_mario::broad::BroadConfig;
use melee_mario::curriculum::{self, Opponent};
use melee_mario::neat::NeatConfig;
use melee_mario::sampler::SamplerConfig;
use melee_mario::trainer::{Config, Ladder, Trainer};
use melee_sim::input::CyborgRating;
use serde_json::Value;

fn config(run: &str) -> Config {
    Config {
        run_id: run.to_string(),
        salt: 0x5eed_1234,
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
            // One matching per round, so a held-out round is fifty games.
            pairs: 25,
            ..BroadConfig::default()
        },
        duty: 1.0,
        readiness_games: 4,
        readiness_threshold: 0.0,
        readiness_period: 2,
        regression_budget: 30,
    }
}

fn trajectory(document: &Value) -> Value {
    let mut stripped = document.clone();
    let object = stripped.as_object_mut().expect("checkpoint is an object");
    object.remove("saved_at");
    object.remove("elapsed_seconds");
    if let Some(events) = object.get_mut("events").and_then(Value::as_array_mut) {
        for event in events.iter_mut() {
            if let Some(entry) = event.as_object_mut() {
                entry.remove("at");
            }
        }
    }
    stripped
}

/// Every genome in the population, in order, as its exact serialised form.
/// Float weights go through the bit-exact round trip the genome schema uses.
fn genomes(trainer: &Trainer) -> Vec<Value> {
    trainer.population.to_json()["species"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|species| {
            species["members"]
                .as_array()
                .unwrap()
                .iter()
                .map(|member| member["genome"].clone())
                .collect::<Vec<_>>()
        })
        .collect()
}

fn run_units(trainer: &mut Trainer, units: usize) {
    for _ in 0..units {
        trainer.step();
    }
}

/// A staged run that has trained long enough to have a champion, gate evidence,
/// scored genomes and a non-trivial RNG position.
fn staged() -> Trainer {
    let mut trainer = Trainer::fresh(config("staged-source"));
    run_units(&mut trainer, 60);
    assert!(trainer.champion.is_some(), "the source needs a champion");
    assert!(trainer.population.generation >= 2);
    trainer
}

#[test]
fn the_fork_carries_the_policy_across_and_leaves_the_measurements_behind() {
    let before = staged();
    let mut after = Trainer::from_json(&before.to_json()).expect("source decodes");
    after.broaden("broad-target", "operator requested any-versus-any")
        .expect("an Awesome source forks");

    // CARRIED: every genome bit for bit, the species structure, the innovation
    // counter, the champion and its drifted rates, both RNG streams, the
    // sampler's decayed statistics, and the episode and timing totals.
    assert_eq!(
        genomes(&after),
        genomes(&before),
        "a genome changed across the fork"
    );
    assert_eq!(
        after.population.innovations.to_json(),
        before.population.innovations.to_json()
    );
    assert_eq!(after.population.generation, before.population.generation);
    assert_eq!(after.population.species.len(), before.population.species.len());
    assert_eq!(
        after.champion.as_ref().map(|g| g.to_json()),
        before.champion.as_ref().map(|g| g.to_json()),
        "the champion's weights changed across the fork"
    );
    assert_eq!(
        after.champion_rates.to_json(),
        before.champion_rates.to_json()
    );
    // RNG state is compared as the exact serialised bit pattern.
    assert_eq!(after.evolution.to_json(), before.evolution.to_json());
    assert_eq!(after.sampling.to_json(), before.sampling.to_json());
    assert_eq!(after.stats.issued, before.stats.issued);
    assert_eq!(after.episodes, before.episodes);
    assert_eq!(after.unresolved, before.unresolved);
    assert_eq!(after.compute, before.compute);

    // LEFT BEHIND: every measurement of the old distribution.
    assert!(after.evidence.is_empty(), "gate evidence survived the fork");
    assert!(after.priority.is_empty());
    assert!(after.panel.is_none());
    assert!(
        after.population.members().all(|m| m.fitness.is_none()),
        "a fitness from the abandoned panel survived"
    );
    assert_eq!(after.last_training_wins, None);
    assert_eq!(after.mastered(), 0, "the fork claimed mastered matchups");

    // SCOPE: the whole board, unlocked by the transition rather than earned.
    assert_eq!(after.ladder, Ladder::Broad);
    assert_eq!(after.stage, curriculum::FINAL_STAGE);
    assert_eq!(after.cyborg_cells().len(), 625);
    assert!(after.model_cells().is_empty(), "broad must not play models yet");
    assert_eq!(after.config.run_id, "broad-target");

    // PROVENANCE: where it came from, and what the fork gave up.
    let origin = after.origin.as_ref().expect("the fork records its origin");
    assert_eq!(origin.run_id, "staged-source");
    assert_eq!(origin.generation, before.population.generation);
    assert_eq!(origin.fingerprint, before.evaluator);
    assert_eq!(origin.reason, "operator requested any-versus-any");
    let transition = after
        .events
        .iter()
        .find(|e| e.message.contains("scope changed to any-versus-any"))
        .map(|e| e.message.clone())
        .expect("the abandonment must be recorded, not performed quietly");
    assert!(transition.contains("NOTHING is mastered"), "{transition}");
    assert!(transition.contains("abandoned"), "{transition}");
    assert!(transition.contains("staged-source"), "{transition}");

    // HISTORY: the scope change is a visible step, not an unexplained jump.
    let last = after.history.back().expect("a transition row");
    assert_eq!(last.stage, curriculum::FINAL_STAGE);
    assert_eq!(last.generation, before.population.generation);
    assert!(
        before.history.iter().all(|row| row.stage < curriculum::FINAL_STAGE),
        "the source was already on the full board"
    );
}

#[test]
fn the_fork_takes_a_baseline_reading_before_the_first_broad_generation() {
    let mut trainer = staged();
    let generation = trainer.population.generation;
    trainer
        .broaden("baseline", "operator requested any-versus-any")
        .expect("an Awesome source forks");

    // The very first units of work are the probe, not a training panel.
    assert_eq!(trainer.phase(), "training");
    assert!(trainer.broad_ready.is_some(), "no baseline probe was armed");
    let episodes = trainer.episodes;
    for _ in 0..40 {
        trainer.step();
        if trainer.broad_ready.as_ref().is_some_and(|r| r.games > 0) {
            break;
        }
    }
    let reading = trainer.broad_ready.as_ref().expect("the probe ran");
    assert!(reading.games > 0, "the baseline probe played nothing");
    assert!(trainer.episodes > episodes, "the probe simulated no fights");
    assert_eq!(
        trainer.population.generation, generation,
        "the baseline was taken after a generation had already been trained"
    );
    // It is a diagnostic, and says so: readiness is never gate evidence.
    assert_eq!(reading.source.as_str(), "ready");
    let status = trainer.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["readiness"]["purpose"], "broad balanced readiness");
    assert!(status["ship_performance"]
        .as_array()
        .unwrap()
        .iter()
        .all(|row| row["source"] == "ready"));
}

#[test]
fn a_forked_run_resumes_exactly_through_training_probing_and_a_held_out_round() {
    const UNITS: usize = 120;

    let mut straight = staged();
    straight
        .broaden("resume-broad", "operator requested any-versus-any")
        .expect("an Awesome source forks");
    let forked_at = straight.population.generation;
    let mut stitched = Trainer::from_json(&straight.to_json()).expect("the fork must decode");
    run_units(&mut straight, UNITS);

    let mut restarts = 0;
    let mut done = 0;
    while done < UNITS {
        let chunk = (UNITS - done).min(7);
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

    assert!(restarts >= 15, "the test did not actually restart much");
    assert!(
        straight.population.generation > forked_at,
        "no broad generation completed: still at the generation {forked_at} the fork inherited"
    );
    let expected = trajectory(&straight.to_json());
    let actual = trajectory(&stitched.to_json());
    if expected != actual {
        let (left, right) = (expected.as_object().unwrap(), actual.as_object().unwrap());
        let differing: Vec<&String> = left
            .keys()
            .filter(|key| left.get(*key) != right.get(*key))
            .collect();
        panic!("resumed broad trajectory diverged in fields: {differing:?}");
    }
    // The RNG bit states and the champion's float weights came through the
    // whole sequence of checkpoint round trips unchanged in value.
    assert_eq!(straight.evolution.to_json(), stitched.evolution.to_json());
    assert_eq!(straight.sampling.to_json(), stitched.sampling.to_json());
    assert_eq!(
        straight.champion.as_ref().map(|g| g.to_json()),
        stitched.champion.as_ref().map(|g| g.to_json())
    );
}

#[test]
fn broad_training_spreads_over_the_whole_board_and_plays_both_seats() {
    let mut trainer = staged();
    trainer
        .broaden("spread", "operator requested any-versus-any")
        .expect("an Awesome source forks");
    run_units(&mut trainer, 200);

    // Coverage walked, and every fight it drew was a real cyborg matchup.
    assert!(trainer.coverage_cursor > 0, "the rotation never advanced");
    let played: Vec<_> = trainer
        .stats
        .cells
        .iter()
        .filter(|(_, stat)| stat.games > 0.0)
        .collect();
    assert!(
        played.len() > 8,
        "broad training stayed on {} cell(s)",
        played.len()
    );
    assert!(
        played.iter().all(|(cell, _)| cell.foe == Opponent::Cyborg),
        "broad training played a frozen model"
    );
    // Both our hulls and theirs moved around, rather than one pair repeating.
    let ours: std::collections::BTreeSet<u8> = played.iter().map(|(c, _)| c.us).collect();
    let theirs: std::collections::BTreeSet<u8> = played.iter().map(|(c, _)| c.them).collect();
    assert!(ours.len() > 4 && theirs.len() > 4, "the board barely moved");
}

#[test]
fn the_broad_gate_runs_for_real_and_the_status_document_stays_honest() {
    let mut trainer = staged();
    trainer
        .broaden("gated", "operator requested any-versus-any")
        .expect("an Awesome source forks");
    // A weak candidate on a fifty-game panel is settled arithmetically within a
    // couple of units, so the document is read at the first point the round has
    // actually played something rather than at some later fixed step.
    let mut status = Value::Null;
    for _ in 0..600 {
        trainer.step();
        if trainer.round().is_none() && trainer.broad_audit.is_none() {
            continue;
        }
        let document = trainer.status(
            melee_mario::status::Phase::Auditing,
            "test",
            "checkpoint.json",
            false,
        );
        if document["overall"]["games"].as_u64().unwrap_or(0) > 0 {
            status = document;
            break;
        }
    }
    assert!(
        !status.is_null(),
        "the readiness probe never opened an overall round that played anything"
    );
    assert_eq!(status["schema_version"], 1);
    assert_eq!(status["curriculum"]["ladder"], "broad");
    assert_eq!(status["curriculum"]["evaluation_scope"], "overall-balanced");
    assert_eq!(status["curriculum"]["stage_unlocked_externally"], true);
    assert_eq!(status["curriculum"]["origin_run_id"], "staged-source");
    assert_eq!(status["curriculum"]["total_matchups"], 625);
    // The board is active, but nothing on it is claimed as mastered.
    assert_eq!(status["curriculum"]["mastered_matchups"], 0);

    let overall = &status["overall"];
    assert_eq!(overall["scope"], "balanced-any-any");
    assert_eq!(overall["panel"], 50);
    assert_eq!(overall["pairs"], 25);
    // Either still in flight, or just finished and reported from its result.
    assert!(
        overall["round"] == "audit"
            || overall["round"] == "confirm"
            || overall["round"].is_null()
    );
    assert_eq!(overall["passed"], false);
    assert!(overall["games"].as_u64().unwrap() > 0);
    assert!(overall["champion_id"].as_str().unwrap().len() > 1);

    // Fifty per-hull rows, each carrying its own sample count and source, and
    // reporting OUR wins on both sides of the split.
    let rows = status["ship_performance"].as_array().unwrap();
    assert_eq!(rows.len(), 50);
    assert_eq!(rows.iter().filter(|r| r["side"] == "ours").count(), 25);
    assert_eq!(rows.iter().filter(|r| r["side"] == "opponent").count(), 25);
    for row in rows {
        assert!(row["games"].as_u64().is_some());
        // Unknown is null, never zero.
        if row["games"] == 0 {
            assert!(row["win_rate"].is_null() && row["lower_bound"].is_null());
        }
        assert!(row["wins"].as_u64().unwrap() <= row["games"].as_u64().unwrap());
    }
    let ours: u64 = rows
        .iter()
        .filter(|r| r["side"] == "ours")
        .map(|r| r["games"].as_u64().unwrap())
        .sum();
    assert_eq!(ours, overall["games"].as_u64().unwrap());

    assert_eq!(status["sampler"]["panel"], 4);
    assert_eq!(status["sampler"]["coverage"], 0.5);

    // Every number in the document is finite or explicitly absent.
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
fn a_staged_run_is_untouched_by_broad_mode_existing() {
    let staged = staged();
    let status = staged.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["curriculum"]["ladder"], "climbing");
    assert_eq!(status["curriculum"]["evaluation_scope"], "per-cell-ladder");
    assert_eq!(status["curriculum"]["stage_unlocked_externally"], false);
    assert!(status["curriculum"]["origin_run_id"].is_null());
    assert!(status["overall"].is_null(), "a staged run has no aggregate");
    assert!(status["sampler"].is_null());
    assert_eq!(status["ship_performance"].as_array().unwrap().len(), 0);
    assert_eq!(status["readiness"]["purpose"], "audit readiness");

    // And a checkpoint written before broad mode existed still resumes: the
    // new fields are all absent from it.
    let mut legacy = staged.to_json();
    let object = legacy.as_object_mut().unwrap();
    for key in [
        "origin",
        "coverage_cursor",
        "broad_ready",
        "broad_audit",
        "broad_confirm",
        "broad_gate",
        "broad_shown",
    ] {
        object.remove(key);
    }
    legacy["config"]
        .as_object_mut()
        .unwrap()
        .remove("broad");
    let restored = Trainer::from_json(&legacy).expect("an older checkpoint must still resume");
    assert_eq!(restored.ladder, Ladder::Climbing);
    assert_eq!(restored.stage, staged.stage);
    assert!(restored.origin.is_none());
    assert_eq!(restored.coverage_cursor, 0);
    assert_eq!(
        restored.champion.as_ref().map(|g| g.to_json()),
        staged.champion.as_ref().map(|g| g.to_json())
    );
}

/// A weak candidate never reaches the confirmation round on its own: the audit
/// settles against it first. So the confirmation state is BUILT here, from the
/// real panels and a self-consistent audit tally, and then everything after the
/// fixture is real: the decoder has to accept it, and the trainer has to carry
/// it through actual simulated fights to a decision.
#[test]
fn a_confirmation_round_resumes_and_only_exists_behind_a_passed_audit() {
    use melee_mario::audit::Round;
    use melee_mario::broad::{balanced_panel, Evaluation, Overall, Source};
    use melee_mario::rng::StreamTag;
    use melee_mario::trainer::Mode;

    let mut trainer = staged();
    trainer
        .broaden("confirming", "operator requested any-versus-any")
        .expect("an Awesome source forks");
    let champion = trainer
        .champion
        .as_ref()
        .map(|g| g.fingerprint())
        .expect("the fork carried a champion");
    let config = trainer.config.broad;
    let attempt = trainer.audit_attempt;
    let salt = trainer.config.salt;
    let ticks = trainer.config.ticks;

    // A passed audit, tallied over the real audit panel so the per-hull splits
    // add up exactly the way a played round's would. Forty-eight of fifty
    // clears a Wilson lower bound above 0.80; forty-five would not.
    let audit_panel = balanced_panel(StreamTag::Audit, salt, attempt, config.pairs, ticks);
    let mut audit = Evaluation::open(Source::Audit, champion.clone());
    for (at, task) in audit_panel.iter().enumerate() {
        audit.record(task.cell, at >= 2);
    }
    assert_eq!(audit.games, 50);
    assert!(
        audit.tally().lower_bound().unwrap() > config.target,
        "the fixture audit does not actually pass"
    );
    trainer.broad_audit = Some(audit);
    trainer.broad_shown = Some(Source::Audit);
    trainer.mode = Mode::Overall {
        gate: Overall::open(
            attempt,
            Round::Confirm,
            config.target,
            champion.clone(),
            balanced_panel(StreamTag::Confirm, salt, attempt, config.pairs, ticks),
        ),
    };

    // The decoder accepts it, because the audit behind it cleared.
    let saved = trainer.to_json();
    let mut resumed = Trainer::from_json(&saved).expect("a backed confirmation must resume");
    assert_eq!(resumed.round(), Some(Round::Confirm));
    let status = resumed.status(
        melee_mario::status::Phase::Auditing,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["overall"]["round"], "confirm");
    assert_eq!(status["overall"]["audit"]["passed"], true);
    assert_eq!(status["overall"]["confirm"]["passed"], false);
    assert_eq!(status["overall"]["passed"], false, "an audit is not a gate");

    // And from here it is real simulation: the round plays actual fights and
    // reaches a decision rather than sitting in flight forever.
    let episodes = resumed.episodes;
    let mut decided = false;
    for _ in 0..120 {
        resumed.step();
        if resumed.round().is_none() {
            decided = true;
            break;
        }
    }
    assert!(decided, "the confirmation round never resolved");
    assert!(resumed.episodes > episodes, "it resolved without fighting");
    let confirm = resumed
        .broad_confirm
        .as_ref()
        .expect("the confirmation recorded its result");
    assert_eq!(confirm.source.as_str(), "confirm");
    assert_eq!(confirm.champion, champion);
    assert!(confirm.games > 0);
    // This candidate is weak, so the gate must NOT have passed, the run must
    // still be broad, and no frozen self-play opponent may have appeared.
    assert!(resumed.broad_gate.is_none(), "a losing confirmation passed the gate");
    assert_eq!(resumed.ladder, Ladder::Broad);
    assert!(resumed.frozen_opponent.is_none());

    // Without the audit behind it, the same confirmation is refused: a
    // confirmation is the second half of a gate, never a gate on its own.
    let mut forged = saved.clone();
    forged["broad_audit"] = Value::Null;
    assert!(
        Trainer::from_json(&forged).is_err(),
        "a confirmation was resumed with no audit behind it"
    );
    // A failing audit is no better than a missing one.
    let mut failing = Evaluation::open(Source::Audit, champion.clone());
    for (at, task) in audit_panel.iter().enumerate() {
        failing.record(task.cell, at >= 20);
    }
    assert!(failing.tally().lower_bound().unwrap() <= config.target);
    let mut forged = saved.clone();
    forged["broad_audit"] = failing.to_json();
    assert!(
        Trainer::from_json(&forged).is_err(),
        "a confirmation was resumed behind an audit that failed"
    );
}

/// Passing the gate and then replacing the champion must still produce a
/// resumable checkpoint.
///
/// The gate proof outlives the champion that earned it, so by the first
/// promotion afterwards the confirmation evidence beside it is already gone.
/// A decoder that insisted the two travel together made every checkpoint from
/// that moment on unresumable.
#[test]
fn the_gate_proof_outlives_the_champion_that_earned_it() {
    use melee_mario::audit::Round;
    use melee_mario::broad::{balanced_panel, Evaluation, Overall, Source};
    use melee_mario::rng::StreamTag;
    use melee_mario::trainer::Mode;

    let mut trainer = staged();
    trainer
        .broaden("passing", "operator requested any-versus-any")
        .expect("an Awesome source forks");
    let winner = trainer
        .champion
        .as_ref()
        .map(|g| g.fingerprint())
        .expect("the fork carried a champion");
    let config = trainer.config.broad;
    let attempt = trainer.audit_attempt;
    let (salt, ticks) = (trainer.config.salt, trainer.config.ticks);

    // Both rounds tallied over their REAL panels, so the per-hull splits add up
    // exactly as a played round's would. Forty-eight of fifty clears the bound.
    let tallied = |stream, source| {
        let panel = balanced_panel(stream, salt, attempt, config.pairs, ticks);
        let mut reading = Evaluation::open(source, winner.clone());
        for (at, task) in panel.iter().enumerate() {
            reading.record(task.cell, at >= 2);
        }
        (panel, reading)
    };
    let (_, audit) = tallied(StreamTag::Audit, Source::Audit);
    assert!(audit.tally().lower_bound().unwrap() > config.target);
    trainer.broad_audit = Some(audit);
    trainer.broad_shown = Some(Source::Audit);

    // A confirmation round already played out and won. Installing it decided
    // means the next unit of work goes straight through the real finishing
    // path: no simulator is stood in for, the fights are simply already over.
    let mut gate = Overall::open(
        attempt,
        Round::Confirm,
        config.target,
        winner.clone(),
        balanced_panel(StreamTag::Confirm, salt, attempt, config.pairs, ticks),
    );
    let mut at = 0;
    while gate.next_task().is_some() {
        gate.record(at >= 2);
        at += 1;
    }
    trainer.mode = Mode::Overall { gate };
    trainer.step();

    // The gate passed: the run keeps its broad provenance, enters the mixed
    // phase with a frozen opponent, and still claims nothing per cell.
    let proof = trainer.broad_gate.as_ref().expect("the gate recorded its pass");
    assert_eq!(proof.champion, winner);
    assert_eq!(proof.source.as_str(), "confirm");
    assert_eq!(trainer.ladder, Ladder::Mixed);
    assert!(trainer.frozen_opponent.is_some());
    assert_eq!(trainer.mastered(), 0, "the gate claimed per-cell mastery");
    assert!(trainer.origin.is_some(), "the fork provenance was forgotten");
    let status = trainer.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["curriculum"]["ladder"], "mixed");
    assert_eq!(status["curriculum"]["evaluation_scope"], "overall-balanced");
    assert_eq!(status["curriculum"]["origin_run_id"], "staged-source");
    assert_eq!(status["curriculum"]["mastered_matchups"], 0);
    assert_eq!(status["curriculum"]["self_play_is_gated"], false);
    assert_eq!(status["overall"]["passed"], true);
    assert_eq!(status["overall"]["passed_by"], winner.as_str());
    assert!(Trainer::from_json(&trainer.to_json()).is_ok());

    // Now replace the champion, which is what discards the confirmation beside
    // the proof. Real generations, real fights.
    let mut replaced = false;
    for _ in 0..900 {
        trainer.step();
        if trainer.champion.as_ref().map(|g| g.fingerprint()).as_deref() != Some(winner.as_str()) {
            replaced = true;
            break;
        }
    }
    assert!(replaced, "no champion replacement happened, so nothing was proved");
    assert!(
        trainer.broad_confirm.is_none() && trainer.broad_audit.is_none(),
        "evidence for a replaced champion survived"
    );
    let proof = trainer.broad_gate.as_ref().expect("the proof was discarded");
    assert_eq!(proof.champion, winner, "the proof was reattributed");

    // THE REGRESSION: this checkpoint has a gate proof and no confirmation.
    let saved = trainer.to_json();
    let resumed = Trainer::from_json(&saved).expect("a passed run must stay resumable");
    assert_eq!(
        resumed.broad_gate.as_ref().map(|e| e.champion.clone()),
        Some(winner.clone())
    );
    assert_eq!(resumed.ladder, Ladder::Mixed);

    // And the pass is reported as a fact about a NAMED champion, not inherited
    // by whoever holds the title now.
    let status = resumed.status(
        melee_mario::status::Phase::Training,
        "test",
        "checkpoint.json",
        false,
    );
    assert_eq!(status["overall"]["passed"], false);
    assert_eq!(status["overall"]["passed_by"], winner.as_str());

    // A proof whose own numbers do not clear the target is still refused.
    let mut forged = saved.clone();
    forged["broad_gate"]["wins"] = serde_json::json!(30);
    assert!(Trainer::from_json(&forged).is_err());
}

#[test]
fn a_checkpoint_cannot_claim_broad_scope_on_a_narrower_board() {
    let mut trainer = staged();
    trainer
        .broaden("narrowed", "operator requested any-versus-any")
        .expect("an Awesome source forks");
    let saved = trainer.to_json();
    assert!(Trainer::from_json(&saved).is_ok());

    // Broad means the whole board. A document claiming otherwise would sample
    // one distribution and gate another.
    let mut tampered = saved.clone();
    tampered["stage"] = serde_json::json!(3);
    assert!(Trainer::from_json(&tampered).is_err());

    // Broad evidence belongs to the champion it measured.
    let mut tampered = saved.clone();
    if !tampered["broad_ready"].is_null() {
        tampered["broad_ready"]["champion"] = serde_json::json!("bsomeoneelse");
        assert!(Trainer::from_json(&tampered).is_err());
    }
}
