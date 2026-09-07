module Evergreen.V2.Melee.Location exposing (..)

import Evergreen.V2.Melee.Input
import Evergreen.V2.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V2.Melee.Local.Mode
    , difficulty : Evergreen.V2.Melee.Input.CyborgRating
    }
