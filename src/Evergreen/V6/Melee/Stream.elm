module Evergreen.V6.Melee.Stream exposing (..)

import Evergreen.V6.Melee.Element
import Evergreen.V6.Melee.Id
import Evergreen.V6.Melee.ShipState
import Evergreen.V6.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V6.Melee.Units.FrameCount
    , combatants : Evergreen.V6.Melee.Units.Sided Evergreen.V6.Melee.ShipState.Combatant
    , changed : List Evergreen.V6.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V6.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
