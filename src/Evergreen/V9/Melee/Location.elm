module Evergreen.V9.Melee.Location exposing (..)

import Evergreen.V9.Melee.Input
import Evergreen.V9.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V9.Melee.Local.Mode
    , difficulty : Evergreen.V9.Melee.Input.CyborgRating
    }
