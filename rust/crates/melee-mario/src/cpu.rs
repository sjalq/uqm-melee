//! CPU seconds this process has burned, summed over every thread.
//!
//! WHY A SECOND CLOCK. The work counters and the phase buckets are both
//! THREAD totals: nine workers simulating for one wall second contribute nine
//! seconds of `simulate` and nine workers' worth of display ticks. Dividing
//! either by a WALL second therefore answers a question nobody asked, and
//! answers it differently at every worker count. At six workers the status
//! document reported 552% of compute accounted for, zero seconds unaccounted,
//! and a nanoseconds-per-display-tick figure a fifth of the single-threaded
//! benchmark's, so raising `--workers` read as an optimisation.
//!
//! `getrusage(RUSAGE_SELF)` aggregates every thread in the process, which puts
//! the denominator in the same units as the numerator. The resulting rates are
//! invariant to the worker count, to the duty governor's rest (asleep threads
//! burn no CPU) and to unrelated load on the machine, which is the whole
//! property the trainer was missing.
//!
//! IT IS NOT A WALL CLOCK AND MUST NOT REPLACE ONE. The duty cycle is a share
//! of wall time by definition, and `elapsed` and `compute` stay exactly what
//! they were. This is only ever the denominator of a per-unit-of-work rate.

/// CPU seconds used by this process so far, user plus system, across all
/// threads. Monotonic within a process.
///
/// `None` when the kernel refused to say. A rate with no denominator is
/// reported as null rather than as zero or as a wall-clock figure wearing a
/// CPU label, because a number that is silently the wrong quantity is worse
/// than an absent one.
pub fn seconds() -> Option<f64> {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    // SAFETY: `getrusage` writes a whole `rusage` through the pointer when it
    // returns zero, and the allocation is the right size and alignment for
    // one. Nothing is assumed initialised on any other return.
    let taken = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) };
    if taken != 0 {
        return None;
    }
    let usage = unsafe { usage.assume_init() };
    let seconds = |time: libc::timeval| time.tv_sec as f64 + time.tv_usec as f64 / 1e6;
    Some(seconds(usage.ru_utime) + seconds(usage.ru_stime))
}

/// The CPU seconds between two samples, when both were taken.
///
/// Saturating at zero: the counter is monotonic, so a negative difference
/// means the clock misreported rather than that work was undone, and a
/// negative denominator would produce a negative rate.
pub fn since(before: Option<f64>) -> Option<f64> {
    let before = before?;
    Some((seconds()? - before).max(0.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cpu_time_is_available_and_advances_when_the_process_works() {
        let before = seconds().expect("the kernel reports this process's CPU time");
        // Enough arithmetic that the process cannot have used zero CPU across
        // it, without depending on how long it takes in wall time.
        let mut total = 0u64;
        for step in 0..8_000_000u64 {
            total = total.wrapping_add(step.wrapping_mul(2_654_435_761));
        }
        assert!(total > 0);
        let spent = since(Some(before)).expect("a second sample");
        assert!(spent > 0.0, "CPU time did not advance across real work");
    }

    #[test]
    fn a_difference_is_never_negative() {
        // A "before" sample from the future cannot produce a negative span.
        let ahead = seconds().expect("a sample") + 1_000.0;
        assert_eq!(since(Some(ahead)), Some(0.0));
    }
}
