//! Observation vector shared with `tests/Neat/Encode.elm`.
//!
//! CROSS-LANGUAGE CONTRACT. `tests/Neat/Encode.elm` emits the same 127 numbers
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
//! LAYOUT, 127 slots.
//!
//! One rule shapes every block that describes a moving object: the cyborg
//! extrapolates with a whole velocity and steers off a whole bearing, so every
//! object a block describes carries its direction of travel as a cosine and a
//! sine, its speed, and its bearing relative to our own facing. A block that
//! emitted only a magnitude or only a cosine would leave the network unable to
//! tell two mirror-image situations apart, which is the one distinction the
//! cyborg's own dodging and leading are built from.
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
//!  16..=20   own resources against the costs that actually gate abilities
//!     16 energy >= weapon_energy_cost
//!     17 energy >= special_energy_cost
//!     18 the Umgah approach budget, world_to_turn(160 * energy / special cost)
//!     19 core special_wait / 64, the live timer, not just whether it expired
//!     20 characteristics special_wait / 64, the reload constant, which is also
//!        the slot Umgah overwrites with the approach distance it stashes
//!  21        own hull mass / (2 * MAX_SHIP_MASS)
//!  22..=32   enemy geometry
//!     22 dx to foe / half arena width      23 dy to foe / half arena height
//!     24 distance to foe / LONG_RANGE      25 closing rate / 200
//!     26 cos(their facing - ours)          27 sin(their facing - ours)
//!     28 their speed / their max_thrust
//!     29 cos(their travel angle - our facing)
//!     30 sin(their travel angle - our facing)
//!     31 signed facing delta to foe / 8
//!     32 foe hull mass / (2 * MAX_SHIP_MASS)
//!  33..=36   enemy visible state
//!     33 foe element cloaked               34 our own cloak
//!     35 their energy / their max_energy   SUPERSET
//!     36 their crew / their max_crew       SUPERSET
//!  37..=41   firing solutions
//!     37 our firing solution against them, the cyborg's own predicate
//!     38 our range probe closing on them, 1/(1+t)
//!     39 their firing solution against us  SUPERSET for missile hulls
//!     40 their range probe closing on us   SUPERSET for missile hulls
//!     41 their ability.immediate_weapon, which says whether 39 and 40 are
//!        the cyborg-visible case or the superset case
//!  42..=46   scalar ship comparisons
//!     42 our intel_range / LONG_RANGE      43 their intel_range / LONG_RANGE
//!     44 maneuverability(ours) / FAST_SHIP 45 maneuverability(theirs) / FAST_SHIP
//!     46 (our max_thrust - their max_thrust) / 64
//!  47..=60   ability bits, ours 47..=53 then theirs 54..=60, each in the order
//!            seeking_weapon, seeking_special, immediate_weapon, fires_fore,
//!            fires_right, fires_aft, fires_left
//!  61..=63   gravity concern
//!     61 planet dx / 4000                  62 planet dy / 4000
//!     63 1/(1+t) from the cyborg's own three-margin gravity battery
//!  64..=102  the three most urgent hostile projectiles, 13 slots each,
//!            base 64 + 13 * rank. The rank key is `cyborg::weapon_concern`'s
//!            own `which_turn`, which is the seeking branch's turn count for a
//!            homing weapon and the coasted intercept for a ballistic one:
//!     +0 1/(1+t) of that concern turn
//!     +1 cos(its travel angle - our facing)
//!     +2 sin(its travel angle - our facing)
//!     +3 its speed / TURN_WORLD
//!     +4 cos(its bearing from us - our facing)
//!     +5 sin(its bearing from us - our facing)
//!     +6 1/(1+turns) of its straight-line range, `seeking_weapon`'s own measure
//!     +7 cos(its travel angle - its bearing back to us), the closing test
//!     +8 sin of that same angle, whose SIGN is the side `entice_avoid` dodges
//!     +9 seeking                          +10 finite_life
//!    +11 its mass / our max_crew          +12 its remaining life / 64
//! 103..=109  crew concern
//!    103 dx / half width  104 dy / half height  105 1/(1+turns)
//!    106 cos(its travel angle - our facing)
//!    107 sin(its travel angle - our facing)
//!    108 its speed / TURN_WORLD
//!    109 our ship already targets it
//! 110..=115  neutral-body concern, the nearest parentless body (asteroids)
//!    110 dx / 4000        111 dy / 4000          112 1/(1+turns)
//!    113 cos(its travel angle - our facing)
//!    114 sin(its travel angle - our facing)
//!    115 its speed / TURN_WORLD
//! 116       constant 1.0, the last of the 117 combat sensors
//! 117..=126 hull identity, our 5-bit roster index then theirs, low bit first
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
pub const OWN_MASS: usize = 21;
pub const FOE_GEOMETRY: usize = 22;
pub const FOE_STATE: usize = 33;
pub const FIRING: usize = 37;
pub const SCALARS: usize = 42;
pub const ABILITIES: usize = 47;
pub const GRAVITY: usize = 61;
pub const THREATS: usize = 64;
pub const CREW: usize = 103;
pub const EMPTY: usize = 110;
pub const CONSTANT: usize = 116;
pub const HULL_BITS: usize = 117;

/// Hostile projectiles ranked and emitted, and the width of one record.
pub const THREAT_SLOTS: usize = 3;
pub const THREAT_WIDTH: usize = 13;

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
/// Speed of an object that has no `max_thrust` of its own to be measured
/// against. `cyborg::TURN_WORLD` is the distance the cyborg calls one turn, so
/// this reads as the fraction of a turn's distance the object covers per frame,
/// on the same scale every `world_to_turn` slot in this vector already uses.
fn pace(v: &VelocityDesc) -> f64 {
    (speed(v) / cyborg::TURN_WORLD as f64).clamp(0.0, 1.0)
}
/// Direction of travel and speed of an object the cyborg extrapolates with,
/// expressed in our own frame. `cyborg::displacement` consumes the whole
/// velocity, so a block that named only its magnitude would leave two opposite
/// headings indistinguishable.
fn motion_of(v: &VelocityDesc, face: i64) -> [f64; 3] {
    let relative = trig::normalize_angle(v.travel_angle - face);
    [unit(relative), unit_s(relative), pace(v)]
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
    /// `consider_weapon`'s own `which_turn` for this projectile at the Awesome
    /// rating: the seeking branch's turn count for a homing weapon, the coasted
    /// intercept for a ballistic one. This is the key the cyborg ranks on.
    concern: i64,
    /// Straight-line range in turns, which is what `seeking_weapon` measures and
    /// what `entice_avoid` needs alongside the bearing.
    turns: i64,
    travel: i64,
    /// Bearing from us to the projectile, and the bearing back from it to us.
    /// `entice_avoid` steers off the angle between the second and `travel`.
    bearing: i64,
    bearing_back: i64,
    velocity: VelocityDesc,
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
    out[OWN_RESOURCES..OWN_RESOURCES + 5].copy_from_slice(&[
        flag(oc.energy >= chars.weapon_energy_cost),
        flag(oc.energy >= chars.special_energy_cost),
        // Umgah spends energy by the turn on its approach and compares this
        // budget against the turns to the enemy, so the quantity is a turn
        // count on the same scale as slot 24.
        ratio(
            cyborg::world_to_turn(idiv(160 * oc.energy, chars.special_energy_cost.max(1))),
            64,
        ),
        // Chenjesu fires on special_wait == 1 exactly, which slot 8 cannot say.
        ratio(oc.special_wait.clamp(0, 64), 64),
        // A DIFFERENT FIELD from the one above. `Characteristics::special_wait`
        // is the hull's reload constant, and it is the slot `remember` writes
        // the Umgah approach distance into; `umgah` then compares the turns to
        // the enemy against it and `pilot` persists it back into the arena. It
        // is live, cyborg-visible state that the live timer above cannot
        // express. 255, the "forget it" sentinel, saturates this ratio at one,
        // which is the same thing the comparison says.
        ratio(chars.special_wait.clamp(0, 64), 64),
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
    let their_motion = motion_of(&foe.velocity, face);
    out[FOE_GEOMETRY..FOE_GEOMETRY + 11].copy_from_slice(&[
        (dx as f64 / (space.width as f64 / 2.0)).clamp(-1.0, 1.0),
        (dy as f64 / (space.height as f64 / 2.0)).clamp(-1.0, 1.0),
        (distance as f64 / cyborg::LONG_RANGE as f64).clamp(0.0, 1.0),
        (closing / 200.0).clamp(-1.0, 1.0),
        unit(relative),
        unit_s(relative),
        (speed(&foe.velocity) / fc.characteristics.max_thrust.max(1) as f64).clamp(0.0, 1.0),
        // `pursue` and `entice` both extrapolate the opponent with
        // `displacement(which_turn, &other.velocity)` and `entice_target` reads
        // `travel_angle(other.velocity)` outright. The closing scalar above is
        // only the radial part of that velocity, so without these two the sign
        // of the tangential part is lost and two opposite circling directions
        // would reach the network as the same situation.
        their_motion[0],
        their_motion[1],
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
        // Slots 4 and 28 normalise each side's speed by its own maximum, which
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
    melee_core::counters::element_scan(arena.elements.len());
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
            threats.push((turns, el.id.0, threat_of(arena, oc, space, own, el, dx, dy)));
        }
    }
    gravity(out, space, oc, own, planet);
    rank_threats(out, oc, threats);
    // Both concerns below reach `pursue`, which extrapolates the object with
    // `displacement(which_turn, &other.velocity)`, so each carries its whole
    // velocity rather than a position the network would have to differentiate.
    let face = oc.facing * 4;
    if let Some((turns, el)) = crew {
        let (dx, dy) = next_delta(space, own, el);
        let moving = motion_of(&el.velocity, face);
        out[CREW..CREW + 7].copy_from_slice(&[
            (dx as f64 / (space.width as f64 / 2.0)).clamp(-1.0, 1.0),
            (dy as f64 / (space.height as f64 / 2.0)).clamp(-1.0, 1.0),
            urgency(turns.max(1)),
            moving[0],
            moving[1],
            moving[2],
            flag(own.target == Some(el.id)),
        ]);
    }
    if let Some((turns, el)) = empty {
        let (dx, dy) = next_delta(space, own, el);
        let moving = motion_of(&el.velocity, face);
        out[EMPTY..EMPTY + 6].copy_from_slice(&[
            (dx as f64 / 4000.0).clamp(-1.0, 1.0),
            (dy as f64 / 4000.0).clamp(-1.0, 1.0),
            urgency(turns.max(1)),
            moving[0],
            moving[1],
            moving[2],
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
    oc: &CombatantCore,
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
    let seeking = (ability.seeking_weapon && !cyborg::is_special_body(el.body))
        || (ability.seeking_special && cyborg::is_special_body(el.body));
    Threat {
        // `consider_weapon`'s own split, at the Awesome rating. A homing weapon
        // goes to `seeking_weapon`, whose turn count is a straight-line range,
        // and a ballistic one is coasted against us over its remaining life at
        // the cyborg's 40-display-unit margin. Scoring every projectile by the
        // ballistic branch would sort a missile that is turning onto us but not
        // yet on a collision course behind every shot with a predicted impact,
        // which is the opposite of the order the cyborg acts in.
        concern: if seeking {
            cyborg::seeking_weapon_turn(&oc.characteristics, el, dx, dy)
        } else {
            cyborg::plot_intercept(
                space,
                el,
                own,
                cyborg::life_span(*el),
                cyborg::display_to_world(40),
            )
        },
        turns: cyborg::world_to_turn(trig::square_root(dx * dx + dy * dy)),
        travel: el.velocity.travel_angle,
        bearing: trig::arctan(dx, dy),
        bearing_back: trig::arctan(-dx, -dy),
        velocity: el.velocity,
        seeking,
        finite_life: el.flags.finite_life,
        mass: el.mass,
        life: cyborg::life_span(*el),
    }
}

fn rank_threats(out: &mut [f64; N_OBS], oc: &CombatantCore, mut threats: Vec<(i64, i64, Threat)>) {
    // `consider_weapon` keeps the smallest positive `which_turn`, and on a tie
    // it prefers the Avoid arm, which is the ballistic one. This is that rule:
    // projectiles the cyborg would score at zero sort behind every one it would
    // act on, then soonest concern first, then Avoid before Entice, then the
    // nearer object, then element id so the order is a function of the arena
    // alone.
    threats.sort_by_key(|(turns, id, t)| (t.concern <= 0, t.concern, t.seeking, *turns, *id));
    let face = oc.facing * 4;
    for (rank, (_, _, t)) in threats.iter().take(THREAT_SLOTS).enumerate() {
        let base = THREATS + rank * THREAT_WIDTH;
        let moving = motion_of(&t.velocity, face);
        let toward = trig::normalize_angle(t.bearing - face);
        let closing = trig::normalize_angle(t.travel - t.bearing_back);
        out[base..base + THREAT_WIDTH].copy_from_slice(&[
            urgency(t.concern),
            moving[0],
            moving[1],
            moving[2],
            // Where the shot is, in our own frame. Without these the network
            // holds an angle between two of the projectile's own directions and
            // no idea which side of us it passes.
            unit(toward),
            unit_s(toward),
            urgency(t.turns.max(1)),
            unit(closing),
            // `entice_avoid` turns `dir = +/-1` on exactly the sign of this
            // sine: the cosine alone leaves the bearing recoverable only up to
            // a mirror reflection about the projectile's travel line, which is
            // the one thing a dodge has to choose between.
            unit_s(closing),
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
        "special reload",
        "our hull mass",
        "foe dx",
        "foe dy",
        "foe range",
        "closing rate",
        "foe facing cos",
        "foe facing sin",
        "foe speed",
        "foe travel cos",
        "foe travel sin",
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
        "speed",
        "bearing cos",
        "bearing sin",
        "range",
        "closing cos",
        "closing sin",
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
        "crew travel cos",
        "crew travel sin",
        "crew speed",
        "crew targeted",
        "rock dx",
        "rock dy",
        "rock urgency",
        "rock travel cos",
        "rock travel sin",
        "rock speed",
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

/// What each block of the vector is built from, as (first slot, width, source).
/// Keyed by block rather than by index range on purpose: the layout test sums
/// these widths and checks the starts abut, so a slot inserted into a block
/// without being declared here leaves the table short of `N_OBS` and fails,
/// instead of quietly inheriting its neighbour's provenance. A source beginning
/// "SUPERSET" is a slot deliberately granted beyond what the cyborg reads.
pub const PROVENANCE: [(usize, usize, &str); 18] = [
    (
        OWN_STATE,
        11,
        "own core and own element, read by cyborg::decide",
    ),
    (
        OWN_MOTION,
        5,
        "motion::at_limit, motion::beyond_limit, MotionFlags, cyborg::is_ultra",
    ),
    (
        OWN_RESOURCES,
        5,
        "own energy against Characteristics costs, the live special_wait and the \
         Characteristics special_wait that cyborg::remember stashes into",
    ),
    (
        OWN_MASS,
        1,
        "own element mass, the field consider_enemy tests against MAX_SHIP_MASS",
    ),
    (
        FOE_GEOMETRY,
        11,
        "both hull elements' next.location, velocity, facing and mass",
    ),
    (FOE_STATE, 2, "foe element prim, own core cloaked"),
    (
        FOE_STATE + 2,
        2,
        "SUPERSET: foe core energy and foe element points",
    ),
    (
        FIRING,
        2,
        "cyborg::firing_solution and cyborg::range_probe from our seat",
    ),
    (
        FIRING + 2,
        2,
        "SUPERSET: the same two probes from the opponent's seat",
    ),
    (FIRING + 4, 1, "their ShipKind stock ability"),
    (
        SCALARS,
        5,
        "both ShipKind intel_range, cyborg::maneuverability, max_thrust",
    ),
    (
        ABILITIES,
        2 * ABILITY_BITS,
        "both ShipKind stock abilities, the seven bits cyborg branches on",
    ),
    (
        GRAVITY,
        3,
        "the gravity body's next.location and cyborg::gravity_intercept",
    ),
    (
        THREATS,
        THREAT_SLOTS * THREAT_WIDTH,
        "hostile projectile elements ranked by cyborg::weapon_concern's own key",
    ),
    (
        CREW,
        7,
        "the nearest crew element, its velocity, and our element's target",
    ),
    (
        EMPTY,
        6,
        "the nearest parentless neutral element and its velocity",
    ),
    (
        CONSTANT,
        1,
        "SUPERSET: the constant 1.0, a second bias path, not arena state",
    ),
    (
        HULL_BITS,
        2 * HULL_BITS_PER_SIDE,
        "both ShipKind roster indices",
    ),
];

/// Only for the layout tests: the pieces of arena state slot `index` is built
/// from, named so a slot cannot silently start reading something else.
pub fn provenance(index: usize) -> &'static str {
    PROVENANCE
        .iter()
        .find(|(start, width, _)| index >= *start && index < start + width)
        .map(|(_, _, source)| *source)
        .unwrap_or("out of range")
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

    /// The provenance table is the only statement of where each block begins and
    /// how wide it is, so a slot added anywhere must be declared there or the
    /// widths stop summing to `N_OBS`. The named block constants are checked
    /// against the same table rather than against a second copy of the layout.
    #[test]
    fn the_blocks_tile_the_vector_exactly_once_in_the_documented_order() {
        let mut next = 0;
        for (start, width, source) in PROVENANCE {
            assert_eq!(
                start, next,
                "block at {start} does not abut its predecessor"
            );
            assert!(width > 0, "block at {start} declares no slots");
            assert!(!source.is_empty(), "block at {start} names no source");
            next = start + width;
        }
        assert_eq!(next, N_OBS, "the blocks do not tile all {N_OBS} slots");
        for start in [
            OWN_STATE,
            OWN_MOTION,
            OWN_RESOURCES,
            OWN_MASS,
            FOE_GEOMETRY,
            FOE_STATE,
            FIRING,
            SCALARS,
            ABILITIES,
            GRAVITY,
            THREATS,
            CREW,
            EMPTY,
            CONSTANT,
            HULL_BITS,
        ] {
            assert!(
                PROVENANCE.iter().any(|(at, _, _)| *at == start),
                "block constant {start} is not where a provenance block begins"
            );
        }
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
            vec![
                FOE_STATE + 2,
                FOE_STATE + 3,
                FIRING + 2,
                FIRING + 3,
                CONSTANT
            ],
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
        //   * `FOE_STATE`, the opponent hull's cloaked prim. `ship_intelligence`
        //     widens its aiming margin on exactly this test, but nothing in
        //     this simulation ever gives a hull a cloaked prim: a ship's prim
        //     is a Stamp for its whole life, and Ilwrath's cloak is carried on
        //     `core.cloaked` (slot 31) instead. The slot stays because it is
        //     the cyborg's own read and because the day the port sets that prim
        //     the network must see it; it is dormant, not wrong;
        //   * `CREW + 6`, whether our hull already targets the crew object.
        //     `consider_crew` is the only reader of an element's `target`, and
        //     nothing in this simulation ever writes a hull element's `target`,
        //     so it reads None for the whole round. Dormant for the same reason
        //     and kept for the same reason.
        for (index, nonzero) in seen_nonzero.iter().enumerate() {
            if (HULL_BITS..HULL_BITS + 2 * HULL_BITS_PER_SIDE).contains(&index)
                || index == FOE_STATE
                || index == CREW + 6
            {
                continue;
            }
            assert!(
                *nonzero,
                "slot {index} ({}) was zero in every fixture arena",
                provenance(index)
            );
        }
    }

    /// Whether the cyborg would route this element to `seeking_weapon`, by the
    /// same two ability bits `consider_weapon` reads.
    fn seeks(arena: &Arena, el: &Element) -> bool {
        let ability = el
            .parent
            .map(|side| arena.combatants.get(side).kind().stock().ability)
            .unwrap_or(ShipKind::Shofixti.stock().ability);
        (ability.seeking_weapon && !cyborg::is_special_body(el.body))
            || (ability.seeking_special && cyborg::is_special_body(el.body))
    }

    /// The sort key the encoder gives one element, or `None` when that element
    /// is not a hostile projectile from this seat at all.
    fn threat_key(side: Side, arena: &Arena, id: i64) -> Option<(bool, i64, bool)> {
        let our = arena.combatants.get(side);
        let oc = our.core();
        let own = arena.elements.get(&oc.element.0)?;
        let el = arena.elements.get(&id)?;
        let (dx, dy) = next_delta(arena.space, own, el);
        let t = threat_of(arena, oc, arena.space, own, el, dx, dy);
        Some((t.concern <= 0, t.concern, t.seeking))
    }

    /// The element ids the encoder ranks, in the order it would emit them. Built
    /// from the encoder's own scan and sort so the test compares the emitted
    /// order rather than a second implementation of it.
    fn ranked_ids(side: Side, arena: &Arena) -> Vec<i64> {
        let our = arena.combatants.get(side);
        let oc = our.core();
        let Some(own) = arena.elements.get(&oc.element.0) else {
            return Vec::new();
        };
        if !cyborg::colliding(*own) {
            return Vec::new();
        }
        let mut threats: Vec<(i64, i64, Threat)> = Vec::new();
        for el in arena.elements.values() {
            if el.id == own.id
                || !cyborg::colliding(*el)
                || cyborg::is_gravity(*el)
                || el.flags.player_ship
                || cyborg::is_crew(*el)
                || el.parent.is_none()
                || el.parent == own.parent
                || cyborg::life_span(*el) <= 0
            {
                continue;
            }
            let (dx, dy) = next_delta(arena.space, own, el);
            let turns = cyborg::world_to_turn(trig::square_root(dx * dx + dy * dy));
            threats.push((
                turns,
                el.id.0,
                threat_of(arena, oc, arena.space, own, el, dx, dy),
            ));
        }
        threats.sort_by_key(|(turns, id, t)| (t.concern <= 0, t.concern, t.seeking, *turns, *id));
        threats
            .into_iter()
            .take(THREAT_SLOTS)
            .map(|(_, id, _)| id)
            .collect()
    }

    /// The projectile the cyborg itself acts on must not be displaced by one it
    /// scores worse, and the first slot's urgency must be the turn the cyborg
    /// scored its concern at. This asks `cyborg::weapon_concern` for the
    /// cyborg's own answer instead of restating the ranking rule, so a key that
    /// drifts away from `consider_weapon` fails here even though the encoder and
    /// a test that merely repeated the rule would still agree with each other.
    /// Scoring every projectile with the ballistic probe is exactly the drift it
    /// catches: a homing weapon the cyborg is avoiding scores zero there and
    /// sorts behind every shot with a predicted impact.
    #[test]
    fn the_cyborgs_own_weapon_concern_is_never_displaced_by_a_lesser_one() {
        let mut compared = 0;
        let mut homing = 0;
        let mut hulls = 0;
        for arena in arenas() {
            for side in [Side::Bottom, Side::Top] {
                let Some((id, which_turn)) =
                    cyborg::weapon_concern(CyborgRating::AwesomeCyborg, side, &arena)
                else {
                    continue;
                };
                let v = vector(side, &arena);
                let Some(object) = arena.elements.get(&id.0) else {
                    continue;
                };
                if object.flags.player_ship {
                    // `consider_enemy` promotes the opponent's own hull into the
                    // weapon concern when it holds an immediate weapon and a
                    // firing solution on us. That is not a projectile, and the
                    // encoder carries it in the firing block instead.
                    hulls += 1;
                    assert_eq!(
                        (v[FIRING + 2], v[FIRING + 4]),
                        (1.0, 1.0),
                        "an opponent hull promoted to the weapon concern is not \
                         readable from the firing block"
                    );
                    continue;
                }
                compared += 1;
                let ranked = ranked_ids(side, &arena);
                let chosen = threat_key(side, &arena, id.0).expect("the concern object is ranked");
                // The cyborg stops scanning the moment a concern reaches turn
                // one and prefers its Avoid arm on a tie, so on a tie it may
                // hold a different element than a total order does. What must
                // never happen is a projectile the cyborg scores WORSE taking
                // its slot: ranking everything by the ballistic probe did
                // exactly that to homing weapons.
                assert!(
                    ranked.contains(&id.0)
                        || ranked.iter().all(|other| {
                            threat_key(side, &arena, *other).expect("a ranked element") <= chosen
                        }),
                    "a projectile the cyborg scores worse than its own concern took its slot"
                );
                assert_eq!(
                    v[THREATS],
                    urgency(which_turn),
                    "threat 0 urgency is not the cyborg's own weapon concern turn"
                );
                if seeks(&arena, object) {
                    homing += 1;
                }
            }
        }
        assert!(compared > 0, "the cyborg never held a projectile concern");
        assert!(
            homing > 0,
            "the cyborg's concern was never a homing weapon, so the seeking branch is untested"
        );
        assert!(
            hulls > 0,
            "the opponent hull was never promoted to the weapon concern, so that arm is untested"
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

    /// Every slot whose provenance names a `cyborg::` function must equal what
    /// that function returns on the same arena. This is the test that makes the
    /// equivalence claim an argument about code rather than about prose: it
    /// imports the cyborg and evaluates it, so a slot that drifts into computing
    /// its own approximation of a cyborg predicate fails here.
    #[test]
    fn the_slots_credited_to_a_cyborg_function_agree_with_that_function() {
        let mut asserted = 0;
        for arena in arenas() {
            for side in [Side::Bottom, Side::Top] {
                let our = arena.combatants.get(side);
                let their = arena.combatants.get(side.other());
                let oc = our.core();
                let fc = their.core();
                let (Some(own), Some(foe)) = (
                    arena.elements.get(&oc.element.0),
                    arena.elements.get(&fc.element.0),
                ) else {
                    continue;
                };
                let v = vector(side, &arena);
                let chars = &oc.characteristics;
                assert_eq!(
                    v[OWN_MOTION],
                    flag(motion::at_limit(&own.velocity, &oc.flags))
                );
                assert_eq!(
                    v[OWN_MOTION + 1],
                    flag(motion::beyond_limit(&own.velocity, &oc.flags))
                );
                assert_eq!(v[OWN_MOTION + 4], flag(cyborg::is_ultra(chars)));
                assert_eq!(
                    v[OWN_RESOURCES + 2],
                    ratio(
                        cyborg::world_to_turn(idiv(
                            160 * oc.energy,
                            chars.special_energy_cost.max(1)
                        )),
                        64
                    )
                );
                assert_eq!(
                    v[OWN_RESOURCES + 4],
                    ratio(chars.special_wait.clamp(0, 64), 64),
                    "the Umgah stash slot is not Characteristics::special_wait"
                );
                assert_eq!(
                    v[FIRING],
                    flag(cyborg::firing_solution(&arena, side, foe, 0))
                );
                assert_eq!(
                    v[FIRING + 2],
                    flag(cyborg::firing_solution(&arena, side.other(), own, 0))
                );
                assert_eq!(
                    v[SCALARS + 2],
                    ratio(cyborg::maneuverability(chars), cyborg::FAST_SHIP)
                );
                assert_eq!(
                    v[SCALARS + 3],
                    ratio(
                        cyborg::maneuverability(&fc.characteristics),
                        cyborg::FAST_SHIP
                    )
                );
                // The last qualifying body wins, exactly as it does in the
                // encoder's own scan and in `fill_concerns`.
                let planet = arena.elements.values().fold(None, |kept, el| {
                    if cyborg::is_gravity(*el) && cyborg::colliding(*el) && el.id != own.id {
                        Some(el)
                    } else {
                        kept
                    }
                });
                if let Some(planet) = planet.filter(|_| cyborg::colliding(*own)) {
                    assert_eq!(
                        v[GRAVITY + 2],
                        urgency(cyborg::gravity_intercept(arena.space, planet, own, chars)),
                        "the gravity slot is not cyborg::gravity_intercept"
                    );
                }
                asserted += 1;
            }
        }
        assert!(asserted > 0, "no seat was ever checked");
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
