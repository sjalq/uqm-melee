//! `src/Melee/Trig.elm`. Integer trig from `units.h` / `trans.c`. No floats.

use crate::units::{WorldExtent, WorldPoint};

pub const FULL_CIRCLE: i64 = 64;
pub const HALF_CIRCLE: i64 = 32;
pub const QUADRANT: i64 = 16;
const SIN_SHIFT: u32 = 14;

/// `trans.c` sinetab, FLT_ADJUST toward zero, SIN_SCALE = 16384.
#[rustfmt::skip]
pub const SINETAB: [i64; 64] = [
    -16384, -16305, -16069, -15678, -15136, -14449, -13622, -12664,
    -11585, -10393, -9102, -7723, -6269, -4756, -3196, -1605,
    0, 1605, 3196, 4756, 6269, 7723, 9102, 10393,
    11585, 12664, 13622, 14449, 15136, 15678, 16069, 16305,
    16384, 16305, 16069, 15678, 15136, 14449, 13622, 12664,
    11585, 10393, 9102, 7723, 6269, 4756, 3196, 1605,
    0, -1605, -3196, -4756, -6269, -7723, -9102, -10393,
    -11585, -12664, -13622, -14449, -15136, -15678, -16069, -16305,
];

#[rustfmt::skip]
pub const ATANTAB: [i64; 33] = [
    0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,
    6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 8, 8, 8,
];

/// Elm `listAt`: out-of-range yields 0, matching `Maybe.withDefault 0`.
#[inline]
fn list_at(i: i64, xs: &[i64]) -> i64 {
    if i < 0 {
        0
    } else {
        xs.get(i as usize).copied().unwrap_or(0)
    }
}

#[inline]
pub fn normalize_angle(a: i64) -> i64 {
    a.rem_euclid(FULL_CIRCLE)
}

#[inline]
pub fn normalize_facing(f: i64) -> i64 {
    f.rem_euclid(16)
}

#[inline]
pub fn angle_to_facing(a: i64) -> i64 {
    normalize_facing((normalize_angle(a) + 2) / 4)
}

#[inline]
pub fn facing_to_angle(f: i64) -> i64 {
    normalize_facing(f) * 4
}

#[inline]
fn sin_val(a: i64) -> i64 {
    list_at(normalize_angle(a), &SINETAB)
}

/// `SINE(a, m) = (sinetab[a & 63] * m) >> 14`, with the Elm rounding written out.
#[inline]
pub fn sine(a: i64, m: i64) -> i64 {
    let product = sin_val(a) * m;
    let scale = 1i64 << SIN_SHIFT;
    if product < 0 {
        -((-product + scale - 1) / scale)
    } else {
        product / scale
    }
}

#[inline]
pub fn cosine(a: i64, m: i64) -> i64 {
    sine(a + QUADRANT, m)
}

/// `trans.c` ARCTAN. (0,0) returns FULL_CIRCLE (64); `velocity.c` treats 64 as
/// "zero vector" before normalising.
pub fn arctan(delta_x: i64, delta_y: i64) -> i64 {
    if delta_x == 0 && delta_y == 0 {
        return FULL_CIRCLE;
    }
    let v1_abs = delta_x.abs();
    let v2_abs = delta_y.abs();
    let raw = if v1_abs > v2_abs {
        QUADRANT - list_at(((v2_abs * 32) + (v1_abs / 2)) / v1_abs, &ATANTAB)
    } else {
        list_at(((v1_abs * 32) + (v2_abs / 2)) / v2_abs, &ATANTAB)
    };
    let after_x = if delta_x < 0 { FULL_CIRCLE - raw } else { raw };
    let after_y = if delta_y > 0 { HALF_CIRCLE - after_x } else { after_x };
    normalize_angle(after_y)
}

#[inline]
pub fn wrap(v: i64, w: i64) -> i64 {
    if w <= 0 {
        v
    } else if v < 0 {
        v + w
    } else if v >= w {
        v - w
    } else {
        v
    }
}

pub fn wrap_delta(d: i64, w: i64) -> i64 {
    if w <= 0 {
        return d;
    }
    let half = w / 2;
    if d < 0 {
        if -d <= half {
            d
        } else {
            w + d
        }
    } else if d <= half {
        d
    } else {
        d - w
    }
}

#[inline]
pub fn wrap_point(space: WorldExtent, p: WorldPoint) -> WorldPoint {
    WorldPoint { x: wrap(p.x, space.width), y: wrap(p.y, space.height) }
}

/// Integer square root, floor. Matches the Elm binary search exactly, including
/// its 46340 clamp.
pub fn square_root(value: i64) -> i64 {
    if value <= 0 {
        return 0;
    }
    let (mut lo, mut hi) = (0i64, value);
    while lo < hi {
        let mid = (lo + hi + 1) / 2;
        if mid > 46340 {
            hi = mid - 1;
        } else if mid * mid > value {
            hi = mid - 1;
        } else {
            lo = mid;
        }
    }
    lo
}
