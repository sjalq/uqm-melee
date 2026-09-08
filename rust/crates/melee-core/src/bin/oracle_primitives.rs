//! Rust half of the primitive differential oracle.
//!
//! Emits byte-for-byte the same dump as `tests/Oracle/Primitives.elm`.
//! `scripts/oracle/check-primitives.sh` diffs the two; any output is a defect.

use melee_core::rng::Seed;
use melee_core::trig;
use melee_core::units::VelocityDesc;
use melee_core::velocity;
use std::fmt::Write as _;

fn main() {
    let mut out = String::with_capacity(1 << 20);
    let rows = dump();
    for (i, line) in rows.iter().enumerate() {
        if i > 0 {
            out.push('\n');
        }
        out.push_str(line);
    }
    out.push('\n');
    print!("{out}");
}

fn row(tag: &str, values: &[i64]) -> String {
    let mut s = String::from(tag);
    for v in values {
        let _ = write!(s, " {v}");
    }
    s
}

/// Elm `stream`: `modBy span v - span // 2`, drawn from the battle RNG.
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

fn dump() -> Vec<String> {
    let mut rows = Vec::new();
    rows.extend(rng_sweep());
    rows.extend(trig_sweep());
    rows.extend(arctan_sweep());
    rows.extend(sqrt_sweep());
    rows.extend(wrap_sweep());
    rows.extend(velocity_sweep());
    rows
}

fn rng_sweep() -> Vec<String> {
    let mut rows = Vec::new();
    for s in [1i64, 2, 42, 1701, 16807, 127773, 2147483646] {
        let mut seed = Seed(s);
        let mut values = Vec::with_capacity(200);
        for _ in 0..200 {
            let (v, next) = seed.next();
            seed = next;
            values.push(v);
        }
        rows.push(row(&format!("rng {s}"), &values));
    }
    for (s, n) in [(1i64, 0i64), (42, -5), (42, 2147483647), (42, 2147483648), (7, 12345)] {
        let (prev, after) = Seed(s).seed_random(n);
        rows.push(row(&format!("rngseed {s} {n}"), &[prev, after.0]));
    }
    rows
}

fn trig_sweep() -> Vec<String> {
    const MAGS: [i64; 14] = [
        -100000, -32768, -4097, -256, -33, -1, 0, 1, 33, 256, 4097, 32768, 100000, 1048576,
    ];
    let mut rows = Vec::new();
    for a in -70..=70i64 {
        let mut values: Vec<i64> = MAGS.iter().map(|&m| trig::sine(a, m)).collect();
        values.extend(MAGS.iter().map(|&m| trig::cosine(a, m)));
        rows.push(row(&format!("sin {a}"), &values));
    }
    for a in -40..=40i64 {
        rows.push(row(&format!("norm {a}"), &[trig::normalize_angle(a), trig::normalize_facing(a)]));
    }
    rows
}

fn arctan_sweep() -> Vec<String> {
    const GRID: [i64; 13] =
        [-4096, -1024, -257, -64, -17, -1, 0, 1, 17, 64, 257, 1024, 4096];
    let mut pairs: Vec<(i64, i64)> = Vec::new();
    for &x in GRID.iter() {
        for &y in GRID.iter() {
            pairs.push((x, y));
        }
    }
    let (rx, seed1) = stream(400, 200000, Seed(1701));
    let (ry, _) = stream(400, 200000, seed1);
    pairs.extend(rx.iter().zip(ry.iter()).map(|(&x, &y)| (x, y)));
    pairs
        .into_iter()
        .map(|(x, y)| row(&format!("atan {x} {y}"), &[trig::arctan(x, y)]))
        .collect()
}

fn sqrt_sweep() -> Vec<String> {
    let (rs, _) = stream(300, 2000000000, Seed(99));
    let mut values: Vec<i64> = (-3..=300i64).collect();
    values.extend([65535i64, 65536, 1048576, 2146689000]);
    values.extend(rs.iter().map(|v| v.abs()));
    values
        .into_iter()
        .map(|v| row(&format!("sqrt {v}"), &[trig::square_root(v)]))
        .collect()
}

fn wrap_sweep() -> Vec<String> {
    const WIDTHS: [i64; 5] = [0, 1, 64, 8192, 7680];
    const VALS: [i64; 10] = [-9000, -8192, -1, 0, 1, 4095, 4096, 8191, 8192, 9000];
    let mut rows = Vec::new();
    for &w in WIDTHS.iter() {
        for &v in VALS.iter() {
            rows.push(row(
                &format!("wrap {w} {v}"),
                &[trig::wrap(v, w), trig::wrap_delta(v, w)],
            ));
        }
    }
    rows
}

fn describe(v: &VelocityDesc) -> Vec<i64> {
    vec![
        v.travel_angle,
        v.vector.width,
        v.vector.height,
        v.fract.width,
        v.fract.height,
        v.error.width,
        v.error.height,
        v.incr.width,
        v.incr.height,
    ]
}

fn integrate(n: i64, v: VelocityDesc) -> ((i64, i64), VelocityDesc) {
    let (mut sx, mut sy) = (0i64, 0i64);
    let mut cur = v;
    for _ in 0..n {
        let ((dx, dy), next) = velocity::get_next(1, &cur);
        cur = next;
        sx += dx;
        sy += dy;
    }
    ((sx, sy), cur)
}

fn velocity_sweep() -> Vec<String> {
    let (dxs, seed1) = stream(500, 4000, Seed(424242));
    let (dys, _) = stream(500, 4000, seed1);
    let pairs: Vec<(i64, i64)> =
        dxs.iter().zip(dys.iter()).map(|(&a, &b)| (a, b)).collect();

    let mut rows = Vec::new();

    for &(dx, dy) in pairs.iter() {
        let v = velocity::set_components(dx, dy);
        let (cx, cy) = velocity::get_current(&v);
        let ((sx, sy), after) = integrate(40, v);
        let mut values = describe(&v);
        values.extend([cx, cy, sx, sy]);
        values.extend(describe(&after));
        rows.push(row(&format!("vel {dx} {dy}"), &values));
    }

    for mag in [0i64, 1, 4, 7, 16, 40, 100, 255, 1024] {
        for f in -3..=18i64 {
            let v = velocity::set_vector(mag, f);
            let ((sx, sy), after) = integrate(24, v);
            let mut values = describe(&v);
            values.extend([sx, sy]);
            values.extend(describe(&after));
            rows.push(row(&format!("velvec {mag} {f}"), &values));
        }
    }

    for &(dx, dy) in pairs.iter() {
        let base = velocity::set_components(dx, dy);
        let stepped = velocity::delta(dy / 3, dx / 5, &base);
        rows.push(row(&format!("veldelta {dx} {dy}"), &describe(&stepped)));
    }

    rows
}
