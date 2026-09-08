//! `src/Melee/Velocity.elm` / `velocity.c`, integer only.
//! `incr` stores MAKE_WORD packed as an Int.

use crate::trig;
use crate::units::{Facing, VelocityDesc, WorldExtent};

pub const VELOCITY_SHIFT: u32 = 5;
pub const VELOCITY_SCALE: i64 = 32;

#[inline]
fn world_to_velocity(w: i64) -> i64 {
    w * VELOCITY_SCALE
}

#[inline]
fn velocity_to_world(v: i64) -> i64 {
    v / VELOCITY_SCALE
}

#[inline]
fn remainder(v: i64) -> i64 {
    v.rem_euclid(VELOCITY_SCALE)
}

#[inline]
fn lo_byte(x: i64) -> i64 {
    x.rem_euclid(256)
}

#[inline]
fn hi_byte(x: i64) -> i64 {
    (x / 256).rem_euclid(256)
}

#[inline]
fn s_byte(b: i64) -> i64 {
    if b >= 128 {
        b - 256
    } else {
        b
    }
}

#[inline]
fn make_word(lo: i64, hi: i64) -> i64 {
    lo.rem_euclid(256) + hi.rem_euclid(256) * 256
}

pub const ZERO: VelocityDesc = VelocityDesc {
    travel_angle: 0,
    vector: WorldExtent {
        width: 0,
        height: 0,
    },
    fract: WorldExtent {
        width: 0,
        height: 0,
    },
    error: WorldExtent {
        width: 0,
        height: 0,
    },
    incr: WorldExtent {
        width: 0,
        height: 0,
    },
};

pub fn get_current(v: &VelocityDesc) -> (i64, i64) {
    (
        world_to_velocity(v.vector.width) + (v.fract.width - hi_byte(v.incr.width)),
        world_to_velocity(v.vector.height) + (v.fract.height - hi_byte(v.incr.height)),
    )
}

/// `GetNextVelocityComponents`. Consumes the error accumulator, so the returned
/// descriptor must replace the old one.
pub fn get_next(num_frames: i64, v: &VelocityDesc) -> ((i64, i64), VelocityDesc) {
    #[inline]
    fn axis(err: i64, fract: i64, vector: i64, incr: i64, num_frames: i64) -> (i64, i64) {
        let e = err + fract * num_frames;
        let d = vector * num_frames + s_byte(lo_byte(incr)) * (e / VELOCITY_SCALE);
        (d, remainder(e))
    }
    let (dx, err_x) = axis(
        v.error.width,
        v.fract.width,
        v.vector.width,
        v.incr.width,
        num_frames,
    );
    let (dy, err_y) = axis(
        v.error.height,
        v.fract.height,
        v.vector.height,
        v.incr.height,
        num_frames,
    );
    let mut out = *v;
    out.error = WorldExtent {
        width: err_x,
        height: err_y,
    };
    ((dx, dy), out)
}

fn set_packed(d: i64) -> (i64, i64) {
    if d >= 0 {
        (velocity_to_world(d), make_word(1, 0))
    } else {
        let ad = -d;
        (-velocity_to_world(ad), make_word(0xFF, remainder(ad) * 2))
    }
}

pub fn set_components(dx: i64, dy: i64) -> VelocityDesc {
    let angle = trig::arctan(dx, dy);
    if angle == trig::FULL_CIRCLE {
        return ZERO;
    }
    let ax = dx.abs();
    let ay = dy.abs();
    let (vw, iw) = set_packed(dx);
    let (vh, ih) = set_packed(dy);
    VelocityDesc {
        travel_angle: trig::normalize_angle(angle),
        vector: WorldExtent {
            width: vw,
            height: vh,
        },
        fract: WorldExtent {
            width: remainder(ax),
            height: remainder(ay),
        },
        error: WorldExtent {
            width: 0,
            height: 0,
        },
        incr: WorldExtent {
            width: iw,
            height: ih,
        },
    }
}

pub fn set_vector(magnitude: i64, facing: Facing) -> VelocityDesc {
    let angle = trig::normalize_facing(facing) * 4;
    let mag_v = world_to_velocity(magnitude);
    let dx = trig::cosine(angle, mag_v);
    let dy = trig::sine(angle, mag_v);
    let mut v = set_components(dx, dy);
    v.travel_angle = angle;
    v
}

pub fn delta(ddx: i64, ddy: i64, v: &VelocityDesc) -> VelocityDesc {
    let (cx, cy) = get_current(v);
    set_components(cx + ddx, cy + ddy)
}
