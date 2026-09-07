module Property.CyborgTests exposing (suite)

import Dict
import Expect
import Melee.Cyborg as Cyborg
import Melee.Init exposing (shofixtiArena)
import Melee.Input as Input exposing (CyborgRating(..), Turn(..))
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..), stock)
import Melee.ShipState as State
import Melee.Step exposing (tick)
import Melee.Units exposing (Side(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Original cyborg"
        [ test "Shofixti maneuverability matches InitCyborg" <|
            \_ ->
                let
                    chars =
                        (stock Shofixti).characteristics
                in
                Expect.equal 175 (Cyborg.maneuverability chars)
        , test "think emits a battle input without allocating extra elements" <|
            \_ ->
                let
                    arena =
                        shofixtiArena (Seed 1)

                    ( input, seed ) =
                        Cyborg.think GoodCyborg Bottom arena arena.seed
                in
                Expect.all
                    [ \_ -> Expect.notEqual arena.seed seed
                    , \_ ->
                        Expect.equal 3 (Dict.size arena.elements)
                    , \_ ->
                        case input.turn of
                            NoTurn ->
                                Expect.pass

                            TurnLeft ->
                                Expect.pass

                            TurnRight ->
                                Expect.pass
                    ]
                    ()
        , test "Standard rating never presses special" <|
            \_ ->
                let
                    start =
                        shofixtiArena (Seed 1)

                    neverSpecial a n =
                        if n <= 0 then
                            True

                        else
                            let
                                ( input, seed ) =
                                    Cyborg.think StandardCyborg Bottom a a.seed

                                next =
                                    tick { bottom = input, top = Input.idle } { a | seed = seed }
                            in
                            not input.special && neverSpecial next (n - 1)
                in
                Expect.equal True (neverSpecial start 48)
        , test "Good cyborg vs idle opponent closes or fires" <|
            \_ ->
                let
                    start =
                        shofixtiArena (Seed 1)

                    end =
                        List.foldl
                            (\_ a ->
                                let
                                    ( input, seed ) =
                                        Cyborg.think GoodCyborg Bottom a a.seed
                                in
                                tick { bottom = input, top = Input.idle } { a | seed = seed }
                            )
                            start
                            (List.range 1 72)

                    b0 =
                        Dict.get 2 start.elements |> Maybe.map (\el -> el.current.location)

                    b1 =
                        Dict.get 2 end.elements |> Maybe.map (\el -> el.current.location)

                    energy =
                        (State.core end.combatants.bottom).energy
                in
                Expect.equal True (b0 /= b1 || energy < 4)
        ]
