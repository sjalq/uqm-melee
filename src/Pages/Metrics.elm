module Pages.Metrics exposing (hud, view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Melee.Telemetry as Telemetry


number : Maybe Float -> String
number =
    Maybe.map (round >> String.fromInt) >> Maybe.withDefault "..."


hud : Telemetry.Client -> Html msg
hud model =
    a
        [ class "telemetry-hud"
        , href "/metrics"
        , target "_blank"
        , rel "noopener"
        , title "Open performance and server workload in a new tab"
        , attribute "aria-label" "Open metrics in a new tab"
        ]
        [ text (number model.fps ++ " FPS · " ++ number model.rtt ++ " ms · METRICS ↗") ]


card : String -> String -> String -> Html msg
card label value detail =
    div [ class "telemetry-card" ]
        [ span [] [ text label ], strong [] [ text value ], small [] [ text detail ] ]


view : Telemetry.Client -> Html msg
view model =
    let
        gauge get =
            model.sample |> Maybe.map (get >> String.fromInt) |> Maybe.withDefault "..."

        rate get =
            model.rates |> Maybe.map (\value -> String.fromFloat (toFloat (round (get value * 10)) / 10)) |> Maybe.withDefault "..."

        total get =
            model.sample |> Maybe.map (.counters >> get >> String.fromInt) |> Maybe.withDefault "..."
    in
    main_ [ class "telemetry-page", id "melee-game", attribute "data-playing" "false" ]
        [ header [ class "telemetry-heading" ]
            [ div [] [ small [] [ text "SUPER MELEE / FLIGHT TELEMETRY" ], h1 [] [ text "Systems monitor" ] ]
            , a [ href "/melee" ] [ text "← Melee" ]
            ]
        , div [ class "telemetry-grid" ]
            [ card "BROWSER FPS" (number model.fps) (number model.frameMs ++ " ms per frame in this tab")
            , card "ROUND TRIP"
                (number model.rtt ++ " ms")
                (if model.rtt == Nothing then
                    "Waiting for echo"

                 else
                    "Measured on this browser's monotonic clock"
                )
            , card "SERVER TICKS / SEC" (rate .ticks) (total .ticks ++ " simulation ticks counted")
            , card "CONTROL MSGS / SEC" (rate .inputs) (total .inputs ++ " player input messages counted")
            , card "GAME DELIVERIES / SEC" (rate .deliveries) (total .deliveries ++ " room messages sent to clients")
            , card "PROBES / SEC" (rate .probes) (total .probes ++ " diagnostic echoes requested")
            , card "LOADED ROOMS" (gauge .rooms) (gauge .battles ++ " with battle arenas")
            , card "SPECTATORS" (gauge .spectators) (gauge .viewers ++ " lobby preview subscribers")
            , card "MATCHMAKING" (gauge .queued) (gauge .saved ++ " saved reusable room setups")
            ]
        , footer []
            [ text "Application workload, not host CPU or memory. One echo every 5 seconds while visible. Rates use browser elapsed time; shared room counts refresh every 120 server ticks. Room deliveries exclude directory broadcasts and auth traffic. Counters persist with server state."
            ]
        ]
