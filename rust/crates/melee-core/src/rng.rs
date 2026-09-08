//! `src/Melee/Rng.elm`. Park-Miller minimal standard generator from
//! `libs/math/random.c`. The seed is part of the simulation state and every
//! consumer must draw from it in the same order, so nothing else may be used.

pub const A_CONST: i64 = 16807;
pub const M_CONST: i64 = 2147483647;
pub const Q_CONST: i64 = 127773;
pub const R_CONST: i64 = 2836;

/// Invariant: 1 <= seed <= 2147483646.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Seed(pub i64);

fn coerce(n: i64) -> i64 {
    if n == 0 {
        1
    } else if n > M_CONST {
        n - M_CONST
    } else if n < 0 {
        1
    } else {
        n
    }
}

impl Seed {
    /// `TFB_SeedRandom`: coerce into 1..M, return the previous seed.
    pub fn seed_random(self, new_seed: i64) -> (i64, Seed) {
        (self.0, Seed(coerce(new_seed)))
    }

    /// `TFB_Random`. Returns the new seed value (also stored).
    #[inline]
    pub fn next(self) -> (i64, Seed) {
        let s0 = self.0;
        let s1 = A_CONST * s0.rem_euclid(Q_CONST) - R_CONST * (s0 / Q_CONST);
        let s2 = if s1 > M_CONST {
            s1 - M_CONST
        } else if s1 == 0 {
            1
        } else {
            s1
        };
        (s2, Seed(s2))
    }
}
