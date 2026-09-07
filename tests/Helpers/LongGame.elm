module Helpers.LongGame exposing (Outcome(..), Report, run, runWith, start)

import Melee.Catalog as Catalog
import Melee.Input exposing (CyborgRating(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind)
import Melee.ShipState as State
import Melee.Strategy as Strategy
import Melee.Units


type alias Report =
    { ticks : Int
    , rounds : Int
    , outcome : Outcome
    , longestQuietTicks : Int
    , winner : String
    , ships : ( String, String )
    , crew : ( Int, Int )
    }


type Outcome
    = Completed
    | Invalidated


start : Int -> List ShipKind -> List ShipKind -> Game.Model
start seed bottom top =
    let
        base =
            Game.init
    in
    Game.update Game.Start { base | mode = Game.Demo, difficulty = AwesomeCyborg, seed = Seed seed, fleets = { bottom = bottom, top = top } }


run : Int -> Game.Model -> Report
run maxTicks game =
    runWith Strategy.originalPilots { bottom = game.difficulty, top = game.difficulty } maxTicks game


runWith : Strategy.Pilots -> Melee.Units.Sided CyborgRating -> Int -> Game.Model -> Report
runWith pilots ratings maxTicks game =
    loop pilots ratings maxTicks 0 0 0 (progress game) game


health : Game.Model -> ( Int, Int )
health game =
    Game.phaseArena game.phase
        |> Maybe.map (\a -> ( Game.crew a.combatants.bottom a, Game.crew a.combatants.top a ))
        |> Maybe.withDefault ( 0, 0 )


progress : Game.Model -> ( Int, Int, Int )
progress game =
    let
        ( bottom, top ) =
            health game
    in
    ( game.round, bottom, top )


loop : Strategy.Pilots -> Melee.Units.Sided CyborgRating -> Int -> Int -> Int -> Int -> ( Int, Int, Int ) -> Game.Model -> Report
loop pilots ratings maxTicks ticks quiet longest previous game =
    let
        complete =
            case game.phase of
                Game.Victory _ ->
                    True

                _ ->
                    False
    in
    if complete || ticks >= maxTicks then
        { ticks = ticks
        , rounds = game.round
        , outcome =
            if complete then
                Completed

            else
                Invalidated
        , longestQuietTicks = longest
        , winner =
            case game.phase of
                Game.Victory (Just side) ->
                    if side == Melee.Units.Bottom then
                        "bottom"

                    else
                        "top"

                Game.Victory Nothing ->
                    "draw"

                _ ->
                    "pending"
        , crew = health game
        , ships = Game.phaseArena game.phase |> Maybe.map (\a -> ( (Catalog.info (State.kind a.combatants.bottom)).name, (Catalog.info (State.kind a.combatants.top)).name )) |> Maybe.withDefault ( "", "" )
        }

    else
        let
            -- One real 60 Hz update. This includes the 24 Hz physics pump,
            -- countdowns, death, resurrection, selection and survivor carry.
            next =
                Game.advanceWith pilots ratings (1000 / 60) Keys.none game

            current =
                progress next

            dry =
                if current /= previous then
                    0

                else
                    quiet + 1
        in
        loop pilots ratings maxTicks (ticks + 1) dry (max longest dry) current next
