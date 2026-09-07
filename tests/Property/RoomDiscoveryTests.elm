module Property.RoomDiscoveryTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Local as Game
import Melee.Room as Room
import Melee.RoomCode as RoomCode
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Side(..))
import Test exposing (..)


send session client message host =
    Room.handle session client message host |> Tuple.first


waiting =
    send "host" "h" Room.CreateRoom Room.init


code =
    RoomCode.generate "host" "h" 1


suite : Test
suite =
    describe "Room discovery"
        [ test "a waiting connected fleet is discoverable" <|
            \() -> Room.discover waiting |> List.map (\r -> ( r.code, r.name, r.ships )) |> Expect.equal [ ( code, "Gold fleet", 4 ) ]
        , test "public listing follows fleet edits" <|
            \() -> waiting |> send "host" "h" (Room.ReplaceFleet "Visitors" [ Shofixti ]) |> Room.discover |> Expect.equal [ { code = code, name = "Visitors", ships = 1, points = 5, fleet = [ Shofixti ] } ]
        , test "full rooms disappear and reopen when a seat leaves" <|
            \() ->
                let
                    full =
                        waiting |> send "guest" "g" (Room.JoinRoom code)

                    reopened =
                        full |> send "guest" "g" Room.LeaveRoom
                in
                Expect.equal ( [], Room.discover waiting ) ( Room.discover full, Room.discover reopened )
        , test "disconnected hosts are not advertised" <|
            \() -> waiting |> Room.disconnect "host" "h" |> Tuple.first |> Room.discover |> Expect.equal []
        , test "a disconnected reserved seat is not advertised as available" <|
            \() -> waiting |> send "guest" "g" (Room.JoinRoom code) |> Room.disconnect "guest" "g" |> Tuple.first |> Room.discover |> Expect.equal []
        , test "an abandoned active match is not advertised" <|
            \() -> waiting |> send "guest" "g" (Room.JoinRoom code) |> send "host" "h" Room.Ready |> send "guest" "g" Room.Ready |> send "guest" "g" Room.LeaveRoom |> Room.discover |> Expect.equal []
        , test "browsers can fetch the directory without joining or changing state" <|
            \() -> Room.handle "visitor" "v" Room.DiscoverRooms waiting |> Expect.equal ( waiting, [ { client = "v", message = Room.RoomsAvailable (Room.discover waiting) }, { client = "v", message = Room.GamesAvailable (Room.games waiting) } ] )
        , test "two simultaneous join attempts cannot overfill a discovered room" <|
            \() ->
                let
                    full =
                        waiting |> send "guest" "g" (Room.JoinRoom code)
                in
                full |> send "other" "o" (Room.JoinRoom code) |> Expect.equal full
        , fuzz Fuzz.string "codes have eight readable symbols and vary with the allocation serial" <|
            \session ->
                let
                    first =
                        RoomCode.generate session "client" 1

                    second =
                        RoomCode.generate session "client" 2
                in
                Expect.all
                    [ \_ -> Expect.equal 8 (String.length first)
                    , \_ -> Expect.equal True (String.all (\c -> String.contains (String.fromChar c) "23456789ABCDEFGHJKLMNPQRSTUVWXYZ") first)
                    , \_ -> Expect.notEqual first second
                    ]
                    ()
        , test "a colliding allocation skips a reserved code without replacing its setup" <|
            \() ->
                let
                    occupied =
                        { waiting | nextId = 1 }

                    ( allocated, next ) =
                        Room.allocateCode "host" "h" occupied
                in
                Expect.equal ( RoomCode.generate "host" "h" 2, 3, waiting.roomSetups ) ( allocated, next.nextId, next.roomSetups )
        , test "empty room links reopen the saved fleet and controllers without retaining combat state" <|
            \() ->
                let
                    empty =
                        waiting
                            |> send "host" "h" (Room.ReplaceFleet "Returning fleet" [ Shofixti ])
                            |> send "host" "h" (Room.SetController Top Room.Computer)
                            |> send "host" "h" Room.LeaveRoom

                    reopened =
                        empty |> send "returning" "new" (Room.JoinRoom ("  " ++ String.toLower code ++ "  "))
                in
                Expect.all
                    [ \_ -> Expect.equal Nothing (Dict.get code empty.rooms)
                    , \_ -> Expect.equal [] (Room.discover empty)
                    , \_ -> Expect.equal (Just ( [ Shofixti ], Room.Computer, Game.Hangar )) (Dict.get code reopened.rooms |> Maybe.map (\room -> ( room.game.fleets.bottom, room.controllers.top, room.game.phase )))
                    , \_ -> Expect.equal (Just Bottom) (Room.findRoom "returning" "new" reopened |> Maybe.map Tuple.second)
                    , \_ -> Expect.equal Nothing (Dict.get "h" empty.clientRooms)
                    ]
                    ()
        , test "disconnect expiry keeps the reusable link but no active room or stale seat index" <|
            \() ->
                let
                    expired =
                        waiting |> Room.disconnect "host" "h" |> Tuple.first |> Room.tick 600001 |> Tuple.first
                in
                Expect.all
                    [ \_ -> Expect.equal Nothing (Dict.get code expired.rooms)
                    , \_ -> Expect.equal True (Dict.member code expired.roomSetups)
                    , \_ -> Expect.equal Dict.empty expired.clientRooms
                    , \_ -> expired |> send "guest" "g" (Room.JoinRoom code) |> Room.findRoom "guest" "g" |> Maybe.map (Tuple.first >> .code) |> Expect.equal (Just code)
                    ]
                    ()
        , test "unknown codes cannot create rooms" <|
            \() -> Room.handle "guest" "g" (Room.JoinRoom "NOTAROOM") Room.init |> Tuple.first |> Expect.equal Room.init
        , test "saved setups add no tick deliveries or active rooms" <|
            \() ->
                let
                    setup =
                        { names = Game.init.names, fleets = Game.init.fleets, controllers = { bottom = Room.Human, top = Room.Human } }

                    base =
                        Room.init

                    archived =
                        { base | roomSetups = List.range 1 2000 |> List.map (\n -> ( String.fromInt n, setup )) |> Dict.fromList }

                    ( next, deliveries ) =
                        Room.tick 1000 archived

                    ( expected, expectedDeliveries ) =
                        Room.tick 1000 base
                in
                Expect.equal ( expected.rooms, expectedDeliveries, archived.roomSetups ) ( next.rooms, deliveries, next.roomSetups )
        , test "returning to the lobby refreshes the directory after unsubscribing" <|
            \() ->
                Room.handle "browser" "b" (Room.PreviewSubscription True) waiting
                    |> Tuple.second
                    |> Expect.equal [ { client = "b", message = Room.RoomsAvailable (Room.discover waiting) }, { client = "b", message = Room.GamesAvailable (Room.games waiting) } ]
        ]
