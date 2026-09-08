//! Collision-facing subset of `src/Melee/Art.elm`.
//!
//! The generated tables resolve the exact sprite path and frame selected by
//! Elm's `Art.ship` and `Art.projectile` directly to its collision mask.

use crate::battle::Arena;
use crate::element::{Body, Element};
use crate::masks::Mask;
use crate::masks_generated;
use crate::ship_state::{AndrosynthExtra, Combatant, MmrnmhrmForm};

#[inline]
pub fn projectile(body: Body, frame: i64) -> Option<&'static Mask> {
    masks_generated::projectile_mask(body, frame)
}

#[inline]
pub fn ship(combatant: &Combatant, facing: i64) -> Option<&'static Mask> {
    let alt = matches!(
        combatant,
        Combatant::LiveAndrosynth(_, AndrosynthExtra::Blazer { .. })
            | Combatant::LiveMmrnmhrm(
                _,
                crate::ship_state::MmrnmhrmExtra {
                    form: MmrnmhrmForm::YWing,
                    ..
                }
            )
    );
    masks_generated::ship_mask(combatant.kind(), alt, facing)
}

/// Exact mask selected by Step's `spritePath` followed by `Masks.mask`.
pub fn element(arena: &Arena, element: &Element) -> Option<&'static Mask> {
    match element.body {
        Body::Ship(side) => ship(arena.combatants.get(side), element.next.frame_index),
        body => projectile(body, element.next.frame_index),
    }
}
