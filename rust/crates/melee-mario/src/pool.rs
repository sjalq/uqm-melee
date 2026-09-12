//! A bounded, reused worker pool for independent fight evaluations.
//!
//! The pool exists to spend more cores, never to change a trajectory. Three
//! rules make that true:
//!
//!   * Every job is a pure function of values copied or `Arc`-shared before it
//!     is queued. No job touches trainer state, a random stream or a shared
//!     arena, so two jobs can never observe each other.
//!   * Results come back in the order the jobs were submitted, whatever order
//!     the threads finished in, and the caller folds them into trainer state on
//!     the main thread in exactly that order. No floating-point reduction ever
//!     happens in a worker.
//!   * One worker means no threads at all: the closure runs inline on the
//!     caller's thread, so the default configuration is the single-threaded
//!     evaluator it replaced rather than a pool of size one.
//!
//! The threads are started once and kept, because a generation submits a batch
//! every few tens of milliseconds and paying a spawn per batch, let alone per
//! fight, would show up against that.

use std::panic::AssertUnwindSafe;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;

type Task = Box<dyn FnOnce() + Send + 'static>;

/// What came back from one job. `Panicked` and `Missing` exist so that a
/// failure is a value the coordinator inspects after every job has finished,
/// rather than a thread death the coordinator would wait on forever.
enum Slot<R> {
    Missing,
    Done(R),
    Panicked,
}

/// How many workers this machine may be asked for: `max(1, cores - 1)`.
///
/// The core that is not counted is CAPACITY left for whatever launched the
/// trainer, not a reservation. Nothing here pins a thread to a core and the
/// scheduler still places all of them wherever it likes; the limit only bounds
/// how much evaluation work is in flight at once. A single-core host gets one
/// worker and no spare, because a trainer that could not run at all would be
/// worse than a busy machine.
pub fn available() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get().saturating_sub(1))
        .unwrap_or(1)
        .max(1)
}

/// Clamps a requested worker count into the safe range for this machine.
pub fn clamp(requested: usize) -> usize {
    requested.clamp(1, available())
}

pub struct Pool {
    sender: Option<Sender<Task>>,
    threads: Vec<JoinHandle<()>>,
}

impl Pool {
    /// A pool of `workers` threads. One worker spawns nothing.
    pub fn new(workers: usize) -> Pool {
        let workers = workers.max(1);
        if workers == 1 {
            return Pool {
                sender: None,
                threads: Vec::new(),
            };
        }
        let (sender, receiver) = channel::<Task>();
        let receiver = Arc::new(Mutex::new(receiver));
        let threads = (0..workers)
            .map(|_| {
                let inbox: Arc<Mutex<Receiver<Task>>> = receiver.clone();
                std::thread::spawn(move || loop {
                    // The lock is held only long enough to take one job, never
                    // while one runs, so the workers do not serialise on it.
                    // Taking it with `lock().unwrap_or_else` rather than `?`
                    // matters: a worker must not die of a poisoned queue, or
                    // the jobs still in it would have nobody to run them.
                    let next = match inbox.lock() {
                        Ok(guard) => guard.recv(),
                        Err(poisoned) => poisoned.into_inner().recv(),
                    };
                    match next {
                        // A panicking job must never take its worker with it:
                        // the remaining jobs of this batch still need running,
                        // and a coordinator waiting on a count that a dead
                        // worker will never reach would wait forever. The
                        // panic is carried back to the coordinator as a value
                        // instead.
                        //
                        // This recovery exists only in an UNWINDING build. The
                        // release profile sets `panic = "abort"`, so in
                        // production a panicking fight kills the process
                        // immediately: nothing is caught, nothing is reported
                        // and no batch finishes. That is the intended
                        // behaviour, and it is safe because a batch is not a
                        // safe point: the run resumes from its last written
                        // checkpoint and replays the batch deterministically,
                        // exactly as it would after a kill or a power cut.
                        // What this arm buys is that the debug and test builds
                        // FAIL rather than hang, which is what makes a bug
                        // findable instead of mysterious.
                        Ok(job) => {
                            let _ = std::panic::catch_unwind(AssertUnwindSafe(job));
                        }
                        // The sender is gone: the pool is shutting down.
                        Err(_) => return,
                    }
                })
            })
            .collect();
        Pool {
            sender: Some(sender),
            threads,
        }
    }

    /// The size of the pool, DERIVED from the threads that exist rather than
    /// remembered from the request, so the number the status document reports
    /// cannot drift away from the number of workers actually running. An empty
    /// thread list is the inline pool, which is one worker: the caller's own
    /// thread.
    pub fn workers(&self) -> usize {
        self.threads.len().max(1)
    }

    /// Runs every job and returns the results in submission order.
    ///
    /// Blocks until all of them are finished, which is what keeps the caller's
    /// state machine serial: a batch is submitted, awaited and folded, and no
    /// work outlives the call.
    pub fn map<J, R, F>(&self, jobs: Vec<J>, work: F) -> Vec<R>
    where
        J: Send + 'static,
        R: Send + 'static,
        F: Fn(J) -> R + Send + Sync + 'static,
    {
        let Some(sender) = self.sender.as_ref() else {
            return jobs.into_iter().map(work).collect();
        };
        if jobs.len() < 2 {
            return jobs.into_iter().map(work).collect();
        }
        let count = jobs.len();
        let slots: Arc<Mutex<Vec<Slot<R>>>> =
            Arc::new(Mutex::new((0..count).map(|_| Slot::Missing).collect()));
        let finished = Arc::new((Mutex::new(0usize), Condvar::new()));
        let work = Arc::new(work);
        for (at, job) in jobs.into_iter().enumerate() {
            let slots = slots.clone();
            let finished = finished.clone();
            let work = work.clone();
            let queued: Task = Box::new(move || {
                // The ticket is counted on drop as well as on success, so no
                // path out of this closure leaves the coordinator waiting on a
                // completion that never arrives.
                let _ticket = Ticket(finished);
                let outcome = std::panic::catch_unwind(AssertUnwindSafe(|| work(job)));
                if let Ok(mut held) = slots.lock() {
                    held[at] = match outcome {
                        Ok(result) => Slot::Done(result),
                        Err(_) => Slot::Panicked,
                    };
                }
            });
            // A closed queue means the workers are gone. The job is already
            // boxed and cannot be handed back, so it is run here instead:
            // slower than a worker, and the only alternative is waiting for
            // one that will never take it.
            if let Err(returned) = sender.send(queued) {
                (returned.0)();
            }
        }
        let (lock, ready) = &*finished;
        let mut done = lock.lock().unwrap_or_else(|held| held.into_inner());
        while *done < count {
            done = match ready.wait(done) {
                Ok(next) => next,
                Err(held) => held.into_inner(),
            };
        }
        drop(done);
        let mut held = slots.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let mut results = Vec::with_capacity(count);
        for slot in std::mem::take(&mut *held) {
            match slot {
                Slot::Done(result) => results.push(result),
                // Reported from the coordinator, in submission order, so which
                // failure surfaces does not depend on which worker lost the
                // race. Every job has already finished by now, so nothing is
                // left running behind this.
                Slot::Panicked => panic!("a pooled job panicked"),
                Slot::Missing => panic!("a pooled job finished without a result"),
            }
        }
        results
    }
}

impl Drop for Pool {
    fn drop(&mut self) {
        self.sender = None;
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

/// Increments the completion counter exactly once, however the job ended.
struct Ticket(Arc<(Mutex<usize>, Condvar)>);

impl Drop for Ticket {
    fn drop(&mut self) {
        let (lock, ready) = &*self.0;
        if let Ok(mut done) = lock.lock() {
            *done += 1;
        }
        ready.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_worker_spawns_no_threads_and_still_maps() {
        let pool = Pool::new(1);
        assert_eq!(pool.workers(), 1);
        assert!(pool.threads.is_empty());
        assert_eq!(pool.map(vec![1, 2, 3], |n| n * 2), vec![2, 4, 6]);
    }

    #[test]
    fn the_reported_count_is_the_live_thread_count_not_the_request() {
        // What the dashboard shows has to be what is running. Zero is not a
        // pool of zero threads with nobody to do the work; it is the inline
        // pool, which is the caller's own thread.
        for requested in [0usize, 1, 2, 3] {
            let pool = Pool::new(requested);
            assert_eq!(pool.workers(), requested.max(1));
            assert_eq!(pool.workers(), pool.threads.len().max(1));
            if requested > 1 {
                assert_eq!(pool.threads.len(), requested);
            } else {
                assert!(pool.threads.is_empty());
            }
        }
    }

    #[test]
    fn results_keep_submission_order_whatever_the_finishing_order() {
        let pool = Pool::new(3);
        // Reversing the cost makes the last job finish first if order were
        // taken from completion rather than from submission.
        let out = pool.map((0..24u64).collect(), |n| {
            let mut spin = 0u64;
            for step in 0..((24 - n) * 20_000) {
                spin = spin.wrapping_add(step);
            }
            (n, spin)
        });
        assert_eq!(
            out.iter().map(|(n, _)| *n).collect::<Vec<_>>(),
            (0..24u64).collect::<Vec<_>>()
        );
    }

    #[test]
    fn the_same_jobs_give_the_same_answers_at_every_worker_count() {
        let job = |n: u64| n.wrapping_mul(0x9e37_79b9_7f4a_7c15) ^ (n << 7);
        let serial = Pool::new(1).map((0..200u64).collect(), job);
        for workers in [2usize, 3] {
            assert_eq!(Pool::new(workers).map((0..200u64).collect(), job), serial);
        }
    }

    #[test]
    fn a_pool_is_reused_across_batches() {
        let pool = Pool::new(2);
        for round in 0..5u64 {
            assert_eq!(
                pool.map((0..8u64).collect(), move |n| n + round),
                (0..8u64).map(|n| n + round).collect::<Vec<_>>()
            );
        }
        assert_eq!(pool.threads.len(), 2);
    }

    /// Runs `body` with the panic hook silenced, so a test that deliberately
    /// panics jobs does not bury the run in backtraces. Restored afterwards.
    fn quietly<R>(body: impl FnOnce() -> R) -> std::thread::Result<R> {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(|_| {}));
        let out = std::panic::catch_unwind(AssertUnwindSafe(body));
        std::panic::set_hook(previous);
        out
    }

    #[test]
    fn every_worker_panicking_fails_the_batch_instead_of_hanging_it() {
        let pool = Pool::new(2);
        // Four times as many jobs as workers, so if a panicking job killed its
        // worker the jobs behind it would have nobody left to run them.
        let out = quietly(|| pool.map((0..8u64).collect(), |_| -> u64 { panic!("job") }));
        assert!(out.is_err());
        // The workers survived their panics, so the pool still works.
        assert_eq!(pool.threads.len(), 2);
        assert_eq!(pool.map((0..8u64).collect(), |n| n + 1), (1..9).collect::<Vec<_>>());
    }

    #[test]
    fn one_panicking_job_still_lets_the_rest_of_the_batch_finish() {
        let pool = Pool::new(2);
        let ran = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let counter = ran.clone();
        let out = quietly(move || {
            pool.map((0..12u64).collect(), move |n| {
                counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                assert!(n != 3, "job three");
                n
            })
        });
        assert!(out.is_err());
        // Every job ran, including the eight queued behind the failing one.
        assert_eq!(ran.load(std::sync::atomic::Ordering::SeqCst), 12);
    }

    #[test]
    fn a_worker_request_is_bounded_by_the_machine() {
        assert_eq!(clamp(0), 1);
        assert_eq!(clamp(1), 1);
        assert_eq!(clamp(usize::MAX), available());
        // Never zero, so even a single-core host gets a working trainer.
        assert!(available() >= 1);
        let cores = std::thread::available_parallelism().map_or(1, |n| n.get());
        assert_eq!(available(), cores.saturating_sub(1).max(1));
    }
}
