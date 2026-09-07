module Evergreen.V2.Melee.Local exposing (..)

import Evergreen.V2.Melee.Battle
import Evergreen.V2.Melee.Graphics
import Evergreen.V2.Melee.Input
import Evergreen.V2.Melee.Rng
import Evergreen.V2.Melee.Ship
import Evergreen.V2.Melee.Units


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe Evergreen.V2.Melee.Ship.ShipKind) (Maybe Evergreen.V2.Melee.Ship.ShipKind)
    | Countdown Int Evergreen.V2.Melee.Battle.Arena
    | Combat Evergreen.V2.Melee.Battle.Arena
    | Paused Evergreen.V2.Melee.Battle.Arena
    | RoundOver Int Evergreen.V2.Melee.Battle.Arena
    | Victory (Maybe Evergreen.V2.Melee.Units.Side)


type alias Model =
    { names : Evergreen.V2.Melee.Units.Sided String
    , notice : String
    , difficulty : Evergreen.V2.Melee.Input.CyborgRating
    , fleets : Evergreen.V2.Melee.Units.Sided (List Evergreen.V2.Melee.Ship.ShipKind)
    , remaining : Evergreen.V2.Melee.Units.Sided (List Evergreen.V2.Melee.Ship.ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Evergreen.V2.Melee.Units.Side
    , seed : Evergreen.V2.Melee.Rng.Seed
    , graphics : Evergreen.V2.Melee.Graphics.Quality
    , sound : Bool
    , sounds :
        List
            { id : Int
            , source : String
            , age : Int
            }
    , clock : Float
    , survivor : Maybe Evergreen.V2.Melee.Battle.Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Evergreen.V2.Melee.Units.Side
    | Rename Evergreen.V2.Melee.Units.Side String
    | SetDifficulty Evergreen.V2.Melee.Input.CyborgRating
    | Add Evergreen.V2.Melee.Ship.ShipKind
    | Remove Evergreen.V2.Melee.Units.Side Int
    | SetMode Mode
    | Start
    | Pick Evergreen.V2.Melee.Units.Side Int
    | RandomPick Evergreen.V2.Melee.Units.Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend
