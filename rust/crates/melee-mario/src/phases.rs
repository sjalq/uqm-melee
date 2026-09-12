//! Where the accounted seconds went, and the machine independent work they
//! bought.
//!
//! `compute` used to be one undifferentiated bucket: simulating, compiling,
//! evolving, checkpointing and rendering the status document all landed in the
//! same number, so "the loop got slower" could not be told from "the loop
//! started doing something else". These two structures split it.
//!
//! WHY THESE ARE SESSION FIGURES, NOT RUN FIGURES. They are deliberately NOT
//! checkpointed, for the same reason `nice` and the worker count are not: they
//! describe what THIS process did on THIS machine under THIS load. A run
//! resumed on a quiet afternoon after a week on a busy one would otherwise
//! average two different machines into one nanoseconds-per-tick figure and
//! present it as a property of the build, which is exactly the confusion the
//! whole module exists to remove. `episodes`, `elapsed` and `compute` stay the
//! all-time run totals they always were; everything here is labelled as this
//! session's and starts at zero on every resume.
//!
//! HONESTY RULE. The buckets are measured independently and their sum is
//! [`Phases::accounted`], which is NOT the same as the time the session spent:
//! the supervisor's own loop, the pool's job dispatch, allocation and anything
//! else nobody put a clock around falls outside all seven. That remainder is
//! reported as `unaccounted`, with its own share, rather than being folded into
//! a bucket or silently rescaling the others. A share here is a share of
//! ACCOUNTED time and says so; the share of the session that is accounted for
//! at all is reported next to it.
//!
//! WHY THE DENOMINATOR IS CPU SECONDS. Every bucket here and every count in
//! [`Work`] is a THREAD total: nine workers simulating for one wall second
//! contribute nine seconds of `simulate`. Dividing those by a WALL second
//! compares nine threads' output against one thread's worth of time, and does
//! it differently at every worker count. Measured at six workers, that is not
//! a rounding error: the document claimed 552% of compute accounted for, zero
//! seconds unaccounted, and a nanoseconds-per-display-tick figure a fifth of
//! the single-threaded benchmark's, so raising `--workers` read as a speedup.
//! [`Spent::cpu`] comes from `getrusage(RUSAGE_SELF)`, which sums every
//! thread, so numerator and denominator are in the same units and every rate
//! below is invariant to the worker count. See [`crate::cpu`].

use melee_core::counters::{Counts, Sample};
use serde_json::{json, Value};

/// What one session spent, on the two clocks that measure it differently.
///
/// Carried as a pair rather than as a bare `f64` so that a caller cannot hand
/// a per-thread total a wall-clock denominator by accident, which is exactly
/// the mistake this type was introduced to make unrepresentable.
#[derive(Copy, Clone, Default, PartialEq, Debug)]
pub struct Spent {
    /// Wall seconds the supervisor spent working, governor rest excluded.
    /// What the duty cycle is a share of, and never a denominator for work.
    pub wall: f64,
    /// CPU seconds across every thread over that same span. `None` when the
    /// kernel would not say, which makes the rates null rather than wrong.
    pub cpu: Option<f64>,
}

impl Spent {
    /// A span measured on both clocks at once.
    pub fn new(wall: f64, cpu: Option<f64>) -> Spent {
        Spent { wall, cpu }
    }

    /// Whether anything was measured at all. A session that has not computed
    /// reports null documents rather than a page of zeroes, because zero
    /// claims a measurement of no work rather than no measurement.
    pub fn measured(&self) -> bool {
        self.wall > 0.0 || self.cpu.is_some_and(|cpu| cpu > 0.0)
    }
}

/// A measurement that has not been made, or a rate with nothing underneath it,
/// is null rather than zero. Zero means "measured, and it was zero".
fn number(value: Option<f64>) -> Value {
    match value {
        Some(n) if n.is_finite() => json!(n),
        _ => Value::Null,
    }
}

fn ratio(numerator: f64, denominator: f64) -> Option<f64> {
    (denominator > 0.0).then(|| numerator / denominator)
}

/// Seconds spent in each named phase, this process only.
#[derive(Copy, Clone, Default, PartialEq, Debug)]
pub struct Phases {
    /// Physics: the pump, collisions, gravity, the cyborg in the other seat
    /// and the round transitions. Derived per fight as the fight's own wall
    /// time less the two phases below, so nothing clocks the step loop.
    pub simulate: f64,
    /// Evaluating the policy network, including its input assembly.
    pub think: f64,
    /// Building the observation vectors the policy reads.
    pub encode: f64,
    /// The graph compiler: the strongly-connected-component pass and the edge
    /// layout it produces.
    pub compile: f64,
    /// Selection, speciation, mutation and panel drawing.
    pub evolve: f64,
    /// Serialising and writing the checkpoint.
    pub checkpoint: f64,
    /// Rendering and publishing the status and network documents.
    pub serve: f64,
}

impl Phases {
    /// The seconds the seven buckets between them account for.
    pub fn accounted(&self) -> f64 {
        self.simulate
            + self.think
            + self.encode
            + self.compile
            + self.evolve
            + self.checkpoint
            + self.serve
    }

    /// Folds the in-fight clocks a pool batch brought back. `simulate` is the
    /// remainder of the fights' own wall time, which is why it needs no clock
    /// of its own inside the step loop.
    pub fn absorb(&mut self, sample: Sample) {
        let nanos = sample.nanos;
        self.simulate += nanos.simulate() as f64 / 1e9;
        self.encode += nanos.encode as f64 / 1e9;
        self.think += nanos.think as f64 / 1e9;
    }

    /// The buckets as seconds, each with its share of ACCOUNTED time, plus the
    /// CPU seconds no bucket claims.
    pub fn to_json(&self, spent: Spent) -> Value {
        let accounted = self.accounted();
        // Against CPU seconds, because every bucket is a thread total, and
        // SIGNED, because clamping it at zero is how the old wall-clock
        // version managed to claim 552% accounted and nothing unaccounted in
        // the same breath. Both signs mean something an operator wants:
        //
        //   positive  CPU nobody put a clock around. The supervisor loop, the
        //             pool's dispatch, allocation, the server thread.
        //   negative  the in-fight clocks are per-thread WALL clocks, so a
        //             worker preempted mid-fight keeps accruing fight time
        //             while it is off-core and the buckets come to slightly
        //             more than the CPU actually burned. Its size against
        //             `accounted` is a contention signal: on an idle machine
        //             it is a fraction of a percent, and it grows with
        //             whatever else the laptop is doing.
        //
        // The clocks stay wall clocks deliberately. A per-thread CPU clock is
        // a syscall on macOS and these are read three times per decision, so
        // buying that last fraction of a percent would mean perturbing the
        // inner loop the whole module exists to measure.
        let unaccounted = spent.cpu.map(|cpu| cpu - accounted);
        let share = |seconds: f64| number(ratio(seconds, accounted));
        let bucket = |seconds: f64| json!({"seconds": seconds, "share": share(seconds)});
        json!({
            // Named so a reader cannot mistake a share of accounted time for a
            // share of the session, and given both denominators to check it
            // against.
            "basis": "bucket seconds are per-thread wall totals; share is of \
                      accounted seconds, not of wall time. unaccounted_seconds \
                      is signed: positive is CPU nobody clocked, negative is \
                      worker threads preempted mid-fight",
            "session_cpu_seconds": number(spent.cpu),
            // Reported beside it because the duty cycle is a share of WALL
            // time and nothing here replaces that. Their ratio is roughly how
            // many cores the pool actually kept busy.
            "session_wall_seconds": spent.wall,
            "threads_busy": number(spent.cpu.and_then(|cpu| ratio(cpu, spent.wall))),
            "accounted_seconds": accounted,
            "accounted_share_of_cpu": number(spent.cpu.and_then(|cpu| ratio(accounted, cpu))),
            // The supervisor loop, pool dispatch, allocation, the server
            // thread and everything else nobody put a clock around. Reported
            // rather than folded into a bucket: a phase split that always
            // summed to exactly 100% would be hiding its own error term.
            "unaccounted_seconds": number(unaccounted),
            "unaccounted_share_of_cpu": number(
                unaccounted.zip(spent.cpu).and_then(|(left, cpu)| ratio(left, cpu))
            ),
            "simulate": bucket(self.simulate),
            "think": bucket(self.think),
            "encode": bucket(self.encode),
            "compile": bucket(self.compile),
            "evolve": bucket(self.evolve),
            "checkpoint": bucket(self.checkpoint),
            "serve": bucket(self.serve)
        })
    }
}

/// Machine independent work this process has done, and nothing else. Every
/// field is a count of events; not one of them moves when the machine gets
/// busy, when the governor rests or when a fight happens to end early.
#[derive(Copy, Clone, Default, PartialEq, Eq, Debug)]
pub struct Work {
    /// Fights folded into run state this session.
    pub episodes: u64,
    /// Display ticks those fights simulated. The denominator that makes two
    /// builds comparable when one of them wins faster and therefore simulates
    /// less: fights per second would call that a speedup, and this does not.
    pub display_ticks: u64,
    pub counts: Counts,
}

impl Work {
    pub fn absorb(&mut self, sample: Sample) {
        self.counts.add(sample.counts);
    }

    /// One finished fight, folded where every other per-episode number is.
    pub fn episode(&mut self, display_ticks: i64) {
        self.episodes += 1;
        self.display_ticks += display_ticks.max(0) as u64;
    }

    /// The counts, plus the rates that are comparable across machines, across
    /// load and across worker counts. Every rate is null until it has
    /// something underneath it.
    pub fn to_json(&self, spent: Spent) -> Value {
        let nanos = spent.cpu.map(|cpu| cpu * 1e9);
        let counts = self.counts;
        // A rate over CPU nanoseconds, or null when the CPU clock was
        // unreadable. Never silently over wall nanoseconds: that is the same
        // number in the same unit meaning something else entirely.
        let per = |total: u64| number(nanos.and_then(|nanos| ratio(nanos, total as f64)));
        json!({
            "basis": "this process, not the whole run: counters start at zero on every resume",
            "episodes": self.episodes,
            "display_ticks": self.display_ticks,
            "decisions": counts.decisions,
            "node_activations": counts.node_activations,
            "link_activations": counts.link_activations,
            "element_scans": counts.element_scans,
            "elements_visited": counts.elements_visited,
            "networks_compiled": counts.networks_compiled,
            // The three headline figures, and the reason this module exists.
            // The first two are CPU nanoseconds per unit of work: the duty
            // governor's rest is out of them because a sleeping thread burns
            // no CPU, and the worker count is out of them because the
            // denominator sums threads exactly as the numerator does. What is
            // left moves only when the BUILD changes, or when unrelated load
            // steals cache and memory bandwidth, which is why the benchmark
            // still takes the best of several repetitions.
            "cpu_nanoseconds_per_display_tick": per(self.display_ticks),
            "cpu_nanoseconds_per_link_activation": per(counts.link_activations),
            "display_ticks_per_episode": number(
                ratio(self.display_ticks as f64, self.episodes as f64)
            ),
            // Two shape figures, so a changed rate can be attributed. The
            // first says whether the graph grew, the second says how crowded
            // the arenas were, which is what every full-map walk costs.
            "link_activations_per_decision": number(
                ratio(counts.link_activations as f64, counts.decisions as f64)
            ),
            "elements_per_scan": number(
                ratio(counts.elements_visited as f64, counts.element_scans as f64)
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use melee_core::counters::Nanos;

    fn at(value: &Value, path: &[&str]) -> Value {
        let mut here = value.clone();
        for step in path {
            here = here.get(step).cloned().unwrap_or(Value::Null);
        }
        here
    }

    #[test]
    fn a_fight_sample_splits_into_three_buckets_that_sum_to_it() {
        let mut phases = Phases::default();
        phases.absorb(Sample {
            counts: Counts::default(),
            nanos: Nanos {
                fight: 1_000_000_000,
                encode: 300_000_000,
                think: 200_000_000,
            },
        });
        assert!((phases.encode - 0.3).abs() < 1e-9);
        assert!((phases.think - 0.2).abs() < 1e-9);
        assert!((phases.simulate - 0.5).abs() < 1e-9);
        assert!((phases.accounted() - 1.0).abs() < 1e-9);
    }

    /// Four CPU seconds of clocked work inside six CPU seconds spent.
    fn six_cpu_seconds() -> Spent {
        Spent::new(1.0, Some(6.0))
    }

    #[test]
    fn the_remainder_of_cpu_is_reported_rather_than_hidden() {
        let phases = Phases {
            simulate: 3.0,
            think: 1.0,
            ..Phases::default()
        };
        let document = phases.to_json(six_cpu_seconds());
        assert_eq!(at(&document, &["accounted_seconds"]), json!(4.0));
        assert_eq!(at(&document, &["unaccounted_seconds"]), json!(2.0));
        // Shares are of accounted time, so simulate is three quarters of four
        // and not a half of six.
        assert_eq!(at(&document, &["simulate", "share"]), json!(0.75));
        assert_eq!(
            at(&document, &["accounted_share_of_cpu"]),
            json!(4.0 / 6.0)
        );
    }

    /// The regression this whole denominator exists for.
    ///
    /// The buckets and the counters are thread totals, so six workers produce
    /// six times the seconds and six times the work in one sixth of the wall
    /// time. Divided by WALL seconds the document claimed 552% of compute
    /// accounted for, zero unaccounted, and a per-tick cost a fifth of the
    /// single-threaded truth, so raising `--workers` read as an optimisation.
    /// Divided by CPU seconds, every figure below is identical at one worker
    /// and at six.
    #[test]
    fn the_shares_and_rates_do_not_move_with_the_worker_count() {
        let phases = Phases {
            simulate: 9.0,
            think: 2.0,
            encode: 1.0,
            ..Phases::default()
        };
        let mut work = Work::default();
        for _ in 0..12 {
            work.episode(900);
        }
        work.absorb(Sample {
            counts: Counts {
                link_activations: 120_000,
                decisions: 1_200,
                ..Counts::default()
            },
            nanos: Nanos::default(),
        });
        // Twelve CPU seconds either way: one worker for twelve wall seconds,
        // or six workers for two.
        let alone = Spent::new(12.0, Some(12.0));
        let pooled = Spent::new(2.0, Some(12.0));
        for key in [
            "accounted_seconds",
            "accounted_share_of_cpu",
            "unaccounted_seconds",
            "unaccounted_share_of_cpu",
        ] {
            assert_eq!(
                at(&phases.to_json(alone), &[key]),
                at(&phases.to_json(pooled), &[key]),
                "{key} moved with the worker count"
            );
        }
        for key in [
            "cpu_nanoseconds_per_display_tick",
            "cpu_nanoseconds_per_link_activation",
        ] {
            assert_eq!(
                at(&work.to_json(alone), &[key]),
                at(&work.to_json(pooled), &[key]),
                "{key} moved with the worker count"
            );
        }
        // And the share is a share: twelve seconds of buckets inside twelve
        // CPU seconds is all of it, never more.
        assert_eq!(
            at(&phases.to_json(pooled), &["accounted_share_of_cpu"]),
            json!(1.0)
        );
        assert_eq!(at(&phases.to_json(pooled), &["unaccounted_seconds"]), json!(0.0));
        // The wall figure is still reported, and still differs: it is what the
        // duty cycle is a share of, and it says how many threads were busy.
        assert_eq!(at(&phases.to_json(pooled), &["threads_busy"]), json!(6.0));
        assert_eq!(at(&phases.to_json(alone), &["threads_busy"]), json!(1.0));
    }

    /// Buckets that come to more than the CPU burned are reported as such
    /// rather than clamped to a tidy zero.
    ///
    /// The in-fight clocks are per-thread wall clocks, so a worker preempted
    /// mid-fight accrues bucket time it did not spend on a core. Clamping is
    /// exactly how the wall-clock version managed to report 552% accounted and
    /// nothing unaccounted at once, so the sign is kept and the magnitude is a
    /// contention signal.
    #[test]
    fn buckets_exceeding_the_cpu_burned_show_as_a_negative_remainder() {
        let phases = Phases {
            simulate: 6.5,
            ..Phases::default()
        };
        // Six CPU seconds, against six and a half seconds of bucket.
        let document = phases.to_json(Spent::new(1.0, Some(6.0)));
        assert_eq!(at(&document, &["unaccounted_seconds"]), json!(-0.5));
        assert_eq!(
            at(&document, &["unaccounted_share_of_cpu"]),
            json!(-0.5 / 6.0)
        );
        // And the overshoot is visible in the share too, rather than hidden by
        // rescaling the buckets to fit.
        assert_eq!(
            at(&document, &["accounted_share_of_cpu"]),
            json!(6.5 / 6.0)
        );
    }

    #[test]
    fn nothing_measured_reads_as_null_rather_than_zero() {
        let nothing = Spent::default();
        assert!(!nothing.measured());
        let document = Phases::default().to_json(nothing);
        assert_eq!(at(&document, &["simulate", "share"]), Value::Null);
        assert_eq!(at(&document, &["accounted_share_of_cpu"]), Value::Null);
        let work = Work::default().to_json(nothing);
        assert_eq!(at(&work, &["cpu_nanoseconds_per_display_tick"]), Value::Null);
        assert_eq!(at(&work, &["display_ticks_per_episode"]), Value::Null);
        assert_eq!(at(&work, &["episodes"]), json!(0));
    }

    /// A wall clock that ran while the CPU clock could not be read is not a
    /// substitute for it: the rate would be the same number in the same unit
    /// meaning something else, so it is null instead.
    #[test]
    fn a_missing_cpu_clock_nulls_the_rates_rather_than_falling_back_to_wall() {
        let mut work = Work::default();
        work.episode(900);
        let blind = Spent::new(5.0, None);
        assert!(blind.measured());
        let document = work.to_json(blind);
        assert_eq!(
            at(&document, &["cpu_nanoseconds_per_display_tick"]),
            Value::Null
        );
        // The counts themselves are still facts and are still reported.
        assert_eq!(at(&document, &["display_ticks"]), json!(900));
        let phases = Phases {
            simulate: 1.0,
            ..Phases::default()
        }
        .to_json(blind);
        assert_eq!(at(&phases, &["unaccounted_seconds"]), Value::Null);
        assert_eq!(at(&phases, &["accounted_seconds"]), json!(1.0));
    }

    #[test]
    fn the_rates_are_per_cpu_second_and_per_unit_of_work() {
        let mut work = Work::default();
        for _ in 0..4 {
            work.episode(900);
        }
        work.absorb(Sample {
            counts: Counts {
                decisions: 1_000,
                node_activations: 20_000,
                link_activations: 100_000,
                element_scans: 500,
                elements_visited: 4_000,
                networks_compiled: 1,
            },
            nanos: Nanos::default(),
        });
        // Two CPU seconds against 3,600 display ticks and 100,000 link
        // activations.
        let document = work.to_json(Spent::new(2.0, Some(2.0)));
        assert_eq!(at(&document, &["display_ticks"]), json!(3_600));
        assert_eq!(
            at(&document, &["cpu_nanoseconds_per_display_tick"]),
            json!(2e9 / 3_600.0)
        );
        assert_eq!(
            at(&document, &["cpu_nanoseconds_per_link_activation"]),
            json!(2e9 / 100_000.0)
        );
        assert_eq!(at(&document, &["display_ticks_per_episode"]), json!(900.0));
        assert_eq!(
            at(&document, &["link_activations_per_decision"]),
            json!(100.0)
        );
        assert_eq!(at(&document, &["elements_per_scan"]), json!(8.0));
    }
}
