use alloc::vec;
use crate::{
    battle::Arena,
    catalog::{mmrnmhrm_y_wing, ShipKind, Stock},
    element::*,
    input::idle,
    ship_state::*,
};
use alloc::collections::BTreeMap;
use melee_core::{rng::Seed, trig, units::*, velocity};

pub fn empty_flags() -> ElementFlags {
    EMPTY_FLAGS
}

fn image(location: WorldPoint, frame_index: i64) -> Image {
    Image {
        location,
        frame_index,
    }
}

fn ship_element(
    id: ElementId,
    side: Side,
    location: WorldPoint,
    crew: i64,
    facing: i64,
) -> Element {
    Element {
        id,
        owner: Owner::Owned(side),
        parent: Some(side),
        target: None,
        flags: ElementFlags {
            player_ship: true,
            appearing: true,
            ignore_similar: true,
            ..EMPTY_FLAGS
        },
        life: Life::Persistent(1),
        points: crew,
        mass: 1,
        turn_wait: 0,
        thrust_wait: 0,
        color_cycle_index: 0,
        velocity: velocity::ZERO,
        intersect: IntersectControl {
            last_time_val: 0,
            end_point: location,
            stamp_origin: location,
        },
        current: image(location, facing),
        next: image(location, facing),
        prim: Prim::Stamp,
        projectile: None,
        body: Body::Ship(side),
    }
}

fn mk_core(id: ElementId, stock: &Stock, facing: i64) -> CombatantCore {
    CombatantCore {
        element: id,
        characteristics: stock.characteristics,
        energy: stock.starting_energy,
        max_energy: stock.max_energy,
        max_crew: stock.max_crew,
        weapon_wait: 0,
        special_wait: 0,
        energy_wait: 0,
        facing,
        input: idle(),
        shield_ticks: 0,
        confused_ticks: 0,
        charge_ticks: 0,
        cloaked: false,
        old_input: idle(),
        flags: MotionFlags {
            low_on_energy: false,
            beyond_max_speed: false,
            at_max_speed: false,
            in_gravity_well: false,
            play_victory_ditty: false,
        },
    }
}

pub fn combatant(kind: ShipKind, c: CombatantCore) -> Combatant {
    use Combatant::*;
    match kind {
        ShipKind::Androsynth => LiveAndrosynth(c, AndrosynthExtra::Guardian),
        ShipKind::Arilou => LiveArilou(c, ArilouExtra::Present),
        ShipKind::Chenjesu => LiveChenjesu(c),
        ShipKind::Chmmr => LiveChmmr(c, ChmmrExtra::TractorIdle),
        ShipKind::Druuge => LiveDruuge(c),
        ShipKind::Earthling => LiveEarthling(c),
        ShipKind::Ilwrath => LiveIlwrath(c),
        ShipKind::KohrAh => LiveKohrAh(c),
        ShipKind::Melnorme => LiveMelnorme(
            c,
            MelnormeExtra {
                pump: PumpLevel::Pump1,
                level_counter: 0,
            },
        ),
        ShipKind::Mmrnmhrm => LiveMmrnmhrm(
            c,
            MmrnmhrmExtra {
                form: MmrnmhrmForm::XWing,
                other_wing: mmrnmhrm_y_wing(),
            },
        ),
        ShipKind::Mycon => LiveMycon(c),
        ShipKind::Orz => LiveOrz(
            c,
            OrzExtra {
                turret_facing: 0,
                turret_wait: 0,
            },
        ),
        ShipKind::Pkunk => LivePkunk(c, PkunkExtra::Flying),
        ShipKind::Shofixti => LiveShofixti(c, ShofixtiExtra::SafetyClosed),
        ShipKind::Slylandro => LiveSlylandro(c),
        ShipKind::Spathi => LiveSpathi(c),
        ShipKind::Supox => LiveSupox(c, SupoxExtra::ForwardOnly),
        ShipKind::Syreen => LiveSyreen(c),
        ShipKind::Thraddash => LiveThraddash(c, ThraddashExtra::Cruise),
        ShipKind::Umgah => LiveUmgah(
            c,
            UmgahExtra {
                prev_facing: c.facing,
            },
        ),
        ShipKind::UrQuan => LiveUrQuan(c),
        ShipKind::Utwig => LiveUtwig(c),
        ShipKind::Vux => LiveVux(c, VuxExtra::WarpPending),
        ShipKind::Yehat => LiveYehat(c),
        ShipKind::ZoqFotPik => LiveZoqFotPik(c),
    }
}

pub fn arena(bottom_kind: ShipKind, top_kind: ShipKind, seed: Seed) -> Arena {
    let (_, s1) = seed.next();
    let (_, seed) = s1.next();
    let at = WorldPoint { x: 4096, y: 3840 };
    let planet = Element {
        id: ElementId(1),
        owner: Owner::Neutral,
        parent: None,
        target: None,
        flags: ElementFlags {
            appearing: true,
            ..EMPTY_FLAGS
        },
        life: Life::Persistent(2),
        points: 200,
        mass: 200,
        turn_wait: 0,
        thrust_wait: 0,
        color_cycle_index: 0,
        velocity: velocity::ZERO,
        intersect: IntersectControl {
            last_time_val: 0,
            end_point: at,
            stamp_origin: at,
        },
        current: image(at, 0),
        next: image(at, 0),
        projectile: None,
        prim: Prim::Stamp,
        body: Body::Planet,
    };
    let mut bottom = ship_element(
        ElementId(2),
        Side::Bottom,
        WorldPoint { x: 3200, y: 3200 },
        bottom_kind.stock().starting_crew,
        4,
    );
    let mut top = ship_element(
        ElementId(3),
        Side::Top,
        WorldPoint { x: 4900, y: 4500 },
        top_kind.stock().starting_crew,
        12,
    );
    bottom.mass = bottom_kind.stock().characteristics.ship_mass;
    top.mass = top_kind.stock().characteristics.ship_mass;
    let mut a = Arena {
        frame: 0,
        previous_locations: BTreeMap::new(),
        pump_acc: 0,
        seed,
        space: STOCK_LOG_SPACE,
        combatants: Sided {
            bottom: combatant(bottom_kind, mk_core(ElementId(2), bottom_kind.stock(), 4)),
            top: combatant(top_kind, mk_core(ElementId(3), top_kind.stock(), 12)),
        },
        elements: BTreeMap::from([(1, planet), (2, bottom), (3, top)]),
        queue: vec![ElementId(1), ElementId(2), ElementId(3)],
        next_element_id: 4,
    };
    satellites(Side::Bottom, &mut a);
    satellites(Side::Top, &mut a);
    a
}

fn satellites(side: Side, a: &mut Arena) {
    let c = a.combatants.get(side);
    if c.kind() != ShipKind::Chmmr {
        return;
    }
    let Some(parent) = a.elements.get(&c.core().element.0).copied() else {
        return;
    };
    for index in 0..3 {
        let id = ElementId(a.next_element_id);
        let angle = index * 21;
        let at = trig::wrap_point(
            a.space,
            WorldPoint {
                x: parent.current.location.x + trig::cosine(angle, 150),
                y: parent.current.location.y + trig::sine(angle, 150),
            },
        );
        let img = image(at, 0);
        let el = Element {
            id,
            body: Body::ChmmrSatellite {
                orbit_facing: index,
            },
            points: 3,
            mass: 1,
            flags: ElementFlags {
                ignore_similar: true,
                defy_physics: true,
                ..EMPTY_FLAGS
            },
            current: img,
            next: img,
            ..parent
        };
        a.elements.insert(id.0, el);
        a.queue.push(id);
        a.next_element_id += 1;
    }
}
