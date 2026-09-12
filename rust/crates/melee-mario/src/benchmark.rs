//! The fixed-work benchmark: the same work, every time, on any machine.
//!
//! WHAT THE OLD ONE MEASURED. It seeded a stream, applied forty mutations,
//! compiled whatever topology the random number generator happened to produce,
//! played forty fights of ONE curriculum cell, and divided by a single wall
//! clock. Three separate things made two builds incomparable:
//!
//!   * the workload was an accident. Change the mutation code, the innovation
//!     book, the default seed or the seed genome's connect probability and the
//!     benchmark evaluates a different network, because `Network::activate`
//!     costs exactly its node and link counts.
//!   * one matchup is not the roster. Collision cost scales with sprite sizes,
//!     the observation encoder only walks mounts for missile-armed hulls, and
//!     satellites, shards and fighters exist for a handful of hulls. A
//!     regression in any of those was invisible.
//!   * a fight stops at a victory. A policy that learns to win faster
//!     simulates less, and fights-per-second calls that a speedup.
//!
//! WHAT THIS ONE PINS. A genome checked into the repository, so no change to
//! the evolution code can move the workload. A fixed ordered task list that
//! spans the roster's weapon and special systems, each pairing played from
//! both seats on two fixed seeds. A fixed tick ceiling. Single threaded, with
//! no duty governor and no `nice`, so nothing paces or deprioritises it.
//!
//! AND WHAT IT REPORTS. Not fights per second. The machine independent work
//! counters, and the time per UNIT OF WORK: nanoseconds per simulated display
//! tick and per link activation. A fight that ended early did less work and
//! the counters say so, so those two rates do not move when a policy gets
//! better at winning. The wall figure is the BEST of several repetitions,
//! which is the statistic least corrupted by whatever else the machine is
//! doing; the mean and the spread are printed beside it so a noisy session is
//! visible rather than averaged away.
//!
//! DETERMINISM IS ASSERTED, NOT ASSUMED. Every repetition plays the identical
//! task list with the identical genome, so every work counter must come back
//! bit-identical. A repetition whose counts differ is a determinism bug and
//! the benchmark says so and fails, because a wall time from a run that did
//! different work is not a measurement of anything.

use crate::broad::{Cell, Opponent};
use crate::cpu;
use crate::episode::{self, Rival, Task};
use crate::genome::Genome;
use crate::graph::Network;
use crate::phases::{Phases, Spent, Work};
use crate::trainer::{self, rating_name, ENGINE_VERSION};
use melee_core::counters;
use melee_sim::catalog::{ShipKind, ALL_SHIPS};
use melee_sim::input::CyborgRating;
use serde_json::{json, Value};
use std::path::Path;
use std::sync::Arc;
use std::time::Instant;

/// The genome the benchmark flies, as a file rather than as a recipe.
///
/// Minted once from a fixed seed and a fixed mutation count and then CHECKED
/// IN, which is the whole point: a recipe would silently evaluate a different
/// network the next time anything about mutation changed, and the printed node
/// and link counts would document the drift without preventing it. Compiled
/// into the binary so the benchmark does not depend on a working directory.
const GENOME: &str = include_str!("../benchmark/genome.json");

/// How many times the fixed task list is replayed. Five is enough for the
/// minimum to have shaken off a scheduling hiccup or two without the whole
/// benchmark becoming something nobody runs.
pub const REPETITIONS: usize = 5;

/// The two seeds every pairing is played on, in both seats. Fixed constants,
/// not a stream: a seed drawn from anything is a seed that can move.
pub const SEEDS: [i64; 2] = [104_729, 1_299_709];

/// The ordered pairings, chosen so that every structurally distinct cost in a
/// fight is exercised by at least one of them. Each is played from both seats,
/// so the list covers sixteen ordered matchups.
///
/// Every arena carries a planet (`init::arena` builds one unconditionally), so
/// the gravity pass and the encoder's planet intercept are paid by all of
/// them; there is no "the one with a planet" to choose.
const PAIRINGS: [(ShipKind, ShipKind); 8] = [
    // Auxiliaries on both sides: Chmmr satellites orbit every frame and the
    // Chenjesu photon becomes shards, which is the busiest element queue the
    // roster can produce and therefore the worst case for the quadratic
    // collision pass.
    (ShipKind::Chmmr, ShipKind::Chenjesu),
    // A homing missile plus a point-defense beam against a flame missile. The
    // encoder only walks mounts and runs intercept predictions for
    // missile-armed hulls, and this is the pair that makes it work hardest.
    (ShipKind::Earthling, ShipKind::Ilwrath),
    // Direct fire against the only contact weapon on the roster: a beam that
    // spawns no projectile at all against one that resolves on touch.
    (ShipKind::Arilou, ShipKind::Umgah),
    // The only lightning weapon against a hull whose special destroys both
    // ships, which is the round transition nothing else reaches.
    (ShipKind::Slylandro, ShipKind::Shofixti),
    // Fighters: an auxiliary that is an independent element with its own beam,
    // against a plasma missile.
    (ShipKind::UrQuan, ShipKind::Mycon),
    // The Pkunk resurrection, which is the one case the evaluator can leave in
    // the Selecting phase rather than a victory. An unresolved fight costs the
    // full tick ceiling, so this pairing also pins the long tail.
    (ShipKind::Androsynth, ShipKind::Pkunk),
    // A hull that switches form mid-fight, so its weapon and characteristics
    // change under the same genome, against a retreating rear-firing shot.
    (ShipKind::Mmrnmhrm, ShipKind::Spathi),
    // Recoil against a shield: two specials that alter motion and damage
    // rather than spawning elements.
    (ShipKind::Druuge, ShipKind::Utwig),
];

fn index_of(kind: ShipKind) -> u8 {
    ALL_SHIPS
        .iter()
        .position(|s| *s == kind)
        .expect("every pairing names a hull on the roster") as u8
}

/// The fixed task list: eight pairings, both seats, two seeds. Thirty-two
/// fights, always the same thirty-two, in always the same order.
pub fn tasks(ticks: i64) -> Vec<Task> {
    let mut out = Vec::with_capacity(PAIRINGS.len() * 4);
    for (us, them) in PAIRINGS {
        let cell = Cell {
            foe: Opponent::Cyborg,
            us: index_of(us),
            them: index_of(them),
        };
        for swap in [false, true] {
            for seed in SEEDS {
                out.push(Task {
                    cell,
                    swap,
                    seed,
                    ticks,
                });
            }
        }
    }
    out
}

/// The checked-in genome.
///
/// A fixture this build cannot read is a broken benchmark, not a benchmark
/// with a smaller workload, so it is an error the caller reports rather than
/// something quietly substituted.
pub fn genome() -> Result<Genome, String> {
    let raw: Value = serde_json::from_str(GENOME)
        .map_err(|e| format!("the benchmark genome fixture is not JSON: {e}"))?;
    Genome::from_json(&raw)
        .map_err(|e| format!("the benchmark genome fixture is not a valid genome: {e}"))
}

/// Everything that decides what work the benchmark does. Two runs whose
/// definitions differ measured different things and their numbers may not be
/// compared, which is what [`Definition::fingerprint`] exists to make loud.
#[derive(Clone, Debug)]
pub struct Definition {
    pub genome: String,
    pub nodes: usize,
    pub links: usize,
    pub tasks: Vec<Task>,
    pub ticks: i64,
    pub rating: CyborgRating,
    pub repetitions: usize,
}

impl Definition {
    pub fn build(
        ticks: i64,
        rating: CyborgRating,
        repetitions: usize,
    ) -> Result<Definition, String> {
        let genome = genome()?;
        Ok(Definition {
            genome: genome.fingerprint(),
            nodes: genome.nodes.len(),
            links: genome.enabled_count(),
            tasks: tasks(ticks),
            ticks,
            rating,
            repetitions,
        })
    }

    /// One short string over everything that decides the workload AND the
    /// statistic: the engine version, the genome, every task in order, the
    /// tick ceiling, the cyborg rating and the repetition count.
    ///
    /// The repetition count is in here deliberately. It does not change the
    /// work one repetition does, but a best-of-three and a best-of-twenty are
    /// different statistics over the same distribution, and the headline
    /// figure is a minimum, so quoting one against the other would flatter
    /// whichever ran more repetitions.
    pub fn fingerprint(&self) -> String {
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        let mut absorb = |word: u64| {
            hash ^= word;
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        };
        for byte in ENGINE_VERSION.bytes() {
            absorb(byte as u64);
        }
        for byte in self.genome.bytes() {
            absorb(byte as u64);
        }
        for task in &self.tasks {
            absorb(task.cell.key());
            absorb(task.swap as u64);
            absorb(task.seed as u64);
            absorb(task.ticks as u64);
        }
        absorb(self.ticks as u64);
        for byte in rating_name(self.rating).bytes() {
            absorb(byte as u64);
        }
        absorb(self.repetitions as u64);
        format!("k{hash:016x}")
    }

    pub fn to_json(&self) -> Value {
        json!({
            "fingerprint": self.fingerprint(),
            "engine": ENGINE_VERSION,
            "genome": self.genome,
            "nodes": self.nodes,
            "links": self.links,
            "fights": self.tasks.len(),
            "ticks": self.ticks,
            "rating": rating_name(self.rating),
            "repetitions": self.repetitions
        })
    }
}

/// One replay of the whole task list.
#[derive(Clone, Copy, Debug)]
pub struct Replay {
    /// Wall seconds the replay took. The figure the best-of-N is taken over,
    /// because wall time is what unrelated load corrupts and what a minimum
    /// therefore rescues.
    pub seconds: f64,
    /// CPU seconds it burned. Single threaded, so this tracks the wall figure
    /// closely; it is measured rather than assumed so that the benchmark's
    /// nanoseconds-per-tick is the SAME quantity the trainer's status document
    /// reports, and the two can be compared directly.
    pub cpu: Option<f64>,
    pub work: Work,
    pub phases: Phases,
}

impl Replay {
    fn spent(&self) -> Spent {
        Spent::new(self.seconds, self.cpu)
    }
}

/// Every repetition, plus the definition they all played.
pub struct Report {
    pub definition: Definition,
    pub replays: Vec<Replay>,
}

/// Plays the fixed task list once, on this thread, timing it end to end.
fn replay(definition: &Definition, network: &Arc<Network>) -> Replay {
    let mut work = Work::default();
    let mut phases = Phases::default();
    let began = Instant::now();
    let began_cpu = cpu::seconds();
    for task in &definition.tasks {
        let (outcome, sample) = counters::measure(|| {
            let started = Instant::now();
            let outcome = episode::run(task, network, Rival::Cyborg(definition.rating));
            counters::fight_nanos(started.elapsed().as_nanos() as u64);
            outcome
        });
        phases.absorb(sample);
        work.absorb(sample);
        work.episode(outcome.ticks);
    }
    Replay {
        seconds: began.elapsed().as_secs_f64(),
        cpu: cpu::since(began_cpu),
        work,
        phases,
    }
}

/// Compiles the fixed genome once and replays the fixed list `repetitions`
/// times.
///
/// The compile is deliberately OUTSIDE the timed replays. It happens once per
/// generation in the real loop and once per benchmark here, so folding it into
/// a per-fight rate would make the benchmark a worse predictor of the loop it
/// is standing in for; `melee-mario`'s own status document reports the compile
/// bucket against real generations.
pub fn measure(definition: &Definition) -> Report {
    let genome = genome().expect("the definition was built from the same fixture");
    let network = Arc::new(Network::compile(&genome));
    // The compile's own counters belong to nobody's replay.
    let _ = counters::take();
    let replays = (0..definition.repetitions)
        .map(|_| replay(definition, &network))
        .collect();
    Report {
        definition: definition.clone(),
        replays,
    }
}

impl Report {
    /// The repetition that finished fastest. The least load-sensitive wall
    /// figure available on a machine nobody controls: unrelated load can only
    /// ever make a repetition slower, so the minimum is the one closest to
    /// what the build costs with the machine to itself.
    pub fn best(&self) -> &Replay {
        self.replays
            .iter()
            .min_by(|a, b| a.seconds.total_cmp(&b.seconds))
            .expect("at least one repetition")
    }

    fn seconds(&self) -> Vec<f64> {
        let mut all: Vec<f64> = self.replays.iter().map(|r| r.seconds).collect();
        all.sort_by(f64::total_cmp);
        all
    }

    fn median(&self) -> f64 {
        let all = self.seconds();
        let middle = all.len() / 2;
        if all.len().is_multiple_of(2) {
            (all[middle - 1] + all[middle]) / 2.0
        } else {
            all[middle]
        }
    }

    fn mean(&self) -> f64 {
        let all = self.seconds();
        all.iter().sum::<f64>() / all.len().max(1) as f64
    }

    /// The repetitions whose work counters disagree with the first one's.
    ///
    /// Every repetition plays the same fights with the same genome, so the
    /// counts are a function of the definition alone. A difference is a
    /// determinism bug and never noise, and it invalidates every time in the
    /// report, because those times describe different amounts of work.
    pub fn divergent(&self) -> Vec<usize> {
        let Some(first) = self.replays.first() else {
            return Vec::new();
        };
        self.replays
            .iter()
            .enumerate()
            .filter(|(_, replay)| replay.work != first.work)
            .map(|(at, _)| at)
            .collect()
    }

    /// One NDJSON row, carrying both fingerprints so a row that is not
    /// comparable with another cannot be mistaken for one.
    pub fn to_json(&self, at: &str) -> Value {
        let best = self.best();
        json!({
            "at": at,
            "build": trainer::build_fingerprint(),
            "definition": self.definition.to_json(),
            "best_seconds": best.seconds,
            "best_cpu_seconds": match best.cpu {
                Some(cpu) => json!(cpu),
                None => Value::Null,
            },
            "median_seconds": self.median(),
            "mean_seconds": self.mean(),
            "worst_seconds": self.seconds().last().copied().unwrap_or(0.0),
            "seconds": self.seconds(),
            // Counted over the best repetition, and identical to every other
            // repetition's unless `divergent` is non-empty.
            "work": best.work.to_json(best.spent()),
            "phases": best.phases.to_json(best.spent()),
            "divergent_repetitions": self.divergent()
        })
    }

    /// The operator's report. The definition fingerprint is the first line, so
    /// two outputs that may not be compared cannot be skimmed as if they could.
    pub fn to_text(&self) -> String {
        let definition = &self.definition;
        let best = self.best();
        let work = best.work;
        let counts = work.counts;
        // Per unit of work, over CPU nanoseconds rather than wall ones, so
        // this figure is the same quantity the trainer's status document
        // reports and the two can be read against each other. Single threaded
        // here, so the two clocks nearly agree; the trainer's do not.
        let cpu_nanos = best.cpu.unwrap_or(f64::NAN) * 1e9;
        let per = |total: u64| match total {
            0 => f64::NAN,
            total => cpu_nanos / total as f64,
        };
        let share = |seconds: f64| {
            let accounted = best.phases.accounted();
            match accounted > 0.0 {
                true => seconds / accounted * 100.0,
                false => f64::NAN,
            }
        };
        let mut out = String::new();
        out.push_str(&format!(
            "definition {} | build {} | genome {} ({} nodes, {} links)\n",
            definition.fingerprint(),
            trainer::build_fingerprint(),
            definition.genome,
            definition.nodes,
            definition.links
        ));
        out.push_str(&format!(
            "workload    {} fights, {} ticks each, {} cyborg, single threaded, {} repetitions\n",
            definition.tasks.len(),
            definition.ticks,
            rating_name(definition.rating),
            definition.repetitions
        ));
        out.push_str(&format!(
            "wall        best {:.3}s | median {:.3}s | mean {:.3}s | worst {:.3}s\n",
            best.seconds,
            self.median(),
            self.mean(),
            self.seconds().last().copied().unwrap_or(0.0)
        ));
        out.push_str(&format!(
            "cpu         {:.3}s over the best repetition, which is what the rates divide by\n",
            best.cpu.unwrap_or(f64::NAN)
        ));
        out.push_str(&format!(
            "work        {} episodes, {} display ticks, {} decisions, {} link activations\n",
            work.episodes, work.display_ticks, counts.decisions, counts.link_activations
        ));
        out.push_str(&format!(
            "            {} element scans over {} elements, {} networks compiled\n",
            counts.element_scans, counts.elements_visited, counts.networks_compiled
        ));
        out.push_str(&format!(
            "rates       {:.1} cpu-ns/display tick | {:.2} cpu-ns/link activation | \
             {:.1} ticks/episode\n",
            per(work.display_ticks),
            per(counts.link_activations),
            work.display_ticks as f64 / work.episodes.max(1) as f64
        ));
        out.push_str(&format!(
            "phases      simulate {:.3}s ({:.1}%) | encode {:.3}s ({:.1}%) | think {:.3}s ({:.1}%)\n",
            best.phases.simulate,
            share(best.phases.simulate),
            best.phases.encode,
            share(best.phases.encode),
            best.phases.think,
            share(best.phases.think)
        ));
        // Against CPU seconds, because the buckets are thread totals. Single
        // threaded here so the remainder is small, but the comparison has to
        // be in the same units as the one the trainer makes at nine workers.
        let cpu = best.cpu.unwrap_or(f64::NAN);
        out.push_str(&format!(
            "            accounted {:.3}s of {:.3}s cpu, {:+.3}s unaccounted\n",
            best.phases.accounted(),
            cpu,
            cpu - best.phases.accounted()
        ));
        let divergent = self.divergent();
        if divergent.is_empty() {
            out.push_str(
                "determinism every repetition did bit-identical work, so the times above \
                 describe one workload\n",
            );
        } else {
            out.push_str(&format!(
                "DETERMINISM FAILED repetitions {divergent:?} did different work from \
                 repetition 0. The times above describe different workloads and none of \
                 them may be compared with anything.\n"
            ));
        }
        out
    }
}

/// The benchmark figure the dashboard may quote for THIS build, read back out
/// of an append-only history file.
///
/// Three filters, and each of them exists because quoting the wrong row would
/// be worse than quoting none:
///
///   * only rows whose `build` is the fingerprint of the running executable.
///     A benchmark of a different binary describes a different program, and
///     the operator reading the dashboard is asking what the binary in front
///     of them costs.
///   * of those, only rows sharing the definition fingerprint of the most
///     recent one, because two definitions measured different workloads and
///     [`Definition::fingerprint`] exists precisely to make that loud.
///   * of THOSE, the fastest, for the same reason the benchmark itself takes
///     a best of N: unrelated load can only ever make a repetition slower.
///
/// `None` when nothing has been recorded for this build, which is the ordinary
/// case on a fresh machine and is reported as an absent measurement rather
/// than as a zero.
pub fn reference(path: &Path) -> Option<Value> {
    let text = std::fs::read_to_string(path).ok()?;
    let build = trainer::build_fingerprint();
    let rows: Vec<Value> = text
        .lines()
        .filter_map(|line| serde_json::from_str::<Value>(line).ok())
        .filter(|row| row.get("build").and_then(Value::as_str) == Some(build.as_str()))
        // A row whose repetitions disagreed measured nothing, so it is not a
        // slow result to be beaten by a faster one, it is not a result.
        .filter(|row| {
            row.get("divergent_repetitions")
                .and_then(Value::as_array)
                .is_none_or(|list| list.is_empty())
        })
        .collect();
    let definition = rows
        .last()?
        .pointer("/definition/fingerprint")?
        .as_str()?
        .to_string();
    let best = rows
        .iter()
        .filter(|row| {
            row.pointer("/definition/fingerprint").and_then(Value::as_str)
                == Some(definition.as_str())
        })
        .filter(|row| seconds_of(row).is_some())
        .min_by(|left, right| seconds_of(left).unwrap().total_cmp(&seconds_of(right).unwrap()))?;
    let comparable = rows
        .iter()
        .filter(|row| {
            row.pointer("/definition/fingerprint").and_then(Value::as_str)
                == Some(definition.as_str())
        })
        .count();
    Some(json!({
        "at": best.get("at").cloned().unwrap_or(Value::Null),
        "build": build,
        "definition": definition,
        "repetitions": best.pointer("/definition/repetitions").cloned().unwrap_or(Value::Null),
        "fights": best.pointer("/definition/fights").cloned().unwrap_or(Value::Null),
        "best_seconds": seconds_of(best),
        // The two rates the status document reports for the live run, in the
        // same units, so the reader can put the two side by side and see
        // whether this session is paying more per unit of work than the build
        // costs with the machine to itself.
        "cpu_nanoseconds_per_display_tick":
            best.pointer("/work/cpu_nanoseconds_per_display_tick").cloned().unwrap_or(Value::Null),
        "cpu_nanoseconds_per_link_activation":
            best.pointer("/work/cpu_nanoseconds_per_link_activation").cloned().unwrap_or(Value::Null),
        // How many rows the minimum was taken over, so a best-of-one cannot be
        // read as a settled figure.
        "comparable_rows": comparable
    }))
}

fn seconds_of(row: &Value) -> Option<f64> {
    row.get("best_seconds")?.as_f64().filter(|n| n.is_finite())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One history row, with only the fields `reference` reads.
    fn row(build: &str, definition: &str, seconds: f64, ns: f64, divergent: Vec<usize>) -> String {
        json!({
            "at": "2026-09-12T00:00:00Z",
            "build": build,
            "definition": {"fingerprint": definition, "repetitions": 5, "fights": 32},
            "best_seconds": seconds,
            "work": {"cpu_nanoseconds_per_display_tick": ns,
                     "cpu_nanoseconds_per_link_activation": ns / 100.0},
            "divergent_repetitions": divergent
        })
        .to_string()
    }

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "melee-mario-bench-{name}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("a scratch directory");
        dir
    }

    fn history(name: &str, lines: &[String]) -> std::path::PathBuf {
        let path = scratch(name).join("bench.ndjson");
        std::fs::write(&path, lines.join("\n")).expect("the history file is writable");
        path
    }

    #[test]
    fn no_history_at_all_is_an_absent_reference_rather_than_a_zero() {
        assert_eq!(reference(&scratch("missing").join("bench.ndjson")), None);
    }

    #[test]
    fn only_rows_from_this_build_and_this_definition_are_quotable() {
        let mine = trainer::build_fingerprint();
        // A faster row from a DIFFERENT build, and a faster row from a
        // different definition of the workload. Neither may be quoted as what
        // this binary costs, so the slower row that actually describes it wins.
        let path = history(
            "builds",
            &[
                row("bsomeoneelse0000", "kdefinition00001", 0.010, 100.0, Vec::new()),
                row(&mine, "kolderworkload01", 0.020, 200.0, Vec::new()),
                row(&mine, "kdefinition00001", 0.300, 3000.0, Vec::new()),
                row(&mine, "kdefinition00001", 0.200, 2000.0, Vec::new()),
            ],
        );
        let quoted = reference(&path).expect("one row describes this build");
        assert_eq!(quoted["build"].as_str(), Some(mine.as_str()));
        assert_eq!(quoted["definition"].as_str(), Some("kdefinition00001"));
        // The best of the two comparable rows, not the best of all four.
        assert_eq!(quoted["best_seconds"].as_f64(), Some(0.200));
        assert_eq!(
            quoted["cpu_nanoseconds_per_display_tick"].as_f64(),
            Some(2000.0)
        );
        assert_eq!(quoted["comparable_rows"].as_u64(), Some(2));
    }

    #[test]
    fn a_row_whose_repetitions_disagreed_is_not_a_faster_result() {
        let mine = trainer::build_fingerprint();
        // The divergent row is the fastest and the most recent. It measured
        // two different workloads, so it names neither the definition to
        // compare against nor a time to beat.
        let path = history(
            "divergent",
            &[
                row(&mine, "kdefinition00001", 0.200, 2000.0, Vec::new()),
                row(&mine, "kdefinition00002", 0.010, 100.0, vec![3]),
            ],
        );
        let quoted = reference(&path).expect("the sound row still stands");
        assert_eq!(quoted["definition"].as_str(), Some("kdefinition00001"));
        assert_eq!(quoted["best_seconds"].as_f64(), Some(0.200));
    }

    #[test]
    fn the_checked_in_genome_loads_and_is_the_one_the_benchmark_names() {
        let genome = genome().expect("the fixture is a valid genome");
        // A fixture that changed is a workload that changed, which is the one
        // thing the whole module exists to prevent. This constant is the
        // tripwire: updating it is a deliberate act, and every number ever
        // recorded against the old one stops being comparable.
        assert_eq!(genome.fingerprint(), "gb991c6862c90cc97");
        assert_eq!(genome.nodes.len(), 192);
        assert_eq!(genome.enabled_count(), 231);
    }

    #[test]
    fn the_task_list_is_fixed_spans_the_roster_and_plays_both_seats() {
        let list = tasks(3600);
        assert_eq!(list.len(), PAIRINGS.len() * 2 * SEEDS.len());
        // Same list every time, in the same order.
        assert_eq!(list, tasks(3600));
        // Both seats for every pairing and every seed.
        for (us, them) in PAIRINGS {
            for seed in SEEDS {
                for swap in [false, true] {
                    assert!(list.iter().any(|t| {
                        t.cell.our_ship() == us
                            && t.cell.their_ship() == them
                            && t.seed == seed
                            && t.swap == swap
                    }));
                }
            }
        }
        // Sixteen distinct hulls, which is the roster coverage the old
        // single-cell benchmark had none of.
        let mut hulls: Vec<ShipKind> = list
            .iter()
            .flat_map(|t| [t.cell.our_ship(), t.cell.their_ship()])
            .collect();
        hulls.sort_by_key(|k| k.index());
        hulls.dedup();
        assert_eq!(hulls.len(), 16);
    }

    #[test]
    fn the_fingerprint_moves_when_anything_that_changes_the_workload_moves() {
        let base =
            Definition::build(3600, CyborgRating::AwesomeCyborg, 5).expect("the fixture loads");
        let same =
            Definition::build(3600, CyborgRating::AwesomeCyborg, 5).expect("the fixture loads");
        assert_eq!(base.fingerprint(), same.fingerprint());
        for other in [
            Definition::build(1800, CyborgRating::AwesomeCyborg, 5),
            Definition::build(3600, CyborgRating::GoodCyborg, 5),
            Definition::build(3600, CyborgRating::AwesomeCyborg, 3),
        ] {
            let other = other.expect("the fixture loads");
            assert_ne!(base.fingerprint(), other.fingerprint());
        }
        // A different task list is a different benchmark even at the same
        // size, so the fingerprint has to cover the tasks and not just count
        // them.
        let mut reordered = base.clone();
        reordered.tasks.reverse();
        assert_ne!(base.fingerprint(), reordered.fingerprint());
    }

    /// A short budget, because this proves determinism and roster coverage
    /// rather than throughput; the real benchmark runs the full ceiling.
    #[test]
    fn every_repetition_does_bit_identical_work() {
        let definition =
            Definition::build(240, CyborgRating::AwesomeCyborg, 3).expect("the fixture loads");
        let report = measure(&definition);
        assert_eq!(report.divergent(), Vec::<usize>::new());
        let best = report.best();
        assert_eq!(best.work.episodes, definition.tasks.len() as u64);
        // Real work happened: display ticks, decisions and the links they
        // activated are all non-zero, and the links are exactly the genome's
        // enabled count per decision.
        assert!(best.work.display_ticks > 0);
        assert!(best.work.counts.decisions > 0);
        assert_eq!(
            best.work.counts.link_activations,
            best.work.counts.decisions * definition.links as u64
        );
        assert!(best
            .work
            .counts
            .node_activations
            .is_multiple_of(best.work.counts.decisions));
        // Only one genome is compiled, and it is compiled outside the replays.
        assert_eq!(best.work.counts.networks_compiled, 0);
        assert!(best.work.counts.element_scans > 0);
    }

    #[test]
    fn the_report_names_both_fingerprints_and_the_determinism_verdict() {
        let definition =
            Definition::build(120, CyborgRating::StandardCyborg, 2).expect("the fixture loads");
        let report = measure(&definition);
        let text = report.to_text();
        assert!(text.contains(&definition.fingerprint()));
        assert!(text.contains(&trainer::build_fingerprint()));
        assert!(text.contains("bit-identical"));
        let row = report.to_json("2026-09-12T00:00:00Z");
        assert_eq!(
            row["definition"]["fingerprint"],
            json!(definition.fingerprint())
        );
        assert_eq!(row["build"], json!(trainer::build_fingerprint()));
        assert_eq!(row["seconds"].as_array().map(Vec::len), Some(2));
        assert_eq!(row["divergent_repetitions"], json!([]));
    }
}
