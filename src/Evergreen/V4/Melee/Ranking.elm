module Evergreen.V4.Melee.Ranking exposing (..)

import Evergreen.V4.Melee.Units


type Outcome
    = Cancelled
    | Scored
        { winner : Maybe Evergreen.V4.Melee.Units.Side
        , changes : Evergreen.V4.Melee.Units.Sided Int
        , ratings : Evergreen.V4.Melee.Units.Sided Int
        }


type alias View =
    { ratings : Evergreen.V4.Melee.Units.Sided Int
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
    { players : Evergreen.V4.Melee.Units.Sided String
    , ratings : Evergreen.V4.Melee.Units.Sided Int
    , deadline : Maybe Int
    , started : Bool
    , away : Evergreen.V4.Melee.Units.Sided (Maybe Int)
    , outcome : Maybe Outcome
    }
