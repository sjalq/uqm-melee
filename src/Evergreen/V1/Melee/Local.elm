module Evergreen.V1.Melee.Local exposing (..)

import Evergreen.V1.Melee.Battle
import Evergreen.V1.Melee.Graphics
import Evergreen.V1.Melee.Input
import Evergreen.V1.Melee.Rng
import Evergreen.V1.Melee.Ship
import Evergreen.V1.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V1.Melee.Ship.ShipKind) (Maybe Evergreen.V1.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V1.Melee.Battle.Arena
    | Combat Evergreen.V1.Melee.Battle.Arena
    | Paused Evergreen.V1.Melee.Battle.Arena
    | RoundOver Int Evergreen.V1.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V1.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V1.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V1.Melee.Input.CyborgRating
    , fleets : Evergreen.V1.Melee.Units.Sided (List Evergreen.V1.Melee.Ship.ShipKind)
    , remaining : Evergreen.V1.Melee.Units.Sided (List Evergreen.V1.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V1.Melee.Units.Side
    , seed : Evergreen.V1.Melee.Rng.Seed
    , graphics : Evergreen.V1.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V1.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V1.Melee.Units.Side
    | Rename Evergreen.V1.Melee.Units.Side String
    | SetDifficulty Evergreen.V1.Melee.Input.CyborgRating
    | Add Evergreen.V1.Melee.Ship.ShipKind
    | Remove Evergreen.V1.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V1.Melee.Units.Side Int
    | RandomPick Evergreen.V1.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
