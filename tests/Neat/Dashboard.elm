module Neat.Dashboard exposing (main)

{-| Live trainer dashboard. Hover (i) for plain-language explainers.
-}

import Array exposing (Array)
import Browser
import Html exposing (Html, button, div, h1, h2, h3, p, span, text)
import Html.Attributes as A
import Html.Events as HE
import Http
import Json.Decode as D
import Json.Decode.Pipeline as P
import Svg
import Svg.Attributes as SA
import Svg.Events as SE
import Time


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( init, Cmd.batch [ fetch, fetchNet, fetchReview ] )
        , update = update
        , view = view
        , subscriptions = \_ -> Time.every 2000 Tick
        }


type alias Model =
    { status : Maybe Status
    , err : Maybe String
    , hoverFit : Maybe Int
    , hoverCrew : Maybe Int
    , explainer : Maybe Explainer
    , pinned : Bool
    , net : Maybe NetPic
    , review : Maybe Review
    , reviewError : String
    }


type alias Review =
    { phase : String
    , lane : String
    , hypothesis : String
    , error : String
    , age : Float
    , active : Bool
    , next : Float
    , now : Float
    , history : List ReviewResult
    , trialGeneration : Int
    , targetGenerations : Int
    , screen : String
    , freshCheck : String
    }


type alias ReviewResult =
    { cycle : Int
    , lane : String
    , decision : String
    , baseline : Int
    , challenger : Int
    , fights : Int
    , hypothesis : String
    , arguments : List String
    }


fetchReview : Cmd Msg
fetchReview =
    Http.get { url = "/api/review", expect = Http.expectJson GotReview reviewDecoder }


reviewDecoder : D.Decoder Review
reviewDecoder =
    D.succeed Review
        |> P.optional "phase" D.string "waiting"
        |> P.optional "lane" D.string "research"
        |> P.optional "hypothesis" D.string "First review pending"
        |> P.optional "error" D.string ""
        |> P.required "status_age_s" D.float
        |> P.required "trainer_active" D.bool
        |> P.optional "next_review_at" D.float 0
        |> P.required "server_time" D.float
        |> P.optional "history" (D.list reviewResultDecoder) []
        |> P.optional "trial_generation" D.int 0
        |> P.optional "target_generations" D.int 160
        |> P.optional "screen" (D.oneOf [ D.map2 (\b c -> "40-generation screening: baseline " ++ String.fromInt b ++ ", challenger " ++ String.fromInt c ++ " wins / 90 fights. These seeds cannot qualify a deployment.") (D.field "baseline" D.int) (D.field "challenger" D.int), D.null "" ]) ""
        |> P.optional "health_check" (D.oneOf [ D.at [ "fresh_check" ] (D.map3 (\before after count -> "Last fresh-seed check: " ++ String.fromInt before ++ " → " ++ String.fromInt after ++ " wins / " ++ String.fromInt count ++ " fresh fights versus its reference policy. This is diagnostic, not a deployment decision.") (D.field "before_wins" D.int) (D.field "after_wins" D.int) (D.field "fights" D.int)), D.succeed "" ]) ""


reviewResultDecoder : D.Decoder ReviewResult
reviewResultDecoder =
    D.succeed ReviewResult
        |> P.required "cycle" D.int
        |> P.required "lane" D.string
        |> P.required "decision" D.string
        |> P.optional "baseline_wins" D.int -1
        |> P.optional "challenger_wins" D.int -1
        |> P.optional "audit_fights" D.int 0
        |> P.optional "hypothesis" D.string "Interrupted before completion"
        |> P.optional "arguments" (D.map2 (\a b -> [ "Case for: " ++ a, "Case against: " ++ b ]) (D.field "case_for" D.string) (D.field "case_against" D.string)) []


reviewCard : Model -> Html Msg
reviewCard model =
    div [ A.style "background" card, A.style "padding" "18px", A.style "border-radius" "12px", A.style "margin-bottom" "20px" ]
        [ h2 [ A.style "font-size" "17px", A.style "margin-top" "0" ] [ text "Is the policy actually improving?" ]
        , if model.reviewError /= "" then
            p [ A.style "color" coral ] [ text ("Review monitor unavailable: " ++ model.reviewError) ]
          else
            text ""
        , case model.review of
            Nothing ->
                text "Waiting for the independent review monitor."

            Just r ->
                div []
                    [ div [ A.style "display" "grid", A.style "grid-template-columns" "repeat(auto-fit,minmax(180px,1fr))", A.style "gap" "12px" ]
                        [ metric "Training health"
                            (if not r.active then "STOPPED" else if r.age > 30 then "STALE" else "LIVE")
                            (r.active && r.age <= 30)
                            { title = "Training health", body = [ "Checks the actual service and status file age. Last status write was " ++ fmt1 r.age ++ " seconds ago. A stale file is not live progress." ] }
                        , metric "Review cycle" (r.lane ++ " / " ++ r.phase) False
                            { title = "Equal experiment lanes", body = [ "Research, creative, radical, one turn each. These are programmed recipes with changing seeds and parameters, not an autonomous LLM reading new papers." ] }
                        , metric "Next scheduled review"
                            (if r.next <= 0 then "pending" else if r.next <= r.now then "due / running" else uptime (r.next - r.now)) False
                            { title = "Hourly experiments, frequent checks", body = [ "New experiments run hourly, with automated health checks every 15 minutes. Trials get a 40-generation screening checkpoint before the full 160-generation comparison. Only independently confirmed gains deploy." ] }
                        ]
                    , p [ A.style "line-height" "1.5" ] [ text r.hypothesis ]
                    , if r.phase == "baseline" || r.phase == "challenger" then p [ A.style "color" mute ] [ text (r.phase ++ ": generation " ++ String.fromInt r.trialGeneration ++ " / " ++ String.fromInt r.targetGenerations ++ ". Both arms get the same fight budget.") ] else text ""
                    , if r.screen /= "" && r.phase /= "waiting" then p [ A.style "color" gold ] [ text r.screen ] else text ""
                    , p [ A.style "color" mute, A.style "font-size" "13px" ] [ text "Keep rule: at least 8 extra wins on 360 fresh fights, then beat the baseline and live champion on another 360. Failed ideas stay in the ledger; the live champion stays protected." ]
                    , if r.freshCheck /= "" then p [ A.style "color" ink ] [ text r.freshCheck ] else text ""
                    , if r.error /= "" then p [ A.style "color" coral ] [ text r.error ] else text ""
                    , if List.isEmpty r.history then
                        p [ A.style "color" mute ] [ text "No completed reviews yet. Fresh-seed improvement has not been demonstrated." ]
                      else
                        div [] (List.map reviewRow (List.take 12 (List.reverse r.history)))
                    ]
        ]


reviewRow : ReviewResult -> Html Msg
reviewRow r =
    div
        [ A.style "padding" "12px 0", A.style "border-top" ("1px solid " ++ line)
        , A.style "cursor" "help", HE.onMouseEnter (ShowExplainer { title = "Experiment " ++ String.fromInt (r.cycle + 1), body = r.hypothesis :: r.arguments ++ [ "Fresh audit seeds are never used for training. The comparison uses the same fight budget. A rejected result is retained as evidence." ] })
        , HE.onMouseLeave HideExplainer
        , HE.onClick (PinExplainer { title = r.lane ++ " experiment", body = r.hypothesis :: r.arguments })
        ]
        [ span [ A.style "color" (if r.decision == "deployed" then mint else mute) ]
            [ text ("#" ++ String.fromInt (r.cycle + 1) ++ " · " ++ r.lane ++ " · " ++ r.decision) ]
        , div [ A.style "margin-top" "5px" ]
            [ text (if r.fights == 0 then "No completed audit" else "Baseline " ++ String.fromInt r.baseline ++ " → challenger " ++ String.fromInt r.challenger ++ " wins / " ++ String.fromInt r.fights ++ " fresh fights") ]
        ]


type alias NetPic =
    { generation : Int
    , nIn : Int
    , nHidden : Int
    , nOut : Int
    , weights : Array Float
    }


type alias Explainer =
    { title : String
    , body : List String
    }


type alias Status =
    { generation : Int
    , bestFitness : Float
    , meanFitness : Float
    , wins : Int
    , own : Float
    , enemy : Float
    , evalS : Float
    , lives : Int
    , sigma : Float
    , pop : Int
    , episodeTicks : Int
    , notes : String
    , history : List Point
    , hall : List Hall
    , error : String
    , paused : Bool
    , gpu : Bool
    , uptimeS : Float
    , fitnessVersion : String
    , nTrain : Int
    , nHold : Int
    , pool : List String
    , champion : Champion
    , experiment : String
    , phase : String
    , evaluator : String
    , generationS : Float
    , scoringVersion : String
    }


type alias Champion =
    { generation : Int
    , fitness : Float
    , coreDual : Bool
    , seatWins : Int
    , fights : List Fight
    }


type alias Fight =
    { seed : Int
    , swap : Bool
    , us : String
    , them : String
    , foe : String
    , group : String
    , winner : String
    , outcome : String
    , own : Int
    , enemy : Int
    , ticks : Int
    }


type alias Point =
    { gen : Int
    , mean : Float
    , best : Float
    , own : Float
    , enemy : Float
    , wins : Int
    }


type alias Hall =
    { gen : Int
    , fitness : Float
    , winner : String
    , own : Int
    , enemy : Int
    , file : String
    }


type alias Series =
    { label : String
    , color : String
    , values : List Float
    }


type Msg
    = Tick Time.Posix
    | Got (Result Http.Error Status)
    | GotNet (Result Http.Error NetPic)
    | GotReview (Result Http.Error Review)
    | HoverFit (Maybe Int)
    | HoverCrew (Maybe Int)
    | ShowExplainer Explainer
    | HideExplainer
    | PinExplainer Explainer
    | Unpin


init : Model
init =
    { status = Nothing
    , err = Nothing
    , hoverFit = Nothing
    , hoverCrew = Nothing
    , explainer = Nothing
    , pinned = False
    , net = Nothing
    , review = Nothing
    , reviewError = ""
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            ( model, Cmd.batch [ fetch, fetchReview ] )

        Got (Ok s) ->
            let
                needNet =
                    case model.net of
                        Nothing ->
                            True

                        Just n ->
                            n.generation /= s.champion.generation
                                || (Maybe.map .experiment model.status /= Just s.experiment)
            in
            ( { model | status = Just s, err = if s.error == "" then Nothing else Just s.error }
            , if needNet then
                fetchNet

              else
                Cmd.none
            )

        Got (Err e) ->
            ( { model | err = Just (httpErr e) }, Cmd.none )

        GotReview (Ok r) ->
            ( { model | review = Just r, reviewError = "" }, Cmd.none )

        GotReview (Err e) ->
            ( { model | reviewError = httpErr e }, Cmd.none )

        GotNet (Ok n) ->
            ( { model | net = Just n }, Cmd.none )

        GotNet (Err _) ->
            ( model, Cmd.none )

        HoverFit i ->
            ( { model | hoverFit = i }, Cmd.none )

        HoverCrew i ->
            ( { model | hoverCrew = i }, Cmd.none )

        ShowExplainer e ->
            if model.pinned then
                ( model, Cmd.none )

            else
                ( { model | explainer = Just e }, Cmd.none )

        HideExplainer ->
            if model.pinned then
                ( model, Cmd.none )

            else
                ( { model | explainer = Nothing }, Cmd.none )

        PinExplainer e ->
            ( { model | explainer = Just e, pinned = True }, Cmd.none )

        Unpin ->
            ( { model | explainer = Nothing, pinned = False }, Cmd.none )


fetch : Cmd Msg
fetch =
    Http.get { url = "/api/status", expect = Http.expectJson Got statusDecoder }


fetchNet : Cmd Msg
fetchNet =
    Http.get { url = "/api/net", expect = Http.expectJson GotNet netDecoder }


netDecoder : D.Decoder NetPic
netDecoder =
    D.succeed rawNet
        |> P.optional "generation" D.int 0
        |> P.optional "n_in" D.int 57
        |> P.optional "n_hidden" D.int 16
        |> P.optional "n_out" D.int 13
        |> P.optional "weights" (D.list floatish) []
        |> D.andThen acceptNet


type alias RawNet =
    { generation : Int
    , nIn : Int
    , nHidden : Int
    , nOut : Int
    , weights : List Float
    }


rawNet : Int -> Int -> Int -> Int -> List Float -> RawNet
rawNet g ni nh no w =
    { generation = g, nIn = ni, nHidden = nh, nOut = no, weights = w }


acceptNet : RawNet -> D.Decoder NetPic
acceptNet r =
    if List.length r.weights == r.nHidden * r.nIn + r.nOut * (r.nHidden + 1) && r.nIn > 0 && r.nHidden > 0 && r.nOut > 0 then
        D.succeed { generation = r.generation, nIn = r.nIn, nHidden = r.nHidden, nOut = r.nOut, weights = Array.fromList r.weights }

    else
        D.fail "net width"


httpErr : Http.Error -> String
httpErr e =
    case e of
        Http.BadUrl u ->
            "bad url " ++ u

        Http.Timeout ->
            "status timed out"

        Http.NetworkError ->
            "cannot reach trainer"

        Http.BadStatus n ->
            "status HTTP " ++ String.fromInt n

        Http.BadBody b ->
            "bad json: " ++ b


intish : D.Decoder Int
intish =
    D.oneOf [ D.int, D.map round D.float, D.succeed 0 ]


boolish : D.Decoder Bool
boolish =
    D.oneOf [ D.bool, D.null False ]


floatish : D.Decoder Float
floatish =
    D.oneOf [ D.float, D.map toFloat D.int ]


statusDecoder : D.Decoder Status
statusDecoder =
    D.succeed Status
        |> P.required "generation" D.int
        |> P.required "best_fitness" floatish
        |> P.required "mean_fitness" floatish
        |> P.optional "wins" D.int 0
        |> P.required "own" floatish
        |> P.required "enemy" floatish
        |> P.optional "eval_s" floatish 0
        |> P.optional "lives" D.int 0
        |> P.optional "sigma" floatish 0
        |> P.optional "pop" D.int 0
        |> P.optional "episode_ticks" D.int 0
        |> P.optional "notes" D.string ""
        |> P.optional "history" (D.list pointDecoder) []
        |> P.optional "hall" (D.list hallDecoder) []
        |> P.optional "error" D.string ""
        |> P.optional "paused" D.bool False
        |> P.optional "gpu" D.bool False
        |> P.optional "uptime_s" floatish 0
        |> P.optional "fitness_version" D.string ""
        |> P.optional "n_train" D.int 0
        |> P.optional "n_hold" D.int 0
        |> P.optional "pool" (D.list D.string) []
        |> P.optional "champion" championDecoder emptyChampion
        |> P.optional "experiment" D.string ""
        |> P.optional "phase" D.string ""
        |> P.optional "evaluator" D.string "elm"
        |> P.optional "generation_s" floatish 0
        |> P.optional "scoring_version" D.string "unknown"


emptyChampion : Champion
emptyChampion =
    { generation = 0, fitness = 0, coreDual = False, seatWins = 0, fights = [] }


championDecoder : D.Decoder Champion
championDecoder =
    D.succeed Champion
        |> P.optional "generation" D.int 0
        |> P.optional "fitness" floatish 0
        |> P.optional "core_dual" boolish False
        |> P.optional "seat_wins" D.int 0
        |> P.optional "scenarios" (D.list fightDecoder) []


fightDecoder : D.Decoder Fight
fightDecoder =
    D.succeed Fight
        |> P.optional "seed" D.int 0
        |> P.optional "swap" D.bool False
        |> P.optional "us" D.string ""
        |> P.optional "them" D.string ""
        |> P.optional "foe" D.string "cyborg"
        |> P.optional "group" D.string ""
        |> P.optional "winner" D.string ""
        |> P.optional "outcome" D.string ""
        |> P.optional "own" intish 0
        |> P.optional "enemy" intish 0
        |> P.optional "ticks" D.int 0


pointDecoder : D.Decoder Point
pointDecoder =
    D.map6 Point
        (D.field "gen" D.int)
        (D.field "mean" floatish)
        (D.field "best" floatish)
        (D.field "own" floatish)
        (D.field "enemy" floatish)
        (D.oneOf [ D.field "wins" D.int, D.succeed 0 ])


hallDecoder : D.Decoder Hall
hallDecoder =
    D.map6 Hall
        (D.field "gen" D.int)
        (D.field "fitness" floatish)
        (D.oneOf [ D.field "winner" D.string, D.succeed "" ])
        (D.oneOf [ D.field "own" intish, D.succeed 0 ])
        (D.oneOf [ D.field "enemy" intish, D.succeed 0 ])
        (D.oneOf [ D.field "file" D.string, D.succeed "" ])


bg : String
bg =
    "#0f1419"


card : String
card =
    "#1a222c"


ink : String
ink =
    "#e8eef4"


mute : String
mute =
    "#9aa8b5"


line : String
line =
    "#2a3542"


gold : String
gold =
    "#e0c29b"


mint : String
mint =
    "#5dcea8"


coral : String
coral =
    "#ff6b6b"


sky : String
sky =
    "#7eb6ff"


view : Model -> Html Msg
view model =
    div
        [ A.style "min-height" "100vh"
        , A.style "background" bg
        , A.style "color" ink
        , A.style "font-family" "ui-sans-serif, system-ui, sans-serif"
        , A.style "padding" "24px 20px 48px"
        , A.style "max-width" "1100px"
        , A.style "margin" "0 auto"
        ]
        [ header model
        , hintBar model
        , case model.status of
            Nothing ->
                p [ A.style "color" mute ] [ text (Maybe.withDefault "Waiting for the trainer." model.err) ]

            Just s ->
                div []
                    [ metrics s
                    , reviewCard model
                    , matchupGrid s
                    , charts model s
                    , Html.details [ A.style "margin" "20px 0" ] [ Html.summary [ A.style "cursor" "pointer", A.style "padding" "14px" ] [ text (String.fromInt (List.length s.champion.fights) ++ " validation fights: seeds, seats, crew and outcomes") ], holdTable s ]
                    , Html.details [] [ Html.summary [ A.style "cursor" "pointer", A.style "padding" "14px" ] [ text "Explore the saved neural network" ], netCard model s ]
                    ]
        , case model.err of
            Just e ->
                p [ A.style "color" coral, A.style "margin-top" "16px" ] [ text e ]

            Nothing ->
                text ""
        , explainerModal model
        ]


header : Model -> Html Msg
header model =
    div [ A.style "margin-bottom" "12px" ]
        [ div [ A.style "display" "flex", A.style "align-items" "center", A.style "gap" "10px" ]
            [ h1
                [ A.style "font-size" "22px"
                , A.style "font-weight" "650"
                , A.style "margin" "0"
                ]
                [ text "Melee policy training" ]
            , infoBtn pageExplainer
            ]
        , p [ A.style "color" mute, A.style "margin" "8px 0 0", A.style "max-width" "72ch", A.style "line-height" "1.5", A.style "font-size" "14px" ]
            [ text "One net learning to fly Super Melee ships against the original Awesome cyborg. Hover any (i) for a plain-language explainer. Click (i) to pin it." ]
        , case model.status of
            Just s ->
                p [ A.style "color" mute, A.style "margin" "8px 0 0", A.style "font-size" "13px" ]
                    [ text
                        ((s.experiment |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault "training")
                            ++ "  ·  "
                            ++ s.phase
                            ++ " | "
                            ++ s.evaluator ++ " / " ++ s.scoringVersion
                            ++ "  ·  "
                            ++ uptime s.uptimeS
                            ++ "  ·  gen "
                            ++ String.fromInt s.generation
                            ++ "  ·  "
                            ++ (if String.trim s.fitnessVersion == "" then
                                    "no version"

                                else
                                    s.fitnessVersion
                               )
                            ++ "  ·  pool "
                            ++ (if List.isEmpty s.pool then
                                    "?"

                                else
                                    String.join ", " s.pool
                               )
                            ++ "  ·  "
                            ++ String.fromInt s.nTrain
                            ++ " train / "
                            ++ String.fromInt s.nHold
                            ++ " hold"
                            ++ (if s.paused then
                                    "  ·  PAUSED"

                                else
                                    ""
                               )
                        )
                    ]

            Nothing ->
                text ""
        ]


hintBar : Model -> Html Msg
hintBar model =
    p
        [ A.style "color" mute
        , A.style "font-size" "13px"
        , A.style "margin" "12px 0 18px"
        ]
        [ text
            (if model.pinned then
                "Explainer pinned. Click the dimmed area or Close to dismiss."

             else
                "Watch fresh-seed improvement and time since the last better champion. Generations and evaluations measure activity, not learning."
            )
        ]


metrics : Status -> Html Msg
metrics s =
    let
        holdN =
            List.length s.champion.fights

        holdWins =
            List.length (List.filter fightWon s.champion.fights)

        poolLabel =
            if List.isEmpty s.pool then
                "?"

            else
                String.join ", " s.pool
    in
    div
        [ A.style "display" "grid"
        , A.style "grid-template-columns" "repeat(auto-fit, minmax(160px, 1fr))"
        , A.style "gap" "12px"
        , A.style "margin-bottom" "22px"
        ]
        [ metric "Saved validation wins" (String.fromInt holdWins ++ " / " ++ String.fromInt (max holdN s.nHold)) False (holdRecordExplainer holdWins (max holdN s.nHold) s)
        , metric "Generations since promotion" (String.fromInt (max 0 (s.generation - s.champion.generation))) False
            { title = "Plateau age", body = [ "Completed generations since the saved champion was promoted. A large number means the search is active without finding a better validation policy. A promotion can improve only the fitness tiebreaker, not wins." ] }
        , metric "Generation duration" (fmt2 s.generationS ++ " s") False
            { title = "Full generation duration", body = [ "Measured time for a completed generation, including candidate evaluations and validation. This is different from a single candidate's evaluation time." ] }
        , metric "Evaluations / second"
            (if s.generationS > 0 then fmt1 (toFloat ((s.pop + 1) * s.nTrain + s.nHold) / s.generationS) else "waiting") False
            { title = "Approximate fight throughput", body = [ "Candidate count times training fights, plus validation fights, divided by generation duration. Useful for capacity, not evidence of learning." ] }

        ]


metric : String -> String -> Bool -> Explainer -> Html Msg
metric label value win e =
    div
        [ A.style "background" card
        , A.style "border" ("1px solid " ++ line)
        , A.style "border-radius" "10px"
        , A.style "padding" "12px 14px"
        , A.style "cursor" "help"
        , HE.onMouseEnter (ShowExplainer e)
        , HE.onMouseLeave HideExplainer
        , HE.onClick (PinExplainer e)
        ]
        [ div [ A.style "display" "flex", A.style "align-items" "center", A.style "justify-content" "space-between" ]
            [ div [ A.style "color" mute, A.style "font-size" "11px", A.style "letter-spacing" "0.04em", A.style "text-transform" "uppercase" ] [ text label ]
            , infoDot
            ]
        , div
            [ A.style "font-size" "22px"
            , A.style "font-weight" "650"
            , A.style "margin-top" "4px"
            , A.style "color"
                (if win then
                    mint

                 else
                    ink
                )
            , A.style "font-variant-numeric" "tabular-nums"
            ]
            [ text value ]
        ]


matchupGrid : Status -> Html Msg
matchupGrid s =
    div [ A.style "margin-bottom" "20px" ]
        [ h2 [ A.style "font-size" "17px" ] [ text "Where the champion wins and gets stuck" ]
        , div [ A.style "display" "grid", A.style "grid-template-columns" "repeat(auto-fit,minmax(220px,1fr))", A.style "gap" "10px" ]
            (List.concatMap
                (\us -> List.map
                    (\them ->
                        let
                            fights = List.filter (\f -> f.us == us && f.them == them) s.champion.fights
                            wins = List.filter fightWon fights |> List.length
                            bottom = List.filter (\f -> not f.swap && fightWon f) fights |> List.length
                            top = List.filter (\f -> f.swap && fightWon f) fights |> List.length
                            timeouts = List.filter (\f -> f.outcome == "invalidated") fights |> List.length
                        in
                        metric (us ++ " vs " ++ them) (String.fromInt wins ++ " / " ++ String.fromInt (List.length fights)) (wins == List.length fights && wins > 0)
                            { title = us ++ " vs " ++ them
                            , body = [ "Saved validation wins. Bottom seat: " ++ String.fromInt bottom ++ ". Top seat: " ++ String.fromInt top ++ ". Timeouts: " ++ String.fromInt timeouts ++ ".", "A zero or seat imbalance identifies a weakness. These fixed validation results are not fresh-seed evidence. Expand the fight list for crew and individual seeds." ] }
                    ) s.pool
                ) s.pool)
        ]


holdTable : Status -> Html Msg
holdTable s =
    let
        fights =
            s.champion.fights

        groups =
            fights
                |> List.map (\f -> f.us ++ " vs " ++ f.them)
                |> List.foldl
                    (\k acc ->
                        if List.member k acc then
                            acc

                        else
                            acc ++ [ k ]
                    )
                    []
    in
    div
        [ A.style "background" card
        , A.style "border" ("1px solid " ++ line)
        , A.style "border-radius" "12px"
        , A.style "padding" "16px 18px"
        , A.style "margin-bottom" "22px"
        ]
        [ div [ A.style "display" "flex", A.style "align-items" "center", A.style "gap" "8px" ]
            [ h2 [ A.style "font-size" "15px", A.style "margin" "0" ]
                [ text
                    ("Exam fights  ·  saved champion from gen "
                        ++ String.fromInt s.champion.generation
                        ++ (if List.isEmpty s.champion.fights then
                                "  ·  none yet"

                            else
                                ""
                           )
                    )
                ]
            , infoBtn (holdTableExplainer s)
            ]
        , p [ A.style "color" mute, A.style "font-size" "13px", A.style "margin" "8px 0 12px", A.style "line-height" "1.45" ]
            [ text ("These " ++ String.fromInt (List.length fights) ++ " validation fights use fixed seeds within this run. Repeated selection can overfit them; independent audits test generalization. Hover a row.") ]
        , if List.isEmpty fights then
            p [ A.style "color" mute ] [ text "No champion fights on status yet. Wait one generation after a trainer restart." ]

          else
            div []
                (div
                    [ A.style "display" "grid"
                    , A.style "grid-template-columns" "1.4fr 0.7fr 0.8fr 0.9fr 1.1fr"
                    , A.style "gap" "8px"
                    , A.style "color" mute
                    , A.style "font-size" "11px"
                    , A.style "letter-spacing" "0.04em"
                    , A.style "text-transform" "uppercase"
                    , A.style "padding" "0 0 6px"
                    ]
                    [ span [] [ text "Our ship vs theirs" ]
                    , span [] [ text "Our seat" ]
                    , span [] [ text "Result" ]
                    , span [] [ text "Crew left" ]
                    , span [] [ text "Duration" ]
                    ]
                    :: List.concatMap (\k -> groupBlock k (List.filter (\f -> (f.us ++ " vs " ++ f.them) == k) fights)) groups
                )
        ]


groupBlock : String -> List Fight -> List (Html Msg)
groupBlock title fights =
    if List.isEmpty fights then
        []

    else
        [ p [ A.style "color" gold, A.style "font-size" "12px", A.style "letter-spacing" "0.04em", A.style "text-transform" "uppercase", A.style "margin" "12px 0 6px" ] [ text (title ++ "  ·  Awesome cyborg") ]
        , div [] (List.map fightRow fights)
        ]


fightRow : Fight -> Html Msg
fightRow f =
    let
        seat =
            if f.swap then
                "top"

            else
                "bottom"

        won =
            fightWon f
    in
    div
        [ A.class "fight-row"
        , A.style "display" "grid"
        , A.style "grid-template-columns" "1.4fr 0.7fr 0.8fr 0.9fr 1.1fr"
        , A.style "gap" "8px"
        , A.style "padding" "8px 0"
        , A.style "border-top" ("1px solid " ++ line)
        , A.style "font-size" "13px"
        , A.style "font-variant-numeric" "tabular-nums"
        , A.style "cursor" "help"
        , A.style "align-items" "center"
        , HE.onMouseEnter (ShowExplainer (fightExplainer f))
        , HE.onMouseLeave HideExplainer
        , HE.onClick (PinExplainer (fightExplainer f))
        ]
        [ span [] [ text (f.us ++ " vs " ++ f.them) ]
        , span [ A.style "color" mute ] [ text seat ]
        , span
            [ A.style "color"
                (if won then
                    mint

                 else
                    coral
                )
            , A.style "font-weight" "650"
            ]
            [ text
                (if won then
                    "KILL"

                 else if f.outcome == "invalidated" then
                    "TIMEOUT"

                 else
                    "LOSS"
                )
            ]
        , span [ A.style "color" mute ] [ text ("us " ++ String.fromInt f.own ++ "  them " ++ String.fromInt f.enemy) ]
        , span [ A.style "color" mute ] [ text (secs f.ticks ++ "  ·  " ++ String.fromInt f.ticks ++ " ticks") ]
        ]


fightWon : Fight -> Bool
fightWon f =
    let
        seat =
            if f.swap then
                "top"

            else
                "bottom"
    in
    f.outcome == "completed" && f.winner == seat && f.enemy == 0


secs : Int -> String
secs ticks =
    let
        n =
            toFloat ticks / 60
    in
    fmt1 n ++ "s"


charts : Model -> Status -> Html Msg
charts model s =
    let
        hist =
            s.history
    in
    div
        [ A.style "display" "grid"
        , A.style "gap" "16px"
        ]
        [ chartCard
            "Saved champion score"
            "Validation score only. A flat line means no better champion was saved. This is a fitness tiebreaker, not a win count. History belongs to this run."
            (scoreChartExplainer s)
            [ { label = "saved validation score", color = mint, values = List.map .best hist }
            ]
            hist
            model.hoverFit
            HoverFit

        ]


chartCard : String -> String -> Explainer -> List Series -> List Point -> Maybe Int -> (Maybe Int -> Msg) -> Html Msg
chartCard title blurb e series history hover hoverMsg =
    div
        [ A.style "background" card
        , A.style "border" ("1px solid " ++ line)
        , A.style "border-radius" "12px"
        , A.style "padding" "16px 16px 8px"
        ]
        [ div [ A.style "display" "flex", A.style "align-items" "center", A.style "gap" "8px" ]
            [ h2 [ A.style "font-size" "15px", A.style "margin" "0", A.style "font-weight" "650" ] [ text title ]
            , infoBtn e
            ]
        , p [ A.style "color" mute, A.style "font-size" "13px", A.style "margin" "8px 0 12px", A.style "line-height" "1.45" ] [ text blurb ]
        , legend series
        , if List.length history < 2 then
            p [ A.style "color" mute, A.style "font-size" "13px" ] [ text ("Waiting for two completed generations in this experiment. Completed: " ++ String.fromInt (List.length history) ++ ". The evaluation counter advances while the next generation runs.") ]

          else
            viewChart series history hover hoverMsg
        ]


legend : List Series -> Html Msg
legend series =
    div [ A.style "display" "flex", A.style "gap" "16px", A.style "margin-bottom" "8px", A.style "font-size" "12px", A.style "color" mute ]
        (List.map
            (\s ->
                span []
                    [ span [ A.style "display" "inline-block", A.style "width" "10px", A.style "height" "10px", A.style "border-radius" "2px", A.style "background" s.color, A.style "margin-right" "6px" ] []
                    , text s.label
                    ]
            )
            series
        )


viewChart : List Series -> List Point -> Maybe Int -> (Maybe Int -> Msg) -> Html Msg
viewChart series history hover hoverMsg =
    let
        n =
            List.length history

        chartW =
            920

        chartH =
            260

        padL =
            58

        padR =
            16

        padT =
            16

        padB =
            28

        plotW =
            chartW - padL - padR

        plotH =
            chartH - padT - padB

        allVals =
            List.concatMap .values series

        lo0 =
            List.minimum allVals |> Maybe.withDefault 0

        hi0 =
            List.maximum allVals |> Maybe.withDefault 1

        lo =
            min lo0 0

        hi =
            if hi0 == lo then
                lo + 1

            else
                hi0

        xStep =
            if n <= 1 then
                toFloat plotW

            else
                toFloat plotW / toFloat (n - 1)

        yOf v =
            toFloat padT + toFloat plotH * (1 - (v - lo) / (hi - lo))

        xOf i =
            toFloat padL + toFloat i * xStep

        grid =
            List.range 0 4
                |> List.map
                    (\i ->
                        let
                            val =
                                lo + (hi - lo) * toFloat i / 4

                            y =
                                yOf val
                        in
                        Svg.g []
                            [ Svg.line
                                [ SA.x1 (String.fromInt padL)
                                , SA.x2 (String.fromInt (padL + plotW))
                                , SA.y1 (String.fromFloat y)
                                , SA.y2 (String.fromFloat y)
                                , SA.stroke line
                                , SA.strokeWidth "0.5"
                                , SA.strokeDasharray "3,3"
                                ]
                                []
                            , Svg.text_
                                [ SA.x (String.fromInt (padL - 8))
                                , SA.y (String.fromFloat (y + 3.5))
                                , SA.textAnchor "end"
                                , SA.fill mute
                                , SA.fontSize "10"
                                , SA.fontFamily "ui-monospace, monospace"
                                ]
                                [ Svg.text (fmtScore val) ]
                            ]
                    )

        polylines =
            series
                |> List.concatMap
                    (\s ->
                        let
                            pts =
                                s.values
                                    |> List.indexedMap (\i v -> String.fromFloat (xOf i) ++ "," ++ String.fromFloat (yOf v))
                                    |> String.join " "
                        in
                        [ Svg.polyline
                            [ SA.points pts
                            , SA.fill "none"
                            , SA.stroke s.color
                            , SA.strokeWidth "2"
                            , SA.strokeLinejoin "round"
                            , SA.strokeLinecap "round"
                            ]
                            []
                        ]
                    )

        hits =
            history
                |> List.indexedMap
                    (\i _ ->
                        Svg.rect
                            [ SA.x (String.fromFloat (xOf i - xStep / 2))
                            , SA.y (String.fromInt padT)
                            , SA.width (String.fromFloat (max 4 xStep))
                            , SA.height (String.fromInt plotH)
                            , SA.fill "transparent"
                            , SE.onMouseOver (hoverMsg (Just i))
                            , SE.onMouseOut (hoverMsg Nothing)
                            ]
                            []
                    )

        hoverBits =
            case hover of
                Nothing ->
                    []

                Just idx ->
                    hoverTooltip series history padL padT plotW plotH xOf yOf idx
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromInt chartW ++ " " ++ String.fromInt chartH)
        , SA.width "100%"
        , A.style "display" "block"
        ]
        (grid ++ polylines ++ hits ++ hoverBits)


hoverTooltip : List Series -> List Point -> Int -> Int -> Int -> Int -> (Int -> Float) -> (Float -> Float) -> Int -> List (Svg.Svg Msg)
hoverTooltip series history padL padT plotW plotH xOf yOf idx =
    case List.drop idx history |> List.head of
        Nothing ->
            []

        Just pt ->
            let
                x =
                    xOf idx

                tooltipW =
                    240.0

                lineH =
                    16.0

                rows =
                    ( "Generation", ink, String.fromInt pt.gen )
                        :: List.filterMap
                            (\s ->
                                List.drop idx s.values
                                    |> List.head
                                    |> Maybe.map (\v -> ( s.label, s.color, fmtScore v ))
                            )
                            series
                        ++ [ ( "leftover crew us / them", mute, fmt1 pt.own ++ " / " ++ fmt1 pt.enemy ) ]

                tooltipH =
                    toFloat (List.length rows) * lineH + 14

                tooltipX =
                    if x + tooltipW + 14 > toFloat (padL + plotW) then
                        x - tooltipW - 14

                    else
                        x + 14

                tooltipY =
                    toFloat padT + 8

                yMain =
                    List.drop idx (List.concatMap .values (List.take 1 series))
                        |> List.head
                        |> Maybe.withDefault 0
            in
            [ Svg.line
                [ SA.x1 (String.fromFloat x)
                , SA.x2 (String.fromFloat x)
                , SA.y1 (String.fromInt padT)
                , SA.y2 (String.fromInt (padT + plotH))
                , SA.stroke gold
                , SA.strokeWidth "1"
                , SA.strokeOpacity "0.35"
                , SA.style "pointer-events:none"
                ]
                []
            , Svg.circle
                [ SA.cx (String.fromFloat x)
                , SA.cy (String.fromFloat (yOf yMain))
                , SA.r "4.5"
                , SA.fill gold
                , SA.stroke "#fff"
                , SA.strokeWidth "2"
                , SA.style "pointer-events:none"
                ]
                []
            , Svg.rect
                [ SA.x (String.fromFloat tooltipX)
                , SA.y (String.fromFloat tooltipY)
                , SA.width (String.fromFloat tooltipW)
                , SA.height (String.fromFloat tooltipH)
                , SA.rx "6"
                , SA.fill "#1e293b"
                , SA.fillOpacity "0.95"
                , SA.style "pointer-events:none"
                ]
                []
            ]
                ++ (rows
                        |> List.indexedMap
                            (\i ( lab, col, val ) ->
                                Svg.text_
                                    [ SA.x (String.fromFloat (tooltipX + 10))
                                    , SA.y (String.fromFloat (tooltipY + 16 + toFloat i * lineH))
                                    , SA.fill col
                                    , SA.fontSize "11"
                                    , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
                                    , SA.style "pointer-events:none"
                                    ]
                                    [ Svg.text (lab ++ "  " ++ val) ]
                            )
                   )


infoBtn : Explainer -> Html Msg
infoBtn e =
    span
        [ A.style "display" "inline-flex"
        , A.style "align-items" "center"
        , A.style "justify-content" "center"
        , A.style "width" "18px"
        , A.style "height" "18px"
        , A.style "border-radius" "50%"
        , A.style "border" ("1px solid " ++ gold)
        , A.style "color" gold
        , A.style "font-size" "12px"
        , A.style "font-weight" "700"
        , A.style "font-style" "italic"
        , A.style "cursor" "help"
        , A.style "flex-shrink" "0"
        , A.style "user-select" "none"
        , HE.onMouseEnter (ShowExplainer e)
        , HE.onMouseLeave HideExplainer
        , HE.stopPropagationOn "click" (D.succeed ( PinExplainer e, True ))
        ]
        [ text "i" ]


infoDot : Html Msg
infoDot =
    span
        [ A.style "display" "inline-flex"
        , A.style "align-items" "center"
        , A.style "justify-content" "center"
        , A.style "width" "14px"
        , A.style "height" "14px"
        , A.style "border-radius" "50%"
        , A.style "border" ("1px solid " ++ mute)
        , A.style "color" mute
        , A.style "font-size" "10px"
        , A.style "font-weight" "700"
        , A.style "font-style" "italic"
        , A.style "user-select" "none"
        ]
        [ text "i" ]


explainerModal : Model -> Html Msg
explainerModal model =
    case model.explainer of
        Nothing ->
            text ""

        Just e ->
            div []
                [ if model.pinned then
                    div
                        [ A.style "position" "fixed"
                        , A.style "inset" "0"
                        , A.style "background" "rgba(0,0,0,0.45)"
                        , A.style "z-index" "40"
                        , HE.onClick Unpin
                        ]
                        []

                  else
                    text ""
                , div
                    [ A.style "position" "fixed"
                    , A.style "right" "20px"
                    , A.style "bottom" "20px"
                    , A.style "width" "min(420px, calc(100vw - 32px))"
                    , A.style "max-height" "70vh"
                    , A.style "overflow" "auto"
                    , A.style "background" "#151c24"
                    , A.style "color" ink
                    , A.style "border" ("1px solid " ++ gold)
                    , A.style "border-radius" "12px"
                    , A.style "padding" "16px 18px 18px"
                    , A.style "z-index" "50"
                    , A.style "box-shadow" "0 12px 40px rgba(0,0,0,0.45)"
                    ]
                    [ div [ A.style "display" "flex", A.style "align-items" "flex-start", A.style "justify-content" "space-between", A.style "gap" "12px" ]
                        [ h3
                            [ A.style "margin" "0"
                            , A.style "font-size" "15px"
                            , A.style "color" gold
                            , A.style "line-height" "1.35"
                            ]
                            [ text e.title ]
                        , if model.pinned then
                            button
                                [ A.style "background" "transparent"
                                , A.style "border" ("1px solid " ++ line)
                                , A.style "color" ink
                                , A.style "border-radius" "6px"
                                , A.style "padding" "2px 8px"
                                , A.style "cursor" "pointer"
                                , A.style "font-size" "12px"
                                , HE.onClick Unpin
                                ]
                                [ text "Close" ]

                          else
                            span [ A.style "color" mute, A.style "font-size" "11px", A.style "white-space" "nowrap" ] [ text "click i to pin" ]
                        ]
                    , div [] (List.map explainerPara e.body)
                    ]
                ]


explainerPara : String -> Html Msg
explainerPara s =
    p
        [ A.style "color" ink
        , A.style "font-size" "13px"
        , A.style "line-height" "1.55"
        , A.style "margin" "10px 0 0"
        ]
        [ text s ]


pageExplainer : Explainer
pageExplainer =
    { title = "What this page is"
    , body =
        [ "We are training one neural net to play Super Melee against the original Awesome cyborg. The net picks a ship, the cyborg picks a ship, they fight in the real engine."
        , "Hull identity is 5 bits for us and 5 bits for them. A hidden layer of 16 tanh units sits between the sensors and the buttons. The current experiment uses Pkunk, Umgah and Yehat in both seats across several starting seeds."
        , "The ship pool stays fixed during this comparison so both experiments face the same challenge."
        , "Ignore leftover v5 numbers and any old 'WIN 509t' jackpot card. The number that matters is Hold record."
        ]
    }


generationExplainer : Status -> Explainer
generationExplainer s =
    { title = "Generation"
    , body =
        [ "How many times this experiment has updated the net, including work restored from a checkpoint. This run is at generation " ++ String.fromInt s.generation ++ "."
        , "It is a loop counter, not a win count. Generation 200 with 3 kills is worse than generation 50 with 15 kills."
        ]
    }


holdRecordExplainer : Int -> Int -> Status -> Explainer
holdRecordExplainer wins n _ =
    { title = "Hold record  (the number to watch)"
    , body =
        [ "The saved net is tested on a fixed validation set of " ++ String.fromInt n ++ " fights. Same ships, seats and set of seeds every time. Right now it has " ++ String.fromInt wins ++ " kills."
        , "A kill means: the fight actually finished, our ship won, and the enemy has 0 crew. Timeouts and dying both count as not a kill."
        , "These fights select the champion. A separate set of fresh seeds checks the selected policy after the experiment comparison."
        ]
    }


poolExplainer : String -> Status -> Explainer
poolExplainer ships s =
    { title = "Ship pool"
    , body =
        [ "Hulls the net must play as and against: " ++ ships ++ "."
        , "Every pair is tested, including mirror matches (Pkunk vs Pkunk) and both seats (our ship on the bottom or the top)."
        , String.fromInt s.nTrain ++ " practice fights and " ++ String.fromInt s.nHold ++ " validation fights per scoring. The pool stays fixed during the comparison."
        ]
    }


holdScoreExplainer : Status -> Explainer
holdScoreExplainer s =
    { title = "Hold score  (not a win count)"
    , body =
        [ "A blended number for the validation fights, currently " ++ fmtScore s.bestFitness ++ ". It mixes the average across all fights with the average of the worst quarter."
        , "A real kill is worth about a million minus how long it took. A timeout is a small damage number. A fight we lose outright is that small number minus 3000, so dying is still worse than timing out, but not by 100000. A new champion is kept only if it has more exam kills, or the same kills and a higher score."
        , "Use this to see whether the exam is getting less bad. Use Hold record for whether we are actually winning fights."
        ]
    }


meanExplainer : Status -> Explainer
meanExplainer s =
    { title = "This generation's practice average"
    , body =
        [ "Each generation we try a batch of mutated nets on the practice fights. This is their average score, currently " ++ fmtScore s.meanFitness ++ "."
        , "It wiggles a lot. A spike toward zero (less negative) means this batch fought less badly. It is not the exam, and it is not a kill count."
        , "If this number is moving over tens of generations, the search is alive. If Hold record is not moving, the search is not yet converting that into exam kills."
        ]
    }


crewMetricExplainer : Status -> Explainer
crewMetricExplainer s =
    { title = "Crew this generation"
    , body =
        [ "Average leftover crew on this generation's practice fights: us " ++ fmt1 s.own ++ ", them " ++ fmt1 s.enemy ++ "."
        , "Pkunk starts with 8, Umgah 10, Yehat 20. The practice mix includes all three, so this is not 'Pkunk 8 vs Umgah 10'."
        , "Them going down over time means we are dealing more damage. Us going down means we are dying more. Absolute 8 / 11 does not mean we are winning."
        ]
    }


evalExplainer : Status -> Explainer
evalExplainer s =
    { title = "Last eval"
    , body =
        [ "Wall time of the last batch of simulated fights: " ++ fmt2 s.evalS ++ " seconds. Each candidate net plays the full practice set on two CPU cores."
        , "Use full generation duration for throughput comparisons. Runtime changes with fight length and other work sharing the CPU."
        ]
    }


sigmaExplainer : Explainer
sigmaExplainer =
    { title = "Sigma"
    , body =
        [ "How hard we mutate the net each generation. Larger means bigger random jabs at the weights. Smaller means finer tweaks."
        , "Mutation size belongs to the frozen experiment configuration. Changes are tested in a new run rather than silently changing an existing experiment."
        ]
    }


holdTableExplainer : Status -> Explainer
holdTableExplainer s =
    { title = "Exam fight list"
    , body =
        [ "Every row is one exam fight for the saved champion from generation " ++ String.fromInt s.champion.generation ++ "."
        , "Our ship vs theirs: which hull we flew, which hull the frozen Awesome cyborg flew."
        , "Our seat: Super Melee has a bottom player and a top player. We test both, because a net that only wins from one side is not done."
        , "KILL means the fight finished, we won, enemy crew 0. TIMEOUT means we hit the 30 second cap with someone still alive. LOSS means the fight finished and we died."
        , "Crew left is ours then theirs. Duration counts combat time at 60 ticks per simulated second. Countdown and post-death resolution are excluded from this budget."
        ]
    }


fightExplainer : Fight -> Explainer
fightExplainer f =
    let
        seat =
            if f.swap then
                "top"

            else
                "bottom"

        won =
            fightWon f

        result =
            if won then
                "This is a KILL: the fight finished, our seat won, enemy crew hit 0."

            else if f.outcome == "invalidated" then
                "This is a TIMEOUT: we hit the 30 second cap. The engine did not crash. Nobody finished the other. It counts as not a win."

            else if f.outcome == "completed" then
                "This is a LOSS: the fight finished in the original game sense, and we were not the winner (winner reported as "
                    ++ f.winner
                    ++ ")."

            else
                "Outcome " ++ f.outcome ++ ", winner " ++ f.winner ++ ". Not a kill."
    in
    { title = f.us ++ " vs " ++ f.them ++ "  (" ++ seat ++ " seat)"
    , body =
        [ "We flew " ++ f.us ++ " on the " ++ seat ++ " seat. The opponent was frozen original Awesome cyborg flying " ++ f.them ++ ". Seed " ++ String.fromInt f.seed ++ "."
        , result
        , "Crew left: us " ++ String.fromInt f.own ++ ", them " ++ String.fromInt f.enemy ++ ". Duration " ++ secs f.ticks ++ " (" ++ String.fromInt f.ticks ++ " ticks at 60 per second)."
        ]
    }


scoreChartExplainer : Status -> Explainer
scoreChartExplainer s =
    { title = "Saved champion score"
    , body =
        [ "Left axis is the blended fight score, abbreviated with k for thousands. It is not kills and not crew."
        , "Mint is the saved champion's exam score. It is a step: it only jumps when we keep a new genome. Long flat mint means no new champion."
        , "Current exam score is " ++ fmtScore s.bestFitness ++ " at generation " ++ String.fromInt s.champion.generation ++ ". Current practice average is " ++ fmtScore s.meanFitness ++ "."
        , "A mint jump with Hold record unchanged usually means the same number of kills, but timeouts did more damage (or kills were faster). Watch Hold record for actual new kills."
        ]
    }


crewChartExplainer : Status -> Explainer
crewChartExplainer s =
    { title = "Why the crew chart looks weird"
    , body =
        [ "This is leftover crew on practice fights, averaged. It is not the exam, not a win/loss chart, and not 'health bars' for one ship."
        , "Every generation we fight as Pkunk, Umgah, and Yehat, against those same three. Starting crew is 8, 10, and 20. Average leftover of 8 / 11 is a mix of those, so it can sit near 8 even when Pkunk fights are going fine."
        , "Mint = our leftover crew. Higher mint means we are dying less. Coral = their leftover crew. Lower coral means we are dealing more damage."
        , "What you want over time: coral drifting down, mint holding or rising. Both bouncing in a band means the search is noisy, which it is."
        , "This generation: us " ++ fmt1 s.own ++ ", them " ++ fmt1 s.enemy ++ ". Compare the two lines across generations, not a single point against 8 and 10."
        ]
    }


netCard : Model -> Status -> Html Msg
netCard model s =
    div
        [ A.style "background" card
        , A.style "border" ("1px solid " ++ line)
        , A.style "border-radius" "12px"
        , A.style "padding" "16px 16px 10px"
        , A.style "margin-bottom" "22px"
        ]
        [ div [ A.style "display" "flex", A.style "align-items" "center", A.style "gap" "8px" ]
            [ h2 [ A.style "font-size" "15px", A.style "margin" "0", A.style "font-weight" "650" ]
                [ text
                    ("Champion net  ·  gen "
                        ++ (case model.net of
                                Just n ->
                                    String.fromInt n.generation

                                Nothing ->
                                    String.fromInt s.champion.generation
                           )
                    )
                ]
            , infoBtn netExplainer
            ]
        , p [ A.style "color" mute, A.style "font-size" "13px", A.style "margin" "8px 0 12px", A.style "line-height" "1.45" ]
            [ text "Two weight layers: inputs to 16 hidden tanh units to 13 outputs. Teal positive, coral negative. Hover a node." ]
        , case model.net of
            Nothing ->
                p [ A.style "color" mute ] [ text "Loading champion weights." ]

            Just n ->
                div [ A.style "height" "640px" ] [ viewBrain n s.pool ]
        ]


netExplainer : Explainer
netExplainer =
    { title = "Champion net"
    , body =
        [ "Three columns of neurons, two layers of weights. Left: what it sees. Middle: 16 tanh hidden units. Right: turn, thrust, fire, special, plus 8 extra memory units that feed back next tick."
        , "Hull identity is 5 bits for us and 5 bits for them (25 ships, so 4 bits is not enough). The hidden layer can mix those bits into ship-specific behaviour."
        , "Teal = positive weight, coral = negative. Thickness is |weight|. Node colour is wiring strength, not a live fight activation."
        ]
    }


brainW : Float
brainW =
    920


brainH : Float
brainH =
    640


viewBrain : NetPic -> List String -> Html Msg
viewBrain n pool =
    let
        inX =
            110

        hidX =
            brainW / 2

        outX =
            brainW - 70

        inYs =
            nodeYs n.nIn

        hidYs =
            nodeYs n.nHidden

        outYs =
            nodeYs n.nOut

        ins =
            inputNames

        outs =
            outputNames

        edges1 =
            List.concat
                (List.indexedMap
                    (\h toY ->
                        List.indexedMap
                            (\i fromY -> Svg.line (edgeAttrs inX fromY hidX toY (w1At n h i)) [])
                            inYs
                    )
                    hidYs
                )

        edges2 =
            List.concat
                (List.indexedMap
                    (\o toY ->
                        List.indexedMap
                            (\h fromY -> Svg.line (edgeAttrs hidX fromY outX toY (w2At n o h)) [])
                            hidYs
                    )
                    outYs
                )

        inNodes =
            List.map3 (\i y name -> inNode n pool i y name) (List.range 0 (n.nIn - 1)) inYs ins

        hidNodes =
            List.indexedMap (\h y -> hidNode n h y) hidYs

        outNodes =
            List.map3 (\o y name -> outNode n o y name) (List.range 0 (n.nOut - 1)) outYs outs

        groups =
            inputGroupLabels

        colLabs =
            [ colLabel inX "inputs"
            , colLabel hidX "hidden"
            , colLabel outX "outputs"
            ]
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat brainW ++ " " ++ String.fromFloat brainH)
        , SA.preserveAspectRatio "xMidYMid meet"
        , SA.width "100%"
        , SA.height "100%"
        , SA.style "display:block; background:#071019; border-radius:8px;"
        ]
        (edges1 ++ edges2 ++ groups ++ colLabs ++ inNodes ++ hidNodes ++ outNodes)


colLabel : Float -> String -> Svg.Svg Msg
colLabel x txt =
    Svg.text_
        [ SA.x (String.fromFloat x)
        , SA.y "16"
        , SA.fill "#5f8080"
        , SA.fontSize "11"
        , SA.textAnchor "middle"
        , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
        ]
        [ Svg.text txt ]


nodeYs : Int -> List Float
nodeYs n =
    let
        top =
            28

        bottom =
            brainH - 16

        gap =
            if n <= 1 then
                0

            else
                (bottom - top) / toFloat (n - 1)
    in
    List.map (\i -> top + gap * toFloat i) (List.range 0 (n - 1))


w1At : NetPic -> Int -> Int -> Float
w1At n h i =
    Array.get (h * n.nIn + i) n.weights |> Maybe.withDefault 0


w2At : NetPic -> Int -> Int -> Float
w2At n o h =
    Array.get (n.nHidden * n.nIn + o * (n.nHidden + 1) + h) n.weights |> Maybe.withDefault 0


inStrength : NetPic -> Int -> Float
inStrength n i =
    List.range 0 (n.nHidden - 1)
        |> List.map (\h -> abs (w1At n h i))
        |> List.maximum
        |> Maybe.withDefault 0


hidStrength : NetPic -> Int -> Float
hidStrength n h =
    let
        inn =
            List.range 0 (n.nIn - 1) |> List.map (\i -> abs (w1At n h i)) |> List.maximum |> Maybe.withDefault 0

        out =
            List.range 0 (n.nOut - 1) |> List.map (\o -> abs (w2At n o h)) |> List.maximum |> Maybe.withDefault 0
    in
    max inn out


outStrength : NetPic -> Int -> Float
outStrength n o =
    List.range 0 (n.nHidden - 1)
        |> List.map (\h -> abs (w2At n o h))
        |> List.maximum
        |> Maybe.withDefault 0


nodeColor : Float -> String
nodeColor v =
    let
        t =
            max -1 (min 1 v)

        mag =
            abs t

        light =
            round (26 + mag * 46)

        hue =
            if t >= 0 then
                35

            else
                200
    in
    "hsl(" ++ String.fromInt hue ++ ", 90%, " ++ String.fromInt light ++ "%)"


edgeAttrs : Float -> Float -> Float -> Float -> Float -> List (Svg.Attribute Msg)
edgeAttrs x1 y1 x2 y2 w =
    let
        a =
            max 0.04 (min 0.8 (abs w / 2.4))

        width =
            max 0.3 (min 2.8 (abs w * 0.85))

        color =
            if w >= 0 then
                "rgba(90,210,200," ++ String.fromFloat a ++ ")"

            else
                "rgba(255,110,90," ++ String.fromFloat a ++ ")"
    in
    [ SA.x1 (String.fromFloat x1)
    , SA.y1 (String.fromFloat y1)
    , SA.x2 (String.fromFloat x2)
    , SA.y2 (String.fromFloat y2)
    , SA.stroke color
    , SA.strokeWidth (String.fromFloat width)
    ]


inNode : NetPic -> List String -> Int -> Float -> String -> Svg.Svg Msg
inNode n pool i y name =
    let
        s =
            inStrength n i

        signed =
            let
                top =
                    List.range 0 (n.nHidden - 1)
                        |> List.map (\h -> w1At n h i)
                        |> List.sortBy (\w -> -(abs w))
                        |> List.head
                        |> Maybe.withDefault 0
            in
            if top < 0 then
                -s

            else
                s

        hot =
            String.startsWith "us " name || String.startsWith "them " name

        e =
            inputExplainer n i name
    in
    Svg.g
        [ SE.onMouseOver (ShowExplainer e)
        , SE.onMouseOut HideExplainer
        , SE.onClick (PinExplainer e)
        , SA.style "cursor:help"
        ]
        [ Svg.circle
            [ SA.cx "110"
            , SA.cy (String.fromFloat y)
            , SA.r
                (if hot then
                    "3.4"

                 else
                    "2.3"
                )
            , SA.fill (nodeColor signed)
            , SA.stroke
                (if hot then
                    gold

                 else
                    "#04121a"
                )
            , SA.strokeWidth "1"
            ]
            []
        , if shouldLabelInput i name pool then
            Svg.text_
                [ SA.x "100"
                , SA.y (String.fromFloat (y + 3))
                , SA.fill "#8fb2b2"
                , SA.fontSize "8"
                , SA.textAnchor "end"
                , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
                ]
                [ Svg.text name ]

          else
            Svg.text ""
        ]


outNode : NetPic -> Int -> Float -> String -> Svg.Svg Msg
outNode n o y name =
    let
        s =
            outStrength n o

        topW =
            List.range 0 (n.nHidden - 1)
                |> List.map (\h -> w2At n o h)
                |> List.sortBy (\w -> -(abs w))
                |> List.head
                |> Maybe.withDefault 0

        signed =
            if topW < 0 then
                -s

            else
                s

        e =
            outputExplainer n o name
    in
    Svg.g
        [ SE.onMouseOver (ShowExplainer e)
        , SE.onMouseOut HideExplainer
        , SE.onClick (PinExplainer e)
        , SA.style "cursor:help"
        ]
        [ Svg.circle
            [ SA.cx (String.fromFloat (brainW - 70))
            , SA.cy (String.fromFloat y)
            , SA.r "6"
            , SA.fill (nodeColor signed)
            , SA.stroke "#04121a"
            , SA.strokeWidth "1"
            ]
            []
        , Svg.text_
            [ SA.x (String.fromFloat (brainW - 58))
            , SA.y (String.fromFloat (y + 3.5))
            , SA.fill "#cfe8e6"
            , SA.fontSize "11"
            , SA.textAnchor "start"
            , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
            ]
            [ Svg.text name ]
        ]


hidNode : NetPic -> Int -> Float -> Svg.Svg Msg
hidNode n h y =
    let
        s =
            hidStrength n h

        topW =
            List.range 0 (n.nIn - 1)
                |> List.map (\i -> w1At n h i)
                |> List.sortBy (\w -> -(abs w))
                |> List.head
                |> Maybe.withDefault 0

        signed =
            if topW < 0 then
                -s

            else
                s

        e =
            hiddenExplainer n h
    in
    Svg.g
        [ SE.onMouseOver (ShowExplainer e)
        , SE.onMouseOut HideExplainer
        , SE.onClick (PinExplainer e)
        , SA.style "cursor:help"
        ]
        [ Svg.circle
            [ SA.cx (String.fromFloat (brainW / 2))
            , SA.cy (String.fromFloat y)
            , SA.r "5"
            , SA.fill (nodeColor signed)
            , SA.stroke "#04121a"
            , SA.strokeWidth "1"
            ]
            []
        ]


shouldLabelInput : Int -> String -> List String -> Bool
shouldLabelInput i name _ =
    (i < 33 && modBy 4 i == 0)
        || (i >= 33 && i <= 42)
        || (i >= 43 && i <= 47)
        || i
        == 56


inputGroupLabels : List (Svg.Svg Msg)
inputGroupLabels =
    [ groupTag 28 "combat"
    , groupTag (ysAt 33) "us bits"
    , groupTag (ysAt 38) "them bits"
    , groupTag (ysAt 43) "last tick"
    , groupTag (ysAt 56) "bias"
    ]


ysAt : Int -> Float
ysAt i =
    nodeYs 57 |> List.drop i |> List.head |> Maybe.withDefault 28


groupTag : Float -> String -> Svg.Svg Msg
groupTag y txt =
    Svg.text_
        [ SA.x "8"
        , SA.y (String.fromFloat (y + 3))
        , SA.fill "#5f8080"
        , SA.fontSize "10"
        , SA.textAnchor "start"
        , SA.fontFamily "ui-sans-serif, system-ui, sans-serif"
        ]
        [ Svg.text txt ]


inputNames : List String
inputNames =
    combatNames
        ++ List.map (\i -> "us b" ++ String.fromInt i) (List.range 0 4)
        ++ List.map (\i -> "them b" ++ String.fromInt i) (List.range 0 4)
        ++ [ "fb L", "fb R", "fb thrust", "fb fire", "fb special", "fb x0", "fb x1", "fb x2", "fb x3", "fb x4", "fb x5", "fb x6", "fb x7", "bias" ]


combatNames : List String
combatNames =
    [ "energy"
    , "crew"
    , "face C"
    , "face S"
    , "speed"
    , "travel C"
    , "travel S"
    , "weapon rdy"
    , "special rdy"
    , "turn rdy"
    , "thrust rdy"
    , "dx"
    , "dy"
    , "dist"
    , "closing"
    , "rel C"
    , "rel S"
    , "foe energy"
    , "foe crew"
    , "foe speed"
    , "cloaked"
    , "my hit"
    , "my soon"
    , "turn err"
    , "their hit"
    , "their soon"
    , "planet x"
    , "planet y"
    , "planet hit"
    , "incoming"
    , "in C"
    , "in S"
    , "one"
    ]


outputNames : List String
outputNames =
    [ "turn L"
    , "turn R"
    , "thrust"
    , "fire"
    , "special"
    , "extra 0"
    , "extra 1"
    , "extra 2"
    , "extra 3"
    , "extra 4"
    , "extra 5"
    , "extra 6"
    , "extra 7"
    ]


topWiresHid : NetPic -> Int -> List ( String, Float )
topWiresHid n i =
    List.range 0 (n.nHidden - 1)
        |> List.map (\h -> ( "h" ++ String.fromInt h, w1At n h i ))
        |> List.sortBy (\( _, w ) -> -(abs w))
        |> List.take 4


topWiresIn : NetPic -> Int -> List ( String, Float )
topWiresIn n o =
    List.range 0 (n.nHidden - 1)
        |> List.map (\h -> ( "h" ++ String.fromInt h, w2At n o h ))
        |> List.sortBy (\( _, w ) -> -(abs w))
        |> List.take 5


outputName : Int -> String
outputName o =
    List.drop o outputNames |> List.head |> Maybe.withDefault ("out " ++ String.fromInt o)


inputName : Int -> String
inputName i =
    List.drop i inputNames |> List.head |> Maybe.withDefault ("in " ++ String.fromInt i)


fmtW : Float -> String
fmtW w =
    let
        sign =
            if w >= 0 then
                "+"

            else
                ""
    in
    sign ++ fmt2 w


inputExplainer : NetPic -> Int -> String -> Explainer
inputExplainer n i name =
    { title = "Input  " ++ name
    , body =
        [ "Index " ++ String.fromInt i ++ " of " ++ String.fromInt n.nIn ++ ". Strongest wires into the hidden layer: "
            ++ (topWiresHid n i |> List.map (\( lab, w ) -> lab ++ " " ++ fmtW w) |> String.join ", ")
            ++ "."
        ]
    }


hiddenExplainer : NetPic -> Int -> Explainer
hiddenExplainer n h =
    { title = "Hidden  h" ++ String.fromInt h
    , body =
        [ "Tanh unit. Mixes the 5-bit hull ids with combat facts before they hit the controls."
        , "Strongest incoming: "
            ++ (List.range 0 (n.nIn - 1)
                    |> List.map (\i -> ( inputName i, w1At n h i ))
                    |> List.sortBy (\( _, w ) -> -(abs w))
                    |> List.take 4
                    |> List.map (\( lab, w ) -> lab ++ " " ++ fmtW w)
                    |> String.join ", "
               )
            ++ "."
        ]
    }


outputExplainer : NetPic -> Int -> String -> Explainer
outputExplainer n o name =
    { title = "Output  " ++ name
    , body =
        [ if o < 5 then
            "Control bit. Fires when this output is above 0."

          else
            "Extra memory unit. Tanh, then fed back as input next tick. Not a button."
        , "Strongest wires from hidden: "
            ++ (topWiresIn n o |> List.map (\( lab, w ) -> lab ++ " " ++ fmtW w) |> String.join ", ")
            ++ "."
        ]
    }


fmtScore : Float -> String
fmtScore x =
    if abs x >= 1000 then
        String.fromInt (round (x / 1000)) ++ "k"

    else
        fmt1 x


fmt1 : Float -> String
fmt1 x =
    String.fromFloat (toFloat (round (x * 10)) / 10)


fmt2 : Float -> String
fmt2 x =
    String.fromFloat (toFloat (round (x * 100)) / 100)


uptime : Float -> String
uptime s =
    let
        n =
            round s
    in
    if n < 60 then
        String.fromInt n ++ "s"

    else if n < 3600 then
        String.fromInt (n // 60) ++ "m " ++ String.fromInt (modBy 60 n) ++ "s"

    else
        String.fromInt (n // 3600) ++ "h " ++ String.fromInt (modBy 60 (n // 60)) ++ "m"
