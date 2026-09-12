module Neat.EncodeTests exposing (suite)

{-| The observation layout, pinned.

`Neat.Encode` and `rust/crates/melee-neat/src/encode.rs` are one contract in two
languages, and the Rust side carries the matching test
`the_blocks_tile_the_vector_exactly_once_in_the_documented_order`. These tests
exist so that widening, reordering or quietly dropping a block cannot pass
unnoticed on this side either.

What they do NOT try to prove is that every slot is something the cyborg also
reads. That argument is made in Rust, and it is made against code rather than
against prose: `only_the_five_declared_slots_exceed_what_the_cyborg_reads` pins
the five deliberate exceptions by index,
`the_slots_credited_to_a_cyborg_function_agree_with_that_function` evaluates the
cyborg itself and compares it slot by slot, and
`the_cyborgs_own_weapon_concern_is_never_displaced_by_a_lesser_one` asks
`cyborg::weapon_concern` for the cyborg's own ranking. What they prove here is
that the shape the two languages agree on is the shape this module actually
emits, on real arenas that have been fought in rather than on an opening
position.

-}

import Expect
import Melee.Battle exposing (Arena)
import Melee.Cyborg as Cyborg
import Melee.Init as Init
import Melee.Input exposing (CyborgRating(..))
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.Step as Step
import Melee.Units exposing (Side(..))
import Neat.Encode as Encode
import Test exposing (Test, describe, test)


{-| The block widths of the documented layout, in order, paired with the slot
each block must begin at. Written out here rather than imported so that the test
states the contract instead of restating whatever the encoder happens to do.
-}
blocks : List ( String, Int )
blocks =
    [ ( "own hull state", 11 )
    , ( "own motion predicates", 5 )
    , ( "own resources", 5 )
    , ( "own hull mass", 1 )
    , ( "enemy geometry", 11 )
    , ( "enemy visible state", 4 )
    , ( "firing solutions", 5 )
    , ( "scalar ship comparisons", 5 )
    , ( "ability bits, both sides", 2 * Encode.abilityBits )
    , ( "gravity concern", 3 )
    , ( "ranked hostile threats", Encode.threatSlots * Encode.threatWidth )
    , ( "crew concern", 7 )
    , ( "neutral-body concern", 6 )
    , ( "constant 1", 1 )
    , ( "hull identity", 2 * Encode.hullBitsPerSide )
    ]


{-| Where each of those blocks starts, copied from the layout comment.
-}
starts : List Int
starts =
    [ 0, 11, 16, 21, 22, 33, 37, 42, 47, 61, 64, 103, 110, 116, 117 ]


suite : Test
suite =
    describe "Neat.Encode layout"
        [ test "the documented blocks tile the vector exactly once, in order" <|
            \() ->
                Expect.equal ( starts, Encode.size )
                    ( List.map Tuple.second blocks
                        |> List.foldl (\width ( at, acc ) -> ( at + width, at :: acc )) ( 0, [] )
                        |> Tuple.second
                        |> List.reverse
                    , List.sum (List.map Tuple.second blocks)
                    )
        , test "the combat sensors run up to and including the constant, then the hull bits" <|
            \() ->
                Expect.equal ( Encode.combatSize, Encode.kindSize, Encode.size )
                    ( 117, 10, 127 )
        , test "every fixture arena produces exactly the documented number of slots" <|
            \() ->
                Expect.equal []
                    (fixtures
                        |> List.concatMap bothSeats
                        |> List.map List.length
                        |> List.filter ((/=) Encode.size)
                    )
        , test "every slot is finite and inside minus one to one" <|
            \() ->
                Expect.equal []
                    (fixtures
                        |> List.concatMap bothSeats
                        |> List.concatMap (List.indexedMap Tuple.pair)
                        |> List.filter (\( _, x ) -> isNaN x || isInfinite x || x < -1 || x > 1)
                        |> List.map Tuple.first
                    )
        , test "the constant slot is one in every fixture" <|
            \() ->
                Expect.equal []
                    (fixtures
                        |> List.concatMap bothSeats
                        |> List.filterMap (nth (Encode.combatSize - 1))
                        |> List.filter ((/=) 1)
                    )
        , test "the hull bits are the last ten slots and read back as the roster indices" <|
            \() ->
                Expect.equal (Encode.kinds Pkunk Umgah)
                    (Encode.vector Bottom (Init.arena Pkunk Umgah (Seed 5))
                        |> List.drop Encode.combatSize
                    )
        , test "one threat record is thirteen slots and three of them are emitted" <|
            \() ->
                Expect.equal 39 (Encode.threatSlots * Encode.threatWidth)
        , test "the encoder rides the same range constants as the cyborg" <|
            \() ->
                Expect.equal ( 4000, 150 ) ( Cyborg.longRange, Cyborg.fastShip )
        ]


bothSeats : Arena -> List (List Float)
bothSeats arena =
    [ Encode.vector Bottom arena, Encode.vector Top arena ]


nth : Int -> List a -> Maybe a
nth index list =
    list |> List.drop index |> List.head


{-| Arenas that have actually been fought in, sampled along the way, so that
projectiles, crew pods, asteroids and the planet all appear. Two Awesome cyborgs
drive both seats, which is the pairing the network is measured against.
-}
fixtures : List Arena
fixtures =
    [ ( Chenjesu, Earthling, 7 )
    , ( Shofixti, Syreen, 1234 )
    , ( Umgah, Chmmr, 99 )
    , ( Ilwrath, Vux, 808 )
    , ( Pkunk, Spathi, 606 )
    ]
        |> List.concatMap (\( bottom, top, seed ) -> samples (Init.arena bottom top (Seed seed)))


samples : Arena -> List Arena
samples start =
    sampleFrom 0 start []


sampleFrom : Int -> Arena -> List Arena -> List Arena
sampleFrom frame arena kept =
    if frame >= 240 then
        List.reverse kept

    else
        let
            ( bottomIn, afterBottom ) =
                Cyborg.pilot AwesomeCyborg Bottom arena

            ( topIn, afterTop ) =
                Cyborg.pilot AwesomeCyborg Top afterBottom

            next =
                Step.tickAuthoritative { bottom = bottomIn, top = topIn } afterTop
        in
        sampleFrom (frame + 1)
            next
            (if modBy 20 frame == 0 then
                arena :: kept

             else
                kept
            )
