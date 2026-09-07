module Property.PresentationTests exposing (suite)

import Dict
import Expect
import Json.Encode as E
import Melee.Local as Game
import Melee.Menu as Menu
import Melee.Presentation as Presentation
import Melee.Preview as Preview
import Melee.Room as Room
import Test exposing (..)


send session client msg host =
    Room.handle session client msg host |> Tuple.first


suite =
    describe "Elm presentation orchestration"
        [ test "lobby feed reconstructs the actual exhibition, with no spectator seat" <|
            \() ->
                let
                    host =
                        Room.init |> send "lobby" "l" (Room.PreviewSubscription True)

                    step n ( state, previousPreview ) =
                        let
                            ( next, deliveries ) =
                                Room.tick (n * 42) state

                            apply delivery previous =
                                case delivery.message of
                                    Room.ArenaPreview update ->
                                        Preview.apply update previous

                                    _ ->
                                        previous
                        in
                        ( next, List.foldl apply previousPreview deliveries )

                    ( final, preview ) =
                        List.range 1 24 |> List.foldl step ( host, Nothing )

                    rendered =
                        Maybe.andThen (Game.phaseArena << .phase) >> Maybe.map (\arena -> ( arena.frame, arena.elements, arena.combatants ))
                in
                Expect.all
                    [ \_ -> Expect.equal (rendered final.previewGame) (rendered preview)
                    , \_ -> Expect.equal (Just Dict.empty) (Dict.get "ARENA" final.rooms |> Maybe.map .spectators)
                    , \_ -> Expect.notEqual Nothing preview
                    ]
                    ()
        , test "new lobby viewers receive the same base as the next shared delta" <|
            \() ->
                let
                    host =
                        Room.init |> send "lobby" "l" (Room.PreviewSubscription True) |> Room.tick 1000 |> Tuple.first

                    packets =
                        Room.handle "second" "s" (Room.PreviewSubscription True) host |> Tuple.second

                    initial =
                        List.filterMap
                            (\packet ->
                                case packet.message of
                                    Room.ArenaPreview (Preview.Snapshot game) ->
                                        Just game

                                    _ ->
                                        Nothing
                            )
                            packets
                            |> List.head
                in
                Expect.equal host.previewGame initial
        , test "Elm chooses the nearest directional target and respects muting" <|
            \() ->
                let
                    a =
                        { id = "a", label = "A", x = 0, y = 0 }

                    b =
                        { id = "b", label = "B", x = 10, y = 0 }

                    c =
                        { id = "c", label = "C", x = 1, y = 100 }
                in
                Menu.respond False (Menu.Key "ArrowRight" "a" False [ a, c, b ]) |> List.map (E.encode 0) |> Expect.equal [ "{\"op\":\"focus\",\"id\":\"b\"}" ]
        , test "countdown is selected by Elm, skips missed seconds, and stops on exit" <|
            \() ->
                let
                    host =
                        Room.init |> send "a" "a" Room.FindMatch |> send "b" "b" Room.FindMatch

                    seated =
                        Room.findRoom "a" "a" host
                            |> Maybe.map (Tuple.first >> Room.deliver)
                            |> Maybe.withDefault []
                            |> List.filterMap
                                (\packet ->
                                    case packet.message of
                                        Room.RoomSnapshot snapshot ->
                                            Just (Room.Seated snapshot)

                                        _ ->
                                            Nothing
                                )
                            |> List.head
                            |> Maybe.withDefault Room.Browsing

                    before =
                        { game = { sound = True, notice = "" }, meleeVisible = True, meleeNow = 114000, melee = seated }

                    encode =
                        List.map (E.encode 0)
                in
                Expect.all
                    [ \_ -> Presentation.commands before { before | meleeNow = 115000 } |> encode |> Expect.equal (encode [ Menu.play "countdown" "/sounds/countdown/5.wav" 0.55 ])
                    , \_ -> Presentation.commands before { before | meleeNow = 116000 } |> encode |> Expect.equal (encode [ Menu.stop "countdown" ])
                    , \_ -> Presentation.commands before { before | melee = Room.Browsing } |> encode |> Expect.equal (encode [ Menu.stop "countdown" ])
                    , \_ -> Presentation.commands before { before | meleeVisible = False } |> encode |> Expect.equal (encode [ Menu.stop "countdown", Menu.stop "menu" ])
                    ]
                    ()
        ]
