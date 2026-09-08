//! `src/Melee/Arsenal.elm`. Weapon catalog selection and launch geometry.

use alloc::vec::Vec;

use crate::catalog::{BeamKind, Inheritance, MissileKind, MissileSpec, Mount, ShipKind, Weapon};
use crate::element::Body;
use crate::ship_state::{Combatant, MmrnmhrmForm};
use melee_core::trig;
use melee_core::units::{Facing, VelocityDesc, WorldPoint};
use melee_core::velocity;

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct LaunchState {
    pub position: WorldPoint,
    pub velocity: VelocityDesc,
}

pub fn primary(ship: &Combatant) -> Weapon {
    match ship {
        Combatant::LiveMmrnmhrm(_, extra) if extra.form == MmrnmhrmForm::YWing => {
            Weapon::Missile(MissileKind::Torpedo)
        }
        _ => standard(ship.kind()),
    }
}

#[inline]
pub fn standard(ship: ShipKind) -> Weapon {
    crate::catalog::standard_weapon(ship)
}

#[inline]
pub fn spec(missile: MissileKind) -> MissileSpec {
    *missile.spec()
}

#[inline]
pub fn missile_body(missile: MissileKind) -> Body {
    crate::catalog_generated::MISSILE_BODY[missile.index()]
}

pub fn beam_body(beam: BeamKind) -> Body {
    match beam {
        BeamKind::AutoAim => Body::ArilouLaser,
        BeamKind::Megawatt => Body::ChmmrLaser,
        BeamKind::Twin => Body::MmrnmhrmLaser,
        BeamKind::Green => Body::VuxLaser,
        BeamKind::PointDefense => Body::EarthlingPointDefense,
        BeamKind::Zap => Body::ChmmrZap,
        BeamKind::FighterBeam => Body::UrQuanFighterLaser,
    }
}

#[inline]
pub fn homing(body: Body) -> bool {
    body.homing()
}

#[inline]
pub fn is_projectile(body: Body) -> bool {
    body.is_projectile()
}

#[inline]
pub fn mounts(missile: &MissileSpec) -> Vec<Mount> {
    missile.mounts().to_vec()
}

pub fn mount_position(
    missile: &MissileSpec,
    facing: i64,
    origin: WorldPoint,
    mount: &Mount,
) -> WorldPoint {
    let angle = if missile.direction_count > 1 {
        facing + mount.facing_offset
    } else {
        facing
    } * 4;
    WorldPoint {
        x: origin.x
            + trig::cosine(angle, mount.forward * 4)
            + trig::cosine(angle + 16, mount.sideways * 4),
        y: origin.y
            + trig::sine(angle, mount.forward * 4)
            + trig::sine(angle + 16, mount.sideways * 4),
    }
}

pub fn launch_state(
    missile: &MissileSpec,
    facing: Facing,
    parent: &VelocityDesc,
    at: WorldPoint,
) -> LaunchState {
    let (dx, dy) = match missile.inheritance {
        Inheritance::InheritVelocity => velocity::get_current(parent),
        Inheritance::Independent => (0, 0),
    };
    // Elm uses floor(toFloat v / 32), which differs from integer truncation for
    // negative inherited velocity.
    let world = |v: i64| v.div_euclid(32);
    LaunchState {
        position: WorldPoint {
            x: at.x - world(dx),
            y: at.y - world(dy),
        },
        velocity: velocity::set_components(
            trig::cosine(facing * 4, missile.speed * 32) + dx,
            trig::sine(facing * 4, missile.speed * 32) + dy,
        ),
    }
}
