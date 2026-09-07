module Evergreen.V6.Melee.Location exposing (..)

import Evergreen.V6.Melee.Input
import Evergreen.V6.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V6.Melee.Local.Mode
    , difficulty : Evergreen.V6.Melee.Input.CyborgRating
    }
