//! `src/Melee/Input.elm`. Inputs visible to the deterministic battle loop.

/// LEFT wins when both physical turn keys are held, so the simulation sees
/// exactly one of these three states.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub enum Turn {
    #[default]
    NoTurn,
    TurnLeft,
    TurnRight,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct BattleInput {
    pub turn: Turn,
    pub thrust: bool,
    pub weapon: bool,
    pub special: bool,
}

#[inline]
pub const fn idle() -> BattleInput {
    BattleInput {
        turn: Turn::NoTurn,
        thrust: false,
        weapon: false,
        special: false,
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum CyborgRating {
    StandardCyborg,
    GoodCyborg,
    AwesomeCyborg,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum KeyLayout {
    KeyLayoutOne,
    KeyLayoutTwo,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Controller {
    LocalHuman(KeyLayout),
    LocalCyborg(CyborgRating),
    Remote,
}
