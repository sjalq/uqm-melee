module Mario.Dashboard.Chart exposing
    ( Config
    , Guide
    , Series
    , runs
    , series
    , view
    )

{-| Small SVG trend charts with an interactive crosshair.

Two correctness rules are built into the geometry rather than left to
the caller's discipline.

1.  A gap is a gap. A `Nothing` sample is never drawn as zero and never
    bridged; the polyline simply stops and restarts.

2.  Every slot is comparable with every other. The trainer trains on the
    whole board from generation one, so consecutive history points
    measure the same question and there is no scope change for the
    geometry to break the line at. The only break left is rule 1's.

The crosshair is driven by one invisible hit rectangle per slot, so it
needs no pointer coordinate arithmetic and behaves identically under
mouse and touch. The whole plot is a single tab stop: focus it and the
left and right arrow keys walk the crosshair, which keeps the chart
usable without a pointer and without adding a hundred tab stops.

-}

import Html exposing (Html, div, span, text)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events


type alias Series =
    { key : String
    , label : String
    , color : String
    , width : Float
    , dashed : Bool
    , markers : Bool
    , values : List (Maybe Float)
    }


series : String -> String -> String -> List (Maybe Float) -> Series
series key label color values =
    { key = key
    , label = label
    , color = color
    , width = 2
    , dashed = False
    , markers = False
    , values = values
    }


type alias Guide =
    { value : Float
    , label : String
    , color : String
    }


type alias Config msg =
    { height : Float
    , userWidth : Float
    , xLabels : List String
    , yMin : Float
    , yMax : Float
    , yTicks : List ( Float, String )
    , series : List Series
    , guides : List Guide
    , hovered : Maybe Int
    , onHover : Int -> msg
    , onLeave : msg
    , formatValue : Float -> String
    , emptyHint : String
    , describedBy : String
    }



-- GEOMETRY
-- A fixed user-space width with a responsive viewBox: the SVG scales to
-- its container without any measurement, and the crosshair hit targets
-- scale with it.


plotLeft : Float
plotLeft =
    46


plotRight : Float
plotRight =
    10


plotTop : Float
plotTop =
    12


plotBottom : Float
plotBottom =
    26


{-| The chart's own coordinate width. Callers pass a value close to the
width the panel actually renders at, because the viewBox is stretched to
fill its container: a 720-wide chart squeezed into a 380-pixel panel
would condense every label to half width and make the axes unreadable.
-}
plotWidth : Config msg -> Float
plotWidth config =
    config.userWidth - plotLeft - plotRight


slotX : Config msg -> Int -> Int -> Float
slotX config total index =
    if total <= 1 then
        plotLeft + (plotWidth config / 2)

    else
        plotLeft + (plotWidth config * toFloat index / toFloat (total - 1))


valueY : Config msg -> Float -> Float
valueY config value =
    let
        span_ =
            config.yMax - config.yMin

        plotHeight =
            config.height - plotTop - plotBottom

        t =
            if span_ <= 0 then
                0.5

            else
                (value - config.yMin) / span_
    in
    plotTop + plotHeight * (1 - clamp 0 1 t)



-- VIEW


view : Config msg -> Html msg
view config =
    let
        total =
            List.length config.xLabels
    in
    if total == 0 then
        div [ Attr.class "placeholder" ]
            [ Html.strong [] [ text "No samples yet" ]
            , span [] [ text config.emptyHint ]
            ]

    else
        div [ Attr.class "chart-wrap" ]
            [ Svg.svg
                [ SA.class "chart-svg"
                , SA.viewBox ("0 0 " ++ String.fromFloat config.userWidth ++ " " ++ String.fromFloat config.height)
                , SA.preserveAspectRatio "none"
                , Attr.attribute "role" "group"
                , Attr.attribute "tabindex" "0"
                , Attr.attribute "aria-label" (ariaLabel config total)
                , Attr.attribute "aria-describedby" config.describedBy
                , Html.Events.preventDefaultOn "keydown" (arrowDecoder config total)
                , Svg.Events.onMouseOut config.onLeave
                ]
                (viewGrid config total
                    ++ viewGuides config
                    ++ List.concatMap (viewSeries config total) config.series
                    ++ viewCrosshair config total
                    ++ viewHitTargets config total
                )
            , viewLegend config
            , viewReadout config total
            ]


ariaLabel : Config msg -> Int -> String
ariaLabel config total =
    "Trend chart, "
        ++ String.fromInt total
        ++ " samples, series: "
        ++ String.join ", " (List.map .label config.series)
        ++ ". Focus this chart and use the left and right arrow keys to read each sample."


arrowDecoder : Config msg -> Int -> Decode.Decoder ( msg, Bool )
arrowDecoder config total =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                let
                    -- With nothing selected, the first arrow press lands on
                    -- the most recent sample rather than stepping off it.
                    move delta =
                        case config.hovered of
                            Nothing ->
                                Decode.succeed ( config.onHover (total - 1), True )

                            Just current ->
                                Decode.succeed ( config.onHover (clampIndex total (current + delta)), True )
                in
                case key of
                    "ArrowLeft" ->
                        move -1

                    "ArrowRight" ->
                        move 1

                    "Home" ->
                        Decode.succeed ( config.onHover 0, True )

                    "End" ->
                        Decode.succeed ( config.onHover (total - 1), True )

                    "Escape" ->
                        Decode.succeed ( config.onLeave, False )

                    _ ->
                        Decode.fail "ignored"
            )


clampIndex : Int -> Int -> Int
clampIndex total index =
    max 0 (min (total - 1) index)



-- GRID


viewGrid : Config msg -> Int -> List (Svg msg)
viewGrid config total =
    let
        bottomY =
            config.height - plotBottom

        ticks =
            List.concatMap
                (\( value, label ) ->
                    let
                        y =
                            valueY config value
                    in
                    [ Svg.line
                        [ SA.x1 (String.fromFloat plotLeft)
                        , SA.x2 (String.fromFloat (config.userWidth - plotRight))
                        , SA.y1 (String.fromFloat y)
                        , SA.y2 (String.fromFloat y)
                        , SA.stroke "#1a2540"
                        , SA.strokeWidth "1"
                        ]
                        []
                    , Svg.text_
                        [ SA.x (String.fromFloat (plotLeft - 8))
                        , SA.y (String.fromFloat (y + 3.5))
                        , SA.textAnchor "end"
                        , SA.fontSize "10"
                        , SA.fill "#7483a6"
                        , SA.fontFamily "ui-monospace, Menlo, Consolas, monospace"
                        ]
                        [ Svg.text label ]
                    ]
                )
                config.yTicks
    in
    ticks
        ++ [ Svg.line
                [ SA.x1 (String.fromFloat plotLeft)
                , SA.x2 (String.fromFloat (config.userWidth - plotRight))
                , SA.y1 (String.fromFloat bottomY)
                , SA.y2 (String.fromFloat bottomY)
                , SA.stroke "#24355c"
                , SA.strokeWidth "1"
                ]
                []
           ]
        ++ xAxisLabels config total


xAxisLabels : Config msg -> Int -> List (Svg msg)
xAxisLabels config total =
    let
        labels =
            List.indexedMap Tuple.pair config.xLabels

        keep =
            max 1 (ceiling (toFloat total / 8))
    in
    labels
        |> List.filter (\( i, _ ) -> modBy keep i == 0 || i == total - 1)
        |> List.map
            (\( i, label ) ->
                Svg.text_
                    [ SA.x (String.fromFloat (slotX config total i))
                    , SA.y (String.fromFloat (config.height - plotBottom + 15))
                    , SA.textAnchor
                        (if i == 0 then
                            "start"

                         else if i == total - 1 then
                            "end"

                         else
                            "middle"
                        )
                    , SA.fontSize "10"
                    , SA.fill "#7483a6"
                    , SA.fontFamily "ui-monospace, Menlo, Consolas, monospace"
                    ]
                    [ Svg.text label ]
            )


viewGuides : Config msg -> List (Svg msg)
viewGuides config =
    List.concatMap
        (\guide ->
            let
                y =
                    valueY config guide.value
            in
            [ Svg.line
                [ SA.x1 (String.fromFloat plotLeft)
                , SA.x2 (String.fromFloat (config.userWidth - plotRight))
                , SA.y1 (String.fromFloat y)
                , SA.y2 (String.fromFloat y)
                , SA.stroke guide.color
                , SA.strokeWidth "1.25"
                , SA.strokeDasharray "6 4"
                ]
                []
            , Svg.text_
                [ SA.x (String.fromFloat (plotLeft + 4))
                , SA.y (String.fromFloat (y - 5))
                , SA.textAnchor "start"
                , SA.fontSize "10"
                , SA.fill guide.color
                , SA.fontFamily "ui-monospace, Menlo, Consolas, monospace"
                ]
                [ Svg.text guide.label ]
            ]
        )
        config.guides



-- SERIES


{-| Contiguous runs of measured samples.

A `Nothing` ends the current run and starts the next one, which is what
keeps an unmeasured generation from being bridged as if it had been
measured. Nothing else breaks a run: every history point answers the
same question as every other.

-}
runs : List (Maybe Float) -> List (List ( Int, Float ))
runs values =
    let
        indexed =
            List.indexedMap Tuple.pair values

        step ( i, value ) ( current, done ) =
            case value of
                Nothing ->
                    ( [], flush current done )

                Just v ->
                    ( ( i, v ) :: current, done )

        flush current done =
            if List.isEmpty current then
                done

            else
                List.reverse current :: done

        ( leftover, collected ) =
            List.foldl step ( [], [] ) indexed
    in
    List.reverse (flush leftover collected)


viewSeries : Config msg -> Int -> Series -> List (Svg msg)
viewSeries config total s =
    let
        measuredRuns =
            runs s.values

        toPoint ( i, v ) =
            String.fromFloat (slotX config total i) ++ "," ++ String.fromFloat (valueY config v)

        lineOf run =
            if List.length run < 2 then
                []

            else
                [ Svg.polyline
                    [ SA.points (String.join " " (List.map toPoint run))
                    , SA.fill "none"
                    , SA.stroke s.color
                    , SA.strokeWidth (String.fromFloat s.width)
                    , SA.strokeLinecap "round"
                    , SA.strokeLinejoin "round"
                    , SA.strokeDasharray
                        (if s.dashed then
                            "5 4"

                         else
                            "none"
                        )
                    ]
                    []
                ]

        dotsOf run =
            if s.markers || List.length run == 1 then
                List.map
                    (\( i, v ) ->
                        Svg.circle
                            [ SA.cx (String.fromFloat (slotX config total i))
                            , SA.cy (String.fromFloat (valueY config v))
                            , SA.r "2.6"
                            , SA.fill s.color
                            ]
                            []
                    )
                    run

            else
                []
    in
    List.concatMap (\run -> lineOf run ++ dotsOf run) measuredRuns



-- CROSSHAIR


viewCrosshair : Config msg -> Int -> List (Svg msg)
viewCrosshair config total =
    case config.hovered of
        Nothing ->
            []

        Just index ->
            let
                x =
                    slotX config total (clampIndex total index)
            in
            Svg.line
                [ SA.x1 (String.fromFloat x)
                , SA.x2 (String.fromFloat x)
                , SA.y1 (String.fromFloat plotTop)
                , SA.y2 (String.fromFloat (config.height - plotBottom))
                , SA.stroke "#f4ead6"
                , SA.strokeWidth "1"
                , SA.strokeOpacity "0.5"
                ]
                []
                :: List.filterMap
                    (\s ->
                        sampleAt index s.values
                            |> Maybe.map
                                (\v ->
                                    Svg.circle
                                        [ SA.cx (String.fromFloat x)
                                        , SA.cy (String.fromFloat (valueY config v))
                                        , SA.r "4"
                                        , SA.fill "#05070f"
                                        , SA.stroke s.color
                                        , SA.strokeWidth "2"
                                        ]
                                        []
                                )
                    )
                    config.series


sampleAt : Int -> List (Maybe Float) -> Maybe Float
sampleAt index values =
    values |> List.drop index |> List.head |> Maybe.withDefault Nothing


viewHitTargets : Config msg -> Int -> List (Svg msg)
viewHitTargets config total =
    let
        bandWidth =
            if total <= 1 then
                plotWidth config

            else
                plotWidth config / toFloat (total - 1)
    in
    List.indexedMap
        (\i _ ->
            Svg.rect
                [ SA.x (String.fromFloat (slotX config total i - bandWidth / 2))
                , SA.y (String.fromFloat plotTop)
                , SA.width (String.fromFloat bandWidth)
                , SA.height (String.fromFloat (config.height - plotTop - plotBottom))
                , SA.fill "transparent"
                , Svg.Events.onMouseOver (config.onHover i)
                , Svg.Events.onClick (config.onHover i)
                ]
                []
        )
        config.xLabels



-- LEGEND AND READOUT


viewLegend : Config msg -> Html msg
viewLegend config =
    div [ Attr.class "chart-legend" ]
        (List.map
            (\s ->
                span [ Attr.class "key" ]
                    [ span
                        [ Attr.class "line"
                        , Attr.style "border-top-color" s.color
                        , Attr.style "border-top-style"
                            (if s.dashed then
                                "dashed"

                             else
                                "solid"
                            )
                        ]
                        []
                    , text s.label
                    ]
            )
            config.series
            ++ List.map
                (\guide ->
                    span [ Attr.class "key" ]
                        [ span
                            [ Attr.class "line"
                            , Attr.style "border-top-color" guide.color
                            , Attr.style "border-top-style" "dashed"
                            ]
                            []
                        , text guide.label
                        ]
                )
                config.guides
        )


viewReadout : Config msg -> Int -> Html msg
viewReadout config total =
    case config.hovered of
        Nothing ->
            div [ Attr.class "chart-readout", Attr.id config.describedBy ]
                [ span [ Attr.class "ro-value" ]
                    [ text "Hover or tap a point, or focus the chart and use the arrow keys, to read exact values." ]
                ]

        Just raw ->
            let
                index =
                    clampIndex total raw

                label =
                    config.xLabels |> List.drop index |> List.head |> Maybe.withDefault ""
            in
            div [ Attr.class "chart-readout", Attr.id config.describedBy ]
                (readoutItem "Sample" label
                    :: List.map
                        (\s ->
                            readoutItem s.label
                                (case sampleAt index s.values of
                                    Just v ->
                                        config.formatValue v

                                    Nothing ->
                                        "not measured"
                                )
                        )
                        config.series
                )


readoutItem : String -> String -> Html msg
readoutItem label value =
    div [ Attr.class "ro-item" ]
        [ span [ Attr.class "ro-label" ] [ text label ]
        , span [ Attr.class "ro-value" ] [ text value ]
        ]
