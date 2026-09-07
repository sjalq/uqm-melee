module Evergreen.V5.Melee.Local exposing (..)

import Evergreen.V5.Melee.Battle
import Evergreen.V5.Melee.Graphics
import Evergreen.V5.Melee.Input
import Evergreen.V5.Melee.Rng
import Evergreen.V5.Melee.Ship
import Evergreen.V5.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V5.Melee.Ship.ShipKind) (Maybe Evergreen.V5.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V5.Melee.Battle.Arena
    | Combat Evergreen.V5.Melee.Battle.Arena
    | Paused Evergreen.V5.Melee.Battle.Arena
    | RoundOver Int Evergreen.V5.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V5.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V5.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V5.Melee.Input.CyborgRating
    , fleets : Evergreen.V5.Melee.Units.Sided (List Evergreen.V5.Melee.Ship.ShipKind)
    , remaining : Evergreen.V5.Melee.Units.Sided (List Evergreen.V5.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V5.Melee.Units.Side
    , seed : Evergreen.V5.Melee.Rng.Seed
    , graphics : Evergreen.V5.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V5.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V5.Melee.Units.Side
    | Rename Evergreen.V5.Melee.Units.Side String
    | SetDifficulty Evergreen.V5.Melee.Input.CyborgRating
    | Add Evergreen.V5.Melee.Ship.ShipKind
    | Remove Evergreen.V5.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V5.Melee.Units.Side Int
    | RandomPick Evergreen.V5.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
