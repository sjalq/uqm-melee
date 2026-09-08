//! Exact port of `src/Melee/Cyborg.elm`.

use crate::arsenal;
use crate::battle::Arena;
use crate::catalog::{Ability, Characteristics, ShipKind, Weapon};
use crate::element::{Body, Element, Image};
use crate::input::{BattleInput, CyborgRating, Turn};
use crate::motion;
use crate::ship_state::{AndrosynthExtra, Combatant, CombatantCore};
use melee_core::rng::Seed;
use melee_core::trig;
use melee_core::units::{
    Side, VelocityDesc, WorldExtent, WorldPoint, GRAVITY_MASS_THRESHOLD, MAX_SHIP_MASS,
};
use melee_core::velocity;
use melee_core::{idiv, mod_by};

const CLOSE_RANGE: i64 = 200;
const LONG_RANGE: i64 = 4000;
#[allow(dead_code)]
const FAST_SHIP: i64 = 150;
const MEDIUM_SHIP: i64 = 45;
const SLOW_SHIP: i64 = 25;
#[allow(dead_code)]
const FULL_CIRCLE: i64 = 64;
const HALF_CIRCLE: i64 = 32;
const QUADRANT: i64 = 16;
const OCTANT: i64 = 8;

#[derive(Copy, Clone, PartialEq, Eq)]
enum MoveState {
    NoMovement,
    Pursue,
    Entice,
    Avoid,
}

#[derive(Copy, Clone)]
struct Eval {
    object: Option<Element>,
    movement: MoveState,
    facing: i64,
    which_turn: i64,
}

#[derive(Copy, Clone)]
struct Concerns {
    enemy: Eval,
    crew: Eval,
    weapon: Eval,
    gravity: Eval,
    empty: Eval,
}

#[derive(Clone)]
struct Work<'a> {
    ship: Element,
    core: CombatantCore,
    kind: ShipKind,
    ability: Ability,
    mi: i64,
    range: i64,
    facing: i64,
    velocity: VelocityDesc,
    next: WorldPoint,
    turn_wait: i64,
    thrust_wait: i64,
    left: bool,
    right: bool,
    thrust: bool,
    weapon: bool,
    special: bool,
    seed: Seed,
    space: WorldExtent,
    rating: CyborgRating,
    moved: bool,
    fired: bool,
    arena: &'a Arena,
    side: Side,
}

const BLANK: Eval = Eval {
    object: None,
    movement: MoveState::NoMovement,
    facing: 0,
    which_turn: 65535,
};

pub fn maneuverability(chars: &Characteristics) -> i64 {
    let index = chars.max_thrust * chars.thrust_increment;
    let divisor = chars.turn_wait + chars.thrust_wait;
    if divisor > 0 {
        idiv(index, divisor)
    } else {
        idiv(index, 2)
    }
}

pub fn think(side: Side, rating: CyborgRating, arena: &Arena, seed: Seed) -> (BattleInput, Seed) {
    let (input, next_seed, _) = decide(rating, side, arena, seed);
    (input, next_seed)
}

pub fn pilot(rating: CyborgRating, side: Side, arena: &mut Arena) -> BattleInput {
    let (input, seed, characteristics) = decide(rating, side, arena, arena.seed);
    arena.seed = seed;
    if let Combatant::LiveUmgah(core, _) = arena.combatants.get_mut(side) {
        core.characteristics = characteristics;
    }
    input
}

const fn idle() -> BattleInput {
    BattleInput {
        turn: Turn::NoTurn,
        thrust: false,
        weapon: false,
        special: false,
    }
}

fn decide(
    rating: CyborgRating,
    side: Side,
    arena: &Arena,
    seed: Seed,
) -> (BattleInput, Seed, Characteristics) {
    let original = combatant(side, arena);
    let core = *original.core();
    let Some(ship) = arena.elements.get(&core.element.0).copied() else {
        return (idle(), seed, core.characteristics);
    };
    if ship.points == 0 {
        return (idle(), seed, core.characteristics);
    }
    let kind = original.kind();
    let spec = kind.stock();
    let work0 = Work {
        ship,
        core,
        kind,
        ability: spec.ability,
        mi: maneuverability(&core.characteristics),
        range: kind.intel_range(),
        facing: core.facing,
        velocity: ship.velocity,
        next: ship.next.location,
        turn_wait: ship.turn_wait,
        thrust_wait: ship.thrust_wait,
        left: false,
        right: false,
        thrust: false,
        weapon: false,
        special: false,
        seed,
        space: arena.space,
        rating,
        moved: ship.turn_wait > 0 && ship.thrust_wait > 0,
        fired: core.weapon_wait > 0 || spec.ability.seeking_weapon,
        arena,
        side,
    };
    let concerns = fill_concerns(&work0);
    let work1 = race_intelligence(work0, concerns);
    let input = BattleInput {
        turn: if work1.left {
            Turn::TurnLeft
        } else if work1.right {
            Turn::TurnRight
        } else {
            Turn::NoTurn
        },
        thrust: work1.thrust,
        weapon: work1.weapon,
        special: rating != CyborgRating::StandardCyborg && work1.special,
    };
    // Only Umgah's adjusted characteristics escape the decision. Avoid
    // returning a copy of the entire combatant just to read this field.
    let characteristics = if matches!(original, Combatant::LiveUmgah(..)) {
        work1.core.characteristics
    } else {
        core.characteristics
    };
    (input, work1.seed, characteristics)
}

#[inline]
fn combatant(side: Side, arena: &Arena) -> &Combatant {
    arena.combatants.get(side)
}

#[inline]
fn other_side(side: Side) -> Side {
    side.other()
}

#[inline]
fn wait_n(wait: i64) -> i64 {
    wait
}

#[inline]
fn weapon_ready(work: &Work<'_>) -> bool {
    wait_n(work.core.weapon_wait) <= 0
}

#[inline]
fn special_ready(work: &Work<'_>) -> bool {
    wait_n(work.core.special_wait) <= 0 && work.rating != CyborgRating::StandardCyborg
}

#[inline]
fn ultra(work: &Work<'_>) -> bool {
    work.core.characteristics.thrust_increment == work.core.characteristics.max_thrust
        && work.mi >= MEDIUM_SHIP
}

#[inline]
fn is_gravity(el: Element) -> bool {
    el.mass > GRAVITY_MASS_THRESHOLD
}

#[inline]
fn is_crew(el: Element) -> bool {
    el.flags.crew_object || is_crew_body(el.body)
}

#[inline]
fn is_crew_body(body: Body) -> bool {
    matches!(body, Body::Crew { .. })
}

#[inline]
fn is_ship(el: Element) -> bool {
    el.flags.player_ship
}

#[inline]
fn same_player(a: Element, b: Element) -> bool {
    a.parent == b.parent && a.parent.is_some()
}

#[inline]
fn colliding(el: Element) -> bool {
    !(el.flags.nonsolid || el.flags.disappearing)
}

fn radius_world(el: Element) -> i64 {
    match el.body {
        Body::Planet => 160,
        Body::Ship(_) => 40,
        Body::Asteroid => 24,
        Body::Crew { .. } => 16,
        _ => 12,
    }
}

#[inline]
fn travel_angle(vel: VelocityDesc) -> i64 {
    vel.travel_angle
}

#[allow(dead_code)]
#[inline]
fn is_velocity_zero(vel: VelocityDesc) -> bool {
    vel.vector.width == 0 && vel.vector.height == 0
}

#[inline]
fn displacement(turns: i64, vel: VelocityDesc) -> (i64, i64) {
    velocity::get_next(turns.max(1), &vel).0
}

#[inline]
fn wrap_loc(space: WorldExtent, point: WorldPoint) -> WorldPoint {
    trig::wrap_point(space, point)
}

#[inline]
fn angle_to_facing(angle: i64) -> i64 {
    trig::angle_to_facing(angle)
}

#[inline]
fn facing_to_angle(facing: i64) -> i64 {
    trig::facing_to_angle(facing)
}

#[inline]
fn display_to_world(n: i64) -> i64 {
    n * 4
}

#[inline]
fn world_to_turn(d: i64) -> i64 {
    idiv(d, 64)
}

fn margin_of_error(rating: CyborgRating) -> i64 {
    match rating {
        CyborgRating::AwesomeCyborg => 0,
        CyborgRating::GoodCyborg => display_to_world(20),
        CyborgRating::StandardCyborg => display_to_world(40),
    }
}

fn plot_intercept(space: WorldExtent, a: Element, b: Element, max_turns: i64, margin: i64) -> i64 {
    if max_turns <= 0 {
        0
    } else {
        plot_from(space, a, b, margin, max_turns, 1)
    }
}

fn plot_from(
    space: WorldExtent,
    a: Element,
    b: Element,
    margin: i64,
    max_turns: i64,
    first_turn: i64,
) -> i64 {
    for t in first_turn..=max_turns {
        let (dax, day) = displacement(t, a.velocity);
        let (dbx, dby) = displacement(t, b.velocity);
        let pa = wrap_loc(
            space,
            WorldPoint {
                x: a.current.location.x + dax,
                y: a.current.location.y + day,
            },
        );
        let pb = wrap_loc(
            space,
            WorldPoint {
                x: b.current.location.x + dbx,
                y: b.current.location.y + dby,
            },
        );
        let dx = trig::wrap_delta(pa.x - pb.x, space.width);
        let dy = trig::wrap_delta(pa.y - pb.y, space.height);
        let r = radius_world(a) + radius_world(b) + margin;
        if dx * dx + dy * dy <= r * r {
            return t;
        }
    }
    0
}

#[inline]
fn life_span(el: Element) -> i64 {
    el.life.ticks()
}

fn fill_concerns(work: &Work<'_>) -> Concerns {
    let mut concerns = Concerns {
        enemy: BLANK,
        crew: BLANK,
        weapon: BLANK,
        gravity: BLANK,
        empty: BLANK,
    };
    for el in work.arena.elements.values().copied() {
        concerns = consider(work, el, concerns);
    }
    concerns
}

fn consider(work: &Work<'_>, el: Element, concerns: Concerns) -> Concerns {
    if el.id == work.ship.id || !colliding(el) || !colliding(work.ship) {
        return concerns;
    }
    let dx = trig::wrap_delta(
        el.next.location.x - work.ship.next.location.x,
        work.space.width,
    );
    let dy = trig::wrap_delta(
        el.next.location.y - work.ship.next.location.y,
        work.space.height,
    );
    if is_gravity(el) {
        consider_gravity(work, el, concerns)
    } else if is_ship(el) {
        consider_enemy(work, el, dx, dy, concerns)
    } else if el.parent.is_none() {
        consider_empty(el, dx, dy, concerns)
    } else if !same_player(el, work.ship)
        && !is_crew(el)
        && concerns.weapon.which_turn > 1
        && life_span(el) > 0
    {
        consider_weapon(work, el, dx, dy, concerns)
    } else if is_crew(el) && concerns.crew.which_turn > 1 {
        consider_crew(work, el, dx, dy, concerns)
    } else {
        concerns
    }
}

fn consider_gravity(work: &Work<'_>, el: Element, mut concerns: Concerns) -> Concerns {
    if work.moved {
        return concerns;
    }
    let maneuver_turn = if ultra(work) {
        16
    } else if work.mi <= MEDIUM_SHIP {
        48
    } else {
        32
    };
    let bounds = 80;
    let hit = plot_intercept(
        work.space,
        el,
        work.ship,
        maneuver_turn,
        display_to_world(30 + bounds * 3),
    );
    if hit > 0
        && (hit > 1
            || plot_intercept(work.space, el, work.ship, 1, display_to_world(35 + bounds)) > 0
            || plot_intercept(
                work.space,
                el,
                work.ship,
                maneuver_turn * 2,
                display_to_world(40 + bounds),
            ) > 1)
    {
        concerns.gravity = Eval {
            object: Some(el),
            movement: if ultra(work) {
                MoveState::Avoid
            } else {
                MoveState::Entice
            },
            facing: trig::arctan(
                -trig::wrap_delta(
                    el.next.location.x - work.ship.next.location.x,
                    work.space.width,
                ),
                -trig::wrap_delta(
                    el.next.location.y - work.ship.next.location.y,
                    work.space.height,
                ),
            ),
            which_turn: hit,
        };
    }
    concerns
}

fn consider_enemy(
    work: &Work<'_>,
    el: Element,
    dx: i64,
    dy: i64,
    mut concerns: Concerns,
) -> Concerns {
    let turns = world_to_turn(trig::square_root(dx * dx + dy * dy)).max(1);
    if turns > concerns.enemy.which_turn {
        return concerns;
    }
    let enemy = combatant(other_side(work.side), work.arena);
    let enemy_chars = enemy.core().characteristics;
    let foe_range = enemy.kind().intel_range();
    let foe_ability = enemy.kind().stock().ability;
    let should_pursue = work.moved
        || el.mass > MAX_SHIP_MASS
        || (work.range < LONG_RANGE
            && (work.range <= CLOSE_RANGE
                || (foe_range >= LONG_RANGE && foe_ability.seeking_weapon)
                || (work.core.characteristics.max_thrust < enemy_chars.max_thrust
                    && work.range < foe_range)));
    let facing = facing_to_angle(enemy.core().facing);
    concerns.enemy = Eval {
        object: Some(el),
        movement: if should_pursue {
            MoveState::Pursue
        } else {
            MoveState::Entice
        },
        facing,
        which_turn: turns,
    };
    let mut threat = work.clone();
    threat.kind = enemy.kind();
    threat.ability = foe_ability;
    threat.range = foe_range;
    threat.facing = enemy.core().facing;
    threat.core = *enemy.core();
    threat.ship = el;
    if foe_ability.immediate_weapon && ship_weapons(&threat, work.ship, 0) {
        concerns.weapon = Eval {
            object: Some(el),
            movement: MoveState::Avoid,
            facing,
            which_turn: 1,
        };
    }
    concerns
}

fn consider_empty(el: Element, dx: i64, dy: i64, mut concerns: Concerns) -> Concerns {
    if el.flags.finite_life {
        return concerns;
    }
    let turns = world_to_turn(trig::square_root(dx * dx + dy * dy));
    if turns < concerns.empty.which_turn {
        concerns.empty = Eval {
            object: Some(el),
            movement: MoveState::Pursue,
            facing: travel_angle(el.velocity),
            which_turn: turns.max(1),
        };
    }
    concerns
}

fn consider_weapon(
    work: &Work<'_>,
    el: Element,
    dx: i64,
    dy: i64,
    mut concerns: Concerns,
) -> Concerns {
    let ability = el
        .parent
        .map(|side| combatant(side, work.arena).kind().stock().ability)
        .unwrap_or(ShipKind::Shofixti.stock().ability);
    let seeking = (ability.seeking_weapon && !is_special_body(el.body))
        || (ability.seeking_special && is_special_body(el.body));
    let eval = if seeking {
        seeking_weapon(work, el, dx, dy)
    } else if work.rating != CyborgRating::AwesomeCyborg {
        Eval {
            object: None,
            movement: MoveState::NoMovement,
            facing: 0,
            which_turn: 0,
        }
    } else {
        let hit = plot_intercept(
            work.space,
            el,
            work.ship,
            life_span(el),
            display_to_world(40),
        );
        Eval {
            object: Some(el),
            movement: MoveState::Avoid,
            facing: travel_angle(el.velocity),
            which_turn: hit,
        }
    };
    if eval.which_turn > 0
        && (eval.which_turn < concerns.weapon.which_turn
            || (eval.which_turn == concerns.weapon.which_turn && eval.movement == MoveState::Avoid))
    {
        concerns.weapon = eval;
    }
    concerns
}

fn seeking_weapon(work: &Work<'_>, el: Element, dx: i64, dy: i64) -> Eval {
    let closing =
        trig::normalize_angle(travel_angle(el.velocity) - trig::arctan(-dx, -dy) + QUADRANT)
            > HALF_CIRCLE;
    let turns0 = world_to_turn(trig::square_root(dx * dx + dy * dy));
    let turns = if !el.flags.finite_life
        && !el.flags.crew_object
        && work.core.characteristics.max_thrust > display_to_world(8)
    {
        0
    } else if closing {
        0
    } else if ultra(work) {
        if turns0 == 0 {
            1
        } else if turns0 > 16 {
            0
        } else {
            turns0
        }
    } else if turns0 == 0 {
        1
    } else if turns0 > 16 || (work.mi > MEDIUM_SHIP && turns0 > 8) {
        0
    } else {
        turns0
    };
    if turns > 0 {
        Eval {
            object: Some(el),
            movement: MoveState::Entice,
            facing: travel_angle(el.velocity),
            which_turn: turns,
        }
    } else {
        Eval {
            object: None,
            movement: MoveState::NoMovement,
            facing: 0,
            which_turn: 0,
        }
    }
}

fn is_special_body(body: Body) -> bool {
    matches!(
        body,
        Body::ChenjesuDogi
            | Body::ChmmrSatellite { .. }
            | Body::ChmmrZap
            | Body::EarthlingPointDefense
            | Body::KohrAhFried
            | Body::MelnormeConfusion
            | Body::OrzMarine
            | Body::ShofixtiGlory
            | Body::SpathiButt
            | Body::ThraddashAfterburn
            | Body::UrQuanFighter
            | Body::VuxLimpet
    )
}

fn consider_crew(
    work: &Work<'_>,
    el: Element,
    dx: i64,
    dy: i64,
    mut concerns: Concerns,
) -> Concerns {
    let ours = (!el.flags.ignore_similar && same_player(el, work.ship)) || is_crew(el);
    let turns = world_to_turn(trig::square_root(dx * dx + dy * dy)).max(1);
    if ours
        && concerns.crew.which_turn > turns
        && (concerns.enemy.which_turn > 32
            || (concerns.enemy.which_turn > 8 && work.ship.target == Some(el.id)))
    {
        concerns.crew = Eval {
            object: Some(el),
            movement: MoveState::Pursue,
            facing: 0,
            which_turn: turns,
        };
    }
    concerns
}

fn ship_intelligence(mut work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let margin = margin_of_error(work.rating)
        + if concerns
            .enemy
            .object
            .is_some_and(|el| el.prim.object_cloaked())
        {
            display_to_world(40)
        } else {
            0
        };
    if work.turn_wait == 0 {
        work.left = false;
        work.right = false;
        work.moved = false;
    }
    if work.thrust_wait == 0 {
        work.thrust = false;
        work.moved = false;
    }
    work = move_and_fire(Concern::Gravity, work, concerns.gravity, margin);
    work = move_and_fire(Concern::Weapon, work, concerns.weapon, margin);
    work = move_and_fire(Concern::Crew, work, concerns.crew, margin);
    move_and_fire(Concern::Enemy, work, concerns.enemy, margin)
}

#[derive(Copy, Clone, PartialEq, Eq)]
enum Concern {
    Gravity,
    Weapon,
    Crew,
    Enemy,
}

fn move_and_fire<'a>(concern: Concern, mut work: Work<'a>, eval: Eval, margin: i64) -> Work<'a> {
    let Some(other) = eval.object else {
        return work;
    };
    if !work.moved
        && (concern != Concern::Weapon
            || eval.movement == MoveState::Pursue
            || other.flags.crew_object
            || work.mi >= MEDIUM_SHIP)
    {
        work.moved = true;
        work = ship_movement(work, eval);
    }
    if !work.fired
        && (concern == Concern::Enemy
            || (concern == Concern::Weapon && eval.movement != MoveState::Avoid))
        && ship_weapons(&work, other, margin)
    {
        work.weapon = true;
        work.fired = true;
    }
    work
}

fn ship_movement(work: Work<'_>, mut eval: Eval) -> Work<'_> {
    if eval.which_turn == 0 {
        eval.which_turn = 1;
    }
    match eval.movement {
        MoveState::Pursue => pursue(work, eval),
        MoveState::Avoid | MoveState::Entice => entice(work, eval),
        MoveState::NoMovement => work,
    }
}

fn ship_weapons(work: &Work<'_>, other: Element, margin: i64) -> bool {
    if work.ability.seeking_weapon || !weapon_ready(work) {
        return false;
    }
    if work.ability.immediate_weapon {
        let dx = trig::wrap_delta(
            other.current.location.x - work.ship.current.location.x,
            work.space.width,
        );
        let dy = trig::wrap_delta(
            other.current.location.y - work.ship.current.location.y,
            work.space.height,
        );
        let dist = trig::square_root(dx * dx + dy * dy);
        let wanted = angle_to_facing(trig::arctan(dx, dy));
        let delta = trig::normalize_facing(wanted - work.facing);
        return dist <= work.range && (delta <= 1 || delta >= 15);
    }
    match arsenal::primary(combatant(work.side, work.arena)) {
        Weapon::Missile(kind) => {
            let spec = kind.spec();
            let (dx, dy) = displacement(1, work.velocity);
            let origin = WorldPoint {
                x: work.ship.current.location.x + dx,
                y: work.ship.current.location.y + dy,
            };
            spec.mounts().iter().any(|mount| {
                let facing = mod_by(16, work.facing + mount.facing_offset);
                let launch = arsenal::launch_state(
                    spec,
                    facing,
                    &work.velocity,
                    arsenal::mount_position(spec, work.facing, origin, mount),
                );
                let mut ghost = work.ship;
                ghost.current = Image {
                    location: launch.position,
                    frame_index: work.facing,
                };
                ghost.velocity = launch.velocity;
                ghost.body = arsenal::missile_body(spec.kind);
                ghost.flags.player_ship = false;
                plot_intercept(work.space, ghost, other, spec.life, margin) > 0
            })
        }
        _ => {
            let dx = trig::wrap_delta(
                other.current.location.x - work.ship.current.location.x,
                work.space.width,
            );
            let dy = trig::wrap_delta(
                other.current.location.y - work.ship.current.location.y,
                work.space.height,
            );
            trig::square_root(dx * dx + dy * dy) <= work.range && facing_aligned(work, other)
        }
    }
}

fn facing_aligned(work: &Work<'_>, other: Element) -> bool {
    let dx = trig::wrap_delta(
        other.current.location.x - work.ship.current.location.x,
        work.space.width,
    );
    let dy = trig::wrap_delta(
        other.current.location.y - work.ship.current.location.y,
        work.space.height,
    );
    let wanted = angle_to_facing(trig::arctan(dx, dy));
    let delta = trig::normalize_facing(wanted - work.facing);
    delta <= 2 || delta >= 14
}

fn pursue(mut work: Work<'_>, eval: Eval) -> Work<'_> {
    let Some(other) = eval.object else {
        return work;
    };
    let (ship_dx, ship_dy) = displacement(eval.which_turn, work.velocity);
    let (other_dx, other_dy) = displacement(eval.which_turn, other.velocity);
    let next = trig::wrap_point(
        work.space,
        WorldPoint {
            x: work.ship.current.location.x + ship_dx,
            y: work.ship.current.location.y + ship_dy,
        },
    );
    let delta_x = trig::wrap_delta(
        other.current.location.x + other_dx - next.x,
        work.space.width,
    );
    let delta_y = trig::wrap_delta(
        other.current.location.y + other_dy - next.y,
        work.space.height,
    );
    let desired_thrust = trig::arctan(delta_x, delta_y);
    let can_turn = work.turn_wait == 0;
    let can_thrust = work.thrust_wait == 0
        && (is_ship(other) || same_player(other, work.ship) || is_crew(other));
    work.next = next;
    if can_turn {
        work = turn_ship(work, desired_thrust);
    }
    if can_thrust {
        thrust_ship(work, desired_thrust)
    } else {
        work
    }
}

fn entice(mut work: Work<'_>, eval: Eval) -> Work<'_> {
    let Some(other) = eval.object else {
        return work;
    };
    let (ship_dx, ship_dy) = displacement(eval.which_turn, work.velocity);
    let (other_dx, other_dy) = displacement(eval.which_turn, other.velocity);
    let next = trig::wrap_point(
        work.space,
        WorldPoint {
            x: work.ship.current.location.x + ship_dx,
            y: work.ship.current.location.y + ship_dy,
        },
    );
    let delta_x = trig::wrap_delta(
        other.current.location.x + other_dx - next.x,
        work.space.width,
    );
    let delta_y = trig::wrap_delta(
        other.current.location.y + other_dy - next.y,
        work.space.height,
    );
    let toward = trig::arctan(delta_x, delta_y);
    let away = trig::normalize_angle(toward + HALF_CIRCLE);
    work.next = next;
    let can_turn = work.turn_wait == 0;
    let can_thrust = work.thrust_wait == 0;
    if eval.movement == MoveState::Avoid {
        entice_avoid(work, eval, toward, can_turn, can_thrust)
    } else if is_gravity(other) {
        entice_planet(work, toward, away, can_turn, can_thrust)
    } else {
        entice_target(work, eval, other, toward, away, can_turn, can_thrust)
    }
}

fn entice_avoid(
    mut work: Work<'_>,
    eval: Eval,
    toward: i64,
    can_turn: bool,
    can_thrust: bool,
) -> Work<'_> {
    let rel = trig::normalize_angle(trig::normalize_angle(toward + HALF_CIRCLE) - eval.facing);
    let dir = if rel <= HALF_CIRCLE { 1 } else { -1 };
    let thrust_angle = trig::normalize_angle(eval.facing + dir * QUADRANT - dir * idiv(OCTANT, 2));
    if can_turn {
        work = turn_ship(work, thrust_angle);
    }
    if can_thrust {
        thrust_ship(work, thrust_angle)
    } else {
        work
    }
}

fn entice_planet(
    mut work: Work<'_>,
    toward: i64,
    away: i64,
    can_turn: bool,
    can_thrust: bool,
) -> Work<'_> {
    let planet_facing = angle_to_facing(toward);
    let cone = trig::normalize_facing(planet_facing - work.facing + angle_to_facing(QUADRANT));
    let needs_coast =
        work.core.characteristics.thrust_increment != work.core.characteristics.max_thrust;
    let (turn_angle, do_thrust) = if cone > angle_to_facing(QUADRANT * 2) {
        (toward, can_thrust && !needs_coast)
    } else if cone == angle_to_facing(QUADRANT) {
        (travel_angle(work.velocity), can_thrust && !needs_coast)
    } else if cone == 0 || cone == angle_to_facing(QUADRANT * 2) {
        (facing_to_angle(work.facing), true)
    } else {
        (away, can_thrust && !needs_coast)
    };
    if can_turn {
        work = turn_ship(work, turn_angle);
    }
    if do_thrust && (can_thrust || cone == 0 || cone == angle_to_facing(QUADRANT * 2)) {
        thrust_ship(work, turn_angle)
    } else {
        work
    }
}

fn maneuver<'a>(
    mut work: Work<'a>,
    angle: i64,
    thrust: bool,
    can_turn: bool,
    can_thrust: bool,
) -> Work<'a> {
    if can_turn {
        work = turn_ship(work, angle);
    }
    if can_thrust && thrust {
        thrust_ship(work, angle)
    } else {
        work
    }
}

fn entice_target(
    work: Work<'_>,
    eval: Eval,
    other: Element,
    toward: i64,
    away: i64,
    can_turn: bool,
    can_thrust: bool,
) -> Work<'_> {
    let at_speed = motion::at_limit(&work.velocity, &work.core.flags);
    let (ship_dx, ship_dy) = displacement(eval.which_turn, work.velocity);
    let (other_dx, other_dy) = displacement(eval.which_turn, other.velocity);
    let ship_travel = trig::arctan(ship_dx, ship_dy);
    let enemy = enemy_ability(&work);
    let fire_directions = [
        (enemy.fires_fore, 0),
        (enemy.fires_right, QUADRANT),
        (enemy.fires_aft, HALF_CIRCLE),
        (enemy.fires_left, QUADRANT * 3),
    ];
    let (mut cone, mut backing) = (trig::normalize_angle(away - eval.facing + OCTANT), false);
    if is_ship(other) {
        for (enabled, offset) in fire_directions {
            if !backing && enabled {
                let facing = eval.facing + offset;
                cone = trig::normalize_angle(away - facing + OCTANT);
                backing = cone <= QUADRANT
                    && (other_dx != 0 || other_dy != 0)
                    && trig::normalize_angle(
                        travel_angle(other.velocity) + HALF_CIRCLE - facing + OCTANT,
                    ) <= QUADRANT;
            }
        }
    }
    let in_range = plot_intercept(
        work.space,
        work.ship,
        other,
        10,
        work.range - idiv(work.range, 4),
    );
    let uses_inertia =
        work.core.characteristics.thrust_increment != work.core.characteristics.max_thrust;
    if is_ship(other) && backing && work.range < LONG_RANGE && eval.which_turn <= 32 {
        maneuver(work, away, true, can_turn, can_thrust)
    } else if is_ship(other)
        && eval.which_turn <= 8
        && work.core.characteristics.max_thrust
            <= combatant(other_side(work.side), work.arena)
                .core()
                .characteristics
                .max_thrust
    {
        maneuver(work, toward, true, can_turn, can_thrust)
    } else if !at_speed && plot_intercept(work.space, work.ship, other, 40, CLOSE_RANGE * 2) > 0 {
        if trig::normalize_angle(toward - facing_to_angle(work.facing) + OCTANT) <= QUADRANT
            || cone > QUADRANT
        {
            maneuver(work, away, true, can_turn, can_thrust)
        } else {
            let facing = facing_to_angle(work.facing);
            maneuver(work, facing, true, can_turn, can_thrust)
        }
    } else if in_range > 0 {
        if uses_inertia
            && at_speed
            && (trig::normalize_angle(away - ship_travel + 10) <= 20
                || plot_intercept(work.space, work.ship, other, 30, CLOSE_RANGE * 2) == 0)
        {
            maneuver(work, toward, false, can_turn, can_thrust)
        } else if in_range == 1 || uses_inertia {
            let mut turned = work;
            if can_turn {
                turned = turn_ship(turned, away);
            }
            let angle = if trig::normalize_angle(toward - ship_travel + 10) <= 20 {
                facing_to_angle(turned.facing)
            } else {
                away
            };
            if can_thrust {
                thrust_ship(turned, angle)
            } else {
                turned
            }
        } else {
            maneuver(work, toward, true, can_turn, can_thrust)
        }
    } else {
        maneuver(work, toward, true, can_turn, can_thrust)
    }
}

fn turn_ship(mut work: Work<'_>, angle: i64) -> Work<'_> {
    let wanted = angle_to_facing(angle);
    let delta0 = trig::normalize_facing(wanted - work.facing);
    let delta = if delta0 == 8 {
        let (r, seed) = work.seed.next();
        work.seed = seed;
        if mod_by(2, r) == 0 {
            trig::normalize_facing(delta0 + 1)
        } else {
            trig::normalize_facing(delta0 - 1)
        }
    } else {
        delta0
    };
    if delta == 0 {
        work
    } else if delta < 8 {
        work.right = true;
        work.left = false;
        work.facing = trig::normalize_facing(work.facing + 1);
        work
    } else {
        work.left = true;
        work.right = false;
        work.facing = trig::normalize_facing(work.facing - 1);
        work
    }
}

fn thrust_ship(mut work: Work<'_>, angle: i64) -> Work<'_> {
    let vel_facing = angle_to_facing(travel_angle(work.velocity));
    let aligned = trig::normalize_facing(angle_to_facing(angle) - vel_facing) == 0;
    let coasting = aligned
        && motion::at_limit(&work.velocity, &work.core.flags)
        && !work.core.flags.in_gravity_well;
    let cone =
        trig::normalize_facing(angle_to_facing(angle) - work.facing + angle_to_facing(QUADRANT));
    let should = work.thrust
        || (!coasting
            && (cone == angle_to_facing(QUADRANT)
                || (motion::beyond_limit(&work.velocity, &work.core.flags) && cone <= 8)));
    if should {
        work.thrust = true;
        work.velocity = inertial(&work);
    }
    work
}

fn inertial(work: &Work<'_>) -> VelocityDesc {
    motion::velocity(motion::thrust(
        &work.velocity,
        &with_facing(work.facing, work.core),
    ))
}

fn with_facing(facing: i64, mut core: CombatantCore) -> CombatantCore {
    core.facing = facing;
    core
}

fn enemy_mi(work: &Work<'_>) -> i64 {
    maneuverability(
        &combatant(other_side(work.side), work.arena)
            .core()
            .characteristics,
    )
}

fn enemy_range(work: &Work<'_>) -> i64 {
    combatant(other_side(work.side), work.arena)
        .kind()
        .intel_range()
}

fn enemy_ability(work: &Work<'_>) -> Ability {
    combatant(other_side(work.side), work.arena)
        .kind()
        .stock()
        .ability
}

fn coin(mut work: Work<'_>, sides: i64) -> (bool, Work<'_>) {
    let (r, seed) = work.seed.next();
    work.seed = seed;
    (mod_by(sides, r) == 0, work)
}

fn race_intelligence(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    match work.kind {
        ShipKind::Shofixti => shofixti(work, concerns),
        ShipKind::Yehat => yehat(work, concerns),
        ShipKind::Earthling => earthling(work, concerns),
        ShipKind::Arilou => arilou(work, concerns),
        ShipKind::Pkunk => pkunk(work, concerns),
        ShipKind::Mycon => mycon(work, concerns),
        ShipKind::Spathi => spathi(work, concerns),
        ShipKind::Androsynth => androsynth(work, concerns),
        ShipKind::Chenjesu => chenjesu(work, concerns),
        ShipKind::Ilwrath => ilwrath(work, concerns),
        ShipKind::Thraddash => thraddash(work, concerns),
        ShipKind::Druuge => druuge(work, concerns),
        ShipKind::Slylandro => slylandro(work, concerns),
        ShipKind::Melnorme => melnorme(work, concerns),
        ShipKind::Utwig => utwig(work, concerns),
        ShipKind::Orz => orz(work, concerns),
        ShipKind::Chmmr => chmmr(work, concerns),
        ShipKind::UrQuan => urquan(work, concerns),
        ShipKind::KohrAh => kohr_ah(work, concerns),
        ShipKind::Vux => vux(work, concerns),
        ShipKind::Umgah => umgah(work, concerns),
        ShipKind::Supox => supox(work, concerns),
        ShipKind::Syreen => syreen(work, concerns),
        ShipKind::Mmrnmhrm => mmrnmhrm(work, concerns),
        ShipKind::ZoqFotPik => zoq_fot_pik(work, concerns),
    }
}

fn shofixti(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let work = ship_intelligence(work, concerns);
    let (flip, mut work) = coin(work, 2);
    if !special_ready(&work) {
        work.special = false;
        return work;
    }
    let ship_close = concerns.enemy.object.is_some() && concerns.enemy.which_turn <= 4;
    let weapon_hit = concerns.weapon.object.is_some_and(|el| {
        (el.flags.player_ship && work.ship.points == 1)
            || (plot_intercept(work.space, el, work.ship, 2, 0) > 0
                && el.mass >= work.ship.points
                && flip)
    });
    work.special = ship_close || weapon_hit;
    work
}

fn yehat(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    let shield = if let Some(el) = concerns.weapon.object {
        if concerns.weapon.movement == MoveState::Entice {
            if !el.flags.finite_life && !el.flags.crew_object {
                concerns.weapon.movement = MoveState::Pursue;
                0
            } else if el.mass != 0 || el.flags.crew_object {
                concerns.weapon = if el.flags.finite_life && el.mass != 0 {
                    Eval {
                        object: None,
                        movement: MoveState::NoMovement,
                        facing: 0,
                        which_turn: idiv(concerns.weapon.which_turn, 2).max(1),
                    }
                } else {
                    Eval {
                        object: Some(el),
                        movement: MoveState::Pursue,
                        facing: concerns.weapon.facing,
                        which_turn: idiv(concerns.weapon.which_turn, 2).max(1),
                    }
                };
                1
            } else {
                0
            }
        } else {
            -1
        }
    } else {
        -1
    };
    let (flip, mut work) = coin(work, 4);
    work.special = special_ready(&work) && shield != 0 && concerns.weapon.which_turn <= 2 && flip;
    if !enemy_ability(&work).immediate_weapon {
        concerns.enemy.movement = MoveState::Pursue;
    }
    ship_intelligence(work, concerns)
}

fn earthling(mut work: Work<'_>, concerns: Concerns) -> Work<'_> {
    work.special = special_ready(&work)
        && ((concerns.weapon.object.is_some() && concerns.weapon.which_turn <= 2)
            || (concerns.enemy.object.is_some() && concerns.enemy.which_turn <= 4));
    let mut without_weapon = concerns;
    without_weapon.weapon = BLANK;
    work = ship_intelligence(work, without_weapon);
    if weapon_ready(&work)
        && concerns.enemy.object.is_some()
        && ((!work.left && !work.right) || concerns.enemy.which_turn <= 12)
    {
        work.weapon = true;
    }
    work
}

fn arilou(mut work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    work.thrust = true;
    concerns.enemy.movement = MoveState::Entice;
    work = ship_intelligence(work, concerns);
    let (unlucky, mut work) = coin(work, 4);
    let jump = special_ready(&work)
        && concerns.weapon.object.is_some()
        && concerns.weapon.which_turn <= 6
        && !unlucky;
    if jump {
        work.special = true;
        work.left = false;
        work.right = false;
        work.thrust = false;
        work.weapon = false;
    } else if work.core.energy <= work.core.characteristics.special_energy_cost * 2 {
        work.special = false;
        work.weapon = false;
    } else {
        work.special = false;
    }
    work
}

fn pkunk(mut work: Work<'_>, concerns: Concerns) -> Work<'_> {
    if work.core.energy >= work.core.max_energy {
        work.special = false;
    } else if wait_n(work.core.special_wait) == 0 {
        work.special = true;
    } else {
        let (random, seed) = work.seed.next();
        work.seed = seed;
        work.special = mod_by(256, random) < 20;
    }
    ship_intelligence(work, concerns)
}

fn mycon(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    if let Some(el) = concerns.weapon.object {
        if concerns.weapon.movement == MoveState::Entice {
            concerns.weapon.movement = if el.flags.finite_life && !el.flags.crew_object {
                MoveState::Avoid
            } else {
                MoveState::Pursue
            };
        }
    }
    let mut work = ship_intelligence(work, concerns);
    if concerns.weapon.movement == MoveState::Pursue {
        work.thrust = false;
    }
    if weapon_ready(&work)
        && concerns.enemy.object.is_some()
        && (concerns.enemy.which_turn <= 16 || work.ship.points == work.core.max_crew)
        && facing_aligned(&work, concerns.enemy.object.unwrap_or(work.ship))
    {
        work.weapon = true;
    }
    work
}

fn spathi(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    if !special_ready(&work) || concerns.enemy.object.is_none() || concerns.enemy.which_turn > 24 {
        work.special = false;
        return work;
    }
    let other = concerns.enemy.object.unwrap_or(work.ship);
    let dx = trig::wrap_delta(
        other.current.location.x - work.ship.current.location.x,
        work.space.width,
    );
    let dy = trig::wrap_delta(
        other.current.location.y - work.ship.current.location.y,
        work.space.height,
    );
    let direction = angle_to_facing(trig::arctan(dx, dy));
    let rear = trig::normalize_facing(work.facing + 8);
    let cone = trig::normalize_facing(direction - rear + 4);
    work.special = cone <= 8 && concerns.enemy.which_turn <= 8;
    work
}

fn androsynth(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    let blazer = matches!(
        combatant(work.side, work.arena),
        Combatant::LiveAndrosynth(_, AndrosynthExtra::Blazer { .. })
    );
    if blazer {
        concerns.crew = BLANK;
        if let Some(el) = concerns.weapon.object {
            if concerns.weapon.movement == MoveState::Entice {
                concerns.weapon = if el.flags.finite_life && !el.flags.crew_object {
                    Eval {
                        movement: MoveState::Avoid,
                        ..concerns.weapon
                    }
                } else {
                    BLANK
                };
            }
        }
        ship_intelligence(work, concerns)
    } else {
        let close = concerns.enemy.which_turn <= 16;
        let low_energy = work.core.energy < idiv(work.core.max_energy, 3);
        if close && (!special_ready(&work) || low_energy) {
            concerns.enemy.movement = MoveState::Entice;
        }
        let mut work = ship_intelligence(work, concerns);
        let blaze = special_ready(&work)
            && ((concerns.weapon.object.is_some() && concerns.weapon.which_turn <= 4)
                || (concerns.enemy.object.is_some()
                    && work.core.energy >= idiv(work.core.max_energy, 3)
                    && concerns.enemy.which_turn < 16));
        work.special = blaze;
        if !blaze
            && weapon_ready(&work)
            && concerns.enemy.object.is_some()
            && concerns.enemy.which_turn <= 4
        {
            work.weapon = true;
        }
        work
    }
}

fn chenjesu(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    let pursue_enemy = concerns.enemy.object.is_some()
        && ((concerns.enemy.which_turn <= 16 && enemy_mi(&work) >= MEDIUM_SHIP)
            || (enemy_mi(&work) <= SLOW_SHIP
                && enemy_range(&work) >= idiv(LONG_RANGE * 3, 4)
                && enemy_ability(&work).seeking_weapon));
    if pursue_enemy {
        concerns.enemy.movement = MoveState::Pursue;
    }
    let mut work = work;
    work.special = false;
    work = ship_intelligence(work, concerns);
    work.special = wait_n(work.core.special_wait) == 1
        && concerns.weapon.object.is_some()
        && concerns.weapon.movement == MoveState::Entice
        && concerns.weapon.which_turn <= 8;
    work
}

fn ilwrath(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    let weapon_concern = concerns.weapon;
    concerns.enemy.movement = MoveState::Pursue;
    if work.core.cloaked {
        concerns.weapon = BLANK;
    }
    let mut work = ship_intelligence(work, concerns);
    let cloak = special_ready(&work)
        && !work.weapon
        && ((weapon_concern.object.is_some() && weapon_concern.which_turn <= 10)
            || !work.core.cloaked);
    work.special = cloak;
    work.weapon = (weapon_ready(&work)
        && concerns.enemy.which_turn <= 8
        && facing_aligned(&work, concerns.enemy.object.unwrap_or(work.ship)))
        || work.weapon;
    work
}

fn thraddash(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = special_ready(&work)
        && ((concerns.weapon.object.is_some() && concerns.weapon.movement == MoveState::Entice)
            || (concerns.enemy.movement == MoveState::Pursue
                && work.core.energy
                    >= work.core.characteristics.weapon_energy_cost
                        + work.core.characteristics.special_energy_cost));
    work
}

fn druuge(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    concerns.enemy.movement = MoveState::Entice;
    let mut work = ship_intelligence(work, concerns);
    let fire =
        weapon_ready(&work) && concerns.weapon.object.is_some() && concerns.weapon.which_turn <= 6;
    let sell = work.weapon && work.core.energy < work.core.characteristics.weapon_energy_cost;
    work.weapon = work.weapon || fire;
    work.special = sell;
    work
}

fn slylandro(mut work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    work.special = false;
    concerns.weapon = BLANK;
    concerns.enemy.movement = MoveState::Entice;
    work = ship_intelligence(work, concerns);
    work.weapon = true;
    work.special = false;
    work
}

fn melnorme(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = special_ready(&work)
        && work.core.energy >= work.core.characteristics.special_energy_cost
        && concerns.enemy.which_turn <= 8;
    work
}

fn utwig(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special =
        special_ready(&work) && concerns.weapon.object.is_some() && concerns.weapon.which_turn <= 4;
    work
}

fn orz(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = concerns.enemy.object.is_some()
        && special_ready(&work)
        && !work.left
        && !work.right
        && !work.weapon
        && concerns.enemy.which_turn < 24;
    work
}

fn chmmr(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special =
        special_ready(&work) && concerns.enemy.object.is_some() && concerns.enemy.which_turn <= 12;
    work
}

fn urquan(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = special_ready(&work)
        && concerns.enemy.object.is_some()
        && concerns.enemy.which_turn > 8
        && work.core.energy >= work.core.characteristics.special_energy_cost;
    work
}

fn kohr_ah(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special =
        special_ready(&work) && concerns.enemy.object.is_some() && concerns.enemy.which_turn <= 20;
    work
}

fn vux(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    concerns.enemy.movement = MoveState::Entice;
    let mut work = ship_intelligence(work, concerns);
    work.special =
        special_ready(&work) && concerns.enemy.object.is_some() && concerns.enemy.which_turn <= 10;
    work
}

fn remember(mut work: Work<'_>, distance: i64) -> Work<'_> {
    work.core.characteristics.special_wait = distance;
    work
}

fn finish_umgah(work: Work<'_>) -> Work<'_> {
    if work.special {
        work
    } else {
        remember(work, 255)
    }
}

fn umgah(work: Work<'_>, mut concerns: Concerns) -> Work<'_> {
    let previous = work.core.input;
    let weapon = concerns.weapon;
    if weapon.object.is_some() && weapon.movement == MoveState::Entice {
        if weapon.which_turn > 3 || previous.special {
            concerns.weapon = BLANK;
        } else {
            concerns.weapon.movement = if weapon
                .object
                .is_some_and(|el| el.flags.finite_life && !el.flags.crew_object)
            {
                MoveState::Avoid
            } else {
                MoveState::Pursue
            };
        }
    }
    let enemy = concerns.enemy;
    let Some(target) = enemy.object else {
        let mut work = work;
        work.range = CLOSE_RANGE;
        work = ship_intelligence(work, concerns);
        work.special = false;
        return finish_umgah(work);
    };
    if !special_ready(&work) || concerns.gravity.object.is_some() {
        let mut work = work;
        work.range = CLOSE_RANGE;
        work = ship_intelligence(work, concerns);
        work.weapon = work.weapon || enemy.which_turn < 16;
        work.special = false;
        return finish_umgah(work);
    }
    let this_turn = enemy.which_turn.min(255);
    let enough = world_to_turn(idiv(
        160 * work.core.energy,
        work.core.characteristics.special_energy_cost,
    )) > this_turn;
    let behind_angle = trig::arctan(
        target.next.location.x - work.ship.next.location.x,
        target.next.location.y - work.ship.next.location.y,
    );
    let behind = trig::normalize_angle(behind_angle - (work.facing * 4 + HALF_CIRCLE) + 10) <= 20;
    let long_approach = enough
        && (previous.special
            || behind
            || (this_turn > 6 && enemy_mi(&work) <= SLOW_SHIP)
            || (this_turn >= 16 && this_turn <= 24));
    let lined_up = work.turn_wait == 0 && previous.turn == Turn::NoTurn;
    let mut work = work;
    work.range = if long_approach {
        LONG_RANGE * 8
    } else {
        CLOSE_RANGE
    };
    work = ship_intelligence(work, concerns);
    if !long_approach {
        work.special = false;
    } else if (previous.special && this_turn <= work.core.characteristics.special_wait)
        || (!previous.special && behind && (lined_up || this_turn < 16))
    {
        work.thrust = false;
        work.special = true;
        work = remember(work, this_turn);
        if this_turn <= 8 && lined_up {
            let (left, randomized) = coin(work, 2);
            work = randomized;
            work.left = left || work.left;
            work.right = !left || work.right;
        }
    } else if previous.special {
        work.thrust = true;
        work.special = false;
        work.left = false;
        work.right = false;
    } else {
        work.thrust = false;
    }
    work.weapon = work.weapon || (this_turn < 16 && !behind);
    finish_umgah(work)
}

fn supox(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = special_ready(&work)
        && concerns.enemy.object.is_some()
        && concerns.enemy.which_turn <= 12
        && (work.left || work.right);
    work
}

fn syreen(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = special_ready(&work) && work.ship.points < work.core.max_crew - 2;
    work
}

fn mmrnmhrm(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special = special_ready(&work)
        && ((concerns.enemy.which_turn < 8 && work.range > CLOSE_RANGE)
            || (concerns.enemy.which_turn > 24 && work.range <= CLOSE_RANGE));
    work
}

fn zoq_fot_pik(work: Work<'_>, concerns: Concerns) -> Work<'_> {
    let mut work = ship_intelligence(work, concerns);
    work.special =
        special_ready(&work) && concerns.enemy.object.is_some() && concerns.enemy.which_turn <= 2;
    work.weapon = work.weapon || (weapon_ready(&work) && concerns.enemy.which_turn <= 8);
    work
}
