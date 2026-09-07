module Evergreen.V2.Melee.Battle exposing (..)

import Dict
import Evergreen.V2.Melee.Element
import Evergreen.V2.Melee.Id
import Evergreen.V2.Melee.Rng
import Evergreen.V2.Melee.ShipState
import Evergreen.V2.Melee.Units


type alias Arena =
    { frame : Evergreen.V2.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V2.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V2.Melee.Rng.Seed
    , space : Evergreen.V2.Melee.Units.WorldExtent
    , combatants : Evergreen.V2.Melee.Units.Sided Evergreen.V2.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V2.Melee.Element.Element
    , queue : List Evergreen.V2.Melee.Id.ElementId
    , nextElementId : Int
    }
