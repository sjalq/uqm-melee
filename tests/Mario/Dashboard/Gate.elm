module Mario.Dashboard.Gate exposing
    ( Blockers
    , Verdict(..)
    , analyse
    , championVerdict
    , explain
    , missingReverseSeats
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

import Mario.Dashboard.Api as Api exposing (Champion, Matchup, MatchupStatus(..))
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
learning, then cells never played.
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
            , ( b.learning, "still training, with no audit evidence yet" )
            , ( b.unseen, "never played" )
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
