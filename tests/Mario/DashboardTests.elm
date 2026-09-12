module Mario.DashboardTests exposing (suite)

{-| Tests for the MarI/O dashboard.

The properties worth proving here are the ones that keep the page
honest rather than merely pretty:

  - an unmeasured value decodes and stays as `Nothing`, never as zero,
  - a future engine that adds fields or new enum values still renders,
  - charts never join samples across a curriculum stage boundary or
    across a gap in measurement,
  - the "why is expansion blocked" answer is derived from per-cell
    evidence, not from an aggregate,
  - the node id layout the topology view labels matches the contract,
  - every tooltip actually states its denominator, window and source.

-}

import Dict
import Expect
import Fuzz
import Json.Decode as Decode
import Mario.Dashboard as Dashboard
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
import Test exposing (Test, describe, fuzz, fuzz2, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "MarI/O dashboard"
        [ decoderSuite
        , formatSuite
        , gateSuite
        , chartSuite
        , heatmapSuite
        , slotSuite
        , topologySuite
        , copySuite
        , controlSuite
        , broadSuite
        , scoringSuite
        ]



-- DECODERS


decode : String -> Result String Api.Status
decode json =
    Decode.decodeString Api.decodeStatus json
        |> Result.mapError Decode.errorToString


decoderSuite : Test
decoderSuite =
    describe "status decoder"
        [ test "an empty object still decodes, so a partially populated engine renders" <|
            \() ->
                case decode "{}" of
                    Ok status ->
                        Expect.equal ( status.champion.winRate, status.champion.lowerBound, status.matchups )
                            ( Nothing, Nothing, [] )

                    Err error ->
                        Expect.fail error
        , test "a null win rate decodes to Nothing, not to zero" <|
            \() ->
                case decode """{"champion":{"win_rate":null,"lower_bound":null,"validated_games":0}}""" of
                    Ok status ->
                        Expect.equal ( status.champion.winRate, status.champion.lowerBound ) ( Nothing, Nothing )

                    Err error ->
                        Expect.fail error
        , test "a genuine zero win rate is preserved and is distinct from absence" <|
            \() ->
                case decode """{"champion":{"win_rate":0.0,"validated_games":40}}""" of
                    Ok status ->
                        Expect.equal status.champion.winRate (Just 0)

                    Err error ->
                        Expect.fail error
        , test "unknown fields are ignored so a newer engine still renders" <|
            \() ->
                case decode """{"generation":7,"brand_new_field":{"nested":[1,2,3]},"population":{"size":300,"future":true}}""" of
                    Ok status ->
                        Expect.equal ( status.generation, status.population.size ) ( 7, 300 )

                    Err error ->
                        Expect.fail error
        , test "an unknown phase is preserved verbatim rather than collapsed into a known state" <|
            \() ->
                case decode """{"phase":"reseeding"}""" of
                    Ok status ->
                        Expect.equal status.phase (Api.UnknownPhase "reseeding")

                    Err error ->
                        Expect.fail error
        , test "an unknown matchup status is preserved verbatim" <|
            \() ->
                case decode """{"matchups":[{"us":"Pkunk","them":"Umgah","status":"quarantined"}]}""" of
                    Ok status ->
                        Expect.equal (List.map .status status.matchups) [ Api.UnknownStatus "quarantined" ]

                    Err error ->
                        Expect.fail error
        , test "a full contract payload decodes every documented field" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal
                            { run = status.runId
                            , phase = status.phase
                            , stage = status.curriculum.stage
                            , target = status.curriculum.target
                            , champion = status.champion.lowerBound
                            , history = List.length status.history
                            , matchups = List.length status.matchups
                            , events = List.length status.events
                            , duty = status.resources.dutyCycle
                            , resumable = status.checkpoint.resumable
                            }
                            { run = "run-2026-09-11-a"
                            , phase = Api.Auditing
                            , stage = 3
                            , target = 0.8
                            , champion = Just 0.71
                            , history = 3
                            , matchups = 4
                            , events = 2
                            , duty = 0.5
                            , resumable = True
                            }

                    Err error ->
                        Expect.fail error
        , test "history keeps unmeasured validation points as gaps" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal (List.map .validationWinRate status.history)
                            [ Nothing, Nothing, Just 0.82 ]

                    Err error ->
                        Expect.fail error
        , test "network genome decodes nodes and genes" <|
            \() ->
                Decode.decodeString Api.decodeNetwork networkPayload
                    |> Result.map (\n -> ( n.championId, List.length n.genome.nodes, List.length n.genome.genes ))
                    |> Expect.equal (Ok ( "champ-17", 3, 2 ))
        , test "the live engine's added fields decode: ladder, opponent revision, audit panel, readiness" <|
            \() ->
                case decode livePayload of
                    Ok status ->
                        Expect.equal
                            { ladder = status.curriculum.ladder
                            , revision = status.curriculum.opponentRevision
                            , fingerprint = status.curriculum.opponentFingerprint
                            , selfPlayGated = status.curriculum.selfPlayIsGated
                            , panel = status.audit.panel
                            , maxLosses = status.audit.maxLosses
                            , budget = status.audit.budget
                            , readinessGames = status.readiness.games
                            , readinessThreshold = status.readiness.threshold
                            , stale = status.stale
                            , hidden = status.champion.hiddenNodes
                            , trainingRate = List.map .trainingWinRate status.matchups
                            }
                            { ladder = Api.Climbing
                            , revision = 0
                            , fingerprint = Nothing
                            , selfPlayGated = False
                            , panel = 100
                            , maxLosses = 12
                            , budget = 200000
                            , readinessGames = 128
                            , readinessThreshold = 0.85
                            , stale = False
                            , hidden = 114
                            , trainingRate = [ Just 0.89 ]
                            }

                    Err error ->
                        Expect.fail error
        , test "the regression block decodes when present" <|
            \() ->
                case decode """{"regression":{"active":true,"budget":4000,"last_failed":2,"last_swept":41,"rehearsing":3,"sweeping":false}}""" of
                    Ok status ->
                        Expect.equal status.regression
                            (Just { active = True, sweeping = False, rehearsing = 3, lastSwept = 41, lastFailed = 2, budget = 4000 })

                    Err error ->
                        Expect.fail error
        , test "an engine that does not report regression leaves it absent, not zeroed" <|
            \() ->
                case decode livePayload of
                    Ok status ->
                        Expect.equal status.regression Nothing

                    Err error ->
                        Expect.fail error
        , test "an unknown ladder phase is preserved verbatim" <|
            \() ->
                case decode """{"curriculum":{"ladder":"spiralling"}}""" of
                    Ok status ->
                        Expect.equal status.curriculum.ladder (Api.UnknownLadder "spiralling")

                    Err error ->
                        Expect.fail error
        , test "a gene with no explicit enabled flag defaults to enabled" <|
            \() ->
                Decode.decodeString Api.decodeNetwork
                    """{"champion_id":"c","genome":{"nodes":[],"genes":[{"innovation":1,"from":0,"to":57,"weight":0.5}]}}"""
                    |> Result.map (\n -> List.map .enabled n.genome.genes)
                    |> Expect.equal (Ok [ True ])
        ]


fullPayload : String
fullPayload =
    """
{"schema_version":1,"run_id":"run-2026-09-11-a","phase":"auditing","message":"auditing candidate",
 "generation":42,"episodes":128400,"elapsed_seconds":7325.5,"episodes_per_second":3.4,
 "updated_at":"2026-09-11T10:15:00Z",
 "curriculum":{"stage":3,"our_roster":["Pkunk","Spathi"],"opponent_roster":["Umgah","Ilwrath"],
   "opponent_types":["cyborg"],"next_side":"opponent","next_ship":"Mycon","target":0.8,
   "mastered_matchups":2,"total_matchups":4},
 "champion":{"id":"champ-17","validated_wins":58,"validated_games":72,"win_rate":0.8055,
   "lower_bound":0.71,"nodes":74,"connections":91},
 "population":{"size":300,"species":11,"mean_nodes":72.4,"mean_connections":83.1},
 "checkpoint":{"saved_at":"2026-09-11T10:14:30Z","generation":42,"resumable":true,
   "path":"artifacts/mario/run-2026-09-11-a"},
 "resources":{"workers":1,"duty_cycle":0.5},
 "history":[
   {"generation":40,"stage":2,"training_win_rate":0.61,"validation_win_rate":null,"species":9,"nodes":72,"episodes":3000},
   {"generation":41,"stage":3,"training_win_rate":0.52,"validation_win_rate":null,"species":10,"nodes":73,"episodes":3100},
   {"generation":42,"stage":3,"training_win_rate":0.64,"validation_win_rate":0.82,"species":11,"nodes":74,"episodes":5200}],
 "matchups":[
   {"us":"Pkunk","them":"Umgah","opponent_type":"cyborg","wins":40,"games":44,"win_rate":0.909,"lower_bound":0.79,"status":"auditing","sample_weight":0.4},
   {"us":"Pkunk","them":"Ilwrath","opponent_type":"cyborg","wins":30,"games":40,"win_rate":0.75,"lower_bound":0.6,"status":"learning","sample_weight":0.35},
   {"us":"Spathi","them":"Umgah","opponent_type":"cyborg","wins":0,"games":0,"win_rate":null,"lower_bound":null,"status":"unseen","sample_weight":0.2},
   {"us":"Spathi","them":"Ilwrath","opponent_type":"cyborg","wins":38,"games":40,"win_rate":0.95,"lower_bound":0.84,"status":"mastered","sample_weight":0.05}],
 "events":[{"at":"2026-09-11T10:00:00Z","message":"stage 3 opened"},
           {"at":"2026-09-11T10:14:00Z","message":"audit started for champ-17"}]}
"""


{-| Trimmed from an actual /api/status response of the running trainer
(run dashboard-smoke-20260911), so the shape under test is the shape the
engine really sends, including the fields added after the first contract.
-}
livePayload : String
livePayload =
    """
{"schema_version":1,"run_id":"dashboard-smoke-20260911","phase":"training","message":"training",
 "generation":258,"episodes":12384,"elapsed_seconds":204.4,"episodes_per_second":60.6,
 "updated_at":"2026-09-11T19:41:04Z","stale":false,
 "curriculum":{"ladder":"climbing","mastered_matchups":0,"next_ship":"Androsynth","next_side":"ours",
   "opponent_fingerprint":null,"opponent_revision":0,"opponent_roster":["Umgah","Androsynth"],
   "opponent_types":["cyborg"],"our_roster":["Pkunk"],"self_play_is_gated":false,
   "stage":1,"target":0.8,"total_matchups":2},
 "champion":{"connections":314,"hidden_nodes":114,"id":"g4dd02251f9b298ea","lower_bound":null,
   "nodes":184,"validated_games":0,"validated_wins":0,"win_rate":null,"worst_cell_lower_bound":null},
 "population":{"mean_connections":293.58,"mean_nodes":170.16,"size":12,"species":2},
 "checkpoint":{"generation":258,"path":"artifacts/mario/dashboard-smoke-20260911/checkpoint.json",
   "resumable":true,"saved_at":"2026-09-11T19:41:03Z"},
 "resources":{"compute_seconds":72.58,"covers":["training","readiness","audit","self_play"],
   "duty_cycle":0.5,"episode_ticks":3600,"measured_duty":0.355,"nice":10,"workers":1},
 "audit":{"budget":200000,"max_losses":12,"panel":100,"round":null,"spent":0},
 "readiness":{"games":128,"last_rate":null,"period":5,"threshold":0.85},
 "history":[{"episodes":48,"generation":0,"nodes":71,"species":12,"stage":0,
   "training_win_rate":0.0,"validation_win_rate":null}],
 "matchups":[{"games":0,"lower_bound":null,"opponent_type":"cyborg","sample_weight":1.697,
   "status":"learning","them":"Umgah","training_games":10.0,"training_win_rate":0.89,
   "us":"Pkunk","win_rate":null,"wins":0}],
 "events":[{"at":"2026-09-11T19:37:40Z","message":"run seeded"}]}
"""


networkPayload : String
networkPayload =
    """
{"schema_version":1,"champion_id":"champ-17",
 "genome":{"schema_version":1,
   "nodes":[{"id":0,"kind":"input"},{"id":57,"kind":"output"},{"id":70,"kind":"hidden"}],
   "genes":[{"innovation":1,"from":0,"to":70,"weight":1.25,"enabled":true},
            {"innovation":2,"from":70,"to":57,"weight":-0.5,"enabled":false}]}}
"""



-- FORMAT


formatSuite : Test
formatSuite =
    describe "formatting"
        [ test "percentages round to one place" <|
            \() ->
                Expect.equal (List.map Format.percent1 [ 0, 0.8, 0.8055, 1 ])
                    [ "0.0%", "80.0%", "80.6%", "100.0%" ]
        , test "counts are grouped in threes" <|
            \() ->
                Expect.equal (List.map Format.count [ 0, 999, 1000, 128400, 1234567 ])
                    [ "0", "999", "1,000", "128,400", "1,234,567" ]
        , test "durations read as wall clock" <|
            \() ->
                Expect.equal (List.map Format.duration [ 0, 65, 3725, 90061 ])
                    [ "00:00", "01:05", "1:02:05", "1d 01:01:01" ]
        , test "a fraction always carries its denominator" <|
            \() ->
                Expect.equal (Format.fraction 58 72) "58 / 72"
        , test "a ratio over zero games reports absence rather than dividing" <|
            \() ->
                Expect.equal (Format.ratio 0 0) Format.awaiting
        , test "weights carry an explicit sign" <|
            \() ->
                Expect.equal (List.map Format.signedWeight [ 1.5, -0.25, 0 ])
                    [ "+1.500", "-0.250", "+0.000" ]
        , fuzz2 (Fuzz.intRange 0 4) (Fuzz.floatRange -10000 10000) "decimal never emits scientific notation or an empty fraction" <|
            \places value ->
                let
                    rendered =
                        Format.decimal places value
                in
                Expect.all
                    [ \s -> Expect.equal False (String.contains "e" s)
                    , \s -> Expect.equal False (String.endsWith "." s)
                    , \s ->
                        Expect.equal
                            (if places == 0 then
                                0

                             else
                                places
                            )
                            (case String.split "." s of
                                [ _, frac ] ->
                                    String.length frac

                                _ ->
                                    0
                            )
                    ]
                    rendered
        , fuzz (Fuzz.floatRange 0 1) "a rendered percentage parses back to within half a tenth of a point" <|
            \value ->
                case Format.percent1 value |> String.dropRight 1 |> String.toFloat of
                    Just parsed ->
                        Expect.lessThan 0.051 (abs (parsed - value * 100))

                    Nothing ->
                        Expect.fail ("could not parse " ++ Format.percent1 value)
        ]



-- GATE


matchup : String -> String -> Int -> Int -> Maybe Float -> Api.MatchupStatus -> Api.Matchup
matchup us them wins games bound status =
    { us = us
    , them = them
    , opponentType = Api.Cyborg
    , wins = wins
    , games = games
    , winRate =
        if games > 0 then
            Just (toFloat wins / toFloat games)

        else
            Nothing
    , lowerBound = bound
    , status = status
    , sampleWeight = 0.1
    , trainingGames = 0
    , trainingWinRate = Nothing
    }


sampleCells : List Api.Matchup
sampleCells =
    [ matchup "Pkunk" "Umgah" 40 44 (Just 0.79) Api.AuditingCell
    , matchup "Pkunk" "Ilwrath" 30 40 (Just 0.6) Api.Learning
    , matchup "Spathi" "Umgah" 0 0 Nothing Api.Unseen
    , matchup "Spathi" "Ilwrath" 38 40 (Just 0.84) Api.Mastered
    ]


curriculumFor : Api.NextSide -> Maybe String -> Api.Curriculum
curriculumFor side ship =
    { stage = 3
    , ourRoster = [ "Pkunk", "Spathi" ]
    , opponentRoster = [ "Umgah", "Ilwrath" ]
    , opponentTypes = [ Api.Cyborg ]
    , nextSide = side
    , nextShip = ship
    , target = 0.8
    , masteredMatchups = 1
    , totalMatchups = 4
    , ladder = Api.Climbing
    , opponentRevision = 0
    , opponentFingerprint = Nothing
    , selfPlayIsGated = False
    , evaluationScope = Api.PerCellScope
    , stageUnlockedExternally = False
    , transitionReason = Nothing
    , originRunId = Nothing
    , originGeneration = Nothing
    , originFingerprint = Nothing
    }


champion : Int -> Int -> Maybe Float -> Api.Champion
champion wins games bound =
    { id = "c"
    , validatedWins = wins
    , validatedGames = games
    , winRate =
        if games > 0 then
            Just (toFloat wins / toFloat games)

        else
            Nothing
    , lowerBound = bound
    , nodes = 70
    , connections = 0
    , hiddenNodes = 0
    , worstCellLowerBound = Nothing
    }


gateSuite : Test
gateSuite =
    describe "gate analysis"
        [ test "blockers are counted per cell, not pooled" <|
            \() ->
                Expect.equal (Gate.analyse 0.8 sampleCells)
                    { total = 4
                    , mastered = 1
                    , unseen = 1
                    , learning = 1
                    , auditing = 1
                    , short = 2
                    , missingReverse = 0
                    }
        , test "a cell with a bound just under the target still blocks" <|
            \() ->
                Gate.analyse 0.8 [ matchup "A" "B" 79 100 (Just 0.799) Api.AuditingCell ]
                    |> .short
                    |> Expect.equal 1
        , test "a cell with games but no published bound is not called short" <|
            \() ->
                Gate.analyse 0.8 [ matchup "A" "B" 90 100 Nothing Api.AuditingCell ]
                    |> .short
                    |> Expect.equal 0
        , test "a pair with no mirror is reported so one seat cannot pass for both" <|
            \() ->
                Gate.missingReverseSeats
                    [ matchup "Pkunk" "Umgah" 10 10 (Just 0.9) Api.Mastered
                    , matchup "Pkunk" "Pkunk" 10 10 (Just 0.9) Api.Mastered
                    , matchup "Umgah" "Umgah" 10 10 (Just 0.9) Api.Mastered
                    ]
                    |> Expect.equal [ ( "Umgah", "Pkunk" ) ]
        , test "a mirror outside the current stage's rosters is not invented as a blocker" <|
            \() ->
                Gate.missingReverseSeats sampleCells
                    |> Expect.equal []
        , test "a symmetric pair reports no missing seat" <|
            \() ->
                Gate.missingReverseSeats
                    [ matchup "Pkunk" "Umgah" 10 10 (Just 0.9) Api.Mastered
                    , matchup "Umgah" "Pkunk" 10 10 (Just 0.9) Api.Mastered
                    ]
                    |> Expect.equal []
        , test "a self pairing needs no mirror" <|
            \() ->
                Gate.missingReverseSeats [ matchup "Pkunk" "Pkunk" 5 10 (Just 0.2) Api.Learning ]
                    |> Expect.equal []
        , test "the weakest audited cell is listed first and mastered cells last" <|
            \() ->
                Gate.weakestFirst 0.8 sampleCells
                    |> List.map (\m -> ( m.us, m.them ))
                    |> Expect.equal
                        [ ( "Pkunk", "Ilwrath" )
                        , ( "Pkunk", "Umgah" )
                        , ( "Spathi", "Umgah" )
                        , ( "Spathi", "Ilwrath" )
                        ]
        , test "no audit games means no verdict rather than a failing score" <|
            \() ->
                Gate.championVerdict 0.8 (champion 0 0 Nothing)
                    |> Expect.equal Gate.NoEvidence
        , test "a high raw rate with no bound is undecided, never a pass" <|
            \() ->
                Gate.championVerdict 0.8 (champion 10 10 Nothing)
                    |> Expect.equal (Gate.RateOnly 1.0)
        , test "a rate above target with a bound below target is short, not passing" <|
            \() ->
                Gate.championVerdict 0.8 (champion 9 10 (Just 0.59))
                    |> Expect.equal (Gate.Short 0.59)
        , test "only a bound at or above target passes" <|
            \() ->
                Gate.championVerdict 0.8 (champion 190 200 (Just 0.8))
                    |> Expect.equal (Gate.Passing 0.8)
        , test "the gate demands 88 observed wins on a panel of 100, not 80" <|
            \() ->
                -- The target is a floor on the Wilson bound, not on the raw
                -- rate. 80 of 100 produces a bound near 71% and fails.
                Expect.equal
                    ( Gate.winsNeeded Gate.z95 0.8 100
                    , Gate.wilsonLower Gate.z95 80 100 |> Maybe.map (\b -> b >= 0.8)
                    , Gate.wilsonLower Gate.z95 88 100 |> Maybe.map (\b -> b >= 0.8)
                    )
                    ( Just 88, Just False, Just True )
        , test "the win count needed is the smallest one that clears the bound" <|
            \() ->
                Gate.wilsonLower Gate.z95 87 100
                    |> Maybe.map (\b -> b >= 0.8)
                    |> Expect.equal (Just False)
        , test "a larger panel needs a lower observed rate, since the bound tightens" <|
            \() ->
                let
                    rateFor n =
                        Gate.winsNeeded Gate.z95 0.8 n
                            |> Maybe.map (\w -> toFloat w / toFloat n)
                in
                case ( rateFor 100, rateFor 1000 ) of
                    ( Just small, Just large ) ->
                        Expect.lessThan small large

                    _ ->
                        Expect.fail "expected both panels to resolve"
        , test "the loss cap is survivable: 12 losses on a panel of 100 still leave exactly 88 winnable" <|
            \() ->
                -- The engine reports max_losses 12 for a panel of 100.
                -- 100 - 88 = 12, so the cap itself still permits a pass and
                -- it is the 13th loss that makes the target unreachable.
                case Gate.winsNeeded Gate.z95 0.8 100 of
                    Just wins ->
                        Expect.equal ( 100 - wins, 100 - (12 + 1) < wins ) ( 12, True )

                    Nothing ->
                        Expect.fail "expected a demand for a panel of 100"
        , test "an unpublished panel size yields no demand rather than a made-up one" <|
            \() ->
                Expect.equal ( Gate.winsNeeded Gate.z95 0.8 0, Gate.wilsonLower Gate.z95 0 0 ) ( Nothing, Nothing )
        , fuzz2 (Fuzz.intRange 1 200) (Fuzz.intRange 0 200) "the bound never exceeds the observed rate" <|
            \games rawWins ->
                let
                    wins =
                        min rawWins games
                in
                case Gate.wilsonLower Gate.z95 wins games of
                    Just bound ->
                        Expect.atMost (toFloat wins / toFloat games) bound

                    Nothing ->
                        Expect.fail "expected a bound for a non-empty panel"
        , test "the explanation leads with how many cells block, not with an average" <|
            \() ->
                case Gate.explain 0.8 (curriculumFor Api.AddOpponent (Just "Mycon")) sampleCells of
                    first :: _ ->
                        Expect.equal True (String.startsWith "3 of 4 active ordered matchups" first)

                    [] ->
                        Expect.fail "expected an explanation"
        , test "the explanation names the next addition" <|
            \() ->
                Gate.explain 0.8 (curriculumFor Api.AddOpponent (Just "Mycon")) sampleCells
                    |> String.join " "
                    |> String.contains "Mycon"
                    |> Expect.equal True
        , test "a cell with no audit games is never called never played" <|
            \() ->
                -- A cell can carry tens of thousands of training episodes
                -- and still have no audit evidence. Calling that "never
                -- played" misdescribes the run.
                let
                    prose =
                        Gate.explain 0.8 (curriculumFor Api.AddOpponent (Just "Mycon")) sampleCells
                            |> String.join " "
                in
                Expect.equal
                    ( String.contains "never played" prose, String.contains "no audit games" prose )
                    ( False, True )
        , test "a fully mastered stage says so and stops blaming cells" <|
            \() ->
                let
                    all =
                        [ matchup "A" "B" 40 40 (Just 0.91) Api.Mastered
                        , matchup "B" "A" 40 40 (Just 0.91) Api.Mastered
                        ]
                in
                case Gate.explain 0.8 (curriculumFor Api.AddOurs (Just "Orz")) all of
                    first :: _ ->
                        Expect.equal True (String.contains "have cleared" first)

                    [] ->
                        Expect.fail "expected an explanation"
        , test "an empty stage says there is nothing to gate on rather than claiming success" <|
            \() ->
                case Gate.explain 0.8 (curriculumFor Api.AddOpponent Nothing) [] of
                    first :: _ ->
                        Expect.equal True (String.contains "No ordered matchups" first)

                    [] ->
                        Expect.fail "expected an explanation"
        ]



-- CHART


chartSuite : Test
chartSuite =
    describe "chart geometry"
        [ test "a gap in measurement breaks the line instead of being drawn as zero" <|
            \() ->
                Chart.runs [ 0, 0, 0, 0 ] [ Just 0.5, Nothing, Just 0.7, Just 0.9 ]
                    |> Expect.equal [ [ ( 0, 0.5 ) ], [ ( 2, 0.7 ), ( 3, 0.9 ) ] ]
        , test "a stage change breaks the line so incomparable spans are never joined" <|
            \() ->
                Chart.runs [ 1, 1, 2, 2 ] [ Just 0.5, Just 0.6, Just 0.7, Just 0.8 ]
                    |> Expect.equal [ [ ( 0, 0.5 ), ( 1, 0.6 ) ], [ ( 2, 0.7 ), ( 3, 0.8 ) ] ]
        , test "a single fully measured stage is one unbroken run" <|
            \() ->
                Chart.runs [ 4, 4, 4 ] [ Just 1, Just 2, Just 3 ]
                    |> Expect.equal [ [ ( 0, 1 ), ( 1, 2 ), ( 2, 3 ) ] ]
        , test "no measurements produce no runs at all" <|
            \() ->
                Chart.runs [ 0, 0 ] [ Nothing, Nothing ]
                    |> Expect.equal []
        , fuzz (Fuzz.listOfLengthBetween 0 20 (Fuzz.maybe (Fuzz.floatRange 0 1)))
            "every measured sample appears exactly once across the runs"
          <|
            \values ->
                let
                    segments =
                        List.indexedMap (\i _ -> i // 3) values

                    measured =
                        values |> List.filterMap identity |> List.length

                    emitted =
                        Chart.runs segments values |> List.concat |> List.length
                in
                Expect.equal measured emitted
        , fuzz (Fuzz.listOfLengthBetween 1 20 (Fuzz.intRange 0 3))
            "no run ever spans two different segments"
          <|
            \segments ->
                let
                    values =
                        List.map (\_ -> Just 1) segments

                    segmentOf i =
                        segments |> List.drop i |> List.head |> Maybe.withDefault -1

                    spans run =
                        run |> List.map (\( i, _ ) -> segmentOf i) |> List.foldl (\s acc -> s :: acc) [] |> unique
                in
                Chart.runs segments values
                    |> List.map (spans >> List.length)
                    |> List.all (\n -> n == 1)
                    |> Expect.equal True
        ]


unique : List a -> List a
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



-- HEATMAP


heatmapSuite : Test
heatmapSuite =
    describe "matchup grid"
        [ test "rows and columns follow the frozen roster order" <|
            \() ->
                let
                    g =
                        Heatmap.grid [ "Pkunk", "Spathi" ] [ "Umgah", "Ilwrath" ] sampleCells
                in
                Expect.equal ( g.rows, g.cols ) ( [ "Pkunk", "Spathi" ], [ "Umgah", "Ilwrath" ] )
        , test "a reported pair outside the roster is appended rather than dropped" <|
            \() ->
                let
                    g =
                        Heatmap.grid [ "Pkunk" ] [ "Umgah" ] (matchup "Orz" "Mycon" 1 2 Nothing Api.Learning :: sampleCells)
                in
                Expect.equal ( List.member "Orz" g.rows, List.member "Mycon" g.cols ) ( True, True )
        , test "an unmeasured cell gets its own fill, distinct from any measured value" <|
            \() ->
                Expect.notEqual (Heatmap.cellFill 0.8 Nothing) (Heatmap.cellFill 0.8 (Just 0))
        , test "crossing the target changes the colour family" <|
            \() ->
                Expect.notEqual (Heatmap.cellFill 0.8 (Just 0.799)) (Heatmap.cellFill 0.8 (Just 0.8))
        , test "names shorten only as the grid grows" <|
            \() ->
                Expect.equal
                    ( Heatmap.shortName 4 "Androsynth", Heatmap.shortName 25 "Androsynth" )
                    ( "Androsynth", "And" )
        ]



-- SLOTS


slotSuite : Test
slotSuite =
    describe "node id layout"
        [ test "the contract's fixed sizes hold" <|
            \() ->
                Expect.equal
                    { sensors = Slots.sensorCount
                    , observations = Slots.observationCount
                    , bias = Slots.biasIndex
                    , inputs = Slots.inputCount
                    , outputFirst = Slots.outputFirst
                    , outputs = Slots.outputCount
                    , hiddenFirst = Slots.hiddenFirst
                    }
                    { sensors = 33
                    , observations = 43
                    , bias = 56
                    , inputs = 57
                    , outputFirst = 57
                    , outputs = 13
                    , hiddenFirst = 70
                    }
        , test "group boundaries land where the contract says" <|
            \() ->
                Expect.equal (List.map Slots.groupOf [ 0, 32, 33, 37, 38, 42, 43, 47, 48, 55, 56, 57, 61, 62, 69, 70 ])
                    [ Slots.Sensors
                    , Slots.Sensors
                    , Slots.OurShipBits
                    , Slots.OurShipBits
                    , Slots.TheirShipBits
                    , Slots.TheirShipBits
                    , Slots.PriorControls
                    , Slots.PriorControls
                    , Slots.PriorMemory
                    , Slots.PriorMemory
                    , Slots.Bias
                    , Slots.ControlOutputs
                    , Slots.ControlOutputs
                    , Slots.MemoryOutputs
                    , Slots.MemoryOutputs
                    , Slots.Hidden
                    ]
        , test "ship identity bits are labelled least significant first" <|
            \() ->
                Expect.equal
                    (List.map (\i -> (Slots.slot i).short) [ 33, 34, 35, 36, 37, 38, 42 ])
                    [ "us b0", "us b1", "us b2", "us b3", "us b4", "them b0", "them b4" ]
        , test "control outputs keep the encoder's order" <|
            \() ->
                Expect.equal (List.map (\i -> (Slots.slot i).short) (List.range 57 61))
                    Slots.controlNames
        , test "memory outputs name the input they feed on the next step" <|
            \() ->
                Expect.equal True (String.contains "input 48" (Slots.slot 62).detail)
        , test "the sensor constant and the extra bias are described as different things" <|
            \() ->
                Expect.equal True (String.contains "Distinct from the extra bias" (Slots.slot 32).detail)
        , fuzz (Fuzz.intRange 0 400) "every node id resolves to a named slot" <|
            \id ->
                Expect.equal False (String.isEmpty (Slots.slot id).short)
        ]



-- TOPOLOGY


genome : List ( Int, String ) -> List Api.Gene -> Api.Genome
genome nodes genes =
    { schemaVersion = 1
    , nodes = List.map (\( id, kind ) -> { id = id, kind = Api.nodeKindFromString kind }) nodes
    , genes = genes
    }


link : Int -> Int -> Int -> Float -> Api.Gene
link innovation from to weight =
    { innovation = innovation, from = from, to = to, weight = weight, enabled = True }


disabledLink : Int -> Int -> Int -> Float -> Api.Gene
disabledLink innovation from to weight =
    { innovation = innovation, from = from, to = to, weight = weight, enabled = False }


topologySuite : Test
topologySuite =
    describe "topology"
        [ test "a cycle does not stop the depth computation" <|
            \() ->
                let
                    cyclic =
                        genome
                            [ ( 0, "input" ), ( 70, "hidden" ), ( 71, "hidden" ), ( 57, "output" ) ]
                            [ link 1 0 70 1
                            , link 2 70 71 1
                            , link 3 71 70 1
                            , link 4 71 57 1
                            ]
                in
                Topology.hiddenDepths cyclic
                    |> (\depths -> ( Dict.get 70 depths, Dict.get 71 depths ))
                    |> Expect.equal ( Just 1, Just 2 )
        , test "a node referenced only by a gene is still placed, not silently dropped" <|
            \() ->
                let
                    partial =
                        genome [ ( 0, "input" ) ] [ link 1 0 99 1 ]
                in
                Topology.orderedIds partial
                    |> List.member 99
                    |> Expect.equal True
        , test "an undeclared node is counted so an invalid genome cannot look clean" <|
            \() ->
                Topology.summarize (genome [ ( 0, "input" ) ] [ link 1 0 99 1 ])
                    |> .undeclared
                    |> Expect.equal 1
        , test "disabled genes are counted separately from enabled ones" <|
            \() ->
                Topology.summarize
                    (genome
                        [ ( 0, "input" ), ( 57, "output" ) ]
                        [ link 1 0 57 1, disabledLink 2 0 57 -1 ]
                    )
                    |> (\s -> ( s.enabled, s.disabled ))
                    |> Expect.equal ( 1, 1 )
        , test "a link from an output back to a hidden node is counted as recurrent" <|
            \() ->
                Topology.summarize
                    (genome
                        [ ( 0, "input" ), ( 70, "hidden" ), ( 57, "output" ) ]
                        [ link 1 0 70 1, link 2 70 57 1, link 3 57 70 1 ]
                    )
                    |> .recurrent
                    |> Expect.equal 1
        , test "every fixed input and output gets a position even in an empty genome" <|
            \() ->
                Topology.layout { schemaVersion = 1, nodes = [], genes = [] }
                    |> .placed
                    |> List.length
                    |> Expect.equal (Slots.inputCount + Slots.outputCount)
        , test "the two ship identity groups get different colours" <|
            \() ->
                Expect.notEqual
                    (Topology.groupColor Slots.OurShipBits)
                    (Topology.groupColor Slots.TheirShipBits)
        , test "memory keeps one colour at both ends of the graph, so the loop is visible" <|
            \() ->
                Expect.equal
                    (Topology.groupColor Slots.PriorMemory)
                    (Topology.groupColor Slots.MemoryOutputs)
        ]



-- TOOLTIP COPY


copySuite : Test
copySuite =
    describe "tooltip copy"
        [ test "every metric explains itself" <|
            \() ->
                (Copy.allTips Nothing)
                    |> List.filter (\t -> String.length t.body < 40 || String.isEmpty t.title)
                    |> List.map .id
                    |> Expect.equal []
        , test "every tip states its denominator, its window and its source" <|
            \() ->
                (Copy.allTips Nothing)
                    |> List.filter
                        (\t ->
                            let
                                keys =
                                    List.map Tuple.first t.meta
                            in
                            not (List.member "Denominator" keys && List.member "Window" keys && List.member "Source" keys)
                        )
                    |> List.map .id
                    |> Expect.equal []
        , test "tip ids are unique, so no two bubbles share an element id" <|
            \() ->
                let
                    ids =
                        List.map .id (Copy.allTips Nothing)
                in
                Expect.equal (List.length ids) (List.length (unique ids))
        , test "no two anchors on the page reuse the same tip, which would duplicate a DOM id" <|
            \() ->
                -- Tip ids become element ids and drive the open/closed state,
                -- so the same tip must not be attached to two anchors. Each
                -- panel heading and each metric therefore gets its own.
                let
                    onPage =
                        [ Copy.vitals
                        , Copy.generation
                        , Copy.machine
                        , Copy.populationSize
                        , Copy.unevaluated
                        , Copy.expansionBlocked
                        , Copy.structureChart
                        , Copy.nodesChart
                        , Copy.species
                        ]
                            |> List.map .id
                in
                Expect.equal (List.length onPage) (List.length (unique onPage))
        , test "the audit and training tips each say which kind of evidence they describe" <|
            \() ->
                Expect.equal
                    ( String.contains "audit" (String.toLower (Copy.championRate Nothing).body)
                    , String.contains "training" (String.toLower Copy.sampleAllocation.body)
                    )
                    ( True, True )
        ]



-- CONTROLS


controlSuite : Test
controlSuite =
    describe "run controls"
        [ test "action keys match the control endpoint contract" <|
            \() ->
                Expect.equal (List.map Dashboard.actionKey [ Dashboard.Pause, Dashboard.Resume, Dashboard.Stop ])
                    [ "pause", "resume", "stop" ]
        , test "a pause stays pending until the trainer itself reports paused" <|
            \() ->
                let
                    stillTraining =
                        statusWithPhase Api.Training
                in
                Dashboard.clearSettledControl stillTraining (Dashboard.ControlAccepted Dashboard.Pause)
                    |> Expect.equal (Dashboard.ControlAccepted Dashboard.Pause)
        , test "a pause clears once the trainer reports paused" <|
            \() ->
                Dashboard.clearSettledControl (statusWithPhase Api.Paused) (Dashboard.ControlAccepted Dashboard.Pause)
                    |> Expect.equal Dashboard.ControlIdle
        , test "a resume clears only when the trainer is live again" <|
            \() ->
                Expect.equal
                    ( Dashboard.clearSettledControl (statusWithPhase Api.Paused) (Dashboard.ControlAccepted Dashboard.Resume)
                    , Dashboard.clearSettledControl (statusWithPhase Api.Auditing) (Dashboard.ControlAccepted Dashboard.Resume)
                    )
                    ( Dashboard.ControlAccepted Dashboard.Resume, Dashboard.ControlIdle )
        , test "a failed control is never cleared by a status poll" <|
            \() ->
                Dashboard.clearSettledControl (statusWithPhase Api.Paused) (Dashboard.ControlFailed Dashboard.Pause "boom")
                    |> Expect.equal (Dashboard.ControlFailed Dashboard.Pause "boom")
        ]


statusWithPhase : Api.Phase -> Api.Status
statusWithPhase phase =
    let
        base =
            Api.empty
    in
    { base | phase = phase }


-- BROAD MODE
--
-- The broad run is gated on one aggregate figure over a balanced held-out
-- distribution. Everything here guards a way that could be mis-stated:
-- an aggregate presented as a per-cell guarantee, a readiness probe
-- presented as audit evidence, an unmeasured hull presented as a loss, or
-- a staged run quietly picking up broad wording it should never show.


broadSuite : Test
broadSuite =
    describe "broad any-versus-any mode"
        [ broadDecoderSuite
        , broadProvenanceSuite
        , broadVerdictSuite
        , broadBlindSpotSuite
        , broadCopySuite
        , stagedUntouchedSuite
        , cumulativeEpisodeSuite
        , scopeChangeSuite
        , readinessBaselineSuite
        ]


broadDecoderSuite : Test
broadDecoderSuite =
    describe "decoding"
        [ test "a staged run decodes with no broad fields at all" <|
            \() ->
                case decode livePayload of
                    Ok status ->
                        Expect.equal
                            { overall = status.overall
                            , ships = status.shipPerformance
                            , sampler = status.sampler
                            , broad = Api.isBroad status.curriculum
                            }
                            { overall = Nothing
                            , ships = []
                            , sampler = Nothing
                            , broad = False
                            }

                    Err error ->
                        Expect.fail error
        , test "explicit nulls for the broad blocks decode as absent, not as empty results" <|
            \() ->
                case decode """{"overall":null,"ship_performance":[],"sampler":null}""" of
                    Ok status ->
                        Expect.equal ( status.overall, status.shipPerformance, status.sampler )
                            ( Nothing, [], Nothing )

                    Err error ->
                        Expect.fail error
        , test "the broad ladder and evaluation scope both decode" <|
            \() ->
                case decode broadPayload of
                    Ok status ->
                        Expect.equal
                            { ladder = status.curriculum.ladder
                            , scope = status.curriculum.evaluationScope
                            , broad = Api.isBroad status.curriculum
                            , unlocked = status.curriculum.stageUnlockedExternally
                            }
                            { ladder = Api.Broad
                            , scope = Api.OverallBalancedScope
                            , broad = True
                            , unlocked = True
                            }

                    Err error ->
                        Expect.fail error
        , test "transition provenance decodes and is not invented when absent" <|
            \() ->
                case ( decode broadPayload, decode "{}" ) of
                    ( Ok broad, Ok bare ) ->
                        Expect.equal
                            ( ( broad.curriculum.originRunId
                              , broad.curriculum.originGeneration
                              , broad.curriculum.transitionReason
                              )
                            , ( bare.curriculum.originRunId
                              , bare.curriculum.originGeneration
                              , bare.curriculum.transitionReason
                              )
                            )
                            ( ( Just "mario-main-20260911"
                              , Just 79
                              , Just "operator requested any-versus-any"
                              )
                            , ( Nothing, Nothing, Nothing )
                            )

                    _ ->
                        Expect.fail "both payloads should decode"
        , test "the overall block keeps its two rounds apart rather than summing them" <|
            \() ->
                case decode broadPayload of
                    Ok status ->
                        case status.overall of
                            Just overall ->
                                Expect.equal
                                    { round = overall.round
                                    , wins = overall.wins
                                    , games = overall.games
                                    , panel = overall.panel
                                    , pairs = overall.pairs
                                    , audit = ( overall.audit.wins, overall.audit.games, overall.audit.passed )
                                    , confirm = ( overall.confirm.wins, overall.confirm.games, overall.confirm.passed )
                                    , passed = overall.passed
                                    }
                                    { round = Just Api.AuditRound
                                    , wins = 861
                                    , games = 1000
                                    , panel = 1000
                                    , pairs = 500
                                    , audit = ( 861, 1000, True )
                                    , confirm = ( 0, 0, False )
                                    , passed = False
                                    }

                            Nothing ->
                                Expect.fail "broad payload should carry an overall block"

                    Err error ->
                        Expect.fail error
        , test "a hull with no games keeps a null rate and bound rather than becoming zero" <|
            \() ->
                case decode broadPayload of
                    Ok status ->
                        status.shipPerformance
                            |> List.filter (\row -> row.games == 0)
                            |> List.map (\row -> ( row.winRate, row.lowerBound ))
                            |> Expect.equal [ ( Nothing, Nothing ) ]

                    Err error ->
                        Expect.fail error
        , test "a genuine zero win rate on a played hull survives as a measurement" <|
            \() ->
                case decode """{"ship_performance":[{"side":"ours","ship":"Umgah","wins":0,"games":40,"win_rate":0.0,"lower_bound":0.0,"source":"audit"}]}""" of
                    Ok status ->
                        List.map (\row -> ( row.winRate, row.lowerBound )) status.shipPerformance
                            |> Expect.equal [ ( Just 0, Just 0 ) ]

                    Err error ->
                        Expect.fail error
        , test "every evidence source decodes and an unknown one is preserved verbatim" <|
            \() ->
                case decode """{"ship_performance":[{"source":"audit"},{"source":"confirm"},{"source":"ready"},{"source":"rehearsal"}]}""" of
                    Ok status ->
                        List.map .source status.shipPerformance
                            |> Expect.equal
                                [ Api.FromAudit
                                , Api.FromConfirm
                                , Api.FromReadiness
                                , Api.UnknownSource "rehearsal"
                                ]

                    Err error ->
                        Expect.fail error
        , test "only the gate rounds count as gate evidence" <|
            \() ->
                List.map Api.evidenceIsGate
                    [ Api.FromAudit, Api.FromConfirm, Api.FromReadiness, Api.UnknownSource "rehearsal" ]
                    |> Expect.equal [ True, True, False, False ]
        , test "sampler figures decode, and an unreported one stays unknown rather than zero" <|
            \() ->
                case ( decode broadPayload, decode """{"sampler":{"panel":32}}""" ) of
                    ( Ok full, Ok partial ) ->
                        Expect.equal
                            ( full.sampler, partial.sampler )
                            ( Just { panel = Just 32, balancedShare = Just 0.5, cursor = Just 1184, tour = Just 1 }
                            , Just { panel = Just 32, balancedShare = Nothing, cursor = Nothing, tour = Nothing }
                            )

                    _ ->
                        Expect.fail "both payloads should decode"
        , test "an unknown ladder or scope is preserved rather than collapsed into broad" <|
            \() ->
                case decode """{"curriculum":{"ladder":"spiral","evaluation_scope":"per-hull"}}""" of
                    Ok status ->
                        Expect.equal
                            ( status.curriculum.ladder
                            , status.curriculum.evaluationScope
                            , Api.isBroad status.curriculum
                            )
                            ( Api.UnknownLadder "spiral"
                            , Api.UnknownScope "per-hull"
                            , False
                            )

                    Err error ->
                        Expect.fail error
        , test "the readiness purpose decodes so a broad probe can name itself" <|
            \() ->
                case decode broadPayload of
                    Ok status ->
                        Expect.equal status.readiness.purpose (Just "broad balanced readiness")

                    Err error ->
                        Expect.fail error
        ]


broadProvenanceSuite : Test
broadProvenanceSuite =
    describe "provenance survives a later mixed phase"
        [ test "a mixed run carrying overall-balanced scope is still judged overall" <|
            \() ->
                case decode broadOriginMixedPayload of
                    Ok status ->
                        Expect.equal
                            { ladder = status.curriculum.ladder
                            , broad = Api.isBroad status.curriculum
                            , origin = status.curriculum.originRunId
                            , gated = status.curriculum.selfPlayIsGated
                            }
                            { ladder = Api.Mixed
                            , broad = True
                            , origin = Just "mario-main-20260911"
                            , gated = False
                            }

                    Err error ->
                        Expect.fail error
        , test "a mixed run that came from broad says so rather than claiming per-cell gating" <|
            \() ->
                case decode broadOriginMixedPayload of
                    Ok status ->
                        Gate.explainBroad Nothing status.curriculum status.overall status.shipPerformance
                            |> List.any (String.contains "did not revert to per-matchup gating")
                            |> Expect.equal True

                    Err error ->
                        Expect.fail error
        , test "an old mixed run with no broad signals is untouched by broad rendering" <|
            \() ->
                case decode """{"curriculum":{"ladder":"mixed","evaluation_scope":"per-cell-ladder"}}""" of
                    Ok status ->
                        Expect.equal ( status.curriculum.ladder, Api.isBroad status.curriculum )
                            ( Api.Mixed, False )

                    Err error ->
                        Expect.fail error
        ]


broadVerdictSuite : Test
broadVerdictSuite =
    describe "the overall verdict"
        [ test "no games is no evidence, and never a zero" <|
            \() ->
                Gate.overallVerdict (overallWith 0 0 Nothing Nothing)
                    |> Expect.equal Gate.NoEvidence
        , test "a bound over the target passes" <|
            \() ->
                Gate.overallVerdict (overallWith 861 1000 (Just 0.861) (Just 0.838))
                    |> Expect.equal (Gate.Passing 0.838)
        , test "a raw rate over the target with a bound under it is short, not a pass" <|
            \() ->
                Gate.overallVerdict (overallWith 820 1000 (Just 0.82) (Just 0.795))
                    |> Expect.equal (Gate.Short 0.795)
        , test "a raw rate with no published bound leaves the gate undecided" <|
            \() ->
                Gate.overallVerdict (overallWith 900 1000 (Just 0.9) Nothing)
                    |> Expect.equal (Gate.RateOnly 0.9)
        , test "clearing 80% on a 1000 game panel takes more than 800 observed wins" <|
            \() ->
                Gate.winsNeeded Gate.z95 0.8 1000
                    |> Maybe.map (\wins -> wins > 800)
                    |> Expect.equal (Just True)
        ]


broadBlindSpotSuite : Test
broadBlindSpotSuite =
    describe "blind spots"
        [ test "an unmeasured hull sorts last, because silence is not weakness" <|
            \() ->
                Gate.blindSpots
                    [ shipRow Api.OurSeat "Unmeasured" 0 0 Nothing Nothing
                    , shipRow Api.OurSeat "Weak" 4 40 (Just 0.1) (Just 0.04)
                    , shipRow Api.OurSeat "Strong" 38 40 (Just 0.95) (Just 0.84)
                    ]
                    |> List.map .ship
                    |> Expect.equal [ "Weak", "Strong", "Unmeasured" ]
        , test "seat coverage counts hulls with games in each grouping" <|
            \() ->
                Gate.seatCoverage
                    [ shipRow Api.OurSeat "A" 1 10 (Just 0.1) Nothing
                    , shipRow Api.OurSeat "B" 0 0 Nothing Nothing
                    , shipRow Api.OpponentSeat "A" 5 10 (Just 0.5) Nothing
                    ]
                    |> Expect.equal
                        { ours = 2, oursWithGames = 1, opponent = 1, opponentWithGames = 1 }
        ]


broadCopySuite : Test
broadCopySuite =
    describe "what the broad explanation is obliged to say"
        [ test "it states the aggregate is not a per-matchup claim" <|
            \() ->
                broadLines
                    |> List.any (String.contains "not a claim that the champion clears")
                    |> Expect.equal True
        , test "it names the confirm round, so an audit pass is never read as the gate" <|
            \() ->
                broadLines
                    |> List.any (String.contains "confirm")
                    |> Expect.equal True
        , test "it says timeouts count as non-wins" <|
            \() ->
                broadLines
                    |> List.any (String.contains "time out")
                    |> Expect.equal True
        , test "it declines to claim a formal guarantee for correlated paired seats" <|
            \() ->
                broadLines
                    |> List.any (String.contains "not as a formal guarantee")
                    |> Expect.equal True
        , test "it says both groupings count our champion's own wins" <|
            \() ->
                broadLines
                    |> List.any (String.contains "count our champion's own wins")
                    |> Expect.equal True
        , test "an externally unlocked stage is named as unlocked, not as mastered" <|
            \() ->
                broadBoardLines
                    |> List.any (String.contains "not earned cell by cell")
                    |> Expect.equal True
        , test "the board explanation says the whole roster is active" <|
            \() ->
                broadBoardLines
                    |> List.any (String.contains "are active at once")
                    |> Expect.equal True
        , test "the cell explanation says the cells gate nothing" <|
            \() ->
                broadCellLines
                    |> List.any (String.contains "no cell here can block or unblock it")
                    |> Expect.equal True
        , test "the cell explanation says an unplayed cell is unmeasured, not lost" <|
            \() ->
                broadCellLines
                    |> List.any (String.contains "unmeasured, not lost")
                    |> Expect.equal True
        , test "no sentence is repeated across the three broad explanations" <|
            \() ->
                -- Three panels could each reasonably say "all 25 ships are
                -- active", and when all three did, the page showed the same
                -- eleven paragraphs twice and nobody read any of them. Each
                -- fact belongs to exactly one panel.
                let
                    all =
                        broadLines ++ broadBoardLines ++ broadCellLines
                in
                Expect.equal (List.length all) (List.length (unique all))
        , test "the gate explanation no longer describes the board, which is another panel's job" <|
            \() ->
                broadLines
                    |> List.any (\line -> String.contains "are active at once" line || String.contains "not earned cell by cell" line)
                    |> Expect.equal False
        , test "detail attached to a tip keeps its id, title and meta" <|
            \() ->
                -- The long reasoning lives behind the explanation trigger, so
                -- a detailed tip has to stay the same tip: a changed id would
                -- collide with another bubble or orphan its aria-describedby,
                -- and dropped meta would lose the denominator the contract
                -- insists every metric states.
                let
                    detailed =
                        Tip.detail (Copy.overallGate Nothing) broadLines
                in
                Expect.equal
                    ( detailed.id, detailed.title, detailed.meta )
                    ( (Copy.overallGate Nothing).id, (Copy.overallGate Nothing).title, (Copy.overallGate Nothing).meta )
        , test "detail actually carries the reasoning into the bubble" <|
            \() ->
                Tip.detail (Copy.overallGate Nothing) broadLines
                    |> .body
                    |> String.contains "not a claim that the champion clears"
                    |> Expect.equal True
        , test "an empty detail list leaves the tip exactly as it was" <|
            \() ->
                Tip.detail (Copy.overallGate Nothing) []
                    |> Expect.equal (Copy.overallGate Nothing)
        , test "the on-screen cell sentence is one line, with the rest behind the tip" <|
            \() ->
                -- The panel prints List.take 1 of this and hides the rest, so
                -- the first entry has to be the one that stands alone.
                case broadCellLines of
                    first :: rest ->
                        Expect.equal
                            ( String.contains "cell" first, String.endsWith "." first, List.isEmpty rest )
                            ( True, True, False )

                    [] ->
                        Expect.fail "the cell explanation should not be empty"
        , test "carried-over provenance names the origin and the evidence that was cleared" <|
            \() ->
                broadLines
                    |> List.any (\line -> String.contains "mario-main-20260911" line && String.contains "abandoned" line)
                    |> Expect.equal True
        , test "readiness rows are called a probe rather than audit evidence" <|
            \() ->
                case decode broadReadyPayload of
                    Ok status ->
                        Gate.explainBroad Nothing status.curriculum status.overall status.shipPerformance
                            |> List.any (\line -> String.contains "readiness probe" line && String.contains "not audit evidence" line)
                            |> Expect.equal True

                    Err error ->
                        Expect.fail error
        , test "gate round rows do not get the readiness caveat" <|
            \() ->
                broadLines
                    |> List.any (String.contains "readiness probe")
                    |> Expect.equal False
        , test "the per-hull tip spells out that both groupings count our own wins" <|
            \() ->
                Expect.equal
                    ( String.contains "OUR champion's wins" (Copy.shipPerformance Nothing).body
                    , String.contains "when piloting" (Copy.shipPerformance Nothing).body
                    , String.contains "when facing" (Copy.shipPerformance Nothing).body
                    )
                    ( True, True, True )
        , test "the sampler tip refuses to call the balanced share board coverage" <|
            \() ->
                Expect.equal
                    ( String.contains "not a measurement of how much of the 625-cell board" Copy.samplerCoverage.body
                    , String.contains "balanced rotation" Copy.samplerCoverage.body
                    )
                    ( True, True )
        , test "the overall gate tip calls itself an operational check, not a guarantee" <|
            \() ->
                Expect.equal
                    ( String.contains "operational confidence check" (Copy.overallGate Nothing).body
                    , String.contains "not a formal guarantee" (Copy.overallGate Nothing).body
                    )
                    ( True, True )
        , test "the overall gate tip says timeouts count against it" <|
            \() ->
                String.contains "timeouts" (String.toLower (denominatorOf (Copy.overallGate Nothing)))
                    |> Expect.equal True
        ]


denominatorOf : Tip.Tip -> String
denominatorOf tip =
    tip.meta
        |> List.filter (\( key, _ ) -> key == "Denominator")
        |> List.map Tuple.second
        |> String.join " "


stagedUntouchedSuite : Test
stagedUntouchedSuite =
    describe "the staged gate is left alone"
        [ test "the per-cell explanation still answers why the roster has not grown" <|
            \() ->
                case decode livePayload of
                    Ok status ->
                        Gate.explain status.curriculum.target status.curriculum status.matchups
                            |> List.any (String.contains "ordered matchups")
                            |> Expect.equal True

                    Err error ->
                        Expect.fail error
        , test "a staged run's per-cell explanation never borrows broad wording" <|
            \() ->
                case decode livePayload of
                    Ok status ->
                        Gate.explain status.curriculum.target status.curriculum status.matchups
                            |> List.any (String.contains "balanced")
                            |> Expect.equal False

                    Err error ->
                        Expect.fail error
        ]


cumulativeEpisodeSuite : Test
cumulativeEpisodeSuite =
    describe "cumulative episode labelling"
        [ test "the throughput tip says cumulative and does not promise a per-generation figure" <|
            \() ->
                Expect.equal
                    ( String.contains "Cumulative" Copy.throughputChart.title
                    , String.contains "cumulative" (String.toLower Copy.throughputChart.body)
                    , String.contains "per generation" (String.toLower Copy.throughputChart.title)
                    )
                    ( True, True, False )
        , test "the throughput tip explains where the per-generation cost actually is" <|
            \() ->
                String.contains "step between two adjacent points" Copy.throughputChart.body
                    |> Expect.equal True
        ]


broadLines : List String
broadLines =
    case decode broadPayload of
        Ok status ->
            Gate.explainBroad Nothing status.curriculum status.overall status.shipPerformance

        Err _ ->
            []


broadBoardLines : List String
broadBoardLines =
    case decode broadPayload of
        Ok status ->
            Gate.explainBroadBoard status.curriculum

        Err _ ->
            []


broadCellLines : List String
broadCellLines =
    case decode broadPayload of
        Ok status ->
            Gate.explainBroadCells status.curriculum status.matchups

        Err _ ->
            []


overallWith : Int -> Int -> Maybe Float -> Maybe Float -> Api.Overall
overallWith wins games winRate lowerBound =
    { scope = "balanced-any-any"
    , target = 0.8
    , panel = 1000
    , pairs = 500
    , round = Just Api.AuditRound
    , wins = wins
    , games = games
    , winRate = winRate
    , lowerBound = lowerBound
    , championId = "champ-broad"
    , passed = False
    , audit = { wins = wins, games = games, winRate = winRate, lowerBound = lowerBound, passed = False }
    , confirm = { wins = 0, games = 0, winRate = Nothing, lowerBound = Nothing, passed = False }
    , attempt = 1
    }


shipRow : Api.Seat -> String -> Int -> Int -> Maybe Float -> Maybe Float -> Api.ShipPerformance
shipRow side ship wins games winRate lowerBound =
    { side = side
    , ship = ship
    , wins = wins
    , games = games
    , winRate = winRate
    , lowerBound = lowerBound
    , source = Api.FromAudit
    }


broadPayload : String
broadPayload =
    """
{
  "schema_version": 1,
  "run_id": "mario-any-any-20260911",
  "phase": "auditing",
  "generation": 80,
  "curriculum": {
    "stage": 48,
    "ladder": "broad",
    "evaluation_scope": "overall-balanced",
    "our_roster": ["Pkunk", "Umgah", "Chmmr"],
    "opponent_roster": ["Pkunk", "Umgah", "Chmmr"],
    "opponent_types": ["cyborg"],
    "next_side": "complete",
    "next_ship": null,
    "target": 0.8,
    "mastered_matchups": 11,
    "total_matchups": 625,
    "stage_unlocked_externally": true,
    "transition_reason": "operator requested any-versus-any",
    "origin_run_id": "mario-main-20260911",
    "origin_generation": 79,
    "origin_fingerprint": "b3f10c2a99",
    "opponent_revision": 0,
    "opponent_fingerprint": null,
    "self_play_is_gated": false
  },
  "overall": {
    "scope": "balanced-any-any",
    "target": 0.8,
    "panel": 1000,
    "pairs": 500,
    "round": "audit",
    "wins": 861,
    "games": 1000,
    "win_rate": 0.861,
    "lower_bound": 0.838,
    "champion_id": "b7712aa4e1",
    "passed": false,
    "audit": {"wins": 861, "games": 1000, "win_rate": 0.861, "lower_bound": 0.838, "passed": true},
    "confirm": {"wins": 0, "games": 0, "win_rate": null, "lower_bound": null, "passed": false},
    "attempt": 1
  },
  "ship_performance": [
    {"side": "ours", "ship": "Pkunk", "wins": 18, "games": 20, "win_rate": 0.9, "lower_bound": 0.699, "source": "audit"},
    {"side": "ours", "ship": "Umgah", "wins": 0, "games": 0, "win_rate": null, "lower_bound": null, "source": "audit"},
    {"side": "opponent", "ship": "Chmmr", "wins": 9, "games": 20, "win_rate": 0.45, "lower_bound": 0.256, "source": "audit"}
  ],
  "sampler": {"panel": 32, "coverage": 0.5, "cursor": 1184, "tour": 1},
  "readiness": {"threshold": 0.85, "games": 250, "period": 5, "last_rate": 0.88, "purpose": "broad balanced readiness"}
}
"""


broadReadyPayload : String
broadReadyPayload =
    """
{
  "curriculum": {"ladder": "broad", "evaluation_scope": "overall-balanced", "target": 0.8},
  "overall": null,
  "ship_performance": [
    {"side": "ours", "ship": "Pkunk", "wins": 4, "games": 5, "win_rate": 0.8, "lower_bound": 0.376, "source": "ready"}
  ]
}
"""


broadOriginMixedPayload : String
broadOriginMixedPayload =
    """
{
  "curriculum": {
    "stage": 48,
    "ladder": "mixed",
    "evaluation_scope": "overall-balanced",
    "opponent_types": ["cyborg", "model"],
    "self_play_is_gated": false,
    "transition_reason": "operator requested any-versus-any",
    "origin_run_id": "mario-main-20260911",
    "origin_generation": 79,
    "target": 0.8
  },
  "overall": {"scope": "balanced-any-any", "target": 0.8, "panel": 1000, "pairs": 500,
              "round": null, "wins": 0, "games": 0, "win_rate": null, "lower_bound": null,
              "champion_id": "", "passed": true, "attempt": 2}
}
"""


-- SCOPE CHANGE
--
-- The transition writes a history row at the new stage, so the run's own
-- history spans two different questions: "can it beat a handful of ships"
-- and "can it beat the whole board". A win rate from the first is not
-- progress toward the second, and the chart must not let one be read as
-- the other.


scopeChangeSuite : Test
scopeChangeSuite =
    describe "the scope change is visible"
        [ test "history spanning the transition decodes with both stages intact" <|
            \() ->
                case decode transitionHistoryPayload of
                    Ok status ->
                        List.map .stage status.history
                            |> Expect.equal [ 1, 1, 48, 48 ]

                    Err error ->
                        Expect.fail error
        , test "no line is drawn across the stage change, so the old rate cannot look like broad progress" <|
            \() ->
                case decode transitionHistoryPayload of
                    Ok status ->
                        Chart.runs (List.map .stage status.history)
                            (List.map .trainingWinRate status.history)
                            |> List.length
                            |> Expect.equal 2

                    Err error ->
                        Expect.fail error
        , test "the narrow points and the broad points never end up in one run" <|
            \() ->
                case decode transitionHistoryPayload of
                    Ok status ->
                        Chart.runs (List.map .stage status.history)
                            (List.map .trainingWinRate status.history)
                            |> List.map List.length
                            |> Expect.equal [ 2, 2 ]

                    Err error ->
                        Expect.fail error
        , test "the generation the transition happened at is preserved, not rewritten" <|
            \() ->
                case decode transitionHistoryPayload of
                    Ok status ->
                        Expect.equal
                            ( List.map .generation status.history
                            , status.curriculum.originGeneration
                            )
                            ( [ 77, 78, 79, 80 ], Just 79 )

                    Err error ->
                        Expect.fail error
        ]



-- READINESS BASELINE
--
-- The first thing a fresh broad run publishes is a 250-game readiness
-- baseline: ten games per hull, from the probe rather than from a gate
-- round. It is small, and it is not audit evidence. Both facts have to
-- survive into the UI.


readinessBaselineSuite : Test
readinessBaselineSuite =
    describe "the initial readiness baseline"
        [ test "the baseline rows are readiness rows, not gate evidence" <|
            \() ->
                case decode readyBaselinePayload of
                    Ok status ->
                        ( List.map .source status.shipPerformance |> List.all (\s -> s == Api.FromReadiness)
                        , List.any (Api.evidenceIsGate << .source) status.shipPerformance
                        )
                            |> Expect.equal ( True, False )

                    Err error ->
                        Expect.fail error
        , test "the small per-hull sample survives decoding rather than being rounded away" <|
            \() ->
                case decode readyBaselinePayload of
                    Ok status ->
                        List.map .games status.shipPerformance
                            |> Expect.equal [ 10, 10, 10 ]

                    Err error ->
                        Expect.fail error
        , test "a baseline with no overall round leaves the gate unjudged rather than failed" <|
            \() ->
                case decode readyBaselinePayload of
                    Ok status ->
                        Expect.equal status.overall Nothing

                    Err error ->
                        Expect.fail error
        , test "the explanation says the figures are a probe and not audit evidence" <|
            \() ->
                case decode readyBaselinePayload of
                    Ok status ->
                        Gate.explainBroad Nothing status.curriculum status.overall status.shipPerformance
                            |> List.any (\line -> String.contains "readiness probe" line && String.contains "not audit evidence" line)
                            |> Expect.equal True

                    Err error ->
                        Expect.fail error
        , test "the per-hull tip names readiness as a diagnostic in its own source line" <|
            \() ->
                Expect.equal
                    ( String.contains "readiness row" (sourceOf (Copy.shipPerformance Nothing))
                    , String.contains "diagnostic only" (sourceOf (Copy.shipPerformance Nothing))
                    )
                    ( True, True )
        ]


sourceOf : Tip.Tip -> String
sourceOf tip =
    tip.meta
        |> List.filter (\( key, _ ) -> key == "Source")
        |> List.map Tuple.second
        |> String.join " "


transitionHistoryPayload : String
transitionHistoryPayload =
    """
{
  "curriculum": {
    "stage": 48, "ladder": "broad", "evaluation_scope": "overall-balanced",
    "origin_run_id": "mario-main-20260911", "origin_generation": 79,
    "stage_unlocked_externally": true, "target": 0.8
  },
  "history": [
    {"generation": 77, "stage": 1, "training_win_rate": 0.91, "validation_win_rate": null, "episodes": 240000},
    {"generation": 78, "stage": 1, "training_win_rate": 0.93, "validation_win_rate": 0.9, "episodes": 246000},
    {"generation": 79, "stage": 48, "training_win_rate": 0.41, "validation_win_rate": null, "episodes": 252000},
    {"generation": 80, "stage": 48, "training_win_rate": 0.44, "validation_win_rate": null, "episodes": 258000}
  ]
}
"""


readyBaselinePayload : String
readyBaselinePayload =
    """
{
  "curriculum": {"stage": 48, "ladder": "broad", "evaluation_scope": "overall-balanced", "target": 0.8},
  "overall": null,
  "readiness": {"threshold": 0.85, "games": 250, "period": 5, "last_rate": 0.62, "purpose": "broad balanced readiness"},
  "ship_performance": [
    {"side": "ours", "ship": "Pkunk", "wins": 6, "games": 10, "win_rate": 0.6, "lower_bound": 0.313, "source": "ready"},
    {"side": "ours", "ship": "Umgah", "wins": 2, "games": 10, "win_rate": 0.2, "lower_bound": 0.057, "source": "ready"},
    {"side": "opponent", "ship": "Chmmr", "wins": 1, "games": 10, "win_rate": 0.1, "lower_bound": 0.018, "source": "ready"}
  ]
}
"""


-- SCORING
--
-- The score is the one number that decides which genomes breed, and the
-- crew ratio is the easiest figure on the page to misread: it looks like
-- a percentage, sits beside real percentages, and is neither a win rate
-- nor a fraction of maximum health. Every test here guards one specific
-- misreading, plus the one that matters most for the archive: a run that
-- predates the selector must never be dressed up as a crew-ratio run.


scoringSuite : Test
scoringSuite =
    describe "scoring rule"
        [ scoringDecoderSuite
        , scoringCopySuite
        , fightLimitSuite
        , gateSeparationSuite
        , renderSuite
        , crewLeadSuite
        , penaltySuite
        , combatVictorySuite
        , historyLegendSuite
        ]


{-| The staged run the operator actually launched: ranked on the crew
ratio, promoted on strict crew leads, with the no-damage penalty armed.
-}
crewLeadPayload : String
crewLeadPayload =
    """
{
  "run_id": "mario-ratio-staged-20260912",
  "episodes": 400,
  "episodes_unresolved": 240,
  "episodes_combat_wins": 37,
  "episodes_combat_counted_since": 0,
  "episodes_combat_wins_all_time": 37,
  "history": [
    {"generation": 0, "stage": 0, "training_win_rate": 0.4, "validation_win_rate": 0.55, "species": 3, "nodes": 70, "episodes": 1200},
    {"generation": 1, "stage": 0, "training_win_rate": 0.6, "validation_win_rate": 0.72, "species": 4, "nodes": 71, "episodes": 2400}
  ],
  "resources": {"workers": 8, "duty_cycle": 0.5, "episode_ticks": 1200},
  "curriculum": {"stage": 0, "target": 0.8, "our_roster": ["Pkunk"], "opponent_roster": ["Umgah"]},
  "champion": {"id": "g-1", "win_rate": 0.9, "lower_bound": 0.82, "validated_wins": 36, "validated_games": 40},
  "audit": {"panel": 40, "max_losses": 4},
  "scoring": {
    "fitness": "crew-ratio", "zero_opponent": 1000, "mutual_zero": 1,
    "speed_bonus": false, "gate": "crew-lead", "no_damage_penalty": 1000
  }
}
"""


crewLeadSuite : Test
crewLeadSuite =
    describe "a crew-lead gate is never rendered as wins"
        [ test "the criterion decodes as its own value rather than as an unrecognised string" <|
            \() ->
                case decode crewLeadPayload of
                    Ok status ->
                        Expect.equal (Maybe.map .gate status.scoring) (Just Api.CrewLead)

                    Err error ->
                        Expect.fail error
        , test "a scoring block that names no gate means the original criterion, not an unknown one" <|
            \() ->
                -- Absence is documented, not a guess: the only gate a build
                -- old enough to omit the field ever had was actual wins.
                case decode """{"scoring":{"fitness":"combat"}}""" of
                    Ok status ->
                        Expect.equal (Maybe.map .gate status.scoring) (Just Api.CombatWins)

                    Err error ->
                        Expect.fail error
        , test "the vocabulary follows the criterion, and absence keeps the original words" <|
            \() ->
                case ( decode crewLeadPayload, decode crewRatioPayload ) of
                    ( Ok lead, Ok wins ) ->
                        Expect.equal
                            ( ( Scoring.rateLabel lead.scoring, Scoring.successPlural lead.scoring )
                            , ( Scoring.rateLabel wins.scoring, Scoring.successPlural wins.scoring )
                            , ( Scoring.rateLabel Nothing, Scoring.successPlural Nothing )
                            )
                            ( ( "crew-lead rate", "crew leads" )
                            , ( "win rate", "wins" )
                            , ( "win rate", "wins" )
                            )

                    _ ->
                        Expect.fail "payloads did not decode"
        , test "an unrecognised criterion is neither reworded as wins nor guessed at" <|
            \() ->
                case decode """{"scoring":{"fitness":"combat","gate":"crew-fraction-at-deadline"}}""" of
                    Ok status ->
                        Expect.equal
                            ( Scoring.successPlural status.scoring
                            , Api.gateCriterionLabel (Scoring.criterion status.scoring)
                            )
                            ( "counted successes", "crew-fraction-at-deadline" )

                    Err error ->
                        Expect.fail error
        , test "the unresolved tile does not call an unresolved episode a non-win under this gate" <|
            \() ->
                -- The whole point of the crew comparison is that a fight
                -- nobody finished still scores, so "timed out, not won" would
                -- state a rule this run does not use.
                case ( decode crewLeadPayload, decode crewRatioPayload ) of
                    ( Ok lead, Ok wins ) ->
                        Expect.equal
                            ( Scoring.unresolvedNote lead.scoring
                            , String.contains "not won" (Scoring.unresolvedNote lead.scoring)
                            , Scoring.unresolvedNote wins.scoring
                            )
                            ( "unresolved; crew leads still count"
                            , False
                            , "timed out, not won"
                            )

                    _ ->
                        Expect.fail "payloads did not decode"
        , test "the gate's own explanation says leads are not wins and that ties fail" <|
            \() ->
                case decode crewLeadPayload of
                    Ok status ->
                        let
                            said phrase =
                                Scoring.explainGate status.scoring
                                    |> List.any (String.contains phrase)
                        in
                        Expect.equal
                            ( said "strictly greater"
                            , said "none of them is a count of wins"
                            , said "Ties do not count"
                            )
                            ( True, True, True )

                    Err error ->
                        Expect.fail error
        , test "no panel on the rendered page calls this run's tallies wins" <|
            \() ->
                expectRendered crewLeadPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Champion fresh audit crew-lead rate" ]
                        , Query.has [ Selector.text "Crew leads needed" ]
                        , Query.has [ Selector.text "crew leads over predeclared panel games" ]
                        , Query.has [ Selector.text "raw crew-lead rate" ]
                        , Query.hasNot [ Selector.text "Champion fresh audit win rate" ]
                        , Query.hasNot [ Selector.text "Wins needed" ]
                        , Query.hasNot [ Selector.text "wins over predeclared panel games" ]
                        ]
                    )
        , test "an archived run keeps every word the original gate earned" <|
            \() ->
                expectRendered crewRatioPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Champion fresh audit win rate" ]
                        , Query.hasNot [ Selector.text "crew-lead rate" ]
                        ]
                    )
        ]


penaltySuite : Test
penaltySuite =
    describe "the no-damage penalty"
        [ test "a reported magnitude is read as armed, and its absence as off" <|
            \() ->
                case ( decode crewLeadPayload, decode crewRatioPayload ) of
                    ( Ok armed, Ok legacy ) ->
                        Expect.equal
                            ( Maybe.map .noDamagePenalty armed.scoring
                            , Maybe.map .noDamagePenalty legacy.scoring
                            )
                            ( Just (Api.PenaltyOf 1000), Just Api.PenaltyOff )

                    _ ->
                        Expect.fail "payloads did not decode"
        , test "a magnitude of zero is off, because a punishment of nothing is not a punishment" <|
            \() ->
                case decode """{"scoring":{"fitness":"crew-ratio","no_damage_penalty":0}}""" of
                    Ok status ->
                        Expect.equal
                            ( Maybe.map .noDamagePenalty status.scoring
                            , Scoring.penaltyLabel status.scoring
                            )
                            ( Just Api.PenaltyOff, Nothing )

                    Err error ->
                        Expect.fail error
        , test "the tile shows the negated magnitude the fitness actually becomes" <|
            \() ->
                case decode crewLeadPayload of
                    Ok status ->
                        Expect.equal (Scoring.penaltyLabel status.scoring) (Just "\u{2212}1000")

                    Err error ->
                        Expect.fail error
        , test "the explanation ties the penalty to their end crew, not to damage we dealt" <|
            \() ->
                case decode crewLeadPayload of
                    Ok status ->
                        let
                            said phrase =
                                Scoring.penaltyExplain status.scoring
                                    |> List.any (String.contains phrase)
                        in
                        Expect.equal
                            ( said "not a measure of damage we dealt"
                            , said "moves fitness only"
                            )
                            ( True, True )

                    Err error ->
                        Expect.fail error
        , test "the penalty is independent of the gate: an armed run still names its own criterion" <|
            \() ->
                case decode """{"scoring":{"fitness":"combat","gate":"combat-wins","no_damage_penalty":1000}}""" of
                    Ok status ->
                        Expect.equal
                            ( Scoring.penaltyLabel status.scoring
                            , Scoring.successPlural status.scoring
                            )
                            ( Just "\u{2212}1000", "wins" )

                    Err error ->
                        Expect.fail error
        , test "the armed run shows the penalty on the page, and a legacy run shows it off" <|
            \() ->
                Expect.all
                    [ \() ->
                        expectRendered crewLeadPayload
                            (Expect.all
                                [ Query.has [ Selector.text "No-damage penalty" ]
                                , Query.has [ Selector.text "\u{2212}1000" ]
                                ]
                            )
                    , \() ->
                        expectRendered crewRatioPayload
                            (Query.has
                                [ Selector.text "no penalty for a fight that costs them nothing" ]
                            )
                    ]
                    ()
        ]


combatVictorySuite : Test
combatVictorySuite =
    describe "factual combat victories stay factual"
        [ test "a fresh run's counter is read as the run's own total" <|
            \() ->
                case decode crewLeadPayload of
                    Ok status ->
                        Expect.equal status.combatVictories (Just (Api.VictoriesAllTime 37))

                    Err error ->
                        Expect.fail error
        , test "a null all-time figure is a partial count, kept with the baseline it started from" <|
            \() ->
                -- The engine nulls the all-time field precisely when the
                -- window opened mid-run, so falling back to the raw count as
                -- though it were a total would invent evidence.
                case decode """{"episodes_combat_wins":5,"episodes_combat_counted_since":900,"episodes_combat_wins_all_time":null}""" of
                    Ok status ->
                        Expect.equal status.combatVictories
                            (Just (Api.VictoriesSince { victories = 5, sinceEpisodes = 900 }))

                    Err error ->
                        Expect.fail error
        , test "a run that publishes no counter shows none rather than a zero it never measured" <|
            \() ->
                case decode """{"run_id":"mario-main-20260911"}""" of
                    Ok status ->
                        Expect.equal
                            ( status.combatVictories
                            , Scoring.combatVictoriesValue status.combatVictories
                            )
                            ( Nothing, Nothing )

                    Err error ->
                        Expect.fail error
        , test "a partial count never appears without saying what it is a count since" <|
            \() ->
                Scoring.combatVictoriesNote
                    (Just (Api.VictoriesSince { victories = 5, sinceEpisodes = 900 }))
                    |> Expect.equal "resolved victories since episode 900"
        , test "the page shows the victory count beside the lead tallies without equating them" <|
            \() ->
                expectRendered crewLeadPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Combat victories" ]
                        , Query.has [ Selector.text "37" ]
                        , Query.has [ Selector.text "resolved victories, whole run, all episodes" ]
                        ]
                    )
        ]


{-| The history chart's two series, named for what the trainer actually
puts in them.

`validation_win_rate` is assigned in exactly one place in the trainer,
`step_probe`, which is the recurring readiness screen. Calling that
series "audit" promoted a screening probe to gate evidence on the one
panel a reader goes to for progress, and it said so beside a real audit
panel that means something else.

`training_win_rate` is recorded only for the champion's own member, so
"whole population" overstated it in the other direction.

-}
historyLegendSuite : Test
historyLegendSuite =
    describe "the history chart names its own evidence"
        [ test "the probe series is never called audit evidence" <|
            \() ->
                expectRendered crewLeadPayload
                    (Expect.all
                        [ Query.has
                            [ Selector.text "Champion readiness crew-lead rate (screening probe, not audit evidence)" ]
                        , Query.hasNot [ Selector.text "Champion audit crew-lead rate" ]
                        , Query.hasNot [ Selector.text "predeclared gate panel)" ]
                        ]
                    )
        , test "the training series is not claimed to cover the whole population" <|
            \() ->
                expectRendered crewLeadPayload
                    (Expect.all
                        [ Query.has
                            [ Selector.text "Training crew-lead rate (champion's own sampled panel this generation)" ]
                        , Query.hasNot [ Selector.text "whole population" ]
                        ]
                    )
        , test "an archived combat run gets the same correction in its own words" <|
            \() ->
                expectRendered combatHistoryPayload
                    (Expect.all
                        [ Query.has
                            [ Selector.text "Champion readiness win rate (screening probe, not audit evidence)" ]
                        , Query.hasNot [ Selector.text "Champion audit win rate" ]
                        ]
                    )
        , test "the chart's tooltip says neither series is gate evidence" <|
            \() ->
                let
                    tip =
                        Copy.winRateChart Nothing
                in
                Expect.equal
                    ( String.contains "neither of them is gate evidence" tip.body
                    , String.contains "a marker is never a passed gate" tip.body
                    , String.contains "readiness probe" (sourceOf (Copy.winRateChart Nothing))
                    )
                    ( True, True, True )
        ]


crewRatioPayload : String
crewRatioPayload =
    """
{
  "run_id": "mario-ratio-staged-20260912",
  "resources": {"workers": 1, "duty_cycle": 0.5, "episode_ticks": 1200, "nice": 10},
  "scoring": {
    "fitness": "crew-ratio", "zero_opponent": 1000, "mutual_zero": 1,
    "speed_bonus": false, "gate": "combat-wins"
  }
}
"""


combatHistoryPayload : String
combatHistoryPayload =
    """
{
  "run_id": "mario-main-20260911",
  "history": [
    {"generation": 0, "stage": 0, "training_win_rate": 0.4, "validation_win_rate": 0.55, "species": 3, "nodes": 70, "episodes": 1200}
  ],
  "resources": {"workers": 1, "duty_cycle": 0.5, "episode_ticks": 1200},
  "scoring": {"fitness": "combat", "gate": "combat-wins"}
}
"""


combatPayload : String
combatPayload =
    """
{
  "run_id": "mario-main-20260911",
  "resources": {"workers": 1, "duty_cycle": 0.5, "episode_ticks": 1200},
  "scoring": {
    "fitness": "combat", "zero_opponent": null, "mutual_zero": null,
    "speed_bonus": true, "gate": "combat-wins"
  }
}
"""


scoringOf : String -> Result String (Maybe Api.Scoring)
scoringOf json =
    decode json |> Result.map .scoring


scoringDecoderSuite : Test
scoringDecoderSuite =
    describe "decoding"
        [ test "a crew-ratio block decodes with the constants the run declared" <|
            \() ->
                Expect.equal (scoringOf crewRatioPayload)
                    (Ok
                        (Just
                            { fitness = Api.CrewRatio { zeroOpponent = Just 1000, mutualZero = Just 1 }
                            , speedBonus = Just False
                            , gate = Api.CombatWins
                            , noDamagePenalty = Api.PenaltyOff
                            }
                        )
                    )
        , test "a combat block decodes without picking up crew-ratio constants" <|
            \() ->
                Expect.equal (scoringOf combatPayload)
                    (Ok (Just { fitness = Api.Combat, speedBonus = Just True, gate = Api.CombatWins, noDamagePenalty = Api.PenaltyOff }))
        , test "an absent block stays absent rather than defaulting to a rule the run never used" <|
            \() ->
                Expect.equal (scoringOf """{"run_id":"mario-main-20260911"}""") (Ok Nothing)
        , test "an absent block reads as the original combat fitness, never as the crew ratio" <|
            \() ->
                -- The selector is newer than the runs it can be pointed at,
                -- so absence has a documented meaning. Printing "crew ratio"
                -- for an archived run would misdescribe every number under it.
                Expect.equal
                    ( Scoring.label Nothing
                    , String.contains "ratio" (Scoring.formula Nothing)
                    , String.contains "not reported" (Scoring.formula Nothing)
                    )
                    ( "combat", False, True )
        , test "an unreported constant is not filled in with the documented default" <|
            \() ->
                case scoringOf """{"scoring":{"fitness":"crew-ratio","gate":"combat-wins"}}""" of
                    Ok (Just reported) ->
                        Expect.equal ( reported.fitness, reported.speedBonus )
                            ( Api.CrewRatio { zeroOpponent = Nothing, mutualZero = Nothing }, Nothing )

                    _ ->
                        Expect.fail "expected a crew-ratio block"
        , test "an unknown fitness is preserved verbatim rather than collapsed into a known rule" <|
            \() ->
                case scoringOf """{"scoring":{"fitness":"crew-delta","gate":"combat-wins"}}""" of
                    Ok (Just reported) ->
                        Expect.equal reported.fitness (Api.UnknownFitness "crew-delta")

                    _ ->
                        Expect.fail "expected an unknown fitness"
        , test "an unknown gate criterion is preserved verbatim, so it is never rephrased as wins" <|
            \() ->
                case scoringOf """{"scoring":{"fitness":"crew-ratio","gate":"crew-ratio-above-one"}}""" of
                    Ok (Just reported) ->
                        Expect.equal ( reported.gate, Api.gateCriterionLabel reported.gate )
                            ( Api.UnknownGate "crew-ratio-above-one", "crew-ratio-above-one" )

                    _ ->
                        Expect.fail "expected an unknown gate"
        , test "a null scoring block is absence, not an empty rule" <|
            \() ->
                Expect.equal (scoringOf """{"scoring":null}""") (Ok Nothing)
        , test "the episode tick budget decodes, and its absence stays unknown rather than zero" <|
            \() ->
                Expect.equal
                    ( decode crewRatioPayload |> Result.map (.resources >> .episodeTicks)
                    , decode """{"resources":{"workers":1}}""" |> Result.map (.resources >> .episodeTicks)
                    )
                    ( Ok (Just 1200), Ok Nothing )
        ]


crewRatioLines : List String
crewRatioLines =
    case decode crewRatioPayload of
        Ok status ->
            Scoring.explain status.scoring status.resources

        Err _ ->
            []


saysCrewRatio : String -> Bool
saysCrewRatio needle =
    List.any (String.contains needle) crewRatioLines


scoringCopySuite : Test
scoringCopySuite =
    describe "what the scoring explanation is obliged to say"
        [ test "it states the formula as a ratio of two starting-crew shares" <|
            \() ->
                Expect.equal
                    ( saysCrewRatio "our surviving crew \u{00F7} our starting crew"
                    , saysCrewRatio "share of the crew they began with"
                    )
                    ( True, True )
        , test "it says the figure is not a win percentage and not a health fraction" <|
            \() ->
                Expect.equal
                    ( saysCrewRatio "not a win percentage"
                    , saysCrewRatio "not a fraction of maximum health"
                    )
                    ( True, True )
        , test "it says 1.00 is an even share rather than a win" <|
            \() ->
                saysCrewRatio "both sides kept the same share"
                    |> Expect.equal True
        , test "it allows a legitimate share above the starting complement" <|
            \() ->
                saysCrewRatio "above 100% on either side is legitimate"
                    |> Expect.equal True
        , test "it names the reported cap for a wiped-out opponent rather than dividing by nobody" <|
            \() ->
                saysCrewRatio "scores 1000"
                    |> Expect.equal True
        , test "it says a mutual wipe is even, at the value the run reported" <|
            \() ->
                Expect.equal
                    ( saysCrewRatio "Both crews at zero scores 1"
                    , saysCrewRatio "a mutual wipe is even"
                    )
                    ( True, True )
        , test "it says losing our whole crew against survivors scores zero" <|
            \() ->
                saysCrewRatio "Losing our whole crew while any of theirs survive scores 0."
                    |> Expect.equal True
        , test "it says there is no time bonus when the run reports none" <|
            \() ->
                saysCrewRatio "no time bonus"
                    |> Expect.equal True
        , test "an unreported cap is called unreported instead of printing the documented default" <|
            \() ->
                case decode """{"scoring":{"fitness":"crew-ratio","gate":"combat-wins"},"resources":{"episode_ticks":1200}}""" of
                    Ok status ->
                        let
                            lines =
                                Scoring.explain status.scoring status.resources
                        in
                        Expect.equal
                            ( List.any (String.contains "did not report what that value is") lines
                            , List.any (String.contains "scores 1000") lines
                            )
                            ( True, False )

                    Err error ->
                        Expect.fail error
        , test "an archived run with no block is explained as the original rule, not the ratio" <|
            \() ->
                case decode """{"resources":{"episode_ticks":1200}}""" of
                    Ok status ->
                        let
                            lines =
                                Scoring.explain status.scoring status.resources
                        in
                        Expect.equal
                            ( List.any (String.contains "It is not the crew ratio.") lines
                            , List.any (String.contains "surviving crew") lines
                            )
                            ( True, False )

                    Err error ->
                        Expect.fail error
        , test "an unrecognised rule is shown verbatim and not interpreted" <|
            \() ->
                case decode """{"scoring":{"fitness":"crew-delta"},"resources":{"episode_ticks":1200}}""" of
                    Ok status ->
                        Scoring.explain status.scoring status.resources
                            |> List.any (String.contains "which this dashboard does not recognise")
                            |> Expect.equal True

                    Err error ->
                        Expect.fail error
        , test "the three scoring tips are distinct anchors, so no two bubbles share a DOM id" <|
            \() ->
                let
                    ids =
                        List.map .id [ Copy.fitnessRule, Copy.fightLimit, Copy.gateCriterion ]
                in
                Expect.equal (List.length ids) (List.length (unique ids))
        , test "the scoring reasoning rides in the tip, keeping its id, title and meta" <|
            \() ->
                let
                    detailed =
                        Tip.detail Copy.fitnessRule crewRatioLines
                in
                Expect.equal
                    ( detailed.id, detailed.meta, String.contains "not a win percentage" detailed.body )
                    ( Copy.fitnessRule.id, Copy.fitnessRule.meta, True )
        ]


fightLimitSuite : Test
fightLimitSuite =
    describe "the fight deadline"
        [ test "1200 ticks at 60 a second is the twenty second limit" <|
            \() ->
                case decode crewRatioPayload of
                    Ok status ->
                        Expect.equal
                            ( Scoring.fightSeconds status.resources, Scoring.fightLimit status.resources )
                            ( Just 20, Just "20 s" )

                    Err error ->
                        Expect.fail error
        , test "the archived broad run's own budget of 3600 ticks reads as sixty seconds, not twenty" <|
            \() ->
                -- Taken from the stopped mario-any-any-20260911 server, which
                -- reports episode_ticks 3600 and no scoring block at all. The
                -- new run's twenty seconds is a property of that run, so
                -- nothing here may hard-code it.
                case decode """{"run_id":"mario-any-any-20260911","resources":{"workers":1,"duty_cycle":0.5,"episode_ticks":3600,"nice":10}}""" of
                    Ok status ->
                        Expect.equal
                            ( Scoring.fightLimit status.resources, Scoring.label status.scoring )
                            ( Just "60 s", "combat" )

                    Err error ->
                        Expect.fail error
        , test "a fractional budget keeps its decimal rather than rounding to a tidy lie" <|
            \() ->
                case decode """{"resources":{"episode_ticks":930}}""" of
                    Ok status ->
                        Expect.equal (Scoring.fightLimit status.resources) (Just "15.5 s")

                    Err error ->
                        Expect.fail error
        , test "an unreported budget is unknown, never zero seconds" <|
            \() ->
                Expect.equal
                    ( Scoring.fightSeconds Api.empty.resources, Scoring.fightLimit Api.empty.resources )
                    ( Nothing, Nothing )
        , test "a nonsense budget of zero ticks is unknown rather than an instant fight" <|
            \() ->
                case decode """{"resources":{"episode_ticks":0}}""" of
                    Ok status ->
                        Expect.equal (Scoring.fightLimit status.resources) Nothing

                    Err error ->
                        Expect.fail error
        , test "the limit is stated as simulated time, not as time the machine spends" <|
            \() ->
                Expect.equal
                    ( saysCrewRatio "cut off at 20 s of simulated time"
                    , saysCrewRatio "not of machine time"
                    )
                    ( True, True )
        , test "the limit is a cut-off for an unfinished fight, not the moment every fight is scored" <|
            \() ->
                -- A resolved fight ends early and is scored there. Calling
                -- the budget "the deadline the score is read at" would put a
                -- twenty second clock on fights that were over in four.
                Expect.equal
                    ( saysCrewRatio "A fight is scored when it ends."
                    , saysCrewRatio "One that neither side has finished is cut off"
                    )
                    ( True, True )
        , test "the tile note says the limit only binds a fight nobody finishes, with no time bonus" <|
            \() ->
                case decode crewRatioPayload of
                    Ok status ->
                        Scoring.limitNote status.scoring
                            |> Expect.equal "simulated, for a fight nobody finishes, and no time bonus"

                    Err error ->
                        Expect.fail error
        , test "a run that reports a speed bonus is not described as having none" <|
            \() ->
                case decode combatPayload of
                    Ok status ->
                        Scoring.limitNote status.scoring
                            |> String.contains "no time bonus"
                            |> Expect.equal False

                    Err error ->
                        Expect.fail error
        ]


gateSeparationSuite : Test
gateSeparationSuite =
    describe "fitness is not the gate"
        [ test "a crew-ratio run says in one line what breeds and what promotes" <|
            \() ->
                case decode crewRatioPayload of
                    Ok status ->
                        Scoring.gateNote status.scoring
                            |> Expect.equal (Just "Breeding ranks on crew ratio; this gate counts actual combat wins.")

                    Err error ->
                        Expect.fail error
        , test "the note repeats whatever gate criterion the engine declares, without rewording it" <|
            \() ->
                case decode """{"scoring":{"fitness":"crew-ratio","gate":"crew-fraction-at-deadline"}}""" of
                    Ok status ->
                        Scoring.gateNote status.scoring
                            |> Maybe.withDefault ""
                            |> String.contains "this gate counts crew-fraction-at-deadline."
                            |> Expect.equal True

                    Err error ->
                        Expect.fail error
        , test "a combat run adds no line, because nothing there invites the confusion" <|
            \() ->
                case decode combatPayload of
                    Ok status ->
                        Scoring.gateNote status.scoring |> Expect.equal Nothing

                    Err error ->
                        Expect.fail error
        , test "an archived run with no block adds no line either" <|
            \() ->
                Scoring.gateNote Nothing |> Expect.equal Nothing
        , test "the gate tip says a best-scoring genome can still fail the gate" <|
            \() ->
                String.contains "still fail this gate" Copy.gateCriterion.body
                    |> Expect.equal True
        ]


{-| The page itself, driven by a decoded status, so the scoring facts
are proven to reach the screen rather than merely to exist as strings.
-}
renderedFrom : String -> Result String (Query.Single Dashboard.Msg)
renderedFrom json =
    decode json
        |> Result.map
            (\status ->
                let
                    ( model, _ ) =
                        Dashboard.init ()
                in
                Dashboard.view { model | status = Just status, requested = True }
                    |> Query.fromHtml
            )


expectRendered : String -> (Query.Single Dashboard.Msg -> Expect.Expectation) -> Expect.Expectation
expectRendered json check =
    case renderedFrom json of
        Ok page ->
            check page

        Err error ->
            Expect.fail error


renderSuite : Test
renderSuite =
    describe "the page says it on screen"
        [ test "a crew-ratio run shows the rule and the deadline as their own tiles" <|
            \() ->
                expectRendered crewRatioPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Fitness" ]
                        , Query.has [ Selector.text "crew ratio" ]
                        , Query.has [ Selector.text "Fight limit" ]
                        , Query.has [ Selector.text "20 s" ]
                        , Query.has [ Selector.text "simulated, for a fight nobody finishes, and no time bonus" ]
                        ]
                    )
        , test "the gate panel carries the one line separating breeding from promotion" <|
            \() ->
                expectRendered crewRatioPayload
                    (Query.has
                        [ Selector.text "Breeding ranks on crew ratio; this gate counts actual combat wins." ]
                    )
        , test "a combat run adds no separating line, so the panel head stays quiet" <|
            \() ->
                expectRendered combatPayload
                    (Query.hasNot [ Selector.text "Breeding ranks on crew ratio" ])
        , test "an archived run with no scoring block is never labelled crew ratio" <|
            \() ->
                expectRendered """{"run_id":"mario-broad-any-any-20260911","resources":{"episode_ticks":1200}}"""
                    (Expect.all
                        [ Query.has [ Selector.text "combat" ]
                        , Query.hasNot [ Selector.text "crew ratio" ]
                        , Query.has [ Selector.text "20 s" ]
                        ]
                    )
        , test "a run that reports no tick budget shows the deadline as unmeasured, not as zero seconds" <|
            \() ->
                expectRendered """{"run_id":"mario-main-20260911","resources":{"workers":1}}"""
                    (Expect.all
                        [ Query.has [ Selector.text "Fight limit" ]
                        , Query.hasNot [ Selector.text "0 s" ]
                        ]
                    )
        ]
