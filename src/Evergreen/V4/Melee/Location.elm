module Evergreen.V4.Melee.Location exposing (..)

import Evergreen.V4.Melee.Input
import Evergreen.V4.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V4.Melee.Local.Mode
    , difficulty : Evergreen.V4.Melee.Input.CyborgRating
    }
