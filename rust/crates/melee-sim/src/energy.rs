//! `src/Melee/Energy.elm`. `status.c` DeltaEnergy and DeltaCrew.

use crate::element::{Element, Life};
use crate::ship_state::CombatantCore;

pub fn delta_energy(
    energy_delta: i64,
    element: &Element,
    core: &CombatantCore,
) -> (bool, Element, CombatantCore) {
    let mut next_core = *core;
    if energy_delta < 0 && -energy_delta > core.energy {
        next_core.flags.low_on_energy = true;
        return (false, *element, next_core);
    }

    let applied = if energy_delta >= 0 {
        (core.energy + energy_delta).min(core.max_energy) - core.energy
    } else {
        energy_delta
    };
    next_core.energy += applied;
    next_core.energy_wait = core.characteristics.energy_wait;
    next_core.flags.low_on_energy = false;
    (true, *element, next_core)
}

pub fn delta_crew(
    crew_delta: i64,
    element: &Element,
    core: &CombatantCore,
) -> (bool, Element, CombatantCore) {
    let mut next = *element;
    if crew_delta > 0 {
        next.points = (element.points + crew_delta).min(core.max_crew);
        (true, next, *core)
    } else if crew_delta < 0 && element.points > -crew_delta {
        next.points += crew_delta;
        (true, next, *core)
    } else if crew_delta < 0 {
        next.points = 0;
        next.life = Life::Finite(0);
        next.flags.nonsolid = true;
        (false, next, *core)
    } else {
        (true, next, *core)
    }
}
