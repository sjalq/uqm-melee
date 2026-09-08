//! Literal state-machine port of `src/Melee/Step.elm`.

use alloc::vec;

use alloc::vec::Vec;
use core::cmp::Ordering;

use melee_core::{
    trig,
    units::{Facing, Side, Sided, VelocityDesc, WorldExtent, WorldPoint},
    velocity,
};

use crate::{
    battle::Arena,
    catalog::{
        self, Animation, BeamKind, ContactKind, Guidance, Inheritance, MissileKind, MissileSpec,
        ShipKind, Weapon,
    },
    element::{
        Body, Element, ElementFlags, ElementId, Image, IntersectControl, Life, Owner, Prim,
        ProjectileState, EMPTY_FLAGS, MAX_DISPLAY_ELEMENTS,
    },
    input::{BattleInput, Turn},
    masks::{self, Mask},
    masks_generated,
    ship_state::{
        core, kind, set_core, AndrosynthExtra, Combatant, CombatantCore, MmrnmhrmForm,
        ShofixtiExtra, VuxExtra,
    },
};

#[inline]
fn elm_div(a: i64, b: i64) -> i64 {
    a / b
}

#[inline]
fn elm_round(x: f64) -> i64 {
    floor_f64(x + 0.5) as i64
}

#[inline]
#[cfg(not(target_arch = "nvptx64"))]
fn floor_f64(x: f64) -> f64 {
    x.floor()
}

#[inline]
#[cfg(target_arch = "nvptx64")]
fn floor_f64(x: f64) -> f64 {
    libm::floor(x)
}

#[inline]
#[cfg(not(target_arch = "nvptx64"))]
fn sqrt_f64(x: f64) -> f64 {
    x.sqrt()
}

#[inline]
#[cfg(target_arch = "nvptx64")]
fn sqrt_f64(x: f64) -> f64 {
    libm::sqrt(x)
}

#[inline]
fn ready(wait: i64) -> bool {
    wait <= 0
}

#[inline]
fn dec_wait(wait: i64) -> i64 {
    (wait - 1).max(0)
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
pub fn tick_authoritative(inputs: Sided<BattleInput>, arena: &mut Arena) {
    tick_with_presentation(false, inputs, arena);
}

pub fn tick(inputs: Sided<BattleInput>, arena: &mut Arena) {
    tick_with_presentation(true, inputs, arena);
}

fn tick_with_presentation(capture_previous: bool, inputs: Sided<BattleInput>, arena: &mut Arena) {
    if capture_previous {
        arena.previous_locations = arena
            .elements
            .iter()
            .map(|(&id, el)| (id, el.current.location))
            .collect();
    }
    apply_inputs(inputs, arena);
    prepare_abilities(arena);
    preprocess_all(arena);
    auxiliaries(arena);
    collide_all(arena);
    gravity_all(arena);
    postprocess_all(arena);
    explosions(arena);
    environment(arena);
    arena.frame += 1;
}

pub fn pump_authoritative(inputs: Sided<BattleInput>, arena: &mut Arena) {
    pump_with(false, inputs, arena);
}

pub fn pump(inputs: Sided<BattleInput>, arena: &mut Arena) {
    pump_with(true, inputs, arena);
}

fn pump_with(presentation: bool, inputs: Sided<BattleInput>, arena: &mut Arena) {
    let mut acc = arena.pump_acc + 24;
    let mut frames = 0;
    while acc >= 60 {
        acc -= 60;
        frames += 1;
    }
    arena.pump_acc = acc;
    for _ in 0..frames {
        tick_with_presentation(presentation, inputs, arena);
    }
}

fn apply_inputs(inputs: Sided<BattleInput>, arena: &mut Arena) {
    for side in [Side::Bottom, Side::Top] {
        let c = arena.combatants.get_mut(side).core_mut();
        c.old_input = c.input;
        c.input = *inputs.get(side);
    }
}

#[inline]
fn get_el(arena: &Arena, id: ElementId) -> Option<Element> {
    arena.elements.get(&id.0).copied()
}

#[inline]
fn put_el(arena: &mut Arena, el: Element) {
    arena.elements.insert(el.id.0, el);
}

#[inline]
fn map_combatant(arena: &mut Arena, side: Side, f: impl FnOnce(Combatant) -> Combatant) {
    let value = *arena.combatants.get(side);
    arena.combatants.set(side, f(value));
}

#[inline]
fn combatant_of(arena: &Arena, owner: Owner) -> Option<Combatant> {
    owner.side().map(|side| *arena.combatants.get(side))
}

#[inline]
fn owner_side(owner: Owner) -> Side {
    owner.side().unwrap_or(Side::Bottom)
}

fn preprocess_all(arena: &mut Arena) {
    let ids = arena.queue.clone();
    for id in ids {
        preprocess_one(id, arena);
    }
}

fn preprocess_one(id: ElementId, arena: &mut Arena) {
    let Some(mut el) = get_el(arena, id) else {
        return;
    };
    if el.life.ticks() == 0 {
        el.flags.disappearing = true;
        put_el(arena, el);
        return;
    }
    if el.flags.appearing {
        el.next = el.current;
        el.flags.appearing = false;
    }
    if el.flags.player_ship {
        el = ship_pre(arena, el);
    } else {
        el = steer_with_seed(arena, el);
    }
    apply_velocity(arena, &mut el);
    if el.flags.finite_life {
        el.life = el.life.dec();
    }
    el.flags.pre_process = true;
    el.flags.post_process = false;
    el.flags.collision = false;
    put_el(arena, el);
}

fn apply_velocity(arena: &Arena, el: &mut Element) {
    if el.flags.ignore_velocity || el.flags.disappearing {
        return;
    }
    let ((dx, dy), vel) = velocity::get_next(1, &el.velocity);
    el.velocity = vel;
    if dx != 0 || dy != 0 {
        el.next.location = trig::wrap_point(
            arena.space,
            WorldPoint {
                x: el.next.location.x + dx,
                y: el.next.location.y + dy,
            },
        );
        el.flags.changing = true;
    }
}

fn delta_energy(delta: i64, el: Element, mut c: CombatantCore) -> (bool, Element, CombatantCore) {
    if delta < 0 && -delta > c.energy {
        c.flags.low_on_energy = true;
        (false, el, c)
    } else {
        let applied = if delta >= 0 {
            (c.energy + delta).min(c.max_energy) - c.energy
        } else {
            delta
        };
        c.energy += applied;
        c.energy_wait = c.characteristics.energy_wait;
        c.flags.low_on_energy = false;
        (true, el, c)
    }
}

fn ship_pre(arena: &mut Arena, mut el: Element) -> Element {
    let Some(combatant) = combatant_of(arena, el.owner) else {
        return el;
    };
    let ship_kind = kind(&combatant);
    let mut c = core(&combatant);
    c.shield_ticks = (c.shield_ticks - 1).max(0);
    c.confused_ticks = (c.confused_ticks - 1).max(0);
    let mut input = c.input;
    if c.confused_ticks > 0 {
        input.turn = Turn::TurnRight;
    }
    if ready(c.energy_wait) {
        if c.energy < c.max_energy || c.characteristics.energy_regeneration < 0 {
            (_, _, c) = delta_energy(c.characteristics.energy_regeneration, el, c);
        }
    } else {
        c.energy_wait = dec_wait(c.energy_wait);
    }
    (c, el) = umgah_pre(ship_kind, el, c);

    let turn_input = if input.special && matches!(ship_kind, ShipKind::Supox | ShipKind::Orz) {
        BattleInput {
            turn: Turn::NoTurn,
            ..input
        }
    } else {
        input
    };
    if ready(el.turn_wait) {
        let (facing, wait, frame, changing) = turn_ship(turn_input, c, el);
        c.facing = facing;
        el.turn_wait = wait;
        el.next.frame_index = frame;
        el.flags.changing |= changing;
    } else {
        el.turn_wait = dec_wait(el.turn_wait);
    }
    let thrust_input = if ship_kind == ShipKind::Supox && input.special {
        BattleInput {
            thrust: false,
            ..input
        }
    } else {
        input
    };
    (el, c) = thrust_ship(thrust_input, el, c);
    map_combatant(arena, owner_side(el.owner), |live| set_core(c, live));
    el
}

fn umgah_pre(ship_kind: ShipKind, mut el: Element, c: CombatantCore) -> (CombatantCore, Element) {
    if ship_kind == ShipKind::Umgah && c.input.special && ready(el.thrust_wait) {
        let (paid, _, mut charged) = delta_energy(-c.characteristics.special_energy_cost, el, c);
        if paid {
            charged.special_wait = 2;
            charged.flags.at_max_speed = false;
            charged.flags.beyond_max_speed = false;
            let angle = charged.facing * 4 + 32;
            el.velocity = velocity::delta(
                trig::cosine(angle, 160 * 32),
                trig::sine(angle, 160 * 32),
                &el.velocity,
            );
            (charged, el)
        } else {
            (charged, el)
        }
    } else {
        (c, el)
    }
}

fn turn_ship(input: BattleInput, c: CombatantCore, el: Element) -> (Facing, i64, i64, bool) {
    if !ready(el.turn_wait) || input.turn == Turn::NoTurn {
        return (c.facing, el.turn_wait, el.next.frame_index, false);
    }
    let facing = trig::normalize_facing(match input.turn {
        Turn::TurnLeft => c.facing - 1,
        Turn::TurnRight => c.facing + 1,
        Turn::NoTurn => c.facing,
    });
    (facing, c.characteristics.turn_wait, facing, true)
}

fn thrust_ship(
    input: BattleInput,
    mut el: Element,
    mut c: CombatantCore,
) -> (Element, CombatantCore) {
    if !ready(el.thrust_wait) {
        el.thrust_wait = dec_wait(el.thrust_wait);
    } else if input.thrust {
        let (vel, at_max, beyond) = inertial_thrust(el.velocity, c);
        el.velocity = vel;
        el.thrust_wait = c.characteristics.thrust_wait;
        c.flags.at_max_speed = at_max;
        c.flags.beyond_max_speed = beyond;
        c.flags.in_gravity_well = false;
    }
    (el, c)
}

fn inertial_thrust(v: VelocityDesc, c: CombatantCore) -> (VelocityDesc, bool, bool) {
    let ch = c.characteristics;
    let angle = c.facing * 4;
    let increment = ch.thrust_increment * 32;
    let (cx, cy) = velocity::get_current(&v);
    let dx = cx + trig::cosine(angle, increment);
    let dy = cy + trig::sine(angle, increment);
    let desired = dx * dx + dy * dy;
    let maximum = ch.max_thrust * 32;
    let max_sq = maximum * maximum;
    let current_sq = cx * cx + cy * cy;
    let stationary = cx == 0 && cy == 0;
    let at_limit = !stationary && (c.flags.at_max_speed || c.flags.beyond_max_speed);
    if ch.thrust_increment == ch.max_thrust {
        (velocity::set_vector(ch.max_thrust, c.facing), true, false)
    } else if v.travel_angle == angle && at_limit && !c.flags.in_gravity_well {
        (v, c.flags.at_max_speed, c.flags.beyond_max_speed)
    } else if desired <= max_sq {
        (velocity::set_components(dx, dy), false, false)
    } else if (c.flags.in_gravity_well && desired <= 2304 * 2304) || desired < current_sq {
        (velocity::set_components(dx, dy), true, true)
    } else if v.travel_angle == angle {
        let out = if current_sq <= max_sq {
            velocity::set_vector(ch.max_thrust, c.facing)
        } else {
            v
        };
        (out, true, false)
    } else {
        let turned = velocity::delta(
            trig::cosine(angle, elm_div(increment, 2)) - trig::cosine(v.travel_angle, increment),
            trig::sine(angle, elm_div(increment, 2)) - trig::sine(v.travel_angle, increment),
            &v,
        );
        let (tx, ty) = velocity::get_current(&turned);
        let turned_sq = tx * tx + ty * ty;
        if turned_sq > max_sq {
            (if turned_sq < current_sq { turned } else { v }, true, true)
        } else {
            (turned, false, false)
        }
    }
}

#[derive(Copy, Clone)]
struct CollisionElement {
    element: Element,
    mask: Option<&'static Mask>,
}

fn collision_element(arena: &Arena, id: ElementId) -> Option<CollisionElement> {
    let el = get_el(arena, id)?;
    if el.flags.nonsolid || el.flags.disappearing {
        None
    } else {
        Some(CollisionElement {
            element: el,
            mask: sprite_mask(arena, el),
        })
    }
}

fn collide_all(arena: &mut Arena) {
    // Keep the original ordered snapshots in stable slots. Removing a collision
    // victim marks its slot empty; survivors retain exactly the old pair order.
    // This avoids shifting and rebuilding the remaining vector after every pair.
    let mut elements: Vec<_> = arena
        .queue
        .iter()
        .filter_map(|&id| collision_element(arena, id))
        .map(Some)
        .collect();
    for index in 0..elements.len() {
        let Some(mut first) = elements[index].take() else { continue };
        for slot in &mut elements[index + 1..] {
            let Some(second) = slot.as_ref() else { continue };
            if collision_possible(&first.element, &second.element)
                && sprites_hit(arena, first.element, second.element, first.mask, second.mask)
            {
                bounce(arena, first.element, second.element);
                *slot = collision_element(arena, second.element.id);
                match collision_element(arena, first.element.id) {
                    Some(next_first) => first = next_first,
                    None => break,
                }
            }
        }
    }
}

fn collision_possible(a: &Element, b: &Element) -> bool {
    !(a.flags.nonsolid || a.flags.disappearing)
        && !(b.flags.nonsolid || b.flags.disappearing)
        && !(a.flags.collision && b.flags.collision)
        && (!(a.flags.ignore_similar && b.flags.ignore_similar) || a.parent != b.parent)
        && (a.mass != 0 || b.mass != 0)
        && !(ship_ignoring_body(a.body) && b.flags.player_ship)
        && !(ship_ignoring_body(b.body) && a.flags.player_ship)
}

fn ship_ignoring_body(body: Body) -> bool {
    matches!(
        body,
        Body::OrzMarine | Body::UrQuanFighter | Body::ChenjesuDogi
    )
}

fn radius_display(el: Element) -> i64 {
    match el.body {
        Body::Planet => 40,
        Body::Asteroid => 6,
        Body::Ship(_) => 10 + el.mass.min(10),
        Body::ShofixtiDart => 3,
        Body::ShofixtiGlory => 20,
        Body::MyconPlasma => 12,
        Body::KohrAhSaw => 7,
        Body::MelnormeCharge => 8,
        _ => 4,
    }
}

fn sprite_mask(arena: &Arena, el: Element) -> Option<&'static Mask> {
    match el.body {
        Body::Ship(side) => {
            let live = arena.combatants.get(side);
            let alt = matches!(
                live,
                Combatant::LiveAndrosynth(_, AndrosynthExtra::Blazer { .. })
            ) || matches!(live, Combatant::LiveMmrnmhrm(_, extra) if extra.form == MmrnmhrmForm::YWing);
            masks_generated::ship_mask(kind(live), alt, el.next.frame_index)
        }
        _ => masks_generated::projectile_mask(el.body, el.next.frame_index),
    }
}

fn sprites_hit(
    arena: &Arena,
    a: Element,
    b: Element,
    am: Option<&Mask>,
    bm: Option<&Mask>,
) -> bool {
    let dx = trig::wrap_delta(
        b.current.location.x - a.current.location.x,
        arena.space.width,
    );
    let dy = trig::wrap_delta(
        b.current.location.y - a.current.location.y,
        arena.space.height,
    );
    let vx = trig::wrap_delta(b.next.location.x - b.current.location.x, arena.space.width)
        - trig::wrap_delta(a.next.location.x - a.current.location.x, arena.space.width);
    let vy = trig::wrap_delta(b.next.location.y - b.current.location.y, arena.space.height)
        - trig::wrap_delta(a.next.location.y - a.current.location.y, arena.space.height);
    let largest = masks_generated::MAXIMUM_DIMENSION * 8;
    if dx.abs() > largest + vx.abs() || dy.abs() > largest + vy.abs() {
        return false;
    }
    match (am, bm) {
        (Some(ma), Some(mb)) => {
            let extent = (ma.width.max(ma.height) + mb.width.max(mb.height)) * 4;
            let steps = elm_div(vx.abs().max(vy.abs()) + 3, 4).max(1);
            dx.abs() <= extent + vx.abs()
                && dy.abs() <= extent + vy.abs()
                && (0..=steps).any(|i| {
                    masks::overlap(
                        ma,
                        mb,
                        elm_div(dx + elm_div(vx * i, steps), 4),
                        elm_div(dy + elm_div(vy * i, steps), 4),
                    )
                })
        }
        _ => circles_hit(arena.space, a, b),
    }
}

fn circles_hit(space: WorldExtent, a: Element, b: Element) -> bool {
    let dx = trig::wrap_delta(a.current.location.x - b.current.location.x, space.width) as f64;
    let dy = trig::wrap_delta(a.current.location.y - b.current.location.y, space.height) as f64;
    let vx = (trig::wrap_delta(a.next.location.x - a.current.location.x, space.width)
        - trig::wrap_delta(b.next.location.x - b.current.location.x, space.width))
        as f64;
    let vy = (trig::wrap_delta(a.next.location.y - a.current.location.y, space.height)
        - trig::wrap_delta(b.next.location.y - b.current.location.y, space.height))
        as f64;
    let denom = vx * vx + vy * vy;
    let time = if denom == 0.0 {
        0.0
    } else {
        (-(dx * vx + dy * vy) / denom).clamp(0.0, 1.0)
    };
    let x = dx + time * vx;
    let y = dy + time * vy;
    let radius = ((radius_display(a) + radius_display(b)) * 4) as f64;
    x * x + y * y <= radius * radius
}

fn is_weapon(el: Element) -> bool {
    el.body.is_projectile()
}

fn bounce(arena: &mut Arena, a: Element, b: Element) {
    if is_weapon(a) {
        if !(a.owner == b.owner && a.owner != Owner::Neutral && a.flags.ignore_similar) {
            apply_hit(arena, a, b);
        }
    } else if is_weapon(b) {
        if !(a.owner == b.owner && a.owner != Owner::Neutral && b.flags.ignore_similar) {
            apply_hit(arena, b, a);
        }
    } else if matches!(a.body, Body::Asteroid | Body::Planet)
        || matches!(b.body, Body::Asteroid | Body::Planet)
    {
        bounce_ship(arena, a, b);
        bounce_ship(arena, b, a);
    } else if a.flags.player_ship && b.flags.player_ship {
        let (x0, y0) = velocity::get_current(&a.velocity);
        let (x1, y1) = velocity::get_current(&b.velocity);
        let m0 = a.mass.max(1);
        let m1 = b.mass.max(1);
        let denom = m0 + m1;
        let exchange = |av, bv| elm_div((m0 - m1) * av + 2 * m1 * bv, denom);
        let angle = bearing(arena, b.next.location, a.next.location) * 4;
        let mut a2 = a;
        a2.velocity = velocity::set_components(exchange(x0, x1), exchange(y0, y1));
        a2.next.location = trig::wrap_point(
            arena.space,
            WorldPoint {
                x: a2.next.location.x + trig::cosine(angle, 20),
                y: a2.next.location.y + trig::sine(angle, 20),
            },
        );
        let mut b2 = b;
        b2.velocity = velocity::set_components(
            elm_div((m1 - m0) * x1 + 2 * m0 * x0, denom),
            elm_div((m1 - m0) * y1 + 2 * m0 * y0, denom),
        );
        b2.next.location = trig::wrap_point(
            arena.space,
            WorldPoint {
                x: b2.next.location.x + trig::cosine(angle, -20),
                y: b2.next.location.y + trig::sine(angle, -20),
            },
        );
        put_el(arena, a2);
        put_el(arena, b2);
    } else {
        collect_crew(arena, b, a);
        collect_crew(arena, a, b);
    }
}

fn bounce_ship(arena: &mut Arena, ship: Element, other: Element) {
    if !ship.flags.player_ship {
        return;
    }
    let dx = trig::wrap_delta(
        ship.next.location.x - other.next.location.x,
        arena.space.width,
    );
    let dy = trig::wrap_delta(
        ship.next.location.y - other.next.location.y,
        arena.space.height,
    );
    let angle = trig::arctan(dx, dy);
    if other.body == Body::Planet {
        damage_ship(arena, 1, ship);
    }
    // Elm's pipeline refreshes and updates this id after applying damage.
    if let Some(mut moved) = get_el(arena, ship.id) {
        moved.velocity =
            velocity::set_components(trig::cosine(angle, 1800), trig::sine(angle, 1800));
        moved.next.location = trig::wrap_point(
            arena.space,
            WorldPoint {
                x: ship.next.location.x + trig::cosine(angle, 60),
                y: ship.next.location.y + trig::sine(angle, 60),
            },
        );
        put_el(arena, moved);
    }
}

fn apply_hit(arena: &mut Arena, weapon: Element, target: Element) {
    if target.flags.player_ship {
        if let Some(combatant) = combatant_of(arena, target.owner) {
            let c = core(&combatant);
            if c.shield_ticks > 0 {
                if kind(&combatant) == ShipKind::Utwig {
                    map_combatant(arena, owner_side(target.owner), |live| {
                        let mut co = core(&live);
                        co.energy = (co.energy + weapon.mass).min(co.max_energy);
                        set_core(co, live)
                    });
                }
            } else if weapon.body == Body::VuxLimpet {
                map_combatant(arena, owner_side(target.owner), |live| {
                    let mut co = core(&live);
                    co.characteristics.max_thrust = (co.characteristics.max_thrust * 7 / 8).max(4);
                    co.characteristics.thrust_increment =
                        (co.characteristics.thrust_increment * 7 / 8).max(1);
                    co.characteristics.turn_wait += 1;
                    set_core(co, live)
                });
            } else if weapon.body == Body::MelnormeConfusion {
                map_combatant(arena, owner_side(target.owner), |live| {
                    let mut co = core(&live);
                    co.confused_ticks = 120;
                    set_core(co, live)
                });
            } else if weapon.body == Body::ChenjesuDogi {
                map_combatant(arena, owner_side(target.owner), |live| {
                    let mut co = core(&live);
                    co.energy = (co.energy - 10).max(0);
                    set_core(co, live)
                });
            } else {
                damage_ship(arena, weapon.mass, target);
            }
        }
    } else if target.body != Body::Planet {
        if target.points > weapon.mass {
            let mut t = target;
            t.points -= weapon.mass;
            put_el(arena, t);
        } else {
            remove_el(arena, target.id);
        }
    }

    let hit_snapshot = arena.clone();
    impact(arena, weapon, target);
    let survives =
        !target.flags.player_ship && target.body != Body::Planet && weapon.points > target.mass;
    if survives {
        *arena = hit_snapshot;
        if let Some(mut w) = get_el(arena, weapon.id) {
            w.points -= target.mass;
            put_el(arena, w);
        }
    } else {
        remove_el(arena, weapon.id);
    }
}

fn impact(arena: &mut Arena, weapon: Element, target: Element) {
    let (vx, vy) = velocity::get_current(&weapon.velocity);
    let angle = trig::arctan(vx, vy);
    let facing = trig::angle_to_facing(angle + 32);
    let frame = elm_div(facing, 4) * 2 + i64::from(facing.rem_euclid(4) != 0);
    let offset = match weapon.projectile {
        Some(ProjectileState::Flying { kind, .. }) => kind.spec().blast_offset * 4,
        _ => 4,
    };
    let at = trig::wrap_point(
        arena.space,
        WorldPoint {
            x: weapon.next.location.x + trig::cosine(angle, offset),
            y: weapon.next.location.y + trig::sine(angle, offset),
        },
    );
    match weapon.projectile {
        Some(ProjectileState::Flying { kind: missile, .. }) => {
            let burst = match missile {
                MissileKind::Nuke => Some((16, 9)),
                MissileKind::Cannon | MissileKind::Fusion => Some((16, 8)),
                MissileKind::Crystal | MissileKind::Shard => Some((2, 9)),
                MissileKind::Charge => Some((20, 6)),
                MissileKind::Plasma => Some((11, ((weapon.mass * 8 + 9) / 10).max(1) * 2 - 1)),
                _ => None,
            };
            if let Some((first, count)) = burst {
                let id = ElementId(arena.next_element_id);
                effect(
                    arena,
                    Body::WeaponImpact(missile),
                    target.next.location,
                    count,
                );
                if let Some(mut e) = get_el(arena, id) {
                    e.current = Image {
                        location: target.next.location,
                        frame_index: first,
                    };
                    e.next = e.current;
                    e.thrust_wait = first;
                    put_el(arena, e);
                }
                return;
            }
        }
        _ => {}
    }
    let id = ElementId(arena.next_element_id);
    effect(arena, Body::Blast, at, 2);
    if let Some(mut e) = get_el(arena, id) {
        e.current = Image {
            location: at,
            frame_index: frame,
        };
        e.next = e.current;
        put_el(arena, e);
    }
}

fn damage_ship(arena: &mut Arena, amount: i64, target: Element) {
    let Some(combatant) = combatant_of(arena, target.owner) else {
        return;
    };
    let c = core(&combatant);
    if c.shield_ticks > 0 {
        return;
    }
    if target.points > amount {
        let mut damaged = target;
        damaged.points -= amount;
        put_el(arena, damaged);
        return;
    }
    let (roll, seed) = arena.seed.next();
    arena.seed = seed;
    if kind(&combatant) == ShipKind::Pkunk && roll.rem_euclid(2) == 0 {
        let mut resurrected = target;
        resurrected.points = c.max_crew;
        put_el(arena, resurrected);
        map_combatant(arena, owner_side(target.owner), |live| {
            let mut next = core(&live);
            next.energy = c.max_energy;
            next.shield_ticks = 36;
            set_core(next, live)
        });
        effect(arena, Body::WarpIn, target.next.location, 24);
    } else {
        start_explosion(arena, target);
    }
}

fn start_explosion(arena: &mut Arena, mut ship: Element) {
    ship.body = Body::Wreck(owner_side(ship.owner));
    ship.points = 0;
    ship.life = Life::Finite(36);
    ship.color_cycle_index = 36;
    ship.flags = ElementFlags {
        finite_life: true,
        nonsolid: true,
        ..EMPTY_FLAGS
    };
    ship.velocity = velocity::ZERO;
    ship.projectile = None;
    put_el(arena, ship);
}

fn explosions(arena: &mut Arena) {
    let wrecks: Vec<_> = arena
        .elements
        .values()
        .copied()
        .filter(|e| matches!(e.body, Body::Wreck(_)))
        .collect();
    for wreck in wrecks {
        let age = 36 - wreck.life.ticks();
        let count = if age > 25 {
            0
        } else if age <= 2 || age >= 20 {
            1
        } else if age <= 5 || age >= 18 {
            2
        } else {
            3
        };
        for _ in 1..=count {
            let (r1, s1) = arena.seed.next();
            let (r2, s2) = s1.next();
            arena.seed = s2;
            let angle = elm_div(r1, 65536).rem_euclid(64);
            let radius = (r1.rem_euclid(8)
                + if elm_div(r1, 256).rem_euclid(256) < 85 {
                    8
                } else {
                    0
                })
                * 4;
            let at = trig::wrap_point(
                arena.space,
                WorldPoint {
                    x: wreck.current.location.x + trig::cosine(angle, radius),
                    y: wreck.current.location.y + trig::sine(angle, radius),
                },
            );
            let id = ElementId(arena.next_element_id);
            effect(arena, Body::Explosion, at, 9);
            let speed = elm_div(r2, 256).rem_euclid(5) * 4 * 32;
            if let Some(mut spark) = get_el(arena, id) {
                spark.velocity =
                    velocity::set_components(trig::cosine(r2, speed), trig::sine(r2, speed));
                put_el(arena, spark);
            }
        }
    }
}

fn gravity_all(arena: &mut Arena) {
    let planet = arena
        .queue
        .iter()
        .find_map(|&id| get_el(arena, id).filter(|e| e.body == Body::Planet));
    if let Some(planet) = planet {
        for id in arena.queue.clone() {
            pull_toward(arena, planet, id);
        }
    }
}

fn pull_toward(arena: &mut Arena, planet: Element, id: ElementId) {
    let Some(mut el) = get_el(arena, id) else {
        return;
    };
    if el.id == planet.id || el.mass > 100 || el.flags.defy_physics {
        return;
    }
    let dx = trig::wrap_delta(
        planet.next.location.x - el.next.location.x,
        arena.space.width,
    );
    let dy = trig::wrap_delta(
        planet.next.location.y - el.next.location.y,
        arena.space.height,
    );
    let adx = elm_div(dx.abs(), 4);
    let ady = elm_div(dy.abs(), 4);
    if adx <= 255 && ady <= 255 && adx * adx + ady * ady <= 255 * 255 {
        let angle = trig::arctan(dx, dy);
        el.velocity = velocity::delta(trig::cosine(angle, 32), trig::sine(angle, 32), &el.velocity);
        put_el(arena, el);
        if el.flags.player_ship {
            map_combatant(arena, owner_side(el.owner), |live| {
                let mut c = core(&live);
                c.flags.at_max_speed = false;
                c.flags.in_gravity_well = true;
                set_core(c, live)
            });
        }
    }
}

fn postprocess_all(arena: &mut Arena) {
    for id in arena.queue.clone() {
        postprocess_one(arena, id);
    }
    arena.queue.retain(|id| arena.elements.contains_key(&id.0));
}

fn postprocess_one(arena: &mut Arena, id: ElementId) {
    let Some(mut el) = get_el(arena, id) else {
        return;
    };
    if el.flags.disappearing {
        remove_element(arena, id);
        return;
    }
    if el.flags.player_ship {
        el = ship_post(arena, el);
    }
    if el.flags.disappearing {
        remove_element(arena, id);
    } else {
        el.current = el.next;
        el.flags.pre_process = false;
        el.flags.changing = false;
        el.flags.appearing = false;
        el.flags.post_process = true;
        put_el(arena, el);
    }
}

#[inline]
fn remove_element(arena: &mut Arena, id: ElementId) {
    arena.elements.remove(&id.0);
}

fn remove_el(arena: &mut Arena, id: ElementId) {
    arena.elements.remove(&id.0);
    arena.queue.retain(|&queued| queued != id);
}

fn ship_post(arena: &mut Arena, el: Element) -> Element {
    if el.points == 0 {
        return el;
    }
    let Some(combatant) = combatant_of(arena, el.owner) else {
        return el;
    };
    let c0 = core(&combatant);
    let aimed = match combatant {
        Combatant::LiveOrz(c, mut extra) => {
            let rotate =
                c.input.special && c.input.turn != Turn::NoTurn && ready(extra.turret_wait);
            if rotate {
                extra.turret_facing = (extra.turret_facing
                    + if c.input.turn == Turn::TurnRight {
                        1
                    } else {
                        -1
                    })
                .rem_euclid(16);
                extra.turret_wait = 3;
            } else {
                extra.turret_wait = dec_wait(extra.turret_wait);
            }
            Combatant::LiveOrz(c, extra)
        }
        _ => combatant,
    };
    arena.combatants.set(owner_side(el.owner), aimed);
    let (mut c1, mut el1) = fire_weapon(arena, el, c0, aimed);
    if kind(&combatant) == ShipKind::Umgah && !ready(c1.special_wait) {
        c1.special_wait = 0;
        el1.velocity = velocity::ZERO;
    }
    map_combatant(arena, owner_side(el.owner), |live| set_core(c1, live));
    el1
}

fn fire_weapon(
    arena: &mut Arena,
    el: Element,
    original: CombatantCore,
    combatant: Combatant,
) -> (CombatantCore, Element) {
    let mut c = original;
    c.weapon_wait = dec_wait(c.weapon_wait);
    c.special_wait = dec_wait(c.special_wait);
    let ship_kind = kind(&combatant);
    let charging = arena.elements.values().any(|e| {
        e.owner == el.owner && matches!(e.projectile, Some(ProjectileState::Charging { .. }))
    });
    let wants_fire = c.input.weapon
        && !(ship_kind == ShipKind::Orz && c.input.special)
        && (ship_kind != ShipKind::Melnorme || !charging);
    let chenjesu_photon = arena
        .elements
        .values()
        .any(|e| e.owner == el.owner && e.body == Body::ChenjesuPhoton);
    let blazer = matches!(
        combatant,
        Combatant::LiveAndrosynth(_, AndrosynthExtra::Blazer { .. })
    );
    let can_fire = ready(original.weapon_wait)
        && (ship_kind != ShipKind::Chenjesu || !chenjesu_photon)
        && wants_fire
        && c.energy >= c.characteristics.weapon_energy_cost
        && !blazer;
    let mut e1 = el;
    if can_fire {
        c.energy -= c.characteristics.weapon_energy_cost;
        c.weapon_wait = c.characteristics.weapon_wait;
        c.charge_ticks = 0;
        c.cloaked = false;
        let mut firing = c;
        if let Combatant::LiveOrz(_, extra) = combatant {
            firing.facing = (firing.facing + extra.turret_facing).rem_euclid(16);
        }
        fire(arena, catalog_primary(combatant), el, firing);
        if ship_kind == ShipKind::Druuge {
            let angle = c.facing * 4;
            e1.velocity = velocity::delta(
                trig::cosine(angle, -1800),
                trig::sine(angle, -1800),
                &e1.velocity,
            );
        }
    }
    if ship_kind == ShipKind::Slylandro && !ready(original.weapon_wait) {
        fire_lightning(arena, el, c);
    }
    if ship_kind == ShipKind::Shofixti && c.input.special != c.old_input.special {
        return special(arena, combatant, e1, c);
    }
    if c.input.special
        && !matches!(ship_kind, ShipKind::Shofixti | ShipKind::Umgah)
        && ready(original.special_wait)
        && (c.energy >= c.characteristics.special_energy_cost
            || matches!(
                ship_kind,
                ShipKind::Druuge | ShipKind::Pkunk | ShipKind::Supox
            ))
    {
        return special(arena, combatant, e1, c);
    }
    (c, e1)
}

fn catalog_primary(combatant: Combatant) -> Weapon {
    match combatant {
        Combatant::LiveMmrnmhrm(_, extra) if extra.form == MmrnmhrmForm::YWing => {
            Weapon::Missile(MissileKind::Torpedo)
        }
        _ => catalog::standard_weapon(kind(&combatant)),
    }
}

fn spawn_dart(arena: &mut Arena, ship: Element, c: CombatantCore) -> ElementId {
    let id = ElementId(arena.next_element_id);
    let facing = c.facing;
    let angle = facing * 4;
    let loc0 = WorldPoint {
        x: ship.next.location.x + trig::cosine(angle, 15 * 4),
        y: ship.next.location.y + trig::sine(angle, 15 * 4),
    };
    let dx = trig::cosine(angle, 24 * 4 * 32);
    let dy = trig::sine(angle, 24 * 4 * 32);
    let vel = velocity::set_components(dx, dy);
    let loc = WorldPoint {
        x: loc0.x - elm_div(dx, 32),
        y: loc0.y - elm_div(dy, 32),
    };
    let image = Image {
        location: loc,
        frame_index: facing,
    };
    let dart = Element {
        id,
        owner: ship.owner,
        parent: ship.parent,
        target: None,
        flags: ElementFlags {
            appearing: true,
            finite_life: true,
            ignore_similar: true,
            ..EMPTY_FLAGS
        },
        life: Life::Finite(10),
        points: 1,
        mass: 1,
        turn_wait: 0,
        thrust_wait: 0,
        color_cycle_index: 0,
        velocity: vel,
        intersect: IntersectControl {
            last_time_val: 0,
            end_point: loc,
            stamp_origin: loc,
        },
        current: image,
        next: image,
        projectile: None,
        prim: Prim::Stamp,
        body: Body::ShofixtiDart,
    };
    arena.elements.insert(id.0, dart);
    arena.queue.push(id);
    arena.next_element_id += 1;
    id
}

fn glory(arena: &mut Arena, el: Element, mut c: CombatantCore) -> (CombatantCore, Element) {
    for id in arena.queue.clone() {
        glory_one(arena, el.id, el.next.location, 180, id);
    }
    let mut dead = el;
    dead.points = 0;
    dead.life = Life::Finite(0);
    dead.flags.nonsolid = true;
    dead.flags.disappearing = true;
    c.special_wait = c.characteristics.special_wait;
    start_explosion(arena, dead);
    (c, dead)
}

fn glory_one(arena: &mut Arena, self_id: ElementId, origin: WorldPoint, range: i64, id: ElementId) {
    let Some(obj) = get_el(arena, id) else { return };
    if obj.id == self_id || obj.flags.nonsolid || obj.mass > 100 {
        return;
    }
    let dx = elm_div(
        trig::wrap_delta(obj.next.location.x - origin.x, arena.space.width).abs(),
        4,
    );
    let dy = elm_div(
        trig::wrap_delta(obj.next.location.y - origin.y, arena.space.height).abs(),
        4,
    );
    let sq = dx * dx + dy * dy;
    if dx <= range && dy <= range && sq <= range * range {
        let destruction = 1 + elm_div(18 * (range - trig::square_root(sq)), range);
        if obj.flags.player_ship {
            damage_ship(arena, destruction, obj);
        } else if is_weapon(obj) {
            remove_el(arena, obj.id);
        }
    }
}

fn fire(arena: &mut Arena, weapon: Weapon, el: Element, c: CombatantCore) {
    if arena.elements.len() >= MAX_DISPLAY_ELEMENTS {
        return;
    }
    match weapon {
        Weapon::Beam(beam) => fire_beam(arena, beam, el, c),
        Weapon::Lightning => fire_lightning(arena, el, c),
        Weapon::Contact(contact) => fire_contact(arena, contact, el, c),
        Weapon::Missile(kind) => {
            let spec = *kind.spec();
            for mount in spec.mounts() {
                let direction = (c.facing + mount.facing_offset).rem_euclid(16);
                let angle = if spec.direction_count > 1 {
                    c.facing + mount.facing_offset
                } else {
                    c.facing
                } * 4;
                let at = trig::wrap_point(
                    arena.space,
                    WorldPoint {
                        x: el.next.location.x
                            + trig::cosine(angle, mount.forward * 4)
                            + trig::cosine(angle + 16, mount.sideways * 4),
                        y: el.next.location.y
                            + trig::sine(angle, mount.forward * 4)
                            + trig::sine(angle + 16, mount.sideways * 4),
                    },
                );
                spawn_missile(
                    arena,
                    spec,
                    el,
                    CombatantCore {
                        facing: direction,
                        ..c
                    },
                    at,
                );
            }
            limit_saws(arena, kind, el.owner);
        }
    }
}

fn limit_saws(arena: &mut Arena, missile: MissileKind, owner: Owner) {
    if missile != MissileKind::Saw {
        return;
    }
    let existing: Vec<_> = arena
        .elements
        .values()
        .filter(|e| e.owner == owner && e.body == Body::KohrAhSaw)
        .map(|e| e.id)
        .collect();
    let expire = existing.len().saturating_sub(8);
    for id in existing.into_iter().take(expire) {
        remove_el(arena, id);
    }
}

fn spawn_missile(
    arena: &mut Arena,
    spec: MissileSpec,
    ship: Element,
    c: CombatantCore,
    at: WorldPoint,
) -> ElementId {
    let id = spawn_dart(arena, ship, c);
    let (parent_dx, parent_dy) = match spec.inheritance {
        Inheritance::InheritVelocity => velocity::get_current(&ship.velocity),
        Inheritance::Independent => (0, 0),
    };
    let position = WorldPoint {
        // Arsenal.launchState uses `floor (toFloat v / 32)`, not Elm `(//)`.
        x: at.x - parent_dx.div_euclid(32),
        y: at.y - parent_dy.div_euclid(32),
    };
    let launch_velocity = velocity::set_components(
        trig::cosine(c.facing * 4, spec.speed * 32) + parent_dx,
        trig::sine(c.facing * 4, spec.speed * 32) + parent_dy,
    );
    let tracking_wait = match spec.guidance {
        Guidance::Tracking { initial_wait, .. } => initial_wait,
        _ => 0,
    };
    let charging = spec.kind == MissileKind::Charge && c.input.weapon;
    if let Some(mut el) = get_el(arena, id) {
        el.body = missile_body(spec.kind);
        el.projectile = Some(if charging {
            ProjectileState::Charging {
                ticks: 0,
                facing: c.facing,
            }
        } else {
            ProjectileState::Flying {
                kind: spec.kind,
                age: 0,
                facing: c.facing,
                tracking_wait,
            }
        });
        el.current = Image {
            location: trig::wrap_point(arena.space, position),
            frame_index: animation_frame(spec.animation, c.facing, 0, spec.damage),
        };
        el.next = el.current;
        el.mass = spec.damage;
        el.points = spec.hit_points;
        el.life = Life::Finite(if charging { 2 } else { spec.life });
        el.velocity = if charging {
            velocity::ZERO
        } else {
            launch_velocity
        };
        el.flags = ElementFlags {
            appearing: true,
            finite_life: true,
            ignore_similar: !spec.friendly_fire,
            ..EMPTY_FLAGS
        };
        put_el(arena, el);
    }
    id
}

fn missile_body(kind: MissileKind) -> Body {
    crate::catalog_generated::MISSILE_BODY[kind.index()]
}

fn animation_frame(animation: Animation, facing: i64, age: i64, damage: i64) -> i64 {
    match animation {
        Animation::Directional => facing,
        Animation::Frames { count, ticks } => elm_div(age, ticks).rem_euclid(count),
        Animation::PlasmaDecay => elm_div(age, 13).min(10),
        Animation::ChargeLevel => {
            let level = if damage >= 16 {
                3
            } else if damage >= 8 {
                2
            } else if damage >= 4 {
                1
            } else {
                0
            };
            let phase = age.rem_euclid(8);
            level * 5 + if phase <= 4 { phase } else { 8 - phase }
        }
    }
}

fn beam_geometry(beam: BeamKind, facing: i64, center: WorldPoint) -> Vec<(WorldPoint, WorldPoint)> {
    let offset = |forward: i64, sideways: i64| WorldPoint {
        x: center.x + trig::cosine(facing * 4, forward) + trig::cosine(facing * 4 + 16, sideways),
        y: center.y + trig::sine(facing * 4, forward) + trig::sine(facing * 4 + 16, sideways),
    };
    match beam {
        BeamKind::AutoAim => vec![(offset(36, 0), offset(436, 0))],
        BeamKind::Megawatt => {
            const CORNERS: [(i64, i64); 16] = [
                (0, -22),
                (11, -20),
                (16, -17),
                (21, -10),
                (22, 0),
                (22, 10),
                (17, 16),
                (11, 20),
                (0, 22),
                (-11, 20),
                (-17, 16),
                (-22, 10),
                (-23, 0),
                (-22, -10),
                (-17, -16),
                (-11, -20),
            ];
            let (x, y) = CORNERS.get(facing as usize).copied().unwrap_or((0, -22));
            let origin = WorldPoint {
                x: center.x + x * 4,
                y: center.y + y * 4,
            };
            vec![(
                origin,
                WorldPoint {
                    x: origin.x + trig::cosine(facing * 4, 600),
                    y: origin.y + trig::sine(facing * 4, 600),
                },
            )]
        }
        BeamKind::Twin => vec![
            (offset(16, 40), offset(580, 0)),
            (offset(16, -40), offset(580, 0)),
        ],
        BeamKind::Green => vec![(offset(48, 0), offset(648, 0))],
        BeamKind::PointDefense => vec![(offset(0, 0), offset(400, 0))],
        BeamKind::Zap => vec![(offset(0, 0), offset(200, 0))],
        BeamKind::FighterBeam => vec![(offset(16, 0), offset(176, 0))],
    }
}

fn fire_beam(arena: &mut Arena, beam: BeamKind, el: Element, c: CombatantCore) {
    let direction = if matches!(
        beam,
        BeamKind::AutoAim | BeamKind::PointDefense | BeamKind::Zap | BeamKind::FighterBeam
    ) {
        enemy(arena, el.owner)
            .map(|other| bearing(arena, el.next.location, other.next.location))
            .unwrap_or(c.facing)
    } else {
        c.facing
    };
    for (origin, end) in beam_geometry(beam, direction, el.next.location) {
        cast_ray(arena, Some(beam), origin, end, el, c);
    }
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
fn cast_ray(
    arena: &mut Arena,
    beam: Option<BeamKind>,
    origin: WorldPoint,
    end: WorldPoint,
    source: Element,
    c: CombatantCore,
) {
    let damage = if beam == Some(BeamKind::Megawatt) {
        2
    } else {
        1
    };
    let mut candidates: Vec<(f64, Element)> = arena
        .elements
        .values()
        .copied()
        .filter(|other| {
            other.id != source.id
                && !other.flags.nonsolid
                && !other.flags.disappearing
                && other.owner != source.owner
        })
        .filter_map(|other| ray_intersection(arena, origin, end, other).map(|t| (t, other)))
        .collect();
    candidates.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(Ordering::Equal));
    let first = candidates.first().copied();
    let stop = first
        .map(|(t, _)| WorldPoint {
            x: origin.x + elm_round((end.x - origin.x) as f64 * t),
            y: origin.y + elm_round((end.y - origin.y) as f64 * t),
        })
        .unwrap_or(end);
    if let Some((_, other)) = first {
        if other.flags.player_ship {
            if let Some(ship) = combatant_of(arena, other.owner) {
                let co = core(&ship);
                if co.shield_ticks > 0 {
                    if kind(&ship) == ShipKind::Utwig {
                        map_combatant(arena, owner_side(other.owner), |live| {
                            let mut x = core(&live);
                            x.energy = (x.energy + damage).min(x.max_energy);
                            set_core(x, live)
                        });
                    }
                } else {
                    damage_ship(arena, damage, other);
                }
            }
        } else if other.body != Body::Planet {
            if other.points > damage {
                let mut hit = other;
                hit.points -= damage;
                put_el(arena, hit);
            } else {
                remove_el(arena, other.id);
            }
        }
    }
    let id = spawn_dart(arena, source, c);
    let start = trig::wrap_point(arena.space, origin);
    let finish = trig::wrap_point(arena.space, stop);
    if let Some(mut visual) = get_el(arena, id) {
        visual.body = beam.map(beam_body).unwrap_or(Body::SlylandroLightning);
        visual.projectile = Some(match beam {
            Some(which) => ProjectileState::Ray {
                beam: which,
                origin: start,
                end: finish,
            },
            None => ProjectileState::LightningSegment {
                origin: start,
                end: finish,
            },
        });
        visual.prim = Prim::Line;
        visual.life = Life::Finite(0);
        visual.mass = damage;
        visual.current = Image {
            location: start,
            frame_index: 0,
        };
        visual.next = visual.current;
        visual.velocity = velocity::ZERO;
        visual.flags = ElementFlags {
            finite_life: true,
            nonsolid: true,
            ..EMPTY_FLAGS
        };
        visual.intersect = IntersectControl {
            last_time_val: 0,
            stamp_origin: start,
            end_point: finish,
        };
        put_el(arena, visual);
    }
}

fn beam_body(beam: BeamKind) -> Body {
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

fn ray_intersection(
    arena: &Arena,
    origin: WorldPoint,
    end: WorldPoint,
    target: Element,
) -> Option<f64> {
    if let Some(mask) = sprite_mask(arena, target) {
        let dx = end.x - origin.x;
        let dy = end.y - origin.y;
        let tx = trig::wrap_delta(target.next.location.x - origin.x, arena.space.width);
        let ty = trig::wrap_delta(target.next.location.y - origin.y, arena.space.height);
        let steps = elm_div(dx.abs().max(dy.abs()) + 3, 4).max(1);
        for i in 0..=steps {
            if mask.opaque(
                elm_div(elm_div(dx * i, steps) - tx, 4),
                elm_div(elm_div(dy * i, steps) - ty, 4),
            ) {
                return Some(i as f64 / steps as f64);
            }
        }
        None
    } else {
        ray_circle(arena.space, origin, end, target)
    }
}

fn ray_circle(
    space: WorldExtent,
    origin: WorldPoint,
    end: WorldPoint,
    target: Element,
) -> Option<f64> {
    let dx = (end.x - origin.x) as f64;
    let dy = (end.y - origin.y) as f64;
    let tx = trig::wrap_delta(target.next.location.x - origin.x, space.width) as f64;
    let ty = trig::wrap_delta(target.next.location.y - origin.y, space.height) as f64;
    let length_sq = dx * dx + dy * dy;
    let projection = (tx * dx + ty * dy) / length_sq.max(1.0);
    let radius = (radius_display(target) * 4) as f64;
    let perpendicular = tx * tx + ty * ty - projection * projection * length_sq;
    let entry =
        projection - sqrt_f64(0.0f64.max(radius * radius - perpendicular) / length_sq.max(1.0));
    if perpendicular <= radius * radius && projection >= 0.0 && entry <= 1.0 {
        Some(entry.max(0.0))
    } else {
        None
    }
}

fn fire_contact(arena: &mut Arena, contact: ContactKind, ship: Element, c: CombatantCore) {
    let id = spawn_dart(arena, ship, c);
    if let Some(mut el) = get_el(arena, id) {
        el.body = if contact == ContactKind::Cone {
            Body::UmgahCone
        } else {
            Body::ZoqTongue
        };
        el.projectile = Some(ProjectileState::Attached {
            contact,
            age: 0,
            facing: c.facing,
        });
        el.current = Image {
            location: ship.next.location,
            frame_index: c.facing,
        };
        el.next = el.current;
        el.velocity = velocity::ZERO;
        el.mass = if contact == ContactKind::Cone { 1 } else { 12 };
        el.points = if contact == ContactKind::Cone { 100 } else { 1 };
        el.life = Life::Finite(if contact == ContactKind::Cone { 1 } else { 7 });
        el.flags = ElementFlags {
            finite_life: true,
            ignore_similar: true,
            defy_physics: true,
            ..EMPTY_FLAGS
        };
        put_el(arena, el);
    }
}

fn fire_lightning(arena: &mut Arena, ship: Element, c: CombatantCore) {
    let direction = enemy(arena, ship.owner)
        .map(|other| bearing(arena, ship.next.location, other.next.location))
        .unwrap_or(c.facing);
    let segments = if c.weapon_wait > 8 {
        17 - c.weapon_wait
    } else {
        c.weapon_wait
    };
    let mut origin = ship.next.location;
    let mut stopped = false;
    for _ in 0..=segments {
        if stopped {
            continue;
        }
        let (random, seed) = arena.seed.next();
        arena.seed = seed;
        let angle = direction * 4 + random.rem_euclid(7) - 3;
        let length = (4 + elm_div(random, 256).rem_euclid(32)) * 4;
        let end = WorldPoint {
            x: origin.x + trig::cosine(angle, length),
            y: origin.y + trig::sine(angle, length),
        };
        let id = ElementId(arena.next_element_id);
        cast_ray(arena, None, origin, end, ship, c);
        stopped = get_el(arena, id)
            .map(|beam| beam.intersect.end_point != trig::wrap_point(arena.space, end))
            .unwrap_or(true);
        origin = end;
    }
}

fn enemy(arena: &Arena, owner: Owner) -> Option<Element> {
    let live = if owner == Owner::Owned(Side::Bottom) {
        arena.combatants.top
    } else {
        arena.combatants.bottom
    };
    let c = core(&live);
    if c.cloaked {
        None
    } else {
        get_el(arena, c.element)
    }
}

fn bearing(arena: &Arena, from: WorldPoint, to: WorldPoint) -> i64 {
    elm_div(
        trig::arctan(
            trig::wrap_delta(to.x - from.x, arena.space.width),
            trig::wrap_delta(to.y - from.y, arena.space.height),
        ) + 2,
        4,
    )
    .rem_euclid(16)
}

fn distance(arena: &Arena, from: WorldPoint, to: WorldPoint) -> i64 {
    let dx = trig::wrap_delta(to.x - from.x, arena.space.width);
    let dy = trig::wrap_delta(to.y - from.y, arena.space.height);
    trig::square_root(dx * dx + dy * dy)
}

fn effect(arena: &mut Arena, body: Body, at: WorldPoint, life: i64) -> ElementId {
    let id = ElementId(arena.next_element_id);
    let image = Image {
        location: at,
        frame_index: 0,
    };
    let el = Element {
        id,
        owner: Owner::Neutral,
        parent: None,
        target: None,
        flags: ElementFlags {
            finite_life: true,
            nonsolid: true,
            defy_physics: true,
            appearing: true,
            ..EMPTY_FLAGS
        },
        life: Life::Finite(life),
        points: 0,
        mass: 0,
        turn_wait: 0,
        thrust_wait: 0,
        color_cycle_index: life,
        velocity: velocity::ZERO,
        intersect: IntersectControl {
            last_time_val: 0,
            end_point: at,
            stamp_origin: at,
        },
        current: image,
        next: image,
        projectile: None,
        prim: Prim::Stamp,
        body,
    };
    arena.elements.insert(id.0, el);
    arena.queue.push(id);
    arena.next_element_id += 1;
    id
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
fn special(
    arena: &mut Arena,
    combatant: Combatant,
    el: Element,
    c: CombatantCore,
) -> (CombatantCore, Element) {
    let mut paid = c;
    paid.energy -= c.characteristics.special_energy_cost;
    paid.special_wait = c.characteristics.special_wait;
    let facing = c.facing;
    match combatant {
        Combatant::LiveShofixti(_, safety) => {
            let next = match safety {
                ShofixtiExtra::SafetyClosed => Some(ShofixtiExtra::OpeningSafety),
                ShofixtiExtra::OpeningSafety => Some(ShofixtiExtra::SafetyOpen),
                ShofixtiExtra::SafetyOpen => Some(ShofixtiExtra::ArmingDevice),
                ShofixtiExtra::ArmingDevice => Some(ShofixtiExtra::Armed),
                ShofixtiExtra::Armed => None,
                ShofixtiExtra::GloryDevice => return (c, el),
            };
            if let Some(next) = next {
                arena
                    .combatants
                    .set(owner_side(el.owner), Combatant::LiveShofixti(c, next));
                (c, el)
            } else {
                glory(arena, el, c)
            }
        }
        Combatant::LiveArilou(..) => {
            let (x, s1) = arena.seed.next();
            let (y, s2) = s1.next();
            arena.seed = s2;
            let at = WorldPoint {
                x: x.rem_euclid(arena.space.width),
                y: y.rem_euclid(arena.space.height),
            };
            let mut moved = el;
            moved.current = Image {
                location: at,
                frame_index: facing,
            };
            moved.next = moved.current;
            moved.velocity = velocity::ZERO;
            paid.shield_ticks = 5;
            effect(arena, Body::WarpIn, at, 10);
            (paid, moved)
        }
        Combatant::LiveAndrosynth(_, form) => match form {
            AndrosynthExtra::Guardian => {
                let guardian = c.characteristics;
                paid.characteristics.max_thrust = 60;
                paid.characteristics.thrust_increment = 60;
                paid.characteristics.turn_wait = 1;
                paid.special_wait = 1;
                arena.combatants.set(
                    owner_side(el.owner),
                    Combatant::LiveAndrosynth(paid, AndrosynthExtra::Blazer { guardian }),
                );
                (paid, el)
            }
            AndrosynthExtra::Blazer { .. } => (c, el),
        },
        Combatant::LiveChenjesu(..) => {
            if count_owned(arena, Body::ChenjesuDogi, el.owner) >= 4 {
                (c, el)
            } else {
                fire(arena, Weapon::Missile(MissileKind::Dogi), el, paid);
                (paid, el)
            }
        }
        Combatant::LiveChmmr(..) => {
            if let Some(mut other) = enemy(arena, el.owner) {
                let angle = bearing(arena, other.next.location, el.next.location) * 4;
                other.velocity = velocity::delta(
                    trig::cosine(angle, 240),
                    trig::sine(angle, 240),
                    &other.velocity,
                );
                put_el(arena, other);
            }
            effect(arena, Body::IonTrail, el.next.location, 3);
            (paid, el)
        }
        Combatant::LiveDruuge(..) => {
            if el.points > 1 && c.energy < c.max_energy {
                paid.energy = (c.energy + 16).min(c.max_energy);
                paid.special_wait = 8;
                let mut e = el;
                e.points -= 1;
                (paid, e)
            } else {
                (c, el)
            }
        }
        Combatant::LiveEarthling(..) => {
            let targets: Vec<_> = arena
                .elements
                .values()
                .copied()
                .filter(|other| {
                    other.id != el.id
                        && !other.flags.nonsolid
                        && !other.flags.disappearing
                        && distance(arena, el.next.location, other.next.location) < 400
                        && combatant_of(arena, other.owner)
                            .map(|live| !core(&live).cloaked)
                            .unwrap_or(true)
                })
                .collect();
            if targets.is_empty() {
                return (c, el);
            }
            for other in targets {
                let origin = el.next.location;
                let end = WorldPoint {
                    x: origin.x
                        + trig::wrap_delta(other.next.location.x - origin.x, arena.space.width),
                    y: origin.y
                        + trig::wrap_delta(other.next.location.y - origin.y, arena.space.height),
                };
                cast_ray(arena, Some(BeamKind::PointDefense), origin, end, el, paid);
            }
            (paid, el)
        }
        Combatant::LiveIlwrath(..) => {
            if c.old_input.special {
                (c, el)
            } else {
                paid.cloaked = !c.cloaked;
                (paid, el)
            }
        }
        Combatant::LiveKohrAh(..) => {
            let mut spec = *MissileKind::Fried.spec();
            spec.damage = 3;
            spec.speed = 70;
            spec.life = 16;
            fire_missile_spec(arena, spec, el, paid);
            (paid, el)
        }
        Combatant::LiveMelnorme(..) => {
            fire(arena, Weapon::Missile(MissileKind::Confusion), el, paid);
            (paid, el)
        }
        Combatant::LiveMmrnmhrm(_, extra) => {
            let old = c.characteristics;
            paid.characteristics = extra.other_wing;
            paid.special_wait = 12;
            let form = if extra.form == MmrnmhrmForm::XWing {
                MmrnmhrmForm::YWing
            } else {
                MmrnmhrmForm::XWing
            };
            arena.combatants.set(
                owner_side(el.owner),
                Combatant::LiveMmrnmhrm(
                    paid,
                    crate::ship_state::MmrnmhrmExtra {
                        form,
                        other_wing: old,
                    },
                ),
            );
            let mut stopped = el;
            stopped.velocity = velocity::ZERO;
            (paid, stopped)
        }
        Combatant::LiveMycon(..) => {
            if el.points < c.max_crew {
                let mut healed = el;
                healed.points = (healed.points + 4).min(c.max_crew);
                (paid, healed)
            } else {
                (c, el)
            }
        }
        Combatant::LiveOrz(..) => {
            if c.input.weapon && el.points > 1 && count_owned(arena, Body::OrzMarine, el.owner) < 8
            {
                fire(
                    arena,
                    Weapon::Missile(MissileKind::Marine),
                    el,
                    CombatantCore {
                        facing: (facing + 8).rem_euclid(16),
                        ..paid
                    },
                );
                let mut ship = el;
                ship.points -= 1;
                (paid, ship)
            } else {
                (c, el)
            }
        }
        Combatant::LivePkunk(..) => {
            paid.energy = (c.energy + 2).min(c.max_energy);
            paid.special_wait = 8;
            (paid, el)
        }
        Combatant::LiveSlylandro(..) => {
            let rocks: Vec<_> = arena
                .elements
                .values()
                .copied()
                .filter(|other| {
                    other.body == Body::Asteroid
                        && distance(arena, el.next.location, other.next.location) < 700
                })
                .map(|e| e.id)
                .collect();
            if rocks.is_empty() {
                (c, el)
            } else {
                paid.energy = c.max_energy;
                for id in rocks {
                    remove_el(arena, id);
                }
                (paid, el)
            }
        }
        Combatant::LiveSpathi(..) => {
            fire(
                arena,
                Weapon::Missile(MissileKind::Butt),
                el,
                CombatantCore {
                    facing: (facing + 8).rem_euclid(16),
                    ..paid
                },
            );
            (paid, el)
        }
        Combatant::LiveSupox(..) => {
            let offset = match (c.input.thrust, c.input.turn) {
                (true, Turn::TurnLeft) => 10,
                (true, Turn::TurnRight) => 6,
                (true, Turn::NoTurn) => 8,
                (false, Turn::TurnLeft) => -4,
                (false, Turn::TurnRight) => 4,
                (false, Turn::NoTurn) => 0,
            };
            if offset == 0 {
                (c, el)
            } else {
                let (vel, _, _) = inertial_thrust(
                    el.velocity,
                    CombatantCore {
                        facing: (facing + offset).rem_euclid(16),
                        ..c
                    },
                );
                let mut moved = el;
                moved.velocity = vel;
                (c, moved)
            }
        }
        Combatant::LiveSyreen(..) => {
            let Some(other) = enemy(arena, el.owner) else {
                return (c, el);
            };
            if distance(arena, el.next.location, other.next.location) < 800 && other.points > 1 {
                let count = (other.points - 1).min(8);
                let mut drained = other;
                drained.points -= count;
                put_el(arena, drained);
                for n in 1..=count {
                    let at = trig::wrap_point(
                        arena.space,
                        WorldPoint {
                            x: other.next.location.x + trig::cosine(n * 8, 90),
                            y: other.next.location.y + trig::sine(n * 8, 90),
                        },
                    );
                    let id = effect(
                        arena,
                        Body::Crew {
                            origin: owner_side(other.owner),
                        },
                        at,
                        240,
                    );
                    if let Some(mut crew) = get_el(arena, id) {
                        crew.points = 1;
                        crew.mass = 1;
                        crew.flags = ElementFlags {
                            finite_life: true,
                            defy_physics: true,
                            crew_object: true,
                            ..EMPTY_FLAGS
                        };
                        put_el(arena, crew);
                    }
                }
                (paid, el)
            } else {
                (c, el)
            }
        }
        Combatant::LiveThraddash(..) => {
            fire(arena, Weapon::Missile(MissileKind::Napalm), el, c);
            paid.special_wait = 1;
            let mut moved = el;
            moved.velocity = velocity::set_vector(80, c.facing);
            (paid, moved)
        }
        Combatant::LiveUmgah(..) => (c, el),
        Combatant::LiveUrQuan(..) => {
            if el.points > 2 && count_owned(arena, Body::UrQuanFighter, el.owner) <= 6 {
                let mut spec = *MissileKind::Fighter.spec();
                spec.direction_count = 2;
                spec.mount_count = 2;
                spec.mounts[0].facing_offset = -2;
                spec.mounts[1] = spec.mounts[0];
                spec.mounts[1].facing_offset = 2;
                fire_missile_spec(arena, spec, el, paid);
                let mut ship = el;
                ship.points -= 2;
                (paid, ship)
            } else {
                (c, el)
            }
        }
        Combatant::LiveUtwig(..) => {
            paid.shield_ticks = 12;
            (paid, el)
        }
        Combatant::LiveVux(..) => {
            let mut spec = *MissileKind::Limpet.spec();
            spec.direction_count = 1;
            spec.mount_count = 1;
            spec.mounts[0].facing_offset = 8;
            fire_missile_spec(arena, spec, el, paid);
            (paid, el)
        }
        Combatant::LiveYehat(..) => {
            paid.shield_ticks = 3;
            (paid, el)
        }
        Combatant::LiveZoqFotPik(..) => {
            fire(arena, Weapon::Contact(ContactKind::Tongue), el, paid);
            (paid, el)
        }
    }
}

fn fire_missile_spec(arena: &mut Arena, spec: MissileSpec, el: Element, c: CombatantCore) {
    if arena.elements.len() >= MAX_DISPLAY_ELEMENTS {
        return;
    }
    for mount in spec.mounts() {
        let direction = (c.facing + mount.facing_offset).rem_euclid(16);
        let angle = if spec.direction_count > 1 {
            c.facing + mount.facing_offset
        } else {
            c.facing
        } * 4;
        let at = trig::wrap_point(
            arena.space,
            WorldPoint {
                x: el.next.location.x
                    + trig::cosine(angle, mount.forward * 4)
                    + trig::cosine(angle + 16, mount.sideways * 4),
                y: el.next.location.y
                    + trig::sine(angle, mount.forward * 4)
                    + trig::sine(angle + 16, mount.sideways * 4),
            },
        );
        spawn_missile(
            arena,
            spec,
            el,
            CombatantCore {
                facing: direction,
                ..c
            },
            at,
        );
    }
    limit_saws(arena, spec.kind, el.owner);
}

fn steer_with_seed(arena: &mut Arena, el: Element) -> Element {
    if let Some(ProjectileState::Flying {
        kind: MissileKind::Bubble,
        age,
        facing: old_facing,
        tracking_wait,
    }) = el.projectile
    {
        let animation_wait = el.turn_wait;
        let (animation_random, after_animation) = if animation_wait == 0 {
            arena.seed.next()
        } else {
            (0, arena.seed)
        };
        let (turn_random, seed) = if tracking_wait == 0 {
            after_animation.next()
        } else {
            (0, after_animation)
        };
        arena.seed = seed;
        let target = enemy(arena, el.owner);
        let desired = target
            .map(|other| bearing(arena, el.next.location, other.next.location))
            .unwrap_or(old_facing);
        let delta = (desired - old_facing).rem_euclid(16);
        let facing = if tracking_wait > 0 {
            old_facing
        } else if target.is_none() {
            turn_random.rem_euclid(16)
        } else {
            (old_facing
                + if delta <= 8 {
                    turn_random.rem_euclid(8)
                } else {
                    -turn_random.rem_euclid(8)
                })
            .rem_euclid(16)
        };
        let mut out = el;
        if animation_wait == 0 {
            out.next.frame_index = (out.next.frame_index + 1).rem_euclid(3);
        }
        out.turn_wait = if animation_wait == 0 {
            animation_random.rem_euclid(4)
        } else {
            animation_wait - 1
        };
        out.projectile = Some(ProjectileState::Flying {
            kind: MissileKind::Bubble,
            age: age + 1,
            facing,
            tracking_wait: if tracking_wait == 0 {
                2
            } else {
                tracking_wait - 1
            },
        });
        out.velocity =
            velocity::set_components(trig::cosine(facing * 4, 1024), trig::sine(facing * 4, 1024));
        out
    } else {
        steer(arena, el)
    }
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
fn steer(arena: &Arena, el: Element) -> Element {
    match el.projectile {
        Some(ProjectileState::Charging {
            ticks: old_ticks, ..
        }) => {
            let Some(ship) = combatant_of(arena, el.owner) else {
                return el;
            };
            let c = core(&ship);
            let at = get_el(arena, c.element)
                .map(|parent| {
                    trig::wrap_point(
                        arena.space,
                        WorldPoint {
                            x: parent.next.location.x + trig::cosine(c.facing * 4, 96),
                            y: parent.next.location.y + trig::sine(c.facing * 4, 96),
                        },
                    )
                })
                .unwrap_or(el.next.location);
            let ticks = old_ticks + 1;
            let damage = 2 * 2i64.pow(elm_div(ticks, 72).min(3) as u32);
            let image = Image {
                location: at,
                frame_index: animation_frame(
                    Animation::ChargeLevel,
                    c.facing,
                    elm_div(ticks, 2),
                    damage,
                ),
            };
            let mut out = el;
            out.current = image;
            out.next = image;
            out.mass = damage;
            out.points = damage;
            out.life = Life::Finite(if c.input.weapon { 2 } else { 10 });
            out.projectile = Some(if c.input.weapon {
                ProjectileState::Charging {
                    ticks,
                    facing: c.facing,
                }
            } else {
                ProjectileState::Flying {
                    kind: MissileKind::Charge,
                    age: 0,
                    facing: c.facing,
                    tracking_wait: 0,
                }
            });
            out.velocity = if c.input.weapon {
                velocity::ZERO
            } else {
                velocity::set_components(
                    trig::cosine(c.facing * 4, 180 * 32),
                    trig::sine(c.facing * 4, 180 * 32),
                )
            };
            out
        }
        Some(ProjectileState::Flying {
            kind: missile,
            age,
            facing,
            tracking_wait,
        }) => fly_missile(arena, missile, age, facing, tracking_wait, el),
        Some(ProjectileState::Attached {
            contact,
            age: old_age,
            ..
        }) => {
            let Some(ship) = combatant_of(arena, el.owner) else {
                return el;
            };
            let c = core(&ship);
            let Some(parent) = get_el(arena, c.element) else {
                return el;
            };
            let age = old_age + 1;
            let reach = if contact == ContactKind::Tongue {
                age.min(3) * 32
            } else {
                0
            };
            let at = trig::wrap_point(
                arena.space,
                WorldPoint {
                    x: parent.next.location.x + trig::cosine(c.facing * 4, reach),
                    y: parent.next.location.y + trig::sine(c.facing * 4, reach),
                },
            );
            let mut out = el;
            out.next = Image {
                location: at,
                frame_index: c.facing
                    + if contact == ContactKind::Cone {
                        age.rem_euclid(3) * 16
                    } else {
                        0
                    },
            };
            out.projectile = Some(ProjectileState::Attached {
                contact,
                age,
                facing: c.facing,
            });
            out
        }
        _ => match el.body {
            Body::WeaponImpact(missile) => {
                let age = el.color_cycle_index - el.life.ticks();
                let first = el.thrust_wait;
                let frame = if missile == MissileKind::Plasma {
                    first + age.min(el.color_cycle_index - 1 - age)
                } else {
                    first + age
                };
                let mut out = el;
                out.next.frame_index = frame;
                out
            }
            _ => steer_legacy(arena, el),
        },
    }
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
fn fly_missile(
    arena: &Arena,
    missile: MissileKind,
    old_age: i64,
    old_facing: Facing,
    old_tracking_wait: i64,
    el: Element,
) -> Element {
    let spec = *missile.spec();
    let age = old_age + 1;
    let target = enemy(arena, el.owner);
    let desired = target
        .map(|other| bearing(arena, el.next.location, other.next.location))
        .unwrap_or(old_facing);
    let turn = |wanted: i64| {
        let delta = (wanted - old_facing).rem_euclid(16);
        (old_facing
            + if delta == 0 {
                0
            } else if delta <= 8 {
                1
            } else {
                -1
            })
        .rem_euclid(16)
    };
    let (facing, tracking_wait) = match spec.guidance {
        Guidance::Tracking { wait, .. } => {
            if old_tracking_wait > 0 {
                (old_facing, old_tracking_wait - 1)
            } else {
                (turn(desired), wait)
            }
        }
        Guidance::BubbleFlight => {
            if age.rem_euclid(3) == 0 {
                (turn(desired), 0)
            } else {
                (old_facing, 0)
            }
        }
        _ => (old_facing, 0),
    };
    let frame = if missile == MissileKind::Shard {
        1
    } else if missile == MissileKind::Spit {
        elm_div(age + 2, 3).min(12)
    } else {
        animation_frame(spec.animation, facing, age, el.mass)
    };
    let remaining = el.life.ticks();
    let plasma_life = if missile == MissileKind::Plasma && el.points < el.mass {
        el.points * 13
    } else {
        remaining
    };
    let plasma_damage = elm_div(plasma_life * 10 + 142, 143).max(1);
    let speed = match missile {
        MissileKind::Nuke => (40 + age * 4).min(80),
        MissileKind::Spit => (13 - elm_div(age + 2, 3).min(12)).max(0) * 8,
        _ => spec.speed,
    };
    let out_velocity = match spec.guidance {
        Guidance::HeldBlade => {
            let held = combatant_of(arena, el.owner)
                .map(|c| core(&c).input.weapon)
                .unwrap_or(false);
            if held {
                el.velocity
            } else {
                let (vx, vy) = velocity::get_current(&el.velocity);
                if vx.abs() + vy.abs() > 32 {
                    velocity::set_components(elm_div(vx, 2), elm_div(vy, 2))
                } else if target
                    .map(|other| distance(arena, el.next.location, other.next.location) < 200 * 4)
                    .unwrap_or(false)
                {
                    velocity::set_components(
                        trig::cosine(desired * 4, 256),
                        trig::sine(desired * 4, 256),
                    )
                } else {
                    velocity::ZERO
                }
            }
        }
        Guidance::Tracking { .. } | Guidance::BubbleFlight => velocity::set_components(
            trig::cosine(facing * 4, speed * 32),
            trig::sine(facing * 4, speed * 32),
        ),
        Guidance::Ballistic => {
            if missile == MissileKind::Spit {
                velocity::set_components(
                    trig::cosine(facing * 4, speed * 32),
                    trig::sine(facing * 4, speed * 32),
                )
            } else {
                el.velocity
            }
        }
    };
    let mut out = el;
    out.projectile = Some(ProjectileState::Flying {
        kind: missile,
        age,
        facing,
        tracking_wait,
    });
    out.next.frame_index = if missile == MissileKind::Plasma {
        (11 - elm_div(plasma_life + 12, 13)).min(10)
    } else {
        frame
    };
    out.velocity = out_velocity;
    if missile == MissileKind::Plasma {
        out.points = plasma_damage;
        out.mass = plasma_damage;
        out.life = Life::Finite(plasma_life);
    } else if missile == MissileKind::Crystal {
        out.life = Life::Finite(remaining + 1);
    } else if missile == MissileKind::Saw
        && !combatant_of(arena, el.owner)
            .map(|c| core(&c).input.weapon)
            .unwrap_or(false)
    {
        out.life = Life::Finite(remaining + 1);
    }
    out
}

fn steer_legacy(arena: &Arena, el: Element) -> Element {
    let target = if matches!(el.body, Body::Crew { .. }) {
        arena
            .elements
            .values()
            .copied()
            .filter(|ship| ship.flags.player_ship)
            .min_by_key(|ship| {
                (
                    distance(arena, el.next.location, ship.next.location),
                    ship.id.0,
                )
            })
    } else {
        enemy(arena, el.owner)
    };
    if el.body.homing() || el.flags.crew_object {
        let Some(other) = target else { return el };
        let wanted = bearing(arena, el.next.location, other.next.location);
        let difference = (wanted - el.next.frame_index).rem_euclid(16);
        let facing = (el.next.frame_index
            + if difference == 0 {
                0
            } else if difference <= 8 {
                1
            } else {
                -1
            })
        .rem_euclid(16);
        let (vx, vy) = velocity::get_current(&el.velocity);
        let speed = if el.flags.crew_object {
            12 * 32
        } else {
            trig::square_root(vx * vx + vy * vy).max(640)
        };
        let mut out = el;
        out.next.frame_index = facing;
        out.velocity = velocity::set_components(
            trig::cosine(facing * 4, speed),
            trig::sine(facing * 4, speed),
        );
        out
    } else if el.body == Body::KohrAhSaw {
        if combatant_of(arena, el.owner)
            .map(|c| !core(&c).input.weapon)
            .unwrap_or(false)
        {
            let mut out = el;
            out.velocity = velocity::ZERO;
            out
        } else {
            el
        }
    } else {
        el
    }
}

fn collect_crew(arena: &mut Arena, ship: Element, crew: Element) {
    if ship.flags.player_ship && crew.flags.crew_object {
        if let Some(combatant) = combatant_of(arena, ship.owner) {
            if ship.points < core(&combatant).max_crew {
                let mut collected = ship;
                collected.points += 1;
                put_el(arena, collected);
                remove_el(arena, crew.id);
            }
        }
    }
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
fn prepare_abilities(arena: &mut Arena) {
    for side in [Side::Bottom, Side::Top] {
        let combatant = *arena.combatants.get(side);
        let c = core(&combatant);
        let Some(el) = get_el(arena, c.element) else {
            continue;
        };
        match combatant {
            Combatant::LiveAndrosynth(_, AndrosynthExtra::Blazer { guardian }) => {
                if c.energy <= 0 {
                    let mut restored = c;
                    restored.characteristics = guardian;
                    arena.combatants.set(
                        side,
                        Combatant::LiveAndrosynth(restored, AndrosynthExtra::Guardian),
                    );
                } else {
                    let mut burned = c;
                    burned.energy = (c.energy - 1).max(0);
                    if let Some(other) = enemy(arena, el.owner) {
                        if distance(arena, el.next.location, other.next.location) < 110 {
                            damage_ship(arena, 3, other);
                        }
                    }
                    map_combatant(arena, side, |live| set_core(burned, live));
                    if let Some(mut ship) = get_el(arena, el.id) {
                        ship.velocity = velocity::set_vector(60, c.facing);
                        put_el(arena, ship);
                    }
                }
            }
            Combatant::LiveChenjesu(..) => {
                if c.old_input.weapon && !c.input.weapon {
                    let crystals: Vec<_> = arena
                        .elements
                        .values()
                        .copied()
                        .filter(|e| e.owner == el.owner && e.body == Body::ChenjesuPhoton)
                        .collect();
                    for crystal in crystals {
                        remove_el(arena, crystal.id);
                        fire(arena, Weapon::Missile(MissileKind::Shard), crystal, c);
                    }
                }
            }
            Combatant::LiveVux(_, VuxExtra::WarpPending) => {
                if let Some(target) = enemy(arena, el.owner) {
                    let angle = bearing(arena, target.next.location, el.next.location) * 4;
                    let at = trig::wrap_point(
                        arena.space,
                        WorldPoint {
                            x: target.next.location.x + trig::cosine(angle, 420),
                            y: target.next.location.y + trig::sine(angle, 420),
                        },
                    );
                    let facing = bearing(arena, at, target.next.location);
                    let mut moved = el;
                    moved.current = Image {
                        location: at,
                        frame_index: facing,
                    };
                    moved.next = moved.current;
                    put_el(arena, moved);
                    arena.combatants.set(
                        side,
                        Combatant::LiveVux(CombatantCore { facing, ..c }, VuxExtra::OnField),
                    );
                }
            }
            Combatant::LiveSlylandro(..) => {
                if let Some(mut ship) = get_el(arena, el.id) {
                    ship.velocity = velocity::set_vector(c.characteristics.max_thrust, c.facing);
                    ship.flags.defy_physics = true;
                    put_el(arena, ship);
                }
            }
            Combatant::LiveArilou(..) => {
                if let Some(mut ship) = get_el(arena, el.id) {
                    if !c.input.thrust {
                        ship.velocity = velocity::ZERO;
                    }
                    ship.flags.defy_physics = true;
                    put_el(arena, ship);
                }
            }
            _ => {}
        }
    }
}

fn environment(arena: &mut Arena) {
    let rocks = arena
        .elements
        .values()
        .filter(|e| e.body == Body::Asteroid)
        .count();
    if arena.frame.rem_euclid(120) == 0 && rocks < 5 {
        let (x, s1) = arena.seed.next();
        let (y, s2) = s1.next();
        arena.seed = s2;
        let at = WorldPoint {
            x: x.rem_euclid(arena.space.width),
            y: y.rem_euclid(arena.space.height),
        };
        let id = effect(arena, Body::Asteroid, at, 1200);
        if let Some(mut rock) = get_el(arena, id) {
            rock.points = 3;
            rock.mass = 3;
            rock.flags = ElementFlags {
                finite_life: true,
                ..EMPTY_FLAGS
            };
            rock.velocity = velocity::set_vector(12, x.rem_euclid(16));
            put_el(arena, rock);
        }
    }
}

#[cfg_attr(target_arch = "nvptx64", inline(never))]
fn auxiliaries(arena: &mut Arena) {
    for id in arena.queue.clone() {
        let Some(pet) = get_el(arena, id) else {
            continue;
        };
        if let Body::ChmmrSatellite { orbit_facing } = pet.body {
            let Some(ship) = combatant_of(arena, pet.owner) else {
                continue;
            };
            let Some(parent) = get_el(arena, core(&ship).element) else {
                remove_el(arena, pet.id);
                continue;
            };
            let frame = arena.frame;
            let angle = frame + orbit_facing * 21;
            let at = trig::wrap_point(
                arena.space,
                WorldPoint {
                    x: parent.next.location.x + trig::cosine(angle, 150),
                    y: parent.next.location.y + trig::sine(angle, 150),
                },
            );
            let image = Image {
                location: at,
                frame_index: frame.rem_euclid(16),
            };
            let mut moved = pet;
            moved.current = image;
            moved.next = image;
            put_el(arena, moved);
            let threats: Vec<_> = arena
                .elements
                .values()
                .copied()
                .filter(|e| {
                    e.owner != pet.owner
                        && (is_weapon(*e) || e.flags.player_ship)
                        && distance(arena, at, e.next.location) < 220
                })
                .collect();
            if frame.rem_euclid(6) == orbit_facing {
                for target in threats {
                    if target.flags.player_ship {
                        damage_ship(arena, 1, target);
                    } else {
                        remove_el(arena, target.id);
                    }
                }
            }
        } else if matches!(
            pet.body,
            Body::OrzMarine | Body::UrQuanFighter | Body::ChenjesuDogi
        ) {
            if let Some(target) = enemy(arena, pet.owner) {
                let range = if pet.body == Body::UrQuanFighter {
                    220
                } else {
                    95
                };
                if !ready(pet.thrust_wait) {
                    let mut waiting = pet;
                    waiting.thrust_wait = dec_wait(waiting.thrust_wait);
                    put_el(arena, waiting);
                } else if distance(arena, pet.next.location, target.next.location) < range {
                    if pet.body == Body::ChenjesuDogi {
                        if combatant_of(arena, target.owner).is_some() {
                            map_combatant(arena, owner_side(target.owner), |live| {
                                let mut c = core(&live);
                                c.energy = (c.energy - 10).max(0);
                                set_core(c, live)
                            });
                        }
                    } else {
                        damage_ship(
                            arena,
                            if pet.body == Body::OrzMarine {
                                1
                            } else {
                                pet.mass
                            },
                            target,
                        );
                    }
                    let mut next = pet;
                    next.thrust_wait = if pet.body == Body::OrzMarine { 18 } else { 12 };
                    if pet.body == Body::ChenjesuDogi {
                        next.velocity =
                            velocity::set_vector(50, (pet.next.frame_index + 8).rem_euclid(16));
                    }
                    put_el(arena, next);
                    effect(arena, Body::Blast, target.next.location, 4);
                }
            } else {
                let opponent = if pet.owner == Owner::Owned(Side::Bottom) {
                    arena.combatants.top
                } else {
                    arena.combatants.bottom
                };
                if get_el(arena, core(&opponent).element).is_some() {
                    continue;
                }
                let Some(ship) = combatant_of(arena, pet.owner) else {
                    continue;
                };
                let Some(mut parent) = get_el(arena, core(&ship).element) else {
                    remove_el(arena, pet.id);
                    continue;
                };
                if distance(arena, pet.next.location, parent.next.location) < 120 {
                    remove_el(arena, pet.id);
                    parent.points = (parent.points
                        + if pet.body == Body::ChenjesuDogi { 0 } else { 1 })
                    .min(core(&ship).max_crew);
                    put_el(arena, parent);
                } else {
                    let mut returning = pet;
                    returning.velocity = velocity::set_vector(
                        48,
                        bearing(arena, pet.next.location, parent.next.location),
                    );
                    put_el(arena, returning);
                }
            }
        }
    }
}

fn count_owned(arena: &Arena, body: Body, owner: Owner) -> usize {
    arena
        .elements
        .values()
        .filter(|el| el.owner == owner && el.body == body)
        .count()
}
