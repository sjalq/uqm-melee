module Property.AbilityTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Catalog as Catalog
import Melee.Element exposing (Body(..), Owner(..))
import Melee.Init as Init
import Melee.Input exposing (..)
import Melee.Local as Game
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.ShipState as State
import Melee.Step as Step
import Melee.Units exposing (..)
import Melee.Velocity as Velocity
import Test exposing (..)


run input arena =
    Step.tick { bottom = input, top = idle } arena


owned body arena =
    Dict.values arena.elements |> List.filter (\el -> el.owner == Owned Bottom && el.body == body) |> List.length


suite : Test
suite =
    describe "Original secondary and combination controls"
        [ test "Earthling point defence draws rays and damages nearby targets" <|
            \() ->
                let
                    base =
                        Init.arena Earthling UrQuan (Seed 1)

                    elements =
                        Dict.filter (\id _ -> id == 2 || id == 3) base.elements
                            |> Dict.map
                                (\id el ->
                                    let
                                        at =
                                            { x =
                                                if id == 2 then
                                                    2000

                                                else
                                                    2300
                                            , y = 2000
                                            }
                                    in
                                    { el | current = { location = at, frameIndex = 0 }, next = { location = at, frameIndex = 0 }, velocity = Velocity.zero }
                                )

                    next =
                        run { idle | special = True } { base | elements = elements }
                in
                Expect.equal ( 1, 41 ) ( owned EarthlingPointDefense next, Game.crew next.combatants.top next )
        , test "Earthling does not spend point-defence energy with no targets" <|
            \() ->
                let
                    base =
                        Init.arena Earthling UrQuan (Seed 1)

                    next =
                        run { idle | special = True } { base | elements = Dict.filter (\id _ -> id == 2) base.elements }
                in
                Expect.equal (State.core base.combatants.bottom).energy (State.core next.combatants.bottom).energy
        , test "Orz special alone does not spend crew or launch a marine" <|
            \() ->
                let
                    next =
                        Init.arena Orz Vux (Seed 1) |> run { idle | special = True }
                in
                Expect.equal ( 0, 16 ) ( owned OrzMarine next, Game.crew next.combatants.bottom next )
        , test "Orz special plus fire launches a marine instead of a howitzer shell" <|
            \() ->
                let
                    next =
                        Init.arena Orz Vux (Seed 1) |> run { idle | special = True, weapon = True }
                in
                Expect.equal ( 1, 0, 15 ) ( owned OrzMarine next, owned OrzHowitzer next, Game.crew next.combatants.bottom next )
        , test "Orz special plus turn rotates the turret without turning its hull" <|
            \() ->
                let
                    next =
                        Init.arena Orz Vux (Seed 1) |> run { idle | special = True, turn = TurnRight }
                in
                case next.combatants.bottom of
                    State.LiveOrz core extra ->
                        Expect.equal ( Facing 4, Facing 1, 0 ) ( core.facing, extra.turretFacing, owned OrzMarine next )

                    _ ->
                        Expect.fail "Expected Nemesis"
        , test "holding Shofixti special cannot skip the safety sequence" <|
            \() ->
                let
                    initial =
                        Init.arena Shofixti UrQuan (Seed 1)

                    next =
                        List.foldl (\_ -> run { idle | special = True }) initial (List.range 1 12)
                in
                Expect.greaterThan 0 (Game.crew next.combatants.bottom next)
        , test "three taps arm and detonate the Shofixti glory device" <|
            \() ->
                let
                    next =
                        List.foldl (\pressed -> run { idle | special = pressed }) (Init.arena Shofixti UrQuan (Seed 1)) [ True, False, True, False, True ]
                in
                Expect.equal 0 (Game.crew next.combatants.bottom next)
        , test "Supox reverse thrust preserves hull facing and consumes no energy" <|
            \() ->
                let
                    initial =
                        Init.arena Supox UrQuan (Seed 1)

                    next =
                        run { idle | special = True, thrust = True } initial

                    core =
                        State.core next.combatants.bottom

                    vx arena =
                        Dict.get 2 arena.elements |> Maybe.map (.velocity >> Velocity.getCurrent >> Tuple.first) |> Maybe.withDefault 0
                in
                Expect.all [ \_ -> Expect.equal (State.core initial.combatants.bottom).energy core.energy, \_ -> Expect.equal (Facing 4) core.facing, \_ -> Expect.lessThan (vx initial) (vx next) ] ()
        , fuzz (Fuzz.intRange 1 100000) "all 25 ships accept secondary and combination inputs without invalid resources" <|
            \seed ->
                let
                    invalid ship =
                        let
                            final =
                                List.foldl (\n -> run { idle | weapon = modBy 3 n == 0, special = modBy 5 n < 3, thrust = True, turn = TurnRight }) (Init.arena ship UrQuan (Seed seed)) (List.range 1 30)

                            core =
                                State.core final.combatants.bottom
                        in
                        core.energy < 0 || core.energy > core.maxEnergy || Game.crew final.combatants.bottom final < 0
                in
                Catalog.all |> List.filter invalid |> Expect.equal []
        ]
