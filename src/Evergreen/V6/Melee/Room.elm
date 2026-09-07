module Evergreen.V6.Melee.Room exposing (..)

import Dict
import Evergreen.V6.Melee.Input
import Evergreen.V6.Melee.Local
import Evergreen.V6.Melee.Preview
import Evergreen.V6.Melee.Ranking
import Evergreen.V6.Melee.Ship
import Evergreen.V6.Melee.Stream
import Evergreen.V6.Melee.Units


type SeatControl
    = Human
    | Computer


type alias Snapshot =
    { code : String
    , side : Evergreen.V6.Melee.Units.Side
    , game : Evergreen.V6.Melee.Local.Model
    , connected : Evergreen.V6.Melee.Units.Sided Bool
    , controllers : Evergreen.V6.Melee.Units.Sided SeatControl
    , ready : Evergreen.V6.Melee.Units.Sided Bool
    , revision : Int
    , ranked : Maybe Evergreen.V6.Melee.Ranking.View
    }


type alias SpectatorSnapshot =
    { code : String
    , game : Evergreen.V6.Melee.Local.Model
    , connected : Evergreen.V6.Melee.Units.Sided Bool
    , controllers : Evergreen.V6.Melee.Units.Sided SeatControl
    , revision : Int
    }


type Client
    = Browsing
    | Seated Snapshot
    | Watching SpectatorSnapshot


type alias GameListing =
    { code : String
    , names : Evergreen.V6.Melee.Units.Sided String
    , stage : String
    , viewers : Int
    }


type alias Listing =
    { code : String
    , name : String
    , ships : Int
    , points : Int
    , fleet : List Evergreen.V6.Melee.Ship.ShipKind
    }


type alias Seat =
    { session : String
    , client : Maybe String
    }


type alias Room =
    { code : String
    , seats : Evergreen.V6.Melee.Units.Sided (Maybe Seat)
    , game : Evergreen.V6.Melee.Local.Model
    , inputs : Evergreen.V6.Melee.Units.Sided Evergreen.V6.Melee.Input.BattleInput
    , controllers : Evergreen.V6.Melee.Units.Sided SeatControl
    , ready : Evergreen.V6.Melee.Units.Sided Bool
    , revision : Int
    , lastBroadcast : Maybe Evergreen.V6.Melee.Local.Model
    , broadcastAt : Int
    , spectators : Dict.Dict String String
    , touched : Int
    , ranked : Maybe Evergreen.V6.Melee.Ranking.Match
    }


type alias RoomSetup =
    { names : Evergreen.V6.Melee.Units.Sided String
    , fleets : Evergreen.V6.Melee.Units.Sided (List Evergreen.V6.Melee.Ship.ShipKind)
    , controllers : Evergreen.V6.Melee.Units.Sided SeatControl
    }


type alias Host =
    { rooms : Dict.Dict String Room
    , roomSetups : Dict.Dict String RoomSetup
    , clientRooms : Dict.Dict String String
    , nextId : Int
    , now : Int
    , previewClients : Dict.Dict String String
    , previewAt : Int
    , previewGame : Maybe Evergreen.V6.Melee.Local.Model
    , players : Dict.Dict String Evergreen.V6.Melee.Ranking.Profile
    , queue :
        List
            { session : String
            , client : String
            }
    }


type ToHost
    = Identify
    | FindMatch
    | CancelSearch
    | SetPlayerName String
    | DiscoverRooms
    | CreateRoom
    | JoinRoom String
    | WatchRoom String
    | LeaveRoom
    | Rename String
    | Add Evergreen.V6.Melee.Ship.ShipKind
    | Remove Int
    | ReplaceFleet String (List Evergreen.V6.Melee.Ship.ShipKind)
    | Visit String Bool
    | PreviewSubscription Bool
    | SetController Evergreen.V6.Melee.Units.Side SeatControl
    | Ready
    | Pick Int
    | RandomPick
    | Controls Evergreen.V6.Melee.Input.BattleInput
    | Pause
    | Suspend
    | Hangar
    | Rematch


type LocalMsg
    = Tick
    | KeyDown String
    | KeyUp String
    | Restart


type ToSeat
    = PlayerStatus Evergreen.V6.Melee.Ranking.Profile Bool
    | MatchFound Snapshot
    | RoomsAvailable (List Listing)
    | CombatDelta String Int Evergreen.V6.Melee.Stream.Delta
    | ArenaPreview Evergreen.V6.Melee.Preview.Preview
    | GamesAvailable (List GameListing)
    | SpectatorView SpectatorSnapshot
    | RoomSnapshot Snapshot
    | RoomLeft
    | RoomError String
