module Evergreen.V2.Melee.Stream exposing (..)

import Evergreen.V2.Melee.Element
import Evergreen.V2.Melee.Id
import Evergreen.V2.Melee.ShipState
import Evergreen.V2.Melee.Units


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage
    , frame : Evergreen.V2.Melee.Units.FrameCount
    , combatants : Evergreen.V2.Melee.Units.Sided Evergreen.V2.Melee.ShipState.Combatant
    , changed : List Evergreen.V2.Melee.Element.Element
    , removed : List Int
    , queue : List Evergreen.V2.Melee.Id.ElementId
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , interval : Float
    }
