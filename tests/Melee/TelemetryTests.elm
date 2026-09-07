module Melee.TelemetryTests exposing (suite)

import Expect
import Fuzz
import Melee.Room as Room
import Melee.Telemetry as Telemetry
import Test exposing (..)


suite : Test
suite =
    describe "Browser telemetry"
        [ test "A visible tab sends one probe per five clock events" <|
            \_ ->
                List.range 1 16
                    |> List.foldl
                        (\_ ( state, count ) ->
                            let
                                ( next, probe ) =
                                    Telemetry.tick True state
                            in
                            ( next
                            , count
                                + (if probe == Nothing then
                                    0

                                   else
                                    1
                                  )
                            )
                        )
                        ( Telemetry.init, 0 )
                    |> Tuple.second
                    |> Expect.equal 4
        , test "Hidden tabs neither probe nor accumulate work" <|
            \_ ->
                Telemetry.tick False Telemetry.init
                    |> Expect.equal ( Telemetry.init, Nothing )
        , test "Missing reply expires stale readings before the next probe" <|
            \_ ->
                let
                    initial =
                        Telemetry.init
                in
                Telemetry.tick True { initial | pending = Just ( 0, 100 ), rtt = Just 20, sample = Just (Telemetry.snapshot Telemetry.zero Room.init) }
                    |> Tuple.first
                    |> (\model -> ( model.rtt, model.sample, model.pending ))
                    |> Expect.equal ( Nothing, Nothing, Nothing )
        , test "Visibility reset invalidates in-flight probe tokens" <|
            \_ ->
                let
                    initial =
                        Telemetry.init
                in
                Telemetry.reset { initial | serial = 4, pending = Just ( 4, 100 ) }
                    |> (\model -> ( model.serial, model.pending, model.previous ))
                    |> Expect.equal ( 5, Nothing, Nothing )
        , fuzz (Fuzz.intRange 10 240) "FPS follows the browser refresh rate without a 60 FPS cap" <|
            \hz ->
                List.repeat (hz * 2) (1000 / toFloat hz)
                    |> List.foldl Telemetry.frame Telemetry.init
                    |> .fps
                    |> Maybe.withDefault 0
                    |> Expect.within (Expect.Absolute 0.01) (toFloat hz)
        , test "A slow visible frame counts toward FPS" <|
            \_ ->
                Telemetry.frame 2000 Telemetry.init
                    |> .fps
                    |> Expect.equal (Just 0.5)
        , test "First frame or invalid interval resets the averaging window" <|
            \_ ->
                Telemetry.init
                    |> Telemetry.frame 16
                    |> Telemetry.frame 0
                    |> .frames
                    |> Expect.equal 0
        , fuzz (Fuzz.floatRange 0 5000) "RTT uses only the two browser clock readings" <|
            \elapsed ->
                let
                    initial =
                        Telemetry.init
                in
                Telemetry.received (10000 + elapsed) Nothing { initial | pending = Just ( 1, 10000 ) }
                    |> .rtt
                    |> Maybe.withDefault -1
                    |> Expect.within (Expect.Absolute 0.00001) elapsed
        , test "Counter rates use elapsed browser time" <|
            \_ ->
                let
                    snapshot =
                        Telemetry.snapshot { ticks = 120, inputs = 50, deliveries = 200, probes = 5 } Room.init

                    initial =
                        Telemetry.init
                in
                Telemetry.received 6000 (Just snapshot) { initial | previous = Just ( 1000, Telemetry.zero ) }
                    |> .rates
                    |> Expect.equal (Just { ticks = 24, inputs = 10, deliveries = 40, probes = 1 })
        , test "Counter reset does not produce negative rates" <|
            \_ ->
                let
                    initial =
                        Telemetry.init
                in
                Telemetry.received 6000 (Just (Telemetry.snapshot Telemetry.zero Room.init)) { initial | previous = Just ( 1000, { ticks = 120, inputs = 50, deliveries = 200, probes = 5 } ) }
                    |> .rates
                    |> Expect.equal Nothing
        ]
