module Mario.Dashboard.Gate exposing
    ( Blockers
    , Verdict(..)
    , analyse
    , blindSpots
    , championVerdict
    , explain
    , explainBroad
    , explainBroadBoard
    , explainBroadCells
    , missingReverseSeats
    , overallVerdict
    , seatCoverage
    , weakestFirst
    , wilsonLower
    , winsNeeded
    , z95
    )

{-| Why the curriculum is or is not expanding.

The rule the trainer enforces is per cell: every active ordered matchup
at the current stage must clear the target on fresh audit evidence, in
both seat orientations. An aggregate win rate cannot stand in for that,
because a strong average hides a weak cell. This module derives the
blocking picture straight from the per-cell evidence so the dashboard
can say exactly what is holding a promotion up, rather than showing a
reassuring mean.

Everything here is a pure function of the reported matchups, which makes
it directly testable and keeps the view free of judgement calls.

-}

import Mario.Dashboard.Api as Api exposing (Champion, Matchup, MatchupStatus(..), Overall, Seat(..), ShipPerformance)
import Mario.Dashboard.Format as Format


{-| The standard two-sided 95% normal quantile, which is what a plain
"Wilson lower bound" means unless stated otherwise.
-}
z95 : Float
z95 =
    1.96


{-| Lower end of the Wilson score interval for `wins` out of `games`.

The trainer computes and publishes its own bound, and the dashboard
always displays that published value rather than this one. This exists
for the inverse question below: given a panel size, how many wins does
the gate actually demand?

-}
wilsonLower : Float -> Int -> Int -> Maybe Float
wilsonLower z wins games =
    if games <= 0 then
        Nothing

    else
        let
            n =
                toFloat games

            p =
                toFloat wins / n

            zz =
                z * z

            denominator =
                1 + (zz / n)

            centre =
                p + (zz / (2 * n))

            margin =
                z * sqrt (((p * (1 - p)) + (zz / (4 * n))) / n)
        in
        Just (max 0 ((centre - margin) / denominator))


{-| The smallest number of observed wins on a panel of `games` whose
Wilson lower bound reaches `target`.

This is the number that matters to anyone reading the gate. A target of
80% does not mean "win 80 of 100"; on a panel of 100 it means win 88,
because the bound has to clear 80% rather than the raw rate. Stating
only the target invites the reader to think an 80/100 result passes,
which it does not.

The bound rises monotonically with wins at a fixed panel size, so a scan
upward finds the first qualifying count.

-}
winsNeeded : Float -> Float -> Int -> Maybe Int
winsNeeded z target games =
    if games <= 0 then
        Nothing

    else
        List.range 0 games
            |> List.filter
                (\wins ->
                    case wilsonLower z wins games of
                        Just bound ->
                            bound >= target

                        Nothing ->
                            False
                )
            |> List.head


type alias Blockers =
    { total : Int
    , mastered : Int
    , unseen : Int
    , learning : Int
    , auditing : Int
    , short : Int
    , missingReverse : Int
    }


{-| A cell counts as short when it has been audited, has a bound to
judge, and that bound sits under the target. A cell with games but no
published bound is not called short; it is simply not yet decided.
-}
analyse : Float -> List Matchup -> Blockers
analyse target matchups =
    let
        isShort m =
            case m.lowerBound of
                Just bound ->
                    m.games > 0 && bound < target

                Nothing ->
                    False

        countWhere predicate =
            matchups |> List.filter predicate |> List.length
    in
    { total = List.length matchups
    , mastered = countWhere (\m -> m.status == Mastered)
    , unseen = countWhere (\m -> m.status == Unseen || m.games <= 0)
    , learning = countWhere (\m -> m.status == Learning)
    , auditing = countWhere (\m -> m.status == AuditingCell)
    , short = countWhere isShort
    , missingReverse = List.length (missingReverseSeats matchups)
    }


{-| Ordered pairs whose mirror image is missing even though the mirror
is a shape this stage could hold. Evidence gathered in one seat says
nothing about the other, so a missing mirror is a real hole in the gate.

A pair is only counted when both ships already appear on both sides. At
a stage where our roster and the opponent roster do not overlap, the
mirror of a cell is simply not part of the curriculum yet, and reporting
it would invent a blocker that does not exist.

-}
missingReverseSeats : List Matchup -> List ( String, String )
missingReverseSeats matchups =
    let
        present =
            List.map (\m -> ( m.us, m.them, m.opponentType )) matchups

        ourShips =
            List.map .us matchups

        theirShips =
            List.map .them matchups

        has cell =
            List.member cell present

        mirrorIsInScope m =
            List.member m.them ourShips && List.member m.us theirShips
    in
    matchups
        |> List.filter (\m -> m.us /= m.them)
        |> List.filter mirrorIsInScope
        |> List.filter (\m -> not (has ( m.them, m.us, m.opponentType )))
        |> List.map (\m -> ( m.them, m.us ))


{-| Cells ordered by how badly they block the gate: audited and short
first, weakest bound leading, then cells mid-audit, then cells still
learning, then cells with no audit games.

"No audit games" never means "no play". A cell can carry tens of
thousands of training episodes and still have nothing here, because only
fresh audit episodes count toward the gate. Saying "never played" would
misdescribe that.
-}
weakestFirst : Float -> List Matchup -> List Matchup
weakestFirst target matchups =
    let
        evidence m =
            case m.lowerBound of
                Just bound ->
                    Just bound

                Nothing ->
                    m.winRate

        rank m =
            case ( m.status, evidence m ) of
                ( Mastered, _ ) ->
                    ( 4, 0 )

                ( _, Just bound ) ->
                    if bound < target then
                        ( 0, bound )

                    else
                        ( 3, bound )

                ( AuditingCell, Nothing ) ->
                    ( 1, 0 )

                ( Learning, Nothing ) ->
                    ( 2, 0 )

                ( _, Nothing ) ->
                    ( 3, 0 )
    in
    matchups
        |> List.sortWith
            (\a b ->
                let
                    ( ra, va ) =
                        rank a

                    ( rb, vb ) =
                        rank b
                in
                if ra /= rb then
                    compare ra rb

                else if va /= vb then
                    compare va vb

                else
                    compare ( a.us, a.them ) ( b.us, b.them )
            )


type Verdict
    = NoEvidence
    | Short Float
    | Passing Float
    | RateOnly Float


{-| What the champion's own audit evidence says. A raw rate over the
target without a published bound is reported as exactly that, never as a
pass, because promotion is gated on the bound.
-}
championVerdict : Float -> Champion -> Verdict
championVerdict target champion =
    if champion.validatedGames <= 0 then
        NoEvidence

    else
        case champion.lowerBound of
            Just bound ->
                if bound >= target then
                    Passing bound

                else
                    Short bound

            Nothing ->
                case champion.winRate of
                    Just rate ->
                        RateOnly rate

                    Nothing ->
                        NoEvidence


{-| Plain sentences for the panel. Ordered so the first one is always
the actual answer to "why has the roster not grown".
-}
explain : Float -> Api.Curriculum -> List Matchup -> List String
explain target curriculum matchups =
    let
        b =
            analyse target matchups

        nextText =
            case curriculum.nextSide of
                Api.Complete ->
                    "Both rosters already hold every ship, so there is nothing left to add."

                side ->
                    "Next promotion would " ++ Api.nextSideLabel side ++ shipSuffix curriculum.nextShip ++ "."

        shipSuffix ship =
            case ship of
                Just name ->
                    ", specifically " ++ name

                Nothing ->
                    ""

        blocking =
            b.total - b.mastered

        breakdown =
            [ ( b.short, "audited and short of the target" )
            , ( b.auditing, "mid-audit with the panel not yet spent" )
            , ( b.learning, "still in training" )
            , ( b.unseen, "with no audit games yet" )
            ]
                |> List.filter (\( n, _ ) -> n > 0)
                |> List.map (\( n, label ) -> String.fromInt n ++ " " ++ label)

        seatNote =
            if b.missingReverse > 0 then
                [ String.fromInt b.missingReverse
                    ++ " ordered pairs have no mirror cell, so one seat is unrepresented. Evidence from one seat does not transfer to the other."
                ]

            else
                []
    in
    if b.total == 0 then
        [ "No ordered matchups have been published for this stage yet, so there is nothing to gate on."
        , nextText
        ]

    else if blocking == 0 && b.missingReverse == 0 then
        [ "All "
            ++ String.fromInt b.total
            ++ " active ordered matchups have cleared "
            ++ Format.percent target
            ++ " on fresh audit evidence, in both seats."
        , nextText
        ]

    else
        [ String.fromInt blocking
            ++ " of "
            ++ String.fromInt b.total
            ++ " active ordered matchups have not cleared "
            ++ Format.percent target
            ++ " on fresh audit evidence, so the roster stays as it is."
        , if List.isEmpty breakdown then
            "The remaining cells are awaiting evidence."

          else
            "Of those: " ++ String.join ", " breakdown ++ "."
        ]
            ++ seatNote
            ++ [ nextText ]



-- BROAD MODE
--
-- A broad run is judged on one aggregate figure: the frozen champion's
-- record on a fixed held-out balanced panel, first as an audit round and
-- then again on an independent confirm round. That is a different claim
-- from the per-cell gate above, and the two must never be worded alike.
-- The per-cell evidence stays on the page, but as a diagnostic that
-- exposes blind spots, not as something the run is gated on.


{-| What the overall balanced panel says about the frozen champion.

The same rule as the per-cell verdict applies: a raw rate over the
target with no published bound is reported as exactly that, never as a
pass, because the gate is a floor on the bound.

-}
overallVerdict : Overall -> Verdict
overallVerdict overall =
    if overall.games <= 0 then
        NoEvidence

    else
        case overall.lowerBound of
            Just bound ->
                if bound >= overall.target then
                    Passing bound

                else
                    Short bound

            Nothing ->
                case overall.winRate of
                    Just rate ->
                        RateOnly rate

                    Nothing ->
                        NoEvidence


{-| How many hulls carry evidence in each grouping, and how many are
silent.

The held-out panel is built to represent all 25 of our hulls and all 25
opponent hulls equally, so a hull with no games in a grouping is a
reporting hole worth naming rather than a hull that lost.

`opponent` here counts hulls our champion has faced, not hulls that have
beaten it: both groupings count our champion's own wins.

-}
seatCoverage : List ShipPerformance -> { ours : Int, oursWithGames : Int, opponent : Int, opponentWithGames : Int }
seatCoverage rows =
    let
        inSeat seat =
            List.filter (\r -> r.side == seat) rows
    in
    { ours = List.length (inSeat OurSeat)
    , oursWithGames = List.length (List.filter (\r -> r.games > 0) (inSeat OurSeat))
    , opponent = List.length (inSeat OpponentSeat)
    , opponentWithGames = List.length (List.filter (\r -> r.games > 0) (inSeat OpponentSeat))
    }


{-| Per-hull rows ordered worst first, so the weakest hulls lead.

"Worst" is always worst for our champion, in both groupings: a low
`opponent` row is a hull our champion loses to, not a hull that is
losing.

Hulls with no games sort last rather than first. A hull with nothing
measured is not evidence of weakness, and putting it at the top of a
"weakest" list would assert something the panel has not shown. Where a
bound exists it ranks; where only a raw rate exists that ranks instead,
because a small sample still says more than silence.

-}
blindSpots : List ShipPerformance -> List ShipPerformance
blindSpots rows =
    let
        rank row =
            if row.games <= 0 then
                ( 1, 0 )

            else
                case row.lowerBound of
                    Just bound ->
                        ( 0, bound )

                    Nothing ->
                        case row.winRate of
                            Just rate ->
                                ( 0, rate )

                            Nothing ->
                                ( 1, 0 )
    in
    rows
        |> List.sortWith
            (\a b ->
                let
                    ( ra, va ) =
                        rank a

                    ( rb, vb ) =
                        rank b
                in
                if ra /= rb then
                    compare ra rb

                else if va /= vb then
                    compare va vb

                else
                    compare ( Api.seatLabel a.side, a.ship ) ( Api.seatLabel b.side, b.ship )
            )


{-| Plain sentences for the broad gate panel.

Three things have to come across, and each has its own sentence so none
can be lost in a clause: the distribution the figure was measured on,
that the figure is an aggregate rather than a promise about every
matchup, and that a pass needs two independent rounds.

-}
explainBroad : Api.Curriculum -> Maybe Overall -> List ShipPerformance -> List String
explainBroad curriculum maybeOverall ships =
    let
        target =
            case maybeOverall of
                Just overall ->
                    overall.target

                Nothing ->
                    curriculum.target

        scopeLine =
            "The run is judged on one number: the frozen champion's win rate over a fixed held-out balanced panel in which every hull appears equally often on both sides, and every pair is played in both seats. The target is "
                ++ Format.percent target
                ++ " overall."

        aggregateLine =
            "That is an aggregate over the whole distribution. It is not a claim that the champion clears "
                ++ Format.percent target
                ++ " in every matchup, and the per-hull and per-cell figures below exist precisely to show where it does not."

        correlationLine =
            "Each pair is played in both seats, so the outcomes on the panel are correlated rather than independent. Treat the bound as an operational confidence check on this distribution, not as a formal guarantee over every matchup."

        roundLine =
            case maybeOverall of
                Nothing ->
                    "No overall panel result has been published yet, so the gate cannot be judged. That is an absence of evidence, not a score of zero."

                Just overall ->
                    case overall.round of
                        Just Api.AuditRound ->
                            "This is the audit round. A pass here is provisional: the same frozen champion then has to repeat it on an independent confirm panel with its own trial counter before the gate is cleared."

                        Just Api.ConfirmRound ->
                            "This is the independent confirm round, played by the same frozen champion on a separate panel with its own trial counter after the audit round passed."

                        Just (Api.UnknownRound other) ->
                            "The trainer reports the round as \"" ++ other ++ "\", which this dashboard does not recognise. The figures are shown as published."

                        Nothing ->
                            "No gate round is running. These figures are the last published panel result, not a live attempt."

        coverage =
            seatCoverage ships

        coverageLine =
            if List.isEmpty ships then
                []

            else if coverage.oursWithGames < coverage.ours || coverage.opponentWithGames < coverage.opponent then
                [ "Per-hull evidence is incomplete: "
                    ++ String.fromInt coverage.oursWithGames
                    ++ " of "
                    ++ String.fromInt coverage.ours
                    ++ " hulls flying for us and "
                    ++ String.fromInt coverage.opponentWithGames
                    ++ " of "
                    ++ String.fromInt coverage.opponent
                    ++ " hulls it has faced have games on this panel. The rest are unmeasured, which is not the same as losing."
                ]

            else
                [ "Every hull reported carries games in both groupings on this panel." ]

        sourceLine =
            "Both groupings count our champion's own wins: one grouped by the hull it was piloting, the other by the hull it was facing. Neither is the enemy's win count. All of it is this frozen champion's balanced-evaluation evidence only, never an earlier champion's and never adaptive training play."

        readinessSourceLine =
            if List.any (\r -> r.source == Api.FromReadiness) ships then
                [ "The per-hull rows currently come from the cheap balanced readiness probe, not from a gate round. A readiness result decides when an audit is worth spending; it is not audit evidence and nothing is gated on it." ]

            else
                []

        timeoutLine =
            "Every game on the panel counts, including games that time out. Those are counted as non-wins, so the figure cannot be flattered by dropping unresolved fights."

        originLine =
            case curriculum.originRunId of
                Just origin ->
                    [ "The population, weights and RNG state were carried over from "
                        ++ origin
                        ++ (case curriculum.originGeneration of
                                Just generation ->
                                    " at generation " ++ String.fromInt generation

                                Nothing ->
                                    ""
                           )
                        ++ ". No validation evidence came with them: the in-flight panel was abandoned on transition and all gate evidence restarted from nothing."
                    ]

                Nothing ->
                    []

        ladderLine =
            case curriculum.ladder of
                Api.Broad ->
                    []

                other ->
                    [ "The ladder now reads \""
                        ++ Api.ladderLabel other
                        ++ "\", but the run is still judged on the overall balanced result and still carries its broad provenance. It did not revert to per-matchup gating."
                    ]
    in
    [ scopeLine, aggregateLine, correlationLine, roundLine ]
        ++ coverageLine
        ++ [ sourceLine ]
        ++ readinessSourceLine
        ++ [ timeoutLine ]
        ++ originLine
        ++ ladderLine


{-| What the board is, for the panel whose subject is the board.

Kept out of `explainBroad` on purpose. Three panels on this page could
each reasonably say "all 25 ships are active", and when all three did,
the reader got the same eleven paragraphs twice and stopped reading any
of them. Each fact is now stated once, in the panel it belongs to: the
gate panel explains the gate, this explains the board, and the
curriculum panel explains the cells.

-}
explainBroadBoard : Api.Curriculum -> List String
explainBroadBoard curriculum =
    let
        rosterLine =
            "All "
                ++ String.fromInt (List.length curriculum.ourRoster)
                ++ " of our hulls and all "
                ++ String.fromInt (List.length curriculum.opponentRoster)
                ++ " opponent hulls are active at once. Nothing is being unlocked stage by stage, so there is no per-matchup gate to pass and no cell is waiting its turn."

        unlockedLine =
            if curriculum.stageUnlockedExternally then
                [ "Stage "
                    ++ String.fromInt curriculum.stage
                    ++ " was opened by the operator transition, not earned cell by cell. The "
                    ++ String.fromInt curriculum.totalMatchups
                    ++ " cells are active, not mastered, and the mastered count is a diagnostic that gates nothing."
                ]

            else
                []
    in
    rosterLine :: unlockedLine


{-| What the per-cell evidence is for, now that it gates nothing.

The grid and the mastered count are the same numbers a staged run gates
on, so in broad mode they need saying plainly: they are diagnostics, a
weak cell blocks nothing, and an unplayed cell is a hole in what is
known rather than a loss.

-}
explainBroadCells : Api.Curriculum -> List Matchup -> List String
explainBroadCells curriculum matchups =
    let
        b =
            analyse curriculum.target matchups

        counted =
            if b.total == 0 then
                [ "No per-cell evidence has been published for this board yet." ]

            else
                [ String.fromInt b.mastered
                    ++ " of "
                    ++ String.fromInt b.total
                    ++ " cells have cleared "
                    ++ Format.percent curriculum.target
                    ++ " on their own evidence, and "
                    ++ String.fromInt b.unseen
                    ++ " have no gate games at all. In this mode neither number gates anything."
                ]
    in
    counted
        ++ [ "These cells are diagnostics. The run is judged on one overall balanced result, explained in full on the gate panel above, and no cell here can block or unblock it."
           , "A cell with no games is unmeasured, not lost. Its absence says where the aggregate has the least evidence behind it, which is exactly what an overall figure cannot show."
           ]
