module Mario.Dashboard.Heatmap exposing
    ( Config
    , Grid
    , cellFill
    , grid
    , shortName
    , view
    )

{-| Per-matchup audit evidence, one cell per ordered pair.

Rows are our ship, columns are the opponent. The pair is ordered: our
Pkunk against their Umgah is a different cell from our Umgah against
their Pkunk, and each has to pass the gate on its own evidence. Nothing
on this grid is pooled, averaged across cells, or borrowed from training
play.

Colour encodes the Wilson lower bound where one exists, and the hue
changes at the target, so a cell that has not actually cleared the gate
can never be mistaken for one that has. A cell with no games is drawn as
unmeasured, not as zero: never played and always lost look nothing alike
and must not be coloured alike.

-}

import Dict exposing (Dict)
import Html exposing (Html, div, span, text)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Mario.Dashboard.Api as Api exposing (Matchup)
import Mario.Dashboard.Format as Format
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events


type alias Grid =
    { rows : List String
    , cols : List String
    , cells : Dict ( String, String ) Matchup
    }


{-| Rows and columns follow the frozen roster order where the trainer
supplied one, so the grid grows by appending rather than reshuffling.
Any pair the trainer reports that is not in the roster is appended
rather than dropped.
-}
grid : List String -> List String -> List Matchup -> Grid
grid ourRoster opponentRoster matchups =
    let
        order preferred present =
            (preferred |> List.filter (\name -> List.member name present))
                ++ (present |> List.filter (\name -> not (List.member name preferred)))

        unique list =
            List.foldl
                (\x acc ->
                    if List.member x acc then
                        acc

                    else
                        acc ++ [ x ]
                )
                []
                list
    in
    { rows = order ourRoster (unique (List.map .us matchups))
    , cols = order opponentRoster (unique (List.map .them matchups))
    , cells = List.foldl (\m acc -> Dict.insert ( m.us, m.them ) m acc) Dict.empty matchups
    }


shortName : Int -> String -> String
shortName columns name =
    if columns <= 8 then
        name

    else if columns <= 16 then
        String.left 5 name

    else
        String.left 3 name



-- COLOUR


type alias Rgb =
    ( Float, Float, Float )


lerp : Rgb -> Rgb -> Float -> String
lerp ( r1, g1, b1 ) ( r2, g2, b2 ) t =
    let
        k =
            clamp 0 1 t

        mix a b =
            String.fromInt (round (a + (b - a) * k))
    in
    "rgb(" ++ mix r1 r2 ++ "," ++ mix g1 g2 ++ "," ++ mix b1 b2 ++ ")"


{-| Below the target the ramp runs deep red to amber. At and above the
target it jumps to the cyan family. The discontinuity is deliberate: the
gate is a threshold, not a gradient, and the grid should look like it.
-}
cellFill : Float -> Maybe Float -> String
cellFill target measured =
    case measured of
        Nothing ->
            "#131c30"

        Just v ->
            if v >= target then
                lerp ( 30, 106, 114 ) ( 79, 214, 224 )
                    (if target >= 1 then
                        1

                     else
                        (v - target) / (1 - target)
                    )

            else
                lerp ( 84, 28, 20 ) ( 255, 178, 63 )
                    (if target <= 0 then
                        1

                     else
                        v / target
                    )


statusStroke : Api.MatchupStatus -> String
statusStroke status =
    case status of
        Api.Mastered ->
            "#4fd6e0"

        Api.AuditingCell ->
            "#a99bf5"

        Api.Learning ->
            "#8a5f1d"

        Api.Unseen ->
            "#24355c"

        Api.UnknownStatus _ ->
            "#98a6c7"



-- VIEW


type alias Config msg =
    { target : Float
    , selected : Maybe ( Int, Int )
    , onSelect : Int -> Int -> msg
    , onClear : msg
    , describedBy : String
    }


cellSize : Int -> Float
cellSize columns =
    if columns <= 6 then
        34

    else if columns <= 12 then
        26

    else if columns <= 18 then
        20

    else
        15


view : Config msg -> Grid -> Html msg
view config g =
    let
        cols =
            List.length g.cols

        rows =
            List.length g.rows
    in
    if cols == 0 || rows == 0 then
        div [ Attr.class "placeholder" ]
            [ Html.strong [] [ text "No matchups reported" ]
            , span [] [ text "The trainer has not published any ordered matchups for this stage yet." ]
            ]

    else
        let
            size =
                cellSize cols

            gap =
                2

            labelLeft =
                if cols <= 12 then
                    82

                else
                    56

            labelTop =
                60

            width =
                labelLeft + toFloat cols * (size + gap) + 10

            height =
                labelTop + toFloat rows * (size + gap) + 10
        in
        div []
            [ div [ Attr.class "heat-wrap" ]
                [ Svg.svg
                    [ SA.class "heat-svg"
                    , SA.viewBox ("0 0 " ++ String.fromFloat width ++ " " ++ String.fromFloat height)
                    , SA.width (String.fromFloat width)
                    , Attr.attribute "role" "group"
                    , Attr.attribute "tabindex" "0"
                    , Attr.attribute "aria-label"
                        ("Ordered matchup evidence grid, "
                            ++ String.fromInt rows
                            ++ " of our ships by "
                            ++ String.fromInt cols
                            ++ " opponent ships. Focus this grid and use the arrow keys to read each cell."
                        )
                    , Attr.attribute "aria-describedby" config.describedBy
                    , Html.Events.preventDefaultOn "keydown" (arrowDecoder config rows cols)
                    ]
                    (colHeadings g size gap labelLeft labelTop cols
                        ++ rowHeadings g size gap labelLeft labelTop cols
                        ++ cellsSvg config g size gap labelLeft labelTop
                    )
                ]
            , viewReadout config g
            , viewLegend config
            ]


arrowDecoder : Config msg -> Int -> Int -> Decode.Decoder ( msg, Bool )
arrowDecoder config rows cols =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                let
                    -- With no cell selected yet, the first arrow press lands
                    -- on the top left cell rather than skipping past it.
                    go dr dc =
                        case config.selected of
                            Nothing ->
                                Decode.succeed ( config.onSelect 0 0, True )

                            Just ( r, c ) ->
                                Decode.succeed
                                    ( config.onSelect
                                        (max 0 (min (rows - 1) (r + dr)))
                                        (max 0 (min (cols - 1) (c + dc)))
                                    , True
                                    )
                in
                case key of
                    "ArrowUp" ->
                        go -1 0

                    "ArrowDown" ->
                        go 1 0

                    "ArrowLeft" ->
                        go 0 -1

                    "ArrowRight" ->
                        go 0 1

                    "Escape" ->
                        Decode.succeed ( config.onClear, False )

                    _ ->
                        Decode.fail "ignored"
            )


colHeadings : Grid -> Float -> Float -> Float -> Float -> Int -> List (Svg msg)
colHeadings g size gap labelLeft labelTop cols =
    List.indexedMap
        (\i name ->
            let
                x =
                    labelLeft + toFloat i * (size + gap) + size / 2
            in
            Svg.text_
                [ SA.x (String.fromFloat x)
                , SA.y (String.fromFloat (labelTop - 6))
                , SA.fontSize "9.5"
                , SA.fill "#98a6c7"
                , SA.textAnchor "start"
                , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
                , SA.transform
                    ("rotate(-60 " ++ String.fromFloat x ++ " " ++ String.fromFloat (labelTop - 6) ++ ")")
                ]
                [ Svg.text (shortName cols name) ]
        )
        g.cols


rowHeadings : Grid -> Float -> Float -> Float -> Float -> Int -> List (Svg msg)
rowHeadings g size gap labelLeft labelTop cols =
    List.indexedMap
        (\i name ->
            Svg.text_
                [ SA.x (String.fromFloat (labelLeft - 8))
                , SA.y (String.fromFloat (labelTop + toFloat i * (size + gap) + size / 2 + 3.5))
                , SA.fontSize "9.5"
                , SA.fill "#98a6c7"
                , SA.textAnchor "end"
                , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
                ]
                [ Svg.text (shortName cols name) ]
        )
        g.rows


cellsSvg : Config msg -> Grid -> Float -> Float -> Float -> Float -> List (Svg msg)
cellsSvg config g size gap labelLeft labelTop =
    List.concat
        (List.indexedMap
            (\r us ->
                List.indexedMap
                    (\c them ->
                        let
                            x =
                                labelLeft + toFloat c * (size + gap)

                            y =
                                labelTop + toFloat r * (size + gap)

                            found =
                                Dict.get ( us, them ) g.cells

                            measured =
                                found
                                    |> Maybe.andThen
                                        (\m ->
                                            if m.games <= 0 then
                                                Nothing

                                            else
                                                case m.lowerBound of
                                                    Just b ->
                                                        Just b

                                                    Nothing ->
                                                        m.winRate
                                        )

                            status =
                                found |> Maybe.map .status |> Maybe.withDefault Api.Unseen

                            isSelected =
                                config.selected == Just ( r, c )
                        in
                        Svg.g []
                            [ Svg.rect
                                [ SA.x (String.fromFloat x)
                                , SA.y (String.fromFloat y)
                                , SA.width (String.fromFloat size)
                                , SA.height (String.fromFloat size)
                                , SA.rx "3"
                                , SA.fill (cellFill config.target measured)
                                , SA.stroke
                                    (if isSelected then
                                        "#f4ead6"

                                     else
                                        statusStroke status
                                    )
                                , SA.strokeWidth
                                    (if isSelected then
                                        "2"

                                     else
                                        "1"
                                    )
                                , SA.strokeDasharray
                                    (if measured == Nothing then
                                        "2 2"

                                     else
                                        "none"
                                    )
                                , Svg.Events.onMouseOver (config.onSelect r c)
                                , Svg.Events.onClick (config.onSelect r c)
                                ]
                                []
                            ]
                    )
                    g.cols
            )
            g.rows
        )


viewReadout : Config msg -> Grid -> Html msg
viewReadout config g =
    let
        wrap children =
            div [ Attr.class "heat-readout", Attr.id config.describedBy ] children

        at index list =
            list |> List.drop index |> List.head
    in
    case config.selected of
        Nothing ->
            wrap
                [ div [ Attr.class "ro-line" ]
                    [ text "Hover, tap, or focus the grid and use the arrow keys to read a cell's audit evidence." ]
                ]

        Just ( r, c ) ->
            case ( at r g.rows, at c g.cols ) of
                ( Just us, Just them ) ->
                    case Dict.get ( us, them ) g.cells of
                        Just m ->
                            wrap
                                [ div [ Attr.class "ro-title" ]
                                    [ text ("our " ++ us ++ "  vs  their " ++ them ++ "  (" ++ Api.opponentTypeLabel m.opponentType ++ ")") ]
                                , div [ Attr.class "ro-line" ]
                                    [ text
                                        (if m.games <= 0 then
                                            "No audit games played for this ordered pair yet. Unmeasured, not lost."

                                         else
                                            "Audit wins "
                                                ++ Format.fraction m.wins m.games
                                                ++ "  \u{00B7}  rate "
                                                ++ (m.winRate |> Maybe.map Format.percent1 |> Maybe.withDefault Format.awaiting)
                                                ++ "  \u{00B7}  Wilson lower bound "
                                                ++ (m.lowerBound |> Maybe.map Format.percent1 |> Maybe.withDefault Format.awaiting)
                                                ++ "  \u{00B7}  target "
                                                ++ Format.percent config.target
                                        )
                                    ]
                                , div [ Attr.class "ro-line" ]
                                    [ text
                                        ("Status "
                                            ++ Api.matchupStatusLabel m.status
                                            ++ "  \u{00B7}  training sample weight "
                                            ++ Format.decimal 3 m.sampleWeight
                                            ++ " (weights steer training play, never the gate)"
                                        )
                                    ]
                                ]

                        Nothing ->
                            wrap
                                [ div [ Attr.class "ro-title" ] [ text ("our " ++ us ++ "  vs  their " ++ them) ]
                                , div [ Attr.class "ro-line" ]
                                    [ text "This ordered pair is not active at the current stage, so it has no evidence." ]
                                ]

                _ ->
                    wrap [ div [ Attr.class "ro-line" ] [ text "Select a cell to read its evidence." ] ]


viewLegend : Config msg -> Html msg
viewLegend config =
    div [ Attr.class "heat-legend" ]
        [ span []
            [ span [ Attr.class "swatch", Attr.style "background" "#131c30" ] []
            , text "unmeasured (no audit games)"
            ]
        , span []
            [ span [ Attr.class "swatch", Attr.style "background" (cellFill config.target (Just 0)) ] []
            , text "0%"
            ]
        , span []
            [ span [ Attr.class "swatch", Attr.style "background" (cellFill config.target (Just (config.target * 0.99))) ] []
            , text ("just under " ++ Format.percent config.target)
            ]
        , span []
            [ span [ Attr.class "swatch", Attr.style "background" (cellFill config.target (Just config.target)) ] []
            , text ("at " ++ Format.percent config.target ++ " (gate)")
            ]
        , span []
            [ span [ Attr.class "swatch", Attr.style "background" (cellFill config.target (Just 1)) ] []
            , text "100%"
            ]
        , span [] [ text "Colour follows the Wilson lower bound, not the raw rate. Outline colour shows cell status." ]
        ]
