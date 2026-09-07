module Evergreen.V4.Melee.Local exposing (..)

import Evergreen.V4.Melee.Battle
import Evergreen.V4.Melee.Graphics
import Evergreen.V4.Melee.Input
import Evergreen.V4.Melee.Rng
import Evergreen.V4.Melee.Ship
import Evergreen.V4.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V4.Melee.Ship.ShipKind) (Maybe Evergreen.V4.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V4.Melee.Battle.Arena
    | Combat Evergreen.V4.Melee.Battle.Arena
    | Paused Evergreen.V4.Melee.Battle.Arena
    | RoundOver Int Evergreen.V4.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V4.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V4.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V4.Melee.Input.CyborgRating
    , fleets : Evergreen.V4.Melee.Units.Sided (List Evergreen.V4.Melee.Ship.ShipKind)
    , remaining : Evergreen.V4.Melee.Units.Sided (List Evergreen.V4.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V4.Melee.Units.Side
    , seed : Evergreen.V4.Melee.Rng.Seed
    , graphics : Evergreen.V4.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V4.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V4.Melee.Units.Side
    | Rename Evergreen.V4.Melee.Units.Side String
    | SetDifficulty Evergreen.V4.Melee.Input.CyborgRating
    | Add Evergreen.V4.Melee.Ship.ShipKind
    | Remove Evergreen.V4.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V4.Melee.Units.Side Int
    | RandomPick Evergreen.V4.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
