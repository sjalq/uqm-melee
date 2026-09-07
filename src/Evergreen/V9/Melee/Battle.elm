module Evergreen.V9.Melee.Battle exposing (..)

import Dict
import Evergreen.V9.Melee.Element
import Evergreen.V9.Melee.Id
import Evergreen.V9.Melee.Rng
import Evergreen.V9.Melee.ShipState
import Evergreen.V9.Melee.Units


type alias Arena =
    { frame : Evergreen.V9.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V9.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V9.Melee.Rng.Seed
    , space : Evergreen.V9.Melee.Units.WorldExtent
    , combatants : Evergreen.V9.Melee.Units.Sided Evergreen.V9.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V9.Melee.Element.Element
    , queue : List Evergreen.V9.Melee.Id.ElementId
    , nextElementId : Int
    }
