port module Oracle.Bench exposing (main)

{-| Like-for-like throughput benchmark of the arithmetic the battle loop is
actually made of: velocity integration and sprite-mask overlap. The Rust bin
`oracle_bench` runs the identical workload, so the ratio of the two wall times
is a real per-component speed figure rather than an estimate.

Both sides print the same checksum, so a run that "went faster" by doing less
work is visible immediately.
-}

import Melee.Catalog as Catalog
import Melee.Masks as Masks
import Melee.Rng as Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Facing(..), VelocityDesc)
import Melee.Velocity as Velocity
import Platform


port emit : String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), emit report )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


velocityRounds : Int
velocityRounds =
    200


maskRounds : Int
maskRounds =
    200


report : String
report =
    "velocity "
        ++ String.fromInt (velocityBench velocityRounds 0)
        ++ "\nmask "
        ++ String.fromInt (maskBench maskRounds 0)


pairs : List ( Int, Int )
pairs =
    let
        stream count span seed0 =
            let
                go n seed acc =
                    if n <= 0 then
                        ( List.reverse acc, seed )

                    else
                        let
                            ( v, next ) =
                                Rng.next seed
                        in
                        go (n - 1) next (modBy span v - span // 2 :: acc)
            in
            go count seed0 []

        ( dxs, seed1 ) =
            stream 500 4000 (Seed 424242)

        ( dys, _ ) =
            stream 500 4000 seed1
    in
    List.map2 Tuple.pair dxs dys


{-| 500 launches, each integrated for 40 frames: the same work the element
loop does when projectiles fly.
-}
velocityBench : Int -> Int -> Int
velocityBench rounds acc =
    if rounds <= 0 then
        acc

    else
        velocityBench (rounds - 1) (acc + List.foldl integrateOne 0 pairs)


integrateOne : ( Int, Int ) -> Int -> Int
integrateOne ( dx, dy ) acc =
    let
        step : Int -> VelocityDesc -> Int -> Int
        step n v total =
            if n <= 0 then
                total

            else
                let
                    ( ( sx, sy ), next ) =
                        Velocity.getNext 1 v
                in
                step (n - 1) next (total + sx + sy)
    in
    acc + step 40 (Velocity.setComponents dx dy) 0


offsets : List Int
offsets =
    List.map (\i -> i * 7 - 63) (List.range 0 18)


maskPairs : List ( Masks.Mask, Masks.Mask )
maskPairs =
    let
        hull kind facing =
            Masks.get (Catalog.sprite kind facing)
    in
    List.filterMap identity
        (List.map (\( a, b ) -> Maybe.map2 Tuple.pair (Tuple.first a |> (\k -> hull k (Tuple.second a))) (Tuple.first b |> (\k -> hull k (Tuple.second b))))
            [ ( ( Pkunk, 0 ), ( Umgah, 8 ) )
            , ( ( Yehat, 3 ), ( Pkunk, 11 ) )
            , ( ( Chenjesu, 5 ), ( Chmmr, 2 ) )
            , ( ( UrQuan, 7 ), ( Earthling, 13 ) )
            ]
        )


{-| Every probe pair over a 19x19 offset grid: the collision inner loop.
-}
maskBench : Int -> Int -> Int
maskBench rounds acc =
    if rounds <= 0 then
        acc

    else
        maskBench (rounds - 1) (acc + List.foldl overlapPair 0 maskPairs)


overlapPair : ( Masks.Mask, Masks.Mask ) -> Int -> Int
overlapPair ( a, b ) acc =
    List.foldl
        (\dy outer ->
            List.foldl
                (\dx inner ->
                    if Masks.overlap a b dx dy then
                        inner + 1

                    else
                        inner
                )
                outer
                offsets
        )
        acc
        offsets
