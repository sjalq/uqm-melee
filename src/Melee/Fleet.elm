module Melee.Fleet exposing
    ( Fleet
    , FleetSlot(..)
    , Slot(..)
    , SlotColumn(..)
    , SlotRow(..)
    , Team
    , TeamName(..)
    , fleetSize
    , maxTeamNameChars
    )

{-| A Super Melee team: exactly 14 ship slots (2 rows x 7 columns) and a
name of at most 30 characters.

Source: supermelee/melee.h (NUM\_MELEE\_ROWS, NUM\_MELEE\_COLUMNS,
MELEE\_FLEET\_SIZE, MAX\_TEAM\_CHARS), meleesetup.h (MeleeTeam),
meleeship.h (MELEE\_NONE = empty slot).

There is no point cap in UQM Super Melee; the fleet value is displayed
(MeleeTeam\_getValue) and used for bragging rights only. A slot is either
empty or holds one of the 25 melee ships. Ships carry no per-slot state in
the fleet: crew and energy are always full when a ship enters battle.

-}

import Melee.Ship exposing (ShipKind)


type SlotRow
    = RowTop
    | RowBottom


type SlotColumn
    = Col1
    | Col2
    | Col3
    | Col4
    | Col5
    | Col6
    | Col7


{-| FleetShipIndex, but a coordinate instead of an unchecked COUNT 0..13.
-}
type Slot
    = Slot SlotRow SlotColumn


type FleetSlot
    = EmptySlot
    | ShipSlot ShipKind


{-| Fourteen slots, positionally fixed. A record rather than a List so that
the fleet can never have 13 or 15 entries. Order matters: the pick screen
lays the fleet out in this order and the "random ship" pick chooses among
the still-available slots.
-}
type alias Fleet =
    { r1c1 : FleetSlot
    , r1c2 : FleetSlot
    , r1c3 : FleetSlot
    , r1c4 : FleetSlot
    , r1c5 : FleetSlot
    , r1c6 : FleetSlot
    , r1c7 : FleetSlot
    , r2c1 : FleetSlot
    , r2c2 : FleetSlot
    , r2c3 : FleetSlot
    , r2c4 : FleetSlot
    , r2c5 : FleetSlot
    , r2c6 : FleetSlot
    , r2c7 : FleetSlot
    }


fleetSize : Int
fleetSize =
    14


{-| Max 30 characters (MAX\_TEAM\_CHARS). Enforced by the smart constructor
once implemented; the constructor is exposed only for the wire codecs.
-}
type TeamName
    = TeamName String


maxTeamNameChars : Int
maxTeamNameChars =
    30


type alias Team =
    { name : TeamName
    , fleet : Fleet
    }
