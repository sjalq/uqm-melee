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

The page reads coarse to fine, in four bands, and every panel belongs to
exactly one of them:

1.  **Am I winning?** One headline success rate, the gate it is judged
    against, and the trend behind it.
2.  **What is it doing?** The phase, the matchups it is drawing, and
    what would open the next gate.
3.  **Is it learning?** Species, structure, and where the aggregate is
    hiding a weakness. The two panels that are for looking closer rather
    than for glancing at, the matchup grid and the network graph, are
    folded shut until asked for.
4.  **Is it healthy?** What the work costs per unit of work, where the
    time went, what the machine is allowed to spend, and the log.

Three rules shape the content.

Honest absence. A measurement the trainer has not taken is rendered as
"awaiting evidence", never as zero. `Maybe` is carried all the way from
the decoder into the view, so there is no place where a missing number
could quietly become `0`.

One number, one place. Nothing restates a figure a band above it
already showed. The gate is stated once, at the top, at the largest size
used anywhere.

Nothing incomparable is joined. Charts break at every unmeasured
sample, and the per-cell grid is labelled as training exposure rather
than as evidence, because that is what it is.

-}

import Browser
import Browser.Events
import Html exposing (Html, button, dd, details, div, dl, dt, h1, h2, h3, p, section, span, summary, text)
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
import Mario.Dashboard.Resources as Resources
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
            "the response did not match schema version 4: " ++ detail



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
                -- Only fetch a genome when there IS one and it is not the one
                -- already held. With no champion there is nothing to draw and
                -- nothing to ask for.
                needsNetwork =
                    status.champion.id /= Nothing && model.networkFor /= status.champion.id

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
                , networkFor = network.championId
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
            [ band "Am I winning?"
                "The one graded question, and the trend behind it."
                [ section [ class "col-12" ] [ viewGate tips model status ]
                , section [ class "col-12" ] [ viewWinChart tips model status ]
                ]
            , band "What is it doing?"
                "What the next episodes are being spent on, and what would open the next gate."
                [ section [ class "col-6" ] [ viewNowPlaying tips status ]
                , section [ class "col-6" ] [ viewNextGate tips status ]
                , section [ class "col-12" ] [ viewAllocation tips status ]
                ]
            , band "Is it learning?"
                "Whether the search is still finding structure, and where the aggregate hides a weakness."
                [ section [ class "col-4" ] [ viewPopulation tips status ]
                , section [ class "col-4" ] [ viewSpeciesChart tips model status ]
                , section [ class "col-4" ] [ viewNodesChart tips model status ]
                , section [ class "col-12" ] [ viewShipPerformance tips status ]
                , section [ class "col-12" ] [ viewHeatmap tips model status ]
                , section [ class "col-12" ] [ viewTopology tips model status ]
                ]
            , band "Is it healthy?"
                "What the work costs, where the time goes, and what the machine is allowed to spend."
                [ section [ class "col-6" ] [ viewThroughput tips model status ]
                , section [ class "col-6" ] [ viewPhaseSplit tips status ]
                , section [ class "col-6" ] [ viewBenchmark tips status ]
                , section [ class "col-6" ] [ viewMachine tips status ]
                , section [ class "col-12" ] [ viewEvents tips status ]
                ]
            ]


{-| One reading band. The heading is a question rather than a noun,
because the whole point of the ordering is that a reader who only has
ten seconds gets an answer from the first band alone.
-}
band : String -> String -> List (Html Msg) -> Html Msg
band title note panels =
    section [ class "band" ]
        [ div [ class "band-head" ]
            [ h2 [ class "band-title" ] [ text title ]
            , span [ class "band-note" ] [ text note ]
            ]
        , div [ class "grid grid-main" ] panels
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
        tone =
            if model.statusError /= Nothing then
                "pill-bad"

            else if isStale model then
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


{-| Stale means either this browser has stopped hearing from the trainer
or the trainer has said so itself.

The client-side age catches a trainer that has gone away entirely, which
the document cannot report because it stops being published. The
document's own `stale` flag catches the case the age cannot see: the
trainer is answering, but the snapshot it is handing out was rendered
some time ago.

-}
isStale : Model -> Bool
isStale model =
    model.statusError
        /= Nothing
        || model.statusAge
        > staleAfterSeconds
        || (model.status |> Maybe.map .stale |> Maybe.withDefault False)


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
        , messageBanner model
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
            if model.statusError == Nothing && isStale model && Api.phaseIsLive status.phase then
                Just
                    (div [ class "banner banner-warn", Attr.attribute "role" "status" ]
                        [ div []
                            [ Html.strong [] [ text "Stale snapshot. " ]
                            , text
                                ("The trainer says it is "
                                    ++ String.toLower (Api.phaseLabel status.phase)
                                    ++ ", but "
                                    ++ (if status.stale then
                                            "it has marked this snapshot stale itself"

                                        else
                                            "it has not published an update for "
                                                ++ Format.decimal 0 model.statusAge
                                                ++ " seconds"
                                       )
                                    ++ ". Treat these numbers as historical until it catches up."
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


{-| Whatever the trainer put in `message`, shown verbatim.

There is no error phase to key a louder treatment off: a start that
fails exits with its reason on stderr rather than publishing, so a
running trainer's message is a note rather than a fault.

-}
messageBanner : Model -> Maybe (Html Msg)
messageBanner model =
    case model.status of
        Just status ->
            if String.isEmpty status.message then
                Nothing

            else
                Just
                    (div [ class "banner", Attr.attribute "role" "status" ]
                        [ div [] [ text status.message ] ]
                    )

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


{-| A panel that starts folded shut.

For the two views that are for looking closer rather than for glancing
at. A native `details` element is used rather than model state so the
fold survives every re-render, works with no JavaScript of ours, and
reaches keyboard and screen-reader users for free.

-}
foldPanel : Tip.Handlers Msg -> Tip.Tip -> String -> String -> List (Html Msg) -> Html Msg
foldPanel tips tip title note children =
    details [ class "panel panel-fold" ]
        (summary [ class "panel-head" ]
            [ Tip.view tips Tip.AlignStart tip [ h2 [] [ text title ] ]
            , span [ class "panel-note" ] [ text note ]
            ]
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


{-| A horizontal share bar, reused by the sample allocation list and the
phase split. One shape for "this is what fraction of the whole X is",
so two panels that mean the same thing look the same.
-}
shareRow : String -> Maybe String -> Float -> Html Msg
shareRow name chip share =
    div []
        [ div [ class "alloc-name" ]
            (span [ class "who" ] [ text name ]
                :: (case chip of
                        Just label ->
                            [ span [ class "chip" ] [ text label ] ]

                        Nothing ->
                            []
                   )
            )
        , div [ class "alloc-row" ]
            [ div [ class "alloc-bar" ]
                [ div
                    [ class "alloc-fill"
                    , Attr.style "width" (Format.decimal 2 (clamp 0 1 share * 100) ++ "%")
                    ]
                    []
                ]
            , span [ class "alloc-share" ] [ text (Format.percent1 share) ]
            ]
        ]



-- BAND 1: AM I WINNING?


{-| The bar behind the gate figure: raw rate, published bound, and the
target line.
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


{-| The headline. One rate, one bound, one target, one meter.

An aggregate over a fixed held-out balanced panel, judged on the bound
rather than on the raw rate, and cleared only when two independent
rounds have both cleared it under the same frozen champion.

-}
viewGate : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewGate tips model status =
    let
        gateTip =
            Tip.detail (Copy.overallGate status.scoring)
                (Gate.explainOverall status.scoring status.board status.overall status.shipPerformance
                    ++ Scoring.explainGate status.scoring
                )

        heading =
            "Overall balanced " ++ Scoring.rateLabel status.scoring
    in
    case status.overall of
        Nothing ->
            div [ class "panel" ]
                [ div [ class "panel-head" ]
                    ([ Tip.view tips Tip.AlignStart gateTip [ h2 [] [ text heading ] ]
                     , span [ class "panel-note" ] [ text "any ship versus any ship, Awesome cyborgs" ]
                     ]
                        ++ scoringNote tips status
                    )
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
                                , value = Maybe.map Format.shortId overall.championId
                                , sub = "evidence resets when this changes"
                                , accent = ""
                                }
                            , roundMetric tips Copy.overallRound "Audit round" overall.target overall.audit
                            , roundMetric tips Copy.overallRound "Confirm round" overall.target overall.confirm
                            ]
                        , p [ class "prose" ] [ text (gateStandingLine model overall) ]
                        ]
                    ]
                ]


{-| The last word under the gate tiles: whether this champion has
cleared it, whether somebody else did, or what is still owed.
-}
gateStandingLine : Model -> Api.Overall -> String
gateStandingLine model overall =
    if isStale model then
        "These figures are from a stale snapshot; see the notice above."

    else if overall.passed then
        "Both rounds have cleared the overall target for this champion. That is an aggregate result over the balanced distribution, not a per-matchup guarantee; the per-hull table below shows where it is weakest."

    else
        case ( overall.passedBy, overall.championId ) of
            ( Just cleared, current ) ->
                if Just cleared /= current then
                    "Champion "
                        ++ Format.shortId cleared
                        ++ " cleared both rounds, but it is no longer the champion. That result belongs to that policy and is not inherited, so the gate stands open again."

                else
                    "Passes only after the audit round and then an independent confirm round. Neither round's evidence is added to the other's."

            ( Nothing, _ ) ->
                "Passes only after the audit round and then an independent confirm round. Neither round's evidence is added to the other's."


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


{-| What the gate actually demands on its panel, in observed successes
rather than in the target percentage: a bound floor of 80% is not 80 in
100.

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


viewWinChart : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewWinChart tips model status =
    let
        target =
            status.overall |> Maybe.map .target |> Maybe.withDefault 0.8

        training =
            let
                base =
                    Chart.series "training"
                        ("Training "
                            ++ Scoring.rateLabel status.scoring
                            ++ " (champion's own sampled panel this generation)"
                        )
                        "#ffb23f"
                        (List.map .trainingWinRate status.history)
            in
            { base | width = 1.3 }

        validation =
            let
                base =
                    Chart.series "validation"
                        ("Champion readiness "
                            ++ Scoring.rateLabel status.scoring
                            ++ " (screening probe, not audit evidence)"
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
            , yMin = 0
            , yMax = 1
            , yTicks = List.map (\v -> ( v, Format.percent v )) [ 0, 0.25, 0.5, 0.75, 1 ]
            , series = [ training, validation ]
            , guides = [ { value = target, label = "gate " ++ Format.percent target, color = "#f4ead6" } ]
            , hovered = model.winCursor
            , onHover = WinHover
            , onLeave = WinLeave
            , formatValue = Format.percent1
            , emptyHint = "The trainer publishes a history point once the first generation has been scored."
            , describedBy = "readout-winrate"
            }
            |> withNote "Neither line is gate evidence. Training is the sampled panel the population was scored on; readiness is the cheap balanced probe that decides when an audit is worth spending. The gate guide is the aggregate target both are read against."
        )



-- BAND 2: WHAT IS IT DOING?


{-| What the next episodes are actually being spent on.

The sampler rows are the real answer, so they lead. The scoring rules
follow them because every one of those fights is scored under them, and
a reader who does not know what a "rate" counts here cannot read any
other panel on the page.

-}
viewNowPlaying : Tip.Handlers Msg -> Api.Status -> Html Msg
viewNowPlaying tips status =
    let
        opponents =
            status.matchups
                |> List.map .opponentType
                |> List.foldl
                    (\kind acc ->
                        if List.member kind acc then
                            acc

                        else
                            acc ++ [ kind ]
                    )
                    []

        samplerRows sampler =
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
    in
    panel tips
        Copy.nowPlaying
        "What it is playing"
        [ div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.board
                , label = "Active board"
                , value =
                    if status.board.totalMatchups > 0 then
                        Just (Format.count status.board.totalMatchups)

                    else
                        Nothing
                , sub = "ordered matchups, all active from generation one"
                , accent = "metric-cyan"
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
            ]
        , dl [ class "deflist", Attr.style "margin-top" "16px" ]
            ([ dt [] [ Tip.view tips Tip.AlignStart Copy.phase [ text "Doing now" ] ]
             , dd []
                [ text
                    (Api.phaseLabel status.phase
                        ++ (case status.overall |> Maybe.andThen .round of
                                Just round ->
                                    ", " ++ Api.overallRoundLabel round ++ " round in flight"

                                Nothing ->
                                    ", no gate round in flight"
                           )
                    )
                ]
             , dt [] [ text "Opponents" ]
             , dd []
                [ text
                    (if List.isEmpty opponents then
                        "not reported"

                     else
                        String.join ", " (List.map Api.opponentTypeLabel opponents)
                    )
                ]
             ]
                ++ (case status.sampler of
                        Just sampler ->
                            samplerRows sampler

                        Nothing ->
                            []
                   )
            )
        ]


{-| What would open the next gate, stated as the sequence it is.
-}
viewNextGate : Tip.Handlers Msg -> Api.Status -> Html Msg
viewNextGate tips status =
    let
        readiness =
            status.readiness

        target =
            status.overall |> Maybe.map .target |> Maybe.withDefault 0.8

        panelSize =
            status.overall |> Maybe.map .panel |> Maybe.withDefault 0
    in
    panel tips
        Copy.nextGate
        "What opens the next gate"
        [ div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.readiness
                , label = "Readiness probe"
                , value = Maybe.map Format.percent1 readiness.lastRate
                , sub =
                    "needs "
                        ++ Format.percent readiness.threshold
                        ++ " over "
                        ++ String.fromInt readiness.games
                        ++ " balanced games to buy an audit"
                        ++ (if readiness.period > 0 then
                                ", probed every " ++ String.fromInt readiness.period ++ " generations"

                            else
                                ""
                           )
                , accent =
                    case readiness.lastRate of
                        Just rate ->
                            if rate >= readiness.threshold then
                                "metric-cyan"

                            else
                                "metric-amber"

                        Nothing ->
                            ""
                }
            , viewMetric tips
                { tip = Copy.observedNeeded status.scoring
                , label = Format.capitalise (Scoring.successPlural status.scoring) ++ " needed"
                , value =
                    Gate.winsNeeded Gate.z95 target panelSize
                        |> Maybe.map (\wins -> Format.fraction wins panelSize)
                , sub = "observed, on one round's panel, to clear the bound"
                , accent = "metric-amber"
                }
            ]
        , div [ Attr.style "margin-top" "14px" ]
            (List.map (\line -> p [ class "prose" ] [ text line ])
                (Gate.nextGateSteps status.scoring readiness status.overall)
            )
        ]


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
            shareRow ("our " ++ matchup.us ++ " vs their " ++ matchup.them)
                (Just (Format.decimal 1 matchup.trainingGames ++ " games"))
                (if total <= 0 then
                    0

                 else
                    matchup.sampleWeight / total
                )
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
            [ text "Weights are a deterministic mixture: a floor that keeps every cell rehearsed, a term that favours cells with little evidence, and a term that favours cells whose outcome is still close. Both seat orientations are sampled." ]
        , p [ class "prose" ]
            [ text "Every population member plays the same sampled panel within a generation, so their scores are comparable with each other. When the panel changes, elites are rescored rather than carrying a fitness earned on a different panel." ]
        , p [ class "prose" ]
            [ text "These weights steer training play only. Gate evidence comes from separate balanced panels on separate seeds, and nothing here feeds it." ]
        ]



-- BAND 3: IS IT LEARNING?


viewPopulation : Tip.Handlers Msg -> Api.Status -> Html Msg
viewPopulation tips status =
    let
        population =
            status.population
    in
    panel tips
        Copy.populationPanel
        "Population and structure"
        [ div [ class "metrics" ]
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
                , sub = String.fromInt Slots.hiddenFirst ++ " are fixed inputs and outputs"
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



-- CHARTS


historyLabels : Api.Status -> List String
historyLabels status =
    List.map (\h -> "g" ++ String.fromInt h.generation) status.history


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
            , yMin = 0
            , yMax = top
            , yTicks = countTicks top
            , series = [ Chart.series "nodes" "Nodes" "#4fd6e0" values ]
            , guides =
                [ { value = toFloat Slots.hiddenFirst
                  , label = String.fromInt Slots.hiddenFirst ++ " fixed"
                  , color = "#56618a"
                  }
                ]
            , hovered = model.nodesCursor
            , onHover = NodesHover
            , onLeave = NodesLeave
            , formatValue = Format.decimal 0
            , emptyHint = "No generations have been scored yet."
            , describedBy = "readout-nodes"
            }
        )



-- HEATMAP


{-| Folded shut by default: this is the panel to open when the aggregate
has already said something interesting, not one to glance at.
-}
viewHeatmap : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewHeatmap tips model status =
    let
        target =
            status.overall |> Maybe.map .target |> Maybe.withDefault 0.8

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
                    { target = target
                    , selected = model.heatCursor
                    , onSelect = HeatSelect
                    , onClear = HeatClear
                    , describedBy = "readout-heat"
                    , successPlural = Scoring.successPlural status.scoring
                    }
                    (Heatmap.grid list)
                ]
    in
    foldPanel tips
        Copy.heatmap
        "Ordered matchup training exposure"
        (Format.count (List.length status.matchups) ++ " cells \u{00B7} open to look closer")
        [ p [ class "prose" ]
            [ text "No cell has a gate of its own. This grid shows where the population has actually been made to practise and how those practice games went, which is what an aggregate cannot show. A cell with no games is unmeasured, not lost." ]
        , if List.isEmpty groups then
            div [ class "placeholder" ]
                [ Html.strong [] [ text "No matchups reported" ]
                , span [] [ text "The trainer has not published per-cell training exposure yet." ]
                ]

          else
            div [] (List.map renderGroup groups)
        ]



-- TOPOLOGY


viewTopology : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewTopology tips model status =
    let
        mismatch =
            case ( model.network |> Maybe.andThen .championId, status.champion.id ) of
                ( Just drawn, Just current ) ->
                    drawn /= current

                _ ->
                    False

        body =
            case ( model.network, model.networkError ) of
                ( Just network, _ ) ->
                    if List.isEmpty network.genome.nodes && List.isEmpty network.genome.genes then
                        div [ class "placeholder" ]
                            [ Html.strong [] [ text "Empty genome" ]
                            , span [] [ text "The network endpoint answered, but there is no champion genome to draw yet." ]
                            ]

                    else
                        div []
                            [ if mismatch then
                                div [ class "banner banner-warn" ]
                                    [ div []
                                        [ text
                                            ("This graph is champion "
                                                ++ Format.shortId (Maybe.withDefault "" network.championId)
                                                ++ ", but the current champion is "
                                                ++ Format.shortId (Maybe.withDefault "" status.champion.id)
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
    foldPanel tips
        Copy.topology
        "Champion network topology"
        (String.fromInt Slots.inputCount
            ++ " inputs \u{2192} evolved hidden nodes \u{2192} "
            ++ String.fromInt Slots.outputCount
            ++ " outputs \u{00B7} open to look closer"
        )
        [ body ]



-- BAND 4: IS IT HEALTHY?


{-| What the work costs, and how much of it there has been.

The two nanosecond figures lead because they are the only ones here that
hold still: they divide thread-summed CPU time by counts of events, so
neither the worker count nor the machine's load can move them. The
episodes-per-second figure sits below them and says in its own sub-label
that it is a wall clock and therefore load dependent, because it is the
number a reader will otherwise assume is the throughput to optimise.

-}
viewThroughput : Tip.Handlers Msg -> Model -> Api.Status -> Html Msg
viewThroughput tips model status =
    let
        work =
            status.work

        rate field =
            work |> Maybe.andThen field
    in
    panel tips
        Copy.workRates
        "Throughput and cost"
        [ div [ class "metrics" ]
            [ viewMetric tips
                { tip = Copy.workRates
                , label = "CPU ns / tick"
                , value = rate .cpuNanosPerDisplayTick |> Maybe.map (Format.decimal 1)
                , sub = "per simulated display tick, this process, all threads"
                , accent = "metric-cyan"
                }
            , viewMetric tips
                { tip = Copy.workRates
                , label = "CPU ns / link"
                , value = rate .cpuNanosPerLinkActivation |> Maybe.map (Format.decimal 2)
                , sub = "per policy link activation, this process, all threads"
                , accent = "metric-cyan"
                }
            , viewMetric tips
                { tip = Copy.workRates
                , label = "Ticks / episode"
                , value = rate .displayTicksPerEpisode |> Maybe.map (Format.decimal 0)
                , sub = "shorter fights do less work, and the rates above say so"
                , accent = ""
                }
            , viewMetric tips
                { tip = Copy.episodesPerSecond
                , label = "Episodes / second"
                , value =
                    if status.episodesPerSecond > 0 then
                        Just (Format.decimal 2 status.episodesPerSecond)

                    else
                        Nothing
                , sub = "wall clock, so load dependent; not a measure of the build"
                , accent = "metric-amber"
                }
            , viewMetric tips
                { tip = Copy.elapsed
                , label = "Elapsed"
                , value = Just (Format.duration status.elapsedSeconds)
                , sub = "summed across resumes"
                , accent = ""
                }
            , viewMetric tips
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
                , sub = "training plus gate play, whole run"
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
                { tip = Copy.combatVictories
                , label = "Combat victories"
                , value = Scoring.combatVictoriesValue status.episodesCombatWins
                , sub = Scoring.combatVictoriesNote status.episodesCombatWins
                , accent = ""
                }
            ]
        , p [ class "prose", Attr.style "margin-top" "14px" ]
            [ text
                (case work of
                    Nothing ->
                        "This process has not computed yet, so there is nothing to divide by and the per-unit-of-work rates are absent rather than zero. Reading a checkpoint from disk is such a process."

                    Just measured ->
                        "Counted over this process only: "
                            ++ Format.count measured.episodes
                            ++ " episodes, "
                            ++ Format.count measured.displayTicks
                            ++ " display ticks and "
                            ++ Format.count measured.linkActivations
                            ++ " link activations. The counters start at zero on every resume and are never checkpointed."
                )
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
                            ", slowed while this tab is hidden."
                       )
                )
            ]
        ]


viewPhaseSplit : Tip.Handlers Msg -> Api.Status -> Html Msg
viewPhaseSplit tips status =
    panel tips
        Copy.phaseSplit
        "Where the time went"
        (case status.phases of
            Nothing ->
                [ div [ class "placeholder" ]
                    [ Html.strong [] [ text Format.awaiting ]
                    , span [] [ text "This process has not spent any compute seconds yet, so there is no split to show. That is no measurement, not a measurement of nothing." ]
                    ]
                ]

            Just split ->
                [ div [ class "alloc" ]
                    (split.buckets
                        |> List.filter (\bucket -> bucket.seconds > 0)
                        |> List.map
                            (\bucket ->
                                shareRow bucket.name
                                    (Just (Format.decimal 2 bucket.seconds ++ "s"))
                                    (Maybe.withDefault 0 bucket.share)
                            )
                    )
                , dl [ class "deflist", Attr.style "margin-top" "16px" ]
                    [ dt [] [ text "Accounted" ]
                    , dd []
                        [ text
                            (Format.decimal 2 split.accountedSeconds
                                ++ "s of "
                                ++ (split.sessionCpuSeconds
                                        |> Maybe.map (\cpu -> Format.decimal 2 cpu ++ "s")
                                        |> Maybe.withDefault Format.awaiting
                                   )
                                ++ " CPU"
                                ++ (split.accountedShareOfCpu
                                        |> Maybe.map (\share -> " (" ++ Format.percent1 share ++ ")")
                                        |> Maybe.withDefault ""
                                   )
                            )
                        ]
                    , dt [] [ text "Unaccounted" ]
                    , dd [] [ text (unaccountedLine split) ]
                    , dt [] [ text "Threads busy" ]
                    , dd []
                        [ text
                            (case split.threadsBusy of
                                Just busy ->
                                    Format.decimal 2 busy
                                        ++ " on average over "
                                        ++ Format.decimal 1 split.sessionWallSeconds
                                        ++ "s of wall time"

                                Nothing ->
                                    Format.awaiting
                            )
                        ]
                    ]
                , p [ class "prose", Attr.style "margin-top" "12px" ]
                    [ text "Shares are of accounted time, so they sum to one; the leftover is on its own line rather than folded into a bucket. Positive leftover is CPU nobody clocked: the supervisor loop, pool dispatch, allocation, the server thread. Negative means workers were preempted mid-fight, so its size is a contention signal rather than an error." ]
                ]
        )


unaccountedLine : Api.PhaseSplit -> String
unaccountedLine split =
    case split.unaccountedSeconds of
        Nothing ->
            Format.awaiting

        Just seconds ->
            (if seconds >= 0 then
                "+"

             else
                "\u{2212}"
            )
                ++ Format.decimal 3 (abs seconds)
                ++ "s"
                ++ (split.unaccountedShareOfCpu
                        |> Maybe.map (\share -> " (" ++ Format.percent1 (abs share) ++ " of CPU)")
                        |> Maybe.withDefault ""
                   )
                ++ (if seconds >= 0 then
                        ", CPU nobody clocked"

                    else
                        ", workers preempted mid-fight"
                   )


viewBenchmark : Tip.Handlers Msg -> Api.Status -> Html Msg
viewBenchmark tips status =
    panel tips
        Copy.benchmark
        "Benchmark reference"
        (case status.benchmark of
            Nothing ->
                [ div [ class "placeholder" ]
                    [ Html.strong [] [ text "Not benchmarked" ]
                    , span [] [ text "No fixed-work benchmark has been recorded for this build. Run melee-mario bench to record one; until then there is nothing to read the live rates against." ]
                    ]
                ]

            Just recorded ->
                [ div [ class "metrics" ]
                    [ viewMetric tips
                        { tip = Copy.benchmark
                        , label = "Best of N"
                        , value = recorded.bestSeconds |> Maybe.map (\s -> Format.decimal 3 s ++ "s")
                        , sub =
                            "fastest of "
                                ++ (recorded.repetitions |> Maybe.map String.fromInt |> Maybe.withDefault "several")
                                ++ " repetitions over "
                                ++ (recorded.fights |> Maybe.map String.fromInt |> Maybe.withDefault "the")
                                ++ " fixed fights"
                        , accent = "metric-cyan"
                        }
                    , viewMetric tips
                        { tip = Copy.benchmark
                        , label = "CPU ns / tick"
                        , value = recorded.cpuNanosPerDisplayTick |> Maybe.map (Format.decimal 1)
                        , sub = "single threaded, no duty governor, no nice"
                        , accent = ""
                        }
                    , viewMetric tips
                        { tip = Copy.benchmark
                        , label = "CPU ns / link"
                        , value = recorded.cpuNanosPerLinkActivation |> Maybe.map (Format.decimal 2)
                        , sub = "same quantity the live figure reports"
                        , accent = ""
                        }
                    ]
                , dl [ class "deflist", Attr.style "margin-top" "16px" ]
                    [ dt [] [ text "Recorded" ]
                    , dd []
                        [ text
                            (Maybe.withDefault "time not reported" recorded.at
                                ++ " \u{00B7} best of "
                                ++ String.fromInt recorded.comparableRows
                                ++ " comparable "
                                ++ (if recorded.comparableRows == 1 then
                                        "result"

                                    else
                                        "results"
                                   )
                            )
                        ]
                    , dt [] [ text "Workload" ]
                    , dd [] [ text (Maybe.withDefault "not reported" recorded.definition) ]
                    , dt [] [ text "Build" ]
                    , dd [] [ text (Maybe.withDefault "not reported" recorded.build) ]
                    ]
                , p [ class "prose", Attr.style "margin-top" "12px" ]
                    [ text (benchmarkComparison status) ]
                ]
        )


{-| The live rate against the recorded one, in words.

Both are CPU nanoseconds per display tick, so they are directly
comparable; the gap is what this session's contention and worker spill
are costing over what the build costs with the machine to itself.

-}
benchmarkComparison : Api.Status -> String
benchmarkComparison status =
    case
        ( status.benchmark |> Maybe.andThen .cpuNanosPerDisplayTick
        , status.work |> Maybe.andThen .cpuNanosPerDisplayTick
        )
    of
        ( Just recorded, Just live ) ->
            if recorded <= 0 then
                "The recorded benchmark reports no cost per tick, so there is nothing to compare the live rate against."

            else
                "This session is running at "
                    ++ Format.decimal 2 (live / recorded)
                    ++ "x the recorded cost per simulated tick. Above one is the price of sharing the machine and of spilling workers onto slower cores; it is not a change in the build."

        _ ->
            "A live rate and a recorded rate are both needed to compare them, and one of the two has not been measured."


viewMachine : Tip.Handlers Msg -> Api.Status -> Html Msg
viewMachine tips status =
    let
        checkpoint =
            status.checkpoint

        resources =
            status.resources
    in
    panel tips
        Copy.resourcesWorkers
        "Machine and checkpoint"
        [ dl [ class "deflist" ]
            ([ dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesWorkers [ text "Threads" ] ]
             , dd [] [ text (Resources.threadsLine resources) ]
             , dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesDuty [ text "Duty cycle" ] ]
             , dd [] [ text (Resources.dutyLine resources) ]
             ]
                ++ (case Resources.budgetLine resources of
                        Just budget ->
                            [ dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesBudget [ text "Compute budget" ] ]
                            , dd [] [ text budget ]
                            ]

                        Nothing ->
                            []
                   )
                ++ [ dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesBudget [ text "Compute spent" ] ]
                   , dd [] [ text (Format.duration resources.computeSeconds ++ " of wall time actually computing, whole run") ]
                   , dt [] [ Tip.view tips Tip.AlignStart Copy.resourcesWorkers [ text "Nice" ] ]
                   , dd [] [ text (String.fromInt resources.nice ++ ", this invocation only") ]
                   , dt [] [ Tip.view tips Tip.AlignStart Copy.checkpointSaved [ text "Saved" ] ]
                   , dd [] [ text (Maybe.withDefault "never in this run" checkpoint.savedAt) ]
                   , dt [] [ Tip.view tips Tip.AlignStart Copy.checkpointGeneration [ text "On disk" ] ]
                   , dd [] [ text (Format.count checkpoint.generation ++ ", the generation a resume would start from") ]
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
                   , dt [] [ Tip.view tips Tip.AlignStart Copy.runId [ text "Run" ] ]
                   , dd [] [ text status.runId ]
                   ]
            )
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
