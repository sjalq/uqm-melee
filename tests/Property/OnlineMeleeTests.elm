module Property.OnlineMeleeTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Input as Input
import Melee.Local as Game
import Melee.Room as Room
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Side(..))
import Test exposing (..)


send session client message host =
    Room.handle session client message host |> Tuple.first


joined =
    Room.init
        |> send "gold" "g" Room.CreateRoom
        |> send "cyan" "c" (Room.JoinRoom "m00001")


room host =
    Dict.get "M00001" host.rooms


playing =
    joined
        |> send "gold" "g" Room.Ready
        |> send "cyan" "c" Room.Ready
        |> send "gold" "g" (Room.Pick 0)
        |> send "cyan" "c" (Room.Pick 0)


suite : Test
suite =
    describe "Backend authoritative rooms"
        [ test "joining returns one seat-specific snapshot to each client" <|
            \() ->
                let
                    initial =
                        send "gold" "g" Room.CreateRoom Room.init

                    ( _, deliveries ) =
                        Room.handle "cyan" "c" (Room.JoinRoom "m00001") initial
                in
                deliveries
                    |> List.filterMap
                        (\delivery ->
                            case delivery.message of
                                Room.RoomSnapshot snapshot ->
                                    Just ( delivery.client, snapshot.side )

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ ( "g", Bottom ), ( "c", Top ) ]
        , test "only both ready fleets start a match" <|
            \() ->
                let
                    once =
                        joined |> send "gold" "g" Room.Ready

                    twice =
                        once |> send "cyan" "c" Room.Ready
                in
                Expect.equal ( Just Game.Hangar, Just (Game.Selecting Nothing Nothing) ) ( room once |> Maybe.map (.game >> .phase), room twice |> Maybe.map (.game >> .phase) )
        , fuzz Fuzz.string "unseated clients cannot change room state" <|
            \name ->
                joined |> send "stranger" "x" (Room.Rename name) |> Expect.equal joined
        , test "a forged session cannot use another client's seat" <|
            \() -> joined |> send "stranger" "g" (Room.Remove 0) |> Expect.equal joined
        , test "each seat edits only its own fleet" <|
            \() ->
                joined |> send "cyan" "c" (Room.ReplaceFleet "Invaders" [ Orz ]) |> room |> Maybe.map (\r -> ( r.game.fleets.bottom, r.game.fleets.top )) |> Expect.equal (Just ( Game.init.fleets.bottom, [ Orz ] ))
        , test "fleet changes invalidate readiness" <|
            \() ->
                joined |> send "gold" "g" Room.Ready |> send "cyan" "c" (Room.Add Orz) |> room |> Maybe.map .ready |> Expect.equal (Just { bottom = False, top = False })
        , test "combat cannot rewrite fleets or choose a negative slot" <|
            \() ->
                playing |> send "gold" "g" (Room.Add Orz) |> send "cyan" "c" (Room.Pick -1) |> Expect.equal playing
        , test "server clock advances a match without client frame messages" <|
            \() ->
                let
                    advance time host =
                        Room.tick time host |> Tuple.first

                    final =
                        List.foldl advance playing (List.range 1 100 |> List.map ((*) 42))
                in
                case room final |> Maybe.map (.game >> .phase) of
                    Just (Game.Combat arena) ->
                        Expect.notEqual (Game.phaseArena Game.init.phase) (Just arena)

                    _ ->
                        Expect.fail "The server should have advanced warp-in into combat"
        , test "inputs are attributed by the authenticated seat" <|
            \() ->
                let
                    idle =
                        Input.idle
                in
                playing |> send "cyan" "c" (Room.Controls { idle | special = True, weapon = True }) |> room |> Maybe.map .inputs |> Expect.equal (Just { bottom = idle, top = { idle | special = True, weapon = True } })
        , test "disconnect clears both inputs and freezes the clock until rejoin" <|
            \() ->
                let
                    idle =
                        Input.idle

                    before =
                        playing |> send "gold" "g" (Room.Controls { idle | thrust = True }) |> Room.disconnect "gold" "g" |> Tuple.first

                    after =
                        Room.tick 500 before |> Tuple.first |> Room.tick 750 |> Tuple.first
                in
                Expect.equal (room before |> Maybe.map (\r -> ( r.game.phase, { bottom = idle, top = idle } ))) (room after |> Maybe.map (\r -> ( r.game.phase, r.inputs )))
        , test "disconnecting a ready player requires them to confirm again" <|
            \() ->
                joined |> send "gold" "g" Room.Ready |> Room.disconnect "gold" "g" |> Tuple.first |> send "cyan" "c" Room.Ready |> Room.reconnect "gold" "new" |> Tuple.first |> send "gold" "new" Room.Ready |> room |> Maybe.map (.game >> .phase) |> Expect.equal (Just (Game.Selecting Nothing Nothing))
        , test "reconnection restores only the disconnected session's seat" <|
            \() ->
                let
                    detached =
                        joined |> Room.disconnect "gold" "g" |> Tuple.first

                    restored =
                        detached |> Room.reconnect "gold" "new" |> Tuple.first
                in
                Expect.equal ( Just ( "M00001", Bottom ), Nothing ) ( Room.findRoom "gold" "new" restored |> Maybe.map (\( r, s ) -> ( r.code, s )), Room.findRoom "gold" "g" restored |> Maybe.map (\( r, s ) -> ( r.code, s )) )
        , test "a second tab cannot steal a connected seat" <|
            \() -> joined |> Room.reconnect "gold" "new" |> Tuple.first |> Expect.equal joined
        , test "empty abandoned rooms expire" <|
            \() -> joined |> Room.disconnect "gold" "g" |> Tuple.first |> Room.disconnect "cyan" "c" |> Tuple.first |> Room.tick 600001 |> Tuple.first |> .rooms |> Dict.remove "ARENA" |> Dict.isEmpty |> Expect.equal True
        , test "hangar and paused rooms do not emit combat ticks" <|
            \() -> Room.tick 1000 joined |> Tuple.second |> Expect.equal []
        ]
