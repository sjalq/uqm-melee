module Property.JevDeskTests exposing (suite)

import Dict
import Expect
import Fuzz exposing (Fuzzer)
import Melee.JevDesk as Desk exposing (Desk)
import Test exposing (..)


type Op
    = Start Int
    | Finish Int
    | Wait Int


op : Fuzzer Op
op =
    Fuzz.oneOf
        [ Fuzz.map Start (Fuzz.intRange 0 5)
        , Fuzz.map Finish (Fuzz.intRange 0 80)
        , Fuzz.map Wait (Fuzz.intRange 0 6000)
        ]


type alias World =
    { desk : Desk, now : Int, issued : List Int }


run : Op -> World -> World
run operation world =
    case operation of
        Start who ->
            case Desk.start ("s" ++ String.fromInt who) "req" world.now world.desk of
                Desk.Started key desk ->
                    { world | desk = desk, issued = key :: world.issued }

                _ ->
                    world

        Finish key ->
            case Desk.finish key world.desk of
                Just ( _, desk ) ->
                    { world | desk = desk }

                Nothing ->
                    world

        Wait ms ->
            { world | now = world.now + ms, desk = Desk.expire (world.now + ms) world.desk }


suite : Test
suite =
    describe "Jev desk"
        [ fuzz (Fuzz.listOfLengthBetween 0 200 op) "counters always agree with the jobs, limits hold and keys never repeat" <|
            \ops ->
                let
                    world =
                        List.foldl run { desk = Desk.empty, now = 0, issued = [] } ops

                    jobs =
                        Dict.values world.desk.jobs

                    perSession =
                        List.foldl (\job -> Dict.update job.session (Maybe.withDefault 0 >> (+) 1 >> Just)) Dict.empty jobs
                in
                Expect.all
                    [ \_ -> Expect.equal (List.length jobs) world.desk.live
                    , \_ -> Expect.equal perSession world.desk.perSession
                    , \_ -> Expect.equal True (List.all (\count -> count <= Desk.sessionLimit) (Dict.values perSession))
                    , \_ -> Expect.atMost Desk.globalLimit world.desk.live
                    , \_ -> Expect.equal (List.length world.issued) (List.length (Dict.keys (Dict.fromList (List.map (\key -> ( key, () )) world.issued))))
                    , \_ -> Expect.equal True (List.all (\job -> world.now - job.startedAt < Desk.jobTtlMs) (Dict.values (Desk.expire world.now world.desk).jobs))
                    ]
                    ()
        , test "a third call from one session is refused until one finishes or expires" <|
            \_ ->
                let
                    started desk =
                        case Desk.start "me" "req" 0 desk of
                            Desk.Started key next ->
                                Just ( key, next )

                            _ ->
                                Nothing

                    twice =
                        started Desk.empty |> Maybe.andThen (\( first, d1 ) -> started d1 |> Maybe.map (\( _, d2 ) -> ( first, d2 )))
                in
                case twice of
                    Just ( first, desk ) ->
                        Expect.all
                            [ \_ -> Expect.equal True (Desk.start "me" "req" 0 desk == Desk.SessionBusy)
                            , \_ -> Expect.equal True (Desk.start "other" "req" 0 desk /= Desk.SessionBusy)
                            , \_ -> Expect.notEqual Nothing (Desk.finish first desk |> Maybe.andThen (\( _, freed ) -> started freed))
                            , \_ ->
                                Expect.notEqual Nothing
                                    (Desk.start "me" "req" Desk.jobTtlMs desk
                                        |> (\s ->
                                                case s of
                                                    Desk.Started _ _ ->
                                                        Just ()

                                                    _ ->
                                                        Nothing
                                           )
                                    )
                            ]
                            ()

                    Nothing ->
                        Expect.fail "first two calls should start"
        , test "an answer for an expired job is dropped" <|
            \_ ->
                case Desk.start "me" "req" 0 Desk.empty of
                    Desk.Started key desk ->
                        Desk.expire Desk.jobTtlMs desk |> Desk.finish key |> Expect.equal Nothing

                    _ ->
                        Expect.fail "should start"
        ]
