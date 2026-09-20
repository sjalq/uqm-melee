module Evergreen.V12.Melee.Local exposing (..)

import Evergreen.V12.Melee.Battle
import Evergreen.V12.Melee.Graphics
import Evergreen.V12.Melee.Input
import Evergreen.V12.Melee.Rng
import Evergreen.V12.Melee.Ship
import Evergreen.V12.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V12.Melee.Ship.ShipKind) (Maybe Evergreen.V12.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V12.Melee.Battle.Arena
    | Combat Evergreen.V12.Melee.Battle.Arena
    | Paused Evergreen.V12.Melee.Battle.Arena
    | RoundOver Int Evergreen.V12.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V12.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V12.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V12.Melee.Input.CyborgRating
    , fleets : Evergreen.V12.Melee.Units.Sided (List Evergreen.V12.Melee.Ship.ShipKind)
    , remaining : Evergreen.V12.Melee.Units.Sided (List Evergreen.V12.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V12.Melee.Units.Side
    , seed : Evergreen.V12.Melee.Rng.Seed
    , graphics : Evergreen.V12.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V12.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V12.Melee.Units.Side
    | Rename Evergreen.V12.Melee.Units.Side String
    | SetDifficulty Evergreen.V12.Melee.Input.CyborgRating
    | Add Evergreen.V12.Melee.Ship.ShipKind
    | Remove Evergreen.V12.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V12.Melee.Units.Side Int
    | RandomPick Evergreen.V12.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
