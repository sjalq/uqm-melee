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
import Mario.Dashboard.Slots as Slots
import Mario.Dashboard.Topology as Topology
import Test exposing (Test, describe, fuzz, fuzz2, test)


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
                Copy.allTips
                    |> List.filter (\t -> String.length t.body < 40 || String.isEmpty t.title)
                    |> List.map .id
                    |> Expect.equal []
        , test "every tip states its denominator, its window and its source" <|
            \() ->
                Copy.allTips
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
                        List.map .id Copy.allTips
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
                    ( String.contains "audit" (String.toLower Copy.championRate.body)
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
