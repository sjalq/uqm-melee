module Evergreen.V1.Melee.Stream exposing (..)

import Evergreen.V1.Melee.Element
import Evergreen.V1.Melee.Id
import Evergreen.V1.Melee.ShipState
import Evergreen.V1.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V1.Melee.Units.FrameCount
    , combatants : Evergreen.V1.Melee.Units.Sided Evergreen.V1.Melee.ShipState.Combatant
    , changed : List Evergreen.V1.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V1.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
