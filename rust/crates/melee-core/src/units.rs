//! `src/Melee/Units.elm`. Fixed-point units of the UQM battle simulation.

/// `stockLogSpace`. LOG_SPACE_WIDTH x LOG_SPACE_HEIGHT for stock 320x240 melee.
pub const STOCK_LOG_SPACE: WorldExtent = WorldExtent { width: 8192, height: 7680 };

pub const BATTLE_FRAMES_PER_SECOND: i64 = 24;
pub const MAX_CREW_SIZE: i64 = 42;
pub const MAX_ENERGY_SIZE: i64 = 42;
pub const MAX_SHIP_MASS: i64 = 10;
/// `GRAVITY_MASS(m) = m > MAX_SHIP_MASS * 10`.
pub const GRAVITY_MASS_THRESHOLD: i64 = 100;
pub const GRAVITY_THRESHOLD: i64 = 255;

/// The two seats of a melee. `Bottom` is playerNr 0, `Top` is playerNr 1.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(u32)]
pub enum Side {
    Bottom = 0,
    Top = 1,
}

impl Side {
    #[inline]
    pub fn other(self) -> Side {
        match self {
            Side::Bottom => Side::Top,
            Side::Top => Side::Bottom,
        }
    }

    #[inline]
    pub fn index(self) -> usize {
        self as u32 as usize
    }
}

/// Elm's `Sided a`: exactly one value per side, so a missing or extra side is
/// unrepresentable.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct Sided<T> {
    pub bottom: T,
    pub top: T,
}

impl<T> Sided<T> {
    #[inline]
    pub fn get(&self, side: Side) -> &T {
        match side {
            Side::Bottom => &self.bottom,
            Side::Top => &self.top,
        }
    }

    #[inline]
    pub fn get_mut(&mut self, side: Side) -> &mut T {
        match side {
            Side::Bottom => &mut self.bottom,
            Side::Top => &mut self.top,
        }
    }

    #[inline]
    pub fn set(&mut self, side: Side, value: T) {
        *self.get_mut(side) = value;
    }
}

impl<T: Copy> Sided<T> {
    #[inline]
    pub fn both(value: T) -> Self {
        Sided { bottom: value, top: value }
    }
}

/// Angle in 1/64ths of a circle, normalised to 0..63.
pub type Angle = i64;
/// Ship facing in 1/16ths of a circle, normalised to 0..15.
pub type Facing = i64;

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct WorldPoint {
    pub x: i64,
    pub y: i64,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct WorldExtent {
    pub width: i64,
    pub height: i64,
}

/// UQM's `VELOCITY_DESC`, verbatim, including the `error` and `fract`
/// accumulators that carry sub-unit remainders across frames.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct VelocityDesc {
    pub travel_angle: Angle,
    pub vector: WorldExtent,
    pub fract: WorldExtent,
    pub error: WorldExtent,
    pub incr: WorldExtent,
}
