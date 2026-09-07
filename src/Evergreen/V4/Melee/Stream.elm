module Evergreen.V4.Melee.Stream exposing (..)

import Evergreen.V4.Melee.Element
import Evergreen.V4.Melee.Id
import Evergreen.V4.Melee.ShipState
import Evergreen.V4.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V4.Melee.Units.FrameCount
    , combatants : Evergreen.V4.Melee.Units.Sided Evergreen.V4.Melee.ShipState.Combatant
    , changed : List Evergreen.V4.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V4.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
