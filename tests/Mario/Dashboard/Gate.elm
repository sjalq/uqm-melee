module Mario.Dashboard.Gate exposing
    ( Verdict(..)
    , blindSpots
    , explainOverall
    , nextGateSteps
    , overallVerdict
    , seatCoverage
    , wilsonLower
    , winsNeeded
    , z95
    )

{-| What the one graded question says, and what it would take to answer
it.

The run trains on the whole 625-cell board from generation one and is
judged on a single aggregate: the frozen champion's success rate over a
fixed held-out balanced panel, first as an audit round and then again on
an independent confirm round. There is no per-cell gate, no stage and no
promotion ladder, so nothing here derives a verdict from the per-matchup
rows: those carry training exposure only.

Everything is a pure function of the reported status, which makes it
directly testable and keeps the view free of judgement calls.

-}

import Mario.Dashboard.Api as Api exposing (Overall, Readiness, Seat(..), ShipPerformance)
import Mario.Dashboard.Format as Format
import Mario.Dashboard.Scoring as Scoring


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
        -- The lower limit of a Wilson interval is never above the point
        -- estimate, but at zero wins the centre and the margin are the
        -- same quantity and cancel only to within floating point, which
        -- leaves a bound a few times 10^-18 above an observed rate of
        -- zero. Clamping to the observed rate states the property the
        -- arithmetic already has rather than rounding a real result.
        Just (clamp 0 p ((centre - margin) / denominator))


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


type Verdict
    = NoEvidence
    | Short Float
    | Passing Float
    | RateOnly Float


{-| What the overall balanced panel says about the frozen champion.

A raw rate over the target with no published bound is reported as
exactly that, never as a pass, because the gate is a floor on the bound.

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


{-| Plain sentences for the gate panel.

Four things have to come across, and each has its own sentence so none
can be lost in a clause: the distribution the figure was measured on,
that the figure is an aggregate rather than a promise about every
matchup, that the paired seats make it a confidence check rather than a
guarantee, and that a pass needs two independent rounds.

-}
explainOverall : Maybe Api.Scoring -> Api.Board -> Maybe Overall -> List ShipPerformance -> List String
explainOverall scoring board maybeOverall ships =
    let
        rate =
            Scoring.rateLabel scoring

        target =
            case maybeOverall of
                Just overall ->
                    overall.target

                Nothing ->
                    0.8

        scopeLine =
            "The run is judged on one number: the frozen champion's "
                ++ rate
                ++ " over a fixed held-out balanced panel in which every hull appears equally often on both sides, and every pair is played in both seats. The target is "
                ++ Format.percent target
                ++ " overall."

        boardLine =
            "All "
                ++ Format.count board.totalMatchups
                ++ " ordered matchups are trained on from generation one. Nothing is unlocked a few ships at a time, so no cell has a gate of its own and none is waiting its turn."

        aggregateLine =
            "That is an aggregate over the whole distribution. It is not a claim that the champion clears "
                ++ Format.percent target
                ++ " in every matchup, and the per-hull figures below exist precisely to show where it does not."

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
            "Both groupings count our champion's own "
                ++ Scoring.successPlural scoring
                ++ ": one grouped by the hull it was piloting, the other by the hull it was facing. Neither is the enemy's count. All of it is this frozen champion's balanced-evaluation evidence only, never an earlier champion's and never adaptive training play."

        readinessSourceLine =
            if List.any (\r -> r.source == Api.FromReadiness) ships then
                [ "The per-hull rows currently come from the cheap balanced readiness probe, not from a gate round. A readiness result decides when an audit is worth spending; it is not audit evidence and nothing is gated on it." ]

            else
                []

        timeoutLine =
            case Scoring.criterion scoring of
                Api.CrewLead ->
                    "Every game on the panel counts, including games that end unresolved. Those are scored on crew share like any other, so an unresolved game can count for this gate as readily as a resolved one, and none is dropped."

                _ ->
                    "Every game on the panel counts, including games that time out. Those are counted as non-wins, so the figure cannot be flattered by dropping unresolved fights."

        inheritedLine =
            case maybeOverall of
                Just overall ->
                    case ( overall.passed, overall.passedBy, overall.championId ) of
                        ( False, Just cleared, Just current ) ->
                            if cleared /= current then
                                [ "The target was cleared by champion "
                                    ++ Format.shortId cleared
                                    ++ ", which is no longer the champion. That result belongs to that policy and is not inherited by "
                                    ++ Format.shortId current
                                    ++ "."
                                ]

                            else
                                []

                        _ ->
                            []

                Nothing ->
                    []
    in
    [ scopeLine, boardLine, aggregateLine, correlationLine, roundLine ]
        ++ coverageLine
        ++ [ sourceLine ]
        ++ readinessSourceLine
        ++ [ timeoutLine ]
        ++ inheritedLine


{-| What has to happen for the next gate round to open and to pass, in
order.

This is the "what opens the next gate" answer, and it is deliberately
sequential: a candidate has to clear the cheap screening probe before an
expensive panel is spent on it, then post a count on the audit panel,
then post it again on an independent confirm panel. Stating only the
target percentage hides the first and third steps entirely.

-}
nextGateSteps : Maybe Api.Scoring -> Readiness -> Maybe Overall -> List String
nextGateSteps scoring readiness maybeOverall =
    let
        successes =
            Scoring.successPlural scoring

        probeLine =
            (case readiness.lastRate of
                Just rate ->
                    "The last readiness probe scored " ++ Format.percent1 rate ++ ", "

                Nothing ->
                    "No readiness probe has been scored yet, "
            )
                ++ "against a "
                ++ Format.percent readiness.threshold
                ++ " threshold over "
                ++ String.fromInt readiness.games
                ++ " balanced games"
                ++ (if readiness.period > 0 then
                        ", run every " ++ String.fromInt readiness.period ++ " generations."

                    else
                        "."
                   )

        demandLine overall =
            case winsNeeded z95 overall.target overall.panel of
                Just wins ->
                    "An audit panel is "
                        ++ String.fromInt overall.panel
                        ++ " games, and clearing the "
                        ++ Format.percent overall.target
                        ++ " Wilson lower bound on it takes "
                        ++ String.fromInt wins
                        ++ " observed "
                        ++ successes
                        ++ " ("
                        ++ Format.percent1 (toFloat wins / toFloat overall.panel)
                        ++ "), not "
                        ++ String.fromInt (ceiling (overall.target * toFloat overall.panel))
                        ++ "."

                Nothing ->
                    "No panel size has been published yet, so the observed count the gate demands cannot be stated."

        roundsLine overall =
            case overall.round of
                Just Api.AuditRound ->
                    "The audit round is in flight. Clearing it opens the confirm round, which has to post the same count again on its own panel and its own seeds."

                Just Api.ConfirmRound ->
                    "The confirm round is in flight. It is the last step: clearing it clears the gate for this champion."

                _ ->
                    "Nothing is in flight. The next probe that clears the threshold starts an audit round, and this would be attempt "
                        ++ String.fromInt (overall.attempt + 1)
                        ++ "."
    in
    case maybeOverall of
        Nothing ->
            [ probeLine
            , "The trainer has published no balanced panel yet, so neither the panel size nor the count it demands is known."
            ]

        Just overall ->
            [ probeLine, demandLine overall, roundsLine overall ]
