//! NDJSON-compatible state trace matching `tests/Oracle/NeatTrace.elm`.

use crate::{
    encode,
    eval::{Job, Phase, State},
    policy::{self, Net, N_WEIGHTS},
};
use melee_core::units::{Side, VelocityDesc, WorldExtent, WorldPoint};
use melee_sim::{
    battle::Arena,
    catalog::{BeamKind, Characteristics, ContactKind, MissileKind},
    element::{Body, Element, ElementFlags, Life, Owner, Prim, ProjectileState},
    input::{BattleInput, CyborgRating, Turn},
    ship_state::{
        AndrosynthExtra, ArilouExtra, ChmmrExtra, Combatant, CombatantCore, MmrnmhrmForm,
        PkunkExtra, PumpLevel, ShofixtiExtra, SupoxExtra, ThraddashExtra, VuxExtra,
    },
};
use serde_json::{json, Value};

pub struct Metadata<'a> {
    pub rating: &'a str,
    pub us: &'a str,
    pub them: &'a str,
    pub foe: &'a str,
}

impl<'a> Metadata<'a> {
    pub fn canonical(job: &Job) -> Self {
        Self {
            rating: rating_name(job.rating),
            us: job.us.name(),
            them: job.them.name(),
            foe: if job.self_play { "self" } else { "cyborg" },
        }
    }
}

/// Emits `header`, initial `event`, every event boundary, then `done`.
pub fn run(job: &Job, net: &Net, mut emit: impl FnMut(Value)) {
    run_with_metadata(job, net, Metadata::canonical(job), &mut emit);
}

pub fn run_with_metadata(
    job: &Job,
    net: &Net,
    metadata: Metadata<'_>,
    mut emit: impl FnMut(Value),
) {
    emit(json!({
        "type": "header",
        "schema": "uqm-neat-trace-v1",
        "seed": job.seed,
        "tick_limit": job.ticks,
        "swap": job.swap,
        "rating": metadata.rating,
        "us": metadata.us,
        "them": metadata.them,
        "foe": metadata.foe,
        "weight_count": N_WEIGHTS,
    }));

    let mut state = State::start(job);
    emit(snapshot(0, 0, &state, None, job));
    let mut event = 0;
    while !matches!(state.phase, Phase::Victory(_)) && state.ticks < job.ticks {
        let policy = policy_trace(&state, net);
        let before = state.ticks;
        state.advance(job, net);
        event += 1;
        emit(snapshot(event, state.ticks - before, &state, policy, job));
    }
    emit(json!({
        "type": "done",
        "events": event,
        "display_ticks": state.ticks,
        "phase": phase_name(state.phase),
        "round": 1,
    }));
}

fn policy_trace(state: &State, net: &Net) -> Option<Value> {
    if state.phase != Phase::Combat {
        return None;
    }
    Some(sided(
        side_trace(state, net, Side::Bottom),
        side_trace(state, net, Side::Top),
    ))
}

fn side_trace(state: &State, net: &Net, side: Side) -> Value {
    let live = state.arena.combatants.get(side);
    let name = live.kind().name();
    let extra = if state.memory_round != 1 || *state.memory_names.get(side) != name {
        [0.0; 8]
    } else {
        *state.memory.get(side)
    };
    let observation = encode::vector(side, &state.arena);
    let action = policy::actions(live.core().old_input);
    let feedback_in: Vec<_> = action.into_iter().chain(extra).collect();
    let stepped = net.step(&observation, live.core().old_input, &extra);
    let feedback_out: Vec<_> = policy::actions(stepped.input)
        .into_iter()
        .chain(stepped.extra)
        .collect();
    json!({
        "ship": name,
        "observation": observation.to_vec(),
        "feedback_in": feedback_in,
        "input": battle_input(stepped.input),
        "extra": stepped.extra,
        "feedback_out": feedback_out,
    })
}

fn snapshot(event: i64, elapsed: i64, state: &State, policy: Option<Value>, job: &Job) -> Value {
    let source = match state.phase {
        Phase::Selecting | Phase::Victory(_) => "survivor",
        _ => "phase",
    };
    json!({
        "type": "event",
        "event": event,
        "display_ticks": state.ticks,
        "elapsed": elapsed,
        "round": 1,
        "phase": phase(state.phase),
        "game_seed": state.game_seed.0,
        "remaining": remaining(state.phase, job),
        "arena_source": source,
        "arena": arena(&state.arena),
        "memory": {
            "extra_bottom": state.memory.bottom,
            "extra_top": state.memory.top,
            "round": state.memory_round,
            "ship_bottom": state.memory_names.bottom,
            "ship_top": state.memory_names.top,
        },
        "policy": policy,
    })
}

fn remaining(phase: Phase, job: &Job) -> Value {
    let (bottom, top) = if job.swap {
        (job.them.name(), job.us.name())
    } else {
        (job.us.name(), job.them.name())
    };
    match phase {
        Phase::Victory(Some(Side::Bottom)) => sided(json!([bottom]), json!([])),
        Phase::Victory(Some(Side::Top)) => sided(json!([]), json!([top])),
        Phase::Victory(None) => sided(json!([]), json!([])),
        _ => sided(json!([bottom]), json!([top])),
    }
}

fn phase(value: Phase) -> Value {
    match value {
        Phase::Countdown(ticks) => json!({"tag":"Countdown","ticks":ticks}),
        Phase::Combat => tag("Combat"),
        Phase::RoundOver(ticks) => json!({"tag":"RoundOver","ticks":ticks}),
        Phase::Selecting => json!({"tag":"Selecting","bottom":null,"top":null}),
        Phase::Victory(winner) => json!({
            "tag":"Victory",
            "winner": winner.map(|side| side as u32),
        }),
    }
}

fn phase_name(value: Phase) -> &'static str {
    match value {
        Phase::Countdown(_) => "Countdown",
        Phase::Combat => "Combat",
        Phase::RoundOver(_) => "RoundOver",
        Phase::Selecting => "Selecting",
        Phase::Victory(_) => "Victory",
    }
}

fn arena(value: &Arena) -> Value {
    json!({
        "frame": value.frame,
        "pump_acc": value.pump_acc,
        "seed": value.seed.0,
        "space": extent(value.space),
        "combatants": sided(combatant(&value.combatants.bottom), combatant(&value.combatants.top)),
        "elements": value.elements.values().map(element).collect::<Vec<_>>(),
        "queue": value.queue.iter().map(|id| id.0).collect::<Vec<_>>(),
        "next_element_id": value.next_element_id,
        "previous_locations": value.previous_locations.iter().map(|(&id,&p)| json!([id, point(p)])).collect::<Vec<_>>(),
    })
}

fn combatant(live: &Combatant) -> Value {
    let extra = match live {
        Combatant::LiveAndrosynth(_, AndrosynthExtra::Guardian) => tag("Guardian"),
        Combatant::LiveAndrosynth(_, AndrosynthExtra::Blazer { guardian }) => {
            json!({"tag":"Blazer","guardian":characteristics(*guardian)})
        }
        Combatant::LiveArilou(_, ArilouExtra::Present) => tag("Present"),
        Combatant::LiveArilou(_, ArilouExtra::Teleporting(wait)) => {
            json!({"tag":"Teleporting","wait":wait})
        }
        Combatant::LiveChmmr(_, state) => tag(match state {
            ChmmrExtra::TractorIdle => "TractorIdle",
            ChmmrExtra::TractorOn => "TractorOn",
        }),
        Combatant::LiveMelnorme(_, state) => json!({
            "pump": match state.pump { PumpLevel::Pump1=>"Pump1", PumpLevel::Pump2=>"Pump2", PumpLevel::Pump3=>"Pump3", PumpLevel::Pump4=>"Pump4" },
            "level_counter": state.level_counter,
        }),
        Combatant::LiveMmrnmhrm(_, state) => json!({
            "form": match state.form { MmrnmhrmForm::XWing=>"XWing", MmrnmhrmForm::YWing=>"YWing" },
            "other_wing": characteristics(state.other_wing),
        }),
        Combatant::LiveOrz(_, state) => {
            json!({"turret_facing":state.turret_facing,"turret_wait":state.turret_wait})
        }
        Combatant::LivePkunk(_, PkunkExtra::Flying) => tag("Flying"),
        Combatant::LivePkunk(_, PkunkExtra::Phoenix(id)) => json!({"tag":"Phoenix","element":id.0}),
        Combatant::LiveShofixti(_, state) => tag(match state {
            ShofixtiExtra::SafetyClosed => "SafetyClosed",
            ShofixtiExtra::OpeningSafety => "OpeningSafety",
            ShofixtiExtra::SafetyOpen => "SafetyOpen",
            ShofixtiExtra::ArmingDevice => "ArmingDevice",
            ShofixtiExtra::Armed => "Armed",
            ShofixtiExtra::GloryDevice => "GloryDevice",
        }),
        Combatant::LiveSupox(_, SupoxExtra::ForwardOnly) => tag("ForwardOnly"),
        Combatant::LiveSupox(_, SupoxExtra::Strafing(turn)) => {
            json!({"tag":"Strafing","turn":turn_name(*turn)})
        }
        Combatant::LiveThraddash(_, ThraddashExtra::Cruise) => tag("Cruise"),
        Combatant::LiveThraddash(
            _,
            ThraddashExtra::Afterburning {
                saved_max_thrust,
                saved_thrust_increment,
            },
        ) => json!({
            "tag":"Afterburning","saved_max_thrust":saved_max_thrust,"saved_thrust_increment":saved_thrust_increment,
        }),
        Combatant::LiveUmgah(_, state) => json!({"prev_facing":state.prev_facing}),
        Combatant::LiveVux(_, state) => tag(match state {
            VuxExtra::WarpPending => "WarpPending",
            VuxExtra::OnField => "OnField",
        }),
        _ => Value::Null,
    };
    json!({"tag": live.kind().name().replace('-', ""), "core": core(live.core()), "extra": extra})
}

fn core(value: &CombatantCore) -> Value {
    json!({
        "element":value.element.0,
        "characteristics":characteristics(value.characteristics),
        "energy":value.energy,"max_energy":value.max_energy,"max_crew":value.max_crew,
        "weapon_wait":value.weapon_wait,"special_wait":value.special_wait,"energy_wait":value.energy_wait,
        "facing":value.facing,"input":battle_input(value.input),"shield_ticks":value.shield_ticks,
        "confused_ticks":value.confused_ticks,"charge_ticks":value.charge_ticks,"cloaked":value.cloaked,
        "old_input":battle_input(value.old_input),
        "flags":{
            "low_on_energy":value.flags.low_on_energy,"beyond_max_speed":value.flags.beyond_max_speed,
            "at_max_speed":value.flags.at_max_speed,"in_gravity_well":value.flags.in_gravity_well,
            "play_victory_ditty":value.flags.play_victory_ditty,
        }
    })
}

fn characteristics(value: Characteristics) -> Value {
    json!({
        "max_thrust":value.max_thrust,"thrust_increment":value.thrust_increment,
        "energy_regeneration":value.energy_regeneration,"weapon_energy_cost":value.weapon_energy_cost,
        "special_energy_cost":value.special_energy_cost,"energy_wait":value.energy_wait,
        "turn_wait":value.turn_wait,"thrust_wait":value.thrust_wait,"weapon_wait":value.weapon_wait,
        "special_wait":value.special_wait,"ship_mass":value.ship_mass,
    })
}

fn element(value: &Element) -> Value {
    json!({
        "id":value.id.0,"owner":match value.owner { Owner::Neutral=>-1, Owner::Owned(side)=>side as i64 },
        "parent":value.parent.map(|side|side as u32),"target":value.target.map(|id|id.0),
        "flags":element_flags(value.flags),"life":life(value.life),"points":value.points,"mass":value.mass,
        "turn_wait":value.turn_wait,"thrust_wait":value.thrust_wait,"color_cycle_index":value.color_cycle_index,
        "velocity":velocity(value.velocity),
        "intersect":{"last_time_val":value.intersect.last_time_val,"end_point":point(value.intersect.end_point),"stamp_origin":point(value.intersect.stamp_origin)},
        "current":{"location":point(value.current.location),"frame_index":value.current.frame_index},
        "next":{"location":point(value.next.location),"frame_index":value.next.frame_index},
        "prim":prim(value.prim),"projectile":value.projectile.map(projectile),"body":body(value.body),
    })
}

fn element_flags(value: ElementFlags) -> Value {
    json!({
        "player_ship":value.player_ship,"appearing":value.appearing,"disappearing":value.disappearing,
        "changing":value.changing,"nonsolid":value.nonsolid,"collision":value.collision,
        "ignore_similar":value.ignore_similar,"defy_physics":value.defy_physics,"finite_life":value.finite_life,
        "pre_process":value.pre_process,"post_process":value.post_process,"ignore_velocity":value.ignore_velocity,
        "crew_object":value.crew_object,"background_object":value.background_object,
    })
}

fn life(value: Life) -> Value {
    match value {
        Life::Persistent(ticks) => json!({"tag":"Persistent","ticks":ticks}),
        Life::Finite(ticks) => json!({"tag":"Finite","ticks":ticks}),
    }
}

fn velocity(value: VelocityDesc) -> Value {
    json!({
        "travel_angle":value.travel_angle,"vector":extent(value.vector),"fract":extent(value.fract),
        "error":extent(value.error),"incr":extent(value.incr),
    })
}

fn prim(value: Prim) -> Value {
    match value {
        Prim::NoPrim => tag("NoPrim"),
        Prim::Stamp => tag("Stamp"),
        Prim::StampFill { black } => json!({"tag":"StampFill","black":black}),
        Prim::Line => tag("Line"),
    }
}

fn projectile(value: ProjectileState) -> Value {
    match value {
        ProjectileState::Flying {
            kind,
            age,
            facing,
            tracking_wait,
        } => {
            json!({"tag":"Flying","kind":missile_name(kind),"age":age,"facing":facing,"tracking_wait":tracking_wait})
        }
        ProjectileState::Charging { ticks, facing } => {
            json!({"tag":"Charging","ticks":ticks,"facing":facing})
        }
        ProjectileState::Ray { beam, origin, end } => {
            json!({"tag":"Ray","kind":beam_name(beam),"origin":point(origin),"end":point(end)})
        }
        ProjectileState::Attached {
            contact,
            age,
            facing,
        } => json!({"tag":"Attached","kind":contact_name(contact),"age":age,"facing":facing}),
        ProjectileState::LightningSegment { origin, end } => {
            json!({"tag":"LightningSegment","origin":point(origin),"end":point(end)})
        }
    }
}

fn body(value: Body) -> Value {
    match value {
        Body::Ship(side) => json!({"tag":"Ship","side":side as u32}),
        Body::Wreck(side) => json!({"tag":"Wreck","side":side as u32}),
        Body::Crew { origin } => json!({"tag":"Crew","origin":origin as u32}),
        Body::WeaponImpact(kind) => json!({"tag":"WeaponImpact","kind":missile_name(kind)}),
        Body::ChmmrSatellite { orbit_facing } => {
            json!({"tag":"ChmmrSatellite","orbit_facing":orbit_facing})
        }
        other => tag(body_name(other)),
    }
}

fn body_name(value: Body) -> &'static str {
    match value {
        Body::Planet => "Planet",
        Body::Asteroid => "Asteroid",
        Body::Blast => "Blast",
        Body::Explosion => "Explosion",
        Body::WarpIn => "WarpIn",
        Body::IonTrail => "IonTrail",
        Body::AndrosynthBubble => "AndrosynthBubble",
        Body::ArilouLaser => "ArilouLaser",
        Body::ChenjesuPhoton => "ChenjesuPhoton",
        Body::ChenjesuFragment => "ChenjesuFragment",
        Body::ChenjesuDogi => "ChenjesuDogi",
        Body::ChmmrLaser => "ChmmrLaser",
        Body::ChmmrZap => "ChmmrZap",
        Body::DruugeHotShot => "DruugeHotShot",
        Body::EarthlingNuke => "EarthlingNuke",
        Body::EarthlingPointDefense => "EarthlingPointDefense",
        Body::IlwrathFlame => "IlwrathFlame",
        Body::KohrAhSaw => "KohrAhSaw",
        Body::KohrAhFried => "KohrAhFried",
        Body::MelnormeCharge => "MelnormeCharge",
        Body::MelnormeConfusion => "MelnormeConfusion",
        Body::MmrnmhrmLaser => "MmrnmhrmLaser",
        Body::MmrnmhrmMissile => "MmrnmhrmMissile",
        Body::MyconPlasma => "MyconPlasma",
        Body::OrzHowitzer => "OrzHowitzer",
        Body::OrzMarine => "OrzMarine",
        Body::PkunkSpread => "PkunkSpread",
        Body::ShofixtiDart => "ShofixtiDart",
        Body::ShofixtiGlory => "ShofixtiGlory",
        Body::SlylandroLightning => "SlylandroLightning",
        Body::SpathiForward => "SpathiForward",
        Body::SpathiButt => "SpathiButt",
        Body::SupoxPellet => "SupoxPellet",
        Body::SyreenMissile => "SyreenMissile",
        Body::ThraddashBlaster => "ThraddashBlaster",
        Body::ThraddashAfterburn => "ThraddashAfterburn",
        Body::UmgahCone => "UmgahCone",
        Body::UrQuanFusion => "UrQuanFusion",
        Body::UrQuanFighter => "UrQuanFighter",
        Body::UrQuanFighterLaser => "UrQuanFighterLaser",
        Body::UtwigGizmo => "UtwigGizmo",
        Body::VuxLaser => "VuxLaser",
        Body::VuxLimpet => "VuxLimpet",
        Body::YehatMissile => "YehatMissile",
        Body::ZoqSpit => "ZoqSpit",
        Body::ZoqTongue => "ZoqTongue",
        _ => unreachable!("payload body handled above"),
    }
}

fn battle_input(value: BattleInput) -> Value {
    json!({"turn":turn_name(value.turn),"thrust":value.thrust,"weapon":value.weapon,"special":value.special})
}

fn turn_name(value: Turn) -> &'static str {
    match value {
        Turn::NoTurn => "NoTurn",
        Turn::TurnLeft => "TurnLeft",
        Turn::TurnRight => "TurnRight",
    }
}

fn missile_name(value: MissileKind) -> &'static str {
    const NAMES: [&str; 29] = [
        "Bubble",
        "Crystal",
        "Shard",
        "Dogi",
        "Cannon",
        "Nuke",
        "Flame",
        "Saw",
        "Fried",
        "Charge",
        "Confusion",
        "Torpedo",
        "Plasma",
        "Howitzer",
        "Marine",
        "Bug",
        "Dart",
        "SpathiShot",
        "Butt",
        "Pellet",
        "Dagger",
        "Blaster",
        "Napalm",
        "Fusion",
        "Fighter",
        "Lance",
        "Limpet",
        "YehatShot",
        "Spit",
    ];
    NAMES[value.index()]
}

fn beam_name(value: BeamKind) -> &'static str {
    match value {
        BeamKind::AutoAim => "AutoAim",
        BeamKind::Megawatt => "Megawatt",
        BeamKind::Twin => "Twin",
        BeamKind::Green => "Green",
        BeamKind::PointDefense => "PointDefense",
        BeamKind::Zap => "Zap",
        BeamKind::FighterBeam => "FighterBeam",
    }
}
fn contact_name(value: ContactKind) -> &'static str {
    match value {
        ContactKind::Cone => "Cone",
        ContactKind::Tongue => "Tongue",
    }
}
fn rating_name(value: CyborgRating) -> &'static str {
    match value {
        CyborgRating::StandardCyborg => "standard",
        CyborgRating::GoodCyborg => "good",
        CyborgRating::AwesomeCyborg => "awesome",
    }
}
fn point(value: WorldPoint) -> Value {
    json!([value.x, value.y])
}
fn extent(value: WorldExtent) -> Value {
    json!([value.width, value.height])
}
fn sided(bottom: Value, top: Value) -> Value {
    json!({"bottom":bottom,"top":top})
}
fn tag(name: &str) -> Value {
    json!({"tag":name})
}
