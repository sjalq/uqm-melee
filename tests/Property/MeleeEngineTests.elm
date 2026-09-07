module Property.MeleeEngineTests exposing (suite)

import Dict
import Expect
import Melee.Init exposing (shofixtiArena)
import Melee.Input as Input exposing (Turn(..))
import Melee.Keys as Keys
import Melee.Rate as Rate
import Melee.Rng as Rng exposing (Seed(..))
import Melee.Step exposing (pump, tick)
import Melee.Trig as Trig
import Melee.Units exposing (Facing(..), FrameCount(..), Side(..), Wait(..))
import Melee.Velocity as Velocity
import Test exposing (Test, describe, test)


idle =
    Input.idle


thrustInput =
    { turn = NoTurn, thrust = True, weapon = False, special = False }


fireInput =
    { turn = NoTurn, thrust = False, weapon = True, special = False }


gloryInput =
    { turn = NoTurn, thrust = False, weapon = False, special = True }


bothIdle =
    { bottom = idle, top = idle }


suite : Test
suite =
    describe "Melee engine"
        [ describe "Rate"
            [ test "60 display ticks fund 24 C frames" <|
                \_ ->
                    let
                        ( frames, _ ) =
                            List.foldl
                                (\_ ( n, acc ) ->
                                    let
                                        ( k, acc1 ) =
                                            Rate.advancePump acc
                                    in
                                    ( n + k, acc1 )
                                )
                                ( 0, 0 )
                                (List.range 1 60)
                    in
                    Expect.equal 24 frames
            ]
        , describe "Keys"
            [ test "left wins over right" <|
                \_ ->
                    let
                        held =
                            Keys.none
                                |> Keys.press "ArrowLeft"
                                |> Keys.press "ArrowRight"
                    in
                    Expect.equal TurnLeft (Keys.inputs held).bottom.turn
            , test "unknown key is a no-op" <|
                \_ ->
                    Expect.equal Keys.none (Keys.press "Escape" Keys.none)
            ]
        , describe "Trig"
            [ test "sine(32, 16384) is +1" <|
                \_ ->
                    Expect.equal 16384 (Trig.sine 32 16384)
            , test "cosine is sine+quadrant" <|
                \_ ->
                    Expect.equal (Trig.sine 16 1000) (Trig.cosine 0 1000)
            , test "arctan 0 0 is full circle" <|
                \_ ->
                    Expect.equal 64 (Trig.arctan 0 0)
            , test "wrap negative" <|
                \_ ->
                    Expect.equal 8191 (Trig.wrap -1 8192)
            ]
        , describe "Rng"
            [ test "Park-Miller from 1 is deterministic" <|
                \_ ->
                    let
                        ( a, s1 ) =
                            Rng.next (Seed 1)

                        ( b, _ ) =
                            Rng.next s1
                    in
                    Expect.equal a 16807
                        |> Expect.onFail (Debug.toString ( a, b ))
            ]
        , describe "Velocity"
            [ test "zero stays zero" <|
                \_ ->
                    let
                        ( ( dx, dy ), _ ) =
                            Velocity.getNext 1 Velocity.zero
                    in
                    Expect.equal ( 0, 0 ) ( dx, dy )
            , test "setVector facing 0 moves" <|
                \_ ->
                    let
                        v =
                            Velocity.setVector 10 (Facing 0)

                        ( ( dx, dy ), _ ) =
                            Velocity.getNext 1 v
                    in
                    Expect.notEqual ( 0, 0 ) ( dx, dy )
            ]
        , describe "Arena tick"
            [ test "idle tick increments frame" <|
                \_ ->
                    let
                        arena =
                            shofixtiArena (Seed 1)

                        next =
                            tick bothIdle arena
                    in
                    Expect.equal (FrameCount 1) next.frame
            , test "two ships and a planet exist" <|
                \_ ->
                    let
                        arena =
                            shofixtiArena (Seed 1)
                    in
                    Expect.equal 3 (List.length arena.queue)
            , test "thrust changes ship location" <|
                \_ ->
                    let
                        start =
                            shofixtiArena (Seed 1)

                        stepped =
                            List.foldl (\_ a -> tick { bottom = thrustInput, top = idle } a) start (List.range 1 30)

                        y0 =
                            start.elements |> dictY 2

                        y1 =
                            stepped.elements |> dictY 2
                    in
                    Expect.notEqual y0 y1
            , test "weapon spawns a dart" <|
                \_ ->
                    let
                        start =
                            shofixtiArena (Seed 1)

                        appeared =
                            tick bothIdle start

                        fired =
                            tick { bottom = fireInput, top = idle } appeared
                    in
                    Expect.greaterThan (List.length start.queue) (List.length fired.queue)
            , test "60 pumps advance 24 C frames" <|
                \_ ->
                    let
                        start =
                            shofixtiArena (Seed 1)

                        end =
                            List.foldl (\_ a -> pump bothIdle a) start (List.range 1 60)
                    in
                    Expect.equal (FrameCount 24) end.frame
            , test "glory removes the firing ship" <|
                \_ ->
                    let
                        start =
                            shofixtiArena (Seed 1)

                        appeared =
                            tick bothIdle start

                        boom =
                            List.foldl (\input arena -> tick { bottom = input, top = idle } arena) appeared [ gloryInput, idle, gloryInput, idle, gloryInput ]
                    in
                    Expect.equal Nothing (dictGet 2 boom.elements)
            , test "idle gravity pulls both ships toward the planet" <|
                \_ ->
                    let
                        start =
                            shofixtiArena (Seed 1)

                        end =
                            List.foldl (\_ a -> tick bothIdle a) start (List.range 1 48)

                        planetX =
                            dictX 1 start.elements

                        planetY =
                            dictY 1 start.elements

                        closer id =
                            dist2 (dictX id start.elements) (dictY id start.elements) planetX planetY
                                > dist2 (dictX id end.elements) (dictY id end.elements) planetX planetY
                    in
                    Expect.equal True (closer 2 && closer 3)
                        |> Expect.onFail
                            (Debug.toString
                                { b0 = ( dictX 2 start.elements, dictY 2 start.elements )
                                , b1 = ( dictX 2 end.elements, dictY 2 end.elements )
                                , t0 = ( dictX 3 start.elements, dictY 3 start.elements )
                                , t1 = ( dictX 3 end.elements, dictY 3 end.elements )
                                }
                            )
            ]
        ]


dictY : Int -> Dict.Dict Int { a | current : { b | location : { c | y : Int } } } -> Int
dictY k elements =
    case Dict.get k elements of
        Just el ->
            el.current.location.y

        Nothing ->
            -1


dictX : Int -> Dict.Dict Int { a | current : { b | location : { c | x : Int } } } -> Int
dictX k elements =
    case Dict.get k elements of
        Just el ->
            el.current.location.x

        Nothing ->
            -1


dist2 : Int -> Int -> Int -> Int -> Int
dist2 x0 y0 x1 y1 =
    let
        dx =
            x0 - x1

        dy =
            y0 - y1
    in
    dx * dx + dy * dy


dictGet : Int -> Dict.Dict Int a -> Maybe a
dictGet =
    Dict.get
