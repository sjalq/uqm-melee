port module Oracle.MarioPolicy exposing (main, answer)

{-| Line oriented MarI/O oracle worker.

Each stdin line is one request:

    {"id": <any JSON value, optional, echoed back>,
     "genome": {"schema_version":1,"nodes":[...],"genes":[...]},
     "steps": [{"observations":[43 floats],
                "previous":[5 floats],
                "memory":[8 floats]}, ...]}

Stdout carries ONE LINE PER STEP, in order, exactly as `melee-mario` does:

    {"outputs": [13 floats]}

A request that is rejected emits a single line instead of that request's step
lines, and reading continues with the next request:

    {"error": "..."}

A request with no steps therefore emits nothing at all.

The genome is compiled once per request and the graph's recurrent state carries
across the steps of that request, starting from zero. The explicit control and
memory feedback is never carried: every step states its own, which is what makes
the trace reproducible from the request alone.

Step vector lengths are checked exactly rather than padded, and every request is
validated in full before any line is written, so a slot layout disagreement with
the Rust port surfaces as an error rather than a silent zero fill or a half
written answer.

This worker needs no trainer artifacts. Build and run it with:

    lamdera make tests/Oracle/MarioPolicy.elm --output=artifacts/oracle/mario-oracle.js
    node scripts/oracle/mario-eval.js < requests.ndjson

-}

import Json.Decode as D
import Json.Encode as E
import Mario.Genome as Genome exposing (Genome, Step)
import Platform


port request : (String -> msg) -> Sub msg


port response : List String -> Cmd msg


main : Program () () String
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = \line _ -> ( (), response (answer line) )
        , subscriptions = \_ -> request identity
        }


{-| Pure request to response lines, exposed so tests can exercise the wire
contract without ports.
-}
answer : String -> List String
answer line =
    case D.decodeString requestDecoder line of
        Err err ->
            [ failure (D.errorToString err) ]

        Ok (Err defect) ->
            [ failure defect ]

        Ok (Ok job) ->
            Genome.activateAll (Genome.compile job.genome) job.steps
                |> List.map (\outputs -> E.encode 0 (E.object [ ( "outputs", E.list E.float outputs ) ]))


failure : String -> String
failure message =
    E.encode 0 (E.object [ ( "error", E.string message ) ])


type alias Job =
    { genome : Genome
    , steps : List Step
    }


{-| The outer decoder fails only on malformed JSON. A well formed request that
breaks the genome or step contract decodes to Err with a readable reason.
-}
requestDecoder : D.Decoder (Result String Job)
requestDecoder =
    D.map2 assemble
        (D.field "genome" Genome.decoder)
        (D.field "steps" (D.list stepDecoder))


assemble : Result Genome.Error Genome -> List (Result String Step) -> Result String Job
assemble genome steps =
    case ( genome, firstError steps ) of
        ( Err defect, _ ) ->
            Err (Genome.errorToString defect)

        ( _, Just reason ) ->
            Err reason

        ( Ok valid, Nothing ) ->
            Ok { genome = valid, steps = List.filterMap Result.toMaybe steps }


firstError : List (Result String a) -> Maybe String
firstError results =
    case results of
        [] ->
            Nothing

        (Err reason) :: _ ->
            Just reason

        (Ok _) :: rest ->
            firstError rest


stepDecoder : D.Decoder (Result String Step)
stepDecoder =
    D.map3
        (\observations previous memory ->
            Ok Step
                |> field "observations" Genome.observationCount observations
                |> field "previous" Genome.controlCount previous
                |> field "memory" Genome.memoryCount memory
        )
        (D.field "observations" (D.list D.float))
        (D.field "previous" (D.list D.float))
        (D.field "memory" (D.list D.float))


field : String -> Int -> List Float -> Result String (List Float -> a) -> Result String a
field name wanted values acc =
    case acc of
        Err reason ->
            Err reason

        Ok build ->
            if List.length values /= wanted then
                Err
                    ("step field "
                        ++ name
                        ++ " needs exactly "
                        ++ String.fromInt wanted
                        ++ " values, got "
                        ++ String.fromInt (List.length values)
                    )

            else if List.any (\v -> isNaN v || isInfinite v) values then
                Err ("step field " ++ name ++ " contains a non finite value")

            else
                Ok (build values)
