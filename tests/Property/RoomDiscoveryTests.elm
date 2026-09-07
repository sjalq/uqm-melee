module Property.RoomDiscoveryTests exposing (suite)

import Expect
import Melee.Room as Room
import Melee.Ship exposing (ShipKind(..))
import Test exposing (..)


send session client message host =
    Room.handle session client message host |> Tuple.first


waiting =
    send "host" "h" Room.CreateRoom Room.init


suite : Test
suite =
    describe "Room discovery"
        [ test "a waiting connected fleet is discoverable" <|
            \() -> Room.discover waiting |> List.map (\r -> ( r.code, r.name, r.ships )) |> Expect.equal [ ( "M00001", "Gold fleet", 4 ) ]
        , test "public listing follows fleet edits" <|
            \() -> waiting |> send "host" "h" (Room.ReplaceFleet "Visitors" [ Shofixti ]) |> Room.discover |> Expect.equal [ { code = "M00001", name = "Visitors", ships = 1, points = 5, fleet = [ Shofixti ] } ]
        , test "full rooms disappear and reopen when a seat leaves" <|
            \() ->
                let
                    full =
                        waiting |> send "guest" "g" (Room.JoinRoom "M00001")

                    reopened =
                        full |> send "guest" "g" Room.LeaveRoom
                in
                Expect.equal ( [], Room.discover waiting ) ( Room.discover full, Room.discover reopened )
        , test "disconnected hosts are not advertised" <|
            \() -> waiting |> Room.disconnect "host" "h" |> Tuple.first |> Room.discover |> Expect.equal []
        , test "a disconnected reserved seat is not advertised as available" <|
            \() -> waiting |> send "guest" "g" (Room.JoinRoom "M00001") |> Room.disconnect "guest" "g" |> Tuple.first |> Room.discover |> Expect.equal []
        , test "an abandoned active match is not advertised" <|
            \() -> waiting |> send "guest" "g" (Room.JoinRoom "M00001") |> send "host" "h" Room.Ready |> send "guest" "g" Room.Ready |> send "guest" "g" Room.LeaveRoom |> Room.discover |> Expect.equal []
        , test "browsers can fetch the directory without joining or changing state" <|
            \() -> Room.handle "visitor" "v" Room.DiscoverRooms waiting |> Expect.equal ( waiting, [ { client = "v", message = Room.RoomsAvailable (Room.discover waiting) }, { client = "v", message = Room.GamesAvailable (Room.games waiting) } ] )
        , test "two simultaneous join attempts cannot overfill a discovered room" <|
            \() ->
                let
                    full =
                        waiting |> send "guest" "g" (Room.JoinRoom "M00001")
                in
                full |> send "other" "o" (Room.JoinRoom "M00001") |> Expect.equal full
        ]
