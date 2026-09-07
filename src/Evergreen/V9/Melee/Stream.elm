module Evergreen.V9.Melee.Stream exposing (..)

import Evergreen.V9.Melee.Element
import Evergreen.V9.Melee.Id
import Evergreen.V9.Melee.ShipState
import Evergreen.V9.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V9.Melee.Units.FrameCount
    , combatants : Evergreen.V9.Melee.Units.Sided Evergreen.V9.Melee.ShipState.Combatant
    , changed : List Evergreen.V9.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V9.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
