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
//! [`Phases::accounted`], which is NOT the same as the session's compute time:
//! the supervisor's own loop, the pool's job dispatch, allocation and anything
//! else nobody put a clock around falls outside all seven. That remainder is
//! reported as `unaccounted`, with its own share, rather than being folded into
//! a bucket or silently rescaling the others. A share here is a share of
//! ACCOUNTED time and says so; the share of the session's compute that is
//! accounted for at all is reported next to it.

use melee_core::counters::{Counts, Sample};
use serde_json::{json, Value};

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

    /// The buckets as seconds, each with its share of ACCOUNTED time, plus
    /// what is left of `compute` that no bucket claims.
    pub fn to_json(&self, compute: f64) -> Value {
        let accounted = self.accounted();
        let unaccounted = (compute - accounted).max(0.0);
        let share = |seconds: f64| number(ratio(seconds, accounted));
        let bucket = |seconds: f64| json!({"seconds": seconds, "share": share(seconds)});
        json!({
            // Named so a reader cannot mistake a share of accounted time for a
            // share of the session, and given both denominators to check it
            // against.
            "basis": "share is of accounted seconds, not of session compute",
            "session_compute_seconds": compute,
            "accounted_seconds": accounted,
            "accounted_share_of_compute": number(ratio(accounted, compute)),
            // The supervisor loop, pool dispatch, allocation and everything
            // else nobody put a clock around. Reported rather than folded into
            // a bucket: a phase split that always summed to exactly 100% would
            // be hiding its own error term.
            "unaccounted_seconds": unaccounted,
            "unaccounted_share_of_compute": number(ratio(unaccounted, compute)),
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

    /// The counts, plus the rates that are comparable across machines and
    /// across load. Every rate is null until it has something underneath it.
    pub fn to_json(&self, compute: f64) -> Value {
        let nanos = compute * 1e9;
        let counts = self.counts;
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
            // The three headline figures. All of them are work per second of
            // COMPUTE rather than of wall clock, so the duty governor's rest
            // is already out of them; unrelated machine load still inflates
            // them, which is why the benchmark takes the best of several runs.
            "nanoseconds_per_display_tick": number(ratio(nanos, self.display_ticks as f64)),
            "nanoseconds_per_link_activation": number(ratio(nanos, counts.link_activations as f64)),
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

    #[test]
    fn the_remainder_of_compute_is_reported_rather_than_hidden() {
        let phases = Phases {
            simulate: 3.0,
            think: 1.0,
            ..Phases::default()
        };
        // Six seconds of compute, four of which any bucket claims.
        let document = phases.to_json(6.0);
        assert_eq!(at(&document, &["accounted_seconds"]), json!(4.0));
        assert_eq!(at(&document, &["unaccounted_seconds"]), json!(2.0));
        // Shares are of accounted time, so simulate is three quarters of four
        // and not a half of six.
        assert_eq!(at(&document, &["simulate", "share"]), json!(0.75));
        assert_eq!(
            at(&document, &["accounted_share_of_compute"]),
            json!(4.0 / 6.0)
        );
    }

    #[test]
    fn nothing_measured_reads_as_null_rather_than_zero() {
        let document = Phases::default().to_json(0.0);
        assert_eq!(at(&document, &["simulate", "share"]), Value::Null);
        assert_eq!(at(&document, &["accounted_share_of_compute"]), Value::Null);
        let work = Work::default().to_json(0.0);
        assert_eq!(at(&work, &["nanoseconds_per_display_tick"]), Value::Null);
        assert_eq!(at(&work, &["display_ticks_per_episode"]), Value::Null);
        assert_eq!(at(&work, &["episodes"]), json!(0));
    }

    #[test]
    fn the_rates_are_per_compute_second_and_per_unit_of_work() {
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
        // Two seconds of compute against 3,600 display ticks and 100,000 link
        // activations.
        let document = work.to_json(2.0);
        assert_eq!(at(&document, &["display_ticks"]), json!(3_600));
        assert_eq!(
            at(&document, &["nanoseconds_per_display_tick"]),
            json!(2e9 / 3_600.0)
        );
        assert_eq!(
            at(&document, &["nanoseconds_per_link_activation"]),
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
