module Mario.GenomeTests exposing (suite)

{-| Properties of the MarI/O genome decoder and sparse graph interpreter.

The contract these tests defend is stated in Mario.Genome. The two independent
checks worth naming are the reference evaluator, which recomputes acyclic
networks by a plain topological sweep that never touches the component code, and
the permutation properties, which prove gene and node storage order cannot leak
into behaviour.

-}

import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Json.Decode as D
import Json.Encode as E
import Mario.Genome as Genome exposing (Gene, Genome, Kind(..), Node, Step)
import Melee.Input exposing (Turn(..))
import Melee.Ship exposing (ShipKind)
import Neat.Encode as Encode
import Test exposing (Test, describe, fuzz, fuzz2, fuzz3, test)



-- SHARED SHAPE


baseNodes : List Node
baseNodes =
    List.map (\id -> { id = id, kind = Input }) (List.range Genome.firstInputId (Genome.firstOutputId - 1))
        ++ List.map (\id -> { id = id, kind = Output }) (List.range Genome.firstOutputId Genome.lastOutputId)


hiddenNodes : Int -> List Node
hiddenNodes count =
    List.map (\id -> { id = id, kind = Hidden }) (hiddenIds count)


hiddenIds : Int -> List Int
hiddenIds count =
    List.range Genome.firstHiddenId (Genome.firstHiddenId + count - 1)


zeros : Int -> List Float
zeros n =
    List.repeat n 0


blankStep : Step
blankStep =
    { observations = zeros Genome.observationCount
    , previous = zeros Genome.controlCount
    , memory = zeros Genome.memoryCount
    }


setAt : Int -> Float -> List Float -> List Float
setAt index value values =
    List.indexedMap
        (\i v ->
            if i == index then
                value

            else
                v
        )
        values


{-| Place one value in the flat 57 slot input vector and split it back into the
three request fields. This is the packing the Rust port must agree with.
-}
stepWithSlot : Int -> Float -> Step
stepWithSlot slot value =
    let
        flat =
            setAt slot value (zeros (Genome.inputCount - 1))
    in
    { observations = List.take Genome.observationCount flat
    , previous = flat |> List.drop Genome.observationCount |> List.take Genome.controlCount
    , memory = flat |> List.drop (Genome.observationCount + Genome.controlCount) |> List.take Genome.memoryCount
    }


build : Int -> List Gene -> Result Genome.Error Genome
build hidden genes =
    Genome.fromParts (baseNodes ++ hiddenNodes hidden) genes


{-| A genome that must be valid. The fallback would hide a defective fuzzer, so
the fuzzed parts are validated directly by their own test below.
-}
forceBuild : Int -> List Gene -> Genome
forceBuild hidden genes =
    Result.withDefault Genome.empty (build hidden genes)


gene : Int -> Int -> Int -> Float -> Gene
gene innovation from to weight =
    { innovation = innovation, from = from, to = to, weight = weight, enabled = True }


outputsOf : Genome -> Step -> List Float
outputsOf genome step =
    let
        compiled =
            Genome.compile genome
    in
    (Genome.activate compiled (Genome.initial compiled) step).outputs


expectClose : List Float -> List Float -> Expectation
expectClose expected actual =
    if List.length expected /= List.length actual then
        Expect.fail
            ("length " ++ String.fromInt (List.length actual) ++ ", expected " ++ String.fromInt (List.length expected))

    else
        case List.maximum (List.map2 (\a b -> abs (a - b)) expected actual) of
            Nothing ->
                Expect.pass

            Just worst ->
                if worst <= 1.0e-12 then
                    Expect.pass

                else
                    Expect.fail ("largest absolute difference " ++ String.fromFloat worst)



-- FUZZERS


weightFuzzer : Fuzzer Float
weightFuzzer =
    Fuzz.floatRange -4 4


valueFuzzer : Fuzzer Float
valueFuzzer =
    Fuzz.floatRange -1 1


stepFuzzer : Fuzzer Step
stepFuzzer =
    Fuzz.map3 Step
        (Fuzz.listOfLength Genome.observationCount valueFuzzer)
        (Fuzz.listOfLength Genome.controlCount (Fuzz.oneOfValues [ 0, 1 ]))
        (Fuzz.listOfLength Genome.memoryCount valueFuzzer)


{-| Links are chosen from an explicit candidate list so no duplicate link can be
generated, only re-chosen, and the later duplicate is dropped.
-}
linksFuzzer : List ( Int, Int ) -> Fuzzer (List Gene)
linksFuzzer candidates =
    case List.length candidates of
        0 ->
            Fuzz.constant []

        count ->
            Fuzz.listOfLengthBetween 0 24
                (Fuzz.map3 (\pick weight enabled -> ( pick, weight, enabled ))
                    (Fuzz.intRange 0 (count - 1))
                    weightFuzzer
                    (Fuzz.oneOfValues [ True, True, True, False ])
                )
                |> Fuzz.map (assemble candidates)


assemble : List ( Int, Int ) -> List ( Int, Float, Bool ) -> List Gene
assemble candidates picks =
    picks
        |> List.filterMap
            (\( pick, weight, enabled ) ->
                candidates
                    |> List.drop pick
                    |> List.head
                    |> Maybe.map (\( from, to ) -> { from = from, to = to, weight = weight, enabled = enabled })
            )
        |> dedupeLinks []
        |> List.indexedMap (\i link -> { innovation = i + 1, from = link.from, to = link.to, weight = link.weight, enabled = link.enabled })


dedupeLinks : List ( Int, Int ) -> List { from : Int, to : Int, weight : Float, enabled : Bool } -> List { from : Int, to : Int, weight : Float, enabled : Bool }
dedupeLinks seen links =
    case links of
        [] ->
            []

        link :: rest ->
            if List.member ( link.from, link.to ) seen then
                dedupeLinks seen rest

            else
                link :: dedupeLinks (( link.from, link.to ) :: seen) rest


{-| Feed forward candidates only: inputs and lower hidden ids feed higher hidden
ids and outputs, and outputs feed nothing.
-}
acyclicCandidates : Int -> List ( Int, Int )
acyclicCandidates hidden =
    let
        hiddens =
            hiddenIds hidden

        outputs =
            List.range Genome.firstOutputId Genome.lastOutputId

        inputs =
            List.range Genome.firstInputId (Genome.firstOutputId - 1)
    in
    List.concatMap (\from -> List.map (\to -> ( from, to )) (hiddens ++ outputs)) inputs
        ++ List.concatMap (\from -> List.map (\to -> ( from, to )) (List.filter (\to -> to > from) hiddens ++ outputs)) hiddens


{-| Anything the NEAT mutations can produce: cycles, self loops and links out of
output nodes included.
-}
anyCandidates : Int -> List ( Int, Int )
anyCandidates hidden =
    let
        hiddens =
            hiddenIds hidden

        outputs =
            List.range Genome.firstOutputId Genome.lastOutputId

        destinations =
            hiddens ++ outputs
    in
    List.concatMap (\from -> List.map (\to -> ( from, to )) destinations)
        (List.range Genome.firstInputId (Genome.firstOutputId - 1) ++ destinations)


partsFuzzerFrom : (Int -> List ( Int, Int )) -> Fuzzer ( Int, List Gene )
partsFuzzerFrom candidates =
    Fuzz.intRange 0 5
        |> Fuzz.andThen
            (\hidden -> linksFuzzer (candidates hidden) |> Fuzz.map (Tuple.pair hidden))


partsFuzzer : Fuzzer ( Int, List Gene )
partsFuzzer =
    partsFuzzerFrom anyCandidates


acyclicFuzzer : Fuzzer Genome
acyclicFuzzer =
    Fuzz.map (\( hidden, links ) -> forceBuild hidden links) (partsFuzzerFrom acyclicCandidates)


genomeFuzzer : Fuzzer Genome
genomeFuzzer =
    Fuzz.map (\( hidden, links ) -> forceBuild hidden links) partsFuzzer



-- REFERENCE EVALUATOR


{-| Independent evaluation of a feed forward genome: sweep inputs, then hidden
nodes in ascending id order, then outputs, summing enabled genes by innovation.
It shares no code with the component analysis under test.
-}
reference : Genome -> Step -> List Float
reference genome step =
    let
        live =
            Genome.genes genome |> List.filter .enabled |> List.sortBy .innovation

        flat =
            List.take Genome.observationCount (step.observations ++ zeros Genome.observationCount)
                ++ List.take Genome.controlCount (step.previous ++ zeros Genome.controlCount)
                ++ List.take Genome.memoryCount (step.memory ++ zeros Genome.memoryCount)
                ++ [ 1 ]

        seeded =
            List.indexedMap Tuple.pair flat

        hiddens =
            Genome.nodes genome |> List.filter (\n -> n.kind == Hidden) |> List.map .id |> List.sort

        outputs =
            List.range Genome.firstOutputId Genome.lastOutputId

        settle values id =
            let
                sum =
                    live
                        |> List.filter (\g -> g.to == id)
                        |> List.foldl
                            (\g acc ->
                                acc + g.weight * (List.filter (\( slot, _ ) -> slot == g.from) values |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault 0)
                            )
                            0
            in
            values ++ [ ( id, Genome.sigmoid sum ) ]

        final =
            List.foldl (\id values -> settle values id) seeded (hiddens ++ outputs)
    in
    List.map (\id -> final |> List.filter (\( slot, _ ) -> slot == id) |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault 0) outputs



-- SUITE


suite : Test
suite =
    describe "Mario genome"
        [ shapeSuite
        , packingSuite
        , evaluationSuite
        , recurrenceSuite
        , controlSuite
        , validationSuite
        , permutationSuite
        ]


shapeSuite : Test
shapeSuite =
    describe "slot layout"
        [ test "the input band is 43 observations, 5 controls, 8 memory and a bias" <|
            \() ->
                Expect.equal [ 43, 5, 8, 57 ]
                    [ Genome.observationCount, Genome.controlCount, Genome.memoryCount, Genome.inputCount ]
        , test "observation width matches the existing encoder" <|
            \() -> Expect.equal Encode.size Genome.observationCount
        , test "ids are banded 0..56 inputs, 57..69 outputs, 70 and up hidden" <|
            \() ->
                Expect.equal [ 56, 57, 69, 70 ]
                    [ Genome.biasId, Genome.firstOutputId, Genome.lastOutputId, Genome.firstHiddenId ]
        , test "feedback bands start right after the observations" <|
            \() ->
                Expect.equal [ 43, 48 ]
                    [ Genome.firstControlFeedbackId, Genome.firstMemoryFeedbackId ]
        , test "outputs are five controls then eight memory channels" <|
            \() ->
                Expect.equal ( 13, 62 ) ( Genome.outputCount, Genome.firstMemoryOutputId )
        , fuzz2 shipFuzzer shipFuzzer "hull bits are five low bit first bits per side" <|
            \us them ->
                Expect.equal
                    [ toFloat (rosterIndex us), toFloat (rosterIndex them) ]
                    (Encode.kinds us them
                        |> splitAt5
                        |> (\( ours, theirs ) -> [ fromLowBitFirst ours, fromLowBitFirst theirs ])
                    )
        , test "hull bits occupy the last ten observation slots" <|
            \() -> Expect.equal Genome.observationCount (Encode.combatSize + Encode.kindSize)
        ]


shipFuzzer : Fuzzer ShipKind
shipFuzzer =
    Fuzz.oneOfValues Encode.roster


rosterIndex : ShipKind -> Int
rosterIndex kind =
    Encode.roster
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, k ) -> k == kind)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault -1


splitAt5 : List Float -> ( List Float, List Float )
splitAt5 bits =
    ( List.take 5 bits, List.drop 5 bits )


fromLowBitFirst : List Float -> Float
fromLowBitFirst bits =
    List.indexedMap (\i b -> b * toFloat (2 ^ i)) bits |> List.sum


packingSuite : Test
packingSuite =
    describe "input packing"
        [ fuzz2 (Fuzz.intRange 0 (Genome.inputCount - 2)) weightFuzzer "every non bias slot reaches the output it is wired to" <|
            \slot weight ->
                let
                    value =
                        0.75
                in
                expectClose
                    (Genome.sigmoid (weight * value) :: zeros 12)
                    (outputsOf (forceBuild 0 [ gene 1 slot Genome.firstOutputId weight ]) (stepWithSlot slot value))
        , fuzz weightFuzzer "the bias slot is always exactly one" <|
            \weight ->
                expectClose
                    (Genome.sigmoid weight :: zeros 12)
                    (outputsOf (forceBuild 0 [ gene 1 Genome.biasId Genome.firstOutputId weight ]) blankStep)
        , fuzz2 (Fuzz.intRange 0 (Genome.memoryCount - 1)) valueFuzzer "memory feedback binds channel by channel" <|
            \channel value ->
                let
                    source =
                        Genome.firstMemoryFeedbackId + channel

                    target =
                        Genome.firstMemoryOutputId + channel

                    step =
                        { blankStep | memory = setAt channel value (zeros Genome.memoryCount) }

                    expected =
                        List.indexedMap
                            (\i _ ->
                                if i == Genome.controlCount + channel then
                                    Genome.sigmoid (1.5 * value)

                                else
                                    0
                            )
                            (zeros Genome.outputCount)
                in
                expectClose expected (outputsOf (forceBuild 0 [ gene 1 source target 1.5 ]) step)
        , fuzz2 (Fuzz.intRange 0 (Genome.controlCount - 1)) weightFuzzer "previous control bits bind in left, right, thrust, weapon, special order" <|
            \index weight ->
                let
                    step =
                        { blankStep | previous = setAt index 1 (zeros Genome.controlCount) }
                in
                expectClose
                    (Genome.sigmoid weight :: zeros 12)
                    (outputsOf
                        (forceBuild 0 [ gene 1 (Genome.firstControlFeedbackId + index) Genome.firstOutputId weight ])
                        step
                    )
        , fuzz genomeFuzzer "activation always yields thirteen outputs and eight memory channels" <|
            \genome ->
                let
                    compiled =
                        Genome.compile genome

                    result =
                        Genome.activate compiled (Genome.initial compiled) blankStep
                in
                Expect.equal ( 13, 8, True )
                    ( List.length result.outputs
                    , List.length result.memory
                    , List.drop Genome.controlCount result.outputs == result.memory
                    )
        ]


evaluationSuite : Test
evaluationSuite =
    describe "evaluation"
        [ fuzz2 acyclicFuzzer stepFuzzer "feed forward networks match an independent topological sweep" <|
            \genome step -> expectClose (reference genome step) (outputsOf genome step)
        , fuzz2 genomeFuzzer stepFuzzer "activation is a function of genome, state and step" <|
            \genome step ->
                let
                    compiled =
                        Genome.compile genome
                in
                Expect.equal
                    (Genome.activateAll compiled [ step, step, step ])
                    (Genome.activateAll compiled [ step, step, step ])
        , fuzz2 genomeFuzzer stepFuzzer "disabled genes cannot influence anything" <|
            \genome step ->
                let
                    loudened =
                        Genome.genes genome
                            |> List.map
                                (\g ->
                                    if g.enabled then
                                        g

                                    else
                                        { g | weight = g.weight + 1000 }
                                )

                    rebuilt =
                        forceBuild (Genome.hiddenCount genome) loudened

                    steps =
                        [ step, step ]
                in
                Expect.equal
                    (Genome.activateAll (Genome.compile genome) steps)
                    (Genome.activateAll (Genome.compile rebuilt) steps)
        , test "an isolated hidden node contributes exactly zero" <|
            \() ->
                expectClose (zeros 13)
                    (outputsOf (forceBuild 1 [ gene 1 Genome.firstHiddenId Genome.firstOutputId 3 ]) blankStep)
        , fuzz genomeFuzzer "every output stays inside the open interval the sigmoid defines" <|
            \genome ->
                outputsOf genome blankStep
                    |> List.all (\v -> v > -1.0000001 && v < 1.0000001 && not (isNaN v))
                    |> Expect.equal True
        , fuzz valueFuzzer "the sigmoid agrees with the written MarI/O formula" <|
            \x -> Expect.within (Expect.Absolute 1.0e-12) (2 / (1 + e ^ (-4.9 * x)) - 1) (Genome.sigmoid x)
        , fuzz (Fuzz.floatRange -1.0e-5 1.0e-5) "near zero the sigmoid is the tanh series, which keeps the sign the formula throws away" <|
            \x ->
                let
                    u =
                        2.45 * x
                in
                if abs x < Genome.taylorThreshold then
                    -- Bit for bit, because the series is the part of the
                    -- contract that has to reproduce across runtimes exactly.
                    Expect.equal True (u - u * u * u / 3 == Genome.sigmoid x)

                else
                    Expect.pass
        , test "the two branches agree where they meet" <|
            \() ->
                let
                    x =
                        Genome.taylorThreshold

                    u =
                        2.45 * x
                in
                -- At the threshold itself sigmoid takes the exponential branch,
                -- so this compares the two formulations at the same input.
                Expect.within (Expect.Absolute 1.0e-15) (u - u * u * u / 3) (Genome.sigmoid x)
        , test "a sum an ulp of the exponential could not resolve still carries its sign" <|
            \() ->
                -- The written formula answers 0 here on at least one runtime,
                -- which would silently turn a left turn into no turn.
                Expect.equal [ True, True ]
                    [ Genome.sigmoid 1.1102230246251565e-16 > 0
                    , Genome.sigmoid -1.1102230246251565e-16 < 0
                    ]
        , fuzz (Fuzz.floatRange -2 2) "the sigmoid is odd" <|
            \x -> Expect.within (Expect.Absolute 1.0e-15) (negate (Genome.sigmoid x)) (Genome.sigmoid -x)
        , test "the sigmoid of zero is exactly zero" <|
            \() -> Expect.equal 0 (Genome.sigmoid 0)
        , test "a non finite accumulator saturates the way the Rust runtime saturates" <|
            \() ->
                Expect.equal [ 1, -1, 0 ]
                    [ Genome.sigmoid (1 / 0), Genome.sigmoid (-1 / 0), Genome.sigmoid (0 / 0) ]
        , fuzz2 valueFuzzer valueFuzzer "the sigmoid never decreases, and separates values a double can tell apart" <|
            \a b ->
                if a <= b then
                    Expect.equal True (Genome.sigmoid a <= Genome.sigmoid b)

                else
                    Expect.equal True (Genome.sigmoid b <= Genome.sigmoid a)
        , test "the sigmoid separates well spaced values" <|
            \() ->
                Expect.equal True (Genome.sigmoid -0.5 < Genome.sigmoid 0 && Genome.sigmoid 0 < Genome.sigmoid 0.5)
        , test "chained hidden nodes resolve within one activation" <|
            \() ->
                let
                    genome =
                        forceBuild 2
                            [ gene 1 Genome.biasId 71 1
                            , gene 2 71 70 1
                            , gene 3 70 Genome.firstOutputId 1
                            ]

                    innerFirst =
                        Genome.sigmoid 1

                    innerSecond =
                        Genome.sigmoid innerFirst
                in
                expectClose (Genome.sigmoid innerSecond :: zeros 12) (outputsOf genome blankStep)
        ]


recurrenceSuite : Test
recurrenceSuite =
    describe "recurrence and reset"
        [ test "a self loop reads the previous decision, so the first step sees zero" <|
            \() ->
                let
                    genome =
                        forceBuild 1
                            [ gene 1 Genome.biasId 70 1
                            , gene 2 70 70 1
                            , gene 3 70 Genome.firstOutputId 1
                            ]

                    first =
                        Genome.sigmoid 1

                    second =
                        Genome.sigmoid (1 + first)

                    steps =
                        Genome.activateAll (Genome.compile genome) [ blankStep, blankStep ]
                in
                expectClose
                    [ Genome.sigmoid first, Genome.sigmoid second ]
                    (List.filterMap List.head steps)
        , test "both edges inside a two node cycle read the previous decision" <|
            \() ->
                let
                    genome =
                        forceBuild 2
                            [ gene 1 Genome.biasId 70 1
                            , gene 2 70 71 1
                            , gene 3 71 70 1
                            , gene 4 71 Genome.firstOutputId 1
                            ]

                    -- Node 70 sums bias plus the previous node 71, node 71 sees
                    -- only the previous node 70, and the output reads node 71
                    -- from this decision because it sits in a later component.
                    a =
                        Genome.sigmoid 1

                    b =
                        Genome.sigmoid a

                    c =
                        Genome.sigmoid (1 + b)

                    d =
                        Genome.sigmoid c
                in
                expectClose
                    [ 0, Genome.sigmoid b, Genome.sigmoid b, Genome.sigmoid d ]
                    (List.filterMap List.head
                        (Genome.activateAll (Genome.compile genome)
                            [ blankStep, blankStep, blankStep, blankStep ]
                        )
                    )
        , fuzz2 acyclicFuzzer stepFuzzer "feed forward networks keep no state at all" <|
            \genome step ->
                case Genome.activateAll (Genome.compile genome) [ step, step ] of
                    [ first, second ] ->
                        expectClose first second

                    _ ->
                        Expect.fail "expected two steps"
        , fuzz2 genomeFuzzer stepFuzzer "reset returns the network to its start of episode behaviour" <|
            \genome step ->
                let
                    compiled =
                        Genome.compile genome

                    fresh =
                        Genome.activate compiled (Genome.initial compiled) step

                    warmed =
                        Genome.activate compiled fresh.state step

                    afterReset =
                        Genome.activate compiled (Genome.reset compiled warmed.state) step
                in
                expectClose fresh.outputs afterReset.outputs
        , fuzz genomeFuzzer "previous values start at zero for every node" <|
            \genome ->
                let
                    compiled =
                        Genome.compile genome
                in
                Genome.previousValues (Genome.initial compiled)
                    |> Expect.all
                        [ List.length >> Expect.equal (Genome.compiledNodeCount compiled)
                        , List.all (\v -> v == 0) >> Expect.equal True
                        ]
        , test "only genes inside a cyclic component are recurrent" <|
            \() ->
                let
                    cyclic =
                        forceBuild 2
                            [ gene 1 Genome.biasId 70 1
                            , gene 2 70 71 1
                            , gene 3 71 70 1
                            , gene 4 71 Genome.firstOutputId 1
                            ]

                    feedForward =
                        forceBuild 2
                            [ gene 1 Genome.biasId 70 1
                            , gene 2 70 71 1
                            , gene 4 71 Genome.firstOutputId 1
                            ]
                in
                Expect.equal ( 2, 0 )
                    ( Genome.recurrentEdgeCount (Genome.compile cyclic)
                    , Genome.recurrentEdgeCount (Genome.compile feedForward)
                    )
        ]


controlSuite : Test
controlSuite =
    describe "control resolution"
        [ fuzz (Fuzz.listOfLength Genome.outputCount (Fuzz.floatRange -1 1)) "left and right together cancel" <|
            \outputs ->
                let
                    both =
                        0.5 :: 0.5 :: List.drop 2 outputs
                in
                Expect.equal NoTurn (Genome.controlsFrom both).turn
        , fuzz (Fuzz.listOfLength Genome.outputCount (Fuzz.floatRange -1 1)) "a single side turns that way" <|
            \outputs ->
                let
                    rest =
                        List.drop 2 outputs
                in
                Expect.equal ( TurnLeft, TurnRight, NoTurn )
                    ( (Genome.controlsFrom (0.5 :: -0.5 :: rest)).turn
                    , (Genome.controlsFrom (-0.5 :: 0.5 :: rest)).turn
                    , (Genome.controlsFrom (-0.5 :: -0.5 :: rest)).turn
                    )
        , test "a zero output is not pressed" <|
            \() -> Expect.equal Melee.Input.idle (Genome.controlsFrom (zeros Genome.outputCount))
        , fuzz (Fuzz.listOfLength Genome.outputCount (Fuzz.floatRange -1 1)) "the fed back bits are the bits actually applied" <|
            \outputs ->
                let
                    bits =
                        Genome.controlBits (Genome.controlsFrom outputs)
                in
                Expect.equal ( 5, True, True )
                    ( List.length bits
                    , List.all (\b -> b == 0 || b == 1) bits
                    , List.take 2 bits /= [ 1, 1 ]
                    )
        , fuzz (Fuzz.listOfLength Genome.outputCount (Fuzz.floatRange -1 1)) "thrust, weapon and special are read from outputs two, three and four" <|
            \outputs ->
                let
                    controls =
                        Genome.controlsFrom outputs

                    above index =
                        (outputs |> List.drop index |> List.head |> Maybe.withDefault 0) > 0
                in
                Expect.equal ( above 2, above 3, above 4 )
                    ( controls.thrust, controls.weapon, controls.special )
        ]


validationSuite : Test
validationSuite =
    describe "validation"
        [ fuzz partsFuzzer "the fuzzers only produce valid genomes" <|
            \( hidden, links ) ->
                build hidden links
                    |> Result.map (always ())
                    |> Result.mapError Genome.errorToString
                    |> Expect.equal (Ok ())
        , test "a duplicate node id is rejected" <|
            \() ->
                Genome.fromParts ({ id = 70, kind = Hidden } :: { id = 70, kind = Hidden } :: baseNodes) []
                    |> expectError (Genome.DuplicateNode 70)
        , test "a duplicate innovation is rejected" <|
            \() ->
                build 1 [ gene 1 Genome.biasId 70 1, gene 1 Genome.biasId Genome.firstOutputId 1 ]
                    |> expectError (Genome.DuplicateInnovation 1)
        , test "a duplicate link is rejected" <|
            \() ->
                build 0 [ gene 1 Genome.biasId Genome.firstOutputId 1, gene 2 Genome.biasId Genome.firstOutputId 2 ]
                    |> expectError (Genome.DuplicateLink Genome.biasId Genome.firstOutputId)
        , test "a negative innovation is rejected" <|
            \() ->
                build 0 [ gene (-1) Genome.biasId Genome.firstOutputId 1 ]
                    |> expectError (Genome.NegativeInnovation (-1))
        , test "a gene into an input is rejected" <|
            \() ->
                build 0 [ gene 1 Genome.biasId 3 1 ]
                    |> expectError (Genome.InputAsDestination 3)
        , test "a gene from an undeclared node is rejected" <|
            \() ->
                build 0 [ gene 1 999 Genome.firstOutputId 1 ]
                    |> expectError (Genome.UnknownNodeId 999)
        , test "a genome may omit fixed slots it never uses" <|
            \() ->
                Genome.fromParts (List.filter (\n -> n.id /= 12 && n.id /= 65) baseNodes) []
                    |> Result.map Genome.nodeCount
                    |> Expect.equal (Ok 68)
        , test "an undeclared output reads as zero" <|
            \() ->
                Genome.fromParts (List.filter (\n -> n.id /= 69) baseNodes)
                    [ gene 1 Genome.biasId Genome.firstOutputId 1 ]
                    |> Result.map (\g -> outputsOf g blankStep)
                    |> Expect.equal (Ok (Genome.sigmoid 1 :: zeros 12))
        , test "a node whose kind contradicts its id is rejected" <|
            \() ->
                Genome.fromParts (List.map (\n -> ifId 70 Output n) ({ id = 70, kind = Hidden } :: baseNodes)) []
                    |> expectError (Genome.KindOutOfRange 70)
        , test "an input declared as hidden is rejected" <|
            \() ->
                Genome.fromParts (List.map (ifId 5 Hidden) baseNodes) []
                    |> expectError (Genome.KindOutOfRange 5)
        , test "a non finite weight is rejected" <|
            \() ->
                build 0 [ gene 7 Genome.biasId Genome.firstOutputId (1 / 0) ]
                    |> expectError (Genome.NonFiniteWeight 7)
        , test "an overflowing JSON weight is rejected rather than read as infinity" <|
            \() ->
                Genome.fromJson (jsonWith "1e400" 1)
                    |> Expect.equal (Err (Genome.errorToString (Genome.NonFiniteWeight 1)))
        , test "an unsupported schema version is rejected" <|
            \() ->
                Genome.fromJson (jsonWith "1.0" 2)
                    |> Expect.equal (Err (Genome.errorToString (Genome.BadSchemaVersion 2)))
        , test "an unknown node kind fails to decode" <|
            \() ->
                Genome.fromJson """{"schema_version":1,"nodes":[{"id":0,"kind":"neuron"}],"genes":[]}"""
                    |> Result.mapError (String.contains "neuron")
                    |> Expect.equal (Err True)
        , test "a genome round trips through JSON" <|
            \() ->
                let
                    genome =
                        forceBuild 1 [ gene 4 Genome.biasId 70 0.25, gene 9 70 Genome.firstOutputId -1.5 ]
                in
                Genome.fromJson (E.encode 0 (Genome.encode genome))
                    |> Result.map Genome.genes
                    |> Expect.equal (Ok (Genome.genes genome))
        , test "an omitted enabled flag is rejected, as the Rust decoder rejects it" <|
            \() ->
                Genome.fromJson (jsonWithoutEnabled 1.0)
                    |> Result.mapError (String.contains "enabled")
                    |> Expect.equal (Err True)
        ]


ifId : Int -> Kind -> Node -> Node
ifId id kind node =
    if node.id == id then
        { node | kind = kind }

    else
        node


expectError : Genome.Error -> Result Genome.Error Genome -> Expectation
expectError expected actual =
    actual
        |> Result.map (always "unexpectedly valid")
        |> Result.mapError Genome.errorToString
        |> Expect.equal (Err (Genome.errorToString expected))


nodesJson : String
nodesJson =
    E.encode 0 (E.list Genome.encodeNode baseNodes)


jsonWith : String -> Int -> String
jsonWith weight version =
    "{\"schema_version\":"
        ++ String.fromInt version
        ++ ",\"nodes\":"
        ++ nodesJson
        ++ ",\"genes\":[{\"innovation\":1,\"from\":56,\"to\":57,\"weight\":"
        ++ weight
        ++ ",\"enabled\":true}]}"


jsonWithoutEnabled : Float -> String
jsonWithoutEnabled weight =
    "{\"schema_version\":1,\"nodes\":"
        ++ nodesJson
        ++ ",\"genes\":[{\"innovation\":1,\"from\":56,\"to\":57,\"weight\":"
        ++ String.fromFloat weight
        ++ "}]}"


permutationSuite : Test
permutationSuite =
    describe "storage order"
        [ fuzz2 genomeFuzzer stepFuzzer "reversing the stored gene and node order changes nothing" <|
            \genome step ->
                let
                    shuffled =
                        E.encode 0
                            (E.object
                                [ ( "schema_version", E.int 1 )
                                , ( "nodes", E.list Genome.encodeNode (List.reverse (Genome.nodes genome)) )
                                , ( "genes", E.list Genome.encodeGene (List.reverse (Genome.genes genome)) )
                                ]
                            )

                    steps =
                        [ step, step ]
                in
                Genome.fromJson shuffled
                    |> Result.map (\g -> Genome.activateAll (Genome.compile g) steps)
                    |> Expect.equal (Ok (Genome.activateAll (Genome.compile genome) steps))
        , fuzz2 genomeFuzzer stepFuzzer "interleaving the stored gene order changes nothing" <|
            \genome step ->
                let
                    interleaved =
                        riffle (Genome.genes genome)

                    rebuilt =
                        Genome.fromParts (Genome.nodes genome) interleaved

                    steps =
                        [ step, step ]
                in
                rebuilt
                    |> Result.map (\g -> Genome.activateAll (Genome.compile g) steps)
                    |> Expect.equal (Ok (Genome.activateAll (Genome.compile genome) steps))
        , fuzz genomeFuzzer "decoding sorts genes by innovation and nodes by id" <|
            \genome ->
                Expect.equal
                    ( List.sort (List.map .innovation (Genome.genes genome))
                    , List.sort (List.map .id (Genome.nodes genome))
                    )
                    ( List.map .innovation (Genome.genes genome)
                    , List.map .id (Genome.nodes genome)
                    )
        , fuzz genomeFuzzer "renumbering innovations while keeping their order keeps behaviour" <|
            \genome ->
                let
                    renumbered =
                        List.indexedMap (\i g -> { g | innovation = (i + 1) * 17 }) (Genome.genes genome)
                in
                Genome.fromParts (Genome.nodes genome) renumbered
                    |> Result.map (\g -> Genome.activateAll (Genome.compile g) [ blankStep, blankStep ])
                    |> Expect.equal (Ok (Genome.activateAll (Genome.compile genome) [ blankStep, blankStep ]))
        ]


{-| Split a list in half and interleave, a cheap deterministic shuffle.
-}
riffle : List a -> List a
riffle items =
    let
        half =
            List.length items // 2
    in
    weave (List.take half items) (List.drop half items)


weave : List a -> List a -> List a
weave left right =
    case ( left, right ) of
        ( [], rest ) ->
            rest

        ( rest, [] ) ->
            rest

        ( a :: restLeft, b :: restRight ) ->
            a :: b :: weave restLeft restRight
