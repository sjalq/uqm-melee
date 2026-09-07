module Property.CyborgLivenessTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Cyborg as Cyborg
import Melee.Id exposing (toInt)
import Melee.Init as Init
import Melee.Input as Input exposing (CyborgRating(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.ShipState as State
import Melee.Step as Step
import Melee.Units exposing (Side(..))
import Test exposing (..)


suite =
    describe "Cyborg liveness"
        [ fuzz (Fuzz.intRange 1 100000) "Melnorme engages a visible stationary Supox from a fresh round" <|
            \seed ->
                Init.arena Melnorme Supox (Seed seed)
                    |> engages Bottom 240
                    |> Expect.equal True
        , test "each pilot engages independently in every ordered original-ship matchup" <|
            \() ->
                Catalog.all
                    |> List.concatMap
                        (\bottom ->
                            Catalog.all
                                |> List.filterMap
                                    (\top ->
                                        let
                                            arena =
                                                Init.arena bottom top (Seed 1701)
                                        in
                                        if engages Bottom 240 arena && engages Top 240 arena then
                                            Nothing

                                        else
                                            Just ( bottom, top )
                                    )
                        )
                    |> Expect.equal []
        , fuzz3 (Fuzz.oneOfValues Catalog.all)
            (Fuzz.oneOfValues Catalog.all)
            (Fuzz.intRange 1 100000)
            "surviving ships still issue pilot intent after two legal round transitions"
          <|
            \ship opponent seed ->
                let
                    fleets =
                        { bottom = [ ship ], top = [ opponent, opponent, opponent ] }

                    base =
                        Game.init

                    first =
                        { base | mode = Game.Demo, difficulty = AwesomeCyborg, fleets = fleets, remaining = fleets, round = 1, phase = Game.Combat (Init.arena ship opponent (Seed seed)) }

                    third =
                        nextRound (nextRound first)
                in
                case Game.phaseArena third.phase of
                    Nothing ->
                        Expect.fail "Two survivor transitions must produce a third-round arena"

                    Just arena ->
                        Expect.all
                            [ \_ -> Expect.equal 3 third.round
                            , \_ -> Expect.equal True (engages Bottom 240 arena)
                            , \_ -> Expect.equal True (engages Top 240 arena)
                            ]
                            ()
        ]



-- Observe this pilot's commands, not combined screen positions: the other
-- ship, camera zoom, or gravity must not conceal a pilot that never acts.


engages : Side -> Int -> Arena -> Bool
engages side frames arena =
    if frames <= 0 then
        False

    else
        let
            ( input, seed ) =
                Cyborg.think AwesomeCyborg side arena arena.seed
        in
        if input /= Input.idle then
            True

        else
            engages side (frames - 1) (Step.tick { bottom = Input.idle, top = Input.idle } { arena | seed = seed })


nextRound : Game.Model -> Game.Model
nextRound game =
    let
        fought =
            List.foldl (\_ model -> Game.advance 100 Keys.none model) game (List.range 1 20)
    in
    case Game.phaseArena fought.phase of
        Nothing ->
            fought

        Just arena ->
            let
                -- Generate a valid terminal state with a living bottom pilot;
                -- retain the counters, flags and ship-specific state from play.
                bottom =
                    State.core arena.combatants.bottom

                top =
                    State.core arena.combatants.top

                terminal =
                    { arena | elements = arena.elements |> Dict.update (toInt bottom.element) (Maybe.map (\el -> { el | points = max 1 el.points })) |> Dict.update (toInt top.element) (Maybe.map (\el -> { el | points = 0 })) }
            in
            Game.finishRound terminal fought
