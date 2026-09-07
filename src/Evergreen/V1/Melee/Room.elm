module Evergreen.V1.Melee.Room exposing (..)

import Dict
import Evergreen.V1.Melee.Input
import Evergreen.V1.Melee.Local
import Evergreen.V1.Melee.Preview
import Evergreen.V1.Melee.Ranking
import Evergreen.V1.Melee.Ship
import Evergreen.V1.Melee.Stream
import Evergreen.V1.Melee.Units


type SeatControl
    = Human
    | Computer


type alias Snapshot =
    { code : String
    , side : Evergreen.V1.Melee.Units.Side
    , game : Evergreen.V1.Melee.Local.Model
    , connected : Evergreen.V1.Melee.Units.Sided Bool
    , controllers : Evergreen.V1.Melee.Units.Sided SeatControl
    , ready : Evergreen.V1.Melee.Units.Sided Bool
    , revision : Int
    , ranked : Maybe Evergreen.V1.Melee.Ranking.View
    }


type alias SpectatorSnapshot =
    { code : String
    , game : Evergreen.V1.Melee.Local.Model
    , connected : Evergreen.V1.Melee.Units.Sided Bool
    , controllers : Evergreen.V1.Melee.Units.Sided SeatControl
    , revision : Int
    }


type Client
    = Browsing
    | Seated Snapshot
    | Watching SpectatorSnapshot


type alias GameListing =
    { code : String
    , names : Evergreen.V1.Melee.Units.Sided String
    , stage : String
    , viewers : Int
    }


type alias Listing =
    { code : String
    , name : String
    , ships : Int
    , points : Int
    , fleet : List Evergreen.V1.Melee.Ship.ShipKind
    }


type alias Seat =
    { session : String
    , client : Maybe String
    }


type alias Room =
    { code : String
    , seats : Evergreen.V1.Melee.Units.Sided (Maybe Seat)
    , game : Evergreen.V1.Melee.Local.Model
    , inputs : Evergreen.V1.Melee.Units.Sided Evergreen.V1.Melee.Input.BattleInput
    , controllers : Evergreen.V1.Melee.Units.Sided SeatControl
    , ready : Evergreen.V1.Melee.Units.Sided Bool
    , revision : Int
    , lastBroadcast : Maybe Evergreen.V1.Melee.Local.Model
    , broadcastAt : Int
    , spectators : Dict.Dict String String
    , touched : Int
    , ranked : Maybe Evergreen.V1.Melee.Ranking.Match
    }


type alias Host =
    { rooms : Dict.Dict String Room
    , nextId : Int
    , now : Int
    , previewClients : Dict.Dict String String
    , previewAt : Int
    , players : Dict.Dict String Evergreen.V1.Melee.Ranking.Profile
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
    | Add Evergreen.V1.Melee.Ship.ShipKind
    | Remove Int
    | ReplaceFleet String (List Evergreen.V1.Melee.Ship.ShipKind)
    | Visit String Bool
    | PreviewSubscription Bool
    | SetController Evergreen.V1.Melee.Units.Side SeatControl
    | Ready
    | Pick Int
    | RandomPick
    | Controls Evergreen.V1.Melee.Input.BattleInput
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
    = PlayerStatus Evergreen.V1.Melee.Ranking.Profile Bool
    | MatchFound Snapshot
    | RoomsAvailable (List Listing)
    | CombatDelta String Int Evergreen.V1.Melee.Stream.Delta
    | ArenaPreview Evergreen.V1.Melee.Preview.Preview
    | GamesAvailable (List GameListing)
    | SpectatorView SpectatorSnapshot
    | RoomSnapshot Snapshot
    | RoomLeft
    | RoomError String
