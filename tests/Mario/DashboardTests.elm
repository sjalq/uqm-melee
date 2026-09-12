module Mario.DashboardTests exposing (suite)

{-| Tests for the MarI/O dashboard.

The properties worth proving here are the ones that keep the page
honest rather than merely pretty:

  - an unmeasured value decodes and stays as `Nothing`, never as zero,
  - a future engine that adds fields or new enum values still renders,
  - charts never join samples across a gap in measurement,
  - the page reads coarse to fine, and nothing restates a number a band
    above it already showed,
  - the two "look closer" panels are folded shut until asked for,
  - a wall-clock throughput figure is labelled as load dependent and a
    per-unit-of-work figure is not,
  - the node id layout the topology view labels matches the contract,
  - every tooltip actually states its denominator, window and source.

-}

import Dict
import Expect
import Fuzz
import Html.Attributes as Attr
import Json.Decode as Decode
import Mario.Dashboard as Dashboard
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
        , layoutSuite
        , healthSuite
        , scoringSuite
        , resourceSuite
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



-- SHARED FIXTURES


decode : String -> Result String Api.Status
decode json =
    Decode.decodeString Api.decodeStatus json
        |> Result.mapError Decode.errorToString


{-| The page itself, driven by a decoded status, so a claim is proven to
reach the screen rather than merely to exist as a string.
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


{-| A training-exposure row, which is all a matchup carries now.
-}
matchup : String -> String -> Float -> Maybe Float -> Float -> Api.Matchup
matchup us them games rate weight =
    { us = us
    , them = them
    , opponentType = Api.Cyborg
    , sampleWeight = weight
    , trainingGames = games
    , trainingWinRate = rate
    }


sampleCells : List Api.Matchup
sampleCells =
    [ matchup "Pkunk" "Umgah" 44 (Just 0.91) 0.4
    , matchup "Pkunk" "Ilwrath" 40 (Just 0.75) 0.35
    , matchup "Spathi" "Umgah" 0 Nothing 0.2
    , matchup "Spathi" "Ilwrath" 40 (Just 0.95) 0.05
    ]


overallWith : Int -> Int -> Maybe Float -> Maybe Float -> Api.Overall
overallWith wins games rate bound =
    { scope = "balanced-any-any"
    , target = 0.8
    , panel = 500
    , pairs = 250
    , round = Just Api.AuditRound
    , wins = wins
    , games = games
    , winRate = rate
    , lowerBound = bound
    , championId = Just "g-champion"
    , passed = False
    , passedBy = Nothing
    , audit = { wins = wins, games = games, winRate = rate, lowerBound = bound, passed = False }
    , confirm = { wins = 0, games = 0, winRate = Nothing, lowerBound = Nothing, passed = False }
    , attempt = 2
    }


shipRow : Api.Seat -> String -> Int -> Int -> Maybe Float -> Maybe Float -> Api.EvidenceSource -> Api.ShipPerformance
shipRow side ship wins games rate bound source =
    { side = side
    , ship = ship
    , wins = wins
    , games = games
    , winRate = rate
    , lowerBound = bound
    , source = source
    }


readinessOf : Float -> Maybe Float -> Api.Readiness
readinessOf threshold lastRate =
    { threshold = threshold, games = 250, lastRate = lastRate, period = 5 }



-- DECODERS


decoderSuite : Test
decoderSuite =
    describe "status decoder"
        [ test "an empty object still decodes, so a partially populated engine renders" <|
            \() ->
                case decode "{}" of
                    Ok status ->
                        Expect.equal ( status.champion.id, status.overall, status.matchups )
                            ( Nothing, Nothing, [] )

                    Err error ->
                        Expect.fail error
        , test "a null overall rate decodes to Nothing, not to zero" <|
            \() ->
                case decode """{"overall":{"win_rate":null,"lower_bound":null,"games":0}}""" of
                    Ok status ->
                        Expect.equal (status.overall |> Maybe.map (\o -> ( o.winRate, o.lowerBound )))
                            (Just ( Nothing, Nothing ))

                    Err error ->
                        Expect.fail error
        , test "a genuine zero rate is preserved and is distinct from absence" <|
            \() ->
                case decode """{"overall":{"win_rate":0.0,"games":500}}""" of
                    Ok status ->
                        Expect.equal (status.overall |> Maybe.andThen .winRate) (Just 0)

                    Err error ->
                        Expect.fail error
        , test "with no champion every topology figure is null rather than a graph with no nodes" <|
            \() ->
                case decode """{"champion":{"id":null,"nodes":null,"connections":null,"hidden_nodes":null}}""" of
                    Ok status ->
                        Expect.equal status.champion
                            { id = Nothing, nodes = Nothing, connections = Nothing, hiddenNodes = Nothing }

                    Err error ->
                        Expect.fail error
        , test "a named champion decodes its counts" <|
            \() ->
                case decode """{"champion":{"id":"g4dd0","nodes":184,"connections":314,"hidden_nodes":114}}""" of
                    Ok status ->
                        Expect.equal status.champion
                            { id = Just "g4dd0", nodes = Just 184, connections = Just 314, hiddenNodes = Just 114 }

                    Err error ->
                        Expect.fail error
        , test "an empty champion id is the same absence a null is, so no caller tests for both" <|
            \() ->
                case decode """{"champion":{"id":""},"overall":{"champion_id":""}}""" of
                    Ok status ->
                        Expect.equal ( status.champion.id, status.overall |> Maybe.andThen .championId )
                            ( Nothing, Nothing )

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
        , test "the phase the engine no longer produces arrives as a stranger, not as a known state" <|
            \() ->
                -- A start that fails exits with its reason on stderr rather
                -- than publishing, so "error" is a string no build sends.
                case decode """{"phase":"error"}""" of
                    Ok status ->
                        Expect.equal status.phase (Api.UnknownPhase "error")

                    Err error ->
                        Expect.fail error
        , test "a full schema 4 payload decodes every documented block" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal
                            { run = status.runId
                            , schema = status.schemaVersion
                            , phase = status.phase
                            , board = status.board.totalMatchups
                            , target = status.overall |> Maybe.map .target
                            , bound = status.overall |> Maybe.andThen .lowerBound
                            , history = List.length status.history
                            , matchups = List.length status.matchups
                            , ships = List.length status.shipPerformance
                            , events = List.length status.events
                            , duty = status.resources.dutyCycle
                            , resumable = status.checkpoint.resumable
                            }
                            { run = "run-2026-09-12-a"
                            , schema = 4
                            , phase = Api.Auditing
                            , board = 625
                            , target = Just 0.8
                            , bound = Just 0.71
                            , history = 3
                            , matchups = 4
                            , ships = 2
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
        , test "a matchup row carries training exposure and nothing that could pass for a verdict" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal (List.take 1 status.matchups)
                            [ { us = "Pkunk"
                              , them = "Umgah"
                              , opponentType = Api.Cyborg
                              , sampleWeight = 0.4
                              , trainingGames = 44.5
                              , trainingWinRate = Just 0.909
                              }
                            ]

                    Err error ->
                        Expect.fail error
        , test "a cell with no decayed games carries no rate rather than a zero one" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        status.matchups
                            |> List.filter (\m -> m.trainingGames <= 0)
                            |> List.map .trainingWinRate
                            |> Expect.equal [ Nothing ]

                    Err error ->
                        Expect.fail error
        , test "the gate names whoever cleared it, so a result is never inherited silently" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal (status.overall |> Maybe.map (\o -> ( o.passed, o.passedBy )))
                            (Just ( False, Just "g-earlier" ))

                    Err error ->
                        Expect.fail error
        , test "the work block decodes its counts and its two per-unit rates" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal
                            (status.work
                                |> Maybe.map
                                    (\w ->
                                        ( w.displayTicks
                                        , w.cpuNanosPerDisplayTick
                                        , w.displayTicksPerEpisode
                                        )
                                    )
                            )
                            (Just ( 99074, Just 1463.7, Just 3096.1 ))

                    Err error ->
                        Expect.fail error
        , test "a process that has not computed reports no work and no split, not a page of zeroes" <|
            \() ->
                case decode """{"work":null,"phases":null,"benchmark":null}""" of
                    Ok status ->
                        Expect.equal ( status.work, status.phases, status.benchmark )
                            ( Nothing, Nothing, Nothing )

                    Err error ->
                        Expect.fail error
        , test "the phase split decodes all seven buckets in reading order" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal (status.phases |> Maybe.map (.buckets >> List.map .name))
                            (Just [ "simulate", "think", "encode", "compile", "evolve", "checkpoint", "serve" ])

                    Err error ->
                        Expect.fail error
        , test "a bucket the engine omits is present at zero seconds with no share" <|
            \() ->
                case decode """{"phases":{"simulate":{"seconds":2,"share":1.0}}}""" of
                    Ok status ->
                        status.phases
                            |> Maybe.map (.buckets >> List.filter (\b -> b.name == "serve"))
                            |> Expect.equal (Just [ { name = "serve", seconds = 0, share = Nothing } ])

                    Err error ->
                        Expect.fail error
        , test "the unaccounted remainder keeps its sign, because both signs mean something" <|
            \() ->
                case decode """{"phases":{"unaccounted_seconds":-0.42,"unaccounted_share_of_cpu":-0.006}}""" of
                    Ok status ->
                        Expect.equal (status.phases |> Maybe.andThen .unaccountedSeconds) (Just -0.42)

                    Err error ->
                        Expect.fail error
        , test "the benchmark reference decodes, including how many results the best was taken over" <|
            \() ->
                case decode fullPayload of
                    Ok status ->
                        Expect.equal status.benchmark
                            (Just
                                { at = Just "2026-09-12T08:00:00Z"
                                , build = Just "b6e517bda09bb2463"
                                , definition = Just "kf64e8f14b35445ef"
                                , repetitions = Just 5
                                , fights = Just 32
                                , bestSeconds = Just 0.145
                                , cpuNanosPerDisplayTick = Just 1463.7
                                , cpuNanosPerLinkActivation = Just 16.91
                                , comparableRows = 12
                                }
                            )

                    Err error ->
                        Expect.fail error
        , test "the combat victory counter is a whole-run total with no window to caveat" <|
            \() ->
                Expect.equal
                    ( decode """{"episodes_combat_wins":37}""" |> Result.map .episodesCombatWins
                    , decode """{"run_id":"x"}""" |> Result.map .episodesCombatWins
                    )
                    ( Ok (Just 37), Ok Nothing )
        , test "network genome decodes nodes and genes" <|
            \() ->
                Decode.decodeString Api.decodeNetwork networkPayload
                    |> Result.map (\n -> ( n.championId, List.length n.genome.nodes, List.length n.genome.genes ))
                    |> Expect.equal (Ok ( Just "champ-17", 3, 2 ))
        , test "a network with no champion decodes to an empty genome rather than failing" <|
            \() ->
                Decode.decodeString Api.decodeNetwork
                    """{"schema_version":4,"champion_id":null,"genome":null}"""
                    |> Result.map (\n -> ( n.championId, n.genome ))
                    |> Expect.equal (Ok ( Nothing, Api.emptyGenome ))
        , test "a gene with no explicit enabled flag defaults to enabled" <|
            \() ->
                Decode.decodeString Api.decodeNetwork
                    """{"champion_id":"c","genome":{"nodes":[],"genes":[{"innovation":1,"from":0,"to":57,"weight":0.5}]}}"""
                    |> Result.map (\n -> List.map .enabled n.genome.genes)
                    |> Expect.equal (Ok [ True ])
        ]


{-| A schema 4 document carrying every block the contract declares, in
the shape the engine publishes them.
-}
fullPayload : String
fullPayload =
    """
{"schema_version":4,"run_id":"run-2026-09-12-a","phase":"auditing","message":"auditing candidate",
 "generation":42,"episodes":128400,"episodes_unresolved":240,"episodes_combat_wins":37,
 "elapsed_seconds":7325.5,"episodes_per_second":3.4,
 "updated_at":"2026-09-12T10:15:00Z","stale":false,
 "scoring":{"fitness":"combat","speed_bonus":true,"gate":"combat-wins","no_damage_penalty":0},
 "board":{"total_matchups":625},
 "champion":{"id":"g-champion","nodes":184,"connections":314,"hidden_nodes":114},
 "population":{"size":300,"species":11,"mean_nodes":172.4,"mean_connections":283.1},
 "checkpoint":{"saved_at":"2026-09-12T10:14:30Z","generation":40,"resumable":true,
   "path":"artifacts/mario/run-2026-09-12-a"},
 "resources":{"workers":6,"duty_cycle":0.5,"measured_duty":0.47,"compute_seconds":3400.25,
   "episode_ticks":3600,"nice":10},
 "work":{"basis":"this process","episodes":32,"display_ticks":99074,"decisions":37128,
   "node_activations":1200000,"link_activations":8576568,"element_scans":303902,
   "elements_visited":2691259,"networks_compiled":0,
   "cpu_nanoseconds_per_display_tick":1463.7,"cpu_nanoseconds_per_link_activation":16.91,
   "display_ticks_per_episode":3096.1,"link_activations_per_decision":231.0,
   "elements_per_scan":8.85},
 "phases":{"basis":"per-thread wall totals","session_cpu_seconds":0.145,
   "session_wall_seconds":0.146,"threads_busy":0.99,"accounted_seconds":0.145,
   "accounted_share_of_cpu":1.0,"unaccounted_seconds":-0.0004,
   "unaccounted_share_of_cpu":-0.003,
   "simulate":{"seconds":0.092,"share":0.632},"think":{"seconds":0.017,"share":0.117},
   "encode":{"seconds":0.036,"share":0.251},"compile":{"seconds":0.0,"share":0.0},
   "evolve":{"seconds":0.0,"share":0.0},"checkpoint":{"seconds":0.0,"share":0.0},
   "serve":{"seconds":0.0,"share":0.0}},
 "benchmark":{"at":"2026-09-12T08:00:00Z","build":"b6e517bda09bb2463",
   "definition":"kf64e8f14b35445ef","repetitions":5,"fights":32,"best_seconds":0.145,
   "cpu_nanoseconds_per_display_tick":1463.7,"cpu_nanoseconds_per_link_activation":16.91,
   "comparable_rows":12},
 "readiness":{"threshold":0.85,"games":250,"last_rate":0.82,"period":5},
 "history":[
   {"generation":40,"training_win_rate":0.61,"validation_win_rate":null,"species":9,"nodes":172,"episodes":3000},
   {"generation":41,"training_win_rate":0.52,"validation_win_rate":null,"species":10,"nodes":173,"episodes":3100},
   {"generation":42,"training_win_rate":0.64,"validation_win_rate":0.82,"species":11,"nodes":174,"episodes":5200}],
 "overall":{"scope":"balanced-any-any","target":0.8,"panel":500,"pairs":250,"round":"audit",
   "wins":402,"games":500,"win_rate":0.804,"lower_bound":0.71,"champion_id":"g-champion",
   "passed":false,"passed_by":"g-earlier",
   "audit":{"wins":402,"games":500,"win_rate":0.804,"lower_bound":0.71,"passed":false},
   "confirm":{"wins":0,"games":0,"win_rate":null,"lower_bound":null,"passed":false},
   "attempt":3},
 "ship_performance":[
   {"side":"ours","ship":"Pkunk","wins":18,"games":20,"win_rate":0.9,"lower_bound":0.7,"source":"audit"},
   {"side":"opponent","ship":"Umgah","wins":4,"games":20,"win_rate":0.2,"lower_bound":0.08,"source":"audit"}],
 "sampler":{"panel":900,"coverage":0.35,"cursor":41250,"tour":66},
 "matchups":[
   {"us":"Pkunk","them":"Umgah","opponent_type":"cyborg","sample_weight":0.4,"training_games":44.5,"training_win_rate":0.909},
   {"us":"Pkunk","them":"Ilwrath","opponent_type":"cyborg","sample_weight":0.35,"training_games":40.0,"training_win_rate":0.75},
   {"us":"Spathi","them":"Umgah","opponent_type":"cyborg","sample_weight":0.2,"training_games":0.0,"training_win_rate":null},
   {"us":"Spathi","them":"Ilwrath","opponent_type":"cyborg","sample_weight":0.05,"training_games":40.0,"training_win_rate":0.95}],
 "events":[{"at":"2026-09-12T10:00:00Z","message":"run seeded"},
           {"at":"2026-09-12T10:14:00Z","message":"audit started for g-champion"}]}
"""


networkPayload : String
networkPayload =
    """
{"schema_version":4,"champion_id":"champ-17",
 "genome":{"schema_version":1,
   "nodes":[{"id":0,"kind":"input"},{"id":57,"kind":"output"},{"id":70,"kind":"hidden"}],
   "genes":[{"innovation":1,"from":0,"to":70,"weight":1.25,"enabled":true},
            {"innovation":2,"from":70,"to":57,"weight":-0.5,"enabled":false}]}}
"""



-- GATE


gateSuite : Test
gateSuite =
    describe "gate analysis"
        [ test "no games on the panel means no verdict rather than a failing score" <|
            \() ->
                Gate.overallVerdict (overallWith 0 0 Nothing Nothing)
                    |> Expect.equal Gate.NoEvidence
        , test "a high raw rate with no bound is undecided, never a pass" <|
            \() ->
                Gate.overallVerdict (overallWith 500 500 (Just 1.0) Nothing)
                    |> Expect.equal (Gate.RateOnly 1.0)
        , test "a rate above target with a bound below target is short, not passing" <|
            \() ->
                Gate.overallVerdict (overallWith 450 500 (Just 0.9) (Just 0.59))
                    |> Expect.equal (Gate.Short 0.59)
        , test "only a bound at or above target passes" <|
            \() ->
                Gate.overallVerdict (overallWith 460 500 (Just 0.92) (Just 0.8))
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
        , test "the weakest hull leads and an unmeasured hull sorts last, never first" <|
            \() ->
                Gate.blindSpots
                    [ shipRow Api.OurSeat "Strong" 19 20 (Just 0.95) (Just 0.77) Api.FromAudit
                    , shipRow Api.OurSeat "Silent" 0 0 Nothing Nothing Api.FromAudit
                    , shipRow Api.OurSeat "Weak" 4 20 (Just 0.2) (Just 0.08) Api.FromAudit
                    ]
                    |> List.map .ship
                    |> Expect.equal [ "Weak", "Strong", "Silent" ]
        , test "seat coverage counts hulls with games apart from hulls that are merely listed" <|
            \() ->
                Gate.seatCoverage
                    [ shipRow Api.OurSeat "A" 5 10 (Just 0.5) (Just 0.3) Api.FromAudit
                    , shipRow Api.OurSeat "B" 0 0 Nothing Nothing Api.FromAudit
                    , shipRow Api.OpponentSeat "A" 5 10 (Just 0.5) (Just 0.3) Api.FromAudit
                    ]
                    |> Expect.equal { ours = 2, oursWithGames = 1, opponent = 1, opponentWithGames = 1 }
        , test "the explanation leads with the one graded question, not with a cell count" <|
            \() ->
                case Gate.explainOverall Nothing { totalMatchups = 625 } (Just (overallWith 402 500 (Just 0.8) (Just 0.71))) [] of
                    first :: _ ->
                        Expect.equal True (String.startsWith "The run is judged on one number" first)

                    [] ->
                        Expect.fail "expected an explanation"
        , test "the explanation says the whole board is active and that nothing is unlocked by stages" <|
            \() ->
                let
                    prose =
                        Gate.explainOverall Nothing { totalMatchups = 625 } (Just (overallWith 402 500 (Just 0.8) (Just 0.71))) []
                            |> String.join " "
                in
                Expect.equal
                    ( String.contains "625 ordered matchups are trained on from generation one" prose
                    , String.contains "no cell has a gate of its own" prose
                    )
                    ( True, True )
        , test "no word of the explanation reinstates the deleted ladder vocabulary" <|
            \() ->
                let
                    prose =
                        Gate.explainOverall Nothing { totalMatchups = 625 } (Just (overallWith 402 500 (Just 0.8) (Just 0.71))) []
                            |> String.join " "
                            |> String.toLower
                in
                [ "stage", "mastered", "promotion", "roster grows", "ladder" ]
                    |> List.filter (\word -> String.contains word prose)
                    |> Expect.equal []
        , test "a gate cleared by an earlier champion is named rather than inherited" <|
            \() ->
                let
                    inherited =
                        overallWith 402 500 (Just 0.8) (Just 0.71)

                    prose =
                        Gate.explainOverall Nothing
                            { totalMatchups = 625 }
                            (Just { inherited | passedBy = Just "g-earlier", championId = Just "g-now" })
                            []
                            |> String.join " "
                in
                Expect.equal True (String.contains "is not inherited" prose)
        , test "a readiness-sourced table is called a probe rather than gate evidence" <|
            \() ->
                Gate.explainOverall Nothing
                    { totalMatchups = 625 }
                    (Just (overallWith 402 500 (Just 0.8) (Just 0.71)))
                    [ shipRow Api.OurSeat "A" 5 10 (Just 0.5) (Just 0.3) Api.FromReadiness ]
                    |> List.any (String.contains "not from a gate round")
                    |> Expect.equal True
        , test "the next-gate steps are the three the run actually walks, in order" <|
            \() ->
                Gate.nextGateSteps Nothing (readinessOf 0.85 (Just 0.82)) (Just (overallWith 402 500 (Just 0.8) (Just 0.71)))
                    |> List.length
                    |> Expect.equal 3
        , test "the first step is the screening probe and it states the threshold it must clear" <|
            \() ->
                case Gate.nextGateSteps Nothing (readinessOf 0.85 (Just 0.82)) (Just (overallWith 402 500 (Just 0.8) (Just 0.71))) of
                    first :: _ ->
                        Expect.equal
                            ( String.contains "82.0%" first, String.contains "85%" first )
                            ( True, True )

                    [] ->
                        Expect.fail "expected steps"
        , test "an unscored probe says so rather than reporting a rate of zero" <|
            \() ->
                case Gate.nextGateSteps Nothing (readinessOf 0.85 Nothing) Nothing of
                    first :: _ ->
                        Expect.equal True (String.startsWith "No readiness probe has been scored yet" first)

                    [] ->
                        Expect.fail "expected steps"
        , test "the demand is stated as an observed count, never as the bare target" <|
            \() ->
                Gate.nextGateSteps Nothing (readinessOf 0.85 (Just 0.9)) (Just (overallWith 0 0 Nothing Nothing))
                    |> String.join " "
                    |> String.contains "observed wins"
                    |> Expect.equal True
        , test "with no published panel neither the size nor the demand is invented" <|
            \() ->
                Gate.nextGateSteps Nothing (readinessOf 0.85 Nothing) Nothing
                    |> String.join " "
                    |> String.contains "no balanced panel yet"
                    |> Expect.equal True
        ]



-- CHART


chartSuite : Test
chartSuite =
    describe "chart geometry"
        [ test "a gap in measurement breaks the line instead of being drawn as zero" <|
            \() ->
                Chart.runs [ Just 0.5, Nothing, Just 0.7, Just 0.9 ]
                    |> Expect.equal [ [ ( 0, 0.5 ) ], [ ( 2, 0.7 ), ( 3, 0.9 ) ] ]
        , test "a fully measured history is one unbroken run, because every point asks the same question" <|
            \() ->
                -- The staged ladder is gone, so there is no scope change left
                -- for the geometry to break at, and inventing one would draw
                -- a discontinuity the data does not have.
                Chart.runs [ Just 1, Just 2, Just 3 ]
                    |> Expect.equal [ [ ( 0, 1 ), ( 1, 2 ), ( 2, 3 ) ] ]
        , test "no measurements produce no runs at all" <|
            \() ->
                Chart.runs [ Nothing, Nothing ]
                    |> Expect.equal []
        , fuzz (Fuzz.listOfLengthBetween 0 20 (Fuzz.maybe (Fuzz.floatRange 0 1)))
            "every measured sample appears exactly once across the runs"
          <|
            \values ->
                let
                    measured =
                        values |> List.filterMap identity |> List.length

                    emitted =
                        Chart.runs values |> List.concat |> List.length
                in
                Expect.equal measured emitted
        , fuzz (Fuzz.listOfLengthBetween 0 20 (Fuzz.maybe (Fuzz.floatRange 0 1)))
            "indices come back in order and never repeat"
          <|
            \values ->
                let
                    indices =
                        Chart.runs values |> List.concat |> List.map Tuple.first
                in
                Expect.equal indices (List.sort (unique indices))
        ]



-- HEATMAP


heatmapSuite : Test
heatmapSuite =
    describe "matchup grid"
        [ test "rows and columns come from the published rows, in the order they arrived" <|
            \() ->
                let
                    g =
                        Heatmap.grid sampleCells
                in
                Expect.equal ( g.rows, g.cols ) ( [ "Pkunk", "Spathi" ], [ "Umgah", "Ilwrath" ] )
        , test "every published pair reaches the grid, so no row can be silently dropped" <|
            \() ->
                let
                    g =
                        Heatmap.grid (matchup "Orz" "Mycon" 2 (Just 0.5) 0.1 :: sampleCells)
                in
                Expect.equal
                    ( List.member "Orz" g.rows, List.member "Mycon" g.cols, Dict.size g.cells )
                    ( True, True, 5 )
        , test "an unmeasured cell gets its own fill, distinct from any measured value" <|
            \() ->
                Expect.notEqual (Heatmap.cellFill 0.8 Nothing) (Heatmap.cellFill 0.8 (Just 0))
        , test "crossing the reference rate changes the colour family" <|
            \() ->
                Expect.notEqual (Heatmap.cellFill 0.8 (Just 0.799)) (Heatmap.cellFill 0.8 (Just 0.8))
        , test "names shorten only as the grid grows" <|
            \() ->
                Expect.equal
                    ( Heatmap.shortName 4 "Androsynth", Heatmap.shortName 25 "Androsynth" )
                    ( "Androsynth", "And" )
        ]



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
                    { sensors = 93
                    , observations = 103
                    , bias = 116
                    , inputs = 117
                    , outputFirst = 117
                    , outputs = 13
                    , hiddenFirst = 130
                    }
        , test "group boundaries land where the contract says" <|
            \() ->
                Expect.equal (List.map Slots.groupOf [ 0, 92, 93, 97, 98, 102, 103, 107, 108, 115, 116, 117, 121, 122, 129, 130 ])
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
                    (List.map (\i -> (Slots.slot i).short) [ 93, 94, 95, 96, 97, 98, 102 ])
                    [ "us b0", "us b1", "us b2", "us b3", "us b4", "them b0", "them b4" ]
        , test "control outputs keep the encoder's order" <|
            \() ->
                Expect.equal (List.map (\i -> (Slots.slot i).short) (List.range 117 121))
                    Slots.controlNames
        , test "memory outputs name the input they feed on the next step" <|
            \() ->
                Expect.equal True (String.contains "input 108" (Slots.slot 122).detail)
        , test "the sensor constant and the extra bias are described as different things" <|
            \() ->
                Expect.equal True (String.contains "Distinct from the extra bias" (Slots.slot 92).detail)
        , fuzz (Fuzz.intRange 0 400) "every node id resolves to a named slot" <|
            \id ->
                Expect.equal False (String.isEmpty (Slots.slot id).short)
        ]



-- TOPOLOGY


{-| Named landmarks so these topology tests stay about the graph rather than
about how wide the observation vector happens to be.
-}
out0 : Int
out0 =
    Slots.outputFirst


h0 : Int
h0 =
    Slots.hiddenFirst


h1 : Int
h1 =
    Slots.hiddenFirst + 1


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
                            [ ( 0, "input" ), ( h0, "hidden" ), ( h1, "hidden" ), ( out0, "output" ) ]
                            [ link 1 0 h0 1
                            , link 2 h0 h1 1
                            , link 3 h1 h0 1
                            , link 4 h1 out0 1
                            ]
                in
                Topology.hiddenDepths cyclic
                    |> (\depths -> ( Dict.get h0 depths, Dict.get h1 depths ))
                    |> Expect.equal ( Just 1, Just 2 )
        , test "a node referenced only by a gene is still placed, not silently dropped" <|
            \() ->
                let
                    partial =
                        genome [ ( 0, "input" ) ] [ link 1 0 (Slots.hiddenFirst + 29) 1 ]
                in
                Topology.orderedIds partial
                    |> List.member (Slots.hiddenFirst + 29)
                    |> Expect.equal True
        , test "an undeclared node is counted so an invalid genome cannot look clean" <|
            \() ->
                Topology.summarize (genome [ ( 0, "input" ) ] [ link 1 0 (Slots.hiddenFirst + 29) 1 ])
                    |> .undeclared
                    |> Expect.equal 1
        , test "disabled genes are counted separately from enabled ones" <|
            \() ->
                Topology.summarize
                    (genome
                        [ ( 0, "input" ), ( out0, "output" ) ]
                        [ link 1 0 out0 1, disabledLink 2 0 out0 -1 ]
                    )
                    |> (\s -> ( s.enabled, s.disabled ))
                    |> Expect.equal ( 1, 1 )
        , test "a link from an output back to a hidden node is counted as recurrent" <|
            \() ->
                Topology.summarize
                    (genome
                        [ ( 0, "input" ), ( h0, "hidden" ), ( out0, "output" ) ]
                        [ link 1 0 h0 1, link 2 h0 out0 1, link 3 out0 h0 1 ]
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
                Copy.allTips Nothing
                    |> List.filter (\t -> String.length t.body < 40 || String.isEmpty t.title)
                    |> List.map .id
                    |> Expect.equal []
        , test "every tip states its denominator, its window and its source" <|
            \() ->
                Copy.allTips Nothing
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
        , test "no tooltip still describes a panel the page no longer has" <|
            \() ->
                -- The staged ladder is gone. A tip that still explains a
                -- stage, a promotion or a per-cell gate would send a reader
                -- looking for a panel that does not exist.
                let
                    banned =
                        [ "stage", "mastered", "ladder", "expansion", "promoted", "roster" ]

                    offending tip =
                        banned
                            |> List.filter (\word -> String.contains word (String.toLower (tip.title ++ " " ++ tip.body)))
                            |> List.isEmpty
                            |> not
                in
                Copy.allTips Nothing
                    |> List.filter offending
                    |> List.map .id
                    |> Expect.equal []
        , test "the training and audit tips each say which kind of evidence they describe" <|
            \() ->
                Expect.equal
                    ( String.contains "held-out" (String.toLower (Copy.overallGate Nothing).body)
                    , String.contains "training" (String.toLower Copy.sampleAllocation.body)
                    )
                    ( True, True )
        , test "the matchup grid tip calls itself training exposure, never audit evidence" <|
            \() ->
                Expect.equal
                    ( String.contains "training" (String.toLower Copy.heatmap.body)
                    , String.contains "it gates nothing" (String.toLower (sourceOf Copy.heatmap))
                    )
                    ( True, True )
        , test "the throughput tip warns that its own figure is load dependent" <|
            \() ->
                String.contains "load dependent" Copy.episodesPerSecond.body
                    |> Expect.equal True
        , test "the per-unit-of-work tip says the worker count cannot move its figures" <|
            \() ->
                String.contains "when the worker count changes" Copy.workRates.body
                    |> Expect.equal True
        , test "the benchmark tip says the figure is a best of several, not a single run" <|
            \() ->
                String.contains "BEST of several repetitions" Copy.benchmark.body
                    |> Expect.equal True
        ]


sourceOf : Tip.Tip -> String
sourceOf tip =
    tip.meta
        |> List.filter (\( key, _ ) -> key == "Source")
        |> List.map Tuple.second
        |> String.join " "



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
                Dashboard.clearSettledControl (statusWithPhase Api.Training) (Dashboard.ControlAccepted Dashboard.Pause)
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



-- LAYOUT
--
-- The page is meant to be readable by someone who does not already know
-- the system, which is a property of the ORDER as much as of the words.
-- Each test below pins one half of that: the four questions appear once
-- each, coarse before fine; the two panels that reward study rather than
-- a glance start folded; and nothing that died with the staged ladder
-- came back.


bandTitles : List String
bandTitles =
    [ "Am I winning?", "What is it doing?", "Is it learning?", "Is it healthy?" ]


layoutSuite : Test
layoutSuite =
    describe "the page reads coarse to fine"
        [ test "all four bands are on the page, each exactly once" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        (List.map
                            (\title page -> Query.has [ Selector.text title ] page)
                            bandTitles
                        )
                    )
        , test "the headline gate is inside the first band, above everything else" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.class "gate-rate" ]
                        , Query.has [ Selector.text "80.4%" ]
                        , Query.has [ Selector.text "Overall balanced win rate" ]
                        ]
                    )
        , test "the two look-closer panels are folded shut, and only those two" <|
            \() ->
                expectRendered fullPayload
                    (Query.findAll [ Selector.class "panel-fold" ]
                        >> Query.count (Expect.equal 2)
                    )
        , test "no panel on the page is marked open, so both folds start shut" <|
            \() ->
                expectRendered fullPayload
                    (Query.hasNot [ Selector.attribute (Attr.attribute "open" "") ])
        , test "the folded panels are the matchup grid and the network graph" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Ordered matchup training exposure" ]
                        , Query.has [ Selector.text "Champion network topology" ]
                        ]
                    )
        , test "no panel the staged ladder owned survived the reorganisation" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.hasNot [ Selector.text "Curriculum" ]
                        , Query.hasNot [ Selector.text "Cells holding the gate up" ]
                        , Query.hasNot [ Selector.text "Next addition" ]
                        , Query.hasNot [ Selector.text "Rosters in frozen expansion order" ]
                        , Query.hasNot [ Selector.text "Regression rehearsal" ]
                        , Query.hasNot [ Selector.text "Cumulative episodes" ]
                        , Query.hasNot [ Selector.text "Any ship versus any ship" ]
                        ]
                    )
        , test "the champion is named in the gate panel and nowhere is its topology restated" <|
            \() ->
                -- The node count used to be printed four times: in the gate,
                -- in the nodes chart, in the population tiles and in the
                -- graph's own summary. Only the last two survive, and they
                -- are different quantities.
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "g-champion" ]
                        , Query.hasNot [ Selector.text "Topology" ]
                        ]
                    )
        , test "band two answers what it is playing and what would open the next gate" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "What it is playing" ]
                        , Query.has [ Selector.text "What opens the next gate" ]
                        , Query.has [ Selector.text "Training sample allocation" ]
                        ]
                    )
        , test "band three answers whether it is learning" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Population and structure" ]
                        , Query.has [ Selector.text "Species" ]
                        , Query.has [ Selector.text "Champion nodes" ]
                        , Query.has [ Selector.text "Per-hull blind spots" ]
                        ]
                    )
        , test "band four answers whether it is healthy" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Throughput and cost" ]
                        , Query.has [ Selector.text "Where the time went" ]
                        , Query.has [ Selector.text "Benchmark reference" ]
                        , Query.has [ Selector.text "Machine and checkpoint" ]
                        , Query.has [ Selector.text "Run events" ]
                        ]
                    )
        , test "the board size is stated once, and never as progress through it" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "ordered matchups, all active from generation one" ]
                        , Query.hasNot [ Selector.text "mastered" ]
                        ]
                    )
        ]



-- HEALTH
--
-- The profiling figures are the reason the health band exists, and the
-- one way to get them wrong is to let a wall-clock number sit beside a
-- per-unit-of-work number with nothing to tell them apart.


healthSuite : Test
healthSuite =
    describe "the health band is honest about what its numbers measure"
        [ test "the per-unit-of-work rates reach the screen" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "CPU ns / tick" ]
                        , Query.has [ Selector.text "1463.7" ]
                        , Query.has [ Selector.text "CPU ns / link" ]
                        , Query.has [ Selector.text "16.91" ]
                        ]
                    )
        , test "the wall-clock throughput figure says on the page that it is load dependent" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Episodes / second" ]
                        , Query.has [ Selector.text "wall clock, so load dependent; not a measure of the build" ]
                        ]
                    )
        , test "a process that has not computed shows absence, not a page of zeroes" <|
            \() ->
                expectRendered """{"run_id":"fresh","work":null,"phases":null,"benchmark":null}"""
                    (Expect.all
                        [ Query.has [ Selector.text "This process has not computed yet, so there is nothing to divide by and the per-unit-of-work rates are absent rather than zero. Reading a checkpoint from disk is such a process." ]
                        , Query.has [ Selector.text "Not benchmarked" ]
                        , Query.hasNot [ Selector.text "1463.7" ]
                        , Query.hasNot [ Selector.text "Where the time went is unavailable" ]
                        ]
                    )
        , test "the phase split reaches the screen as named buckets" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "simulate" ]
                        , Query.has [ Selector.text "encode" ]
                        , Query.has [ Selector.text "think" ]
                        ]
                    )
        , test "a bucket with no seconds is left out rather than drawn as an empty bar" <|
            \() ->
                -- The fixture spends nothing in four of the seven buckets, so
                -- only the three that cost something get a bar. A zero-width
                -- bar would read as a measured phase that happens to be free.
                expectRendered fullPayload
                    (Query.hasNot [ Selector.text "compile" ])
        , test "the unaccounted remainder is shown signed, and negative is explained" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Unaccounted" ]
                        , Query.has [ Selector.text "\u{2212}0.000s (0.3% of CPU), workers preempted mid-fight" ]
                        ]
                    )
        , test "a positive remainder is labelled as CPU nobody clocked" <|
            \() ->
                expectRendered """{"run_id":"x","phases":{"unaccounted_seconds":0.5,"unaccounted_share_of_cpu":0.02}}"""
                    (Query.has [ Selector.text "+0.500s (2.0% of CPU), CPU nobody clocked" ])
        , test "the benchmark reference states the best of N and what it was taken over" <|
            \() ->
                expectRendered fullPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Best of N" ]
                        , Query.has [ Selector.text "0.145s" ]
                        , Query.has [ Selector.text "fastest of 5 repetitions over 32 fixed fights" ]
                        , Query.has [ Selector.text "2026-09-12T08:00:00Z \u{00B7} best of 12 comparable results" ]
                        ]
                    )
        , test "the live rate is compared with the recorded one in the same units" <|
            \() ->
                expectRendered fullPayload
                    (Query.has [ Selector.text "This session is running at 1.00x the recorded cost per simulated tick. Above one is the price of sharing the machine and of spilling workers onto slower cores; it is not a change in the build." ])
        , test "with only one of the two rates there is no ratio invented" <|
            \() ->
                expectRendered """{"run_id":"x","benchmark":{"best_seconds":0.2,"cpu_nanoseconds_per_display_tick":1000},"work":null}"""
                    (Query.has [ Selector.text "A live rate and a recorded rate are both needed to compare them, and one of the two has not been measured." ])
        , test "a stale snapshot the trainer flags itself is treated as stale, not merely as old" <|
            \() ->
                expectRendered """{"run_id":"x","phase":"training","stale":true}"""
                    (Query.has
                        [ Selector.text "The trainer says it is training, but it has marked this snapshot stale itself. Treat these numbers as historical until it catches up." ]
                    )
        ]

-- RESOURCES
--
-- Once the evaluator can run a pool, three numbers sit beside each other
-- that are all easy to read as each other: the thread count, the duty
-- cycle, and the share of the machine. The duty cycle is a scheduling
-- fraction, identical for one thread and for nine, so nine threads at a
-- full duty cycle is nine threads' worth of capacity and not "one core",
-- and it is not a CPU measurement in either case. Every test below pins
-- one of those misreadings shut.


resourcePool : Api.Resources
resourcePool =
    { workers = 9
    , dutyCycle = 1.0
    , measuredDuty = Just 0.97
    , computeSeconds = 4200.5
    , episodeTicks = Just 1200
    , nice = 10
    }


resourceLegacy : Api.Resources
resourceLegacy =
    { workers = 1
    , dutyCycle = 0.5
    , measuredDuty = Just 0.355
    , computeSeconds = 72.58
    , episodeTicks = Just 1200
    , nice = 10
    }


resourceSuite : Test
resourceSuite =
    describe "resource caps"
        [ describe "decoding"
            [ test "the measured duty cycle decodes beside the configured cap rather than replacing it" <|
                \() ->
                    case decode """{"resources":{"workers":9,"duty_cycle":1.0,"measured_duty":0.97}}""" of
                        Ok status ->
                            Expect.equal
                                ( status.resources.workers, status.resources.dutyCycle, status.resources.measuredDuty )
                                ( 9, 1.0, Just 0.97 )

                        Err error ->
                            Expect.fail error
            , test "an unmeasured duty cycle stays Nothing rather than becoming a measured zero" <|
                \() ->
                    Expect.equal
                        ( decode """{"resources":{"workers":9,"duty_cycle":1.0}}""" |> Result.map (.resources >> .measuredDuty)
                        , decode """{"resources":{"measured_duty":null}}""" |> Result.map (.resources >> .measuredDuty)
                        )
                        ( Ok Nothing, Ok Nothing )
            , test "a run from before the pool existed still reports its single thread" <|
                \() ->
                    decode """{"resources":{"workers":1,"duty_cycle":0.5}}"""
                        |> Result.map (.resources >> .workers)
                        |> Expect.equal (Ok 1)
            ]
        , describe "wording"
            [ test "a pool is counted as threads in a pool, and one thread is not called a pool" <|
                \() ->
                    Expect.equal
                        ( Resources.threadsLine resourcePool, Resources.threadsLine resourceLegacy )
                        ( "9 in the evaluator pool", "1, evaluated inline" )
            , test "an unreported thread count is absent rather than zero threads" <|
                \() ->
                    Resources.threadsLine Api.empty.resources
                        |> Expect.equal "not reported"
            , test "the duty line separates the cap from what was measured" <|
                \() ->
                    Resources.dutyLine resourceLegacy
                        |> Expect.equal "50.0% cap, 35.5% measured working"
            , test "an unmeasured duty cycle says so rather than reporting the cap as a measurement" <|
                \() ->
                    Resources.dutyLine { resourceLegacy | measuredDuty = Nothing }
                        |> Expect.equal "50.0% cap, not yet measured"
            , test "nine threads at a full duty cycle is nine cores of capacity, never one" <|
                \() ->
                    Expect.equal
                        ( Resources.budgetLine resourcePool, Resources.budgetLine resourceLegacy )
                        ( Just "9.0 cores allowed, not measured load", Just "0.5 cores allowed, not measured load" )
            , test "the budget is absent when either factor is unreported, rather than claiming no cores" <|
                \() ->
                    Expect.equal
                        ( Resources.budgetLine Api.empty.resources
                        , Resources.budgetLine { resourcePool | dutyCycle = 0 }
                        )
                        ( Nothing, Nothing )
            , test "no resource line claims to have measured the machine's CPU" <|
                \() ->
                    [ Resources.threadsLine resourcePool
                    , Resources.dutyLine resourcePool
                    , Maybe.withDefault "" (Resources.budgetLine resourcePool)
                    ]
                        |> List.filter (\line -> String.contains "cpu" (String.toLower line))
                        |> Expect.equal []
            ]
        , describe "tooltips"
            [ test "the thread tip no longer promises the trainer occupies about one core" <|
                \() ->
                    [ Copy.resourcesWorkers, Copy.resourcesDuty, Copy.resourcesBudget ]
                        |> List.filter (\tip -> String.contains "one core" (String.toLower tip.body))
                        |> List.map .id
                        |> Expect.equal []
            , test "the duty tip says a full duty cycle is not a full pool of busy threads" <|
                \() ->
                    Copy.resourcesDuty.body
                        |> String.contains "only one thread of the pool busy"
                        |> Expect.equal True
            , test "the duty tip states the run-long window rather than claiming recent batches" <|
                \() ->
                    -- The engine accumulates working and elapsed time across
                    -- resumes, so the figure carries hours recorded under an
                    -- earlier cap. Calling the window "recent batches" would
                    -- make a run raised from half duty to full look as though
                    -- it were failing to use the cap it was just given.
                    Expect.equal
                        ( List.filter (\( key, _ ) -> key == "Window") Copy.resourcesDuty.meta
                            |> List.map Tuple.second
                        , String.contains "accumulates over the whole run" Copy.resourcesDuty.body
                        )
                        ( [ "Accumulated run history, including earlier sessions and earlier resource settings." ], True )
            , test "the budget tip calls itself a ceiling rather than a measurement" <|
                \() ->
                    Expect.equal
                        ( String.contains "ceiling" Copy.resourcesBudget.body
                        , String.contains "never a measurement" Copy.resourcesBudget.body
                        )
                        ( True, True )
            , test "the thread tip says the count changes speed and not what the run finds" <|
                \() ->
                    Copy.resourcesWorkers.body
                        |> String.contains "never what it finds"
                        |> Expect.equal True
            ]
        , describe "on screen"
            [ test "a nine-thread run shows the pool, both duty figures and the capacity" <|
                \() ->
                    expectRendered """{"run_id":"mario-ratio-staged-20260912","resources":{"workers":9,"duty_cycle":1.0,"measured_duty":0.97,"episode_ticks":1200}}"""
                        (Expect.all
                            [ Query.has [ Selector.text "9 in the evaluator pool" ]
                            , Query.has [ Selector.text "100.0% cap, 97.0% measured working" ]
                            , Query.has [ Selector.text "Compute budget" ]
                            , Query.has [ Selector.text "9.0 cores allowed, not measured load" ]
                            ]
                        )
            , test "a legacy single-threaded run renders without a pool or an invented measurement" <|
                \() ->
                    expectRendered """{"run_id":"mario-ratio-staged-20260912","resources":{"workers":1,"duty_cycle":0.5,"episode_ticks":1200}}"""
                        (Expect.all
                            [ Query.has [ Selector.text "1, evaluated inline" ]
                            , Query.has [ Selector.text "50.0% cap, not yet measured" ]
                            , Query.hasNot [ Selector.text "9 in the evaluator pool" ]
                            ]
                        )
            , test "a run that reports no resources at all shows no compute budget row" <|
                \() ->
                    expectRendered """{"run_id":"mario-main-20260911"}"""
                        (Query.hasNot [ Selector.text "Compute budget" ])
            ]
        ]

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


{-| The run the operator actually launched: ranked on the crew ratio,
gated on strict crew leads, with the no-damage penalty armed.
-}
crewLeadPayload : String
crewLeadPayload =
    """
{
  "schema_version": 4,
  "run_id": "mario-ratio-20260912",
  "episodes": 400,
  "episodes_unresolved": 240,
  "episodes_combat_wins": 37,
  "history": [
    {"generation": 0, "training_win_rate": 0.4, "validation_win_rate": 0.55, "species": 3, "nodes": 70, "episodes": 1200},
    {"generation": 1, "training_win_rate": 0.6, "validation_win_rate": 0.72, "species": 4, "nodes": 71, "episodes": 2400}
  ],
  "resources": {"workers": 8, "duty_cycle": 0.5, "episode_ticks": 1200, "nice": 10},
  "board": {"total_matchups": 625},
  "champion": {"id": "g-1", "nodes": 184, "connections": 314, "hidden_nodes": 114},
  "readiness": {"threshold": 0.85, "games": 250, "last_rate": 0.9, "period": 5},
  "overall": {"target": 0.8, "panel": 40, "pairs": 20, "round": "audit",
    "wins": 36, "games": 40, "win_rate": 0.9, "lower_bound": 0.82,
    "champion_id": "g-1", "passed": false, "passed_by": null,
    "audit": {"wins": 36, "games": 40, "win_rate": 0.9, "lower_bound": 0.82, "passed": true},
    "confirm": {"wins": 0, "games": 0, "win_rate": null, "lower_bound": null, "passed": false},
    "attempt": 1},
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
                        [ Query.has [ Selector.text "Overall balanced crew-lead rate" ]
                        , Query.has [ Selector.text "Crew leads needed" ]
                        , Query.has [ Selector.text "crew leads over 40 predeclared games, 20 pairs in both seats" ]
                        , Query.has [ Selector.text "raw crew-lead rate" ]
                        , Query.hasNot [ Selector.text "Overall balanced win rate" ]
                        , Query.hasNot [ Selector.text "Wins needed" ]
                        , Query.hasNot [ Selector.text "wins over 40 predeclared games, 20 pairs in both seats" ]
                        ]
                    )
        , test "an archived run keeps every word the original gate earned" <|
            \() ->
                expectRendered crewRatioPayload
                    (Expect.all
                        [ Query.has [ Selector.text "Overall balanced win rate" ]
                        , Query.hasNot [ Selector.text "Overall balanced crew-lead rate" ]
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
        [ test "the counter is read as the run's own total, whatever the gate counts" <|
            \() ->
                case decode crewLeadPayload of
                    Ok status ->
                        Expect.equal status.episodesCombatWins (Just 37)

                    Err error ->
                        Expect.fail error
        , test "a run that publishes no counter shows none rather than a zero it never measured" <|
            \() ->
                case decode """{"run_id":"mario-main-20260911"}""" of
                    Ok status ->
                        Expect.equal
                            ( status.episodesCombatWins
                            , Scoring.combatVictoriesValue status.episodesCombatWins
                            )
                            ( Nothing, Nothing )

                    Err error ->
                        Expect.fail error
        , test "the note says the whole run, because there is no partial window left to caveat" <|
            \() ->
                Scoring.combatVictoriesNote (Just 37)
                    |> Expect.equal "resolved victories, whole run, all episodes"
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
  "run_id": "mario-ratio-20260912",
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
    {"generation": 0, "training_win_rate": 0.4, "validation_win_rate": 0.55, "species": 3, "nodes": 70, "episodes": 1200}
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
