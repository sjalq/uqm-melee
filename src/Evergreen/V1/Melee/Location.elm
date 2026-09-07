module Evergreen.V1.Melee.Location exposing (..)

import Evergreen.V1.Melee.Input
import Evergreen.V1.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V1.Melee.Local.Mode
    , difficulty : Evergreen.V1.Melee.Input.CyborgRating
    }
