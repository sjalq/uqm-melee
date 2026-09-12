//! Deterministic random number streams.
//!
//! The trainer keeps evolution, training sampling, readiness validation and
//! auditing on separate streams so that scheduling, pausing or resuming can
//! never shift one stream's draws into another. Every stream's exact state is
//! four words wide and goes into the checkpoint verbatim.
//!
//! Episode seeds are not drawn from a stream at all: they are HASHED from
//! (stream tag, run salt, cell, seat, index) into a NUMERIC PARTITION of the
//! legal Park-Miller seed space that belongs to that tag alone.
//!
//! The partition is what makes withholding real. The legal seeds are
//! `1 ..= 2147483646`; writing a seed as `value + 1`, each tag owns one residue
//! class of `value` modulo the number of tags. Two seeds from different tags
//! therefore differ in `(seed - 1) % ALL_STREAMS.len()` and CANNOT be equal,
//! whatever the hash does. Hashing
//! merely chooses which member of the tag's own class to use, so the training
//! sampler cannot reach an audit seed even by accident, and a resumed run
//! reproduces the identical seed for the identical slot.

use serde_json::{json, Value};

/// The legal Park-Miller seed values are `1 ..= MAX_SEED`.
pub const MAX_SEED: u64 = 2_147_483_646;

/// Which withheld pool an episode seed comes from. This is an enum rather than
/// a number so that an unrecognised stream cannot be invented at a call site.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub enum StreamTag {
    /// Fights the population is trained on.
    Train,
    /// The cheap probe that decides whether an audit is worth opening.
    Ready,
    /// The gate's first fixed panel.
    Audit,
    /// The disjoint panel that must also pass before the gate is cleared.
    Confirm,
}

pub const ALL_STREAMS: [StreamTag; 4] = [
    StreamTag::Train,
    StreamTag::Ready,
    StreamTag::Audit,
    StreamTag::Confirm,
];

impl StreamTag {
    /// The residue class of `seed - 1` this tag owns, modulo [`ALL_STREAMS`].
    #[inline]
    pub const fn residue(self) -> u64 {
        match self {
            StreamTag::Train => 0,
            StreamTag::Ready => 1,
            StreamTag::Audit => 2,
            StreamTag::Confirm => 3,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            StreamTag::Train => "train",
            StreamTag::Ready => "ready",
            StreamTag::Audit => "audit",
            StreamTag::Confirm => "confirm",
        }
    }
}

#[inline]
fn split_mix(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9e37_79b9_7f4a_7c15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

/// xoshiro256\*\*. Chosen because its state is small, exactly reproducible and
/// trivial to serialise; it is never used for anything the simulation sees.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Stream {
    state: [u64; 4],
}

impl Stream {
    pub fn seeded(seed: u64) -> Stream {
        let mut mix = seed;
        let mut state = [0u64; 4];
        for slot in state.iter_mut() {
            *slot = split_mix(&mut mix);
        }
        if state == [0; 4] {
            state[0] = 1;
        }
        Stream { state }
    }

    #[inline]
    pub fn next_u64(&mut self) -> u64 {
        let s = &mut self.state;
        let result = s[1].wrapping_mul(5).rotate_left(7).wrapping_mul(9);
        let t = s[1] << 17;
        s[2] ^= s[0];
        s[3] ^= s[1];
        s[1] ^= s[2];
        s[0] ^= s[3];
        s[2] ^= t;
        s[3] = s[3].rotate_left(45);
        result
    }

    /// Uniform in [0, 1).
    #[inline]
    pub fn unit(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
    }

    /// Uniform in [-1, 1).
    #[inline]
    pub fn signed(&mut self) -> f64 {
        self.unit() * 2.0 - 1.0
    }

    /// Uniform in `0..bound`, rejection sampled so the distribution is exact.
    pub fn below(&mut self, bound: usize) -> usize {
        assert!(bound > 0, "below(0) has no result");
        let bound = bound as u64;
        let limit = u64::MAX - (u64::MAX % bound);
        loop {
            let draw = self.next_u64();
            if draw < limit {
                return (draw % bound) as usize;
            }
        }
    }

    #[inline]
    pub fn chance(&mut self, probability: f64) -> bool {
        self.unit() < probability
    }

    pub fn to_json(self) -> Value {
        json!(self.state.map(|w| w.to_string()))
    }

    pub fn from_json(value: &Value) -> Option<Stream> {
        let list = value.as_array()?;
        if list.len() != 4 {
            return None;
        }
        let mut state = [0u64; 4];
        for (slot, raw) in state.iter_mut().zip(list) {
            *slot = raw.as_str()?.parse().ok()?;
        }
        if state == [0; 4] {
            return None;
        }
        Some(Stream { state })
    }
}

/// Park-Miller seed for one simulated episode, drawn from the partition that
/// belongs to `stream`. Pure in its arguments, so the same slot always yields
/// the same battle, and provably disjoint across streams.
///
/// The hash is folded into the tag's residue class rather than into the whole
/// range. Reducing a 64-bit hash modulo roughly 5.4e8 members leaves a
/// selection bias on the order of 1e-10, which is irrelevant for choosing which
/// battle to fight and does not affect the disjointness argument at all.
pub fn episode_seed(stream: StreamTag, salt: u64, cell: u64, seat: u64, index: u64) -> i64 {
    let streams = ALL_STREAMS.len() as u64;
    let residue = stream.residue();
    let mut mix = 0x243f_6a88_85a3_08d3;
    for word in [residue + 1, salt, cell, seat, index] {
        mix ^= word.wrapping_mul(0x9e37_79b9_7f4a_7c15);
        mix = split_mix(&mut mix);
    }
    // Members of this class are residue, residue + streams, residue + 2 *
    // streams, ... below MAX_SEED, counted exactly so the result can never
    // leave the legal range.
    let members = (MAX_SEED - residue).div_ceil(streams);
    let value = residue + streams * (mix % members);
    debug_assert!(value < MAX_SEED);
    value as i64 + 1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn streams_are_reproducible_and_survive_serialisation() {
        let mut a = Stream::seeded(12345);
        let saved = a.to_json();
        let draws: Vec<u64> = (0..8).map(|_| a.next_u64()).collect();
        let mut restored = Stream::from_json(&saved).expect("round trip");
        assert_eq!(draws, (0..8).map(|_| restored.next_u64()).collect::<Vec<_>>());
        assert_eq!(restored, a);
        assert!(Stream::from_json(&json!(["0", "0", "0", "0"])).is_none());
        assert!(Stream::from_json(&json!(["1", "2"])).is_none());
    }

    #[test]
    fn draws_stay_inside_their_declared_ranges() {
        let mut s = Stream::seeded(7);
        for _ in 0..10_000 {
            let u = s.unit();
            assert!((0.0..1.0).contains(&u));
            let g = s.signed();
            assert!((-1.0..1.0).contains(&g));
            assert!(s.below(13) < 13);
        }
    }

    #[test]
    fn episode_seeds_are_legal_pure_and_land_only_in_their_own_partition() {
        let seed = |stream, index| episode_seed(stream, 99, 4, 1, index);
        assert_eq!(seed(StreamTag::Train, 3), seed(StreamTag::Train, 3));
        assert_ne!(seed(StreamTag::Train, 3), seed(StreamTag::Audit, 3));

        let streams = ALL_STREAMS.len() as i64;
        for stream in ALL_STREAMS {
            for index in 0..50_000u64 {
                let s = episode_seed(stream, index * 7 + 1, index % 97, index % 2, index);
                assert!(
                    (1..=MAX_SEED as i64).contains(&s),
                    "{stream:?} produced an illegal seed {s}"
                );
                assert_eq!(
                    (s - 1) % streams,
                    stream.residue() as i64,
                    "{stream:?} left its partition with seed {s}"
                );
            }
        }
    }

    #[test]
    fn no_two_streams_can_ever_share_an_episode_seed() {
        // The partitions are disjoint by construction, so ANY overlap between
        // two different streams is a defect, not bad luck. (Within a single
        // stream a repeat is possible in principle: 40,000 draws from about
        // 5.4e8 members collide now and then, which is harmless because the
        // slot, not the seed, is what identifies an episode.)
        let drawn: Vec<HashSet<i64>> = ALL_STREAMS
            .iter()
            .map(|stream| {
                (0..40_000u64)
                    .map(|index| episode_seed(*stream, 5, index % 211, index % 2, index))
                    .collect()
            })
            .collect();
        for (a, left) in drawn.iter().enumerate() {
            for (b, right) in drawn.iter().enumerate().skip(a + 1) {
                let shared: Vec<&i64> = left.intersection(right).collect();
                assert!(
                    shared.is_empty(),
                    "{:?} and {:?} shared seeds {shared:?}",
                    ALL_STREAMS[a],
                    ALL_STREAMS[b]
                );
            }
        }
    }

    #[test]
    fn the_partitions_exactly_cover_the_legal_seed_space() {
        let streams = ALL_STREAMS.len() as u64;
        let total: u64 = ALL_STREAMS
            .iter()
            .map(|s| (MAX_SEED - s.residue()).div_ceil(streams))
            .sum();
        assert_eq!(total, MAX_SEED, "the partitions lost or double counted seeds");
    }
}
