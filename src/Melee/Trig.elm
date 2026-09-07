module Melee.Trig exposing
    ( angleToFacing
    , arctan
    , cosine
    , facingToAngle
    , fullCircle
    , halfCircle
    , normalizeAngle
    , normalizeFacing
    , quadrant
    , sine
    , squareRoot
    , wrap
    , wrapDelta
    , wrapPoint
    )

{-| Integer trig from units.h / trans.c. No floats.

SINE(a,m) = (sinetab[a & 63] \* m) >> 14
COSINE(a,m) = SINE(a + 16, m)

-}

import Melee.Units exposing (Angle(..), Facing(..), WorldExtent, WorldPoint)


fullCircle : Int
fullCircle =
    64


halfCircle : Int
halfCircle =
    32


quadrant : Int
quadrant =
    16


sinShift : Int
sinShift =
    14


{-| trans.c sinetab, FLT\_ADJUST toward zero, SIN\_SCALE = 16384.
-}
sinetab : List Int
sinetab =
    [ -16384
    , -16305
    , -16069
    , -15678
    , -15136
    , -14449
    , -13622
    , -12664
    , -11585
    , -10393
    , -9102
    , -7723
    , -6269
    , -4756
    , -3196
    , -1605
    , 0
    , 1605
    , 3196
    , 4756
    , 6269
    , 7723
    , 9102
    , 10393
    , 11585
    , 12664
    , 13622
    , 14449
    , 15136
    , 15678
    , 16069
    , 16305
    , 16384
    , 16305
    , 16069
    , 15678
    , 15136
    , 14449
    , 13622
    , 12664
    , 11585
    , 10393
    , 9102
    , 7723
    , 6269
    , 4756
    , 3196
    , 1605
    , 0
    , -1605
    , -3196
    , -4756
    , -6269
    , -7723
    , -9102
    , -10393
    , -11585
    , -12664
    , -13622
    , -14449
    , -15136
    , -15678
    , -16069
    , -16305
    ]


atantab : List Int
atantab =
    [ 0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 8, 8, 8 ]


listAt : Int -> List Int -> Int
listAt i xs =
    xs
        |> List.drop i
        |> List.head
        |> Maybe.withDefault 0


normalizeAngle : Int -> Int
normalizeAngle a =
    modBy fullCircle a


normalizeFacing : Int -> Int
normalizeFacing f =
    modBy 16 f


angleToFacing : Angle -> Facing
angleToFacing (Angle a) =
    Facing (normalizeFacing ((normalizeAngle a + 2) // 4))


facingToAngle : Facing -> Angle
facingToAngle (Facing f) =
    Angle (normalizeFacing f * 4)


sinVal : Int -> Int
sinVal a =
    listAt (normalizeAngle a) sinetab


sine : Int -> Int -> Int
sine a m =
    let
        product =
            sinVal a * m

        scale =
            2 ^ sinShift
    in
    if product < 0 then
        negate ((negate product + scale - 1) // scale)

    else
        product // scale


cosine : Int -> Int -> Int
cosine a m =
    sine (a + quadrant) m


{-| trans.c ARCTAN. (0,0) returns FULL\_CIRCLE (64), then NORMALIZE\_ANGLE
makes it 0. velocity.c treats 64 as "zero vector" before normalize.
-}
arctan : Int -> Int -> Int
arctan deltaX deltaY =
    if deltaX == 0 && deltaY == 0 then
        fullCircle

    else
        let
            v1Abs =
                abs deltaX

            v2Abs =
                abs deltaY

            raw =
                if v1Abs > v2Abs then
                    quadrant
                        - listAt (((v2Abs * 32) + (v1Abs // 2)) // v1Abs) atantab

                else
                    listAt (((v1Abs * 32) + (v2Abs // 2)) // v2Abs) atantab

            afterX =
                if deltaX < 0 then
                    fullCircle - raw

                else
                    raw

            afterY =
                if deltaY > 0 then
                    halfCircle - afterX

                else
                    afterX
        in
        normalizeAngle afterY


wrap : Int -> Int -> Int
wrap v w =
    if w <= 0 then
        v

    else if v < 0 then
        v + w

    else if v >= w then
        v - w

    else
        v


wrapDelta : Int -> Int -> Int
wrapDelta d w =
    if w <= 0 then
        d

    else
        let
            half =
                w // 2
        in
        if d < 0 then
            if -d <= half then
                d

            else
                w + d

        else if d <= half then
            d

        else
            d - w


wrapPoint : WorldExtent -> WorldPoint -> WorldPoint
wrapPoint space p =
    { x = wrap p.x space.width
    , y = wrap p.y space.height
    }


{-| Integer square root, floor. Matches C square\_root for melee-scale
values (display distances, velocity squares).
-}
squareRoot : Int -> Int
squareRoot value =
    if value <= 0 then
        0

    else
        isqrt 0 value value


isqrt : Int -> Int -> Int -> Int
isqrt lo hi n =
    if lo >= hi then
        lo

    else
        let
            mid =
                (lo + hi + 1) // 2
        in
        if mid > 46340 then
            -- mid*mid would exceed 32-bit; melee never needs this
            isqrt lo (mid - 1) n

        else if mid * mid > n then
            isqrt lo (mid - 1) n

        else
            isqrt mid hi n
