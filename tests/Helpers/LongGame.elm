module Helpers.LongGame exposing (Outcome(..), Report, healthy, nextEvent, run, runFold, runWith, start)

import Melee.Catalog as Catalog
import Melee.Input exposing (CyborgRating(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Rate as Rate
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


healthy : Int -> Report -> Bool
healthy quietLimit report =
    report.outcome == Completed || report.longestQuietTicks < quietLimit


start : Int -> List ShipKind -> List ShipKind -> Game.Model
start seed bottom top =
    let
        base =
            Game.init
    in
    Game.update Game.Start { base | mode = Game.Demo, difficulty = AwesomeCyborg, seed = Seed seed, fleets = { bottom = bottom, top = top }, sound = False }


run : Int -> Game.Model -> Report
run maxTicks game =
    runWith Strategy.originalPilots { bottom = game.difficulty, top = game.difficulty } maxTicks game


runWith : Strategy.Pilots -> Melee.Units.Sided CyborgRating -> Int -> Game.Model -> Report
runWith pilots ratings maxTicks game =
    runFold (\_ s -> ( pilots, s )) () ratings maxTicks game


{-| Like `runWith`, but `prep` may rebuild the pilots between events.
Use this to thread policy feedback across 24 Hz thinks without storing
it in the battle Seed or combatant combat fields.
-}
runFold : (Game.Model -> s -> ( Strategy.Pilots, s )) -> s -> Melee.Units.Sided CyborgRating -> Int -> Game.Model -> Report
runFold prep state ratings maxTicks game =
    loopFold prep ratings maxTicks 0 0 0 (progress game) state game


health : Game.Model -> ( Int, Int )
health game =
    case crewOf game.phase of
        Just crew ->
            crew

        Nothing ->
            case game.survivor of
                Just arena ->
                    ( Game.crew arena.combatants.bottom arena, Game.crew arena.combatants.top arena )

                Nothing ->
                    ( 0, 0 )


crewOf : Game.Phase -> Maybe ( Int, Int )
crewOf phase =
    Game.phaseArena phase
        |> Maybe.map (\a -> ( Game.crew a.combatants.bottom a, Game.crew a.combatants.top a ))


progress : Game.Model -> ( Int, Int, Int )
progress game =
    let
        ( bottom, top ) =
            health game
    in
    ( game.round, bottom, top )


loopFold : (Game.Model -> s -> ( Strategy.Pilots, s )) -> Melee.Units.Sided CyborgRating -> Int -> Int -> Int -> Int -> ( Int, Int, Int ) -> s -> Game.Model -> Report
loopFold prep ratings maxTicks ticks quiet longest previous state game =
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
        , ships = shipsOf game
        }

    else
        let
            ( pilots, nextState ) =
                prep game state

            -- One real 60 Hz update. This includes the 24 Hz physics pump,
            -- countdowns, death, resurrection, selection and survivor carry.
            ( elapsed, next ) =
                nextEvent pilots ratings (maxTicks - ticks) game

            current =
                progress next

            dry =
                if current /= previous then
                    0

                else
                    quiet + elapsed

            longestBeforeProgress =
                if current /= previous then
                    quiet + elapsed - 1

                else
                    dry
        in
        loopFold prep ratings maxTicks (ticks + elapsed) dry (max longest longestBeforeProgress) current nextState next


shipsOf : Game.Model -> ( String, String )
shipsOf game =
    let
        fromArena arena =
            ( (Catalog.info (State.kind arena.combatants.bottom)).name, (Catalog.info (State.kind arena.combatants.top)).name )
    in
    case Game.phaseArena game.phase of
        Just arena ->
            fromArena arena

        Nothing ->
            case game.survivor of
                Just arena ->
                    fromArena arena

                Nothing ->
                    ( "", "" )


nextEvent : Strategy.Pilots -> Melee.Units.Sided CyborgRating -> Int -> Game.Model -> ( Int, Game.Model )
nextEvent pilots ratings remaining game =
    case game.phase of
        Game.Combat arena ->
            let
                displayTicks =
                    max 1 ((Rate.displayHz - arena.pumpAcc + Rate.cBattleFramesPerSecond - 1) // Rate.cBattleFramesPerSecond)
            in
            if displayTicks <= remaining then
                let
                    skipped =
                        displayTicks - 1

                    primed =
                        { game | phase = Game.Combat { arena | pumpAcc = arena.pumpAcc + skipped * Rate.cBattleFramesPerSecond } }
                in
                ( displayTicks, Game.tickAuthoritativeWith pilots ratings Keys.none primed )

            else
                ( 1, Game.advanceAuthoritativeWith pilots ratings (1000 / 60) Keys.none game )

        _ ->
            ( 1, Game.advanceAuthoritativeWith pilots ratings (1000 / 60) Keys.none game )
