//! The duty cap has to hold for the WHOLE run loop, not just for the part of
//! it that simulates fights.
//!
//! The first version of this governor measured only `Trainer::step` and then
//! rested in proportion to that. With small, fast panels the per-iteration
//! publish and checkpoint work was a large share of the iteration, so the
//! process used far more of a core than the cap allowed. These tests drive the
//! real command line, with the real server disabled, and check the share of
//! wall time the process actually spent computing.
//!
//!   cargo test -j 2 -p melee-mario --test governor -- --test-threads=1

use std::path::{Path, PathBuf};
use std::time::Instant;

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "melee-mario-governor-{name}-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn args(raw: &[&str]) -> Vec<String> {
    raw.iter().map(|s| s.to_string()).collect()
}

/// Runs a bounded training session and returns (wall seconds, checkpoint).
fn train(root: &Path, run: &str, duty: &str, episodes: &str) -> (f64, serde_json::Value) {
    let started = Instant::now();
    let code = melee_mario::cli::run(&args(&[
        "start",
        "--root",
        root.to_str().unwrap(),
        "--run",
        run,
        "--no-server",
        // The test process must not be re-niced out from under the harness.
        "--nice",
        "0",
        "--duty",
        duty,
        "--episodes",
        episodes,
        // Small and fast, which is precisely the shape that exposed the bug.
        "--population",
        "6",
        "--panel",
        "2",
        "--ticks",
        "240",
        "--readiness-period",
        "1000",
    ]));
    assert_eq!(code, 0, "the trainer exited with {code}");
    let wall = started.elapsed().as_secs_f64();
    let checkpoint = melee_mario::store::read_json(
        &melee_mario::store::run_dir(root, run).join(melee_mario::store::CHECKPOINT),
    )
    .expect("a checkpoint must exist");
    (wall, checkpoint)
}

#[test]
fn the_measured_duty_matches_the_cap_including_publishing_and_checkpointing() {
    let root = scratch("duty");
    let (wall, checkpoint) = train(&root, "quarter", "0.25", "600");

    let compute = checkpoint["compute_seconds"].as_f64().unwrap();
    let elapsed = checkpoint["elapsed_seconds"].as_f64().unwrap();
    assert!(compute > 0.0 && elapsed > 0.0, "nothing was measured");

    // The loop's own accounting must agree with the wall clock, otherwise the
    // dashboard is reporting a duty the machine does not see.
    assert!(
        (elapsed - wall).abs() < wall * 0.25 + 0.5,
        "the loop measured {elapsed:.2}s of a {wall:.2}s run"
    );

    let measured = compute / elapsed;
    assert!(
        measured <= 0.25 * 1.35,
        "asked for a quarter of a core and used {:.1}%",
        measured * 100.0
    );
    // And it must not be pathologically under either: a governor that never
    // works would pass the ceiling for the wrong reason.
    assert!(
        measured >= 0.25 * 0.4,
        "asked for a quarter of a core and used only {:.1}%",
        measured * 100.0
    );

    std::fs::remove_dir_all(&root).unwrap();
}

#[test]
fn a_full_duty_run_does_not_rest_at_all() {
    let root = scratch("full");
    let (_, checkpoint) = train(&root, "full", "1.0", "400");
    let compute = checkpoint["compute_seconds"].as_f64().unwrap();
    let elapsed = checkpoint["elapsed_seconds"].as_f64().unwrap();
    let measured = compute / elapsed;
    assert!(
        measured > 0.9,
        "an uncapped run should be nearly all compute, measured {:.1}%",
        measured * 100.0
    );
    std::fs::remove_dir_all(&root).unwrap();
}

#[test]
fn a_resumed_run_rests_at_the_duty_it_reports() {
    // The governor used to read the session's default while the dashboard read
    // the restored value, so a run checkpointed at a quarter of a core resumed
    // at a half and said a quarter.
    let root = scratch("authoritative");
    let (_, first) = train(&root, "keeps", "0.25", "150");
    assert_eq!(first["config"]["duty"].as_f64().unwrap(), 0.25);

    // Resume WITHOUT naming a duty: the run's own value must still govern.
    let code = melee_mario::cli::run(&args(&[
        "resume",
        "--root",
        root.to_str().unwrap(),
        "--run",
        "keeps",
        "--no-server",
        "--nice",
        "0",
        "--episodes",
        "400",
    ]));
    assert_eq!(code, 0);
    let dir = melee_mario::store::run_dir(&root, "keeps");
    let after = melee_mario::store::read_json(&dir.join(melee_mario::store::CHECKPOINT)).unwrap();
    assert_eq!(after["config"]["duty"].as_f64().unwrap(), 0.25);
    let session_compute = after["compute_seconds"].as_f64().unwrap()
        - first["compute_seconds"].as_f64().unwrap();
    let session_elapsed =
        after["elapsed_seconds"].as_f64().unwrap() - first["elapsed_seconds"].as_f64().unwrap();
    let measured = session_compute / session_elapsed;
    assert!(
        measured <= 0.25 * 1.35,
        "resumed session used {:.1}% of a core against a stored cap of 25%",
        measured * 100.0
    );

    // An explicit --duty is allowed, and then the run records the new value so
    // the dashboard and the governor still agree.
    let code = melee_mario::cli::run(&args(&[
        "resume",
        "--root",
        root.to_str().unwrap(),
        "--run",
        "keeps",
        "--no-server",
        "--nice",
        "0",
        "--duty",
        "1.0",
        "--episodes",
        "100",
    ]));
    assert_eq!(code, 0);
    let changed = melee_mario::store::read_json(&dir.join(melee_mario::store::CHECKPOINT)).unwrap();
    assert_eq!(changed["config"]["duty"].as_f64().unwrap(), 1.0);
    std::fs::remove_dir_all(&root).unwrap();
}

#[test]
fn a_bounded_run_is_resumable_and_the_lock_is_exclusive() {
    let root = scratch("resume");
    let (_, first) = train(&root, "twice", "1.0", "200");
    let episodes = first["episodes"].as_u64().unwrap();
    assert!(episodes >= 200);

    // While a lock is held, a second trainer must refuse rather than join in.
    let dir = melee_mario::store::run_dir(&root, "twice");
    let held = melee_mario::store::RunLock::acquire(&dir).unwrap();
    let blocked = melee_mario::cli::run(&args(&[
        "resume",
        "--root",
        root.to_str().unwrap(),
        "--run",
        "twice",
        "--no-server",
        "--nice",
        "0",
        "--episodes",
        "1",
    ]));
    assert_ne!(blocked, 0, "a second trainer joined a locked run");
    drop(held);

    let code = melee_mario::cli::run(&args(&[
        "resume",
        "--root",
        root.to_str().unwrap(),
        "--run",
        "twice",
        "--no-server",
        "--nice",
        "0",
        "--episodes",
        "200",
    ]));
    assert_eq!(code, 0, "the run did not resume");
    let after = melee_mario::store::read_json(&dir.join(melee_mario::store::CHECKPOINT)).unwrap();
    assert!(
        after["episodes"].as_u64().unwrap() > episodes,
        "resuming did not continue the run"
    );
    std::fs::remove_dir_all(&root).unwrap();
}
