module Property.LongGameTests exposing (suite)

import Dict
import Expect
import Fuzz
import Helpers.LongGame as LongGame
import Melee.Catalog as Catalog
import Melee.Input exposing (CyborgRating(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Ship exposing (ShipKind(..))
import Melee.Strategy as Strategy
import Test exposing (..)


suite =
    describe "Full match loop endurance"
        [ fuzz (Fuzz.intRange 1 1000000) "headless event stepping matches every skipped 60 Hz update" <|
            \seed ->
                let
                    ratings =
                        { bottom = AwesomeCyborg, top = GoodCyborg }

                    combat =
                        List.foldl (\_ model -> Game.advanceAuthoritativeWith Strategy.originalPilots ratings (1000 / 60) Keys.none model)
                            (LongGame.start seed [ Chenjesu ] [ UrQuan ])
                            (List.range 1 91)

                    ( elapsed, actual ) =
                        LongGame.nextEvent Strategy.originalPilots ratings 10 combat

                    expected =
                        List.foldl (\_ model -> Game.advanceAuthoritativeWith Strategy.originalPilots ratings (1000 / 60) Keys.none model) combat (List.range 1 elapsed)
                in
                Expect.equal expected actual
        , fuzz (Fuzz.intRange 1 1000000) "authoritative stepping changes only presentation history" <|
            \seed ->
                let
                    initial =
                        LongGame.start seed [ Chenjesu ] [ UrQuan ]

                    run advance =
                        List.foldl (\_ model -> advance (1000 / 60) Keys.none model) initial (List.range 1 300)

                    withoutPresentation model =
                        { model | phase = Game.mapArena (\arena -> { arena | previousLocations = Dict.empty }) model.phase }
                in
                run Game.advanceAuthoritative |> withoutPresentation |> Expect.equal (run Game.advance |> withoutPresentation)
        , test "Pkunk versus Umgah fleets continue beyond round six" <|
            \() ->
                [ 1, 1701, 314159 ]
                    |> List.map (\seed -> ( seed, LongGame.run (60 * 30 * 60) (LongGame.start seed (List.repeat 6 Pkunk) (List.repeat 6 Umgah)) ))
                    |> List.filter (\( _, report ) -> report.outcome == LongGame.Invalidated)
                    |> Expect.equal []
        , test "Standard versus Good Androsynth counterexample completes within thirty simulated minutes" <|
            \() ->
                LongGame.runWith Strategy.originalPilots
                    { bottom = StandardCyborg, top = GoodCyborg }
                    (60 * 30 * 60)
                    (LongGame.start 1 [ Androsynth ] [ Androsynth ])
                    |> .outcome
                    |> Expect.equal LongGame.Completed
        , fuzz3 (Fuzz.oneOfValues Catalog.all)
            (Fuzz.oneOfValues Catalog.all)
            (Fuzz.map3
                (\bottomRating topRating seed -> ( bottomRating, topRating, seed ))
                (Fuzz.oneOfValues [ StandardCyborg, GoodCyborg, AwesomeCyborg ])
                (Fuzz.oneOfValues [ StandardCyborg, GoodCyborg, AwesomeCyborg ])
                (Fuzz.intRange 1 1000000)
            )
            "random ship and cyborg-rating combinations do not stall before invalidation"
          <|
            \bottom top ( bottomRating, topRating, seed ) ->
                let
                    report =
                        LongGame.runWith Strategy.originalPilots
                            { bottom = bottomRating, top = topRating }
                            (60 * 10 * 60)
                            (LongGame.start seed [ bottom ] [ top ])
                in
                if LongGame.healthy (60 * 5 * 60) report then
                    Expect.pass

                else
                    Expect.fail
                        ("stalled and invalidated after "
                            ++ String.fromInt report.ticks
                            ++ " ticks in round "
                            ++ String.fromInt report.rounds
                            ++ "; ships="
                            ++ Debug.toString report.ships
                            ++ "; ratings="
                            ++ Debug.toString ( bottomRating, topRating )
                            ++ "; seed="
                            ++ String.fromInt seed
                            ++ "; crew="
                            ++ Debug.toString report.crew
                            ++ "; longestQuietTicks="
                            ++ String.fromInt report.longestQuietTicks
                        )
        ]
