//! Rust half of the like-for-like throughput benchmark. Identical workload to
//! `tests/Oracle/Bench.elm`; the printed checksums must match, so a faster run
//! that quietly did less work is caught.

use melee_core::rng::Seed;
use melee_core::units::VelocityDesc;
use melee_core::velocity;
use melee_sim::catalog::ShipKind;
use melee_sim::masks::{overlap, Mask};
use melee_sim::masks_generated::ship_mask;

const VELOCITY_ROUNDS: i64 = 200;
const MASK_ROUNDS: i64 = 200;

fn main() {
    // Component selection mirrors the Elm bench, which always prints both
    // lines and zeroes the round count of the component it is not measuring.
    // "none" measures process startup alone.
    let which = std::env::args().nth(1).unwrap_or_else(|| "both".to_string());
    let (vel_rounds, mask_rounds) = match which.as_str() {
        "velocity" => (VELOCITY_ROUNDS, 0),
        "mask" => (0, MASK_ROUNDS),
        "none" => (0, 0),
        _ => (VELOCITY_ROUNDS, MASK_ROUNDS),
    };
    println!("velocity {}", velocity_bench(vel_rounds));
    println!("mask {}", mask_bench(mask_rounds));
}

fn stream(count: usize, span: i64, seed0: Seed) -> (Vec<i64>, Seed) {
    let mut seed = seed0;
    let mut acc = Vec::with_capacity(count);
    for _ in 0..count {
        let (v, next) = seed.next();
        seed = next;
        acc.push(v.rem_euclid(span) - span / 2);
    }
    (acc, seed)
}

fn pairs() -> Vec<(i64, i64)> {
    let (dxs, seed1) = stream(500, 4000, Seed(424242));
    let (dys, _) = stream(500, 4000, seed1);
    dxs.iter().zip(dys.iter()).map(|(&a, &b)| (a, b)).collect()
}

/// 500 launches, each integrated for 40 frames.
fn velocity_bench(rounds: i64) -> i64 {
    let pairs = pairs();
    let mut acc = 0i64;
    for _ in 0..rounds {
        for &(dx, dy) in &pairs {
            let mut v: VelocityDesc = velocity::set_components(dx, dy);
            let mut total = 0i64;
            for _ in 0..40 {
                let ((sx, sy), next) = velocity::get_next(1, &v);
                v = next;
                total += sx + sy;
            }
            acc += total;
        }
    }
    acc
}

fn offsets() -> Vec<i64> {
    (0..=18).map(|i| i * 7 - 63).collect()
}

fn mask_pairs() -> Vec<(&'static Mask, &'static Mask)> {
    use ShipKind::*;
    [
        ((Pkunk, 0i64), (Umgah, 8i64)),
        ((Yehat, 3), (Pkunk, 11)),
        ((Chenjesu, 5), (Chmmr, 2)),
        ((UrQuan, 7), (Earthling, 13)),
    ]
    .into_iter()
    .filter_map(|((ka, fa), (kb, fb))| {
        Some((ship_mask(ka, false, fa)?, ship_mask(kb, false, fb)?))
    })
    .collect()
}

/// Every probe pair over a 19x19 offset grid.
fn mask_bench(rounds: i64) -> i64 {
    let pairs = mask_pairs();
    let offsets = offsets();
    let mut acc = 0i64;
    for _ in 0..rounds {
        for (a, b) in &pairs {
            for &dy in &offsets {
                for &dx in &offsets {
                    if overlap(a, b, dx, dy) {
                        acc += 1;
                    }
                }
            }
        }
    }
    acc
}
