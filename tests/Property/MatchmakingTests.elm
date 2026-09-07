module Property.MatchmakingTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Ranking as Ranking
import Melee.Room as Room
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Side(..))
import Test exposing (..)


send session client message host =
    Room.handle session client message host |> Tuple.first


paired =
    Room.init |> send "alice-cookie" "a" Room.FindMatch |> send "bob-cookie" "b" Room.FindMatch


match host =
    Dict.get "M00001" host.rooms


launched =
    paired |> send "alice-cookie" "a" Room.Ready |> send "bob-cookie" "b" Room.Ready


suite : Test
suite =
    describe "Cookie identities, FIFO matchmaking and rated duels"
        [ test "two players on one keyboard have independent controls" <|
            \() ->
                let
                    held =
                        Keys.none |> Keys.press "ArrowUp" |> Keys.press "w" |> Keys.press "Enter" |> Keys.press "j" |> Keys.release "ArrowUp"

                    inputs =
                        Keys.inputs held
                in
                Expect.equal ( False, True, True ) ( inputs.bottom.thrust, inputs.top.thrust, inputs.bottom.weapon && inputs.top.weapon )
        , test "first two available players pair; third stays queued" <|
            \() ->
                let
                    host =
                        paired |> send "third" "c" Room.FindMatch
                in
                Expect.all [ \_ -> Expect.equal [ "third" ] (List.map .session host.queue), \_ -> Expect.equal (Just ( Just "alice-cookie", Just "bob-cookie" )) (match host |> Maybe.map (\room -> ( Maybe.map .session room.seats.bottom, Maybe.map .session room.seats.top ))) ] ()
        , test "match notification contains the complete seat atomically" <|
            \() ->
                Room.init
                    |> send "alice" "a" Room.FindMatch
                    |> Room.handle "bob" "b" Room.FindMatch
                    |> Tuple.second
                    |> List.filterMap
                        (\delivery ->
                            case delivery.message of
                                Room.MatchFound snapshot ->
                                    Just snapshot.code

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ "M00001", "M00001" ]
        , test "equal-rated draw records the result without exchanging points" <|
            \() ->
                let
                    ( bottom, top, _ ) =
                        Ranking.rate Nothing (Ranking.initial 1) (Ranking.initial 2)
                in
                Expect.equal ( 1000, 1000, 2 ) ( bottom.rating, top.rating, bottom.draws + top.draws )
        , test "winning against a stronger player awards more Elo" <|
            \() ->
                let
                    base =
                        Ranking.initial 1

                    ( normal, _, _ ) =
                        Ranking.rate (Just Bottom) base base

                    ( upset, _, _ ) =
                        Ranking.rate (Just Bottom) base { base | rating = 1400 }
                in
                Expect.greaterThan normal.lastChange upset.lastChange
        , test "same browser cannot match itself from another tab" <|
            \() -> Room.init |> send "cookie" "a" Room.FindMatch |> send "cookie" "b" Room.FindMatch |> .rooms |> Dict.size |> Expect.equal 1
        , test "leaving the queue and disconnecting remove pending entries" <|
            \() -> Room.init |> send "cookie" "a" Room.FindMatch |> send "cookie" "a" Room.CancelSearch |> send "other" "b" Room.FindMatch |> Room.disconnect "other" "b" |> Tuple.first |> .queue |> Expect.equal []
        , test "names persist across client connections using the cookie" <|
            \() -> Room.init |> send "cookie" "old-tab" (Room.SetPlayerName "  Zelnick  ") |> Room.identify "cookie" "new-tab" |> Tuple.first |> .players |> Dict.get "cookie" |> Maybe.map .name |> Expect.equal (Just "Zelnick")
        , test "both players receive the same default fleet and a two minute deadline" <|
            \() -> match paired |> Maybe.map (\room -> ( room.game.fleets.bottom == room.game.fleets.top, room.ranked |> Maybe.andThen .deadline )) |> Expect.equal (Just ( True, Just 120000 ))
        , test "one ready player does not launch; both launch their first ship" <|
            \() -> Expect.all [ \_ -> paired |> send "alice-cookie" "a" Room.Ready |> match |> Maybe.map (.game >> .phase) |> Expect.equal (Just Game.Hangar), \_ -> match launched |> Maybe.map (.game >> .phase >> Room.running) |> Expect.equal (Just True) ] ()
        , test "editing your fleet does not unset the opponent's readiness" <|
            \() -> paired |> send "alice-cookie" "a" Room.Ready |> send "bob-cookie" "b" (Room.Add Spathi) |> match |> Maybe.map (.ready >> .bottom) |> Expect.equal (Just True)
        , test "ready locks a player's fleet" <|
            \() ->
                let
                    ready =
                        paired |> send "alice-cookie" "a" Room.Ready
                in
                ready |> send "alice-cookie" "a" (Room.Add Spathi) |> Expect.equal ready
        , test "timer starts at pairing and cannot be extended by edits" <|
            \() -> paired |> Room.tick 119999 |> Tuple.first |> send "alice-cookie" "a" (Room.Add Spathi) |> Room.tick 120000 |> Tuple.first |> match |> Maybe.map (.game >> .phase >> Room.running) |> Expect.equal (Just True)
        , test "removing every ship is rejected before automatic launch" <|
            \() -> List.range 1 8 |> List.foldl (\_ host -> send "alice-cookie" "a" (Room.Remove 0) host) paired |> match |> Maybe.map (.game >> .fleets >> .bottom >> List.length) |> Expect.equal (Just 1)
        , test "ranked players cannot replace their opponent with a bot" <|
            \() -> paired |> send "alice-cookie" "a" (Room.SetController Top Room.Computer) |> Expect.equal paired
        , test "leaving before launch cancels without Elo changes" <|
            \() -> paired |> send "alice-cookie" "a" Room.LeaveRoom |> .players |> Dict.values |> List.map .rating |> Expect.equal [ 1000, 1000 ]
        , test "forfeit updates both ratings exactly once" <|
            \() -> launched |> send "alice-cookie" "a" Room.LeaveRoom |> Room.tick 5000 |> Tuple.first |> Room.tick 10000 |> Tuple.first |> .players |> Dict.values |> List.map (\p -> ( p.rating, p.wins + p.losses + p.draws )) |> Expect.equal [ ( 984, 1 ), ( 1016, 1 ) ]
        , test "a completed combat result updates ratings once" <|
            \() ->
                let
                    won =
                        { launched
                            | rooms =
                                Dict.update "M00001"
                                    (Maybe.map
                                        (\room ->
                                            let
                                                game =
                                                    room.game
                                            in
                                            { room | game = { game | phase = Game.Victory (Just Bottom) } }
                                        )
                                    )
                                    launched.rooms
                        }
                in
                won |> Room.tick 1000 |> Tuple.first |> Room.tick 2000 |> Tuple.first |> .players |> Dict.values |> List.map .rating |> Expect.equal [ 1016, 984 ]
        , test "disconnect gives a sixty second grace period then forfeits" <|
            \() ->
                let
                    gone =
                        launched |> Room.disconnect "alice-cookie" "a" |> Tuple.first

                    ratings =
                        .players >> Dict.values >> List.map .rating
                in
                Expect.all [ \_ -> Room.tick 59999 gone |> Tuple.first |> ratings |> Expect.equal [ 1000, 1000 ], \_ -> Room.tick 60000 gone |> Tuple.first |> ratings |> Expect.equal [ 984, 1016 ] ] ()
        , test "reconnecting clears the forfeit deadline" <|
            \() -> launched |> Room.disconnect "alice-cookie" "a" |> Tuple.first |> Room.tick 30000 |> Tuple.first |> Room.reconnect "alice-cookie" "new-tab" |> Tuple.first |> Room.tick 60001 |> Tuple.first |> .players |> Dict.values |> List.map .rating |> Expect.equal [ 1000, 1000 ]
        , fuzz2 (Fuzz.intRange 100 3000) (Fuzz.intRange 100 3000) "Elo exchange is zero sum and winner never loses points" <|
            \bottomRating topRating ->
                let
                    base =
                        Ranking.initial 1

                    ( bottom, top, _ ) =
                        Ranking.rate (Just Bottom) { base | rating = bottomRating } { base | rating = topRating }
                in
                Expect.all [ \_ -> Expect.equal (bottomRating + topRating) (bottom.rating + top.rating), \_ -> Expect.atLeast bottomRating bottom.rating ] ()
        ]
