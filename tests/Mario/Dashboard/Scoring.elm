module Mario.Dashboard.Scoring exposing
    ( combatVictoriesNote
    , combatVictoriesValue
    , criterion
    , explain
    , explainGate
    , fightLimit
    , fightSeconds
    , formula
    , gateNote
    , label
    , limitNote
    , nonSuccessPhrase
    , penaltyExplain
    , penaltyLabel
    , penaltyNote
    , rateLabel
    , successHeading
    , successNoun
    , successPlural
    , unresolvedNote
    )

{-| What the trainer is optimising, said in one line and explained in
full behind a tooltip.

The score is the one number on this page that decides which genomes get
to breed, and it is the easiest one to misread. A crew ratio looks like
a percentage, sits next to a pile of real percentages, and is neither a
win rate nor a fraction of maximum health. So every phrase here is
chosen against a specific misreading:

  - a ratio of two shares is not a win percentage,
  - a share is of the crew the ship *started* with, not of its maximum,
    so a ship that takes on crew can legitimately exceed 1.00,
  - the engine's finite stand-in for "divided by nobody" is a reported
    constant, not a measurement, and is shown only when the run reports
    it,
  - the fight length is simulated seconds, not seconds of the machine's
    time, and it is a cut-off for a fight nobody finishes rather than a
    clock every fight runs out,
  - fitness ranks breeding; promotion is judged separately, and the two
    can disagree by design.

Absence is handled once, here: a status with no `scoring` block came
from a build that only ever had the original combat fitness, and that is
what the page says. It never borrows the crew-ratio wording for a run
that never used it.

Everything is a pure function of the reported status, so each claim on
the page is directly testable.

-}

import Mario.Dashboard.Api as Api
import Mario.Dashboard.Format as Format


{-| The ticks-per-second the trainer's episode budget is expressed in.
`episode_ticks` counts display ticks, which is the loop the trainer
steps, so the limit in seconds is that count over this rate.

Those are seconds *inside the simulation*, not seconds of machine time:
the trainer plays a fight far faster than it would be watched, so this
figure says how long the fight lasts to the ships in it, and says
nothing about how long the computer took.

-}
displayHz : Float
displayHz =
    60


{-| The fight's cut-off in simulated seconds, when the run reports its
tick budget. `Nothing` rather than a plausible default: the cut-off is
part of what the score means, so guessing it would misstate the score.
-}
fightSeconds : Api.Resources -> Maybe Float
fightSeconds resources =
    resources.episodeTicks
        |> Maybe.andThen
            (\ticks ->
                if ticks > 0 then
                    Just (toFloat ticks / displayHz)

                else
                    Nothing
            )


{-| The cut-off as a compact label, e.g. "20 s" of simulated time.
-}
fightLimit : Api.Resources -> Maybe String
fightLimit resources =
    fightSeconds resources
        |> Maybe.map
            (\seconds ->
                if seconds == toFloat (round seconds) then
                    Format.decimal 0 seconds ++ " s"

                else
                    Format.decimal 1 seconds ++ " s"
            )


{-| The name of the rule, short enough for a metric tile.
-}
label : Maybe Api.Scoring -> String
label scoring =
    case scoring of
        Nothing ->
            -- Documented meaning of absence, not a guess: the selector is
            -- newer than the runs it can be pointed at.
            Api.fitnessLabel Api.Combat

        Just reported ->
            Api.fitnessLabel reported.fitness


{-| The formula in one line, for the tile under the name.
-}
formula : Maybe Api.Scoring -> String
formula scoring =
    case scoring of
        Nothing ->
            "not reported; a run without the selector has only this rule"

        Just reported ->
            case reported.fitness of
                Api.CrewRatio _ ->
                    "our surviving share \u{00F7} theirs, 1.00 is even"

                Api.Combat ->
                    "a win, then the crew margin, then speed"

                Api.UnknownFitness _ ->
                    "a rule this dashboard does not know, shown as reported"


{-| What the cut-off means for the score, in the few words that fit
under the tile. The time term is the engine's to declare, so an
unreported one is left unsaid rather than assumed either way.
-}
limitNote : Maybe Api.Scoring -> String
limitNote scoring =
    case Maybe.andThen .speedBonus scoring of
        Just False ->
            "simulated, for a fight nobody finishes, and no time bonus"

        Just True ->
            "simulated, for a fight nobody finishes; a quicker win scores higher"

        Nothing ->
            "simulated, for a fight nobody finishes, then scored where it stands"


{-| The full reasoning, attached to the tile's own explanation bubble
rather than printed as a wall of prose next to it.
-}
explain : Maybe Api.Scoring -> Api.Resources -> List String
explain scoring resources =
    let
        -- One line only. The penalty has its own tile and its own full
        -- explanation; repeating that here is the wall of prose this
        -- panel was rewritten to stop printing.
        penaltyLine =
            case Maybe.map .noDamagePenalty scoring of
                Just (Api.PenaltyOf magnitude) ->
                    [ "One condition overrides the rule above: if their crew ends no smaller than it started, fitness is "
                        ++ "\u{2212}"
                        ++ Format.decimal 0 magnitude
                        ++ " instead."
                    ]

                _ ->
                    []

        deadline =
            case fightLimit resources of
                Just limit ->
                    [ "A fight is scored when it ends. One that neither side has finished is cut off at "
                        ++ limit
                        ++ " of simulated time, not of machine time, and scored where it stands."
                    ]

                Nothing ->
                    [ "A fight is scored when it ends, or at a cut-off if neither side has finished. This run does not report that cut-off, so how long a fight may run is unknown." ]
    in
    case scoring of
        Nothing ->
            [ "This run published no scoring block, which means the original combat fitness: the only rule the build that wrote it had. It is not the crew ratio."
            ]
                ++ deadline

        Just reported ->
            case reported.fitness of
                Api.CrewRatio caps ->
                    crewRatioLines caps reported ++ penaltyLine ++ deadline

                Api.Combat ->
                    [ "A win scores one point, the crew margin adds up to 0.20 and a quick finish up to 0.02, so any win outranks any non-win and the margins only order wins among themselves."
                    ]
                        ++ penaltyLine
                        ++ deadline

                Api.UnknownFitness other ->
                    [ "This run reports its scoring rule as \""
                        ++ other
                        ++ "\", which this dashboard does not recognise. It is shown verbatim rather than guessed at, and nothing on this page interprets it."
                    ]
                        ++ penaltyLine
                        ++ deadline


crewRatioLines : { zeroOpponent : Maybe Float, mutualZero : Maybe Float } -> Api.Scoring -> List String
crewRatioLines caps reported =
    [ "Fitness is (our surviving crew \u{00F7} our starting crew) \u{00F7} (their surviving crew \u{00F7} their starting crew), both sides measured as a share of the crew they began with, counted the moment the fight stops."
    , "1.00 means both sides kept the same share of their crew. It is a raw ratio, not a win percentage and not a fraction of maximum health, so it can sit well above 1.00 while the fight itself was never won."
    , "A ship that gains crew during the fight can hold more than its starting complement, so a share above 100% on either side is legitimate rather than a bug."
    , case caps.zeroOpponent of
        Just cap ->
            "Wiping the other side out while any of ours survive scores " ++ Format.decimal 0 cap ++ ", the run's finite stand-in for dividing by nobody."

        Nothing ->
            "Wiping the other side out while any of ours survive scores the run's finite stand-in for dividing by nobody, and this run did not report what that value is."
    , case caps.mutualZero of
        Just even ->
            "Both crews at zero scores " ++ Format.decimal 0 even ++ ": a mutual wipe is even, not a win and not a loss."

        Nothing ->
            "Both crews at zero is treated as even, and this run did not report the value it scores."
    , "Losing our whole crew while any of theirs survive scores 0."
    ]
        ++ (case reported.speedBonus of
                Just False ->
                    [ "There is no time bonus: the same crew ratio scores the same whether the fight ended in two seconds or ran to the cut-off." ]

                Just True ->
                    [ "This run also reports a speed bonus, so a quicker finish scores higher than the same crew ratio reached later." ]

                Nothing ->
                    [ "This run does not report whether a time bonus applies." ]
           )


-- THE CRITERION'S VOCABULARY
--
-- Every tally the trainer publishes under a `wins`-shaped name counts
-- whatever the run's gate criterion counts. Under the original gate that
-- is a win and the old wording was right. Under a crew-lead gate it is
-- not: a fight that runs to the cut-off with both ships intact can be a
-- lead and can never be a win, so any panel still saying "win rate"
-- would be stating something the run never measured.
--
-- The words are therefore derived from the reported criterion in one
-- place, and every panel asks for them rather than spelling them out.
-- Absence resolves to the original gate, which is what a build old
-- enough to omit the block could only have used.


{-| The criterion every counted figure on the page was gathered under.
-}
criterion : Maybe Api.Scoring -> Api.GateCriterion
criterion scoring =
    case scoring of
        Nothing ->
            Api.CombatWins

        Just reported ->
            reported.gate


{-| "win" / "crew lead": one counted success, singular.
-}
successNoun : Maybe Api.Scoring -> String
successNoun scoring =
    Api.gateSuccessNoun (criterion scoring)


{-| "wins" / "crew leads".
-}
successPlural : Maybe Api.Scoring -> String
successPlural scoring =
    Api.gateSuccessPlural (criterion scoring)


{-| "win rate" / "crew-lead rate": what a `wins ÷ games` figure is a rate
of, in the words the run actually earns.
-}
rateLabel : Maybe Api.Scoring -> String
rateLabel scoring =
    case criterion scoring of
        Api.CombatWins ->
            "win rate"

        Api.CrewLead ->
            "crew-lead rate"

        Api.UnknownGate _ ->
            "gate success rate"


{-| The same, capitalised for a heading.
-}
successHeading : Maybe Api.Scoring -> String
successHeading scoring =
    case criterion scoring of
        Api.CombatWins ->
            "Win rate"

        Api.CrewLead ->
            "Crew-lead rate"

        Api.UnknownGate _ ->
            "Gate success rate"


{-| What the audit's spare-game allowance is counted in.

Under the original gate this is a loss, and the page has always called
it one; that wording is kept exactly. Under a crew-lead gate it is not:
a game that fails the gate can be a draw on crew share, or a fight
neither side finished, so calling it a loss would report an outcome that
never happened.

-}
nonSuccessPhrase : Maybe Api.Scoring -> String
nonSuccessPhrase scoring =
    case criterion scoring of
        Api.CombatWins ->
            "losses"

        Api.CrewLead ->
            "non-leads"

        Api.UnknownGate _ ->
            "games that did not count"


{-| What the unresolved count means for this run, which the two criteria
disagree about completely.

Under the original gate an unresolved episode is definitionally not a
win, and that is what the page has always said. Under a crew-lead gate
that sentence is false: an episode nobody finished is exactly the one
the crew comparison was introduced to score, and it counts whenever our
share is ahead.

The count is also not purely a timeout count: an episode can end
unresolved through selection and resurrection as well. So the crew-lead
wording says "unresolved" rather than naming a single cause, and the
unrecognised-criterion wording claims nothing beyond that.

-}
unresolvedNote : Maybe Api.Scoring -> String
unresolvedNote scoring =
    case criterion scoring of
        Api.CombatWins ->
            "timed out, not won"

        Api.CrewLead ->
            "unresolved; crew leads still count"

        Api.UnknownGate _ ->
            "unresolved"



-- THE NO-DAMAGE PENALTY


{-| The penalty as a tile value, or `Nothing` when the run applies none.
-}
penaltyLabel : Maybe Api.Scoring -> Maybe String
penaltyLabel scoring =
    case Maybe.map .noDamagePenalty scoring of
        Just (Api.PenaltyOf magnitude) ->
            Just ("\u{2212}" ++ Format.decimal 0 magnitude)

        _ ->
            Nothing


{-| The line under that tile, said for both states because "off" is a
fact about the run worth reading, not a blank.
-}
penaltyNote : Maybe Api.Scoring -> String
penaltyNote scoring =
    case Maybe.map .noDamagePenalty scoring of
        Just (Api.PenaltyOf _) ->
            "fitness when they end no smaller than they started"

        _ ->
            "no penalty for a fight that costs them nothing"


{-| The full reasoning behind the penalty tile.

Two misreadings are worth heading off explicitly: that the penalty is a
gate (it is not, it moves fitness only), and that it measures damage we
dealt (it does not, it compares their crew at the end against their crew
at the start, so an opponent we hurt and who then recovered counts the
same as one we never touched).

-}
penaltyExplain : Maybe Api.Scoring -> List String
penaltyExplain scoring =
    case Maybe.map .noDamagePenalty scoring of
        Just (Api.PenaltyOf magnitude) ->
            [ "When a fight ends with their crew at or above the number it started with, fitness is not the ordinary score at all: it is replaced by "
                ++ "\u{2212}"
                ++ Format.decimal 0 magnitude
                ++ "."
            , "The condition compares their crew at the end against their crew at the start. It is not a measure of damage we dealt: an opponent we hurt and who then took on replacements counts the same as one we never touched."
            , "The penalty moves fitness only. It changes which genomes breed and nothing about whether the run may move on: the gate is judged separately, on its own evidence."
            ]

        Just Api.PenaltyOff ->
            [ "This run applies no no-damage penalty: a fight that leaves the other side no smaller than it started is scored by the ordinary rule, with nothing subtracted." ]

        Nothing ->
            [ "This run published no scoring block, so it predates the no-damage penalty and applies none. Its fitness is the original combat rule throughout." ]


{-| The factual combat-victory tile's value, and `Nothing` when the run
publishes no such counter or publishes only a partial one whose figure
would be read as a run total.
-}
combatVictoriesValue : Maybe Api.CombatVictories -> Maybe String
combatVictoriesValue victories =
    case victories of
        Just (Api.VictoriesAllTime total) ->
            Just (Format.count total)

        Just (Api.VictoriesSince partial) ->
            Just (Format.count partial.victories)

        Nothing ->
            Nothing


{-| The line under that tile. A partial count carries its baseline in
the line itself, because without it the number reads as a run total the
engine never claimed.
-}
combatVictoriesNote : Maybe Api.CombatVictories -> String
combatVictoriesNote victories =
    case victories of
        Just (Api.VictoriesAllTime _) ->
            "resolved victories, whole run, all episodes"

        Just (Api.VictoriesSince partial) ->
            "resolved victories since episode " ++ Format.count partial.sinceEpisodes

        Nothing ->
            "not counted by this run"


{-| One sentence separating what breeds from what promotes, and only
when the two could be confused.

A run whose fitness is the original combat rule needs no such sentence:
nothing on the page invites the reader to mistake it for something else.
A crew-ratio run does, because the headline gate is still counting
whole wins while the population is being ranked on a ratio.

-}
gateNote : Maybe Api.Scoring -> Maybe String
gateNote scoring =
    scoring
        |> Maybe.andThen
            (\reported ->
                case ( reported.fitness, reported.gate ) of
                    -- The original pairing. Nothing on the page invites
                    -- the reader to mistake either half for the other.
                    ( Api.Combat, Api.CombatWins ) ->
                        Nothing

                    ( fitness, gate ) ->
                        Just
                            ("Breeding ranks on "
                                ++ Api.fitnessLabel fitness
                                ++ "; this gate counts "
                                ++ Api.gateCriterionLabel gate
                                ++ "."
                            )
            )


{-| The gate criterion spelled out, for the gate panel's own tooltip.

The crew-lead case has to say three things the word "rate" hides: what
is being compared, that ties do not count, and that a fight nobody
finished is eligible. The last matters most, because it is the exact
sentence the original gate's copy got right and this gate would get
wrong.

-}
explainGate : Maybe Api.Scoring -> List String
explainGate scoring =
    case criterion scoring of
        Api.CombatWins ->
            [ "This gate counts actual combat wins: fights our champion resolved in its favour. A fight that reaches the cut-off unresolved is not a win and counts against the rate."
            ]

        Api.CrewLead ->
            [ "This gate counts strict crew-share leads, not wins. A game counts when our surviving share of our starting crew is strictly greater than theirs, compared as an exact ratio rather than as rounded percentages."
            , "A fight that reaches the cut-off with both ships still flying is eligible and counts whenever our share is ahead. Every figure gathered under this gate is therefore a count of leads, and none of them is a count of wins."
            , "Ties do not count, including the case where both crews are at zero. A dead heat fails the gate rather than half-passing it."
            ]

        Api.UnknownGate other ->
            [ "This run reports its gate criterion as \""
                ++ other
                ++ "\", which this dashboard does not recognise. The counted figures are shown as published and are not described as wins."
            ]
