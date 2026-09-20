module Evergreen.V12.Melee.Stream exposing (..)

import Evergreen.V12.Melee.Element
import Evergreen.V12.Melee.Id
import Evergreen.V12.Melee.ShipState
import Evergreen.V12.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V12.Melee.Units.FrameCount
    , combatants : Evergreen.V12.Melee.Units.Sided Evergreen.V12.Melee.ShipState.Combatant
    , changed : List Evergreen.V12.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V12.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
