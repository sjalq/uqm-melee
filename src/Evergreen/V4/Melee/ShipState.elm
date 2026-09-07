module Evergreen.V4.Melee.ShipState exposing (..)

import Evergreen.V4.Melee.Id
import Evergreen.V4.Melee.Input
import Evergreen.V4.Melee.Ship
import Evergreen.V4.Melee.Units


type alias MotionFlags =
    { lowOnEnergy : Bool
    , beyondMaxSpeed : Bool
    , atMaxSpeed : Bool
    , inGravityWell : Bool
    , playVictoryDitty : Bool
    }


type alias CombatantCore =
    { element : Evergreen.V4.Melee.Id.ElementId
    , characteristics : Evergreen.V4.Melee.Ship.Characteristics
    , energy : Int
    , maxEnergy : Int
    , maxCrew : Int
    , weaponWait : Evergreen.V4.Melee.Units.Wait
    , specialWait : Evergreen.V4.Melee.Units.Wait
    , energyWait : Evergreen.V4.Melee.Units.Wait
    , facing : Evergreen.V4.Melee.Units.Facing
    , input : Evergreen.V4.Melee.Input.BattleInput
    , shieldTicks : Int
    , confusedTicks : Int
    , chargeTicks : Int
    , cloaked : Bool
    , oldInput : Evergreen.V4.Melee.Input.BattleInput
    , flags : MotionFlags
    }


type AndrosynthExtra
    = Guardian
    | Blazer
        { guardian : Evergreen.V4.Melee.Ship.Characteristics
        }


type ArilouExtra
    = Present
    | Teleporting Evergreen.V4.Melee.Units.Wait


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
    , levelCounter : Evergreen.V4.Melee.Units.Wait
    }


type MmrnmhrmForm
    = XWing
    | YWing


type alias MmrnmhrmExtra =
    { form : MmrnmhrmForm
    , otherWing : Evergreen.V4.Melee.Ship.Characteristics
    }


type alias OrzExtra =
    { turretFacing : Evergreen.V4.Melee.Units.Facing
    , turretWait : Evergreen.V4.Melee.Units.Wait
    }


type PkunkExtra
    = Flying
    | Phoenix Evergreen.V4.Melee.Id.ElementId


type ShofixtiExtra
    = SafetyClosed
    | OpeningSafety
    | SafetyOpen
    | ArmingDevice
    | Armed
    | GloryDevice


type SupoxExtra
    = ForwardOnly
    | Strafing Evergreen.V4.Melee.Input.Turn


type ThraddashExtra
    = Cruise
    | Afterburning
        { savedMaxThrust : Int
        , savedThrustIncrement : Int
        }


type alias UmgahExtra =
    { prevFacing : Evergreen.V4.Melee.Units.Facing
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
