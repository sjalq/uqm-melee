module Evergreen.V6.Melee.Battle exposing (..)

import Dict
import Evergreen.V6.Melee.Element
import Evergreen.V6.Melee.Id
import Evergreen.V6.Melee.Rng
import Evergreen.V6.Melee.ShipState
import Evergreen.V6.Melee.Units


type alias Arena =
    { frame : Evergreen.V6.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V6.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V6.Melee.Rng.Seed
    , space : Evergreen.V6.Melee.Units.WorldExtent
    , combatants : Evergreen.V6.Melee.Units.Sided Evergreen.V6.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V6.Melee.Element.Element
    , queue : List Evergreen.V6.Melee.Id.ElementId
    , nextElementId : Int
    }
