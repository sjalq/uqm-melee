//! `src/Melee/Battle.elm`. State owned by one deterministic battle round.

use alloc::collections::BTreeMap;
use alloc::vec::Vec;

use crate::element::{Element, ElementId};
use crate::ship_state::Combatant;
use melee_core::rng::Seed;
use melee_core::units::{Sided, WorldExtent, WorldPoint};

#[derive(Clone, PartialEq, Eq, Debug, Hash)]
pub struct Arena {
    pub frame: i64,
    pub previous_locations: BTreeMap<i64, WorldPoint>,
    pub pump_acc: i64,
    pub seed: Seed,
    pub space: WorldExtent,
    pub combatants: Sided<Combatant>,
    pub elements: BTreeMap<i64, Element>,
    pub queue: Vec<ElementId>,
    pub next_element_id: i64,
}
