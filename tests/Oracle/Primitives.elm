port module Oracle.Primitives exposing (main)

{-| Deterministic dump of every pure integer primitive the battle simulation
rests on. The Rust port emits the same sweep from the same code path
(`rust/crates/melee-core/src/bin/oracle_primitives.rs`); `diff` of the two dumps
must be empty. Sweep inputs are drawn from the battle RNG itself, so neither
side needs a second generator that could drift.
-}

import Melee.Rng as Rng exposing (Seed(..))
import Melee.Trig as Trig
import Melee.Units exposing (VelocityDesc)
import Melee.Velocity as Velocity
import Platform


port emit : String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), emit (String.join "\n" dump) )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


dump : List String
dump =
    List.concat
        [ rngSweep
        , trigSweep
        , arctanSweep
        , sqrtSweep
        , wrapSweep
        , velocitySweep
        ]


{-| A reproducible stream of "random" ints in a range, drawn from the battle
RNG so both ports share one definition of the sequence.
-}
stream : Int -> Int -> Seed -> ( List Int, Seed )
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


row : String -> List Int -> String
row tag values =
    tag ++ " " ++ String.join " " (List.map String.fromInt values)


rngSweep : List String
rngSweep =
    let
        walk n seed acc =
            if n <= 0 then
                List.reverse acc

            else
                let
                    ( v, next ) =
                        Rng.next seed
                in
                walk (n - 1) next (v :: acc)

        forSeed s =
            let
                values =
                    walk 200 (Seed s) []
            in
            row ("rng " ++ String.fromInt s) values

        seedRound s n =
            let
                ( prev, Seed after ) =
                    Rng.seedRandom n (Seed s)
            in
            row ("rngseed " ++ String.fromInt s ++ " " ++ String.fromInt n) [ prev, after ]
    in
    List.map forSeed [ 1, 2, 42, 1701, 16807, 127773, 2147483646 ]
        ++ List.map (\( s, n ) -> seedRound s n) [ ( 1, 0 ), ( 42, -5 ), ( 42, 2147483647 ), ( 42, 2147483648 ), ( 7, 12345 ) ]


trigSweep : List String
trigSweep =
    let
        mags =
            [ -100000, -32768, -4097, -256, -33, -1, 0, 1, 33, 256, 4097, 32768, 100000, 1048576 ]

        angles =
            List.range -70 70
    in
    List.map
        (\a ->
            row ("sin " ++ String.fromInt a)
                (List.map (Trig.sine a) mags ++ List.map (Trig.cosine a) mags)
        )
        angles
        ++ List.map
            (\a -> row ("norm " ++ String.fromInt a) [ Trig.normalizeAngle a, Trig.normalizeFacing a ])
            (List.range -40 40)


arctanSweep : List String
arctanSweep =
    let
        grid =
            [ -4096, -1024, -257, -64, -17, -1, 0, 1, 17, 64, 257, 1024, 4096 ]

        pairs =
            List.concatMap (\x -> List.map (\y -> ( x, y )) grid) grid

        ( rx, seed1 ) =
            stream 400 200000 (Seed 1701)

        ( ry, _ ) =
            stream 400 200000 seed1

        randomPairs =
            List.map2 Tuple.pair rx ry
    in
    List.map (\( x, y ) -> row ("atan " ++ String.fromInt x ++ " " ++ String.fromInt y) [ Trig.arctan x y ])
        (pairs ++ randomPairs)


sqrtSweep : List String
sqrtSweep =
    let
        ( rs, _ ) =
            stream 300 2000000000 (Seed 99)

        values =
            List.range -3 300 ++ [ 65535, 65536, 1048576, 2146689000 ] ++ List.map abs rs
    in
    List.map (\v -> row ("sqrt " ++ String.fromInt v) [ Trig.squareRoot v ]) values


wrapSweep : List String
wrapSweep =
    let
        widths =
            [ 0, 1, 64, 8192, 7680 ]

        vals =
            [ -9000, -8192, -1, 0, 1, 4095, 4096, 8191, 8192, 9000 ]
    in
    List.concatMap
        (\w ->
            List.map
                (\v ->
                    row ("wrap " ++ String.fromInt w ++ " " ++ String.fromInt v)
                        [ Trig.wrap v w, Trig.wrapDelta v w ]
                )
                vals
        )
        widths


velocitySweep : List String
velocitySweep =
    let
        ( dxs, seed1 ) =
            stream 500 4000 (Seed 424242)

        ( dys, _ ) =
            stream 500 4000 seed1

        pairs =
            List.map2 Tuple.pair dxs dys

        describe : VelocityDesc -> List Int
        describe v =
            let
                (Melee.Units.Angle a) =
                    v.travelAngle
            in
            [ a
            , v.vector.width
            , v.vector.height
            , v.fract.width
            , v.fract.height
            , v.error.width
            , v.error.height
            , v.incr.width
            , v.incr.height
            ]

        -- Integrate 40 frames so the error accumulator is exercised, not just set.
        integrate : Int -> VelocityDesc -> ( Int, Int ) -> ( ( Int, Int ), VelocityDesc )
        integrate n v ( sx, sy ) =
            if n <= 0 then
                ( ( sx, sy ), v )

            else
                let
                    ( ( dx, dy ), v1 ) =
                        Velocity.getNext 1 v
                in
                integrate (n - 1) v1 ( sx + dx, sy + dy )

        components ( dx, dy ) =
            let
                v =
                    Velocity.setComponents dx dy

                ( cx, cy ) =
                    Velocity.getCurrent v

                ( ( sx, sy ), after ) =
                    integrate 40 v ( 0, 0 )
            in
            row ("vel " ++ String.fromInt dx ++ " " ++ String.fromInt dy)
                (describe v ++ [ cx, cy, sx, sy ] ++ describe after)

        vectors =
            List.concatMap
                (\mag ->
                    List.map
                        (\f ->
                            let
                                v =
                                    Velocity.setVector mag (Melee.Units.Facing f)

                                ( ( sx, sy ), after ) =
                                    integrate 24 v ( 0, 0 )
                            in
                            row ("velvec " ++ String.fromInt mag ++ " " ++ String.fromInt f)
                                (describe v ++ [ sx, sy ] ++ describe after)
                        )
                        (List.range -3 18)
                )
                [ 0, 1, 4, 7, 16, 40, 100, 255, 1024 ]

        deltas =
            List.map
                (\( dx, dy ) ->
                    let
                        base =
                            Velocity.setComponents dx dy

                        stepped =
                            Velocity.delta (dy // 3) (dx // 5) base
                    in
                    row ("veldelta " ++ String.fromInt dx ++ " " ++ String.fromInt dy) (describe stepped)
                )
                pairs
    in
    List.map components pairs ++ vectors ++ deltas
