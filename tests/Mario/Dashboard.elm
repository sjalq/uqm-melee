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


fetchStatus : Cmd Msg
fetchStatus =
    Http.get { url = statusUrl, expect = Http.expectJson GotStatus Api.decodeStatus }


fetchNetwork : Cmd Msg
fetchNetwork =
    Http.get { url = networkUrl, expect = Http.expectJson GotNetwork Api.decodeNetwork }


sendControl : Action -> Cmd Msg
sendControl action =
    Http.post
        { url = controlUrl
        , body = Http.jsonBody (Encode.object [ ( "action", Encode.string (actionKey action) ) ])
        , expect = Http.expectWhatever (GotControl action)
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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.visible then
            Time.every pollMillis Tick

          else
            Sub.none
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
                [ section [ class "col-8" ] [ viewChampionGate tips model status ]
                , section [ class "col-4" ] [ viewVitals tips model status ]
                , section [ class "col-7" ] [ viewCurriculum tips status ]
                , section [ class "col-5" ] [ viewLadder tips status ]
                , section [ class "col-12" ] [ viewWinChart tips model status ]
                , section [ class "col-4" ] [ viewSpeciesChart tips model status ]
                , section [ class "col-4" ] [ viewNodesChart tips model status ]
                , section [ class "col-4" ] [ viewEpisodesChart tips model status ]
                , section [ class "col-12" ] [ viewHeatmap tips model status ]
                , section [ class "col-7" ] [ viewAllocation tips status ]
                , section [ class "col-5" ] [ viewMachine tips status ]
                , section [ class "col-12" ] [ viewTopology tips model status ]
                , section [ class "col-12" ] [ viewEvents tips status ]
                ]
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
            [ Tip.view tips Tip.AlignStart Copy.championRate [ h2 [] [ text "Champion fresh audit win rate" ] ]
            , span [ class "panel-note" ] [ text "Audit evidence only. Not population training play." ]
            ]
        , div [ class "gate" ]
            [ div [ class "gate-figure" ]
                [ div [ class rateClass ] [ text rateText ]
                , div [ class "gate-denominator" ]
                    [ text
                        (if champion.validatedGames > 0 then
                            "over " ++ Format.fraction champion.validatedWins champion.validatedGames ++ " fresh audit games"

                         else
                            "no audit games on this champion's panel yet"
                        )
                    ]
                , div [ class "gate-meter" ]
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
                , div [ class "gate-legend" ]
                    [ span []
                        [ span [ class "swatch", Attr.style "background" "#4fd6e0" ] []
                        , text "Wilson lower bound"
                        ]
                    , span []
                        [ span [ class "swatch", Attr.style "background" "rgba(79,214,224,0.3)" ] []
                        , text "raw win rate"
                        ]
                    , span []
                        [ span [ class "swatch", Attr.style "background" "#f4ead6" ] []
                        , text ("gate target " ++ Format.percent target)
                        ]
                    ]
                , p [ class "prose" ] [ text verdictLine ]
                ]
            , div [ class "gate-side" ]
                [ div [ class "metrics" ]
                    [ viewMetric tips
                        { tip = Copy.championLowerBound
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
                        { tip = Copy.championGames
                        , label = "Audit sample"
                        , value =
                            if champion.validatedGames > 0 then
                                Just (Format.fraction champion.validatedWins champion.validatedGames)

                            else
                                Nothing
                        , sub = "wins over predeclared panel games"
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
                        , sub = "nodes / enabled links"
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

        blockers =
            Gate.analyse target status.matchups

        reasons =
            Gate.explain target curriculum status.matchups

        weakest =
            Gate.weakestFirst target status.matchups
                |> List.filter (\m -> m.status /= Api.Mastered)
                |> List.take 5
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart Copy.expansionBlocked [ h2 [] [ text "Curriculum and why it is or is not expanding" ] ]
            , span [ class "panel-note" ] [ text ("stage " ++ String.fromInt curriculum.stage) ]
            ]
        , div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.stage
                , label = "Stage"
                , value = Just (String.fromInt curriculum.stage)
                , sub =
                    String.fromInt (List.length curriculum.ourRoster)
                        ++ " of ours \u{00D7} "
                        ++ String.fromInt (List.length curriculum.opponentRoster)
                        ++ " opponents"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.matchupCoverage
                , label = "Mastered cells"
                , value = Just (Format.fraction curriculum.masteredMatchups curriculum.totalMatchups)
                , sub = "each cell gated on its own evidence"
                , accent =
                    if curriculum.totalMatchups > 0 && curriculum.masteredMatchups == curriculum.totalMatchups then
                        "metric-cyan"

                    else
                        ""
                }
            , viewMetric tips
                { tip = Copy.unevaluated
                , label = "Unevaluated"
                , value = Just (String.fromInt blockers.unseen)
                , sub = "active cells with no audit games"
                , accent =
                    if blockers.unseen > 0 then
                        "metric-amber"

                    else
                        ""
                }
            , viewMetric tips
                { tip = Copy.nextExpansion
                , label = "Next addition"
                , value =
                    case ( curriculum.nextSide, curriculum.nextShip ) of
                        ( Api.Complete, _ ) ->
                            Just "complete"

                        ( _, Just ship ) ->
                            Just ship

                        ( Api.UnknownSide _, Nothing ) ->
                            Nothing

                        ( _, Nothing ) ->
                            Nothing
                , sub = Api.nextSideLabel curriculum.nextSide
                , accent = ""
                }
            ]
        , div [ Attr.style "margin-top" "14px" ]
            (List.map (\line -> p [ class "prose" ] [ text line ]) reasons)
        , if List.isEmpty weakest then
            text ""

          else
            div [ Attr.style "margin-top" "14px" ]
                [ h3 [] [ text "Cells holding the gate up" ]
                , div [ class "alloc", Attr.style "margin-top" "8px" ]
                    (List.map (viewWeakCell target) weakest)
                ]
        , div [ Attr.style "margin-top" "16px" ]
            [ h3 [] [ text "Rosters in frozen expansion order" ]
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
                            "no games"
                    )
                ]
            ]
        ]



-- LADDER


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
                    Chart.series "training" "Training win rate (sampled panel, whole population)" "#ffb23f" (List.map .trainingWinRate status.history)
            in
            { base | dashed = True, width = 1.6 }

        validation =
            let
                base =
                    Chart.series "validation" "Champion audit win rate (predeclared gate panel)" "#4fd6e0" (List.map .validationWinRate status.history)
            in
            { base | markers = True, width = 2.4 }
    in
    chartPanel tips
        Copy.winRateChart
        "Win rate over generations"
        status
        (Chart.view
            { height = 240
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
        )


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
        "Episodes per generation"
        status
        (Chart.view
            { height = 190
            , xLabels = historyLabels status
            , segments = historySegments status
            , yMin = 0
            , yMax = top
            , yTicks = countTicks top
            , series = [ Chart.series "episodes" "Episodes" "#ffb23f" values ]
            , guides = []
            , hovered = model.episodesCursor
            , onHover = EpisodesHover
            , onLeave = EpisodesLeave
            , formatValue = Format.decimal 0
            , emptyHint = "No generations have been scored yet."
            , describedBy = "readout-episodes"
            }
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
                    }
                    (Heatmap.grid status.curriculum.ourRoster status.curriculum.opponentRoster list)
                ]
    in
    div [ class "panel" ]
        [ div [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart Copy.heatmap [ h2 [] [ text "Ordered matchup audit evidence" ] ]
            , span [ class "panel-note" ]
                [ text ("current champion, stage " ++ String.fromInt status.curriculum.stage ++ ", audit games only") ]
            ]
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
