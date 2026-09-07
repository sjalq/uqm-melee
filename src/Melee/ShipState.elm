module Melee.ShipState exposing
    ( AndrosynthExtra(..)
    , ArilouExtra(..)
    , ChmmrExtra(..)
    , Combatant(..)
    , CombatantCore
    , MelnormeExtra
    , MmrnmhrmExtra
    , MmrnmhrmForm(..)
    , MotionFlags
    , OrzExtra
    , PkunkExtra(..)
    , PumpLevel(..)
    , ShofixtiExtra(..)
    , SupoxExtra(..)
    , ThraddashExtra(..)
    , UmgahExtra
    , VuxExtra(..)
    , core
    , kind
    , setCore
    )

{-| Live STARSHIP plus the per-race `RACE_DESC.data` blob.

A combatant is tagged with its `ShipKind` extra so an Androsynth blazer
flag cannot sit on a Pkunk, and a phoenix handle cannot sit on an
Earthling (MISI). Common STARSHIP fields live in `CombatantCore`.

Crew is stored on the ship `Element` (that is what checksum.c CRCs).
Energy, weapon/special/energy counters, and live characteristics live
here: they are not in the element CRC, but they determine which
elements get spawned.

-}

import Melee.Id exposing (ElementId)
import Melee.Input exposing (BattleInput, Turn)
import Melee.Ship exposing (Characteristics, ShipKind(..))
import Melee.Units exposing (Facing, Wait)


{-| Heat-of-battle STATUS\_FLAGS that are not input bits.
LEFT/RIGHT/THRUST/WEAPON/SPECIAL are `input` / `oldInput` instead, so
"both left and right" cannot be represented (see `Melee.Input.Turn`).
-}
type alias MotionFlags =
    { lowOnEnergy : Bool
    , beyondMaxSpeed : Bool
    , atMaxSpeed : Bool
    , inGravityWell : Bool
    , playVictoryDitty : Bool
    }


{-| STARSHIP fields shared by every live ship.

    element          HELEMENT hShip
    characteristics  live copy; VUX limpets, afterburner, transform, blazer mutate this
    energy           SHIP_INFO.energy_level (0..maxEnergy)
    maxEnergy        SHIP_INFO.max_energy (does not change in melee)
    maxCrew          SHIP_INFO.max_crew (Syreen 42; starting crew is 12)
    weaponWait       STARSHIP.weapon_counter
    specialWait      STARSHIP.special_counter
    energyWait       STARSHIP.energy_counter
    facing           STARSHIP.ShipFacing
    input            cur_status_flags input bits, after race preprocess may have mutated them
    oldInput         old_status_flags; status.c copies cur -> old at end of postprocess

-}
type alias CombatantCore =
    { element : ElementId
    , characteristics : Characteristics
    , energy : Int
    , maxEnergy : Int
    , maxCrew : Int
    , weaponWait : Wait
    , specialWait : Wait
    , energyWait : Wait
    , facing : Facing
    , input : BattleInput
    , shieldTicks : Int
    , confusedTicks : Int
    , chargeTicks : Int
    , cloaked : Bool
    , oldInput : BattleInput
    , flags : MotionFlags
    }


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


kind : Combatant -> ShipKind
kind combatant =
    case combatant of
        LiveAndrosynth _ _ ->
            Androsynth

        LiveArilou _ _ ->
            Arilou

        LiveChenjesu _ ->
            Chenjesu

        LiveChmmr _ _ ->
            Chmmr

        LiveDruuge _ ->
            Druuge

        LiveEarthling _ ->
            Earthling

        LiveIlwrath _ ->
            Ilwrath

        LiveKohrAh _ ->
            KohrAh

        LiveMelnorme _ _ ->
            Melnorme

        LiveMmrnmhrm _ _ ->
            Mmrnmhrm

        LiveMycon _ ->
            Mycon

        LiveOrz _ _ ->
            Orz

        LivePkunk _ _ ->
            Pkunk

        LiveShofixti _ _ ->
            Shofixti

        LiveSlylandro _ ->
            Slylandro

        LiveSpathi _ ->
            Spathi

        LiveSupox _ _ ->
            Supox

        LiveSyreen _ ->
            Syreen

        LiveThraddash _ _ ->
            Thraddash

        LiveUmgah _ _ ->
            Umgah

        LiveUrQuan _ ->
            UrQuan

        LiveUtwig _ ->
            Utwig

        LiveVux _ _ ->
            Vux

        LiveYehat _ ->
            Yehat

        LiveZoqFotPik _ ->
            ZoqFotPik


{-| Guardian vs comet. Live stats are always `CombatantCore.characteristics`.
Blazer keeps the Guardian copy so a transform-back cannot restock and
wipe VUX limpets that landed while blazing.
-}
type AndrosynthExtra
    = Guardian
    | Blazer { guardian : Characteristics }


{-| Arilou special is a 5-frame hyperjump (HYPER\_LIFE). Teleporting ships
are NONSOLID / not on the field.
-}
type ArilouExtra
    = Present
    | Teleporting Wait


{-| Tractor beam. The lock is the enemy ship element (there is only one).
Zap-sats are `Melee.Element.ChmmrSatellite` nodes, not extra state.
-}
type ChmmrExtra
    = TractorIdle
    | TractorOn


{-| Melnorme primary charge. MAX\_PUMP = 4; LEVEL\_COUNTER = 72 frames
per step while the weapon key is held.
-}
type PumpLevel
    = Pump1
    | Pump2
    | Pump3
    | Pump4


type alias MelnormeExtra =
    { pump : PumpLevel
    , levelCounter : Wait
    }


{-| Transform. `otherWing` is the stored inactive CHARACTERISTIC\_STUFF
(C RACE\_DESC.data). It is not restocked, so limpets survive a transform.
-}
type MmrnmhrmForm
    = XWing
    | YWing


type alias MmrnmhrmExtra =
    { form : MmrnmhrmForm
    , otherWing : Characteristics
    }


{-| Rotating howitzer. Marines are `Melee.Element.OrzMarine` nodes.
TURRET\_WAIT = 3.
-}
type alias OrzExtra =
    { turretFacing : Facing
    , turretWait : Wait
    }


{-| Phoenix resurrection. The phoenix element is a FINITE\_LIFE
animation; on death it may spawn a new Fury from the same side.
-}
type PkunkExtra
    = Flying
    | Phoenix ElementId


type ShofixtiExtra
    = SafetyClosed
    | OpeningSafety
    | SafetyOpen
    | ArmingDevice
    | Armed
    | GloryDevice


{-| Special converts turn into lateral thrust. `ForwardOnly` is the
inertial default; `Strafing` is the special-held state.
-}
type SupoxExtra
    = ForwardOnly
    | Strafing Turn


{-| Afterburner. Cruise thrust is stored, not restocked, so limpets
survive afterburner off.
-}
type ThraddashExtra
    = Cruise
    | Afterburning { savedMaxThrust : Int, savedThrustIncrement : Int }


{-| Zip-zip needs the previous facing so a 180-degree reverse can be
detected (umgah.c `prevFacing`).
-}
type alias UmgahExtra =
    { prevFacing : Facing
    }


{-| VUX warps in close to the enemy on APPEARING. After that it is a
normal ship. Limpets are elements parented to the victim.
-}
type VuxExtra
    = WarpPending
    | OnField


core : Combatant -> CombatantCore
core combatant =
    case combatant of
        LiveAndrosynth c _ ->
            c

        LiveArilou c _ ->
            c

        LiveChenjesu c ->
            c

        LiveChmmr c _ ->
            c

        LiveDruuge c ->
            c

        LiveEarthling c ->
            c

        LiveIlwrath c ->
            c

        LiveKohrAh c ->
            c

        LiveMelnorme c _ ->
            c

        LiveMmrnmhrm c _ ->
            c

        LiveMycon c ->
            c

        LiveOrz c _ ->
            c

        LivePkunk c _ ->
            c

        LiveShofixti c _ ->
            c

        LiveSlylandro c ->
            c

        LiveSpathi c ->
            c

        LiveSupox c _ ->
            c

        LiveSyreen c ->
            c

        LiveThraddash c _ ->
            c

        LiveUmgah c _ ->
            c

        LiveUrQuan c ->
            c

        LiveUtwig c ->
            c

        LiveVux c _ ->
            c

        LiveYehat c ->
            c

        LiveZoqFotPik c ->
            c


setCore : CombatantCore -> Combatant -> Combatant
setCore c combatant =
    case combatant of
        LiveAndrosynth _ e ->
            LiveAndrosynth c e

        LiveArilou _ e ->
            LiveArilou c e

        LiveChenjesu _ ->
            LiveChenjesu c

        LiveChmmr _ e ->
            LiveChmmr c e

        LiveDruuge _ ->
            LiveDruuge c

        LiveEarthling _ ->
            LiveEarthling c

        LiveIlwrath _ ->
            LiveIlwrath c

        LiveKohrAh _ ->
            LiveKohrAh c

        LiveMelnorme _ e ->
            LiveMelnorme c e

        LiveMmrnmhrm _ e ->
            LiveMmrnmhrm c e

        LiveMycon _ ->
            LiveMycon c

        LiveOrz _ e ->
            LiveOrz c e

        LivePkunk _ e ->
            LivePkunk c e

        LiveShofixti _ e ->
            LiveShofixti c e

        LiveSlylandro _ ->
            LiveSlylandro c

        LiveSpathi _ ->
            LiveSpathi c

        LiveSupox _ e ->
            LiveSupox c e

        LiveSyreen _ ->
            LiveSyreen c

        LiveThraddash _ e ->
            LiveThraddash c e

        LiveUmgah _ e ->
            LiveUmgah c e

        LiveUrQuan _ ->
            LiveUrQuan c

        LiveUtwig _ ->
            LiveUtwig c

        LiveVux _ e ->
            LiveVux c e

        LiveYehat _ ->
            LiveYehat c

        LiveZoqFotPik _ ->
            LiveZoqFotPik c
