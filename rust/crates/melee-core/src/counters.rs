//! Machine independent work counters and the two in-fight phase clocks.
//!
//! WHY THIS EXISTS. The only speed figure the trainer used to report was
//! `episodes_per_second` off a wall clock, on a laptop that is also being used
//! for other work, niced down, and paced by a duty-cycle governor. That number
//! moves when the machine gets busy, when the governor rests, and when a policy
//! learns to win faster and therefore simulates less. None of those are
//! optimisations, and all three look like one. A count of work actually done is
//! invariant to every one of them: the same fixed task list does the same
//! number of display ticks, decisions, link activations and element scans on a
//! quiet afternoon and on a loaded one, at one worker and at nine. Divide a
//! count by a time and the ratio is a property of the BUILD.
//!
//! WHY THREAD LOCAL AND NOT ATOMIC. Fights run on pool workers at 24 physics
//! frames per simulated second, and a decision happens on every one of them.
//! An `AtomicU64` shared by nine workers would put every one of those events on
//! one cache line and make the counters themselves the bottleneck they were
//! added to find. Every counter here is a plain `Cell<u64>` in thread-local
//! storage: one non-atomic load, add and store per event, invisible to any
//! other thread, with no synchronisation anywhere in a per-tick path.
//!
//! HOW THE NUMBERS GET OUT. [`measure`] parks whatever the calling thread had
//! pending, zeroes the thread, runs the body, and takes what the body produced.
//! The pool wraps every job in it and the coordinator folds the samples on the
//! main thread in SUBMISSION order, exactly where fight outcomes are already
//! folded. So the totals are identical at one worker and at nine, for the same
//! reason the fitness reduction is, and a panicking job cannot leak its counts
//! into the next fight on that worker.
//!
//! WHAT THE TWO CLOCKS COST. `encode_nanos` and `think_nanos` are the only
//! timers taken inside a fight, and they are taken with three `Instant::now()`
//! reads per evaluated seat per decision rather than one pair each, so the
//! observation build and the network decision are separated without a clock
//! read per physics pass. Everything else the fight spends is derived by
//! subtraction from the fight's own wall time, so the physics loop, the
//! collision pass and the cyborg are timed without a single clock read inside
//! them.

/// Machine independent work. Every field counts EVENTS, never seconds, so two
/// runs of the same task list agree on all of them whatever the machine was
/// doing at the time. A difference in any of these across repetitions or across
/// worker counts is a determinism bug, not noise.
#[derive(Copy, Clone, Default, PartialEq, Eq, Debug)]
pub struct Counts {
    /// Network decisions taken: one per evaluated seat per decision tick.
    pub decisions: u64,
    /// Node visits inside those decisions. Exactly `decisions * node_count`
    /// for a fixed genome, which is what makes "the graph got bigger" and
    /// "the fight ran longer" separable.
    pub node_activations: u64,
    /// Multiply-adds inside those decisions: `decisions * link_count`.
    pub link_activations: u64,
    /// Walks over the whole element map, as opposed to over the frame queue.
    pub element_scans: u64,
    /// Elements those walks visited. Divided by `element_scans` this is the
    /// mean arena occupancy, which is the load parameter every quadratic cost
    /// in the step loop scales with.
    pub elements_visited: u64,
    /// Genomes put through the strongly-connected-component pass. Rising
    /// faster than the population does means a compile cache stopped hitting.
    pub networks_compiled: u64,
}

impl Counts {
    pub fn add(&mut self, other: Counts) {
        self.decisions += other.decisions;
        self.node_activations += other.node_activations;
        self.link_activations += other.link_activations;
        self.element_scans += other.element_scans;
        self.elements_visited += other.elements_visited;
        self.networks_compiled += other.networks_compiled;
    }
}

/// The clocks that can only be read from inside a fight. Nanoseconds.
#[derive(Copy, Clone, Default, PartialEq, Eq, Debug)]
pub struct Nanos {
    /// Wall time inside one fight, start to finish, recorded by whoever ran it.
    pub fight: u64,
    /// Of that, building observation vectors.
    pub encode: u64,
    /// Of that, evaluating the policy.
    pub think: u64,
}

impl Nanos {
    pub fn add(&mut self, other: Nanos) {
        self.fight += other.fight;
        self.encode += other.encode;
        self.think += other.think;
    }

    /// What the fight spent on everything that is not the observation build or
    /// the policy: the physics pump, collisions, gravity, the cyborg in the
    /// other seat and the round transitions.
    ///
    /// Derived by subtraction rather than measured, which is the point: no
    /// clock is read inside the step loop, so the loop being timed is the loop
    /// that runs in production. Saturating, because on a machine whose clock
    /// can step backwards under load the parts must never sum to more than the
    /// whole and produce a negative bucket.
    pub fn simulate(&self) -> u64 {
        self.fight
            .saturating_sub(self.encode)
            .saturating_sub(self.think)
    }
}

/// One thread's contribution, taken at a boundary and folded on the main
/// thread. Work and time travel together because they are folded together.
#[derive(Copy, Clone, Default, PartialEq, Eq, Debug)]
pub struct Sample {
    pub counts: Counts,
    pub nanos: Nanos,
}

impl Sample {
    pub fn add(&mut self, other: Sample) {
        self.counts.add(other.counts);
        self.nanos.add(other.nanos);
    }
}

#[cfg(not(target_arch = "nvptx64"))]
mod live {
    use super::{Counts, Nanos, Sample};
    use core::cell::Cell;

    // One `Cell` per counter rather than one `Cell<Sample>`: bumping a single
    // counter is then a load, an add and a store of one word, instead of a
    // copy of the whole struct out and back for every event.
    thread_local! {
        static DECISIONS: Cell<u64> = const { Cell::new(0) };
        static NODE_ACTIVATIONS: Cell<u64> = const { Cell::new(0) };
        static LINK_ACTIVATIONS: Cell<u64> = const { Cell::new(0) };
        static ELEMENT_SCANS: Cell<u64> = const { Cell::new(0) };
        static ELEMENTS_VISITED: Cell<u64> = const { Cell::new(0) };
        static NETWORKS_COMPILED: Cell<u64> = const { Cell::new(0) };
        static FIGHT_NANOS: Cell<u64> = const { Cell::new(0) };
        static ENCODE_NANOS: Cell<u64> = const { Cell::new(0) };
        static THINK_NANOS: Cell<u64> = const { Cell::new(0) };
    }

    #[inline]
    fn bump(cell: &'static std::thread::LocalKey<Cell<u64>>, by: u64) {
        // A saturating add, not a wrapping one: a counter that wrapped would
        // read as a speedup of exactly the wrong size. At one event per
        // nanosecond `u64` still lasts five centuries, so saturation is a
        // statement that this cannot silently go backwards rather than a case
        // anything expects to reach.
        let _ = cell.try_with(|slot| slot.set(slot.get().saturating_add(by)));
    }

    #[inline]
    fn read(cell: &'static std::thread::LocalKey<Cell<u64>>) -> u64 {
        cell.try_with(Cell::get).unwrap_or(0)
    }

    #[inline]
    fn drain(cell: &'static std::thread::LocalKey<Cell<u64>>) -> u64 {
        cell.try_with(|slot| slot.replace(0)).unwrap_or(0)
    }

    /// One network decision over a graph of `nodes` steps and `links` edges.
    #[inline]
    pub fn decision(nodes: usize, links: usize) {
        bump(&DECISIONS, 1);
        bump(&NODE_ACTIVATIONS, nodes as u64);
        bump(&LINK_ACTIVATIONS, links as u64);
    }

    /// One walk over the whole element map, of `size` elements. Called at the
    /// TOP of the walk, never inside it, so the loop being counted keeps the
    /// codegen and the short-circuit behaviour it has in production.
    #[inline]
    pub fn element_scan(size: usize) {
        bump(&ELEMENT_SCANS, 1);
        bump(&ELEMENTS_VISITED, size as u64);
    }

    /// One genome put through the graph compiler.
    #[inline]
    pub fn network_compiled() {
        bump(&NETWORKS_COMPILED, 1);
    }

    #[inline]
    pub fn fight_nanos(nanos: u64) {
        bump(&FIGHT_NANOS, nanos);
    }

    #[inline]
    pub fn encode_nanos(nanos: u64) {
        bump(&ENCODE_NANOS, nanos);
    }

    #[inline]
    pub fn think_nanos(nanos: u64) {
        bump(&THINK_NANOS, nanos);
    }

    /// This thread's pending sample, without disturbing it.
    pub fn peek() -> Sample {
        Sample {
            counts: Counts {
                decisions: read(&DECISIONS),
                node_activations: read(&NODE_ACTIVATIONS),
                link_activations: read(&LINK_ACTIVATIONS),
                element_scans: read(&ELEMENT_SCANS),
                elements_visited: read(&ELEMENTS_VISITED),
                networks_compiled: read(&NETWORKS_COMPILED),
            },
            nanos: Nanos {
                fight: read(&FIGHT_NANOS),
                encode: read(&ENCODE_NANOS),
                think: read(&THINK_NANOS),
            },
        }
    }

    /// This thread's pending sample, zeroing it.
    pub fn take() -> Sample {
        Sample {
            counts: Counts {
                decisions: drain(&DECISIONS),
                node_activations: drain(&NODE_ACTIVATIONS),
                link_activations: drain(&LINK_ACTIVATIONS),
                element_scans: drain(&ELEMENT_SCANS),
                elements_visited: drain(&ELEMENTS_VISITED),
                networks_compiled: drain(&NETWORKS_COMPILED),
            },
            nanos: Nanos {
                fight: drain(&FIGHT_NANOS),
                encode: drain(&ENCODE_NANOS),
                think: drain(&THINK_NANOS),
            },
        }
    }

    /// Adds a sample back onto this thread. Only [`super::measure`] needs it,
    /// to restore what it parked.
    pub fn restore(sample: Sample) {
        bump(&DECISIONS, sample.counts.decisions);
        bump(&NODE_ACTIVATIONS, sample.counts.node_activations);
        bump(&LINK_ACTIVATIONS, sample.counts.link_activations);
        bump(&ELEMENT_SCANS, sample.counts.element_scans);
        bump(&ELEMENTS_VISITED, sample.counts.elements_visited);
        bump(&NETWORKS_COMPILED, sample.counts.networks_compiled);
        bump(&FIGHT_NANOS, sample.nanos.fight);
        bump(&ENCODE_NANOS, sample.nanos.encode);
        bump(&THINK_NANOS, sample.nanos.think);
    }
}

/// The GPU target has no threads to keep counters for and no `std` to keep
/// them in, so every entry point compiles away to nothing there. The call
/// sites stay identical in both builds rather than being conditional
/// themselves, which is what keeps the simulation one piece of code.
#[cfg(target_arch = "nvptx64")]
mod live {
    use super::Sample;

    #[inline]
    pub fn decision(_nodes: usize, _links: usize) {}
    #[inline]
    pub fn element_scan(_size: usize) {}
    #[inline]
    pub fn network_compiled() {}
    #[inline]
    pub fn fight_nanos(_nanos: u64) {}
    #[inline]
    pub fn encode_nanos(_nanos: u64) {}
    #[inline]
    pub fn think_nanos(_nanos: u64) {}
    #[inline]
    pub fn peek() -> Sample {
        Sample::default()
    }
    #[inline]
    pub fn take() -> Sample {
        Sample::default()
    }
    #[inline]
    pub fn restore(_sample: Sample) {}
}

pub use live::{
    decision, element_scan, encode_nanos, fight_nanos, network_compiled, peek, restore, take,
    think_nanos,
};

/// Runs `body` and returns what IT alone counted.
///
/// Nesting-safe and identical on a worker thread and on the caller's own: the
/// caller's pending counts are parked, the thread is zeroed, the body runs, its
/// sample is taken and the parked counts are put back. That is what lets the
/// pool use one code path for its inline single-worker case, where the caller
/// may well have counts of its own in flight, and for a worker thread, where it
/// never does.
pub fn measure<R>(body: impl FnOnce() -> R) -> (R, Sample) {
    let parked = take();
    let out = body();
    let mine = take();
    restore(parked);
    (out, mine)
}

#[cfg(all(test, not(target_arch = "nvptx64")))]
mod tests {
    use super::*;

    #[test]
    fn measure_returns_only_what_the_body_counted() {
        let _ = take();
        decision(10, 40);
        let (out, inner) = measure(|| {
            decision(3, 7);
            element_scan(12);
            99
        });
        assert_eq!(out, 99);
        assert_eq!(inner.counts.decisions, 1);
        assert_eq!(inner.counts.node_activations, 3);
        assert_eq!(inner.counts.link_activations, 7);
        assert_eq!(inner.counts.element_scans, 1);
        assert_eq!(inner.counts.elements_visited, 12);
        // What was pending before the body is still pending after it.
        let outer = take();
        assert_eq!(outer.counts.decisions, 1);
        assert_eq!(outer.counts.link_activations, 40);
    }

    #[test]
    fn nesting_a_measure_does_not_lose_the_outer_counts() {
        let _ = take();
        let ((), outer) = measure(|| {
            decision(1, 2);
            let ((), inner) = measure(|| decision(5, 6));
            assert_eq!(inner.counts.node_activations, 5);
            decision(1, 2);
        });
        // The inner body's counts belong to the inner sample only.
        assert_eq!(outer.counts.decisions, 2);
        assert_eq!(outer.counts.node_activations, 2);
        assert_eq!(outer.counts.link_activations, 4);
        let _ = take();
    }

    #[test]
    fn counters_are_per_thread_and_never_shared() {
        let _ = take();
        decision(100, 100);
        let seen = std::thread::spawn(|| {
            let before = peek();
            decision(1, 1);
            (before, take())
        })
        .join()
        .expect("the probe thread finished");
        // A fresh thread starts at zero and takes only its own work.
        assert_eq!(seen.0, Sample::default());
        assert_eq!(seen.1.counts.decisions, 1);
        // And this thread's counts were untouched by it.
        assert_eq!(take().counts.node_activations, 100);
    }

    #[test]
    fn simulate_is_the_fight_less_the_two_measured_phases() {
        let nanos = Nanos {
            fight: 1_000,
            encode: 300,
            think: 200,
        };
        assert_eq!(nanos.simulate(), 500);
        // Parts that somehow exceed the whole floor at zero rather than
        // wrapping into an enormous bucket.
        let impossible = Nanos {
            fight: 100,
            encode: 300,
            think: 200,
        };
        assert_eq!(impossible.simulate(), 0);
    }
}
