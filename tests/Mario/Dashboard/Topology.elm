module Mario.Dashboard.Topology exposing
    ( Config
    , Placed
    , Summary
    , groupColor
    , hiddenDepths
    , layout
    , orderedIds
    , summarize
    , view
    )

{-| Champion network topology.

The point of this view is that the 117 inputs are not an anonymous
column. They are laid out in their six contract groups, each band is
labelled, and every node carries its own name, so our ship's five
identity bits, the opponent's five identity bits and the eight memory
channels are all individually identifiable. Memory is drawn in the same
violet at both ends of the graph and controls in the same amber, which
makes the feedback loop visible: what leaves on the right in violet
comes back on the left in violet.

Hidden nodes are placed by longest acyclic path depth from the inputs.
A connection that runs backwards, into an equal or earlier column, is a
recurrent edge; it is drawn with a distinct bowed curve and counted
separately, because recurrence is the part of an evolved graph that is
easiest to miss and hardest to reason about.

No activations are replayed here. This is the stored genome: nodes,
connections, weights and enabled flags, exactly as served.

-}

import Dict exposing (Dict)
import Html exposing (Html, div, span, text)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Mario.Dashboard.Api as Api
import Mario.Dashboard.Format as Format
import Mario.Dashboard.Slots as Slots exposing (Group(..))
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events



-- GEOMETRY


userWidth : Float
userWidth =
    980


inputX : Float
inputX =
    154


outputX : Float
outputX =
    userWidth - 150


topMargin : Float
topMargin =
    30


bottomMargin : Float
bottomMargin =
    18


rowStep : Float
rowStep =
    11


{-| Hidden nodes need less room than a labelled input row, but they still
need enough that two adjacent circles do not touch.
-}
hiddenRowStep : Float
hiddenRowStep =
    11


{-| Above this many nodes in one column, per-node id labels stop being
readable and become texture. The nodes stay; only the numbering goes,
and the readout still names whichever node is selected.
-}
denseColumn : Int
denseColumn =
    26


bandGap : Float
bandGap =
    10


inputBands : List Group
inputBands =
    [ Sensors, OurShipBits, TheirShipBits, PriorControls, PriorMemory, Bias ]


outputBands : List Group
outputBands =
    [ ControlOutputs, MemoryOutputs ]


type alias Placed =
    { id : Int
    , x : Float
    , y : Float
    , group : Group
    , declared : Bool
    }


type alias Layout =
    { height : Float
    , placed : List Placed
    , index : Dict Int Placed
    , bandMarks : List ( Group, Float, Float )
    , crowded : Bool
    }


{-| Every node id the genome mentions, whether declared in `nodes` or
only referenced by a connection. A referenced-but-undeclared id is drawn
hollow rather than dropped, because silently hiding it would make an
invalid genome look fine.
-}
orderedIds : Api.Genome -> List Int
orderedIds genome =
    let
        declared =
            List.map .id genome.nodes

        referenced =
            List.concatMap (\g -> [ g.from, g.to ]) genome.genes
    in
    (declared ++ referenced)
        |> List.foldl (\i acc -> Dict.insert i () acc) Dict.empty
        |> Dict.keys


{-| Shortest path depth from the input layer, by bounded relaxation.

Shortest rather than longest is deliberate. An evolved graph is not a
DAG: recurrent links are the whole point of the memory channels, and a
longest-path relaxation run over a cycle simply pumps every node in that
cycle up to the cap, which would push a genuinely shallow node to the
far right for no reason. Taking the minimum is immune to that, because
going around a cycle can only ever lengthen a path.

Relaxation is capped at `maxDepth` passes, which is exactly enough: any
node whose true distance is at or under the cap has settled by then, and
anything further is clamped to the cap anyway. A hidden node with no
path from an input keeps the cap and lands in the last hidden column,
where its lack of incoming edges is plain to see.

-}
hiddenDepths : Api.Genome -> Dict Int Int
hiddenDepths genome =
    let
        ids =
            orderedIds genome

        hidden =
            List.filter (\i -> Slots.groupOf i == Hidden) ids

        edges =
            genome.genes
                |> List.filter .enabled
                |> List.filter (\g -> Slots.groupOf g.to == Hidden)

        initial =
            List.foldl (\i acc -> Dict.insert i maxDepth acc) Dict.empty hidden

        depthOf table id =
            if Slots.groupOf id == Hidden then
                Dict.get id table |> Maybe.withDefault maxDepth

            else
                0

        relax table =
            List.foldl
                (\g acc ->
                    let
                        candidate =
                            min maxDepth (depthOf acc g.from + 1)

                        current =
                            Dict.get g.to acc |> Maybe.withDefault maxDepth
                    in
                    if candidate < current then
                        Dict.insert g.to candidate acc

                    else
                        acc
                )
                table
                edges
    in
    List.foldl (\_ table -> relax table) initial (List.range 1 maxDepth)


maxDepth : Int
maxDepth =
    8


layout : Api.Genome -> Layout
layout genome =
    let
        ids =
            orderedIds genome

        declaredSet =
            List.foldl (\n acc -> Dict.insert n.id () acc) Dict.empty genome.nodes

        inputIds =
            List.range 0 (Slots.inputCount - 1)

        outputIds =
            List.range Slots.outputFirst (Slots.hiddenFirst - 1)

        hidden =
            ids |> List.filter (\i -> Slots.groupOf i == Hidden) |> List.sort

        depths =
            hiddenDepths genome

        -- Inputs: one row each, with a gap between contract groups.
        inputRows =
            List.foldl
                (\id ( y, acc ) ->
                    let
                        gap =
                            case acc of
                                ( prevId, _ ) :: _ ->
                                    if Slots.groupOf prevId /= Slots.groupOf id then
                                        bandGap

                                    else
                                        0

                                [] ->
                                    0

                        thisY =
                            y + gap
                    in
                    ( thisY + rowStep, ( id, thisY ) :: acc )
                )
                ( topMargin, [] )
                inputIds
                |> Tuple.second
                |> List.reverse

        inputColumnHeight =
            inputRows
                |> List.map Tuple.second
                |> List.maximum
                |> Maybe.withDefault (topMargin + rowStep)

        -- An evolved champion can carry far more hidden nodes than the 57
        -- fixed inputs. Sizing the canvas to the inputs alone would stack
        -- a hundred hidden nodes on top of each other into an unreadable
        -- smear, so the tallest hidden column sets the floor instead.
        widestHiddenColumn =
            hidden
                |> List.map (\id -> Dict.get id depths |> Maybe.withDefault maxDepth)
                |> List.foldl (\d acc -> Dict.update d (\m -> Just (1 + Maybe.withDefault 0 m)) acc) Dict.empty
                |> Dict.values
                |> List.maximum
                |> Maybe.withDefault 0

        columnHeight =
            max inputColumnHeight (topMargin + (toFloat widestHiddenColumn * hiddenRowStep))

        height =
            columnHeight + rowStep + bottomMargin

        span_ =
            columnHeight - topMargin

        -- Outputs: evenly spread over the same vertical extent, with a
        -- gap separating the five controls from the eight memory channels.
        outputRows =
            let
                n =
                    List.length outputIds

                step =
                    if n <= 1 then
                        0

                    else
                        span_ / toFloat (n - 1 + 1)
            in
            List.indexedMap
                (\i id ->
                    let
                        extra =
                            if Slots.groupOf id == MemoryOutputs then
                                step

                            else
                                0
                    in
                    ( id, topMargin + (step * toFloat i) + extra )
                )
                outputIds

        hiddenColumns =
            hidden
                |> List.map (\id -> ( Dict.get id depths |> Maybe.withDefault maxDepth, id ))
                |> List.foldl (\( d, id ) acc -> Dict.update d (\m -> Just (id :: Maybe.withDefault [] m)) acc) Dict.empty
                |> Dict.map (\_ v -> List.reverse v)

        usedDepths =
            Dict.keys hiddenColumns

        columnX depth =
            let
                lanes =
                    max 1 (List.length usedDepths)

                position =
                    usedDepths
                        |> List.indexedMap Tuple.pair
                        |> List.filter (\( _, d ) -> d == depth)
                        |> List.head
                        |> Maybe.map Tuple.first
                        |> Maybe.withDefault 0

                usable =
                    outputX - inputX - 120
            in
            inputX + 60 + (usable * (toFloat position + 0.5) / toFloat lanes)

        hiddenRows =
            hiddenColumns
                |> Dict.toList
                |> List.concatMap
                    (\( depth, members ) ->
                        let
                            n =
                                List.length members

                            step =
                                if n <= 1 then
                                    0

                                else
                                    span_ / toFloat (n - 1)

                            startY =
                                if n <= 1 then
                                    topMargin + span_ / 2

                                else
                                    topMargin
                        in
                        List.indexedMap
                            (\i id -> ( id, columnX depth, startY + step * toFloat i ))
                            members
                    )

        place x ( id, y ) =
            { id = id
            , x = x
            , y = y
            , group = Slots.groupOf id
            , declared = Dict.member id declaredSet
            }

        crowded =
            widestHiddenColumn > denseColumn

        placed =
            List.map (place inputX) inputRows
                ++ List.map (place outputX) outputRows
                ++ List.map (\( id, x, y ) -> place x ( id, y )) hiddenRows

        bandMarks =
            (inputBands ++ outputBands)
                |> List.filterMap
                    (\group ->
                        let
                            ys =
                                placed |> List.filter (\p -> p.group == group) |> List.map .y
                        in
                        case ( List.minimum ys, List.maximum ys ) of
                            ( Just lo, Just hi ) ->
                                Just ( group, lo, hi )

                            _ ->
                                Nothing
                    )
    in
    { height = height
    , placed = placed
    , index = List.foldl (\p acc -> Dict.insert p.id p acc) Dict.empty placed
    , bandMarks = bandMarks
    , crowded = crowded
    }



-- SUMMARY


type alias Summary =
    { nodes : Int
    , hidden : Int
    , enabled : Int
    , disabled : Int
    , recurrent : Int
    , undeclared : Int
    , maxWeight : Float
    }


summarize : Api.Genome -> Summary
summarize genome =
    let
        lay =
            layout genome

        xOf id =
            Dict.get id lay.index |> Maybe.map .x |> Maybe.withDefault 0

        enabled =
            List.filter .enabled genome.genes

        declaredSet =
            List.foldl (\n acc -> Dict.insert n.id () acc) Dict.empty genome.nodes

        referenced =
            orderedIds genome
    in
    { nodes = List.length referenced
    , hidden = referenced |> List.filter (\i -> Slots.groupOf i == Hidden) |> List.length
    , enabled = List.length enabled
    , disabled = List.length genome.genes - List.length enabled
    , recurrent = enabled |> List.filter (\g -> xOf g.to <= xOf g.from) |> List.length
    , undeclared = referenced |> List.filter (\i -> not (Dict.member i declaredSet)) |> List.length
    , maxWeight =
        genome.genes
            |> List.map (\g -> abs g.weight)
            |> List.maximum
            |> Maybe.withDefault 1
            |> max 0.001
    }



-- COLOUR


groupColor : Group -> String
groupColor group =
    case group of
        Sensors ->
            "#7f95cc"

        OurShipBits ->
            "#4fd6e0"

        TheirShipBits ->
            "#f0715a"

        PriorControls ->
            "#ffb23f"

        PriorMemory ->
            "#a99bf5"

        Bias ->
            "#f4ead6"

        ControlOutputs ->
            "#ffb23f"

        MemoryOutputs ->
            "#a99bf5"

        Hidden ->
            "#9db2d8"



-- VIEW


type alias Config msg =
    { selected : Maybe Int
    , onSelect : Int -> msg
    , onClear : msg
    , describedBy : String
    }


view : Config msg -> Api.Genome -> Html msg
view config genome =
    let
        lay =
            layout genome

        summary =
            summarize genome

        ids =
            lay.placed |> List.map .id |> List.sort
    in
    div []
        [ div [ Attr.class "topo-wrap" ]
            [ Svg.svg
                [ SA.class "topo-svg"
                , SA.viewBox ("0 0 " ++ String.fromFloat userWidth ++ " " ++ String.fromFloat lay.height)
                , Attr.attribute "role" "group"
                , Attr.attribute "tabindex" "0"
                , Attr.attribute "aria-label"
                    ("Champion network graph with "
                        ++ String.fromInt summary.nodes
                        ++ " nodes and "
                        ++ String.fromInt summary.enabled
                        ++ " enabled connections. Focus this graph and use the arrow keys to step through nodes."
                    )
                , Attr.attribute "aria-describedby" config.describedBy
                , Html.Events.preventDefaultOn "keydown" (arrowDecoder config ids)
                ]
                (defs
                    :: viewBands lay
                    ++ viewEdges config lay summary genome
                    ++ List.concatMap (viewNode config lay.crowded) lay.placed
                )
            ]
        , viewReadout config genome summary
        , viewKey
        ]


{-| An arrowhead for recurrent edges. Signal flows left to right through
the graph, so a link that travels right to left is the exception, and an
explicit head at its destination says which way it is actually going.
-}
defs : Svg msg
defs =
    Svg.defs []
        [ Svg.marker
            [ SA.id "mario-recurrent-arrow"
            , SA.viewBox "0 0 8 8"
            , SA.refX "7"
            , SA.refY "4"
            , SA.markerWidth "5"
            , SA.markerHeight "5"
            , SA.orient "auto"
            ]
            [ Svg.path [ SA.d "M 0 0 L 8 4 L 0 8 z", SA.fill "#f4ead6" ] [] ]
        ]


arrowDecoder : Config msg -> List Int -> Decode.Decoder ( msg, Bool )
arrowDecoder config ids =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                let
                    current =
                        config.selected
                            |> Maybe.andThen (\s -> indexOf s ids)
                            |> Maybe.withDefault -1

                    pick i =
                        ids
                            |> List.drop (max 0 (min (List.length ids - 1) i))
                            |> List.head

                    move delta =
                        case pick (current + delta) of
                            Just id ->
                                Decode.succeed ( config.onSelect id, True )

                            Nothing ->
                                Decode.fail "edge"
                in
                case key of
                    "ArrowDown" ->
                        move 1

                    "ArrowRight" ->
                        move 1

                    "ArrowUp" ->
                        move -1

                    "ArrowLeft" ->
                        move -1

                    "Escape" ->
                        Decode.succeed ( config.onClear, False )

                    _ ->
                        Decode.fail "ignored"
            )


indexOf : Int -> List Int -> Maybe Int
indexOf target list =
    list
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, v ) -> v == target)
        |> List.head
        |> Maybe.map Tuple.first


viewBands : Layout -> List (Svg msg)
viewBands lay =
    List.concatMap
        (\( group, lo, hi ) ->
            let
                caption =
                    Slots.groupLabel group

                fits =
                    (hi - lo) > (toFloat (String.length caption) * 5.0)

                isOutput =
                    group == ControlOutputs || group == MemoryOutputs

                x =
                    if isOutput then
                        outputX + 112

                    else
                        10
            in
            [ Svg.line
                [ SA.x1 (String.fromFloat x)
                , SA.x2 (String.fromFloat x)
                , SA.y1 (String.fromFloat (lo - 4))
                , SA.y2 (String.fromFloat (hi + 4))
                , SA.stroke (groupColor group)
                , SA.strokeWidth "2"
                , SA.strokeOpacity "0.5"
                ]
                []
            ]
                ++ (if fits then
                        [ Svg.text_
                            [ SA.x (String.fromFloat (x + 5))
                            , SA.y (String.fromFloat ((lo + hi) / 2))
                            , SA.fontSize "9"
                            , SA.fill (groupColor group)
                            , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
                            , SA.transform
                                ("rotate(-90 "
                                    ++ String.fromFloat (x + 5)
                                    ++ " "
                                    ++ String.fromFloat ((lo + hi) / 2)
                                    ++ ")"
                                )
                            , SA.textAnchor "middle"
                            ]
                            [ Svg.text caption ]
                        ]

                    else
                        []
                   )
        )
        lay.bandMarks


viewEdges : Config msg -> Layout -> Summary -> Api.Genome -> List (Svg msg)
viewEdges config lay summary genome =
    genome.genes
        |> List.filterMap
            (\gene ->
                Maybe.map2 (\a b -> ( gene, a, b ))
                    (Dict.get gene.from lay.index)
                    (Dict.get gene.to lay.index)
            )
        |> List.map
            (\( gene, from, to ) ->
                let
                    touched =
                        case config.selected of
                            Nothing ->
                                True

                            Just id ->
                                gene.from == id || gene.to == id

                    recurrent =
                        to.x <= from.x

                    strength =
                        abs gene.weight / summary.maxWeight

                    baseOpacity =
                        0.12 + 0.55 * strength

                    opacity =
                        case config.selected of
                            Nothing ->
                                baseOpacity

                            Just _ ->
                                if touched then
                                    min 1 (baseOpacity + 0.35)

                                else
                                    0.05

                    color =
                        if not gene.enabled then
                            "#56618a"

                        else if gene.weight >= 0 then
                            "#4fd6e0"

                        else
                            "#f0715a"

                    dx =
                        (to.x - from.x) * 0.45

                    path =
                        if recurrent then
                            -- Bow the curve well clear of the forward
                            -- traffic so recurrence is visible at a glance.
                            "M "
                                ++ pt from.x from.y
                                ++ " C "
                                ++ pt (from.x + 70) (from.y - 34)
                                ++ ", "
                                ++ pt (to.x - 70) (to.y - 34)
                                ++ ", "
                                ++ pt to.x to.y

                        else
                            "M "
                                ++ pt from.x from.y
                                ++ " C "
                                ++ pt (from.x + dx) from.y
                                ++ ", "
                                ++ pt (to.x - dx) to.y
                                ++ ", "
                                ++ pt to.x to.y
                in
                Svg.path
                    [ SA.d path
                    , SA.fill "none"
                    , SA.stroke color
                    , SA.strokeWidth (String.fromFloat (0.5 + 1.8 * strength))
                    , SA.strokeOpacity (String.fromFloat opacity)
                    , SA.strokeDasharray
                        (if gene.enabled then
                            "none"

                         else
                            "3 3"
                        )
                    , SA.markerEnd
                        (if recurrent then
                            "url(#mario-recurrent-arrow)"

                         else
                            "none"
                        )
                    ]
                    []
            )


pt : Float -> Float -> String
pt x y =
    String.fromFloat x ++ " " ++ String.fromFloat y


viewNode : Config msg -> Bool -> Placed -> List (Svg msg)
viewNode config crowded placed =
    let
        info =
            Slots.slot placed.id

        isSelected =
            config.selected == Just placed.id

        color =
            groupColor placed.group

        radius =
            case placed.group of
                Hidden ->
                    4

                ControlOutputs ->
                    4.5

                MemoryOutputs ->
                    4.5

                _ ->
                    3.2

        isOutput =
            placed.group == ControlOutputs || placed.group == MemoryOutputs

        labelNode =
            if placed.group == Hidden then
                if crowded then
                    []

                else
                    [ Svg.text_
                    [ SA.x (String.fromFloat placed.x)
                    , SA.y (String.fromFloat (placed.y - 7))
                    , SA.fontSize "7.5"
                    , SA.fill "#7483a6"
                    , SA.textAnchor "middle"
                    , SA.fontFamily "ui-monospace, Menlo, Consolas, monospace"
                    ]
                    [ Svg.text (String.fromInt placed.id) ]
                    ]

            else
                [ Svg.text_
                    [ SA.x
                        (String.fromFloat
                            (if isOutput then
                                placed.x + 9

                             else
                                placed.x - 9
                            )
                        )
                    , SA.y (String.fromFloat (placed.y + 3))
                    , SA.fontSize "8.5"
                    , SA.fill
                        (if isSelected then
                            "#f4ead6"

                         else
                            "#98a6c7"
                        )
                    , SA.textAnchor
                        (if isOutput then
                            "start"

                         else
                            "end"
                        )
                    , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
                    ]
                    [ Svg.text info.short ]
                ]
    in
    labelNode
        ++ [ Svg.circle
                [ SA.cx (String.fromFloat placed.x)
                , SA.cy (String.fromFloat placed.y)
                , SA.r (String.fromFloat radius)
                , SA.fill
                    (if placed.declared then
                        color

                     else
                        "#05070f"
                    )
                , SA.stroke
                    (if isSelected then
                        "#f4ead6"

                     else
                        color
                    )
                , SA.strokeWidth
                    (if isSelected then
                        "2"

                     else
                        "1"
                    )
                , SA.strokeDasharray
                    (if placed.declared then
                        "none"

                     else
                        "2 2"
                    )
                ]
                []
           , Svg.circle
                [ SA.cx (String.fromFloat placed.x)
                , SA.cy (String.fromFloat placed.y)
                , SA.r "8"
                , SA.fill "transparent"
                , Svg.Events.onMouseOver (config.onSelect placed.id)
                , Svg.Events.onClick (config.onSelect placed.id)
                ]
                []
           ]


viewReadout : Config msg -> Api.Genome -> Summary -> Html msg
viewReadout config genome summary =
    let
        base =
            div [ Attr.class "topo-readout", Attr.id config.describedBy ]
    in
    case config.selected of
        Nothing ->
            base
                [ text
                    (String.fromInt summary.nodes
                        ++ " nodes ("
                        ++ String.fromInt summary.hidden
                        ++ " hidden, evolved), "
                        ++ String.fromInt summary.enabled
                        ++ " enabled connections of which "
                        ++ String.fromInt summary.recurrent
                        ++ " are recurrent, "
                        ++ String.fromInt summary.disabled
                        ++ " disabled. Hover, tap, or focus the graph and use the arrow keys to inspect a node."
                    )
                ]

        Just id ->
            let
                info =
                    Slots.slot id

                incoming =
                    genome.genes |> List.filter (\g -> g.to == id)

                outgoing =
                    genome.genes |> List.filter (\g -> g.from == id)

                describe label list =
                    label
                        ++ " "
                        ++ String.fromInt (List.length (List.filter .enabled list))
                        ++ " enabled"
                        ++ (if List.length list > List.length (List.filter .enabled list) then
                                ", " ++ String.fromInt (List.length list - List.length (List.filter .enabled list)) ++ " disabled"

                            else
                                ""
                           )
            in
            base
                [ Html.b [] [ text ("node " ++ String.fromInt id ++ " \u{00B7} " ++ info.short) ]
                , text (" \u{00B7} " ++ Slots.groupLabel info.group)
                , Html.br [] []
                , text info.detail
                , Html.br [] []
                , text (describe "In:" incoming ++ ". " ++ describe "Out:" outgoing ++ ".")
                , text (strongestNote incoming outgoing)
                ]


strongestNote : List Api.Gene -> List Api.Gene -> String
strongestNote incoming outgoing =
    let
        strongest =
            (incoming ++ outgoing)
                |> List.filter .enabled
                |> List.sortBy (\g -> -(abs g.weight))
                |> List.head
    in
    case strongest of
        Nothing ->
            " No enabled connection touches this node, so it contributes nothing."

        Just g ->
            " Strongest link: "
                ++ String.fromInt g.from
                ++ " \u{2192} "
                ++ String.fromInt g.to
                ++ " at "
                ++ Format.signedWeight g.weight
                ++ "."


viewKey : Html msg
viewKey =
    div [ Attr.class "topo-key" ]
        (List.map
            (\group ->
                span []
                    [ span [ Attr.class "swatch", Attr.style "background" (groupColor group) ] []
                    , text (Slots.groupLabel group)
                    ]
            )
            [ Sensors, OurShipBits, TheirShipBits, PriorControls, PriorMemory, Bias, Hidden ]
            ++ [ span []
                    [ span [ Attr.class "swatch", Attr.style "background" "#4fd6e0" ] []
                    , text "positive weight"
                    ]
               , span []
                    [ span [ Attr.class "swatch", Attr.style "background" "#f0715a" ] []
                    , text "negative weight"
                    ]
               , span []
                    [ span [ Attr.class "swatch", Attr.style "background" "#56618a" ] []
                    , text "disabled gene (dashed)"
                    ]
               , span [] [ text "Bowed curves are recurrent links." ]
               ]
        )
