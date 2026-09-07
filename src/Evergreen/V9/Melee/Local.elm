module Evergreen.V9.Melee.Local exposing (..)

import Evergreen.V9.Melee.Battle
import Evergreen.V9.Melee.Graphics
import Evergreen.V9.Melee.Input
import Evergreen.V9.Melee.Rng
import Evergreen.V9.Melee.Ship
import Evergreen.V9.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V9.Melee.Ship.ShipKind) (Maybe Evergreen.V9.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V9.Melee.Battle.Arena
    | Combat Evergreen.V9.Melee.Battle.Arena
    | Paused Evergreen.V9.Melee.Battle.Arena
    | RoundOver Int Evergreen.V9.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V9.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V9.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V9.Melee.Input.CyborgRating
    , fleets : Evergreen.V9.Melee.Units.Sided (List Evergreen.V9.Melee.Ship.ShipKind)
    , remaining : Evergreen.V9.Melee.Units.Sided (List Evergreen.V9.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V9.Melee.Units.Side
    , seed : Evergreen.V9.Melee.Rng.Seed
    , graphics : Evergreen.V9.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V9.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V9.Melee.Units.Side
    | Rename Evergreen.V9.Melee.Units.Side String
    | SetDifficulty Evergreen.V9.Melee.Input.CyborgRating
    | Add Evergreen.V9.Melee.Ship.ShipKind
    | Remove Evergreen.V9.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V9.Melee.Units.Side Int
    | RandomPick Evergreen.V9.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
