module Evergreen.V4.Melee.Battle exposing (..)

import Dict
import Evergreen.V4.Melee.Element
import Evergreen.V4.Melee.Id
import Evergreen.V4.Melee.Rng
import Evergreen.V4.Melee.ShipState
import Evergreen.V4.Melee.Units


type alias Arena =
    { frame : Evergreen.V4.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V4.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V4.Melee.Rng.Seed
    , space : Evergreen.V4.Melee.Units.WorldExtent
    , combatants : Evergreen.V4.Melee.Units.Sided Evergreen.V4.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V4.Melee.Element.Element
    , queue : List Evergreen.V4.Melee.Id.ElementId
    , nextElementId : Int
    }
