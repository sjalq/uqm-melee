module Evergreen.V12.Melee.Jev exposing (..)

import Evergreen.V12.Melee.Ship
import Evergreen.V12.Melee.Units


type Button
    = Idle
    | Left
    | Right
    | Thrust
    | Fire
    | Special


type alias Memory =
    String


type alias ShipSight =
    { kind : Evergreen.V12.Melee.Ship.ShipKind
    , name : String
    , crew : Int
    , energy : Int
    , maxEnergy : Int
    , facing : Int
    , x : Int
    , y : Int
    , speed : Int
    , weaponReady : Bool
    , specialReady : Bool
    }


type alias Threat =
    { label : String
    , x : Int
    , y : Int
    , range : Int
    }


type alias Sight =
    { frame : Int
    , side : Evergreen.V12.Melee.Units.Side
    , own : ShipSight
    , foe : ShipSight
    , bearing : Int
    , range : Int
    , threats : List Threat
    }


type alias Client =
    { enabled : Bool
    , button : Button
    , pending : Bool
    , token : Maybe String
    , lastAskedMs : Float
    , status : String
    , memories : List Memory
    , history : List Sight
    }
