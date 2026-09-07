module Property.CameraTests exposing (suite)

import Expect
import Fuzz
import Melee.Init as Init
import Melee.Local as Game
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.View as View
import Test exposing (..)


suite : Test
suite =
    describe "HD presentation zoom"
        [ fuzz (Fuzz.floatRange 1 100) "zoom eases toward its target without changing physics" <|
            \elapsed ->
                let
                    base =
                        Game.init

                    arena =
                        Init.arena Chmmr Spathi (Seed 1)

                    target =
                        toFloat (View.camera arena).w

                    initial =
                        { base | phase = Game.Combat arena, zoomWidth = target * 2 }

                    next =
                        Game.animate elapsed initial
                in
                Expect.all [ \_ -> Expect.equal initial.phase next.phase, \_ -> Expect.lessThan initial.zoomWidth next.zoomWidth, \_ -> Expect.greaterThan target next.zoomWidth ] ()
        , test "zoom expands smoothly as ships leave the inner zoom level" <|
            \() ->
                let
                    base =
                        Game.init

                    arena =
                        Init.arena Chmmr Spathi (Seed 1)

                    target =
                        toFloat (View.camera arena).w

                    next =
                        Game.animate 16 { base | phase = Game.Combat arena, zoomWidth = target / 2 }
                in
                Expect.all [ \_ -> Expect.greaterThan (target / 2) next.zoomWidth, \_ -> Expect.lessThan target next.zoomWidth ] ()
        , test "online presentation never advances simulation frames or resources" <|
            \() ->
                let
                    base =
                        Game.init

                    arena =
                        Init.arena Chmmr Spathi (Seed 1)

                    next =
                        List.foldl (\_ -> Game.present 16) { base | phase = Game.Combat arena } (List.range 1 120)
                in
                Game.phaseArena next.phase |> Maybe.map (\a -> ( a.frame, a.elements, a.combatants )) |> Expect.equal (Just ( arena.frame, arena.elements, arena.combatants ))
        ]
