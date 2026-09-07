module Exhaustive.ShipProwessMatrixTests exposing (suite)

import Expect
import Helpers.LongGame as LongGame
import Melee.Catalog as Catalog
import Melee.Input exposing (CyborgRating(..))
import Melee.Strategy as Strategy
import Test exposing (..)


suite =
    Catalog.all
        |> List.indexedMap
            (\bottomIndex bottom ->
                Catalog.all
                    |> List.indexedMap
                        (\topIndex top ->
                            ratings
                                |> List.concatMap
                                    (\bottomRating ->
                                        ratings
                                            |> List.map
                                                (\topRating ->
                                                    matrixCase (1 + bottomIndex * List.length Catalog.all + topIndex) bottom top bottomRating topRating
                                                )
                                    )
                        )
                    |> List.concat
            )
        |> List.concat
        |> describe "all ordered ship and prowess combinations"


ratings =
    [ StandardCyborg, GoodCyborg, AwesomeCyborg ]


matrixTicks =
    60 * 6


matrixCase seed bottom top bottomRating topRating =
    test
        ("matrix bottom="
            ++ (Catalog.info bottom).name
            ++ " top="
            ++ (Catalog.info top).name
            ++ " prowess="
            ++ Debug.toString bottomRating
            ++ "/"
            ++ Debug.toString topRating
        )
    <|
        \() ->
            let
                report =
                    LongGame.runWith Strategy.originalPilots
                        { bottom = bottomRating, top = topRating }
                        matrixTicks
                        (LongGame.start seed [ bottom ] [ top ])
            in
            if report.outcome == LongGame.Completed || report.ticks == matrixTicks then
                Expect.pass

            else
                Expect.fail
                    ("stopped early; seed="
                        ++ String.fromInt seed
                        ++ "; round="
                        ++ String.fromInt report.rounds
                        ++ "; crew="
                        ++ Debug.toString report.crew
                    )
