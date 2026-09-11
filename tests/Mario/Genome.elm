module Mario.Genome exposing
    ( Genome, Node, Gene, Kind(..)
    , Error(..), errorToString
    , decoder, fromJson, fromParts, encode, encodeNode, encodeGene
    , empty, nodes, genes, nodeCount, linkCount, enabledCount, hiddenCount
    , Compiled, compile, compiledNodeCount, compiledEdgeCount, recurrentEdgeCount, evaluationOrder
    , State, initial, reset, previousValues
    , Step, Activation, activate, activateAll
    , controlsFrom, controlBits, sigmoid, taylorThreshold
    , observationCount, controlCount, memoryCount, inputCount, outputCount
    , firstInputId, firstControlFeedbackId, firstMemoryFeedbackId, biasId
    , firstOutputId, lastOutputId, firstMemoryOutputId, firstHiddenId
    )

{-| Validated MarI/O genome plus the compiled sparse graph interpreter.

This module is the Elm oracle for the Rust trainer. Both implementations must
produce the same outputs for the same genome and the same step sequence, so the
semantics below are contractual, not incidental.


# Slot layout (57 inputs, 13 outputs)

    id  0 .. 42   observations (Neat.Encode.vector: 33 combat sensors that
                  already include the encoder's own constant 1, then our hull
                  as 5 low-bit-first bits, then their hull as 5 low-bit-first
                  bits)
    id 43 .. 47   the five control bits actually applied on the previous tick,
                  in the order left, right, thrust, weapon, special
    id 48 .. 55   the eight explicit memory channels emitted last tick
    id 56         bias, always exactly 1
    id 57 .. 61   control outputs left, right, thrust, weapon, special
    id 62 .. 69   the eight memory outputs
    id >= 70      hidden nodes

The explicit control and memory feedback is supplied by the caller on every
step. It is deliberately separate from the graph's own recurrent activations,
which this module keeps in State.


# Activation semantics

  - Only enabled genes take part in the graph. Disabled genes change nothing,
    neither the sums nor the component structure.

  - Nodes are grouped into strongly connected components of the enabled graph.
    Components are evaluated in a topological order of the condensation, and
    the nodes inside one component in ascending node id order.

  - An edge whose endpoints lie in the same cyclic component (a component of
    more than one node, or a single node carrying a self loop) reads the source
    node's value from the previous decision. Every other edge reads the value
    computed during the current decision. Because cross component edges always
    run from an earlier component to a later one, the source of such an edge is
    always already computed, so the result never depends on which valid
    topological order was chosen.

  - A non input node sums weight * source over its enabled incoming genes in
    ascending innovation order. That summation order is part of the contract
    because floating point addition is not associative.

  - The node value is sigmoid sum, with sigmoid x = 2 / (1 + e ^ (-4.9 * x)) - 1,
    saturating a non finite accumulator to 1, -1 or, for a not a number sum, 0.
    Near zero that written form cancels away the whole answer, so the identical
    function tanh (2.45 x) is evaluated from its Taylor series instead; see the
    sigmoid documentation below, and note that the Rust runtime branches on the
    same threshold. A non input node with no enabled incoming gene therefore
    outputs exactly 0, which is also the rule for isolated nodes.

  - A genome need not declare every fixed slot. An undeclared input feeds
    nothing, because no gene may reference an undeclared node, and an undeclared
    output reads as zero.

  - Every node value is 0 at the start of an episode and after reset.

  - Turning is resolved from the two control outputs: left alone turns left,
    right alone turns right, and both above zero cancel to no turn. That is a
    policy rule for reading the network, not the C engine's key handling, where
    LEFT wins when both keys are held.

Cross language note: Elm reaches the exponential through e ^ x while Rust uses
f64::exp, so above the sigmoid's Taylor threshold the two runtimes can disagree
in the last unit in the last place. Compare those numbers with a small absolute
tolerance rather than bitwise. Control DECISIONS are a different matter and must
match exactly, which is what the threshold exists for: any output whose sign an
ulp of the exponential could flip is computed by the series instead, using only
correctly rounded arithmetic.

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E
import Melee.Input exposing (BattleInput, Turn(..), idle)
import Set exposing (Set)



-- SHAPE


{-| Observation slots, matching Neat.Encode.size (33 combat sensors + 10 hull bits).
-}
observationCount : Int
observationCount =
    43


controlCount : Int
controlCount =
    5


memoryCount : Int
memoryCount =
    8


{-| Observations, previous controls, explicit memory and one bias.
-}
inputCount : Int
inputCount =
    observationCount + controlCount + memoryCount + 1


outputCount : Int
outputCount =
    controlCount + memoryCount


firstInputId : Int
firstInputId =
    0


firstControlFeedbackId : Int
firstControlFeedbackId =
    observationCount


firstMemoryFeedbackId : Int
firstMemoryFeedbackId =
    observationCount + controlCount


biasId : Int
biasId =
    inputCount - 1


firstOutputId : Int
firstOutputId =
    inputCount


firstMemoryOutputId : Int
firstMemoryOutputId =
    firstOutputId + controlCount


lastOutputId : Int
lastOutputId =
    firstOutputId + outputCount - 1


firstHiddenId : Int
firstHiddenId =
    firstOutputId + outputCount



-- GENOME


type Kind
    = Input
    | Output
    | Hidden


type alias Node =
    { id : Int, kind : Kind }


type alias Gene =
    { innovation : Int
    , from : Int
    , to : Int
    , weight : Float
    , enabled : Bool
    }


{-| A genome is opaque so only validated, canonically ordered values exist.
Nodes are held in ascending id order and genes in ascending innovation order,
which is what makes gene storage order irrelevant to behaviour.
-}
type Genome
    = Genome
        { nodes : List Node
        , genes : List Gene
        }


{-| Every input and output declared, with no links yet: the starting point a
minimal seed grows from, and a total value tests can fall back on.
-}
empty : Genome
empty =
    Genome
        { nodes =
            List.map (\id -> { id = id, kind = Input }) (List.range firstInputId (firstOutputId - 1))
                ++ List.map (\id -> { id = id, kind = Output }) (List.range firstOutputId lastOutputId)
        , genes = []
        }


nodes : Genome -> List Node
nodes (Genome g) =
    g.nodes


genes : Genome -> List Gene
genes (Genome g) =
    g.genes


nodeCount : Genome -> Int
nodeCount (Genome g) =
    List.length g.nodes


linkCount : Genome -> Int
linkCount (Genome g) =
    List.length g.genes


enabledCount : Genome -> Int
enabledCount (Genome g) =
    List.length (List.filter .enabled g.genes)


hiddenCount : Genome -> Int
hiddenCount (Genome g) =
    List.length (List.filter (\n -> n.kind == Hidden) g.nodes)



-- ERRORS


type Error
    = BadSchemaVersion Int
    | DuplicateNode Int
    | DuplicateInnovation Int
    | DuplicateLink Int Int
    | NegativeInnovation Int
    | UnknownNodeId Int
    | KindOutOfRange Int
    | InputAsDestination Int
    | NonFiniteWeight Int


errorToString : Error -> String
errorToString error =
    case error of
        BadSchemaVersion v ->
            "unsupported schema_version " ++ String.fromInt v ++ ", expected 1"

        DuplicateNode id ->
            "node " ++ String.fromInt id ++ " is declared more than once"

        DuplicateInnovation innovation ->
            "innovation " ++ String.fromInt innovation ++ " is used by more than one gene"

        DuplicateLink from to ->
            "link " ++ String.fromInt from ++ " -> " ++ String.fromInt to ++ " is declared more than once"

        NegativeInnovation innovation ->
            "innovation " ++ String.fromInt innovation ++ " is negative"

        UnknownNodeId id ->
            "gene refers to undeclared node " ++ String.fromInt id

        KindOutOfRange id ->
            "node " ++ String.fromInt id ++ " has a kind that does not match its id range"

        InputAsDestination id ->
            "input node " ++ String.fromInt id ++ " is used as a link destination"

        NonFiniteWeight innovation ->
            "gene " ++ String.fromInt innovation ++ " has a non finite weight"



-- VALIDATION


{-| The kind a node id must carry. Negative ids belong to no band.
-}
kindForId : Int -> Maybe Kind
kindForId id =
    if id < 0 then
        Nothing

    else if id < firstOutputId then
        Just Input

    else if id <= lastOutputId then
        Just Output

    else
        Just Hidden


{-| Validate and canonicalise. A genome may declare a subset of the fixed slots,
matching the Rust trainer, which treats an undeclared output as zero.
-}
fromParts : List Node -> List Gene -> Result Error Genome
fromParts rawNodes rawGenes =
    let
        sortedNodes =
            List.sortBy .id rawNodes

        sortedGenes =
            List.sortBy .innovation rawGenes

        declared =
            Set.fromList (List.map .id sortedNodes)
    in
    Ok ()
        |> andCheck (\() -> firstDuplicate .id sortedNodes |> Maybe.map DuplicateNode)
        |> andCheck (\() -> firstWhere (\n -> kindForId n.id /= Just n.kind) sortedNodes |> Maybe.map (.id >> KindOutOfRange))
        |> andCheck (\() -> firstDuplicate .innovation sortedGenes |> Maybe.map DuplicateInnovation)
        |> andCheck (\() -> firstWhere (\g -> g.innovation < 0) sortedGenes |> Maybe.map (.innovation >> NegativeInnovation))
        |> andCheck (\() -> firstWhere (\g -> isNaN g.weight || isInfinite g.weight) sortedGenes |> Maybe.map (.innovation >> NonFiniteWeight))
        |> andCheck (\() -> firstWhere (\g -> not (Set.member g.from declared)) sortedGenes |> Maybe.map (.from >> UnknownNodeId))
        |> andCheck (\() -> firstWhere (\g -> not (Set.member g.to declared)) sortedGenes |> Maybe.map (.to >> UnknownNodeId))
        |> andCheck (\() -> firstWhere (\g -> g.to < firstOutputId) sortedGenes |> Maybe.map (.to >> InputAsDestination))
        |> andCheck
            (\() ->
                firstDuplicate (\g -> ( g.from, g.to )) (List.sortBy (\g -> ( g.from, g.to )) sortedGenes)
                    |> Maybe.map (\( from, to ) -> DuplicateLink from to)
            )
        |> Result.map (\() -> Genome { nodes = sortedNodes, genes = sortedGenes })


andCheck : (() -> Maybe Error) -> Result Error () -> Result Error ()
andCheck check acc =
    case acc of
        Err e ->
            Err e

        Ok () ->
            case check () of
                Just e ->
                    Err e

                Nothing ->
                    Ok ()


firstWhere : (a -> Bool) -> List a -> Maybe a
firstWhere predicate items =
    List.head (List.filter predicate items)


{-| First key repeated in a list already sorted by that same key.
-}
firstDuplicate : (a -> comparable) -> List a -> Maybe comparable
firstDuplicate key items =
    case items of
        first :: second :: rest ->
            if key first == key second then
                Just (key first)

            else
                firstDuplicate key (second :: rest)

        _ ->
            Nothing



-- JSON


{-| The outer decoder only fails on a malformed document. A well formed document
that is not a legal genome decodes to Err, so callers can report the defect.
-}
decoder : D.Decoder (Result Error Genome)
decoder =
    D.field "schema_version" D.int
        |> D.andThen
            (\version ->
                if version /= 1 then
                    D.succeed (Err (BadSchemaVersion version))

                else
                    D.map2 fromParts
                        (D.field "nodes" (D.list nodeDecoder))
                        (D.field "genes" (D.list geneDecoder))
            )


nodeDecoder : D.Decoder Node
nodeDecoder =
    D.map2 Node
        (D.field "id" D.int)
        (D.field "kind" D.string |> D.andThen kindFromString)


kindFromString : String -> D.Decoder Kind
kindFromString raw =
    case raw of
        "input" ->
            D.succeed Input

        "output" ->
            D.succeed Output

        "hidden" ->
            D.succeed Hidden

        other ->
            D.fail ("unknown node kind " ++ other)


geneDecoder : D.Decoder Gene
geneDecoder =
    D.map5 Gene
        (D.field "innovation" D.int)
        (D.field "from" D.int)
        (D.field "to" D.int)
        (D.field "weight" D.float)
        (D.field "enabled" D.bool)


{-| Decode from a JSON string, flattening decoder failures and genome defects.
-}
fromJson : String -> Result String Genome
fromJson raw =
    case D.decodeString decoder raw of
        Err err ->
            Err (D.errorToString err)

        Ok (Err defect) ->
            Err (errorToString defect)

        Ok (Ok genome) ->
            Ok genome


encode : Genome -> E.Value
encode (Genome g) =
    E.object
        [ ( "schema_version", E.int 1 )
        , ( "nodes", E.list encodeNode g.nodes )
        , ( "genes", E.list encodeGene g.genes )
        ]


encodeNode : Node -> E.Value
encodeNode node =
    E.object
        [ ( "id", E.int node.id )
        , ( "kind", E.string (kindToString node.kind) )
        ]


kindToString : Kind -> String
kindToString kind =
    case kind of
        Input ->
            "input"

        Output ->
            "output"

        Hidden ->
            "hidden"


encodeGene : Gene -> E.Value
encodeGene gene =
    E.object
        [ ( "innovation", E.int gene.innovation )
        , ( "from", E.int gene.from )
        , ( "to", E.int gene.to )
        , ( "weight", E.float gene.weight )
        , ( "enabled", E.bool gene.enabled )
        ]



-- COMPILED GRAPH


{-| An edge reads either the value decided during this activation or the value
decided during the previous one, fixed at compile time by the component test.
-}
type alias Edge =
    { source : Int
    , weight : Float
    , recurrent : Bool
    }


type alias Unit =
    { slot : Int
    , incoming : List Edge
    }


{-| Immutable compiled network. Episode state lives in State, never in here.
The slot lists are positional and hold Nothing where the genome declared no node
for that fixed identifier, so a partial genome keeps the layout aligned.
-}
type Compiled
    = Compiled
        { size : Int
        , inputSlots : List (Maybe Int)
        , outputSlots : List (Maybe Int)
        , order : List Unit
        }


compiledNodeCount : Compiled -> Int
compiledNodeCount (Compiled c) =
    c.size


compiledEdgeCount : Compiled -> Int
compiledEdgeCount (Compiled c) =
    List.sum (List.map (.incoming >> List.length) c.order)


recurrentEdgeCount : Compiled -> Int
recurrentEdgeCount (Compiled c) =
    List.sum (List.map (.incoming >> List.filter .recurrent >> List.length) c.order)


{-| Slot indices of the non input nodes in the order they are evaluated.
Exposed so tests can assert the ordering contract directly.
-}
evaluationOrder : Compiled -> List Int
evaluationOrder (Compiled c) =
    List.map .slot c.order


compile : Genome -> Compiled
compile (Genome g) =
    let
        ids =
            List.map .id g.nodes

        slotOf =
            List.indexedMap (\slot id -> ( id, slot )) ids |> Dict.fromList

        live =
            List.filter .enabled g.genes

        successors =
            List.foldl
                (\gene acc -> Dict.update gene.from (\prev -> Just (gene.to :: Maybe.withDefault [] prev)) acc)
                Dict.empty
                live
                |> Dict.map (\_ targets -> List.sort targets)

        components =
            stronglyConnected successors ids

        componentOf =
            List.indexedMap (\i members -> List.map (\id -> ( id, i )) members) components
                |> List.concat
                |> Dict.fromList

        selfLooped =
            live
                |> List.filter (\gene -> gene.from == gene.to)
                |> List.map .from
                |> Set.fromList

        cyclic =
            components
                |> List.indexedMap
                    (\i members ->
                        ( i
                        , List.length members > 1 || List.any (\id -> Set.member id selfLooped) members
                        )
                    )
                |> List.filter Tuple.second
                |> List.map Tuple.first
                |> Set.fromList

        -- Folding the reversed list of genes restores ascending innovation
        -- order inside each destination bucket.
        incoming =
            List.foldl
                (\gene acc -> Dict.update gene.to (\prev -> Just (gene :: Maybe.withDefault [] prev)) acc)
                Dict.empty
                (List.reverse live)

        edgesFor id =
            Dict.get id incoming
                |> Maybe.withDefault []
                |> List.map
                    (\gene ->
                        { source = Dict.get gene.from slotOf |> Maybe.withDefault 0
                        , weight = gene.weight
                        , recurrent =
                            case ( Dict.get gene.from componentOf, Dict.get gene.to componentOf ) of
                                ( Just a, Just b ) ->
                                    a == b && Set.member a cyclic

                                _ ->
                                    False
                        }
                    )
    in
    Compiled
        { size = List.length ids
        , inputSlots = List.range firstInputId (firstOutputId - 1) |> List.map (\id -> Dict.get id slotOf)
        , outputSlots = List.range firstOutputId lastOutputId |> List.map (\id -> Dict.get id slotOf)
        , order =
            components
                |> List.concatMap List.sort
                |> List.filter (\id -> id >= firstOutputId)
                |> List.map (\id -> { slot = Dict.get id slotOf |> Maybe.withDefault 0, incoming = edgesFor id })
        }



-- STRONGLY CONNECTED COMPONENTS


type alias Tarjan =
    { counter : Int
    , index : Dict Int Int
    , low : Dict Int Int
    , onStack : Set Int
    , stack : List Int
    , frames : List Frame
    , components : List (List Int)
    }


type alias Frame =
    { node : Int, pending : List Int }


{-| Tarjan's algorithm, iterative so a deep graph cannot exhaust the call stack.
The algorithm closes a component only after every component it points at, so
prepending each closed component leaves the list in topological order of the
condensation. Roots are visited in ascending id order, which makes the whole
result a deterministic function of the genome.
-}
stronglyConnected : Dict Int (List Int) -> List Int -> List (List Int)
stronglyConnected successors roots =
    List.foldl
        (\root state ->
            if Dict.member root state.index then
                state

            else
                drain successors (enter successors root state)
        )
        { counter = 0
        , index = Dict.empty
        , low = Dict.empty
        , onStack = Set.empty
        , stack = []
        , frames = []
        , components = []
        }
        roots
        |> .components


enter : Dict Int (List Int) -> Int -> Tarjan -> Tarjan
enter successors node state =
    { state
        | counter = state.counter + 1
        , index = Dict.insert node state.counter state.index
        , low = Dict.insert node state.counter state.low
        , onStack = Set.insert node state.onStack
        , stack = node :: state.stack
        , frames = { node = node, pending = Dict.get node successors |> Maybe.withDefault [] } :: state.frames
    }


drain : Dict Int (List Int) -> Tarjan -> Tarjan
drain successors state =
    case state.frames of
        [] ->
            state

        frame :: rest ->
            drain successors (advance successors frame rest state)


advance : Dict Int (List Int) -> Frame -> List Frame -> Tarjan -> Tarjan
advance successors frame rest state =
    case frame.pending of
        [] ->
            finish frame rest state

        next :: remaining ->
            let
                walked =
                    { state | frames = { frame | pending = remaining } :: rest }
            in
            if not (Dict.member next walked.index) then
                enter successors next walked

            else if Set.member next walked.onStack then
                { walked | low = Dict.insert frame.node (min (lowOf frame.node walked) (indexOf next walked)) walked.low }

            else
                walked


finish : Frame -> List Frame -> Tarjan -> Tarjan
finish frame rest state =
    let
        closed =
            if lowOf frame.node state == indexOf frame.node state then
                popComponent frame.node { state | frames = rest }

            else
                { state | frames = rest }
    in
    case rest of
        parent :: _ ->
            { closed | low = Dict.insert parent.node (min (lowOf parent.node closed) (lowOf frame.node closed)) closed.low }

        [] ->
            closed


popComponent : Int -> Tarjan -> Tarjan
popComponent root state =
    let
        ( members, remainder ) =
            splitAt root state.stack []
    in
    { state
        | stack = remainder
        , onStack = List.foldl Set.remove state.onStack members
        , components = List.sort members :: state.components
    }


splitAt : Int -> List Int -> List Int -> ( List Int, List Int )
splitAt root stack acc =
    case stack of
        [] ->
            ( acc, [] )

        head :: tail ->
            if head == root then
                ( head :: acc, tail )

            else
                splitAt root tail (head :: acc)


lowOf : Int -> Tarjan -> Int
lowOf node state =
    Dict.get node state.low |> Maybe.withDefault 0


indexOf : Int -> Tarjan -> Int
indexOf node state =
    Dict.get node state.index |> Maybe.withDefault 0



-- EPISODE STATE


{-| The values every node decided on the previous activation. All zero at the
start of an episode, and reset whenever a ship or round starts.
-}
type State
    = State (Array Float)


initial : Compiled -> State
initial (Compiled c) =
    State (Array.repeat c.size 0)


reset : Compiled -> State -> State
reset compiled _ =
    initial compiled


previousValues : State -> List Float
previousValues (State values) =
    Array.toList values



-- ACTIVATION


type alias Step =
    { observations : List Float
    , previous : List Float
    , memory : List Float
    }


type alias Activation =
    { outputs : List Float
    , controls : BattleInput
    , memory : List Float
    , state : State
    }


{-| One decision. Lists shorter than their slot count are padded with zeros and
longer ones are truncated, so a caller can never shift the slot layout.
-}
activate : Compiled -> State -> Step -> Activation
activate (Compiled c) (State previous) step =
    let
        supplied =
            Array.fromList
                (fit observationCount step.observations
                    ++ fit controlCount step.previous
                    ++ fit memoryCount step.memory
                    ++ [ 1 ]
                )

        seeded =
            List.foldl
                (\( position, slot ) values ->
                    case slot of
                        Just index ->
                            Array.set index (Array.get position supplied |> Maybe.withDefault 0) values

                        Nothing ->
                            values
                )
                (Array.repeat c.size 0)
                (List.indexedMap Tuple.pair c.inputSlots)

        settled =
            List.foldl (evaluate previous) seeded c.order

        outputs =
            List.map
                (\slot ->
                    slot
                        |> Maybe.andThen (\index -> Array.get index settled)
                        |> Maybe.withDefault 0
                )
                c.outputSlots
    in
    { outputs = outputs
    , controls = controlsFrom outputs
    , memory = List.drop controlCount outputs
    , state = State settled
    }


evaluate : Array Float -> Unit -> Array Float -> Array Float
evaluate previous unit values =
    Array.set unit.slot (sigmoid (weightedSum previous values unit.incoming 0)) values


{-| Ascending innovation order, accumulated left to right from zero. The Rust
port must use the same order.
-}
weightedSum : Array Float -> Array Float -> List Edge -> Float -> Float
weightedSum previous values edges acc =
    case edges of
        [] ->
            acc

        edge :: rest ->
            let
                source =
                    if edge.recurrent then
                        Array.get edge.source previous |> Maybe.withDefault 0

                    else
                        Array.get edge.source values |> Maybe.withDefault 0
            in
            weightedSum previous values rest (acc + edge.weight * source)


{-| Run a whole step sequence from a fresh state, returning the outputs of each
step. Graph state carries across steps, the explicit feedback does not.
-}
activateAll : Compiled -> List Step -> List (List Float)
activateAll compiled steps =
    List.foldl
        (\step ( state, acc ) ->
            let
                result =
                    activate compiled state step
            in
            ( result.state, result.outputs :: acc )
        )
        ( initial compiled, [] )
        steps
        |> Tuple.second
        |> List.reverse


{-| MarI/O's activation function, evaluated so that two runtimes agree on the
sign of the answer.

`2 / (1 + exp(-4.9 x)) - 1` is algebraically `tanh(2.45 x)`, but near zero the
written form cancels catastrophically: `exp(-4.9 x)` lands a hair under 1,
adding 1 gives a number a hair under 2, and subtracting 1 from the quotient
throws away every bit that carried the answer. What survives is quantised to
multiples of about 1.1e-16, and which multiple it lands on is decided by the
last unit in the last place of `exp`. Elm reaches the exponential through
`e ^ x` and Rust through `f64::exp`, and those disagree by an ulp, so the same
tiny sum came out positive on one runtime and exactly zero on the other, which
is the difference between turning left and not turning at all.

Below the threshold the odd Taylor series of `tanh` is used instead. It is the
same function, not a deadzone or an approximation of convenience: it is far more
accurate than the exponential form there, and it uses only multiplication,
division and subtraction, which IEEE-754 requires to be correctly rounded, so
every runtime produces the identical double. The first dropped term is
`2 u^5 / 15`, about 1.2e-24 at the threshold, which is a thousandth of an
ulp of the answer there.

This is a shared contract with the Rust runtime, which branches on the same
threshold and evaluates the same expression with the same associativity:

    NaN -> 0, +inf -> 1, -inf -> -1
    u = 2.45 * x
    |x| < 1e-5  ->  u - u * u * u / 3
    otherwise   ->  2 / (1 + exp(-4.9 * x)) - 1

Above the threshold the two runtimes' exponentials may still differ by an ulp,
so numbers there compare within a tolerance rather than bitwise. No output that
large can have its sign flipped by an ulp, so control decisions are unaffected.

-}
sigmoid : Float -> Float
sigmoid x =
    if isNaN x then
        0

    else if x == 1 / 0 then
        1

    else if x == -1 / 0 then
        -1

    else
        let
            u =
                2.45 * x
        in
        if abs x < taylorThreshold then
            u - u * u * u / 3

        else
            2 / (1 + e ^ (-4.9 * x)) - 1


{-| Below this magnitude the exponential form has already cancelled the answer
away, so the series is both the accurate and the reproducible choice. Part of
the cross-language contract: the Rust port branches on the same number.
-}
taylorThreshold : Float
taylorThreshold =
    1.0e-5


{-| Read the five control outputs. Left and right both above zero cancel, which
keeps "both pressed" out of the simulation exactly as Melee.Input.Turn requires.
-}
controlsFrom : List Float -> BattleInput
controlsFrom outputs =
    let
        values =
            Array.fromList outputs

        on index =
            (Array.get index values |> Maybe.withDefault 0) > 0
    in
    { idle
        | turn =
            if on 0 && on 1 then
                NoTurn

            else if on 0 then
                TurnLeft

            else if on 1 then
                TurnRight

            else
                NoTurn
        , thrust = on 2
        , weapon = on 3
        , special = on 4
    }


{-| The five bits actually applied, which is what the next step feeds back.
-}
controlBits : BattleInput -> List Float
controlBits input =
    [ bit (input.turn == TurnLeft)
    , bit (input.turn == TurnRight)
    , bit input.thrust
    , bit input.weapon
    , bit input.special
    ]


bit : Bool -> Float
bit flag =
    if flag then
        1

    else
        0


fit : Int -> List Float -> List Float
fit n values =
    List.take n (values ++ List.repeat n 0)
