module Evergreen.V5.Melee.Battle exposing (..)

import Dict
import Evergreen.V5.Melee.Element
import Evergreen.V5.Melee.Id
import Evergreen.V5.Melee.Rng
import Evergreen.V5.Melee.ShipState
import Evergreen.V5.Melee.Units


type alias Arena =
    { frame : Evergreen.V5.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V5.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V5.Melee.Rng.Seed
    , space : Evergreen.V5.Melee.Units.WorldExtent
    , combatants : Evergreen.V5.Melee.Units.Sided Evergreen.V5.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V5.Melee.Element.Element
    , queue : List Evergreen.V5.Melee.Id.ElementId
    , nextElementId : Int
    }
