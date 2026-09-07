module Evergreen.V1.Melee.Battle exposing (..)

import Dict
import Evergreen.V1.Melee.Element
import Evergreen.V1.Melee.Id
import Evergreen.V1.Melee.Rng
import Evergreen.V1.Melee.ShipState
import Evergreen.V1.Melee.Units


type alias Arena =
    { frame : Evergreen.V1.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V1.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V1.Melee.Rng.Seed
    , space : Evergreen.V1.Melee.Units.WorldExtent
    , combatants : Evergreen.V1.Melee.Units.Sided Evergreen.V1.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V1.Melee.Element.Element
    , queue : List Evergreen.V1.Melee.Id.ElementId
    , nextElementId : Int
    }
