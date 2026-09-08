//! `src/Melee/Motion.elm`. Typed interpretation of the combined speed flags.

use crate::ship_state::{CombatantCore, MotionFlags};
use melee_core::trig;
use melee_core::units::VelocityDesc;
use melee_core::velocity;

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Speed {
    BelowLimit,
    AtLimit,
    GravityBoosted,
    BeyondLimit,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Motion {
    Stationary,
    Moving(VelocityDesc, Speed),
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct SpeedFlags {
    pub at_max_speed: bool,
    pub beyond_max_speed: bool,
}

#[inline]
fn from_velocity(v: VelocityDesc, speed: Speed) -> Motion {
    if velocity::get_current(&v) == (0, 0) {
        Motion::Stationary
    } else {
        Motion::Moving(v, speed)
    }
}

#[inline]
pub fn current(v: &VelocityDesc, state: &MotionFlags) -> Motion {
    let speed = match (state.at_max_speed, state.beyond_max_speed) {
        (false, false) => Speed::BelowLimit,
        (true, false) => Speed::AtLimit,
        (false, true) => Speed::GravityBoosted,
        (true, true) => Speed::BeyondLimit,
    };
    from_velocity(*v, speed)
}

#[inline]
pub fn velocity_of(motion: Motion) -> VelocityDesc {
    match motion {
        Motion::Stationary => velocity::ZERO,
        Motion::Moving(v, _) => v,
    }
}

/// Alias matching the Elm function name.
#[inline]
pub fn velocity(motion: Motion) -> VelocityDesc {
    velocity_of(motion)
}

#[inline]
pub fn flags(motion: Motion) -> SpeedFlags {
    match motion {
        Motion::Stationary => SpeedFlags::default(),
        Motion::Moving(_, speed) => SpeedFlags {
            at_max_speed: matches!(speed, Speed::AtLimit | Speed::BeyondLimit),
            beyond_max_speed: matches!(speed, Speed::GravityBoosted | Speed::BeyondLimit),
        },
    }
}

#[inline]
pub fn at_limit(v: &VelocityDesc, state: &MotionFlags) -> bool {
    !matches!(
        current(v, state),
        Motion::Stationary | Motion::Moving(_, Speed::BelowLimit)
    )
}

#[inline]
pub fn beyond_limit(v: &VelocityDesc, state: &MotionFlags) -> bool {
    flags(current(v, state)).beyond_max_speed
}

pub fn thrust(v: &VelocityDesc, c: &CombatantCore) -> Motion {
    let chars = c.characteristics;
    let angle = c.facing * 4;
    let travel = v.travel_angle;
    let increment = chars.thrust_increment * 32;
    let (cx, cy) = velocity::get_current(v);
    let dx = cx + trig::cosine(angle, increment);
    let dy = cy + trig::sine(angle, increment);
    let desired = dx * dx + dy * dy;
    let maximum = chars.max_thrust * 32;
    let max_squared = maximum * maximum;
    let current_squared = cx * cx + cy * cy;

    if chars.thrust_increment == chars.max_thrust {
        from_velocity(
            velocity::set_vector(chars.max_thrust, c.facing),
            Speed::AtLimit,
        )
    } else if travel == angle && at_limit(v, &c.flags) && !c.flags.in_gravity_well {
        current(v, &c.flags)
    } else if desired <= max_squared {
        from_velocity(velocity::set_components(dx, dy), Speed::BelowLimit)
    } else if (c.flags.in_gravity_well && desired <= 2304 * 2304) || desired < current_squared {
        from_velocity(velocity::set_components(dx, dy), Speed::BeyondLimit)
    } else if travel == angle {
        from_velocity(
            if current_squared <= max_squared {
                velocity::set_vector(chars.max_thrust, c.facing)
            } else {
                *v
            },
            Speed::AtLimit,
        )
    } else {
        let turned = velocity::delta(
            trig::cosine(angle, increment / 2) - trig::cosine(travel, increment),
            trig::sine(angle, increment / 2) - trig::sine(travel, increment),
            v,
        );
        let (tx, ty) = velocity::get_current(&turned);
        let turned_squared = tx * tx + ty * ty;
        if turned_squared > max_squared {
            from_velocity(
                if turned_squared < current_squared {
                    turned
                } else {
                    *v
                },
                Speed::BeyondLimit,
            )
        } else {
            from_velocity(turned, Speed::BelowLimit)
        }
    }
}
