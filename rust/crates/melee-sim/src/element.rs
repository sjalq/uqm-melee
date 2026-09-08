//! `src/Melee/Element.elm`. One node of the display queue: UQM's ELEMENT with
//! the C unions split so a planet cannot carry a weapon counter.

use crate::catalog::{MissileKind, ShipKind};
use melee_core::units::{Facing, Side, VelocityDesc, WorldPoint};

/// `MAX_DISPLAY_ELEMENTS`.
pub const MAX_DISPLAY_ELEMENTS: usize = 150;

/// `Melee.Id.ElementId`. 0 is never allocated (C uses 0 as the null HLINK).
#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, Debug, Hash, Default)]
pub struct ElementId(pub i64);

/// playerNr -1 / 0 / 1.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub enum Owner {
    #[default]
    Neutral,
    Owned(Side),
}

impl Owner {
    #[inline]
    pub fn side(self) -> Option<Side> {
        match self {
            Owner::Neutral => None,
            Owner::Owned(s) => Some(s),
        }
    }
}

/// ELEMENT_FLAGS as booleans, in the Elm field order.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct ElementFlags {
    pub player_ship: bool,
    pub appearing: bool,
    pub disappearing: bool,
    pub changing: bool,
    pub nonsolid: bool,
    pub collision: bool,
    pub ignore_similar: bool,
    pub defy_physics: bool,
    pub finite_life: bool,
    pub pre_process: bool,
    pub post_process: bool,
    pub ignore_velocity: bool,
    pub crew_object: bool,
    pub background_object: bool,
}

/// Ships and the planet are not FINITE_LIFE; weapons are.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Life {
    Persistent(i64),
    Finite(i64),
}

impl Default for Life {
    fn default() -> Self {
        Life::Persistent(0)
    }
}

impl Life {
    /// `Melee.Step.lifeTicks`.
    #[inline]
    pub fn ticks(self) -> i64 {
        match self {
            Life::Persistent(n) | Life::Finite(n) => n,
        }
    }

    /// `Melee.Step.decLife`. Persistent life never counts down.
    #[inline]
    pub fn dec(self) -> Life {
        match self {
            Life::Persistent(n) => Life::Persistent(n),
            Life::Finite(n) => Life::Finite((n - 1).max(0)),
        }
    }
}

/// `gfxlib.h INTERSECT_CONTROL`.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct IntersectControl {
    pub last_time_val: i64,
    pub end_point: WorldPoint,
    pub stamp_origin: WorldPoint,
}

/// Display prim. OBJECT_CLOAKED is `NoPrim` or a black `StampFill`.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub enum Prim {
    #[default]
    NoPrim,
    Stamp,
    StampFill {
        black: bool,
    },
    Line,
}

impl Prim {
    /// `Melee.Element.objectCloaked`.
    #[inline]
    pub fn object_cloaked(self) -> bool {
        match self {
            Prim::NoPrim => true,
            Prim::StampFill { black } => black,
            Prim::Stamp | Prim::Line => false,
        }
    }
}

/// C STATE: location plus the facing/anim index of the stamp.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct Image {
    pub location: WorldPoint,
    pub frame_index: i64,
}

/// `Melee.Element.Body`. Payload-carrying variants keep the Elm payloads.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Body {
    Ship(Side),
    Wreck(Side),
    Planet,
    Asteroid,
    Crew { origin: Side },
    WeaponImpact(MissileKind),
    Blast,
    Explosion,
    WarpIn,
    IonTrail,
    AndrosynthBubble,
    ArilouLaser,
    ChenjesuPhoton,
    ChenjesuFragment,
    ChenjesuDogi,
    ChmmrLaser,
    ChmmrSatellite { orbit_facing: Facing },
    ChmmrZap,
    DruugeHotShot,
    EarthlingNuke,
    EarthlingPointDefense,
    IlwrathFlame,
    KohrAhSaw,
    KohrAhFried,
    MelnormeCharge,
    MelnormeConfusion,
    MmrnmhrmLaser,
    MmrnmhrmMissile,
    MyconPlasma,
    OrzHowitzer,
    OrzMarine,
    PkunkSpread,
    ShofixtiDart,
    ShofixtiGlory,
    SlylandroLightning,
    SpathiForward,
    SpathiButt,
    SupoxPellet,
    SyreenMissile,
    ThraddashBlaster,
    ThraddashAfterburn,
    UmgahCone,
    UrQuanFusion,
    UrQuanFighter,
    UrQuanFighterLaser,
    UtwigGizmo,
    VuxLaser,
    VuxLimpet,
    YehatMissile,
    ZoqSpit,
    ZoqTongue,
}

impl Default for Body {
    fn default() -> Self {
        Body::Planet
    }
}

impl Body {
    /// `Melee.Arsenal.isProjectile`: everything that is not a ship, wreck,
    /// planet, asteroid, crew, impact, blast, explosion, warp-in, ion trail or
    /// Chmmr satellite.
    pub fn is_projectile(self) -> bool {
        !matches!(
            self,
            Body::Ship(_)
                | Body::Wreck(_)
                | Body::Planet
                | Body::Asteroid
                | Body::Crew { .. }
                | Body::WeaponImpact(_)
                | Body::Blast
                | Body::Explosion
                | Body::WarpIn
                | Body::IonTrail
                | Body::ChmmrSatellite { .. }
        )
    }

    /// `Melee.Arsenal.homing`.
    pub fn homing(self) -> bool {
        matches!(
            self,
            Body::AndrosynthBubble
                | Body::EarthlingNuke
                | Body::MyconPlasma
                | Body::MmrnmhrmMissile
                | Body::SpathiButt
                | Body::VuxLimpet
                | Body::ChenjesuDogi
                | Body::OrzMarine
                | Body::UrQuanFighter
        )
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct Element {
    pub id: ElementId,
    pub owner: Owner,
    pub parent: Option<Side>,
    pub target: Option<ElementId>,
    pub flags: ElementFlags,
    pub life: Life,
    /// C `crew_level` / `hit_points` union.
    pub points: i64,
    /// C `mass_points`: damage for weapons, inertial mass for bodies.
    pub mass: i64,
    pub turn_wait: i64,
    pub thrust_wait: i64,
    pub color_cycle_index: i64,
    pub velocity: VelocityDesc,
    pub intersect: IntersectControl,
    pub current: Image,
    pub next: Image,
    pub prim: Prim,
    pub projectile: Option<ProjectileState>,
    pub body: Body,
}

/// `Melee.Projectile.State`.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum ProjectileState {
    Flying {
        kind: MissileKind,
        age: i64,
        facing: Facing,
        tracking_wait: i64,
    },
    Charging {
        ticks: i64,
        facing: Facing,
    },
    Ray {
        beam: crate::catalog::BeamKind,
        origin: WorldPoint,
        end: WorldPoint,
    },
    Attached {
        contact: crate::catalog::ContactKind,
        age: i64,
        facing: Facing,
    },
    LightningSegment {
        origin: WorldPoint,
        end: WorldPoint,
    },
}

/// `Melee.Init.emptyFlags`.
pub const EMPTY_FLAGS: ElementFlags = ElementFlags {
    player_ship: false,
    appearing: false,
    disappearing: false,
    changing: false,
    nonsolid: false,
    collision: false,
    ignore_similar: false,
    defy_physics: false,
    finite_life: false,
    pre_process: false,
    post_process: false,
    ignore_velocity: false,
    crew_object: false,
    background_object: false,
};

/// Convenience for the ship-kind carried by a `Body::Ship`, used by the
/// observation encoder.
pub fn ship_kind_of(body: Body, kinds: melee_core::units::Sided<ShipKind>) -> Option<ShipKind> {
    match body {
        Body::Ship(side) | Body::Wreck(side) => Some(*kinds.get(side)),
        _ => None,
    }
}
