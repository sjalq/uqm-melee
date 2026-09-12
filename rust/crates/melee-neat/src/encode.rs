//! Observation vector shared with `tests/Neat/Encode.elm`.
//!
//! CROSS-LANGUAGE CONTRACT. `tests/Neat/Encode.elm` emits the same 103 numbers
//! in the same order from the same arena, and `tests/Mario/Dashboard/Slots.elm`
//! names them. A change here is a change to all three, plus `policy::N_OBS`,
//! `melee_mario::genome::{N_OBS, N_INPUT}` and the layout comment at the top of
//! `melee_mario::brain`. It also invalidates every stored genome and checkpoint,
//! because the input width is part of a genome's meaning.
//!
//! WHAT THIS VECTOR IS ALLOWED TO CONTAIN. Every slot must be something the
//! original cyborg (`melee_sim::cyborg`) also reads out of the arena, so that a
//! network and a cyborg can be compared on equal footing. There are exactly
//! five deliberate exceptions, each marked SUPERSET below and each justified
//! where it is emitted. Two further extras live outside this vector and are out
//! of scope here: the five previous-tick controls and the eight memory
//! channels, both appended by the policy, not by this encoder.
//!
//! WHAT IT DELIBERATELY DOES NOT REPRODUCE: the cyborg's *gating*. The cyborg
//! ignores gravity while `moved` is latched, ignores crew while the enemy is
//! near, and ignores ballistic projectiles below Awesome rating. Those gates are
//! decisions taken over facts it has already read, and every input to them is
//! itself a slot here (`turn ready`, `thrust ready`, `distance to foe`). This
//! encoder emits the facts and leaves the gating to the network, which is what
//! makes the comparison a comparison of policies rather than of eyesight.
//!
//! LAYOUT, 103 slots.
//!
//! ```text
//!   0..=10   own hull state
//!      0 energy / max_energy
//!      1 crew / max_crew
//!      2 cos(facing angle)
//!      3 sin(facing angle)
//!      4 speed / max_thrust
//!      5 cos(travel angle - facing angle)
//!      6 sin(travel angle - facing angle)
//!      7 weapon_wait <= 0
//!      8 special_wait <= 0
//!      9 turn_wait <= 0
//!     10 thrust_wait <= 0
//!  11..=15   own motion predicates
//!     11 at_limit            12 beyond_limit       13 in_gravity_well
//!     14 uses_inertia        15 ultra
//!  16..=19   own resources against the costs that actually gate abilities
//!     16 energy >= weapon_energy_cost
//!     17 energy >= special_energy_cost
//!     18 the Umgah approach budget, world_to_turn(160 * energy / special cost)
//!     19 special_wait / 64, the exact timer, not just whether it expired
//!  20        own hull mass / (2 * MAX_SHIP_MASS)
//!  21..=29   enemy geometry
//!     21 dx to foe / half arena width      22 dy to foe / half arena height
//!     23 distance to foe / LONG_RANGE      24 closing rate / 200
//!     25 cos(their facing - ours)          26 sin(their facing - ours)
//!     27 their speed / their max_thrust    28 signed facing delta to foe / 8
//!     29 foe hull mass / (2 * MAX_SHIP_MASS)
//!  30..=33   enemy visible state
//!     30 foe element cloaked               31 our own cloak
//!     32 their energy / their max_energy   SUPERSET
//!     33 their crew / their max_crew       SUPERSET
//!  34..=38   firing solutions
//!     34 our firing solution against them, the cyborg's own predicate
//!     35 our range probe closing on them, 1/(1+t)
//!     36 their firing solution against us  SUPERSET for missile hulls
//!     37 their range probe closing on us   SUPERSET for missile hulls
//!     38 their ability.immediate_weapon, which says whether 36 and 37 are
//!        the cyborg-visible case or the superset case
//!  39..=43   scalar ship comparisons
//!     39 our intel_range / LONG_RANGE      40 their intel_range / LONG_RANGE
//!     41 maneuverability(ours) / FAST_SHIP 42 maneuverability(theirs) / FAST_SHIP
//!     43 (our max_thrust - their max_thrust) / 64
//!  44..=57   ability bits, ours 44..=50 then theirs 51..=57, each in the order
//!            seeking_weapon, seeking_special, immediate_weapon, fires_fore,
//!            fires_right, fires_aft, fires_left
//!  58..=60   gravity concern
//!     58 planet dx / 4000                  59 planet dy / 4000
//!     60 1/(1+t) from the cyborg's own three-margin gravity battery
//!  61..=84   the three most urgent hostile projectiles, 8 slots each,
//!            base 61 + 8 * rank:
//!     +0 1/(1+t) of the predicted impact   +1 cos(its travel angle - our facing)
//!     +2 sin(its travel angle - our facing)
//!     +3 cos(its travel angle - its bearing to us), the cyborg's closing test
//!     +4 seeking                           +5 finite_life
//!     +6 its mass / our max_crew           +7 its remaining life / 64
//!  85..=88   crew concern
//!     85 dx / half width   86 dy / half height   87 1/(1+turns)
//!     88 our ship already targets it
//!  89..=91   neutral-body concern, the nearest parentless body (asteroids)
//!     89 dx / 4000         90 dy / 4000          91 1/(1+turns)
//!  92        constant 1.0, the last of the 93 combat sensors
//!  93..=102  hull identity, our 5-bit roster index then theirs, low bit first
//! ```
use crate::policy::N_OBS;
use melee_core::{
    idiv, trig,
    units::{Side, VelocityDesc, WorldExtent, MAX_SHIP_MASS},
};
use melee_sim::{
    battle::Arena,
    catalog::{Ability, Characteristics, ShipKind},
    cyborg,
    element::Element,
    motion,
    ship_state::CombatantCore,
};

/// Where each block starts. The layout above is normative; these names exist so
/// that the encoder, the tests and any future insertion cannot disagree about
/// where a block begins.
pub const OWN_STATE: usize = 0;
pub const OWN_MOTION: usize = 11;
pub const OWN_RESOURCES: usize = 16;
pub const OWN_MASS: usize = 20;
pub const FOE_GEOMETRY: usize = 21;
pub const FOE_STATE: usize = 30;
pub const FIRING: usize = 34;
pub const SCALARS: usize = 39;
pub const ABILITIES: usize = 44;
pub const GRAVITY: usize = 58;
pub const THREATS: usize = 61;
pub const CREW: usize = 85;
pub const EMPTY: usize = 89;
pub const CONSTANT: usize = 92;
pub const HULL_BITS: usize = 93;

/// Hostile projectiles ranked and emitted, and the width of one record.
pub const THREAT_SLOTS: usize = 3;
pub const THREAT_WIDTH: usize = 8;

/// Ability bits emitted per side, in `ability_bits` order.
pub const ABILITY_BITS: usize = 7;

/// Hull roster index bits per side.
pub const HULL_BITS_PER_SIDE: usize = 5;

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
/// Urgency of a predicted event `t` turns away. A `t` of zero means the probe
/// predicted nothing, which reads as no urgency at all rather than as maximum.
fn urgency(t: i64) -> f64 {
    if t <= 0 {
        0.0
    } else {
        1.0 / (1.0 + t as f64)
    }
}
fn ratio(numerator: i64, denominator: i64) -> f64 {
    (numerator as f64 / denominator.max(1) as f64).clamp(0.0, 1.0)
}
fn hull_mass(el: &Element) -> f64 {
    ratio(el.mass, 2 * MAX_SHIP_MASS)
}
/// The cyborg reads every displacement off `next.location` inside its concern
/// scan, so everything derived from a concern uses the same tick.
fn next_delta(space: WorldExtent, a: &Element, b: &Element) -> (i64, i64) {
    (
        trig::wrap_delta(b.next.location.x - a.next.location.x, space.width),
        trig::wrap_delta(b.next.location.y - a.next.location.y, space.height),
    )
}

fn ability_bits(ability: &Ability) -> [f64; ABILITY_BITS] {
    [
        flag(ability.seeking_weapon),
        flag(ability.seeking_special),
        flag(ability.immediate_weapon),
        flag(ability.fires_fore),
        flag(ability.fires_right),
        flag(ability.fires_aft),
        flag(ability.fires_left),
    ]
}

/// One ranked hostile projectile, in the terms the cyborg classifies it.
struct Threat {
    hit: i64,
    travel: i64,
    bearing_back: i64,
    seeking: bool,
    finite_life: bool,
    mass: i64,
    life: i64,
}

pub fn vector(side: Side, arena: &Arena) -> [f64; N_OBS] {
    let our = arena.combatants.get(side);
    let their = arena.combatants.get(side.other());
    let oc = our.core();
    let fc = their.core();
    let mut out = [0.0; N_OBS];
    hull_bits(&mut out, our.kind(), their.kind());
    out[CONSTANT] = 1.0;
    let (Some(own), Some(foe)) = (
        arena.elements.get(&oc.element.0),
        arena.elements.get(&fc.element.0),
    ) else {
        // Without both hulls in the arena there is no geometry to read; the
        // roster bits and the constant are the whole truth this tick.
        return out;
    };
    own_state(&mut out, oc, own);
    enemy(&mut out, arena, side, oc, fc, own, foe);
    scalars(&mut out, our.kind(), their.kind(), oc, fc);
    abilities(&mut out, our.kind(), their.kind());
    concerns(&mut out, arena, oc, own);
    out
}

fn hull_bits(out: &mut [f64; N_OBS], ours: ShipKind, theirs: ShipKind) {
    for i in 0..HULL_BITS_PER_SIDE {
        out[HULL_BITS + i] = ((ours.index() >> i) & 1) as f64;
        out[HULL_BITS + HULL_BITS_PER_SIDE + i] = ((theirs.index() >> i) & 1) as f64;
    }
}

fn own_state(out: &mut [f64; N_OBS], oc: &CombatantCore, own: &Element) {
    let chars: &Characteristics = &oc.characteristics;
    let face = oc.facing * 4;
    let travel = trig::normalize_angle(own.velocity.travel_angle - face);
    out[OWN_STATE..OWN_STATE + 11].copy_from_slice(&[
        ratio(oc.energy, oc.max_energy),
        ratio(own.points, oc.max_crew),
        unit(face),
        unit_s(face),
        // The cyborg has no speed scalar, but it does read the whole velocity
        // and extrapolate with it. Slots 11 and 12 carry the predicates it
        // actually branches on, which this ratio cannot express.
        (speed(&own.velocity) / chars.max_thrust.max(1) as f64).clamp(0.0, 1.0),
        unit(travel),
        unit_s(travel),
        flag(oc.weapon_wait <= 0),
        flag(oc.special_wait <= 0),
        flag(own.turn_wait <= 0),
        flag(own.thrust_wait <= 0),
    ]);
    out[OWN_MOTION..OWN_MOTION + 5].copy_from_slice(&[
        flag(motion::at_limit(&own.velocity, &oc.flags)),
        flag(motion::beyond_limit(&own.velocity, &oc.flags)),
        flag(oc.flags.in_gravity_well),
        flag(chars.thrust_increment != chars.max_thrust),
        flag(cyborg::is_ultra(chars)),
    ]);
    out[OWN_RESOURCES..OWN_RESOURCES + 4].copy_from_slice(&[
        flag(oc.energy >= chars.weapon_energy_cost),
        flag(oc.energy >= chars.special_energy_cost),
        // Umgah spends energy by the turn on its approach and compares this
        // budget against the turns to the enemy, so the quantity is a turn
        // count on the same scale as slot 23.
        ratio(
            cyborg::world_to_turn(idiv(160 * oc.energy, chars.special_energy_cost.max(1))),
            64,
        ),
        // Chenjesu fires on special_wait == 1 exactly and Umgah compares the
        // timer against a value it stashed, neither of which slot 8 can say.
        ratio(oc.special_wait.clamp(0, 64), 64),
    ]);
    // `consider_enemy` reads a hull element's raw mass and tests it against
    // MAX_SHIP_MASS to spot a transformed hull. Halving the scale keeps that
    // threshold at one half while leaving the ordinary 1..=10 range resolvable,
    // which a bare boolean would throw away.
    out[OWN_MASS] = hull_mass(own);
}

#[allow(clippy::too_many_arguments)]
fn enemy(
    out: &mut [f64; N_OBS],
    arena: &Arena,
    side: Side,
    oc: &CombatantCore,
    fc: &CombatantCore,
    own: &Element,
    foe: &Element,
) {
    let space = arena.space;
    let (dx, dy) = next_delta(space, own, foe);
    let distance = trig::square_root(dx * dx + dy * dy);
    let face = oc.facing * 4;
    let relative = trig::normalize_angle(fc.facing * 4 - face);
    // The cyborg holds no closing scalar, only the positions it re-extrapolates.
    // This is a one-slot summary of that same geometry, kept because it is cheap
    // and well conditioned, not because the cyborg computes it.
    let closing = ((foe.velocity.vector.width - own.velocity.vector.width) * dx
        + (foe.velocity.vector.height - own.velocity.vector.height) * dy) as f64
        / distance.max(1) as f64;
    let turn = trig::normalize_facing(trig::angle_to_facing(trig::arctan(dx, dy)) - oc.facing);
    let turn = if turn > 8 { turn - 16 } else { turn };
    out[FOE_GEOMETRY..FOE_GEOMETRY + 9].copy_from_slice(&[
        (dx as f64 / (space.width as f64 / 2.0)).clamp(-1.0, 1.0),
        (dy as f64 / (space.height as f64 / 2.0)).clamp(-1.0, 1.0),
        (distance as f64 / cyborg::LONG_RANGE as f64).clamp(0.0, 1.0),
        (closing / 200.0).clamp(-1.0, 1.0),
        unit(relative),
        unit_s(relative),
        (speed(&foe.velocity) / fc.characteristics.max_thrust.max(1) as f64).clamp(0.0, 1.0),
        (turn as f64 / 8.0).clamp(-1.0, 1.0),
        hull_mass(foe),
    ]);
    out[FOE_STATE..FOE_STATE + 4].copy_from_slice(&[
        flag(foe.prim.object_cloaked()),
        flag(oc.cloaked),
        // SUPERSET. `consider_enemy` clones the opponent's core but consumes
        // only its weapon_wait, ability, range and facing; the opponent's energy
        // is read nowhere in cyborg.rs. Kept deliberately: knowing when a Chmmr
        // laser or an Ur-Quan fighter launch has become affordable is exactly
        // the judgement the cyborg lacks and a policy should be free to learn.
        ratio(fc.energy, fc.max_energy),
        // SUPERSET. The opponent's element is read for mass, position, velocity,
        // flags and prim, never for `points`. Kept for the same reason: knowing
        // the opponent is one hit from death is a real tactical fact, and
        // withholding it would cap the policy at the cyborg's blind spots.
        ratio(foe.points, fc.max_crew),
    ]);
    let their_ability = arena.combatants.get(side.other()).kind().stock().ability;
    out[FIRING..FIRING + 5].copy_from_slice(&[
        flag(cyborg::firing_solution(arena, side, foe, 0)),
        urgency(cyborg::range_probe(
            space,
            own,
            foe,
            arena.combatants.get(side).kind().intel_range(),
        )),
        // SUPERSET, conditionally. `consider_enemy` runs this same probe from
        // the opponent's seat only when their ability is immediate_weapon; for a
        // missile hull the cyborg gets no warning until the missile exists as an
        // element. Kept because dropping it would hand every missile hull an
        // unearned advantage over the network. Slot 38 tells the network which
        // of the two cases it is looking at.
        flag(cyborg::firing_solution(arena, side.other(), own, 0)),
        urgency(cyborg::range_probe(
            space,
            foe,
            own,
            arena.combatants.get(side.other()).kind().intel_range(),
        )),
        flag(their_ability.immediate_weapon),
    ]);
}

fn scalars(
    out: &mut [f64; N_OBS],
    ours: ShipKind,
    theirs: ShipKind,
    oc: &CombatantCore,
    fc: &CombatantCore,
) {
    out[SCALARS..SCALARS + 5].copy_from_slice(&[
        ratio(ours.intel_range(), cyborg::LONG_RANGE),
        ratio(theirs.intel_range(), cyborg::LONG_RANGE),
        ratio(
            cyborg::maneuverability(&oc.characteristics),
            cyborg::FAST_SHIP,
        ),
        ratio(
            cyborg::maneuverability(&fc.characteristics),
            cyborg::FAST_SHIP,
        ),
        // Slots 4 and 27 normalise each side's speed by its own maximum, which
        // destroys the raw comparison `consider_enemy` and `entice_target` make.
        // This restores it.
        ((oc.characteristics.max_thrust - fc.characteristics.max_thrust) as f64 / 64.0)
            .clamp(-1.0, 1.0),
    ]);
}

fn abilities(out: &mut [f64; N_OBS], ours: ShipKind, theirs: ShipKind) {
    // Only the seven the cyborg branches on. point_defense, crew_immune,
    // shield_defense and dont_chase appear nowhere in cyborg.rs, so they are
    // not this network's to see.
    out[ABILITIES..ABILITIES + ABILITY_BITS].copy_from_slice(&ability_bits(&ours.stock().ability));
    out[ABILITIES + ABILITY_BITS..ABILITIES + 2 * ABILITY_BITS]
        .copy_from_slice(&ability_bits(&theirs.stock().ability));
}

/// One pass over the arena applying the cyborg's own `consider` dispatch, then
/// the gravity, threat, crew and empty blocks it feeds.
fn concerns(out: &mut [f64; N_OBS], arena: &Arena, oc: &CombatantCore, own: &Element) {
    let space = arena.space;
    if !cyborg::colliding(*own) {
        return;
    }
    let mut planet: Option<&Element> = None;
    let mut empty: Option<(i64, &Element)> = None;
    let mut crew: Option<(i64, &Element)> = None;
    let mut threats: Vec<(i64, i64, Threat)> = Vec::new();
    for el in arena.elements.values() {
        if el.id == own.id || !cyborg::colliding(*el) {
            continue;
        }
        let (dx, dy) = next_delta(space, own, el);
        let turns = cyborg::world_to_turn(trig::square_root(dx * dx + dy * dy));
        if cyborg::is_gravity(*el) {
            // The last qualifying body wins, as it does in `fill_concerns`.
            planet = Some(el);
        } else if el.flags.player_ship {
            // The enemy hull already has its own block.
        } else if cyborg::is_crew(*el) {
            // `consider`'s chain tests `parent.is_none()` before it tests
            // `is_crew`, and every crew object this simulation makes is
            // parentless, so the cyborg's own crew concern can never fire: the
            // object falls into `consider_empty`, which drops it for being
            // finite_life. The cyborg still measures the object's displacement
            // on the way there, so the fact is one it holds. Classify by the
            // predicate, not by the order, and the network can see it.
            if crew.is_none_or(|(best, _)| turns < best) {
                crew = Some((turns, el));
            }
        } else if el.parent.is_none() {
            // `consider_empty` narrows this to bodies that are not finite_life,
            // and every asteroid this simulation spawns IS finite_life, so the
            // cyborg's empty concern never fires here either. `consider`
            // measures the displacement of every colliding element before it
            // dispatches, so the fact is the cyborg's; the narrowing is its
            // policy. A drifting rock is a real hazard and the network sees it.
            if empty.is_none_or(|(best, _)| turns < best) {
                empty = Some((turns, el));
            }
        } else if el.parent != own.parent && cyborg::life_span(*el) > 0 {
            threats.push((turns, el.id.0, threat_of(arena, space, own, el, dx, dy)));
        }
    }
    gravity(out, space, oc, own, planet);
    rank_threats(out, oc, threats);
    if let Some((turns, el)) = crew {
        let (dx, dy) = next_delta(space, own, el);
        out[CREW..CREW + 4].copy_from_slice(&[
            (dx as f64 / (space.width as f64 / 2.0)).clamp(-1.0, 1.0),
            (dy as f64 / (space.height as f64 / 2.0)).clamp(-1.0, 1.0),
            urgency(turns.max(1)),
            flag(own.target == Some(el.id)),
        ]);
    }
    if let Some((turns, el)) = empty {
        let (dx, dy) = next_delta(space, own, el);
        out[EMPTY..EMPTY + 3].copy_from_slice(&[
            (dx as f64 / 4000.0).clamp(-1.0, 1.0),
            (dy as f64 / 4000.0).clamp(-1.0, 1.0),
            urgency(turns.max(1)),
        ]);
    }
}

fn gravity(
    out: &mut [f64; N_OBS],
    space: WorldExtent,
    oc: &CombatantCore,
    own: &Element,
    planet: Option<&Element>,
) {
    let Some(planet) = planet else {
        return;
    };
    let (dx, dy) = next_delta(space, own, planet);
    out[GRAVITY..GRAVITY + 3].copy_from_slice(&[
        (dx as f64 / 4000.0).clamp(-1.0, 1.0),
        (dy as f64 / 4000.0).clamp(-1.0, 1.0),
        urgency(cyborg::gravity_intercept(
            space,
            planet,
            own,
            &oc.characteristics,
        )),
    ]);
}

#[allow(clippy::too_many_arguments)]
fn threat_of(
    arena: &Arena,
    space: WorldExtent,
    own: &Element,
    el: &Element,
    dx: i64,
    dy: i64,
) -> Threat {
    let ability = el
        .parent
        .map(|side| arena.combatants.get(side).kind().stock().ability)
        // `consider_weapon`'s own fallback for a parentless projectile.
        .unwrap_or(ShipKind::Shofixti.stock().ability);
    Threat {
        // `consider_weapon`'s Awesome branch: the projectile coasted against us
        // over its own remaining life, at the cyborg's 40-display-unit margin.
        hit: cyborg::plot_intercept(
            space,
            el,
            own,
            cyborg::life_span(*el),
            cyborg::display_to_world(40),
        ),
        travel: el.velocity.travel_angle,
        bearing_back: trig::arctan(-dx, -dy),
        seeking: (ability.seeking_weapon && !cyborg::is_special_body(el.body))
            || (ability.seeking_special && cyborg::is_special_body(el.body)),
        finite_life: el.flags.finite_life,
        mass: el.mass,
        life: cyborg::life_span(*el),
    }
}

fn rank_threats(out: &mut [f64; N_OBS], oc: &CombatantCore, mut threats: Vec<(i64, i64, Threat)>) {
    // The cyborg keeps the soonest predicted impact, not the nearest object, so
    // that is the primary key. Projectiles with no predicted impact sort after
    // every one that has an impact, and among themselves by the distance the
    // seeking branch measures in turns. Element id breaks the last tie so the
    // order is a function of the arena alone.
    threats.sort_by_key(|(turns, id, t)| (t.hit <= 0, t.hit, *turns, *id));
    let face = oc.facing * 4;
    for (rank, (_, _, t)) in threats.iter().take(THREAT_SLOTS).enumerate() {
        let base = THREATS + rank * THREAT_WIDTH;
        let relative = trig::normalize_angle(t.travel - face);
        let closing = trig::normalize_angle(t.travel - t.bearing_back);
        out[base..base + THREAT_WIDTH].copy_from_slice(&[
            urgency(t.hit),
            unit(relative),
            unit_s(relative),
            unit(closing),
            flag(t.seeking),
            flag(t.finite_life),
            // Projectile mass is its damage, which Shofixti weighs against its
            // own remaining crew.
            ratio(t.mass, oc.max_crew),
            ratio(t.life.clamp(0, 64), 64),
        ]);
    }
}

/// Short names for the slots, in layout order, so a topology diagram can say
/// what a link actually reads. Kept here beside the layout rather than copied
/// into the dashboard, so a slot cannot be renumbered without being renamed.
/// `tests/Mario/Dashboard/Slots.elm` carries the same names plus the longer
/// explanations the tooltips show.
pub fn slot_names() -> Vec<String> {
    const FIXED: [&str; GRAVITY] = [
        "our energy",
        "our crew",
        "facing cos",
        "facing sin",
        "our speed",
        "drift cos",
        "drift sin",
        "weapon ready",
        "special ready",
        "turn ready",
        "thrust ready",
        "at limit",
        "beyond limit",
        "in gravity",
        "uses inertia",
        "ultra",
        "can pay weapon",
        "can pay special",
        "approach fuel",
        "special timer",
        "our hull mass",
        "foe dx",
        "foe dy",
        "foe range",
        "closing rate",
        "foe facing cos",
        "foe facing sin",
        "foe speed",
        "aim error",
        "foe hull mass",
        "foe cloak",
        "we cloak",
        "foe energy",
        "foe crew",
        "we can fire",
        "we close in",
        "they can fire",
        "they close in",
        "they hit instantly",
        "our range",
        "their range",
        "our agility",
        "their agility",
        "thrust edge",
        "us seek wpn",
        "us seek spec",
        "us instant wpn",
        "us fire fore",
        "us fire right",
        "us fire aft",
        "us fire left",
        "them seek wpn",
        "them seek spec",
        "them instant wpn",
        "them fire fore",
        "them fire right",
        "them fire aft",
        "them fire left",
    ];
    const THREAT_FIELDS: [&str; THREAT_WIDTH] = [
        "urgency",
        "travel cos",
        "travel sin",
        "closing",
        "seeking",
        "finite life",
        "damage",
        "life left",
    ];
    let mut names: Vec<String> = FIXED.iter().map(|s| s.to_string()).collect();
    for name in ["planet dx", "planet dy", "planet impact"] {
        names.push(name.to_string());
    }
    for rank in 0..THREAT_SLOTS {
        for field in THREAT_FIELDS {
            names.push(format!("threat {rank} {field}"));
        }
    }
    for name in [
        "crew dx",
        "crew dy",
        "crew urgency",
        "crew targeted",
        "rock dx",
        "rock dy",
        "rock urgency",
        "constant one",
    ] {
        names.push(name.to_string());
    }
    for bit in 0..HULL_BITS_PER_SIDE {
        names.push(format!("our hull bit {bit}"));
    }
    for bit in 0..HULL_BITS_PER_SIDE {
        names.push(format!("their hull bit {bit}"));
    }
    names
}

/// Only for the layout test: the pieces of arena state slot `index` is built
/// from, named so a slot cannot silently start reading something else.
pub fn provenance(index: usize) -> &'static str {
    match index {
        0..=10 => "own core and own element, read by cyborg::decide",
        11..=15 => "motion::at_limit, motion::beyond_limit, MotionFlags, Characteristics",
        16..=19 => "own energy and Characteristics costs, own special_wait",
        20 => "own element mass, the field consider_enemy tests against MAX_SHIP_MASS",
        21..=29 => "both hull elements' next.location, velocity, facing and mass",
        30..=31 => "foe element prim, own core cloaked",
        32..=33 => "SUPERSET: foe core energy and foe element points",
        34..=35 => "cyborg::firing_solution and cyborg::range_probe from our seat",
        36..=37 => "SUPERSET: the same two probes from the opponent's seat",
        38 => "their ShipKind stock ability",
        39..=43 => "both ShipKind intel_range, cyborg::maneuverability, max_thrust",
        44..=57 => "both ShipKind stock abilities, the seven bits cyborg branches on",
        58..=60 => "the gravity body's next.location and cyborg::gravity_intercept",
        61..=84 => "hostile projectile elements ranked by cyborg::plot_intercept",
        85..=88 => "the nearest crew element and our element's target",
        89..=91 => "the nearest parentless neutral element, an asteroid or debris",
        92 => "SUPERSET: the constant 1.0, a second bias path, not arena state",
        93..=102 => "both ShipKind roster indices",
        _ => "out of range",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use melee_core::rng::Seed;
    use melee_core::units::Sided;
    use melee_sim::catalog::ALL_SHIPS;
    use melee_sim::init;
    use melee_sim::input::{BattleInput, CyborgRating};
    use melee_sim::step;

    /// Every fixed arena the layout test and the bounds test share: a handful of
    /// ordered pairs, each stepped by two Awesome cyborgs so that projectiles,
    /// crew and gravity all actually occur.
    fn arenas() -> Vec<Arena> {
        let mut out = Vec::new();
        for (bottom, top, seed) in [
            (ShipKind::Chenjesu, ShipKind::Earthling, 7),
            (ShipKind::Shofixti, ShipKind::Syreen, 1234),
            (ShipKind::Umgah, ShipKind::Chmmr, 99),
            (ShipKind::Mycon, ShipKind::Androsynth, 5),
            (ShipKind::Slylandro, ShipKind::Utwig, 4242),
            // Ilwrath is the only hull that cloaks, so without it the two cloak
            // slots are never exercised.
            (ShipKind::Ilwrath, ShipKind::Vux, 808),
            // Pkunk is the only hull that fires right and left and Spathi the
            // only one that fires aft, so without this pair three ability bits
            // are never set on either side.
            (ShipKind::Pkunk, ShipKind::Spathi, 606),
        ] {
            let mut arena = init::arena(bottom, top, Seed(seed));
            for frame in 0..600 {
                // Once a hull has left the arena the round is over and every
                // later sample is the degenerate one-ship case, which
                // `a_missing_hull_leaves_only_identity_and_the_constant` covers
                // on its own.
                if [Side::Bottom, Side::Top].iter().any(|s| {
                    !arena
                        .elements
                        .contains_key(&arena.combatants.get(*s).core().element.0)
                }) {
                    break;
                }
                if frame % 5 == 0 {
                    out.push(arena.clone());
                }
                let mut inputs = Sided::both(BattleInput::default());
                for side in [Side::Bottom, Side::Top] {
                    inputs.set(
                        side,
                        melee_sim::cyborg::pilot(CyborgRating::AwesomeCyborg, side, &mut arena),
                    );
                }
                step::tick_authoritative(inputs, &mut arena);
            }
        }
        out
    }

    #[test]
    fn every_slot_has_a_distinct_name_in_layout_order() {
        let names = slot_names();
        assert_eq!(
            names.len(),
            N_OBS,
            "the name table lost step with the layout"
        );
        let mut sorted = names.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), N_OBS, "two slots share a name");
        assert_eq!(names[CONSTANT], "constant one");
        assert_eq!(names[HULL_BITS], "our hull bit 0");
        assert_eq!(names[THREATS], "threat 0 urgency");
        assert_eq!(names[THREATS + THREAT_WIDTH], "threat 1 urgency");
    }

    #[test]
    fn the_blocks_tile_the_vector_exactly_once_in_the_documented_order() {
        let bounds = [
            (OWN_STATE, 11),
            (OWN_MOTION, 5),
            (OWN_RESOURCES, 4),
            (OWN_MASS, 1),
            (FOE_GEOMETRY, 9),
            (FOE_STATE, 4),
            (FIRING, 5),
            (SCALARS, 5),
            (ABILITIES, 2 * ABILITY_BITS),
            (GRAVITY, 3),
            (THREATS, THREAT_SLOTS * THREAT_WIDTH),
            (CREW, 4),
            (EMPTY, 3),
            (CONSTANT, 1),
            (HULL_BITS, 2 * HULL_BITS_PER_SIDE),
        ];
        let mut next = 0;
        for (start, width) in bounds {
            assert_eq!(
                start, next,
                "block at {start} does not abut its predecessor"
            );
            next = start + width;
        }
        assert_eq!(next, N_OBS, "the blocks do not tile all {N_OBS} slots");
        for index in 0..N_OBS {
            assert_ne!(
                provenance(index),
                "out of range",
                "slot {index} has no recorded provenance"
            );
        }
    }

    /// Every slot must be justifiable as something the cyborg also reads, and
    /// the five exceptions must be exactly the five we chose to grant. This is
    /// what stops the vector quietly regrowing an advantage.
    #[test]
    fn only_the_five_declared_slots_exceed_what_the_cyborg_reads() {
        let superset: Vec<usize> = (0..N_OBS)
            .filter(|i| provenance(*i).starts_with("SUPERSET"))
            .collect();
        assert_eq!(
            superset,
            vec![32, 33, 36, 37, CONSTANT],
            "the set of slots that exceed the cyborg changed"
        );
    }

    #[test]
    fn every_slot_is_finite_and_inside_its_declared_range() {
        let mut seen_nonzero = [false; N_OBS];
        let mut count = 0;
        for arena in arenas() {
            for side in [Side::Bottom, Side::Top] {
                let v = vector(side, &arena);
                count += 1;
                for (index, x) in v.iter().enumerate() {
                    assert!(x.is_finite(), "slot {index} is not finite");
                    assert!(
                        (-1.0..=1.0).contains(x),
                        "slot {index} left [-1, 1] with {x}"
                    );
                    if *x != 0.0 {
                        seen_nonzero[index] = true;
                    }
                }
                assert_eq!(v[CONSTANT], 1.0, "the constant slot must always be one");
            }
        }
        assert!(count > 50, "the fixture produced too few observations");
        // A slot that is zero in every fixture is either dead or misplaced.
        // Two honest exceptions:
        //
        //   * the hull bits, where a roster index simply may not have a given
        //     bit set for the six pairs above;
        //   * slot 30, the opponent hull's cloaked prim. `ship_intelligence`
        //     widens its aiming margin on exactly this test, but nothing in
        //     this simulation ever gives a hull a cloaked prim: a ship's prim
        //     is a Stamp for its whole life, and Ilwrath's cloak is carried on
        //     `core.cloaked` (slot 31) instead. The slot stays because it is
        //     the cyborg's own read and because the day the port sets that prim
        //     the network must see it; it is dormant, not wrong;
        //   * slot 88, whether our hull already targets the crew object.
        //     `consider_crew` is the only reader of an element's `target`, and
        //     nothing in this simulation ever writes a hull element's `target`,
        //     so it reads None for the whole round. Dormant for the same reason
        //     and kept for the same reason.
        for index in 0..N_OBS {
            if (HULL_BITS..HULL_BITS + 2 * HULL_BITS_PER_SIDE).contains(&index)
                || index == FOE_STATE
                || index == CREW + 3
            {
                continue;
            }
            assert!(
                seen_nonzero[index],
                "slot {index} ({}) was zero in every fixture arena",
                provenance(index)
            );
        }
    }

    /// The threat block must be ordered by predicted impact, not by distance,
    /// and the two must actually disagree somewhere in the fixtures or the
    /// assertion proves nothing.
    #[test]
    fn threats_rank_by_predicted_impact_rather_than_distance() {
        let mut disagreed = 0;
        let mut ranked = 0;
        for arena in arenas() {
            for side in [Side::Bottom, Side::Top] {
                let our = arena.combatants.get(side);
                let Some(own) = arena.elements.get(&our.core().element.0) else {
                    continue;
                };
                if !cyborg::colliding(*own) {
                    continue;
                }
                let mut scored: Vec<(i64, i64, i64)> = Vec::new();
                for el in arena.elements.values() {
                    if el.id == own.id
                        || !cyborg::colliding(*el)
                        || cyborg::is_gravity(*el)
                        || el.flags.player_ship
                        || el.parent.is_none()
                        || el.parent == own.parent
                        || cyborg::is_crew(*el)
                        || cyborg::life_span(*el) <= 0
                    {
                        continue;
                    }
                    let (dx, dy) = next_delta(arena.space, own, el);
                    let hit = cyborg::plot_intercept(
                        arena.space,
                        el,
                        own,
                        cyborg::life_span(*el),
                        cyborg::display_to_world(40),
                    );
                    scored.push((hit, dx * dx + dy * dy, el.id.0));
                }
                if scored.len() < 2 {
                    continue;
                }
                ranked += 1;
                let mut by_impact = scored.clone();
                by_impact.sort_by_key(|(hit, d2, id)| (*hit <= 0, *hit, *d2, *id));
                let mut by_distance = scored.clone();
                by_distance.sort_by_key(|(_, d2, id)| (*d2, *id));
                if by_impact[0].2 != by_distance[0].2 {
                    disagreed += 1;
                    let v = vector(side, &arena);
                    let expected = urgency(by_impact[0].0);
                    assert_eq!(
                        v[THREATS], expected,
                        "threat 0 did not come from the soonest predicted impact"
                    );
                }
            }
        }
        assert!(ranked > 0, "no fixture ever held two hostile projectiles");
        assert!(
            disagreed > 0,
            "impact order and distance order never disagreed, so the check is vacuous"
        );
    }

    /// The seat's own firing slot must agree with the cyborg's own predicate,
    /// hull by hull, rather than with a local restatement of it.
    #[test]
    fn the_firing_slot_is_the_cyborgs_own_predicate() {
        let mut asserted = 0;
        let mut fired = 0;
        for kind in ALL_SHIPS {
            let mut arena = init::arena(kind, ShipKind::Earthling, Seed(31));
            for _ in 0..300 {
                for side in [Side::Bottom, Side::Top] {
                    let our = arena.combatants.get(side);
                    let their = arena.combatants.get(side.other());
                    let (Some(own), Some(foe)) = (
                        arena.elements.get(&our.core().element.0),
                        arena.elements.get(&their.core().element.0),
                    ) else {
                        continue;
                    };
                    let expected = flag(cyborg::firing_solution(&arena, side, foe, 0));
                    let v = vector(side, &arena);
                    assert_eq!(v[FIRING], expected, "{kind:?} firing slot disagreed");
                    assert_eq!(
                        v[FIRING + 1],
                        urgency(cyborg::range_probe(
                            arena.space,
                            own,
                            foe,
                            our.kind().intel_range()
                        )),
                        "{kind:?} range probe slot disagreed"
                    );
                    asserted += 1;
                    if expected > 0.0 {
                        fired += 1;
                    }
                }
                let mut inputs = Sided::both(BattleInput::default());
                for side in [Side::Bottom, Side::Top] {
                    inputs.set(
                        side,
                        melee_sim::cyborg::pilot(CyborgRating::AwesomeCyborg, side, &mut arena),
                    );
                }
                step::tick_authoritative(inputs, &mut arena);
            }
        }
        assert!(asserted > 0, "no seat was ever checked");
        assert!(
            fired > 0,
            "the firing predicate was false everywhere, so agreement proves nothing"
        );
    }

    /// A missing hull must not produce a half-filled vector: the roster bits and
    /// the constant are all that survive, and nothing else may be non-zero.
    #[test]
    fn a_missing_hull_leaves_only_identity_and_the_constant() {
        let mut arena = init::arena(ShipKind::Pkunk, ShipKind::Umgah, Seed(3));
        let id = arena.combatants.get(Side::Bottom).core().element.0;
        arena.elements.remove(&id);
        let v = vector(Side::Bottom, &arena);
        for (index, x) in v.iter().enumerate() {
            let identity = (HULL_BITS..HULL_BITS + 2 * HULL_BITS_PER_SIDE).contains(&index);
            if identity || index == CONSTANT {
                continue;
            }
            assert_eq!(*x, 0.0, "slot {index} survived a missing hull");
        }
        assert_eq!(v[CONSTANT], 1.0);
    }
}
