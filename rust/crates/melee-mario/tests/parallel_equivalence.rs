//! A worker count must be invisible in the trajectory.
//!
//! The pool exists to spend more cores. If it also changed a single fitness
//! number, a counter, a panel cursor, a promotion or a random stream, it would
//! be a different trainer wearing the old one's name, and the checkpoint the
//! operator has been accumulating for a hundred generations would no longer
//! describe the run that continues from it. So every test here drives the REAL
//! simulator, at several worker counts, and demands that the checkpoint
//! documents match FIELD FOR FIELD, not merely that both runs look healthy.
//!
//! The comparison points are the ones a checkpoint is actually written at:
//! completed generations, and equal episode counts inside a generation. Unit
//! counts are deliberately NOT compared, because one unit of pooled work
//! scores several candidates and one unit of serial work scores one; that is
//! the whole point of the pool and the one thing allowed to differ.
//!
//! The budgets are small so the file finishes in a few seconds, and the worker
//! counts stay at two and three so the suite never fights the machine for
//! cores. The trajectory argument is about ordering, not about scale: two
//! workers reorder completion exactly as nine do.
//!
//! Run just this file with:
//!
//!   cargo test -j 2 -p melee-mario --test parallel_equivalence -- --test-threads=2

use melee_mario::audit::AuditConfig;
use melee_mario::broad::BroadConfig;
use melee_mario::episode::{GateCriterion, Scoring, ScoringConfig};
use melee_mario::neat::NeatConfig;
use melee_mario::sampler::SamplerConfig;
use melee_mario::trainer::{Config, Trainer};
use melee_sim::input::CyborgRating;
use serde_json::Value;

/// Worker counts every equivalence test sweeps. Bounded on purpose: this suite
/// runs beside a live trainer, and one and three prove the same thing nine do.
const COUNTS: [usize; 2] = [2, 3];

/// The run the equivalence tests drive. Small enough to finish quickly, and
/// large enough to turn several generations over, replace champions, run
/// readiness probes and open a real audit gate.
fn config(run: &str, scoring: ScoringConfig) -> Config {
    Config {
        scoring,
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

/// The legacy settings: the combat scorer, gated on actual wins, no penalty.
fn combat() -> ScoringConfig {
    ScoringConfig::default()
}

/// The staged settings the live run uses: crew-ratio fitness, a crew-lead gate
/// and a penalty for a fight that did the enemy no net harm. A different
/// scorer, a different success criterion and a different fitness distribution,
/// so the pool is proved under the arithmetic actually in production.
fn lead_gated() -> ScoringConfig {
    ScoringConfig {
        fitness: Scoring::CrewRatio,
        gate: GateCriterion::CrewLead,
        no_damage_penalty: 1000.0,
    }
}

/// Wall-clock facts and resource metadata differ between a run on one worker
/// and the same run on three. They are the ONLY things allowed to: everything
/// else in the document is trajectory and must match exactly.
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

fn trainer(run: &str, scoring: ScoringConfig, workers: usize) -> Trainer {
    let mut trainer = Trainer::fresh(config(run, scoring));
    trainer.use_workers(workers);
    assert_eq!(trainer.workers(), workers, "the pool must be the size asked for");
    trainer
}

/// Steps until the run has completed `target` generations. Both a serial and a
/// pooled trainer stop at the same place: a generation turns over inside
/// `close_panel`, which is the only thing its unit of work does.
fn run_to_generation(trainer: &mut Trainer, target: u32) {
    let mut guard = 0;
    while trainer.population.generation < target {
        trainer.step();
        guard += 1;
        assert!(guard < 20_000, "the run never reached generation {target}");
    }
}

/// Steps until exactly `target` episodes have been played, and fails rather
/// than overshooting: a comparison point that one run walked past is not a
/// comparison point.
fn run_to_episodes(trainer: &mut Trainer, target: u64) {
    let mut guard = 0;
    while trainer.episodes < target {
        trainer.step();
        guard += 1;
        assert!(guard < 20_000, "the run never reached {target} episodes");
    }
    assert_eq!(
        trainer.episodes, target,
        "a unit of work overshot the comparison point"
    );
}

fn panel_cursor(trainer: &Trainer) -> Option<usize> {
    trainer.panel.as_ref().map(|panel| panel.cursor)
}

fn diverging_fields(expected: &Value, actual: &Value) -> Vec<String> {
    let (left, right) = (
        expected.as_object().expect("object"),
        actual.as_object().expect("object"),
    );
    left.keys()
        .filter(|key| left.get(*key) != right.get(*key))
        .cloned()
        .collect()
}

fn assert_same(what: &str, expected: &Trainer, actual: &Trainer) {
    let left = trajectory(&expected.to_json());
    let right = trajectory(&actual.to_json());
    if left != right {
        panic!("{what}: diverged in fields {:?}", diverging_fields(&left, &right));
    }
}

#[test]
fn a_fresh_trainer_is_single_threaded_until_it_is_told_otherwise() {
    let plain = Trainer::fresh(config("default", combat()));
    assert_eq!(plain.workers(), 1, "the default must spawn no threads");
}

#[test]
fn one_worker_still_scores_exactly_one_candidate_per_unit() {
    // The legacy unit, on a panel that is NOT the default eight, so a unit
    // sized from a fight budget rather than from the population would show up.
    let mut solo = trainer("legacy-unit", combat(), 1);
    let unit = solo.step();
    assert_eq!(unit.episodes, 3, "one candidate over a panel of three");
    assert_eq!(panel_cursor(&solo), Some(1), "one candidate scored");
}

#[test]
fn a_pool_scores_several_candidates_per_unit_without_passing_the_population() {
    let mut pooled = trainer("pooled-unit", combat(), 3);
    let unit = pooled.step();
    assert!(
        unit.episodes > 3,
        "a pool of three should batch candidates, saw {} episodes",
        unit.episodes
    );
    assert_eq!(
        unit.episodes % 3,
        0,
        "a batch is whole candidates over the whole panel"
    );
    let scored = panel_cursor(&pooled).expect("a panel is open");
    assert_eq!(unit.episodes, scored as u64 * 3);
    assert!(
        scored <= pooled.population.size(),
        "a unit must never run past the population"
    );
}

#[test]
fn every_worker_count_reaches_the_same_state_under_the_combat_scorer() {
    const GENERATIONS: u32 = 4;
    let mut serial = trainer("combat-serial", combat(), 1);
    run_to_generation(&mut serial, GENERATIONS);
    // The run has to be doing real work for the comparison to mean anything.
    assert!(
        serial.episodes > 100,
        "expected real fights, saw {}",
        serial.episodes
    );
    assert!(serial.champion.is_some(), "expected a champion to exist");

    for workers in COUNTS {
        let mut pooled = trainer("combat-serial", combat(), workers);
        run_to_generation(&mut pooled, GENERATIONS);
        assert_same(&format!("{workers} workers"), &serial, &pooled);
        assert_eq!(pooled.episodes, serial.episodes, "episode counter");
        assert_eq!(pooled.unresolved, serial.unresolved, "unresolved counter");
        assert_eq!(pooled.combat_wins, serial.combat_wins, "combat win counter");
    }
}

#[test]
fn every_worker_count_reaches_the_same_state_under_the_lead_gated_scorer() {
    const GENERATIONS: u32 = 4;
    let mut serial = trainer("lead-serial", lead_gated(), 1);
    run_to_generation(&mut serial, GENERATIONS);
    assert!(serial.episodes > 100);

    for workers in COUNTS {
        let mut pooled = trainer("lead-serial", lead_gated(), workers);
        run_to_generation(&mut pooled, GENERATIONS);
        assert_same(&format!("{workers} workers, lead gate"), &serial, &pooled);
    }
}

#[test]
fn the_panel_cursor_and_counters_agree_part_way_through_a_generation() {
    // A pooled unit scores several candidates at once, so the comparison point
    // is taken FROM it: one pooled unit, then the serial run walked to the same
    // episode count one candidate at a time. That lands inside the first
    // generation, where the panel cursor and the sampler statistics are still
    // live state rather than something a turnover has already consumed.
    for workers in COUNTS {
        let mut pooled = trainer("mid-panel", lead_gated(), workers);
        let unit = pooled.step();
        assert!(unit.episodes > 3, "a pool should batch more than one candidate");
        assert_eq!(pooled.population.generation, 0, "still inside generation one");

        let mut serial = trainer("mid-panel", lead_gated(), 1);
        run_to_episodes(&mut serial, pooled.episodes);
        assert_eq!(panel_cursor(&pooled), panel_cursor(&serial), "panel cursor");
        assert_eq!(pooled.unresolved, serial.unresolved, "unresolved counter");
        assert_eq!(pooled.combat_wins, serial.combat_wins, "combat win counter");
        assert_same(&format!("mid-panel at {workers} workers"), &serial, &pooled);
    }
}

#[test]
fn a_mid_generation_checkpoint_resumes_on_a_different_worker_count() {
    const GENERATIONS: u32 = 4;
    let mut straight = trainer("crossed", lead_gated(), 1);
    run_to_generation(&mut straight, GENERATIONS);

    // Serial to a mid-generation safe point, checkpointed through the real
    // decoder, then finished on a pool. And the same crossing the other way.
    for (first, second) in [(1usize, 3usize), (3, 1), (2, 3)] {
        let mut stitched = trainer("crossed", lead_gated(), first);
        stitched.step();
        assert!(
            panel_cursor(&stitched).is_some_and(|cursor| cursor > 0),
            "the checkpoint must land inside a generation, not on its edge"
        );
        assert!(
            stitched.population.generation < GENERATIONS,
            "the checkpoint must land before the finish line"
        );
        let saved = stitched.to_json();
        let mut stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
        // A restored trainer is single-threaded until told otherwise, which is
        // exactly what makes the worker count safe to change on a resume.
        assert_eq!(stitched.workers(), 1);
        stitched.use_workers(second);
        run_to_generation(&mut stitched, GENERATIONS);
        assert_same(
            &format!("resumed from {first} workers onto {second}"),
            &straight,
            &stitched,
        );
    }
}

#[test]
fn repeated_checkpoints_across_changing_worker_counts_stay_on_trajectory() {
    const GENERATIONS: u32 = 4;
    let mut straight = trainer("rotating", combat(), 1);
    run_to_generation(&mut straight, GENERATIONS);

    // The worker count changes at EVERY restart, the way an operator raising
    // and lowering the knob across a long run would change it.
    let mut stitched = trainer("rotating", combat(), 1);
    let mut restarts = 0;
    for generation in 1..=GENERATIONS {
        let workers = COUNTS[generation as usize % COUNTS.len()];
        stitched.use_workers(workers);
        run_to_generation(&mut stitched, generation);
        let saved = stitched.to_json();
        stitched = Trainer::from_json(&saved).expect("checkpoint must restore");
        restarts += 1;
        assert_eq!(
            trajectory(&stitched.to_json()),
            trajectory(&saved),
            "restoring changed the state at generation {generation}"
        );
    }
    assert_eq!(restarts, GENERATIONS);
    assert_same("rotating worker counts", &straight, &stitched);
}

#[test]
fn the_worker_count_is_never_written_into_a_checkpoint() {
    let mut pooled = trainer("not-persisted", combat(), 3);
    run_to_generation(&mut pooled, 1);
    let saved = pooled.to_json();
    let text = saved.to_string();
    assert!(
        !text.contains("workers"),
        "a resource knob has no business in a run's state"
    );
    // And the fingerprint guard is untouched by it: the same binary produced
    // both, so a resume across worker counts is not a rebuilt evaluator.
    let restored = Trainer::from_json(&saved).expect("checkpoint must restore");
    assert_eq!(restored.evaluator, pooled.evaluator);
    assert_eq!(restored.workers(), 1);
}

#[test]
fn a_readiness_probe_and_an_audit_survive_the_pool() {
    // Generation four is past the second readiness probe, so this run really
    // has taken the probe path (pooled) and the gate path (serial) rather than
    // only the training path.
    const GENERATIONS: u32 = 6;
    let mut serial = trainer("gated", combat(), 1);
    run_to_generation(&mut serial, GENERATIONS);
    let probed = serial
        .history
        .iter()
        .filter(|row| row.validation_win_rate.is_some())
        .count();
    assert!(
        probed > 0,
        "the run never ran a readiness probe, so this test proves nothing"
    );

    for workers in COUNTS {
        let mut pooled = trainer("gated", combat(), workers);
        run_to_generation(&mut pooled, GENERATIONS);
        assert_eq!(pooled.phase(), serial.phase(), "phase");
        assert_eq!(
            pooled
                .history
                .iter()
                .map(|row| row.validation_win_rate)
                .collect::<Vec<_>>(),
            serial
                .history
                .iter()
                .map(|row| row.validation_win_rate)
                .collect::<Vec<_>>(),
            "readiness probe results"
        );
        assert_same(
            &format!("probing and gating on {workers} workers"),
            &serial,
            &pooled,
        );
    }
}
