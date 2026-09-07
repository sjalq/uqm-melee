module Property.SpectatorControllerTests exposing (suite)

import Dict
import Expect
import Melee.Input as Input
import Melee.Local as Game
import Melee.Room as Room
import Melee.Units exposing (Side(..))
import Test exposing (..)


send session client message host =
    Room.handle session client message host |> Tuple.first


initial =
    Room.init |> send "host" "h" Room.CreateRoom


get host =
    Dict.get "M00001" host.rooms


suite : Test
suite =
    describe "Watching matches and assigning pilots"
        [ test "spectators receive state without occupying a player seat" <|
            \() ->
                let
                    ( host, deliveries ) =
                        Room.handle "watcher" "w" (Room.WatchRoom "M00001") initial
                in
                Expect.all [ \_ -> Expect.equal Nothing (Room.findRoom "watcher" "w" host), \_ -> Expect.equal (Just 1) (get host |> Maybe.map (.spectators >> Dict.size)), \_ -> deliveries |> List.any isSpectatorMessage |> Expect.equal True ] ()
        , test "spectators cannot pause, change pilots, ready up or submit controls" <|
            \() ->
                let
                    watching =
                        initial |> send "watcher" "w" (Room.WatchRoom "M00001")
                in
                List.foldl (send "watcher" "w") watching [ Room.Pause, Room.SetController Top Room.Computer, Room.Ready, Room.Controls Input.idle ] |> Expect.equal watching
        , test "spectator disconnect removes the audience membership" <|
            \() -> initial |> send "watcher" "w" (Room.WatchRoom "M00001") |> Room.disconnect "watcher" "w" |> Tuple.first |> get |> Maybe.map (.spectators >> Dict.size) |> Expect.equal (Just 0)
        , test "closing the last seat sends spectators back to rooms, never back to the deleted match" <|
            \() ->
                let
                    watching =
                        initial |> send "watcher" "w" (Room.WatchRoom "M00001")

                    ( _, messages ) =
                        Room.handle "host" "h" Room.LeaveRoom watching
                in
                messages |> List.filter (\d -> d.client == "w") |> List.map .message |> Expect.equal [ Room.RoomLeft ]
        , test "computer versus computer launches without a second human" <|
            \() ->
                let
                    host =
                        initial |> send "host" "h" (Room.SetController Bottom Room.Computer) |> send "host" "h" (Room.SetController Top Room.Computer) |> send "host" "h" Room.Ready
                in
                case get host |> Maybe.map (.game >> .phase) of
                    Just (Game.Countdown _ _) ->
                        Expect.pass

                    _ ->
                        Expect.fail "Computer fleets should select and launch"
        , test "human versus computer auto-selects only the computer's ship" <|
            \() ->
                let
                    host =
                        initial |> send "host" "h" (Room.SetController Top Room.Computer) |> send "host" "h" Room.Ready
                in
                case get host |> Maybe.map (.game >> .phase) of
                    Just (Game.Selecting Nothing (Just _)) ->
                        Expect.pass

                    _ ->
                        Expect.fail "The human should choose the gold ship"
        , test "computer versus human works with the human in the top seat" <|
            \() ->
                let
                    host =
                        initial |> send "host" "h" (Room.SetController Bottom Room.Computer) |> send "guest" "g" (Room.JoinRoom "M00001") |> send "guest" "g" Room.Ready
                in
                case get host |> Maybe.map (.game >> .phase) of
                    Just (Game.Selecting (Just _) Nothing) ->
                        Expect.pass

                    _ ->
                        Expect.fail "The human should choose the cyan ship"
        , test "a player cannot replace another connected human with a computer" <|
            \() ->
                let
                    full =
                        initial |> send "guest" "g" (Room.JoinRoom "M00001")
                in
                full |> send "host" "h" (Room.SetController Top Room.Computer) |> Expect.equal full
        , test "computer pilot settings cannot change after launch" <|
            \() ->
                let
                    launched =
                        initial |> send "host" "h" (Room.SetController Top Room.Computer) |> send "host" "h" Room.Ready
                in
                launched |> send "host" "h" (Room.SetController Bottom Room.Computer) |> Expect.equal launched
        , test "the backend advances AI battles and sends spectator snapshots" <|
            \() ->
                let
                    launched =
                        initial |> send "host" "h" (Room.SetController Bottom Room.Computer) |> send "host" "h" (Room.SetController Top Room.Computer) |> send "host" "h" Room.Ready |> send "watcher" "w" (Room.WatchRoom "M00001")

                    advanced =
                        List.foldl (\n host -> Room.tick (n * 42) host |> Tuple.first) launched (List.range 1 60)

                    ( _, messages ) =
                        Room.tick 2700 advanced
                in
                messages |> List.any isSpectatorMessage |> Expect.equal True
        ]


isSpectatorMessage delivery =
    case delivery.message of
        Room.CombatDelta _ _ _ ->
            delivery.client == "w"

        Room.SpectatorView _ ->
            delivery.client == "w"

        _ ->
            False
