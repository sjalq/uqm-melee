//! Training on the whole board, and the balanced aggregate gate over it.
//!
//! Like `restart_equivalence`, every unit of work here drives the REAL
//! simulator through `melee_neat::eval`: real fights, a real population, real
//! readiness probes and a real held-out round. The budgets are small so the
//! file finishes in seconds, but no code path is stood in for.
//!
//! Run just this file with:
//!
//!   cargo test -j 2 -p melee-mario --test broad_gate -- --test-threads=2

use melee_mario::broad::{self, BroadConfig, Opponent};
use melee_mario::neat::NeatConfig;
use melee_mario::trainer::{Config, Trainer};
use melee_sim::input::CyborgRating;
use serde_json::Value;

fn config(run: &str) -> Config {
    Config {
        run_id: run.to_string(),
        salt: 0x5eed_1234,
        // These tests are about the board and the gate, not about scoring, so
        // they keep the default scorer every existing run was trained under.
        scoring: melee_mario::episode::ScoringConfig::default(),
        ticks: 420,
        rating: CyborgRating::AwesomeCyborg,
        neat: NeatConfig {
            population: 8,
            stale_species: 3,
            ..NeatConfig::default()
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

fn run_units(trainer: &mut Trainer, units: usize) {
    for _ in 0..units {
        trainer.step();
    }
}

/// A run that has trained long enough to have a champion, scored genomes and a
/// non-trivial RNG position.
fn trained(run: &str) -> Trainer {
    let mut trainer = Trainer::fresh(config(run));
    run_units(&mut trainer, 60);
    assert!(trainer.champion.is_some(), "the run needs a champion");
    assert!(trainer.population.generation >= 2);
    trainer
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
fn a_fresh_run_opens_on_the_whole_board_and_claims_nothing() {
    let trainer = Trainer::fresh(config("fresh"));
    let status = status_of(&trainer);
    assert_eq!(status["schema_version"], melee_mario::status::SCHEMA_VERSION);
    assert_eq!(status["board"]["total_matchups"], 625);
    assert_eq!(status["board"]["evaluation_scope"], "overall-balanced");
    assert_eq!(status["readiness"]["purpose"], "balanced readiness");
    // Every ordered matchup is listed, and not one of them has been seen.
    let matchups = status["matchups"].as_array().unwrap();
    assert_eq!(matchups.len(), 625);
    assert!(matchups.iter().all(|row| row["status"] == "unseen"));
    assert!(matchups.iter().all(|row| row["training_win_rate"].is_null()));
    // Nothing is claimed: no aggregate has been measured yet.
    assert_eq!(status["overall"]["games"], 0);
    assert_eq!(status["overall"]["passed"], false);
    assert!(status["overall"]["passed_by"].is_null());
    assert_eq!(status["ship_performance"].as_array().unwrap().len(), 0);
    // The seeding event says what the run actually is.
    let seeded = trainer
        .events
        .iter()
        .find(|e| e.message.contains("625 ordered matchups active"))
        .expect("the run must record the board it opened on");
    assert!(seeded.message.contains("balanced aggregate"), "{seeded:?}");
}

#[test]
fn a_run_resumes_exactly_through_training_probing_and_a_held_out_round() {
    const UNITS: usize = 120;

    let mut straight = Trainer::fresh(config("resume"));
    let mut stitched = Trainer::fresh(config("resume"));
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
    assert!(straight.population.generation >= 2, "no generation completed");
    let expected = trajectory(&straight.to_json());
    let actual = trajectory(&stitched.to_json());
    if expected != actual {
        let (left, right) = (expected.as_object().unwrap(), actual.as_object().unwrap());
        let differing: Vec<&String> = left
            .keys()
            .filter(|key| left.get(*key) != right.get(*key))
            .collect();
        panic!("resumed trajectory diverged in fields: {differing:?}");
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
fn training_spreads_over_the_whole_board_and_plays_both_seats() {
    let mut trainer = Trainer::fresh(config("spread"));
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
        "training stayed on {} cell(s)",
        played.len()
    );
    assert!(
        played.iter().all(|(cell, _)| cell.foe == Opponent::Cyborg),
        "training played something other than the graded opponent"
    );
    // Both our hulls and theirs moved around, rather than one pair repeating.
    let ours: std::collections::BTreeSet<u8> = played.iter().map(|(c, _)| c.us).collect();
    let theirs: std::collections::BTreeSet<u8> = played.iter().map(|(c, _)| c.them).collect();
    assert!(ours.len() > 4 && theirs.len() > 4, "the board barely moved");
    // And a panel of a generation covers both seats.
    let panel = trainer.panel.as_ref().expect("a panel is open");
    assert!(panel.tasks.iter().any(|t| t.swap));
    assert!(panel.tasks.iter().any(|t| !t.swap));
}

#[test]
fn the_gate_runs_for_real_and_the_status_document_stays_honest() {
    let mut trainer = Trainer::fresh(config("gated"));
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
        "the readiness probe never opened a held-out round that played anything"
    );
    assert_eq!(status["schema_version"], melee_mario::status::SCHEMA_VERSION);
    assert_eq!(status["board"]["total_matchups"], 625);

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
    // No matchup is ever "mastered": nothing in this run gates per cell.
    assert!(status["matchups"]
        .as_array()
        .unwrap()
        .iter()
        .all(|row| row["status"] == "learning" || row["status"] == "unseen"));

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

    let mut trainer = trained("confirming");
    let champion = trainer
        .champion
        .as_ref()
        .map(|g| g.fingerprint())
        .expect("the run has a champion");
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
    // This candidate is weak, so the gate must NOT have passed.
    assert!(
        resumed.broad_gate.is_none(),
        "a losing confirmation passed the gate"
    );
    assert!(!resumed.gate_passed());

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

/// Passing the gate names ONE champion, keeps the run training, and does not
/// let that champion be re-audited on fresh withheld evidence it has already
/// earned.
///
/// The gate proof outlives the champion that earned it, so by the first
/// promotion afterwards the confirmation evidence beside it is already gone. A
/// decoder that insisted the two travel together made every checkpoint from
/// that moment on unresumable.
#[test]
fn the_gate_proof_outlives_the_champion_that_earned_it() {
    use melee_mario::audit::Round;
    use melee_mario::broad::{balanced_panel, Evaluation, Overall, Source};
    use melee_mario::rng::StreamTag;
    use melee_mario::trainer::Mode;

    let mut trainer = trained("passing");
    let winner = trainer
        .champion
        .as_ref()
        .map(|g| g.fingerprint())
        .expect("the run has a champion");
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
        reading
    };
    let audit = tallied(StreamTag::Audit, Source::Audit);
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

    // The gate passed for a NAMED champion, and the run went straight back to
    // training rather than into some further phase.
    let proof = trainer
        .broad_gate
        .as_ref()
        .expect("the gate recorded its pass");
    assert_eq!(proof.champion, winner);
    assert_eq!(proof.source.as_str(), "confirm");
    assert!(trainer.gate_passed());
    assert_eq!(trainer.phase(), "training");
    assert_eq!(trainer.round(), None);
    let status = status_of(&trainer);
    assert_eq!(status["overall"]["passed"], true);
    assert_eq!(status["overall"]["passed_by"], winner.as_str());
    assert!(Trainer::from_json(&trainer.to_json()).is_ok());

    // A champion that has already cleared both rounds is not re-audited: doing
    // so would spend withheld evidence re-answering a settled question.
    let spent = trainer.audit_attempt;
    for _ in 0..200 {
        trainer.step();
        if trainer.champion.as_ref().map(|g| g.fingerprint()).as_deref()
            != Some(winner.as_str())
        {
            break;
        }
        assert_eq!(trainer.round(), None, "the passed champion was re-audited");
    }
    assert_eq!(trainer.audit_attempt, spent, "a held-out round was spent");

    // Now replace the champion, which is what discards the confirmation beside
    // the proof. Real generations, real fights.
    let mut replaced = false;
    for _ in 0..900 {
        trainer.step();
        if trainer.champion.as_ref().map(|g| g.fingerprint()).as_deref()
            != Some(winner.as_str())
        {
            replaced = true;
            break;
        }
    }
    assert!(
        replaced,
        "no champion replacement happened, so nothing was proved"
    );
    assert!(
        trainer.broad_confirm.is_none() && trainer.broad_audit.is_none(),
        "evidence for a replaced champion survived"
    );
    let proof = trainer.broad_gate.as_ref().expect("the proof was discarded");
    assert_eq!(proof.champion, winner, "the proof was reattributed");
    assert!(!trainer.gate_passed(), "the pass was inherited");

    // THE REGRESSION: this checkpoint has a gate proof and no confirmation.
    let saved = trainer.to_json();
    let resumed = Trainer::from_json(&saved).expect("a passed run must stay resumable");
    assert_eq!(
        resumed.broad_gate.as_ref().map(|e| e.champion.clone()),
        Some(winner.clone())
    );

    // And the pass is reported as a fact about a NAMED champion, not inherited
    // by whoever holds the title now.
    let status = status_of(&resumed);
    assert_eq!(status["overall"]["passed"], false);
    assert_eq!(status["overall"]["passed_by"], winner.as_str());

    // A proof whose own numbers do not clear the target is still refused.
    let mut forged = saved.clone();
    forged["broad_gate"]["wins"] = serde_json::json!(30);
    assert!(Trainer::from_json(&forged).is_err());
}

#[test]
fn a_checkpoint_from_the_staged_schema_is_refused_rather_than_reinterpreted() {
    let trainer = trained("schema");
    let saved = trainer.to_json();
    assert!(Trainer::from_json(&saved).is_ok());
    assert_eq!(saved["schema_version"], melee_mario::checkpoint::SCHEMA_VERSION);

    // Schema 1 numbered cells by an expansion order this build does not have,
    // so the same indices name different hulls. Reading one would resume a run
    // about matchups that were never played.
    let mut older = saved.clone();
    older["schema_version"] = serde_json::json!(1);
    assert!(Trainer::from_json(&older).is_err());

    // Held-out evidence belongs to the champion it measured.
    let mut tampered = saved.clone();
    if !tampered["broad_ready"].is_null() {
        tampered["broad_ready"]["champion"] = serde_json::json!("bsomeoneelse");
        assert!(Trainer::from_json(&tampered).is_err());
    }

    // And a cell naming an opponent this build does not implement is refused
    // rather than narrowed into the one it does.
    let board = broad::board();
    assert_eq!(board.len(), 625);
    assert!(melee_mario::broad::Cell::decode(&serde_json::json!(["model", 0, 0])).is_none());
}
