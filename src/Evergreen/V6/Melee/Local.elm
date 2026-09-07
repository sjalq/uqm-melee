module Evergreen.V6.Melee.Local exposing (..)

import Evergreen.V6.Melee.Battle
import Evergreen.V6.Melee.Graphics
import Evergreen.V6.Melee.Input
import Evergreen.V6.Melee.Rng
import Evergreen.V6.Melee.Ship
import Evergreen.V6.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V6.Melee.Ship.ShipKind) (Maybe Evergreen.V6.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V6.Melee.Battle.Arena
    | Combat Evergreen.V6.Melee.Battle.Arena
    | Paused Evergreen.V6.Melee.Battle.Arena
    | RoundOver Int Evergreen.V6.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V6.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V6.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V6.Melee.Input.CyborgRating
    , fleets : Evergreen.V6.Melee.Units.Sided (List Evergreen.V6.Melee.Ship.ShipKind)
    , remaining : Evergreen.V6.Melee.Units.Sided (List Evergreen.V6.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V6.Melee.Units.Side
    , seed : Evergreen.V6.Melee.Rng.Seed
    , graphics : Evergreen.V6.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V6.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V6.Melee.Units.Side
    | Rename Evergreen.V6.Melee.Units.Side String
    | SetDifficulty Evergreen.V6.Melee.Input.CyborgRating
    | Add Evergreen.V6.Melee.Ship.ShipKind
    | Remove Evergreen.V6.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V6.Melee.Units.Side Int
    | RandomPick Evergreen.V6.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
