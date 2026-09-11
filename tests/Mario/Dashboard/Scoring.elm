module Mario.Dashboard.Scoring exposing
    ( explain
    , fightLimit
    , fightSeconds
    , formula
    , gateNote
    , label
    , limitNote
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
                    crewRatioLines caps reported ++ deadline

                Api.Combat ->
                    [ "A win scores one point, the crew margin adds up to 0.20 and a quick finish up to 0.02, so any win outranks any non-win and the margins only order wins among themselves."
                    ]
                        ++ deadline

                Api.UnknownFitness other ->
                    [ "This run reports its scoring rule as \""
                        ++ other
                        ++ "\", which this dashboard does not recognise. It is shown verbatim rather than guessed at, and nothing on this page interprets it."
                    ]
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
                case reported.fitness of
                    Api.Combat ->
                        Nothing

                    Api.CrewRatio _ ->
                        Just
                            ("Breeding ranks on the crew ratio; this gate counts "
                                ++ Api.gateCriterionLabel reported.gate
                                ++ "."
                            )

                    Api.UnknownFitness _ ->
                        Just
                            ("Breeding ranks on \""
                                ++ Api.fitnessLabel reported.fitness
                                ++ "\"; this gate counts "
                                ++ Api.gateCriterionLabel reported.gate
                                ++ "."
                            )
            )
