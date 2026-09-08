//! `src/Melee/ShipState.elm`. Live STARSHIP state and race-specific data.

use crate::catalog::{Characteristics, ShipKind};
use crate::element::ElementId;
use crate::input::{BattleInput, Turn};
use melee_core::units::Facing;

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Hash)]
pub struct MotionFlags {
    pub low_on_energy: bool,
    pub beyond_max_speed: bool,
    pub at_max_speed: bool,
    pub in_gravity_well: bool,
    pub play_victory_ditty: bool,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct CombatantCore {
    pub element: ElementId,
    pub characteristics: Characteristics,
    pub energy: i64,
    pub max_energy: i64,
    pub max_crew: i64,
    pub weapon_wait: i64,
    pub special_wait: i64,
    pub energy_wait: i64,
    pub facing: Facing,
    pub input: BattleInput,
    pub shield_ticks: i64,
    pub confused_ticks: i64,
    pub charge_ticks: i64,
    pub cloaked: bool,
    pub old_input: BattleInput,
    pub flags: MotionFlags,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum AndrosynthExtra {
    Guardian,
    Blazer { guardian: Characteristics },
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum ArilouExtra {
    Present,
    Teleporting(i64),
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum ChmmrExtra {
    TractorIdle,
    TractorOn,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum PumpLevel {
    Pump1,
    Pump2,
    Pump3,
    Pump4,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct MelnormeExtra {
    pub pump: PumpLevel,
    pub level_counter: i64,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum MmrnmhrmForm {
    XWing,
    YWing,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct MmrnmhrmExtra {
    pub form: MmrnmhrmForm,
    pub other_wing: Characteristics,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct OrzExtra {
    pub turret_facing: Facing,
    pub turret_wait: i64,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum PkunkExtra {
    Flying,
    Phoenix(ElementId),
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum ShofixtiExtra {
    SafetyClosed,
    OpeningSafety,
    SafetyOpen,
    ArmingDevice,
    Armed,
    GloryDevice,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum SupoxExtra {
    ForwardOnly,
    Strafing(Turn),
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum ThraddashExtra {
    Cruise,
    Afterburning {
        saved_max_thrust: i64,
        saved_thrust_increment: i64,
    },
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub struct UmgahExtra {
    pub prev_facing: Facing,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum VuxExtra {
    WarpPending,
    OnField,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
pub enum Combatant {
    LiveAndrosynth(CombatantCore, AndrosynthExtra),
    LiveArilou(CombatantCore, ArilouExtra),
    LiveChenjesu(CombatantCore),
    LiveChmmr(CombatantCore, ChmmrExtra),
    LiveDruuge(CombatantCore),
    LiveEarthling(CombatantCore),
    LiveIlwrath(CombatantCore),
    LiveKohrAh(CombatantCore),
    LiveMelnorme(CombatantCore, MelnormeExtra),
    LiveMmrnmhrm(CombatantCore, MmrnmhrmExtra),
    LiveMycon(CombatantCore),
    LiveOrz(CombatantCore, OrzExtra),
    LivePkunk(CombatantCore, PkunkExtra),
    LiveShofixti(CombatantCore, ShofixtiExtra),
    LiveSlylandro(CombatantCore),
    LiveSpathi(CombatantCore),
    LiveSupox(CombatantCore, SupoxExtra),
    LiveSyreen(CombatantCore),
    LiveThraddash(CombatantCore, ThraddashExtra),
    LiveUmgah(CombatantCore, UmgahExtra),
    LiveUrQuan(CombatantCore),
    LiveUtwig(CombatantCore),
    LiveVux(CombatantCore, VuxExtra),
    LiveYehat(CombatantCore),
    LiveZoqFotPik(CombatantCore),
}

impl Combatant {
    #[inline]
    pub fn core(&self) -> &CombatantCore {
        match self {
            Combatant::LiveAndrosynth(c, _)
            | Combatant::LiveArilou(c, _)
            | Combatant::LiveChmmr(c, _)
            | Combatant::LiveMelnorme(c, _)
            | Combatant::LiveMmrnmhrm(c, _)
            | Combatant::LiveOrz(c, _)
            | Combatant::LivePkunk(c, _)
            | Combatant::LiveShofixti(c, _)
            | Combatant::LiveSupox(c, _)
            | Combatant::LiveThraddash(c, _)
            | Combatant::LiveUmgah(c, _)
            | Combatant::LiveVux(c, _)
            | Combatant::LiveChenjesu(c)
            | Combatant::LiveDruuge(c)
            | Combatant::LiveEarthling(c)
            | Combatant::LiveIlwrath(c)
            | Combatant::LiveKohrAh(c)
            | Combatant::LiveMycon(c)
            | Combatant::LiveSlylandro(c)
            | Combatant::LiveSpathi(c)
            | Combatant::LiveSyreen(c)
            | Combatant::LiveUrQuan(c)
            | Combatant::LiveUtwig(c)
            | Combatant::LiveYehat(c)
            | Combatant::LiveZoqFotPik(c) => c,
        }
    }

    #[inline]
    pub fn core_mut(&mut self) -> &mut CombatantCore {
        match self {
            Combatant::LiveAndrosynth(c, _)
            | Combatant::LiveArilou(c, _)
            | Combatant::LiveChmmr(c, _)
            | Combatant::LiveMelnorme(c, _)
            | Combatant::LiveMmrnmhrm(c, _)
            | Combatant::LiveOrz(c, _)
            | Combatant::LivePkunk(c, _)
            | Combatant::LiveShofixti(c, _)
            | Combatant::LiveSupox(c, _)
            | Combatant::LiveThraddash(c, _)
            | Combatant::LiveUmgah(c, _)
            | Combatant::LiveVux(c, _)
            | Combatant::LiveChenjesu(c)
            | Combatant::LiveDruuge(c)
            | Combatant::LiveEarthling(c)
            | Combatant::LiveIlwrath(c)
            | Combatant::LiveKohrAh(c)
            | Combatant::LiveMycon(c)
            | Combatant::LiveSlylandro(c)
            | Combatant::LiveSpathi(c)
            | Combatant::LiveSyreen(c)
            | Combatant::LiveUrQuan(c)
            | Combatant::LiveUtwig(c)
            | Combatant::LiveYehat(c)
            | Combatant::LiveZoqFotPik(c) => c,
        }
    }

    #[inline]
    pub fn kind(&self) -> ShipKind {
        kind(self)
    }
}

#[inline]
pub fn core(combatant: &Combatant) -> CombatantCore {
    *combatant.core()
}

pub fn kind(combatant: &Combatant) -> ShipKind {
    use Combatant::*;
    match combatant {
        LiveAndrosynth(..) => ShipKind::Androsynth,
        LiveArilou(..) => ShipKind::Arilou,
        LiveChenjesu(..) => ShipKind::Chenjesu,
        LiveChmmr(..) => ShipKind::Chmmr,
        LiveDruuge(..) => ShipKind::Druuge,
        LiveEarthling(..) => ShipKind::Earthling,
        LiveIlwrath(..) => ShipKind::Ilwrath,
        LiveKohrAh(..) => ShipKind::KohrAh,
        LiveMelnorme(..) => ShipKind::Melnorme,
        LiveMmrnmhrm(..) => ShipKind::Mmrnmhrm,
        LiveMycon(..) => ShipKind::Mycon,
        LiveOrz(..) => ShipKind::Orz,
        LivePkunk(..) => ShipKind::Pkunk,
        LiveShofixti(..) => ShipKind::Shofixti,
        LiveSlylandro(..) => ShipKind::Slylandro,
        LiveSpathi(..) => ShipKind::Spathi,
        LiveSupox(..) => ShipKind::Supox,
        LiveSyreen(..) => ShipKind::Syreen,
        LiveThraddash(..) => ShipKind::Thraddash,
        LiveUmgah(..) => ShipKind::Umgah,
        LiveUrQuan(..) => ShipKind::UrQuan,
        LiveUtwig(..) => ShipKind::Utwig,
        LiveVux(..) => ShipKind::Vux,
        LiveYehat(..) => ShipKind::Yehat,
        LiveZoqFotPik(..) => ShipKind::ZoqFotPik,
    }
}

#[inline]
pub fn set_core(core: CombatantCore, mut combatant: Combatant) -> Combatant {
    *combatant.core_mut() = core;
    combatant
}
