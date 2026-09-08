//! Types for the immutable catalog tables.
//!
//! The tables themselves live in `catalog_generated.rs`, produced from the Elm
//! source of truth by `scripts/oracle/gen-catalog.mjs`. Never hand-edit them:
//! regenerate instead, so `Melee.Ship`/`Melee.Arsenal` stay authoritative.

use melee_core::units::Facing;

/// `Melee.Ship.ShipKind`. Discriminants follow Elm constructor order, which is
/// also `meleeship.h` order and the 5-bit hull id the policy network sees.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(u8)]
pub enum ShipKind {
    Androsynth = 0,
    Arilou,
    Chenjesu,
    Chmmr,
    Druuge,
    Earthling,
    Ilwrath,
    KohrAh,
    Melnorme,
    Mmrnmhrm,
    Mycon,
    Orz,
    Pkunk,
    Shofixti,
    Slylandro,
    Spathi,
    Supox,
    Syreen,
    Thraddash,
    Umgah,
    UrQuan,
    Utwig,
    Vux,
    Yehat,
    ZoqFotPik,
}

pub const MELEE_SHIP_COUNT: usize = 25;

pub const ALL_SHIPS: [ShipKind; MELEE_SHIP_COUNT] = {
    use ShipKind::*;
    [
        Androsynth, Arilou, Chenjesu, Chmmr, Druuge, Earthling, Ilwrath, KohrAh, Melnorme,
        Mmrnmhrm, Mycon, Orz, Pkunk, Shofixti, Slylandro, Spathi, Supox, Syreen, Thraddash, Umgah,
        UrQuan, Utwig, Vux, Yehat, ZoqFotPik,
    ]
};

impl ShipKind {
    #[inline]
    pub const fn index(self) -> usize {
        self as u8 as usize
    }

    /// Parses the names `Neat.Eval.kindFrom` accepts, with its same fallback.
    pub fn from_str_lossy(raw: &str) -> ShipKind {
        let lower = raw.to_ascii_lowercase();
        match lower.as_str() {
            "androsynth" => ShipKind::Androsynth,
            "arilou" => ShipKind::Arilou,
            "chenjesu" => ShipKind::Chenjesu,
            "chmmr" => ShipKind::Chmmr,
            "druuge" => ShipKind::Druuge,
            "earthling" => ShipKind::Earthling,
            "ilwrath" => ShipKind::Ilwrath,
            "kohr-ah" | "kohrah" => ShipKind::KohrAh,
            "melnorme" => ShipKind::Melnorme,
            "mmrnmhrm" => ShipKind::Mmrnmhrm,
            "mycon" => ShipKind::Mycon,
            "orz" => ShipKind::Orz,
            "pkunk" => ShipKind::Pkunk,
            "shofixti" => ShipKind::Shofixti,
            "slylandro" => ShipKind::Slylandro,
            "spathi" => ShipKind::Spathi,
            "supox" => ShipKind::Supox,
            "syreen" => ShipKind::Syreen,
            "thraddash" => ShipKind::Thraddash,
            "umgah" => ShipKind::Umgah,
            "ur-quan" | "urquan" => ShipKind::UrQuan,
            "utwig" => ShipKind::Utwig,
            "vux" => ShipKind::Vux,
            "yehat" => ShipKind::Yehat,
            "zoq-fot-pik" | "zoqfotpik" => ShipKind::ZoqFotPik,
            _ => ShipKind::Pkunk,
        }
    }

    #[inline]
    pub fn stock(self) -> &'static Stock {
        &crate::catalog_generated::STOCK[self.index()]
    }

    /// `Melee.Catalog.info(kind).name`, which is what the fitness report emits.
    #[inline]
    pub fn name(self) -> &'static str {
        crate::catalog_generated::SHIP_NAMES[self.index()]
    }

    /// `INTEL_STUFF.WeaponRange` in world units.
    #[inline]
    pub fn intel_range(self) -> i64 {
        crate::catalog_generated::INTEL_RANGE[self.index()]
    }
}

/// `SHIP_INFO.ship_flags` as individual booleans.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct Ability {
    pub seeking_weapon: bool,
    pub seeking_special: bool,
    pub point_defense: bool,
    pub immediate_weapon: bool,
    pub crew_immune: bool,
    pub fires_fore: bool,
    pub fires_right: bool,
    pub fires_aft: bool,
    pub fires_left: bool,
    pub shield_defense: bool,
    pub dont_chase: bool,
}

/// Live `CHARACTERISTIC_STUFF`. `energy_regeneration` is signed: the Androsynth
/// blazer writes -1, which `ship.c` treats as "always apply".
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct Characteristics {
    pub max_thrust: i64,
    pub thrust_increment: i64,
    pub energy_regeneration: i64,
    pub weapon_energy_cost: i64,
    pub special_energy_cost: i64,
    pub energy_wait: i64,
    pub turn_wait: i64,
    pub thrust_wait: i64,
    pub weapon_wait: i64,
    pub special_wait: i64,
    pub ship_mass: i64,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct Stock {
    pub kind: ShipKind,
    pub cost: i64,
    pub max_crew: i64,
    pub max_energy: i64,
    pub starting_crew: i64,
    pub starting_energy: i64,
    pub ability: Ability,
    pub characteristics: Characteristics,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(u8)]
pub enum MissileKind {
    Bubble = 0,
    Crystal,
    Shard,
    Dogi,
    Cannon,
    Nuke,
    Flame,
    Saw,
    Fried,
    Charge,
    Confusion,
    Torpedo,
    Plasma,
    Howitzer,
    Marine,
    Bug,
    Dart,
    SpathiShot,
    Butt,
    Pellet,
    Dagger,
    Blaster,
    Napalm,
    Fusion,
    Fighter,
    Lance,
    Limpet,
    YehatShot,
    Spit,
}

pub const MISSILE_KIND_COUNT: usize = 29;

impl MissileKind {
    #[inline]
    pub const fn index(self) -> usize {
        self as u8 as usize
    }

    #[inline]
    pub fn spec(self) -> &'static MissileSpec {
        &crate::catalog_generated::MISSILE_SPECS[self.index()]
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(u8)]
pub enum BeamKind {
    AutoAim = 0,
    Megawatt,
    Twin,
    Green,
    PointDefense,
    Zap,
    FighterBeam,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(u8)]
pub enum ContactKind {
    Cone = 0,
    Tongue,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Guidance {
    Ballistic,
    Tracking { wait: i64, initial_wait: i64 },
    BubbleFlight,
    HeldBlade,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Animation {
    Directional,
    Frames { count: i64, ticks: i64 },
    PlasmaDecay,
    ChargeLevel,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Inheritance {
    Independent,
    InheritVelocity,
}

/// One launch port, already resolved from `Melee.Arsenal.mounts`.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct Mount {
    pub forward: i64,
    pub sideways: i64,
    pub facing_offset: i64,
}

/// Largest `mounts` list in the catalog (Utwig Lance has 6, Pkunk 3, the
/// widest `directions` list is 8). Fixed capacity keeps the spec POD.
pub const MAX_MOUNTS: usize = 8;

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct MissileSpec {
    pub kind: MissileKind,
    pub speed: i64,
    pub life: i64,
    pub damage: i64,
    pub hit_points: i64,
    pub guidance: Guidance,
    pub animation: Animation,
    pub inheritance: Inheritance,
    pub blast_offset: i64,
    pub friendly_fire: bool,
    /// `directions` length; `mountPosition` only adds `facingOffset` when > 1.
    pub direction_count: usize,
    pub mount_count: usize,
    pub mounts: [Mount; MAX_MOUNTS],
}

impl MissileSpec {
    #[inline]
    pub fn mounts(&self) -> &[Mount] {
        &self.mounts[..self.mount_count]
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Weapon {
    Missile(MissileKind),
    Beam(BeamKind),
    Contact(ContactKind),
    Lightning,
}

/// `Melee.Arsenal.standard`. The Mmrnmhrm Y-wing override lives in
/// `Arsenal::primary`, which needs live state.
#[inline]
pub fn standard_weapon(kind: ShipKind) -> Weapon {
    crate::catalog_generated::STANDARD_WEAPON[kind.index()]
}

/// `Melee.Ship.mmrnmhrmYWing`: the stored inactive wing characteristics.
#[inline]
pub fn mmrnmhrm_y_wing() -> Characteristics {
    crate::catalog_generated::MMRNMHRM_Y_WING
}

/// Kept for the satellite body payload, which is a facing.
pub type OrbitFacing = Facing;
