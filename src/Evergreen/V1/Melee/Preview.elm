module Evergreen.V1.Melee.Preview exposing (..)

import Evergreen.V1.Melee.Ship


type alias Preview =
    { frame : Int
    , ships :
        List
            { kind : Evergreen.V1.Melee.Ship.ShipKind
            , facing : Int
            , x : Int
            , y : Int
            }
    , shots :
        List
            { x : Int
            , y : Int
            }
    }
