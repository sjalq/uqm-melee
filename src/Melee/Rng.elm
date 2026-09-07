module Melee.Rng exposing (Seed(..), next, seedRandom)

{-| The battle RNG. libs/math/random.c is a Park-Miller minimal standard
generator:

    seed = 16807 * (seed % 127773) - 2836 * (seed / 127773)
    seed in 1 .. 2147483646 (0 is coerced to 1, values > M wrap)

The seed is part of the simulation state: it is CRC'd into the netplay
checksum every frame (checksum.c crc\_processRNG) and every consumer
(asteroid spawns, Pkunk resurrection, Melnorme confusion, random ship pick,
AI decisions of the cyborg) must draw from it in the same order on every
client. Nothing in the simulation may use `elm/random`.

-}


{-| Invariant: 1 <= seed <= 2147483646. All arithmetic fits in a JS double
exactly (max intermediate ~ 16807 \* 127773 < 2^31), so Elm Ints are safe.
-}
type Seed
    = Seed Int


aConst : Int
aConst =
    16807


mConst : Int
mConst =
    2147483647


qConst : Int
qConst =
    127773


rConst : Int
rConst =
    2836


coerce : Int -> Int
coerce n =
    if n == 0 then
        1

    else if n > mConst then
        n - mConst

    else if n < 0 then
        1

    else
        n


{-| TFB\_SeedRandom: coerce into 1..M, return previous seed in the pair.
-}
seedRandom : Int -> Seed -> ( Int, Seed )
seedRandom newSeed (Seed old) =
    ( old, Seed (coerce newSeed) )


{-| TFB\_Random. Returns the new seed value (also stored).
-}
next : Seed -> ( Int, Seed )
next (Seed s0) =
    let
        s1 =
            aConst * modBy qConst s0 - rConst * (s0 // qConst)

        s2 =
            if s1 > mConst then
                s1 - mConst

            else if s1 == 0 then
                1

            else
                s1
    in
    ( s2, Seed s2 )
