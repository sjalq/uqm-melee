module Property.MaskOptimizationTests exposing (suite)

import Array
import Expect
import Fuzz
import Melee.Masks as Masks
import Test exposing (..)


suite =
    fuzz3 maskFuzzer maskFuzzer (Fuzz.pair (Fuzz.intRange -30 30) (Fuzz.intRange -30 30)) "optimized mask overlap is identical to the direct row scan" <|
        \a b ( dx, dy ) ->
            Masks.overlap a b dx dy |> Expect.equal (referenceOverlap a b dx dy)


maskFuzzer =
    Fuzz.intRange 1 20
        |> Fuzz.andThen
            (\height ->
                Fuzz.map4
                    (\width x y rows -> { width = width, height = height, x = x, y = y, rows = Array.fromList rows })
                    (Fuzz.intRange 1 20)
                    (Fuzz.intRange 0 10)
                    (Fuzz.intRange 0 10)
                    (Fuzz.listOfLength height rowFuzzer)
            )


rowFuzzer =
    Fuzz.listOfLengthBetween 0
        3
        (Fuzz.map2 (\a b -> ( min a b, max a b )) (Fuzz.intRange 0 19) (Fuzz.intRange 0 19))


referenceOverlap a b dx dy =
    let
        left =
            dx + a.x - b.x

        top =
            dy + a.y - b.y

        first =
            max 0 top

        last =
            min (a.height - 1) (top + b.height - 1)

        row y =
            let
                ar =
                    Array.get y a.rows |> Maybe.withDefault []

                br =
                    Array.get (y - top) b.rows |> Maybe.withDefault []
            in
            List.any (\( x0, x1 ) -> List.any (\( z0, z1 ) -> x0 <= z1 + left && x1 >= z0 + left) br) ar
    in
    left < a.width && left + b.width > 0 && first <= last && List.any row (List.range first last)
