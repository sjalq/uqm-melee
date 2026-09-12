module Mario.Dashboard.Resources exposing (budgetLine, dutyLine, threadsLine)

{-| How the resource cap is said out loud.

Three numbers are easy to confuse once the trainer can run more than one
evaluator thread, and reading either of the first two as the third is the
whole risk:

  - the thread count is how many evaluators the pool actually runs,
  - the duty cycle is the fraction of wall time the scheduler spends
    working rather than resting, which is the same number for one thread
    and for nine,
  - the budget is those two multiplied, which is a ceiling in cores the
    run is allowed to occupy and never a measurement of what it draws.

So "a full duty cycle" must never be allowed to read as "a full machine",
nor as "one core", and nothing here is phrased as measured CPU. Real load
is measured outside the trainer.

-}

import Mario.Dashboard.Api as Api
import Mario.Dashboard.Format as Format


threadsLine : Api.Resources -> String
threadsLine resources =
    if resources.workers <= 0 then
        "not reported"

    else if resources.workers == 1 then
        "1, evaluated inline"

    else
        String.fromInt resources.workers ++ " in the evaluator pool"


dutyLine : Api.Resources -> String
dutyLine resources =
    let
        measured =
            case resources.measuredDuty of
                Just value ->
                    ", " ++ Format.percent1 value ++ " measured working"

                Nothing ->
                    ", not yet measured"
    in
    if resources.dutyCycle > 0 then
        Format.percent1 resources.dutyCycle ++ " cap" ++ measured

    else
        case resources.measuredDuty of
            Just value ->
                Format.percent1 value ++ " measured working, no cap reported"

            Nothing ->
                "not measured"


{-| Absent rather than zero when either factor is unreported: a budget of
no cores would read as a claim about the machine that nobody made.
-}
budgetLine : Api.Resources -> Maybe String
budgetLine resources =
    if resources.workers > 0 && resources.dutyCycle > 0 then
        Just
            (Format.decimal 1 (toFloat resources.workers * resources.dutyCycle)
                ++ " cores allowed, not measured load"
            )

    else
        Nothing
