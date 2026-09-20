module Evergreen.V12.Melee.Location exposing (..)

import Evergreen.V12.Melee.Input
import Evergreen.V12.Melee.Local


type alias Location =
    { room : Maybe String
    , watching : Bool
    , local : Bool
    , watchingList : Bool
    , page : Int
    , roster : Int
    , mode : Evergreen.V12.Melee.Local.Mode
    , difficulty : Evergreen.V12.Melee.Input.CyborgRating
    }
