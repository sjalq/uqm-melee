//! Observation vector shared with `tests/Neat/Encode.elm`.
use crate::policy::N_OBS;
use melee_core::{
    trig,
    units::{Side, VelocityDesc, WorldExtent, WorldPoint},
    velocity,
};
use melee_sim::{
    arsenal,
    battle::Arena,
    catalog::Weapon,
    element::{Body, Element},
    ship_state::Combatant,
};

fn flag(b: bool) -> f64 {
    if b {
        1.0
    } else {
        0.0
    }
}
fn unit(a: i64) -> f64 {
    trig::cosine(a, 100) as f64 / 100.0
}
fn unit_s(a: i64) -> f64 {
    trig::sine(a, 100) as f64 / 100.0
}
fn speed(v: &VelocityDesc) -> f64 {
    trig::square_root(v.vector.width * v.vector.width + v.vector.height * v.vector.height) as f64
}
fn delta(space: WorldExtent, a: &Element, b: &Element) -> (i64, i64) {
    (
        trig::wrap_delta(b.current.location.x - a.current.location.x, space.width),
        trig::wrap_delta(b.current.location.y - a.current.location.y, space.height),
    )
}

pub fn vector(side: Side, arena: &Arena) -> [f64; N_OBS] {
    let our = arena.combatants.get(side);
    let their = arena.combatants.get(side.other());
    let oc = our.core();
    let fc = their.core();
    let mut out = [0.0; N_OBS];
    for i in 0..5 {
        out[33 + i] = ((our.kind().index() >> i) & 1) as f64;
        out[38 + i] = ((their.kind().index() >> i) & 1) as f64;
    }
    let (Some(own), Some(foe)) = (
        arena.elements.get(&oc.element.0),
        arena.elements.get(&fc.element.0),
    ) else {
        return out;
    };
    let (dx, dy) = delta(arena.space, own, foe);
    let distance = trig::square_root(dx * dx + dy * dy);
    let face = oc.facing * 4;
    let relative = trig::normalize_angle(fc.facing * 4 - face);
    let travel = trig::normalize_angle(own.velocity.travel_angle - face);
    let closing = ((foe.velocity.vector.width - own.velocity.vector.width) * dx
        + (foe.velocity.vector.height - own.velocity.vector.height) * dy) as f64
        / distance.max(1) as f64;
    let (my_now, my_soon) = hit_hints(arena, our, own, oc.facing, foe);
    let (their_now, their_soon) = hit_hints(arena, their, foe, fc.facing, own);
    let turn = trig::normalize_facing(trig::angle_to_facing(trig::arctan(dx, dy)) - oc.facing);
    let turn = if turn > 8 { turn - 16 } else { turn };
    let (pdx, pdy, phit) = planet_vec(arena, own);
    let (sh, sc, ss) = incoming(arena, side, own);
    out[..33].copy_from_slice(&[
        (oc.energy as f64 / oc.max_energy.max(1) as f64).clamp(0.0, 1.0),
        (own.points as f64 / oc.max_crew.max(1) as f64).clamp(0.0, 1.0),
        unit(face),
        unit_s(face),
        (speed(&own.velocity) / oc.characteristics.max_thrust.max(1) as f64).clamp(0.0, 1.0),
        unit(travel),
        unit_s(travel),
        flag(oc.weapon_wait <= 0),
        flag(oc.special_wait <= 0),
        flag(own.turn_wait <= 0),
        flag(own.thrust_wait <= 0),
        (dx as f64 / (arena.space.width as f64 / 2.0)).clamp(-1.0, 1.0),
        (dy as f64 / (arena.space.height as f64 / 2.0)).clamp(-1.0, 1.0),
        (distance as f64 / 4000.0).clamp(0.0, 1.0),
        (closing / 200.0).clamp(-1.0, 1.0),
        unit(relative),
        unit_s(relative),
        (fc.energy as f64 / fc.max_energy.max(1) as f64).clamp(0.0, 1.0),
        (foe.points as f64 / fc.max_crew.max(1) as f64).clamp(0.0, 1.0),
        (speed(&foe.velocity) / fc.characteristics.max_thrust.max(1) as f64).clamp(0.0, 1.0),
        flag(oc.cloaked),
        my_now,
        my_soon,
        (turn as f64 / 8.0).clamp(-1.0, 1.0),
        their_now,
        their_soon,
        pdx,
        pdy,
        phit,
        sh,
        sc,
        ss,
        1.0,
    ]);
    out
}

fn hit_hints(
    arena: &Arena,
    ship: &Combatant,
    origin: &Element,
    facing: i64,
    target: &Element,
) -> (f64, f64) {
    match arsenal::primary(ship) {
        Weapon::Missile(kind) => {
            let spec = kind.spec();
            let mut best = 0;
            for mount in spec.mounts() {
                let f = (facing + mount.facing_offset).rem_euclid(16);
                let launch = arsenal::launch_state(
                    spec,
                    f,
                    &origin.velocity,
                    arsenal::mount_position(spec, facing, origin.current.location, mount),
                );
                let mut ghost = *origin;
                ghost.current.location = launch.position;
                ghost.current.frame_index = facing;
                ghost.velocity = launch.velocity;
                ghost.flags.player_ship = false;
                let t = plot_intercept(arena.space, &ghost, target, spec.life, 0);
                if t > 0 && (best == 0 || t < best) {
                    best = t;
                }
            }
            if best <= 0 {
                (0.0, 0.0)
            } else {
                (1.0 / (1.0 + best as f64), flag(best <= spec.life))
            }
        }
        _ => {
            let (dx, dy) = delta(arena.space, origin, target);
            let dist = trig::square_root(dx * dx + dy * dy);
            let d = trig::normalize_facing(trig::angle_to_facing(trig::arctan(dx, dy)) - facing);
            let lined = flag(dist <= ship.kind().intel_range() && (d <= 2 || d >= 14));
            (lined, lined)
        }
    }
}

fn plot_intercept(
    space: WorldExtent,
    a: &Element,
    b: &Element,
    max_turns: i64,
    margin: i64,
) -> i64 {
    for t in 1..=max_turns {
        let ((ax, ay), _) = velocity::get_next(t, &a.velocity);
        let ((bx, by), _) = velocity::get_next(t, &b.velocity);
        let pa = trig::wrap_point(
            space,
            WorldPoint {
                x: a.current.location.x + ax,
                y: a.current.location.y + ay,
            },
        );
        let pb = trig::wrap_point(
            space,
            WorldPoint {
                x: b.current.location.x + bx,
                y: b.current.location.y + by,
            },
        );
        let dx = trig::wrap_delta(pa.x - pb.x, space.width);
        let dy = trig::wrap_delta(pa.y - pb.y, space.height);
        let r = 80 + margin;
        if dx * dx + dy * dy <= r * r {
            return t;
        }
    }
    0
}

fn planet_vec(arena: &Arena, own: &Element) -> (f64, f64, f64) {
    match arena
        .elements
        .values()
        .rev()
        .find(|e| e.body == Body::Planet)
    {
        None => (0.0, 0.0, 0.0),
        Some(p) => {
            let (dx, dy) = delta(arena.space, own, p);
            let hit = plot_intercept(arena.space, own, p, 32, 160);
            (
                (dx as f64 / 4000.0).clamp(-1.0, 1.0),
                (dy as f64 / 4000.0).clamp(-1.0, 1.0),
                if hit <= 0 {
                    0.0
                } else {
                    1.0 / (1.0 + hit as f64)
                },
            )
        }
    }
}

fn incoming(arena: &Arena, side: Side, own: &Element) -> (f64, f64, f64) {
    let mut best: Option<(&Element, i64, i64, i64)> = None;
    for el in arena.elements.values() {
        if el.flags.player_ship
            || el.flags.nonsolid
            || el.parent == Some(side)
            || el.parent.is_none()
        {
            continue;
        }
        let (dx, dy) = delta(arena.space, own, el);
        let d2 = dx * dx + dy * dy;
        if best.as_ref().is_none_or(|b| d2 < b.1) {
            best = Some((el, d2, dx, dy));
        }
    }
    match best {
        None => (0.0, 0.0, 0.0),
        Some((el, _, dx, dy)) => {
            let hit = plot_intercept(arena.space, el, own, 16, 40);
            let a = trig::arctan(dx, dy);
            (
                if hit <= 0 {
                    0.0
                } else {
                    1.0 / (1.0 + hit as f64)
                },
                unit(a),
                unit_s(a),
            )
        }
    }
}
