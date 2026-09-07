module Evergreen.V5.Melee.Location exposing (..)

import Evergreen.V5.Melee.Input
import Evergreen.V5.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V5.Melee.Local.Mode
    , difficulty : Evergreen.V5.Melee.Input.CyborgRating
    }
