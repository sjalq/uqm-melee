module Evergreen.V2.Melee.ShipState exposing (..)

import Evergreen.V2.Melee.Id
import Evergreen.V2.Melee.Input
import Evergreen.V2.Melee.Ship
import Evergreen.V2.Melee.Units


type alias MotionFlags =
    { lowOnEnergy : Bool
    , beyondMaxSpeed : Bool
    , atMaxSpeed : Bool
    , inGravityWell : Bool
    , playVictoryDitty : Bool
    }


type alias CombatantCore =
    { element : Evergreen.V2.Melee.Id.ElementId
    , characteristics : Evergreen.V2.Melee.Ship.Characteristics
    , energy : Int
    , maxEnergy : Int
    , maxCrew : Int
    , weaponWait : Evergreen.V2.Melee.Units.Wait
    , specialWait : Evergreen.V2.Melee.Units.Wait
    , energyWait : Evergreen.V2.Melee.Units.Wait
    , facing : Evergreen.V2.Melee.Units.Facing
    , input : Evergreen.V2.Melee.Input.BattleInput
    , shieldTicks : Int
    , confusedTicks : Int
    , chargeTicks : Int
    , cloaked : Bool
    , oldInput : Evergreen.V2.Melee.Input.BattleInput
    , flags : MotionFlags
    }


type AndrosynthExtra
    = Guardian
    | Blazer
        { guardian : Evergreen.V2.Melee.Ship.Characteristics
        }


type ArilouExtra
    = Present
    | Teleporting Evergreen.V2.Melee.Units.Wait


type ChmmrExtra
    = TractorIdle
    | TractorOn


type PumpLevel
    = Pump1
    | Pump2
    | Pump3
    | Pump4


type alias MelnormeExtra =
    { pump : PumpLevel
    , levelCounter : Evergreen.V2.Melee.Units.Wait
    }


type MmrnmhrmForm
    = XWing
    | YWing


type alias MmrnmhrmExtra =
    { form : MmrnmhrmForm
    , otherWing : Evergreen.V2.Melee.Ship.Characteristics
    }


type alias OrzExtra =
    { turretFacing : Evergreen.V2.Melee.Units.Facing
    , turretWait : Evergreen.V2.Melee.Units.Wait
    }


type PkunkExtra
    = Flying
    | Phoenix Evergreen.V2.Melee.Id.ElementId


type ShofixtiExtra
    = SafetyClosed
    | OpeningSafety
    | SafetyOpen
    | ArmingDevice
    | Armed
    | GloryDevice


type SupoxExtra
    = ForwardOnly
    | Strafing Evergreen.V2.Melee.Input.Turn


type ThraddashExtra
    = Cruise
    | Afterburning
        { savedMaxThrust : Int
        , savedThrustIncrement : Int
        }


type alias UmgahExtra =
    { prevFacing : Evergreen.V2.Melee.Units.Facing
    }


type VuxExtra
    = WarpPending
    | OnField


type Combatant
    = LiveAndrosynth CombatantCore AndrosynthExtra
    | LiveArilou CombatantCore ArilouExtra
    | LiveChenjesu CombatantCore
    | LiveChmmr CombatantCore ChmmrExtra
    | LiveDruuge CombatantCore
    | LiveEarthling CombatantCore
    | LiveIlwrath CombatantCore
    | LiveKohrAh CombatantCore
    | LiveMelnorme CombatantCore MelnormeExtra
    | LiveMmrnmhrm CombatantCore MmrnmhrmExtra
    | LiveMycon CombatantCore
    | LiveOrz CombatantCore OrzExtra
    | LivePkunk CombatantCore PkunkExtra
    | LiveShofixti CombatantCore ShofixtiExtra
    | LiveSlylandro CombatantCore
    | LiveSpathi CombatantCore
    | LiveSupox CombatantCore SupoxExtra
    | LiveSyreen CombatantCore
    | LiveThraddash CombatantCore ThraddashExtra
    | LiveUmgah CombatantCore UmgahExtra
    | LiveUrQuan CombatantCore
    | LiveUtwig CombatantCore
    | LiveVux CombatantCore VuxExtra
    | LiveYehat CombatantCore
    | LiveZoqFotPik CombatantCore
