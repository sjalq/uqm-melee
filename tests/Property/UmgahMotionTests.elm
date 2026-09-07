module Property.UmgahMotionTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Id exposing (toInt)
import Melee.Init as Init
import Melee.Input as Input
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.ShipState as State
import Melee.Step as Step
import Melee.Units exposing (Facing(..))
import Melee.Velocity as Velocity
import Test exposing (..)


suite =
    fuzz (Fuzz.intRange 0 15) "Umgah reverse zip moves this frame and ends with zero velocity, as in C preprocess/postprocess" <|
        \facing ->
            let
                original =
                    Init.arena Umgah Pkunk (Seed 1)

                core =
                    State.core original.combatants.bottom

                bottom =
                    State.setCore { core | facing = Facing facing } original.combatants.bottom

                -- Remove environmental forces, preserving both real ships.
                arena =
                    { original | combatants = { bottom = bottom, top = original.combatants.top }, elements = Dict.filter (\_ el -> el.flags.playerShip) original.elements }

                getShip a =
                    Dict.get (toInt core.element) a.elements

                input =
                    Input.idle

                after =
                    Step.tick { bottom = { input | special = True }, top = input } arena
            in
            Expect.all
                [ \_ -> Expect.notEqual (getShip arena |> Maybe.map (.current >> .location)) (getShip after |> Maybe.map (.current >> .location))
                , \_ -> Expect.equal (Just ( 0, 0 )) (getShip after |> Maybe.map (.velocity >> Velocity.getCurrent))
                , \_ -> Expect.equal (core.energy - 1) (State.core after.combatants.bottom).energy
                ]
                ()
