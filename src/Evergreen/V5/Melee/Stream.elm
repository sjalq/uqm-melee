module Evergreen.V5.Melee.Stream exposing (..)

import Evergreen.V5.Melee.Element
import Evergreen.V5.Melee.Id
import Evergreen.V5.Melee.ShipState
import Evergreen.V5.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V5.Melee.Units.FrameCount
    , combatants : Evergreen.V5.Melee.Units.Sided Evergreen.V5.Melee.ShipState.Combatant
    , changed : List Evergreen.V5.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V5.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
