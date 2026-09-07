module Evergreen.V2.Melee.Ranking exposing (..)

import Evergreen.V2.Melee.Units


type Outcome
    = Cancelled
    | Scored
        { winner : Maybe Evergreen.V2.Melee.Units.Side
        , changes : Evergreen.V2.Melee.Units.Sided Int
        , ratings : Evergreen.V2.Melee.Units.Sided Int
        }


type alias View =
    { ratings : Evergreen.V2.Melee.Units.Sided Int
    , deadline : Maybe Int
    , outcome : Maybe Outcome
    }


type alias Profile =
    { name : String
    , rating : Int
    , wins : Int
    , losses : Int
    , draws : Int
    , lastChange : Int
    }


type alias Match =
    { players : Evergreen.V2.Melee.Units.Sided String
    , ratings : Evergreen.V2.Melee.Units.Sided Int
    , deadline : Maybe Int
    , started : Bool
    , away : Evergreen.V2.Melee.Units.Sided (Maybe Int)
    , outcome : Maybe Outcome
    }
