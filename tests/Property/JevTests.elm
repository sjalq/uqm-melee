module Property.JevTests exposing (suite)

import Expect
import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Melee.Catalog as Catalog
import Melee.Init as Init
import Melee.Input exposing (Turn(..))
import Melee.Jev as Jev
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Side(..))
import Test exposing (..)


{-| A real `/v1/evaluate` body captured from Vercel AI Gateway for the
four-question request.
-}
gatewayBody : String
gatewayBody =
    """{"model":"typesafe-ai/jev","answers":{"turn":{"type":"choice","choice":"left","probabilities":{"none":0.08,"left":0.88,"right":0.04},"confidence":0.82},"thrust":{"type":"boolean","probability":0.71},"fire":{"type":"boolean","probability":0.54},"special":{"type":"boolean","probability":0.34}},"usage":{"inputTokens":555,"outputTokens":88}}"""


answer : Jev.Answer
answer =
    { turn = TurnLeft, thrust = 0.7, fire = 0.2, special = 0.1, turnConfidence = 0.8 }


ship : Fuzzer ShipKind
ship =
    Fuzz.oneOfValues Catalog.all


side : Fuzzer Side
side =
    Fuzz.oneOfValues [ Bottom, Top ]


suite : Test
suite =
    describe "Local Jev pilot"
        [ test "a real gateway body decodes into all four answers" <|
            \_ ->
                Decode.decodeString Jev.answerDecoder gatewayBody
                    |> Expect.equal (Ok { turn = TurnLeft, thrust = 0.71, fire = 0.54, special = 0.34, turnConfidence = 0.82 })
        , fuzz (Fuzz.triple (Fuzz.floatRange 0 1) (Fuzz.floatRange 0 1) (Fuzz.floatRange 0 1)) "keys are held independently, each at probability one half" <|
            \( thrust, fire, special ) ->
                Jev.answerToInput { answer | thrust = thrust, fire = fire, special = special }
                    |> Expect.equal { turn = TurnLeft, thrust = thrust >= 0.5, weapon = fire >= 0.5, special = special >= 0.5 }
        , fuzz (Fuzz.pair (Fuzz.floatRange 0 5000) (Fuzz.floatRange 1 3000)) "an answer records its round trip and frees the seat to ask again" <|
            \( sentAt, trip ) ->
                let
                    ( id, waiting ) =
                        Jev.sent "top" sentAt Jev.empty

                    done =
                        Jev.landed id (sentAt + trip) answer waiting
                in
                Expect.all
                    [ \_ -> Expect.equal Jev.Idle done.call
                    , \_ -> Expect.equal 1 (List.length done.latency.recent)
                    , \_ -> Maybe.withDefault -1 done.latency.average |> Expect.within (Expect.Absolute 0.001) trip
                    , \_ -> Expect.equal (Jev.answerToInput answer) done.input
                    , \_ -> Expect.equal True (Jev.due (sentAt + trip) done)
                    ]
                    ()
        , test "an answer to a superseded call changes nothing" <|
            \_ ->
                let
                    ( _, waiting ) =
                        Jev.sent "top" 0 Jev.empty
                in
                Jev.landed "top-99" 500 answer waiting |> Expect.equal waiting
        , fuzz (Fuzz.intRange 1 12) "a transient failure backs off, keeps the held keys, then asks again" <|
            \streak ->
                let
                    fail client =
                        let
                            ( id, waiting ) =
                                Jev.sent "bottom" 0 client
                        in
                        Jev.failed (Just id) 0 (Jev.Transient "HTTP 503") waiting

                    blank =
                        Jev.empty

                    held =
                        { blank | input = Jev.answerToInput answer }

                    after =
                        List.foldl (\_ client -> fail client) held (List.range 1 streak)

                    wait =
                        Jev.backoffMs streak
                in
                Expect.all
                    [ \_ -> Expect.equal held.input after.input
                    , \_ -> Expect.equal False (Jev.due (wait - 1) after)
                    , \_ -> Expect.equal True (Jev.due wait after)
                    , \_ -> Expect.atMost 2000 wait
                    ]
                    ()
        , test "a call that never answers is abandoned after the timeout" <|
            \_ ->
                let
                    ( _, waiting ) =
                        Jev.sent "top" 1000 Jev.empty
                in
                Expect.equal ( False, True ) ( Jev.due (1000 + Jev.timeoutMs - 1) waiting, Jev.due (1000 + Jev.timeoutMs) waiting )
        , fuzz (Fuzz.listOfLengthBetween 1 60 (Fuzz.floatRange 50 5000)) "the moving average stays inside the samples and the window stays bounded" <|
            \samples ->
                let
                    latency =
                        List.foldl Jev.noteLatency Jev.empty.latency samples

                    low =
                        List.minimum samples |> Maybe.withDefault 0

                    high =
                        List.maximum samples |> Maybe.withDefault 0
                in
                Expect.all
                    [ \_ -> Expect.equal True (Maybe.map (\avg -> avg >= low - 0.001 && avg <= high + 0.001) latency.average == Just True)
                    , \_ -> Expect.equal (min Jev.latencySamples (List.length samples)) (List.length latency.recent)
                    , \_ -> Expect.equal (List.length samples) latency.answered
                    ]
                    ()
        , fuzz (Fuzz.triple ship ship side) "every matchup describes now, the previous call and three seconds ago within the endpoint's size cap" <|
            \( bottom, top, seat ) ->
                let
                    arena =
                        Init.arena bottom top (Seed 1)

                    past =
                        [] |> Jev.remember 6800 arena |> Jev.remember 9400 arena

                    at path decoder picture =
                        Decode.decodeValue (Decode.at path decoder) picture
                in
                case Jev.state 10000 (Just 480) seat arena past of
                    Just picture ->
                        Expect.all
                            [ \_ -> Expect.atMost 16000 (String.length (Encode.encode 0 picture))
                            , \_ -> at [ "timing", "inputLandsInFrames" ] Decode.int picture |> Expect.equal (Ok 12)
                            , \_ -> at [ "timing", "avgRoundTripMs" ] Decode.int picture |> Expect.equal (Ok 480)
                            , \_ -> at [ "now", "you", "crew" ] Decode.int picture |> Result.map (\crew -> crew > 0) |> Expect.equal (Ok True)
                            , \_ -> at [ "previous", "secondsAgo" ] Decode.float picture |> Expect.equal (Ok 0.6)
                            , \_ -> at [ "threeSecondsAgo", "secondsAgo" ] Decode.float picture |> Expect.equal (Ok 3.2)
                            , \_ -> at [ "threeSecondsAgo", "snapshot", "enemy", "range" ] Decode.int picture |> Result.map (always True) |> Expect.equal (Ok True)
                            , \_ -> at [ "game" ] Decode.string picture |> Result.map (String.contains "Star Control II") |> Expect.equal (Ok True)
                            ]
                            ()

                    Nothing ->
                        Expect.fail "state missing for a fresh arena"
        , fuzz (Fuzz.listOfLengthBetween 0 200 (Fuzz.floatRange 1 900)) "history reaches back past three seconds but never grows with the game" <|
            \gaps ->
                let
                    arena =
                        Init.arena Spathi Chmmr (Seed 1)

                    ( now, past ) =
                        List.foldl (\gap ( t, kept ) -> ( t + gap, Jev.remember (t + gap) arena kept )) ( 0, [] ) gaps
                in
                Expect.all
                    [ \_ -> Expect.atMost 16 (List.length past)
                    , \_ -> Expect.equal True (List.all (\entry -> now - entry.atMs <= 4000) past)
                    ]
                    ()
        , test "the request asks one turn choice and three independent key questions" <|
            \_ ->
                let
                    kind name =
                        Decode.decodeValue (Decode.at [ name, "type" ] Decode.string) Jev.questions
                in
                Expect.equal [ Ok "choice", Ok "boolean", Ok "boolean", Ok "boolean" ] (List.map kind [ "turn", "thrust", "fire", "special" ])
        ]
