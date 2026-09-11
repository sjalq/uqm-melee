module Mario.Dashboard exposing
    ( Action(..)
    , ControlState(..)
    , Model
    , Msg(..)
    , actionKey
    , clearSettledControl
    , init
    , main
    , update
    , view
    )

{-| MarI/O mission control.

A standalone Elm page served by the local melee-mario binary at `/`,
polling `/api/status` every two seconds while the tab is visible and
`/api/network` whenever the champion changes.

Three rules shape the whole page.

Honest absence. A measurement the trainer has not taken is rendered as
"awaiting evidence", never as zero. `Maybe Float` is carried all the way
from the decoder into the view, so there is no place where a missing
number could quietly become `0%`.

Fresh audit evidence is the headline. The champion's win rate on its
predeclared gate panel, its Wilson lower bound, and the sample size that
produced them sit at the top of the page at the largest size used
anywhere. Population training results are shown elsewhere, in a
different colour, with their own label, and are never averaged into the
gate figures.

Nothing incomparable is joined. Charts break at every curriculum stage
boundary and at every unmeasured sample. The matchup grid shows the
current stage and the current champion only.

-}

import Browser
import Browser.Events
import Html exposing (Html, button, dd, div, dl, dt, h1, h2, h3, p, section, span, text)
import Html.Attributes as Attr exposing (class)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Mario.Dashboard.Api as Api
import Mario.Dashboard.Chart as Chart
import Mario.Dashboard.Copy as Copy
import Mario.Dashboard.Format as Format
import Mario.Dashboard.Gate as Gate
import Mario.Dashboard.Heatmap as Heatmap
import Mario.Dashboard.Scoring as Scoring
import Mario.Dashboard.Slots as Slots
import Mario.Dashboard.Tip as Tip
import Mario.Dashboard.Topology as Topology
import Svg
import Svg.Attributes as SA
import Time



-- CONFIGURATION


statusUrl : String
statusUrl =
    "/api/status"


networkUrl : String
networkUrl =
    "/api/network"


controlUrl : String
controlUrl =
    "/api/control"


pollMillis : Float
pollMillis =
    2000


{-| Beyond this the snapshot is called stale rather than current. Three
missed polls, so a single slow response does not cry wolf.
-}
staleAfterSeconds : Float
staleAfterSeconds =
    7



-- MODEL


type Action
    = Pause
    | Resume
    | Stop


actionKey : Action -> String
actionKey action =
    case action of
        Pause ->
            "pause"

        Resume ->
            "resume"

        Stop ->
            "stop"


actionLabel : Action -> String
actionLabel action =
    case action of
        Pause ->
            "Pause"

        Resume ->
            "Resume"

        Stop ->
            "Stop"


type ControlState
    = ControlIdle
    | ControlPending Action
    | ControlAccepted Action
    | ControlFailed Action String


type alias Model =
    { status : Maybe Api.Status
    , statusError : Maybe String
    , statusAge : Float
    , failures : Int
    , requested : Bool
    , inFlight : Bool
    , network : Maybe Api.Network
    , networkError : Maybe String
    , networkFor : Maybe String
    , networkInFlight : Bool
    , now : Time.Posix
    , receivedAt : Maybe Time.Posix
    , visible : Bool
    , control : ControlState
    , tipHover : Maybe String
    , tipPin : Maybe String
    , winCursor : Maybe Int
    , speciesCursor : Maybe Int
    , nodesCursor : Maybe Int
    , episodesCursor : Maybe Int
    , heatCursor : Maybe ( Int, Int )
    , nodeCursor : Maybe Int
    }


init : () -> ( Model, Cmd Msg )
init () =
    ( { status = Nothing
      , statusError = Nothing
      , statusAge = 0
      , failures = 0
      , requested = False
      , inFlight = True
      , network = Nothing
      , networkError = Nothing
      , networkFor = Nothing
      , networkInFlight = True
      , now = Time.millisToPosix 0
      , receivedAt = Nothing
      , visible = True
      , control = ControlIdle
      , tipHover = Nothing
      , tipPin = Nothing
      , winCursor = Nothing
      , speciesCursor = Nothing
      , nodesCursor = Nothing
      , episodesCursor = Nothing
      , heatCursor = Nothing
      , nodeCursor = Nothing
      }
    , Cmd.batch [ fetchStatus, fetchNetwork ]
    )



-- HTTP


{-| Every request carries an explicit timeout.

Without one, a request that never completes leaves the in-flight flag
set forever and the poll loop skips every subsequent tick, so a single
dropped response wedges the page permanently. With a timeout the runtime
always delivers an outcome, the flag always clears, and the next tick
retries.
-}
requestTimeout : Maybe Float
requestTimeout =
    Just 10000


getJson : String -> (Result Http.Error a -> Msg) -> Decode.Decoder a -> Cmd Msg
getJson url toMsg decoder =
    Http.request
        { method = "GET"
        , headers = []
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg decoder
        , timeout = requestTimeout
        , tracker = Nothing
        }


fetchStatus : Cmd Msg
fetchStatus =
    getJson statusUrl GotStatus Api.decodeStatus


fetchNetwork : Cmd Msg
fetchNetwork =
    getJson networkUrl GotNetwork Api.decodeNetwork


sendControl : Action -> Cmd Msg
sendControl action =
    Http.request
        { method = "POST"
        , headers = []
        , url = controlUrl
        , body = Http.jsonBody (Encode.object [ ( "action", Encode.string (actionKey action) ) ])
        , expect = Http.expectWhatever (GotControl action)
        , timeout = requestTimeout
        , tracker = Nothing
        }


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "bad URL " ++ url

        Http.Timeout ->
            "the request timed out"

        Http.NetworkError ->
            "no response from the local trainer"

        Http.BadStatus code ->
            "the trainer answered with HTTP " ++ String.fromInt code

        Http.BadBody detail ->
            "the response did not match schema version 1: " ++ detail



-- UPDATE


type Msg
    = Tick Time.Posix
    | GotStatus (Result Http.Error Api.Status)
    | GotNetwork (Result Http.Error Api.Network)
    | VisibilityChanged Browser.Events.Visibility
    | GlobalKey String
    | TipOpen String
    | TipClose String
    | TipToggle String
    | WinHover Int
    | WinLeave
    | SpeciesHover Int
    | SpeciesLeave
    | NodesHover Int
    | NodesLeave
    | EpisodesHover Int
    | EpisodesLeave
    | HeatSelect Int Int
    | HeatClear
    | NodeSelect Int
    | NodeClear
    | RequestControl Action
    | GotControl Action (Result Http.Error ())
    | RefreshNow


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick now ->
            let
                age =
                    case model.receivedAt of
                        Just at ->
                            toFloat (Time.posixToMillis now - Time.posixToMillis at) / 1000

                        Nothing ->
                            model.statusAge
            in
            ( { model | now = now, statusAge = age, inFlight = True }
            , if model.inFlight then
                Cmd.none

              else
                fetchStatus
            )

        GotStatus (Ok status) ->
            let
                needsNetwork =
                    model.networkFor /= Just status.champion.id && status.champion.id /= ""

                control =
                    clearSettledControl status model.control
            in
            ( { model
                | status = Just status
                , statusError = Nothing
                , failures = 0
                , requested = True
                , inFlight = False
                , receivedAt = Just model.now
                , statusAge = 0
                , control = control
                , networkInFlight = model.networkInFlight || needsNetwork
              }
            , if needsNetwork && not model.networkInFlight then
                fetchNetwork

              else
                Cmd.none
            )

        GotStatus (Err error) ->
            ( { model
                | statusError = Just (httpErrorToString error)
                , failures = model.failures + 1
                , requested = True
                , inFlight = False
              }
            , Cmd.none
            )

        GotNetwork (Ok network) ->
            ( { model
                | network = Just network
                , networkError = Nothing
                , networkFor = Just network.championId
                , networkInFlight = False
              }
            , Cmd.none
            )

        GotNetwork (Err error) ->
            ( { model | networkError = Just (httpErrorToString error), networkInFlight = False }
            , Cmd.none
            )

        VisibilityChanged visibility ->
            let
                visible =
                    visibility == Browser.Events.Visible
            in
            ( { model | visible = visible, inFlight = visible || model.inFlight }
            , if visible then
                fetchStatus

              else
                Cmd.none
            )

        GlobalKey "Escape" ->
            ( { model | tipPin = Nothing, tipHover = Nothing }, Cmd.none )

        GlobalKey _ ->
            ( model, Cmd.none )

        TipOpen tipId ->
            ( { model | tipHover = Just tipId }, Cmd.none )

        TipClose tipId ->
            ( { model
                | tipHover =
                    if model.tipHover == Just tipId then
                        Nothing

                    else
                        model.tipHover
              }
            , Cmd.none
            )

        TipToggle tipId ->
            if model.tipPin == Just tipId then
                ( { model | tipPin = Nothing, tipHover = Nothing }, Cmd.none )

            else
                ( { model | tipPin = Just tipId, tipHover = Just tipId }, Cmd.none )

        WinHover index ->
            ( { model | winCursor = Just index }, Cmd.none )

        WinLeave ->
            ( { model | winCursor = Nothing }, Cmd.none )

        SpeciesHover index ->
            ( { model | speciesCursor = Just index }, Cmd.none )

        SpeciesLeave ->
            ( { model | speciesCursor = Nothing }, Cmd.none )

        NodesHover index ->
            ( { model | nodesCursor = Just index }, Cmd.none )

        NodesLeave ->
            ( { model | nodesCursor = Nothing }, Cmd.none )

        EpisodesHover index ->
            ( { model | episodesCursor = Just index }, Cmd.none )

        EpisodesLeave ->
            ( { model | episodesCursor = Nothing }, Cmd.none )

        HeatSelect row col ->
            ( { model | heatCursor = Just ( row, col ) }, Cmd.none )

        HeatClear ->
            ( { model | heatCursor = Nothing }, Cmd.none )

        NodeSelect id ->
            ( { model | nodeCursor = Just id }, Cmd.none )

        NodeClear ->
            ( { model | nodeCursor = Nothing }, Cmd.none )

        RequestControl action ->
            ( { model | control = ControlPending action }, sendControl action )

        GotControl action (Ok ()) ->
            ( { model | control = ControlAccepted action, inFlight = True }, fetchStatus )

        GotControl action (Err error) ->
            ( { model | control = ControlFailed action (httpErrorToString error) }, Cmd.none )

        RefreshNow ->
            ( { model | inFlight = True, networkInFlight = True }
            , Cmd.batch [ fetchStatus, fetchNetwork ]
            )


{-| A control request stays pending on screen until the trainer's own
reported phase confirms it. Nothing is assumed to have worked.
-}
clearSettledControl : Api.Status -> ControlState -> ControlState
clearSettledControl status control =
    case control of
        ControlAccepted Pause ->
            if status.phase == Api.Paused then
                ControlIdle

            else
                control

        ControlAccepted Resume ->
            if Api.phaseIsLive status.phase then
                ControlIdle

            else
                control

        ControlAccepted Stop ->
            if status.phase == Api.Stopped then
                ControlIdle

            else
                control

        _ ->
            control



-- SUBSCRIPTIONS


{-| While hidden the page keeps a slow heartbeat rather than stopping
dead. The intent of pausing is to stop burning the machine's battery and
the trainer's time on a page nobody is looking at, and a poll every
thirty seconds honours that. Stopping entirely does not: an embedded or
background webview can stay hidden for its whole life, and a page that
never polls there shows a snapshot that is silently hours old.
-}
hiddenPollMillis : Float
hiddenPollMillis =
    30000


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every
            (if model.visible then
                pollMillis

             else
                hiddenPollMillis
            )
            Tick
        , Browser.Events.onVisibilityChange VisibilityChanged
        , Browser.Events.onKeyDown (Decode.map GlobalKey (Decode.field "key" Decode.string))
        ]



-- VIEW


tipHandlers : Model -> Tip.Handlers Msg
tipHandlers model =
    { open = TipOpen
    , close = TipClose
    , toggle = TipToggle
    , openId =
        case model.tipPin of
            Just pinned ->
                Just pinned

            Nothing ->
                model.tipHover
    , pinnedId = model.tipPin
    }


view : Model -> Html Msg
view model =
    div [ class "page" ]
        (viewMasthead model
            :: viewBanners model
            ++ viewBody model
        )


viewBody : Model -> List (Html Msg)
viewBody model =
    case model.status of
        Nothing ->
            if model.requested then
                [ div [ class "panel" ]
                    [ div [ class "placeholder" ]
                        [ Html.strong [] [ text "Not connected" ]
                        , span []
                            [ text
                                ("The dashboard could not read "
                                    ++ statusUrl
                                    ++ ": "
                                    ++ Maybe.withDefault "unknown reason" model.statusError
                                    ++ "."
                                )
                            ]
                        , span [] [ text "No data is shown because none has ever been received in this session. Start the trainer, then retry." ]
                        , button [ class "btn btn-primary", onClick RefreshNow ] [ text "Retry now" ]
                        ]
                    ]
                ]

            else
                [ div [ class "panel" ]
                    [ div [ class "placeholder" ]
                        [ Html.strong [] [ text "Loading" ]
                        , span [] [ text "Waiting for the first status snapshot from the local trainer." ]
                        ]
                    ]
                ]

        Just status ->
            let
                tips =
                    tipHandlers model
            in
            [ div [ class "grid grid-main" ]
                ([ section [ class "col-8" ] [ viewGate tips model status ]
                 , section [ class "col-4" ] [ viewVitals tips model status ]
                 , section [ class "col-7" ] [ viewCurriculum tips status ]
                 , section [ class "col-5" ] [ viewProgression tips status ]
                 ]
                    ++ (if Api.isBroad status.curriculum then
                            [ section [ class "col-12" ] [ viewShipPerformance tips status ] ]

                        else
                            []
                       )
                    ++ viewCharts tips model status
                )
            ]


viewCharts : Tip.Handlers Msg -> Model -> Api.Status -> List (Html Msg)
viewCharts tips model status =
    [ section [ class "col-12" ] [ viewWinChart tips model status ]
    , section [ class "col-4" ] [ viewSpeciesChart tips model status ]
    , section [ class "col-4" ] [ viewNodesChart tips model status ]
    , section [ class "col-4" ] [ viewEpisodesChart tips model status ]
    , section [ class "col-12" ] [ viewHeatmap tips model status ]
    , section [ class "col-7" ] [ viewAllocation tips status ]
    , section [ class "col-5" ] [ viewMachine tips status ]
    , section [ class "col-12" ] [ viewTopology tips model status ]
    , section [ class "col-12" ] [ viewEvents tips status ]
    ]



-- MASTHEAD


viewMasthead : Model -> Html Msg
viewMasthead model =
    let
        tips =
            tipHandlers model
    in
    div [ class "masthead" ]
        [ crest
        , div [ class "masthead-titles" ]
            [ h1 [] [ text "MarI/O Mission Control" ]
            , span [ class "eyebrow" ]
                [ text
                    (case model.status of
                        Just status ->
                            "run " ++ status.runId

                        Nothing ->
                            "local trainer, loopback only"
                    )
                ]
            ]
        , div [ class "masthead-spacer" ] []
        , div [ class "masthead-actions" ]
            (viewPhasePill tips model
                :: viewFreshnessPill tips model
                :: viewControls tips model
            )
        ]


crest : Html msg
crest =
    Svg.svg
        [ SA.class "crest", SA.viewBox "0 0 40 40", Attr.attribute "aria-hidden" "true" ]
        [ Svg.polygon
            [ SA.points "20,2 36,11 36,29 20,38 4,29 4,11"
            , SA.fill "none"
            , SA.stroke "#ffb23f"
            , SA.strokeWidth "1.6"
            ]
            []
        , Svg.polygon
            [ SA.points "20,9 30,14.5 30,25.5 20,31 10,25.5 10,14.5"
            , SA.fill "none"
            , SA.stroke "#4fd6e0"
            , SA.strokeWidth "1.2"
            ]
            []
        , Svg.circle [ SA.cx "20", SA.cy "20", SA.r "3.2", SA.fill "#f4ead6" ] []
        , Svg.line [ SA.x1 "20", SA.y1 "9", SA.x2 "20", SA.y2 "16.8", SA.stroke "#4fd6e0", SA.strokeWidth "1" ] []
        , Svg.line [ SA.x1 "20", SA.y1 "23.2", SA.x2 "20", SA.y2 "31", SA.stroke "#4fd6e0", SA.strokeWidth "1" ] []
        ]


viewPhasePill : Tip.Handlers Msg -> Model -> Html Msg
viewPhasePill tips model =
    let
        ( tone, label ) =
            case model.status of
                Nothing ->
                    ( "pill-idle", "Connecting" )

                Just status ->
                    ( case status.phase of
                        Api.Errored ->
                            "pill-bad"

                        Api.Paused ->
                            "pill-warn"

                        Api.Stopped ->
                            "pill-warn"

                        Api.Training ->
                            "pill-ok"

                        Api.Auditing ->
                            "pill-ok"

                        Api.Initializing ->
                            "pill-idle"

                        Api.UnknownPhase _ ->
                            "pill-idle"
                    , Api.phaseLabel status.phase
                    )
    in
    Tip.view tips Tip.AlignEnd Copy.phase [ span [ class ("pill " ++ tone) ] [ span [ class "dot" ] [], text label ] ]


viewFreshnessPill : Tip.Handlers Msg -> Model -> Html Msg
viewFreshnessPill tips model =
    let
        stale =
            isStale model

        tone =
            if model.statusError /= Nothing then
                "pill-bad"

            else if stale then
                "pill-warn"

            else
                "pill-idle"

        label =
            case model.receivedAt of
                Nothing ->
                    "no snapshot"

                Just _ ->
                    Format.decimal 0 model.statusAge ++ "s old"
    in
    Tip.view tips Tip.AlignEnd Copy.freshness [ span [ class ("pill " ++ tone) ] [ text label ] ]


isStale : Model -> Bool
isStale model =
    model.statusError /= Nothing || model.statusAge > staleAfterSeconds


viewControls : Tip.Handlers Msg -> Model -> List (Html Msg)
viewControls tips model =
    let
        live =
            model.status |> Maybe.map (\s -> Api.phaseIsLive s.phase) |> Maybe.withDefault False

        stopped =
            model.status |> Maybe.map (\s -> s.phase == Api.Stopped) |> Maybe.withDefault False

        pendingFor action =
            case model.control of
                ControlPending a ->
                    a == action

                ControlAccepted a ->
                    a == action

                _ ->
                    False

        busy =
            case model.control of
                ControlPending _ ->
                    True

                ControlAccepted _ ->
                    True

                _ ->
                    False

        controlButton action extraClass enabled =
            button
                [ class
                    ("btn "
                        ++ (if pendingFor action then
                                "btn-pending"

                            else
                                extraClass
                           )
                    )
                , Attr.disabled (busy || not enabled)
                , Attr.attribute "aria-live" "polite"
                , onClick (RequestControl action)
                ]
                [ text
                    (if pendingFor action then
                        actionLabel action ++ "\u{2026}"

                     else
                        actionLabel action
                    )
                ]
    in
    [ Tip.view tips
        Tip.AlignEnd
        Copy.controls
        [ controlButton Pause "" live
        , controlButton Resume "btn-primary" (not live && not stopped)
        , controlButton Stop "btn-danger" (not stopped)
        ]
    , button [ class "btn", onClick RefreshNow ] [ text "Refresh" ]
    ]



-- BANNERS


viewBanners : Model -> List (Html Msg)
viewBanners model =
    List.filterMap identity
        [ disconnectedBanner model
        , staleBanner model
        , controlBanner model
        , errorPhaseBanner model
        ]


disconnectedBanner : Model -> Maybe (Html Msg)
disconnectedBanner model =
    case ( model.statusError, model.status ) of
        ( Just reason, Just _ ) ->
            Just
                (div [ class "banner banner-bad", Attr.attribute "role" "status" ]
                    [ div []
                        [ Html.strong [] [ text "Disconnected. " ]
                        , text
                            ("The last "
                                ++ String.fromInt model.failures
                                ++ " polls failed: "
                                ++ reason
                                ++ ". Everything below is the snapshot from "
                                ++ Format.decimal 0 model.statusAge
                                ++ " seconds ago, not the current state of the trainer."
                            )
                        ]
                    , div [ class "banner-actions" ]
                        [ button [ class "btn btn-small", onClick RefreshNow ] [ text "Retry" ] ]
                    ]
                )

        _ ->
            Nothing


staleBanner : Model -> Maybe (Html Msg)
staleBanner model =
    case model.status of
        Just status ->
            if model.statusError == Nothing && model.statusAge > staleAfterSeconds && Api.phaseIsLive status.phase then
                Just
                    (div [ class "banner banner-warn", Attr.attribute "role" "status" ]
                        [ div []
                            [ Html.strong [] [ text "Stale snapshot. " ]
                            , text
                                ("The trainer says it is "
                                    ++ String.toLower (Api.phaseLabel status.phase)
                                    ++ ", but it has not published an update for "
                                    ++ Format.decimal 0 model.statusAge
                                    ++ " seconds. Treat these numbers as historical until it catches up."
                                )
                            ]
                        ]
                    )

            else
                Nothing

        Nothing ->
            Nothing


controlBanner : Model -> Maybe (Html Msg)
controlBanner model =
    case model.control of
        ControlFailed action reason ->
            Just
                (div [ class "banner banner-bad", Attr.attribute "role" "alert" ]
                    [ div []
                        [ Html.strong [] [ text (actionLabel action ++ " failed. ") ]
                        , text ("The trainer did not accept the request: " ++ reason ++ ". The run is unchanged.")
                        ]
                    , div [ class "banner-actions" ]
                        [ button [ class "btn btn-small", onClick (RequestControl action) ] [ text "Try again" ] ]
                    ]
                )

        ControlAccepted action ->
            Just
                (div [ class "banner banner-info", Attr.attribute "role" "status" ]
                    [ div []
                        [ Html.strong [] [ text (actionLabel action ++ " requested. ") ]
                        , text "The trainer has accepted the request and will act at its next safe boundary. This notice clears when its reported phase confirms it."
                        ]
                    ]
                )

        ControlPending action ->
            Just
                (div [ class "banner banner-info", Attr.attribute "role" "status" ]
                    [ div []
                        [ Html.strong [] [ text (actionLabel action ++ " sending\u{2026} ") ]
                        , text "Waiting for the trainer to acknowledge."
                        ]
                    ]
                )

        ControlIdle ->
            Nothing


errorPhaseBanner : Model -> Maybe (Html Msg)
errorPhaseBanner model =
    case model.status of
        Just status ->
            if status.phase == Api.Errored then
                Just
                    (div [ class "banner banner-bad", Attr.attribute "role" "alert" ]
                        [ div []
                            [ Html.strong [] [ text "Trainer reported an error. " ]
                            , text
                                (if String.isEmpty status.message then
                                    "No detail was supplied."

                                 else
                                    status.message
                                )
                            ]
                        ]
                    )

            else if not (String.isEmpty status.message) then
                Just
                    (div [ class "banner", Attr.attribute "role" "status" ]
                        [ div [] [ text status.message ] ]
                    )

            else
                Nothing

        Nothing ->
            Nothing



-- SHARED PIECES


panel : Tip.Handlers Msg -> Tip.Tip -> String -> List (Html Msg) -> Html Msg
panel tips tip title children =
    div [ class "panel" ]
        (div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart tip [ h2 [] [ text title ] ] ]
            :: children
        )


type alias MetricSpec =
    { tip : Tip.Tip
    , label : String
    , value : Maybe String
    , sub : String
    , accent : String
    }


{-| The only way a number reaches the screen. A `Nothing` value renders
the "awaiting evidence" state, which is why no caller can accidentally
substitute a zero for an unmeasured quantity.
-}
viewMetric : Tip.Handlers Msg -> MetricSpec -> Html Msg
viewMetric tips spec =
    div [ class ("metric " ++ spec.accent) ]
        [ div [ class "metric-label" ]
            [ Tip.view tips Tip.AlignStart spec.tip [ text spec.label ] ]
        , case spec.value of
            Just value ->
                div [ class "metric-value" ] [ text value ]

            Nothing ->
                div [ class "metric-value is-unknown" ] [ text Format.awaiting ]
        , div [ class "metric-sub" ] [ text spec.sub ]
        ]



-- CHAMPION GATE


{-| The bar behind every gate figure: raw rate, published bound, and the
target line. Shared by the per-cell gate and the broad overall gate so
the two cannot drift into meaning different things visually.
-}
gateMeter : Float -> Gate.Verdict -> Float -> Float -> Html msg
gateMeter target verdict rateFraction boundFraction =
    div [ class "gate-meter" ]
        [ div
            [ class "gate-meter-rate"
            , Attr.style "width" (Format.decimal 2 (clamp 0 1 rateFraction * 100) ++ "%")
            ]
            []
        , div
            [ class
                ("gate-meter-bound"
                    ++ (case verdict of
                            Gate.Passing _ ->
                                ""

                            _ ->
                                " is-short"
                       )
                )
            , Attr.style "width" (Format.decimal 2 (clamp 0 1 boundFraction * 100) ++ "%")
            ]
            []
        , div
            [ class "gate-meter-target"
            , Attr.style "left" (Format.decimal 2 (clamp 0 1 target * 100) ++ "%")
            ]
            []
        ]


gateLegend : Maybe Api.Scoring -> Float -> Html msg
gateLegend scoring target =
    div [ class "gate-legend" ]
        [ span []
            [ span [ class "swatch", Attr.style "background" "#4fd6e0" ] []
            , text "Wilson lower bound"
            ]
        , span []
            [ span [ class "swatch", Attr.style "background" "rgba(79,214,224,0.3)" ] []
            , text ("raw " ++ Scoring.rateLabel scoring)
            ]
        , span []
            [ span [ class "swatch", Attr.style "background" "#f4ead6" ] []
            , text ("gate target " ++ Format.percent target)
            ]
        ]


{-| The headline gate. Which gate that is depends on what the run is
being judged on, and the two are never shown at once: a staged run is
gated cell by cell, a broad run on one overall balanced result.
-}
viewGate : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewGate tips model status =
    if Api.isBroad status.curriculum then
        viewOverallGate tips model status

    else
        viewChampionGate tips model status


{-| The one line that keeps the scoring rule from being read as the
gate, rendered in the gate panel's head because that is exactly where
the two would be confused. Nothing is added when the run's fitness is
the original combat rule, which nobody mistakes for a different measure.
-}
scoringNote : Tip.Handlers Msg -> Api.Status -> List (Html Msg)
scoringNote tips status =
    case Scoring.gateNote status.scoring of
        Nothing ->
            []

        Just note ->
            [ span [ class "panel-note" ]
                [ Tip.view tips Tip.AlignEnd Copy.gateCriterion [ text note ] ]
            ]


viewChampionGate : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewChampionGate tips model status =
    let
        champion =
            status.champion

        target =
            status.curriculum.target

        verdict =
            Gate.championVerdict target champion

        ( rateClass, rateText ) =
            case champion.winRate of
                Just rate ->
                    ( case verdict of
                        Gate.Passing _ ->
                            "gate-rate gate-pass"

                        _ ->
                            "gate-rate gate-fail"
                    , Format.percent1 rate
                    )

                Nothing ->
                    ( "gate-rate is-unknown", Format.awaiting )

        boundFraction =
            champion.lowerBound |> Maybe.withDefault 0

        rateFraction =
            champion.winRate |> Maybe.withDefault 0

        verdictLine =
            case verdict of
                Gate.NoEvidence ->
                    "No audit games have been played for this champion yet. The gate cannot be judged, and this is not a score of zero."

                Gate.Passing bound ->
                    "Wilson lower bound " ++ Format.percent1 bound ++ " clears the " ++ Format.percent target ++ " target on this panel."

                Gate.Short bound ->
                    "Wilson lower bound " ++ Format.percent1 bound ++ " is below the " ++ Format.percent target ++ " target, so this panel does not yet support a promotion."

                Gate.RateOnly rate ->
                    "The trainer published a raw rate of " ++ Format.percent1 rate ++ " but no confidence bound, so the gate is undecided. Promotion is judged on the bound."
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            ([ Tip.view tips
                Tip.AlignStart
                (Tip.detail (Copy.championRate status.scoring) (Scoring.explainGate status.scoring))
                [ h2 [] [ text ("Champion fresh audit " ++ Scoring.rateLabel status.scoring) ] ]
             , span [ class "panel-note" ] [ text "Audit evidence only. Not population training play." ]
             ]
                ++ scoringNote tips status
            )
        , div [ class "gate" ]
            [ div [ class "gate-figure" ]
                [ div [ class rateClass ] [ text rateText ]
                , div [ class "gate-denominator" ]
                    [ text
                        (if champion.validatedGames > 0 then
                            "over "
                                ++ Format.fraction champion.validatedWins champion.validatedGames
                                ++ " fresh audit games"

                         else
                            "no audit games on this champion's panel yet"
                        )
                    ]
                , gateMeter target verdict rateFraction boundFraction
                , gateLegend status.scoring target
                , p [ class "prose" ] [ text verdictLine ]
                , p [ class "prose" ] [ text (demandLine status) ]
                ]
            , div [ class "gate-side" ]
                [ div [ class "metrics" ]
                    [ viewMetric tips
                        { tip = Copy.championLowerBound status.scoring
                        , label = "Lower bound"
                        , value = Maybe.map Format.percent1 champion.lowerBound
                        , sub = "gate target " ++ Format.percent target
                        , accent =
                            case verdict of
                                Gate.Passing _ ->
                                    "metric-cyan"

                                Gate.Short _ ->
                                    "metric-amber"

                                _ ->
                                    ""
                        }
                    , viewMetric tips
                        { tip = Copy.championGames status.scoring
                        , label = "Audit sample"
                        , value =
                            if champion.validatedGames > 0 then
                                Just (Format.fraction champion.validatedWins champion.validatedGames)

                            else
                                Nothing
                        , sub = Scoring.successPlural status.scoring ++ " over predeclared panel games"
                        , accent = ""
                        }
                    , viewMetric tips
                        { tip = Copy.championId
                        , label = "Champion"
                        , value =
                            if String.isEmpty champion.id then
                                Nothing

                            else
                                Just (Format.shortId champion.id)
                        , sub = "evidence resets when this changes"
                        , accent = ""
                        }
                    , viewMetric tips
                        { tip = Copy.championStructure
                        , label = "Topology"
                        , value = Just (Format.count champion.nodes ++ " / " ++ Format.count champion.connections)
                        , sub = Format.count champion.hiddenNodes ++ " hidden, evolved"
                        , accent = ""
                        }
                    , viewMetric tips
                        { tip = Copy.observedNeeded status.scoring
                        , label = Format.capitalise (Scoring.successPlural status.scoring) ++ " needed"
                        , value =
                            Gate.winsNeeded Gate.z95 target status.audit.panel
                                |> Maybe.map (\wins -> Format.fraction wins status.audit.panel)
                        , sub = "observed, to clear the bound"
                        , accent = "metric-amber"
                        }
                    , viewMetric tips
                        { tip = Copy.auditPanel status.scoring
                        , label = "Audit panel"
                        , value =
                            if status.audit.panel > 0 then
                                Just (String.fromInt status.audit.panel)

                            else
                                Nothing
                        , sub =
                            String.fromInt status.audit.maxLosses
                                ++ " losses allowed, abandoned on the "
                                ++ ordinal (status.audit.maxLosses + 1)
                        , accent = ""
                        }
                    , viewMetric tips
                        { tip = Copy.worstCell
                        , label = "Worst cell"
                        , value = Maybe.map Format.percent1 champion.worstCellLowerBound
                        , sub = "weakest cell's bound"
                        , accent = ""
                        }
                    ]
                , p [ class "prose" ]
                    [ text
                        (if isStale model then
                            "These figures are from a stale snapshot; see the notice above."

                         else
                            "These figures describe one champion on one predeclared panel at stage "
                                ++ String.fromInt status.curriculum.stage
                                ++ ". They say nothing about matchups outside that panel."
                        )
                    ]
                ]
            ]
        ]



{-| The broad run's headline: one aggregate win rate over a balanced
held-out distribution.

Everything on this panel is worded to keep three things from being
confused with one another: the aggregate figure being gated, the two
independent rounds that have to clear it, and the per-hull diagnostics
that show where the aggregate is hiding a weakness. The per-cell
language used by the staged gate does not appear here at all, because
nothing on this panel is a per-cell claim.

-}
viewOverallGate : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewOverallGate tips model status =
    let
        -- The full reasoning lives behind the heading's explanation trigger
        -- rather than under it. Printed in full it ran to a dozen paragraphs
        -- and pushed every number below the fold, which is how a dashboard
        -- stops being read at all.
        gateTip =
            Tip.detail (Copy.overallGate status.scoring)
                (Gate.explainBroad status.scoring status.curriculum status.overall status.shipPerformance
                    ++ Scoring.explainGate status.scoring
                )

        heading =
            "Overall balanced " ++ Scoring.rateLabel status.scoring
    in
    case status.overall of
        Nothing ->
            div [ class "panel" ]
                [ div [ class "panel-head" ]
                    [ Tip.view tips Tip.AlignStart gateTip [ h2 [] [ text heading ] ]
                    , span [ class "panel-note" ] [ text "any ship versus any ship, Awesome cyborgs" ]
                    ]
                , div [ class "placeholder" ]
                    [ Html.strong [] [ text Format.awaiting ]
                    , span [] [ text "The trainer has not published an overall balanced panel result yet. This is an absence of evidence, not a score of zero." ]
                    ]
                ]

        Just overall ->
            let
                verdict =
                    Gate.overallVerdict overall

                ( rateClass, rateText ) =
                    case overall.winRate of
                        Just rate ->
                            ( case verdict of
                                Gate.Passing _ ->
                                    "gate-rate gate-pass"

                                _ ->
                                    "gate-rate gate-fail"
                            , Format.percent1 rate
                            )

                        Nothing ->
                            ( "gate-rate is-unknown", Format.awaiting )

                verdictLine =
                    case verdict of
                        Gate.NoEvidence ->
                            "No games have been played on this round's balanced panel yet, so the overall gate cannot be judged. This is not a score of zero."

                        Gate.Passing bound ->
                            "Wilson lower bound "
                                ++ Format.percent1 bound
                                ++ " clears the "
                                ++ Format.percent overall.target
                                ++ " overall target on this round's panel."

                        Gate.Short bound ->
                            "Wilson lower bound "
                                ++ Format.percent1 bound
                                ++ " is below the "
                                ++ Format.percent overall.target
                                ++ " overall target, so this round does not support a pass."

                        Gate.RateOnly rate ->
                            "The trainer published a raw rate of "
                                ++ Format.percent1 rate
                                ++ " but no confidence bound, so the gate is undecided. It is judged on the bound."

                roundText =
                    case overall.round of
                        Just round ->
                            Api.overallRoundLabel round ++ " round in flight"

                        Nothing ->
                            "no round in flight"
            in
            div [ class "panel" ]
                [ div [ class "panel-head" ]
                    ([ Tip.view tips Tip.AlignStart gateTip [ h2 [] [ text heading ] ]
                     , span [ class "panel-note" ]
                         [ text ("any ship versus any ship, Awesome cyborgs \u{00B7} " ++ roundText) ]
                     ]
                        ++ scoringNote tips status
                    )
                , div [ class "gate" ]
                    [ div [ class "gate-figure" ]
                        [ div [ class rateClass ] [ text rateText ]
                        , div [ class "gate-denominator" ]
                            [ text
                                (if overall.games > 0 then
                                    "over "
                                        ++ Format.fraction overall.wins overall.games
                                        ++ " games on the balanced held-out panel"

                                 else
                                    "no games played on this round's panel yet"
                                )
                            ]
                        , gateMeter overall.target
                            verdict
                            (Maybe.withDefault 0 overall.winRate)
                            (Maybe.withDefault 0 overall.lowerBound)
                        , gateLegend status.scoring overall.target
                        , p [ class "prose" ] [ text verdictLine ]
                        , p [ class "prose" ]
                            [ text
                                ("An aggregate over a balanced held-out panel, not a promise about every matchup. "
                                    ++ overallDemandLine status.scoring overall
                                )
                            ]
                        ]
                    , div [ class "gate-side" ]
                        [ div [ class "metrics" ]
                            [ viewMetric tips
                                { tip = Copy.overallGate status.scoring
                                , label = "Lower bound"
                                , value = Maybe.map Format.percent1 overall.lowerBound
                                , sub = "overall target " ++ Format.percent overall.target
                                , accent =
                                    case verdict of
                                        Gate.Passing _ ->
                                            "metric-cyan"

                                        Gate.Short _ ->
                                            "metric-amber"

                                        _ ->
                                            ""
                                }
                            , viewMetric tips
                                { tip = Copy.overallPanel
                                , label = "Panel sample"
                                , value =
                                    if overall.games > 0 then
                                        Just (Format.fraction overall.wins overall.games)

                                    else
                                        Nothing
                                , sub =
                                    Scoring.successPlural status.scoring
                                        ++ " over "
                                        ++ String.fromInt overall.panel
                                        ++ " predeclared games, "
                                        ++ String.fromInt overall.pairs
                                        ++ " pairs in both seats"
                                , accent = ""
                                }
                            , viewMetric tips
                                { tip = Copy.overallRound
                                , label = "Round"
                                , value = Maybe.map Api.overallRoundLabel overall.round
                                , sub =
                                    "attempt "
                                        ++ String.fromInt overall.attempt
                                        ++ ", champion frozen throughout"
                                , accent = ""
                                }
                            , viewMetric tips
                                { tip = Copy.championId
                                , label = "Champion"
                                , value =
                                    if String.isEmpty overall.championId then
                                        Nothing

                                    else
                                        Just (Format.shortId overall.championId)
                                , sub = "evidence resets when this changes"
                                , accent = ""
                                }
                            , viewMetric tips
                                { tip = Copy.observedNeeded status.scoring
                                , label = Format.capitalise (Scoring.successPlural status.scoring) ++ " needed"
                                , value =
                                    Gate.winsNeeded Gate.z95 overall.target overall.panel
                                        |> Maybe.map (\wins -> Format.fraction wins overall.panel)
                                , sub = "observed, to clear the bound"
                                , accent = "metric-amber"
                                }
                            , roundMetric tips Copy.overallRound "Audit round" overall.target overall.audit
                            , roundMetric tips Copy.overallRound "Confirm round" overall.target overall.confirm
                            ]
                        , p [ class "prose" ]
                            [ text
                                (if isStale model then
                                    "These figures are from a stale snapshot; see the notice above."

                                 else if overall.passed then
                                    "Both rounds have cleared the overall target for this champion. That is an aggregate result over the balanced distribution, not a per-matchup guarantee; the per-hull table below shows where it is weakest."

                                 else
                                    "Passes only after the audit round and then an independent confirm round. Neither round's evidence is added to the other's."
                                )
                            ]
                        ]
                    ]
                ]


{-| One round's standing, shown beside the other so a passed audit can
never be mistaken for a passed gate.
-}
roundMetric : Tip.Handlers Msg -> Tip.Tip -> String -> Float -> Api.RoundResult -> Html Msg
roundMetric tips tip label target round =
    viewMetric tips
        { tip = tip
        , label = label
        , value =
            if round.games > 0 then
                Maybe.map Format.percent1 round.lowerBound

            else
                Nothing
        , sub =
            if round.games > 0 then
                Format.fraction round.wins round.games
                    ++ " games, "
                    ++ (if round.passed then
                            "cleared " ++ Format.percent target

                        else
                            "not cleared"
                       )

            else
                "not played on this attempt"
        , accent =
            if round.games > 0 && round.passed then
                "metric-cyan"

            else if round.games > 0 then
                "metric-amber"

            else
                ""
        }


{-| What the overall gate actually demands on its panel, in observed
successes rather than in the target percentage, for the same reason the
staged gate spells it out: a bound floor of 80% is not 80 in 100.

The noun is the run's own, because under a crew-lead gate the count the
panel has to post is a count of leads and calling it a win count would
name evidence the run never gathered.

-}
overallDemandLine : Maybe Api.Scoring -> Api.Overall -> String
overallDemandLine scoring overall =
    case Gate.winsNeeded Gate.z95 overall.target overall.panel of
        Just wins ->
            "On the balanced panel of "
                ++ String.fromInt overall.panel
                ++ " games, clearing the "
                ++ Format.percent overall.target
                ++ " Wilson lower bound takes "
                ++ String.fromInt wins
                ++ " observed "
                ++ Scoring.successPlural scoring
                ++ " ("
                ++ Format.percent1 (toFloat wins / toFloat overall.panel)
                ++ "), not "
                ++ String.fromInt (ceiling (overall.target * toFloat overall.panel))
                ++ ". The same has to happen twice, on two independent rounds."

        Nothing ->
            "No overall panel size has been published yet, so the observed count the gate demands cannot be stated."


{-| Spells out what the gate actually demands on this panel. A target of
80% is a floor on the Wilson bound, so the observed score a candidate
has to post is meaningfully higher, and saying only "80%" invites the
reader to think 80 of 100 would pass.
-}
demandLine : Api.Status -> String
demandLine status =
    let
        panelSize =
            status.audit.panel

        target =
            status.curriculum.target
    in
    case Gate.winsNeeded Gate.z95 target panelSize of
        Just wins ->
            "On the predeclared panel of "
                ++ String.fromInt panelSize
                ++ ", clearing the "
                ++ Format.percent target
                ++ " Wilson lower bound takes "
                ++ String.fromInt wins
                ++ " observed "
                ++ Scoring.successPlural status.scoring
                ++ " ("
                ++ Format.percent1 (toFloat wins / toFloat panelSize)
                ++ "), not "
                ++ String.fromInt (ceiling (target * toFloat panelSize))
                ++ ". That leaves "
                ++ String.fromInt status.audit.maxLosses
                ++ " "
                ++ Scoring.nonSuccessPhrase status.scoring
                ++ " to spare, so the attempt survives "
                ++ String.fromInt status.audit.maxLosses
                ++ " and is abandoned on the "
                ++ ordinal (status.audit.maxLosses + 1)
                ++ ", the point at which the target became unreachable."

        Nothing ->
            "No audit panel size has been published yet, so the observed count the gate demands cannot be stated."


{-| The loss cap is the number of losses an attempt can absorb and still
reach the target, so the cap itself is survivable and the abort happens
on the next one.
-}
ordinal : Int -> String
ordinal n =
    let
        suffix =
            if modBy 100 n >= 11 && modBy 100 n <= 13 then
                "th"

            else
                case modBy 10 n of
                    1 ->
                        "st"

                    2 ->
                        "nd"

                    3 ->
                        "rd"

                    _ ->
                        "th"
    in
    String.fromInt n ++ suffix



-- VITALS


viewVitals : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewVitals tips model status =
    panel tips Copy.vitals
        "Run vitals"
        [ div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.generation
                , label = "Generation"
                , value = Just (Format.count status.generation)
                , sub = "bred and scored"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.episodes
                , label = "Episodes"
                , value = Just (Format.count status.episodes)
                , sub = "training plus audit"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.episodesPerSecond
                , label = "Throughput"
                , value =
                    if status.episodesPerSecond > 0 then
                        Just (Format.decimal 2 status.episodesPerSecond)

                    else
                        Nothing
                , sub = "episodes per second"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.elapsed
                , label = "Elapsed"
                , value = Just (Format.duration status.elapsedSeconds)
                , sub = "summed across resumes"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.unresolved status.scoring
                , label = "Unresolved"
                , value = Just (Format.count status.episodesUnresolved)
                , sub =
                    if status.episodes > 0 then
                        Format.percent1 (toFloat status.episodesUnresolved / toFloat status.episodes)
                            ++ " "
                            ++ Scoring.unresolvedNote status.scoring

                    else
                        Scoring.unresolvedNote status.scoring
                , accent =
                    if status.episodes > 0 && toFloat status.episodesUnresolved > 0.25 * toFloat status.episodes then
                        "metric-amber"

                    else
                        ""
                }
            , viewMetric tips
                { tip = Tip.detail Copy.fitnessRule (Scoring.explain status.scoring status.resources)
                , label = "Fitness"
                , value = Just (Scoring.label status.scoring)
                , sub = Scoring.formula status.scoring
                , accent =
                    case Maybe.map .fitness status.scoring of
                        Just (Api.CrewRatio _) ->
                            "metric-cyan"

                        _ ->
                            ""
                }
            , viewMetric tips
                { tip = Copy.fightLimit
                , label = "Fight limit"
                , value = Scoring.fightLimit status.resources
                , sub = Scoring.limitNote status.scoring
                , accent = ""
                }
            , viewMetric tips
                { tip = Tip.detail Copy.noDamagePenalty (Scoring.penaltyExplain status.scoring)
                , label = "No-damage penalty"
                , value = Scoring.penaltyLabel status.scoring
                , sub = Scoring.penaltyNote status.scoring
                , accent =
                    case Maybe.map .noDamagePenalty status.scoring of
                        Just (Api.PenaltyOf _) ->
                            "metric-amber"

                        _ ->
                            ""
                }
            , viewMetric tips
                { tip = Copy.combatVictories
                , label = "Combat victories"
                , value = Scoring.combatVictoriesValue status.combatVictories
                , sub = Scoring.combatVictoriesNote status.combatVictories
                , accent = ""
                }
            ]
        , p [ class "prose" ]
            [ text
                ("Polling "
                    ++ statusUrl
                    ++ " every "
                    ++ Format.decimal 0 (pollMillis / 1000)
                    ++ " seconds"
                    ++ (if model.visible then
                            "."

                        else
                            ", paused while this tab is hidden."
                       )
                )
            ]
        ]



-- CURRICULUM


viewCurriculum : Tip.Handlers Msg -> Api.Status -> Html Msg
viewCurriculum tips status =
    let
        curriculum =
            status.curriculum

        target =
            curriculum.target

        broad =
            Api.isBroad curriculum

        blockers =
            Gate.analyse target status.matchups

        -- In broad mode this panel earns one sentence on screen. Its subject
        -- is the cells, the gate is explained on the gate panel, and the rest
        -- of the reasoning sits behind the heading's explanation trigger.
        cellDetail =
            Gate.explainBroadCells curriculum status.matchups

        reasons =
            if broad then
                List.take 1 cellDetail

            else
                Gate.explain target curriculum status.matchups

        weakest =
            Gate.weakestFirst target status.matchups
                |> List.filter (\m -> m.status /= Api.Mastered)
                |> List.take 5
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips
                Tip.AlignStart
                (if broad then
                    Tip.detail (Copy.broadMode status.scoring) (List.drop 1 cellDetail)

                 else
                    Copy.expansionBlocked
                )
                [ h2 []
                    [ text
                        (if broad then
                            "Curriculum: all ships active"

                         else
                            "Curriculum and why it is or is not expanding"
                        )
                    ]
                ]
            , span [ class "panel-note" ]
                [ text
                    (if broad then
                        "overall balanced target, no per-matchup gate"

                     else
                        "stage " ++ String.fromInt curriculum.stage
                    )
                ]
            ]
        , div [ class "metrics" ]
            [ viewMetric tips
                { tip =
                    if broad then
                        Copy.broadMode status.scoring

                    else
                        Copy.stage
                , label =
                    if broad then
                        "Active board"

                    else
                        "Stage"
                , value =
                    if broad then
                        Just
                            (String.fromInt (List.length curriculum.ourRoster)
                                ++ " \u{00D7} "
                                ++ String.fromInt (List.length curriculum.opponentRoster)
                            )

                    else
                        Just (String.fromInt curriculum.stage)
                , sub =
                    if broad then
                        "every ship of ours against every opponent, at once"

                    else
                        String.fromInt (List.length curriculum.ourRoster)
                            ++ " of ours \u{00D7} "
                            ++ String.fromInt (List.length curriculum.opponentRoster)
                            ++ " opponents"
                , accent =
                    if broad then
                        "metric-cyan"

                    else
                        ""
                }
            , viewMetric tips
                { tip = Copy.matchupCoverage
                , label =
                    if broad then
                        "Cells cleared"

                    else
                        "Mastered cells"
                , value = Just (Format.fraction curriculum.masteredMatchups curriculum.totalMatchups)
                , sub =
                    if broad then
                        "diagnostic only, gates nothing in this mode"

                    else
                        "each cell gated on its own evidence"
                , accent =
                    if broad then
                        ""

                    else if curriculum.totalMatchups > 0 && curriculum.masteredMatchups == curriculum.totalMatchups then
                        "metric-cyan"

                    else
                        ""
                }
            , viewMetric tips
                { tip = Copy.unevaluated
                , label = "Unevaluated"
                , value = Just (String.fromInt blockers.unseen)
                , sub =
                    if broad then
                        "cells with no gate games; a blind spot, not a blocker"

                    else
                        "active cells with no audit games"
                , accent =
                    if broad then
                        ""

                    else if blockers.unseen > 0 then
                        "metric-amber"

                    else
                        ""
                }
            , viewMetric tips
                { tip =
                    if broad then
                        Copy.overallGate status.scoring

                    else
                        Copy.nextExpansion
                , label =
                    if broad then
                        "Overall target"

                    else
                        "Next addition"
                , value =
                    if broad then
                        Just (Format.percent curriculum.target)

                    else
                        case ( curriculum.nextSide, curriculum.nextShip ) of
                            ( Api.Complete, _ ) ->
                                Just "complete"

                            ( _, Just ship ) ->
                                Just ship

                            ( Api.UnknownSide _, Nothing ) ->
                                Nothing

                            ( _, Nothing ) ->
                                Nothing
                , sub =
                    if broad then
                        "overall, on a balanced held-out panel"

                    else
                        Api.nextSideLabel curriculum.nextSide
                , accent = ""
                }
            ]
        , div [ Attr.style "margin-top" "14px" ]
            (List.map (\line -> p [ class "prose" ] [ text line ]) reasons)
        , if List.isEmpty weakest then
            text ""

          else
            div [ Attr.style "margin-top" "14px" ]
                [ h3 []
                    [ text
                        (if broad then
                            "Weakest cells on the board"

                         else
                            "Cells holding the gate up"
                        )
                    ]
                , p [ class "prose", Attr.style "margin-top" "4px" ]
                    [ text
                        (if broad then
                            "Diagnostics. None of these blocks the overall gate; they show where an aggregate pass would be thinnest."

                         else
                            "Each of these has to clear the target on its own fresh audit evidence before the roster grows."
                        )
                    ]
                , div [ class "alloc", Attr.style "margin-top" "8px" ]
                    (List.map (viewWeakCell target) weakest)
                ]
        , div [ Attr.style "margin-top" "16px" ]
            [ h3 []
                [ text
                    (if broad then
                        "Rosters, all active"

                     else
                        "Rosters in frozen expansion order"
                    )
                ]
            , div [ Attr.style "margin-top" "8px" ]
                [ Tip.view tips Tip.AlignStart Copy.rosterOurs [ span [ class "eyebrow" ] [ text "Ours" ] ] ]
            , div [ class "chip-row", Attr.style "margin-top" "6px" ] (rosterChips curriculum.ourRoster)
            , div [ Attr.style "margin-top" "12px" ]
                [ Tip.view tips Tip.AlignStart Copy.rosterTheirs [ span [ class "eyebrow" ] [ text "Opponents" ] ] ]
            , div [ class "chip-row", Attr.style "margin-top" "6px" ] (rosterChips curriculum.opponentRoster)
            , div [ Attr.style "margin-top" "12px" ]
                [ Tip.view tips Tip.AlignStart Copy.opponentTypes [ span [ class "eyebrow" ] [ text "Opponent types" ] ] ]
            , div [ class "chip-row", Attr.style "margin-top" "6px" ]
                (if List.isEmpty curriculum.opponentTypes then
                    [ span [ class "chip" ] [ text "none reported" ] ]

                 else
                    List.map (\kind -> span [ class "chip" ] [ text (Api.opponentTypeLabel kind) ]) curriculum.opponentTypes
                )
            ]
        , dl [ class "deflist", Attr.style "margin-top" "16px" ]
            ([ dt [] [ Tip.view tips Tip.AlignStart Copy.ladderPhase [ text "Ladder" ] ]
             , dd [] [ text (Api.ladderLabel curriculum.ladder) ]
             , dt [] [ Tip.view tips Tip.AlignStart Copy.opponentRevision [ text "Opponent rev" ] ]
             , dd []
                [ text
                    ("r"
                        ++ String.fromInt curriculum.opponentRevision
                        ++ (case curriculum.opponentFingerprint of
                                Just fingerprint ->
                                    " \u{00B7} " ++ Format.shortId fingerprint

                                Nothing ->
                                    " \u{00B7} cyborg only, no frozen model yet"
                           )
                    )
                ]
             , dt [] [ Tip.view tips Tip.AlignStart Copy.readiness [ text "Readiness" ] ]
             , dd []
                [ text
                    ((case status.readiness.lastRate of
                        Just rate ->
                            Format.percent1 rate
                                ++ " "
                                ++ Scoring.rateLabel status.scoring
                                ++ " over "
                                ++ String.fromInt status.readiness.games
                                ++ " games, needs "
                                ++ Format.percent status.readiness.threshold

                        Nothing ->
                            "not yet screened \u{00B7} "
                                ++ String.fromInt status.readiness.games
                                ++ " games every "
                                ++ String.fromInt status.readiness.period
                                ++ " generations, needs "
                                ++ Format.percent status.readiness.threshold
                                ++ " "
                                ++ Scoring.rateLabel status.scoring
                     )
                        ++ " \u{00B7} screening probe, never gate evidence"
                        ++ (case status.readiness.purpose of
                                Just purpose ->
                                    " \u{00B7} " ++ purpose

                                Nothing ->
                                    ""
                           )
                    )
                ]
             ]
                ++ regressionRow tips status
            )
        ]


{-| One row, and only when the trainer actually reports the block. An
engine that does not run regression rehearsal should not grow an empty
placeholder for it.
-}
regressionRow : Tip.Handlers Msg -> Api.Status -> List (Html Msg)
regressionRow tips status =
    case status.regression of
        Nothing ->
            []

        Just regression ->
            let
                phaseText =
                    if regression.sweeping then
                        "sweeping now"

                    else if regression.rehearsing > 0 then
                        "rehearsing " ++ String.fromInt regression.rehearsing ++ " cells"

                    else if regression.active then
                        "armed"

                    else
                        "idle"

                resultText =
                    if regression.lastSwept <= 0 then
                        "no sweep yet"

                    else if regression.lastFailed > 0 then
                        "last sweep at generation "
                            ++ String.fromInt regression.lastSwept
                            ++ " lost "
                            ++ String.fromInt regression.lastFailed
                            ++ " previously mastered cells"

                    else
                        "last sweep at generation "
                            ++ String.fromInt regression.lastSwept
                            ++ " held every mastered cell"
            in
            [ dt [] [ Tip.view tips Tip.AlignStart (Copy.regression status.scoring) [ text "Regression" ] ]
            , dd [] [ text (phaseText ++ " \u{00B7} " ++ resultText) ]
            ]


rosterChips : List String -> List (Html Msg)
rosterChips roster =
    case roster of
        [] ->
            [ span [ class "chip" ] [ text "none reported" ] ]

        first :: rest ->
            span [ class "chip chip-seed" ] [ text (first ++ " \u{00B7} seed") ]
                :: List.indexedMap
                    (\i name ->
                        span
                            [ class
                                (if i == List.length rest - 1 then
                                    "chip chip-new"

                                 else
                                    "chip"
                                )
                            ]
                            [ text name ]
                    )
                    rest


viewWeakCell : Float -> Api.Matchup -> Html Msg
viewWeakCell target matchup =
    let
        measured =
            case matchup.lowerBound of
                Just bound ->
                    Just bound

                Nothing ->
                    matchup.winRate

        width =
            case measured of
                Just value ->
                    clamp 0 1 value * 100

                Nothing ->
                    0
    in
    div []
        [ div [ class "alloc-name" ]
            [ span [ class "who" ] [ text ("our " ++ matchup.us ++ " vs their " ++ matchup.them) ]
            , span [ class "chip" ] [ text (Api.matchupStatusLabel matchup.status) ]

            -- A cell with no audit evidence has usually still been played
            -- hard in training. Showing that here stops the bar reading as
            -- an untouched matchup.
            , if matchup.trainingGames > 0 then
                span [ class "chip" ]
                    [ text (Format.decimal 0 matchup.trainingGames ++ " training") ]

              else
                text ""
            ]
        , div [ class "alloc-row" ]
            [ div [ class "alloc-bar" ]
                [ div
                    [ class "alloc-fill"
                    , Attr.style "width" (Format.decimal 2 width ++ "%")
                    , Attr.style "background" (Heatmap.cellFill target measured)
                    ]
                    []
                ]
            , span [ class "alloc-share" ]
                [ text
                    (case measured of
                        Just value ->
                            Format.percent1 value

                        Nothing ->
                            "no audit"
                    )
                ]
            ]
        ]



-- LADDER


{-| The panel in the ladder's slot. A staged run gets the rung ladder; a
broad run has no rungs to climb, so it gets the mode's own summary
instead of a ladder that would imply an expansion that is not happening.
-}
viewProgression : Tip.Handlers Msg -> Api.Status -> Html Msg
viewProgression tips status =
    if Api.isBroad status.curriculum then
        viewBroadMode tips status

    else
        viewLadder tips status


viewBroadMode : Tip.Handlers Msg -> Api.Status -> Html Msg
viewBroadMode tips status =
    let
        curriculum =
            status.curriculum

        ours =
            List.length curriculum.ourRoster

        theirs =
            List.length curriculum.opponentRoster

        samplerRows =
            case status.sampler of
                Nothing ->
                    []

                Just sampler ->
                    [ dt [] [ Tip.view tips Tip.AlignStart Copy.samplerCoverage [ text "Training panel" ] ]
                    , dd []
                        [ text
                            (case sampler.panel of
                                Just episodes ->
                                    String.fromInt episodes ++ " shared episodes per generation, same panel for every genome"

                                Nothing ->
                                    "size not reported"
                            )
                        ]
                    , dt [] [ Tip.view tips Tip.AlignStart Copy.samplerCoverage [ text "Balanced share" ] ]
                    , dd []
                        [ text
                            (case sampler.balancedShare of
                                Just share ->
                                    Format.percent1 share ++ " of that panel drawn by the balanced rotation, the rest drawn adaptively"

                                Nothing ->
                                    Format.awaiting
                            )
                        ]
                    , dt [] [ Tip.view tips Tip.AlignStart Copy.samplerCoverage [ text "Rotation" ] ]
                    , dd []
                        [ text
                            (case ( sampler.cursor, sampler.tour ) of
                                ( Just cursor, Just tour ) ->
                                    "cursor at "
                                        ++ Format.count cursor
                                        ++ ", "
                                        ++ String.fromInt tour
                                        ++ " full tours of the board completed"

                                ( Just cursor, Nothing ) ->
                                    "cursor at " ++ Format.count cursor ++ ", completed tours not reported"

                                ( Nothing, Just tour ) ->
                                    String.fromInt tour ++ " full tours completed, cursor not reported"

                                ( Nothing, Nothing ) ->
                                    Format.awaiting
                            )
                        ]
                    ]

        provenanceRows =
            case curriculum.originRunId of
                Nothing ->
                    []

                Just origin ->
                    -- One row, not three. The whole migration is a single fact.
                    [ dt [] [ Tip.view tips Tip.AlignStart Copy.originRun [ text "Carried over" ] ]
                    , dd []
                        [ text
                            (origin
                                ++ (case curriculum.originGeneration of
                                        Just generation ->
                                            " \u{00B7} g" ++ String.fromInt generation

                                        Nothing ->
                                            ""
                                   )
                                ++ (case curriculum.originFingerprint of
                                        Just fingerprint ->
                                            " \u{00B7} " ++ Format.shortId fingerprint

                                        Nothing ->
                                            ""
                                   )
                                ++ (case curriculum.transitionReason of
                                        Just reason ->
                                            " \u{00B7} " ++ reason

                                        Nothing ->
                                            ""
                                   )
                            )
                        ]
                    ]
    in
    panel tips
        (Tip.detail (Copy.broadMode status.scoring) (List.drop 1 (Gate.explainBroadBoard curriculum)))
        "Any ship versus any ship"
        [ div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.broadMode status.scoring
                , label = "Active board"
                , value = Just (String.fromInt ours ++ " \u{00D7} " ++ String.fromInt theirs)
                , sub = Format.count (ours * theirs) ++ " ordered matchups, all active at once"
                , accent = "metric-cyan"
                }
            , viewMetric tips
                { tip = Copy.broadMode status.scoring
                , label = "Evaluation"
                , value = Just "overall"
                , sub = Api.evaluationScopeLabel curriculum.evaluationScope
                , accent = ""
                }
            ]
        , p [ class "prose", Attr.style "margin-top" "12px" ]
            [ text (Maybe.withDefault "" (List.head (Gate.explainBroadBoard curriculum))) ]
        , dl [ class "deflist", Attr.style "margin-top" "16px" ]
            ([ dt [] [ Tip.view tips Tip.AlignStart Copy.ladderPhase [ text "Ladder" ] ]
             , dd [] [ text (Api.ladderLabel curriculum.ladder) ]
             , dt [] [ Tip.view tips Tip.AlignStart Copy.opponentTypes [ text "Opponents" ] ]
             , dd []
                [ text
                    (if List.isEmpty curriculum.opponentTypes then
                        "not reported"

                     else
                        String.join ", " (List.map Api.opponentTypeLabel curriculum.opponentTypes)
                            ++ (if curriculum.selfPlayIsGated then
                                    " \u{00B7} frozen model opponents gated until the overall target is cleared"

                                else
                                    ""
                               )
                    )
                ]
             ]
                ++ samplerRows
                ++ provenanceRows
            )
        ]


{-| Per-hull blind spots on the current round's balanced evidence.

Both groupings count our champion's own wins. "When piloting" groups
them by the hull our champion flew; "when facing" groups the same wins
by the hull it flew against, so a weak row there means our champion
loses to that hull rather than that the hull is losing. Nothing here
gates anything, and no hull has a minimum to meet: the table exists
because an aggregate pass can hide a hull it never beats.

-}
viewShipPerformance : Tip.Handlers Msg -> Api.Status -> Html Msg
viewShipPerformance tips status =
    let
        sources =
            status.shipPerformance
                |> List.map .source
                |> List.foldl
                    (\source acc ->
                        if List.member source acc then
                            acc

                        else
                            acc ++ [ source ]
                    )
                    []

        sourceNote =
            case sources of
                [] ->
                    "no evidence published"

                _ ->
                    String.join ", " (List.map Api.evidenceSourceLabel sources)

        diagnosticOnly =
            not (List.any Api.evidenceIsGate sources) && not (List.isEmpty sources)

        section_ seat heading caption =
            let
                rows =
                    status.shipPerformance
                        |> List.filter (\row -> row.side == seat)
                        |> Gate.blindSpots
            in
            if List.isEmpty rows then
                []

            else
                let
                    games =
                        rows |> List.map .games |> List.sum

                    measured =
                        rows |> List.filter (\row -> row.games > 0) |> List.length
                in
                [ div [ Attr.style "margin-top" "14px" ]
                    [ h3 [] [ text heading ]
                    , p [ class "prose", Attr.style "margin-top" "4px" ] [ text caption ]
                    , p [ class "prose" ]
                        [ text
                            (Format.count games
                                ++ " games across "
                                ++ String.fromInt measured
                                ++ " of "
                                ++ String.fromInt (List.length rows)
                                ++ " hulls"
                                ++ (if measured > 0 then
                                        ", about " ++ Format.count (games // measured) ++ " each"

                                    else
                                        ""
                                   )
                                ++ ". Read every rate against its own sample size."
                            )
                        ]
                    , shipTable status.scoring rows
                    ]
                ]
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips
                Tip.AlignStart
                (Tip.detail (Copy.shipPerformance status.scoring)
                    [ "There is no per-hull target. A hull with no games shows as unmeasured, not as a loss, and no row here can block or unblock the overall gate." ]
                )
                [ h2 [] [ text "Per-hull blind spots" ] ]

            -- The source stays here, right beside the table it describes.
            , span [ class "panel-note" ] [ text sourceNote ]
            ]
        , if List.isEmpty status.shipPerformance then
            div [ class "placeholder" ]
                [ Html.strong [] [ text "No per-hull evidence" ]
                , span [] [ text "The trainer has not published per-hull figures for this round yet." ]
                ]

          else
            div []
                ([ p [ class "prose" ]
                    [ text
                        ("Both tables count our champion's own "
                            ++ Scoring.successPlural status.scoring
                            ++ ", grouped two ways."
                            ++ (if diagnosticOnly then
                                    " These rows are the cheap balanced readiness probe, not gate evidence."

                                else
                                    ""
                               )
                        )
                    ]
                 ]
                    ++ section_ Api.OurSeat
                        "When piloting"
                        ("Grouped by the hull our champion flew. A weak row is a hull it cannot "
                            ++ weakRowVerb status.scoring
                            ++ " with.")
                    ++ section_ Api.OpponentSeat
                        "When facing"
                        "The same games grouped by the hull it flew against. A weak row is a hull it cannot beat."
                )
        ]


{-| What a strong row in the per-hull table would show, in the run's own
terms. Under a crew-lead gate a hull our champion "cannot win with" is
the wrong complaint: it may win nothing at all and still lead on crew
every time, which is exactly what the run is asking it to do.
-}
weakRowVerb : Maybe Api.Scoring -> String
weakRowVerb scoring =
    case Scoring.criterion scoring of
        Api.CombatWins ->
            "win"

        _ ->
            "score"


shipTable : Maybe Api.Scoring -> List Api.ShipPerformance -> Html Msg
shipTable scoring rows =
    let
        cell attrs content =
            Html.td attrs [ text content ]

        header label =
            Html.th [ Attr.scope "col" ] [ text label ]

        row entry =
            Html.tr
                [ class
                    (if entry.games <= 0 then
                        "is-unknown"

                     else
                        ""
                    )
                ]
                [ Html.th [ Attr.scope "row" ] [ text entry.ship ]
                , cell [ class "num" ] (Format.count entry.games)
                , cell [ class "num" ]
                    (if entry.games > 0 then
                        Format.count entry.wins

                     else
                        "\u{2014}"
                    )
                , cell [ class "num" ]
                    (case entry.winRate of
                        Just rate ->
                            Format.percent1 rate

                        Nothing ->
                            Format.awaiting
                    )
                , cell [ class "num" ]
                    (case entry.lowerBound of
                        Just bound ->
                            Format.percent1 bound

                        Nothing ->
                            Format.awaiting
                    )
                , cell [] (Api.evidenceSourceLabel entry.source)
                ]
    in
    div [ class "ship-wrap" ]
        [ Html.table [ class "ships" ]
            [ Html.thead []
                [ Html.tr []
                    [ header "Hull"
                    , header "Games"
                    , header ("Champion " ++ Scoring.successPlural scoring)
                    , header (Scoring.successHeading scoring)
                    , header "Lower bound"
                    , header "Evidence"
                    ]
                ]
            , Html.tbody [] (List.map row rows)
            ]
        ]


viewLadder : Tip.Handlers Msg -> Api.Status -> Html Msg
viewLadder tips status =
    let
        curriculum =
            status.curriculum

        ours =
            max 1 (List.length curriculum.ourRoster)

        theirs =
            max 1 (List.length curriculum.opponentRoster)

        currentStage =
            curriculum.stage

        -- Stage 0 is 1x1. Each stage adds one ship, opponent side first,
        -- so stage n has 1 + ceil(n/2) opponents and 1 + floor(n/2) of ours.
        sizesAt stage =
            ( 1 + (stage // 2), 1 + ((stage + 1) // 2) )

        lastStage =
            48

        window =
            List.range (max 0 (currentStage - 2)) (min lastStage (currentStage + 3))

        rung stage =
            let
                ( o, t ) =
                    sizesAt stage

                isCurrent =
                    stage == currentStage

                ( shownO, shownT ) =
                    if isCurrent then
                        ( ours, theirs )

                    else
                        ( o, t )
            in
            div
                [ class
                    ("ladder-rung"
                        ++ (if isCurrent then
                                " is-current"

                            else if stage < currentStage then
                                " is-done"

                            else
                                ""
                           )
                    )
                ]
                [ span [ class "ladder-stage" ] [ text ("stage " ++ String.fromInt stage) ]
                , div []
                    [ div [ class "ladder-size" ]
                        [ text (String.fromInt shownO ++ " ours \u{00D7} " ++ String.fromInt shownT ++ " opponents") ]
                    , div [ class "ladder-detail" ]
                        [ text (String.fromInt (shownO * shownT) ++ " ordered matchups, each gated separately") ]
                    ]
                , span [ class "ladder-right" ]
                    [ text
                        (if isCurrent then
                            "here"

                         else if stage < currentStage then
                            "passed"

                         else
                            "not attempted"
                        )
                    ]
                ]
    in
    panel tips
        Copy.ladder
        "Curriculum ladder"
        [ div [ class "ladder" ] (List.map rung window)
        , p [ class "prose", Attr.style "margin-top" "12px" ]
            [ text
                ("Expansion alternates: opponent side, then our side, from the seeded pair up to 25 \u{00D7} 25 ("
                    ++ Format.count 625
                    ++ " ordered matchups). Sizes for stages other than the current one are derived from that fixed order, not measured."
                )
            ]
        ]



-- CHARTS


historyLabels : Api.Status -> List String
historyLabels status =
    List.map (\h -> "g" ++ String.fromInt h.generation) status.history


historySegments : Api.Status -> List Int
historySegments status =
    List.map .stage status.history


countTicks : Float -> List ( Float, String )
countTicks top =
    let
        hi =
            max 1 top
    in
    List.map
        (\i ->
            let
                v =
                    hi * toFloat i / 4
            in
            ( v, Format.decimal 0 v )
        )
        (List.range 0 4)


maxOf : List (Maybe Float) -> Float
maxOf values =
    values
        |> List.filterMap identity
        |> List.maximum
        |> Maybe.withDefault 1
        |> (\m -> m * 1.15)
        |> max 1


{-| A caption under a chart, for the case where the shape of the data is
not what the axis label alone would suggest.
-}
withNote : String -> Html Msg -> Html Msg
withNote note body =
    div [] [ body, p [ class "prose", Attr.style "margin-top" "8px" ] [ text note ] ]


chartPanel : Tip.Handlers Msg -> Tip.Tip -> String -> Api.Status -> Html Msg -> Html Msg
chartPanel tips tip title status body =
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart tip [ h2 [] [ text title ] ]
            , span [ class "panel-note" ]
                [ text (String.fromInt (List.length status.history) ++ " generations recorded") ]
            ]
        , body
        ]


viewWinChart : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewWinChart tips model status =
    let
        training =
            let
                base =
                    Chart.series "training"
                        ("Training "
                            ++ Scoring.rateLabel status.scoring
                            ++ " (sampled panel, whole population)"
                        )
                        "#ffb23f"
                        (List.map .trainingWinRate status.history)
            in
            { base | width = 1.3 }

        validation =
            let
                base =
                    Chart.series "validation"
                        ("Champion audit "
                            ++ Scoring.rateLabel status.scoring
                            ++ " (predeclared gate panel)"
                        )
                        "#4fd6e0"
                        (List.map .validationWinRate status.history)
            in
            { base | markers = True, width = 2.4 }
    in
    chartPanel tips
        (Tip.detail (Copy.winRateChart status.scoring) (Scoring.explainGate status.scoring))
        (Scoring.successHeading status.scoring ++ " over generations")
        status
        (Chart.view
            { height = 240
            , userWidth = 760
            , xLabels = historyLabels status
            , segments = historySegments status
            , yMin = 0
            , yMax = 1
            , yTicks = List.map (\v -> ( v, Format.percent v )) [ 0, 0.25, 0.5, 0.75, 1 ]
            , series = [ training, validation ]
            , guides = [ { value = status.curriculum.target, label = "gate " ++ Format.percent status.curriculum.target, color = "#f4ead6" } ]
            , hovered = model.winCursor
            , onHover = WinHover
            , onLeave = WinLeave
            , formatValue = Format.percent1
            , emptyHint = "The trainer publishes a history point once the first generation has been scored."
            , describedBy = "readout-winrate"
            }
            |> scopeChangeNote status
        )


{-| The transition from a staged run to a broad one changes what the win
rate is a win rate *of*, which no axis can show.

The chart already refuses to join a line across a stage boundary, so the
break is drawn. What the break cannot say is that the points to its left
were measured against a handful of ships and the points to its right
against the whole board, and that a drop across it is a change of
question rather than a loss of skill. That has to be said in words.

-}
scopeChangeNote : Api.Status -> Html Msg -> Html Msg
scopeChangeNote status body =
    let
        stages =
            List.map .stage status.history

        earlier =
            List.filter (\stage -> stage < status.curriculum.stage) stages
    in
    if Api.isBroad status.curriculum && not (List.isEmpty earlier) then
        withNote
            ("The dashed break marks the change of scope. Points to its left were measured on the narrow staged roster, up to stage "
                ++ String.fromInt (List.foldl max 0 earlier)
                ++ "; points to its right are measured against all "
                ++ Format.count (List.length status.curriculum.ourRoster * List.length status.curriculum.opponentRoster)
                ++ " ordered matchups. They are not the same measurement, they are never joined, and a fall across the break is a harder question rather than a worse champion."
            )
            body

    else
        body


viewSpeciesChart : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewSpeciesChart tips model status =
    let
        values =
            List.map (\h -> Just (toFloat h.species)) status.history

        top =
            maxOf values
    in
    chartPanel tips
        Copy.structureChart
        "Species"
        status
        (Chart.view
            { height = 190
            , userWidth = 400
            , xLabels = historyLabels status
            , segments = historySegments status
            , yMin = 0
            , yMax = top
            , yTicks = countTicks top
            , series = [ Chart.series "species" "Species" "#a99bf5" values ]
            , guides = []
            , hovered = model.speciesCursor
            , onHover = SpeciesHover
            , onLeave = SpeciesLeave
            , formatValue = Format.decimal 0
            , emptyHint = "No generations have been scored yet."
            , describedBy = "readout-species"
            }
        )


viewNodesChart : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewNodesChart tips model status =
    let
        values =
            List.map (\h -> Just (toFloat h.nodes)) status.history

        top =
            maxOf values
    in
    chartPanel tips
        Copy.nodesChart
        "Champion nodes"
        status
        (Chart.view
            { height = 190
            , userWidth = 400
            , xLabels = historyLabels status
            , segments = historySegments status
            , yMin = 0
            , yMax = top
            , yTicks = countTicks top
            , series = [ Chart.series "nodes" "Nodes" "#4fd6e0" values ]
            , guides = [ { value = toFloat Slots.hiddenFirst, label = "70 fixed", color = "#56618a" } ]
            , hovered = model.nodesCursor
            , onHover = NodesHover
            , onLeave = NodesLeave
            , formatValue = Format.decimal 0
            , emptyHint = "No generations have been scored yet."
            , describedBy = "readout-nodes"
            }
        )


viewEpisodesChart : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewEpisodesChart tips model status =
    let
        values =
            List.map (\h -> Just (toFloat h.episodes)) status.history

        top =
            maxOf values
    in
    chartPanel tips
        Copy.throughputChart
        "Cumulative episodes"
        status
        (Chart.view
            { height = 190
            , userWidth = 400
            , xLabels = historyLabels status
            , segments = historySegments status
            , yMin = 0
            , yMax = top
            , yTicks = countTicks top
            , series = [ Chart.series "episodes" "Episodes resolved, running total" "#ffb23f" values ]
            , guides = []
            , hovered = model.episodesCursor
            , onHover = EpisodesHover
            , onLeave = EpisodesLeave
            , formatValue = Format.decimal 0
            , emptyHint = "No generations have been scored yet."
            , describedBy = "readout-episodes"
            }
            |> withNote "This is a running total, so the line can only rise. The cost of one generation is the step between two adjacent points, not the height of the line."
        )



-- HEATMAP


viewHeatmap : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewHeatmap tips model status =
    let
        byType =
            [ Api.Cyborg, Api.ModelOpponent ]
                |> List.map (\kind -> ( kind, List.filter (\m -> m.opponentType == kind) status.matchups ))
                |> List.filter (\( _, list ) -> not (List.isEmpty list))

        others =
            status.matchups
                |> List.filter
                    (\m ->
                        case m.opponentType of
                            Api.UnknownOpponent _ ->
                                True

                            _ ->
                                False
                    )

        groups =
            byType
                ++ (if List.isEmpty others then
                        []

                    else
                        [ ( Api.UnknownOpponent "other", others ) ]
                   )

        renderGroup ( kind, list ) =
            div [ Attr.style "margin-top" "14px" ]
                [ h3 [] [ text ("Opponent type: " ++ Api.opponentTypeLabel kind) ]
                , Heatmap.view
                    { target = status.curriculum.target
                    , selected = model.heatCursor
                    , onSelect = HeatSelect
                    , onClear = HeatClear
                    , describedBy = "readout-heat"
                    , successPlural = Scoring.successPlural status.scoring
                    }
                    (Heatmap.grid status.curriculum.ourRoster status.curriculum.opponentRoster list)
                ]
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart Copy.heatmap [ h2 [] [ text "Ordered matchup evidence" ] ]
            , span [ class "panel-note" ]
                [ text
                    (if Api.isBroad status.curriculum then
                        "current champion \u{00B7} per-cell diagnostic, gates nothing"

                     else
                        "current champion, stage " ++ String.fromInt status.curriculum.stage ++ ", audit games only"
                    )
                ]
            ]
        , if Api.isBroad status.curriculum then
            p [ class "prose" ]
                [ text "In broad mode no cell has a gate of its own. This grid is a diagnostic: it shows where the champion is weak inside the distribution the overall target averages over. A cell with no games is unmeasured, not lost." ]

          else
            text ""
        , if List.isEmpty groups then
            div [ class "placeholder" ]
                [ Html.strong [] [ text "No matchups reported" ]
                , span [] [ text "The trainer has not published per-cell evidence for this stage yet." ]
                ]

          else
            div [] (List.map renderGroup groups)
        ]



-- SAMPLE ALLOCATION


viewAllocation : Tip.Handlers Msg -> Api.Status -> Html Msg
viewAllocation tips status =
    let
        total =
            status.matchups |> List.map .sampleWeight |> List.sum

        top =
            status.matchups
                |> List.sortBy (\m -> -m.sampleWeight)
                |> List.take 10
                |> List.filter (\m -> m.sampleWeight > 0)

        row matchup =
            let
                share =
                    if total <= 0 then
                        0

                    else
                        matchup.sampleWeight / total
            in
            div []
                [ div [ class "alloc-name" ]
                    [ span [ class "who" ] [ text ("our " ++ matchup.us ++ " vs their " ++ matchup.them) ]
                    , span [ class "chip" ] [ text (Api.matchupStatusLabel matchup.status) ]
                    ]
                , div [ class "alloc-row" ]
                    [ div [ class "alloc-bar" ]
                        [ div [ class "alloc-fill", Attr.style "width" (Format.decimal 2 (share * 100) ++ "%") ] [] ]
                    , span [ class "alloc-share" ] [ text (Format.percent1 share) ]
                    ]
                ]
    in
    panel tips
        Copy.sampleAllocation
        "Training sample allocation"
        [ if List.isEmpty top then
            div [ class "placeholder" ]
                [ Html.strong [] [ text "No weights published" ]
                , span [] [ text "The sampler has not reported per-cell weights for the upcoming generation." ]
                ]

          else
            div [ class "alloc" ] (List.map row top)
        , p [ class "prose", Attr.style "margin-top" "14px" ]
            [ text "Weights are a deterministic mixture: weak and uncertain cells, cells added by the most recent expansion, and a coverage floor that keeps every active cell rehearsed. Both seat orientations are sampled." ]
        , p [ class "prose" ]
            [ text "Every population member plays the same sampled panel within a generation, so their scores are comparable with each other. When the panel changes, elites are rescored rather than carrying a fitness earned on a different panel." ]
        , p [ class "prose" ]
            [ text "These weights steer training play only. Gate evidence comes from separate audit panels on separate seeds, and nothing here feeds it." ]
        ]



-- MACHINE


viewMachine : Tip.Handlers Msg -> Api.Status -> Html Msg
viewMachine tips status =
    let
        checkpoint =
            status.checkpoint

        resources =
            status.resources

        population =
            status.population
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart Copy.machine [ h2 [] [ text "Population, checkpoint and resources" ] ] ]
        , div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.populationSize
                , label = "Population"
                , value = Just (Format.count population.size)
                , sub = "genomes this generation"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.species
                , label = "Species"
                , value = Just (Format.count population.species)
                , sub = "compatibility groups"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.meanNodes
                , label = "Mean nodes"
                , value = Just (Format.decimal 1 population.meanNodes)
                , sub = "70 are fixed inputs and outputs"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.meanConnections
                , label = "Mean links"
                , value = Just (Format.decimal 1 population.meanConnections)
                , sub = "enabled connections"
                , accent = ""
                }
            ]
        , div [ Attr.style "margin-top" "16px" ]
            [ h3 [] [ text "Checkpoint" ] ]
        , dl [ class "deflist", Attr.style "margin-top" "8px" ]
            [ dt [] [ Tip.view tips Tip.AlignStart Copy.checkpointSaved [ text "Saved" ] ]
            , dd []
                [ text
                    (case checkpoint.savedAt of
                        Just at ->
                            at

                        Nothing ->
                            "never in this run"
                    )
                ]
            , dt [] [ Tip.view tips Tip.AlignStart Copy.checkpointGeneration [ text "Generation" ] ]
            , dd [] [ text (Format.count checkpoint.generation) ]
            , dt [] [ Tip.view tips Tip.AlignStart Copy.checkpointResumable [ text "Resumable" ] ]
            , dd []
                [ text
                    (if checkpoint.resumable then
                        "yes, exact resume"

                     else
                        "no"
                    )
                ]
            , dt [] [ Tip.view tips Tip.AlignStart Copy.checkpointPath [ text "Path" ] ]
            , dd []
                [ text
                    (if String.isEmpty checkpoint.path then
                        "not reported"

                     else
                        checkpoint.path
                    )
                ]
            ]
        , div [ Attr.style "margin-top" "16px" ]
            [ h3 [] [ text "Resource caps" ] ]
        , dl [ class "deflist", Attr.style "margin-top" "8px" ]
            [ dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesWorkers [ text "Threads" ] ]
            , dd [] [ text (String.fromInt resources.workers) ]
            , dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesDuty [ text "Duty cycle" ] ]
            , dd []
                [ text
                    (if resources.dutyCycle > 0 then
                        Format.percent1 resources.dutyCycle ++ " working"

                     else
                        "not measured"
                    )
                ]
            , dt [] [ Tip.view tips Tip.AlignStart Copy.runId [ text "Run" ] ]
            , dd [] [ text status.runId ]
            ]
        ]



-- TOPOLOGY


viewTopology : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewTopology tips model status =
    let
        body =
            case ( model.network, model.networkError ) of
                ( Just network, _ ) ->
                    if List.isEmpty network.genome.nodes && List.isEmpty network.genome.genes then
                        div [ class "placeholder" ]
                            [ Html.strong [] [ text "Empty genome" ]
                            , span [] [ text "The network endpoint answered, but the champion genome contains no nodes or connections yet." ]
                            ]

                    else
                        div []
                            [ if network.championId /= status.champion.id && network.championId /= "" && status.champion.id /= "" then
                                div [ class "banner banner-warn" ]
                                    [ div []
                                        [ text
                                            ("This graph is champion "
                                                ++ Format.shortId network.championId
                                                ++ ", but the current champion is "
                                                ++ Format.shortId status.champion.id
                                                ++ ". Refresh to fetch the current genome."
                                            )
                                        ]
                                    , div [ class "banner-actions" ]
                                        [ button [ class "btn btn-small", onClick RefreshNow ] [ text "Refresh" ] ]
                                    ]

                              else
                                text ""
                            , Topology.view
                                { selected = model.nodeCursor
                                , onSelect = NodeSelect
                                , onClear = NodeClear
                                , describedBy = "readout-topology"
                                }
                                network.genome
                            ]

                ( Nothing, Just reason ) ->
                    div [ class "placeholder" ]
                        [ Html.strong [] [ text "Network unavailable" ]
                        , span [] [ text ("Could not read " ++ networkUrl ++ ": " ++ reason ++ ".") ]
                        , button [ class "btn btn-small", onClick RefreshNow ] [ text "Retry" ]
                        ]

                ( Nothing, Nothing ) ->
                    div [ class "placeholder" ]
                        [ Html.strong [] [ text "Loading genome" ]
                        , span [] [ text "Fetching the champion network." ]
                        ]
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart Copy.topology [ h2 [] [ text "Champion network topology" ] ]
            , span [ class "panel-note" ]
                [ text
                    (String.fromInt Slots.inputCount
                        ++ " inputs \u{2192} evolved hidden nodes \u{2192} "
                        ++ String.fromInt Slots.outputCount
                        ++ " outputs"
                    )
                ]
            ]
        , body
        ]



-- EVENTS


viewEvents : Tip.Handlers Msg -> Api.Status -> Html Msg
viewEvents tips status =
    panel tips
        Copy.timeline
        "Run events"
        [ if List.isEmpty status.events then
            div [ class "placeholder" ]
                [ Html.strong [] [ text "No events" ]
                , span [] [ text "The trainer has not recorded any notable transitions in this run yet." ]
                ]

          else
            div [ class "events" ]
                (List.map
                    (\event ->
                        div [ class "event-row" ]
                            [ span [ class "event-at" ] [ text (Format.timeOfDay event.at) ]
                            , span [] [ text event.message ]
                            ]
                    )
                    (List.reverse status.events)
                )
        ]



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
