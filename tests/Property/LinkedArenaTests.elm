module Property.LinkedArenaTests exposing (suite)

import Dict
import Expect
import Melee.Input as Input
import Melee.Local as Game
import Melee.Location as Location
import Melee.Room as Room
import Melee.Stream as Stream
import Melee.View as View
import Test exposing (..)
import Url


suite : Test
suite =
    describe "Linked rooms and economical authoritative delivery"
        [ test "room and list URL state survives a round trip" <|
            \() ->
                let
                    location =
                        { room = Just "ARENA", watching = True, local = False, watchingList = True, page = 2, roster = 1, mode = Game.Solo, difficulty = Input.GoodCyborg }
                in
                Url.fromString ("https://game.test" ++ Location.toUrl location) |> Maybe.map Location.fromUrl |> Expect.equal (Just location)
        , test "malformed pagination is harmless and room codes normalize" <|
            \() ->
                Url.fromString "https://game.test/melee?room=%20arena%20&page=-4&roster=nope" |> Maybe.map Location.fromUrl |> Expect.equal (Just { room = Just "ARENA", watching = False, local = False, watchingList = False, page = 0, roster = 0, mode = Game.Solo, difficulty = Input.GoodCyborg })
        , test "exhibition always starts with twelve distinct ships" <|
            \() ->
                let
                    fleet =
                        (Room.exhibition 0).game.fleets
                in
                Expect.all [ \_ -> Expect.equal 6 (List.length fleet.bottom), \_ -> Expect.equal 6 (List.length fleet.top), \_ -> Expect.equal False (List.any (\ship -> List.member ship fleet.top) fleet.bottom) ] ()
        , test "exhibition restarts after victory and preserves its audience" <|
            \() ->
                let
                    initial =
                        Room.exhibition 0

                    game =
                        initial.game

                    ended =
                        { initial | game = { game | phase = Game.Victory Nothing }, revision = 7, touched = 1000, spectators = Dict.singleton "viewer" "session" }

                    host =
                        Room.init
                in
                Room.tick 5001 { host | rooms = Dict.singleton "ARENA" ended } |> Tuple.first |> .rooms |> Dict.get "ARENA" |> Maybe.map (\room -> ( Room.running room.game.phase, room.spectators, room.game.fleets /= game.fleets )) |> Expect.equal (Just ( True, ended.spectators, True ))
        , test "combat is capped at ten deliveries and preview follows sixty server ticks per second" <|
            \() ->
                let
                    watching =
                        Room.handle "watcher" "w" (Room.WatchRoom "ARENA") Room.init |> Tuple.first |> Room.handle "lobby" "l" (Room.PreviewSubscription True) |> Tuple.first

                    step n ( host, accumulated ) =
                        let
                            ( next, delivered ) =
                                Room.tick (round (toFloat n * 1000 / 60)) host
                        in
                        ( next, delivered ++ accumulated )

                    messages =
                        List.range 1 60 |> List.foldl step ( watching, [] ) |> Tuple.second

                    count client =
                        List.filter (\d -> d.client == client) messages |> List.length
                in
                Expect.all [ \_ -> Expect.atMost 10 (count "w"), \_ -> Expect.atLeast 7 (count "w"), \_ -> Expect.equal 60 (count "l") ] ()
        , test "existing exhibitions upgrade both computer pilots to awesome" <|
            \() ->
                let
                    initial =
                        Room.exhibition 0

                    game =
                        initial.game

                    host =
                        Room.init

                    old =
                        { initial | game = { game | difficulty = Input.GoodCyborg } }

                    upgraded =
                        Room.tick 17 { host | rooms = Dict.singleton "ARENA" old } |> Tuple.first |> .rooms |> Dict.get "ARENA" |> Maybe.map .game
                in
                Expect.all
                    [ \_ -> Expect.equal Input.AwesomeCyborg game.difficulty
                    , \_ -> Expect.equal (Just ( Game.Demo, Input.AwesomeCyborg )) (Maybe.map (\next -> ( next.mode, next.difficulty )) upgraded)
                    ]
                    ()
        , test "input changes do not send full state acknowledgements" <|
            \() ->
                Room.handle "pilot" "p" Room.CreateRoom Room.init |> Tuple.first |> Room.handle "pilot" "p" (Room.Controls Input.idle) |> Tuple.second |> Expect.equal []
        , test "delta reconstruction preserves every rendered element" <|
            \() ->
                let
                    before =
                        (Room.exhibition 0).game

                    after =
                        Room.tick 125 Room.init |> Tuple.first |> .rooms |> Dict.get "ARENA" |> Maybe.map .game |> Maybe.withDefault before

                    rendered model =
                        Game.phaseArena model.phase |> Maybe.map (\arena -> ( arena.elements, arena.combatants, arena.queue ))
                in
                Stream.between 125 before after |> Maybe.map (\delta -> rendered (Stream.apply delta before)) |> Expect.equal (Just (rendered after))
        , test "new snapshots interpolate from the position currently displayed" <|
            \() ->
                let
                    before =
                        (Room.exhibition 0).game

                    halfway =
                        { before
                            | phase =
                                Game.mapArena
                                    (\arena ->
                                        { arena
                                            | pumpAcc = 30
                                            , previousLocations =
                                                Dict.map
                                                    (\_ el ->
                                                        let
                                                            at =
                                                                el.current.location
                                                        in
                                                        { at | x = at.x - 100 }
                                                    )
                                                    arena.elements
                                        }
                                    )
                                    before.phase
                        }

                    expected =
                        Game.phaseArena halfway.phase |> Maybe.map (\arena -> Dict.map (\_ el -> View.displayLocation arena el) arena.elements)

                    actual =
                        Stream.between 17 halfway before
                            |> Maybe.map (\delta -> Stream.apply delta halfway)
                            |> Maybe.andThen (Game.phaseArena << .phase)
                            |> Maybe.map .previousLocations
                in
                Expect.equal expected actual
        , test "terminal state is delivered even if it arrived between broadcast slots" <|
            \() ->
                let
                    initial =
                        Room.exhibition 0

                    game =
                        initial.game

                    pending =
                        { initial | game = { game | phase = Game.Victory Nothing }, lastBroadcast = Just game, revision = 2, touched = 80, broadcastAt = 0, spectators = Dict.singleton "w" "s" }

                    host =
                        Room.init
                in
                Room.tick 125 { host | rooms = Dict.singleton "ARENA" pending } |> Tuple.second |> List.length |> Expect.equal 1
        , test "unsubscribed lobby receives no preview" <|
            \() -> Room.init |> Room.handle "lobby" "l" (Room.PreviewSubscription True) |> Tuple.first |> Room.handle "lobby" "l" (Room.PreviewSubscription False) |> Tuple.first |> Room.tick 1000 |> Tuple.second |> Expect.equal []
        ]
