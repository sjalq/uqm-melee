module Property.SurvivorMotionTests exposing (suite)

import Dict
import Expect
import Melee.Init as Init
import Melee.Input exposing (CyborgRating(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.ShipState as State
import Melee.Units exposing (Side(..))
import Test exposing (test)


suite =
    test "stationary survivor with stale maximum-speed flags resumes fighting" <|
        \_ ->
            let
                fresh =
                    Init.arena Melnorme Supox (Seed 1701)

                survivor =
                    State.core fresh.combatants.top

                flags =
                    survivor.flags

                a =
                    { fresh | combatants = { bottom = fresh.combatants.bottom, top = State.setCore { survivor | flags = { flags | atMaxSpeed = True } } fresh.combatants.top } }

                base =
                    Game.init

                model =
                    { base | mode = Game.Demo, difficulty = AwesomeCyborg, phase = Game.Combat a }

                after =
                    List.foldl (\_ m -> Game.advance 100 Keys.none m) model (List.range 1 50)

                positions =
                    Game.phaseArena >> Maybe.map (\ar -> Dict.filter (\id _ -> id == 2 || id == 3) ar.elements |> Dict.map (\_ e -> e.current.location))
            in
            Expect.notEqual (positions model.phase) (positions after.phase)
