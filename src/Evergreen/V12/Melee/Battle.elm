module Evergreen.V12.Melee.Battle exposing (..)

import Dict
import Evergreen.V12.Melee.Element
import Evergreen.V12.Melee.Id
import Evergreen.V12.Melee.Rng
import Evergreen.V12.Melee.ShipState
import Evergreen.V12.Melee.Units


type alias Arena =
    { frame : Evergreen.V12.Melee.Units.FrameCount
    , previousLocations : Dict.Dict Int Evergreen.V12.Melee.Units.WorldPoint
    , pumpAcc : Int
    , seed : Evergreen.V12.Melee.Rng.Seed
    , space : Evergreen.V12.Melee.Units.WorldExtent
    , combatants : Evergreen.V12.Melee.Units.Sided Evergreen.V12.Melee.ShipState.Combatant
    , elements : Dict.Dict Int Evergreen.V12.Melee.Element.Element
    , queue : List Evergreen.V12.Melee.Id.ElementId
    , nextElementId : Int
    }
