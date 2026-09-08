#![cfg_attr(target_arch = "nvptx64", no_std)]

//! Bit-exact Rust mirror of the pure-integer foundation of `src/Melee/`.
//!
//! Every function here is a literal transcription of its Elm counterpart.
//! The Elm simulation runs on JS doubles restricted to integers, so `i64` is
//! the safe carrier: it reproduces `//` (truncation toward zero) and, via
//! `rem_euclid`, `modBy`. Do not "simplify" the arithmetic; the accumulators
//! and rounding rules below are the simulation, not an approximation of it.

pub mod rng;
pub mod trig;
pub mod units;
pub mod velocity;

/// Elm `//` on Int. Truncates toward zero, which is what JS `(a / b) | 0` does.
#[inline(always)]
pub fn idiv(a: i64, b: i64) -> i64 {
    a / b
}

/// Elm `modBy n x`. Elm's result takes the sign of the divisor; the simulation
/// only ever uses positive divisors, where this is `rem_euclid`.
#[inline(always)]
pub fn mod_by(n: i64, x: i64) -> i64 {
    debug_assert!(
        n > 0,
        "modBy with non-positive divisor is not used by the sim"
    );
    x.rem_euclid(n)
}
