module Property.StrategyTests exposing (suite)

import Expect
import Fuzz
import Helpers.LongGame as LongGame
import Melee.Init as Init
import Melee.Input as Input exposing (CyborgRating(..), Turn(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.Strategy as Strategy
import Melee.Units exposing (Side(..))
import Strategies.DirectPursuit
import Test exposing (..)


suite =
    describe "Pluggable ship strategies"
        [ fuzz (Fuzz.intRange 1 100000) "injected bot strategies never override human controls" <|
            \seed ->
                let
                    game =
                        LongGame.start seed [ Pkunk, Melnorme, Umgah ] [ Umgah, Supox, Pkunk ]

                    humanGame =
                        { game | mode = Game.Versus }

                    ratings =
                        { bottom = AwesomeCyborg, top = AwesomeCyborg }

                    pilots =
                        { bottom = \_ -> Strategies.DirectPursuit.strategy, top = \_ -> Strategies.DirectPursuit.strategy }

                    advance step =
                        List.foldl (\_ model -> step 250 (Keys.press "ArrowUp" Keys.none) model) humanGame (List.range 1 40)
                in
                Expect.equal (advance Game.advance) (advance (Game.advanceWith pilots ratings))
        , fuzz (Fuzz.intRange 1 100000) "a candidate replays deterministically with the same seed" <|
            \seed ->
                let
                    pilots =
                        { bottom = Strategy.override Pkunk Strategies.DirectPursuit.strategy Strategy.originalRoster, top = Strategy.originalRoster }

                    replay () =
                        LongGame.runWith pilots
                            { bottom = AwesomeCyborg, top = AwesomeCyborg }
                            (10 * 60)
                            (LongGame.start seed [ Pkunk ] [ Umgah ])
                in
                Expect.equal (replay ()) (replay ())
        , test "ship overrides affect only the named kind and cannot directly mutate the arena" <|
            \() ->
                let
                    idle =
                        Input.idle

                    candidate =
                        Strategy.controls (\context -> ( { idle | weapon = True }, context.seed ))

                    roster =
                        Strategy.override Pkunk candidate Strategy.originalRoster

                    arena =
                        Init.arena Pkunk Umgah (Seed 1)

                    ( input, unchanged ) =
                        Strategy.run roster AwesomeCyborg Bottom arena
                in
                Expect.all
                    [ \_ -> Expect.equal { idle | weapon = True } input
                    , \_ -> Expect.equal arena unchanged
                    , \_ -> Expect.equal (Strategy.run Strategy.originalRoster AwesomeCyborg Top arena) (Strategy.run roster AwesomeCyborg Top arena)
                    ]
                    ()
        ]
