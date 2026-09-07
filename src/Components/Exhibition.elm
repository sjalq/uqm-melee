module Components.Exhibition exposing (view)

import Html exposing (..)
import Html.Attributes as A
import Html.Events as E
import Melee.Audio as Audio
import Melee.Local as Game
import Melee.Preview as Preview
import Svg
import Svg.Attributes as S


view : { game : Maybe Game.Model, sound : Bool, onToggleSound : msg, onWatch : msg } -> Html msg
view config =
    section [ A.class "exhibition-card", A.attribute "aria-label" "Live exhibition match" ]
        [ div [ A.class "exhibition-preview", A.attribute "data-room" "ARENA" ] [ Preview.view config.game ]
        , config.game |> Maybe.map (\game -> Audio.effects { game | sound = config.sound }) |> Maybe.withDefault (text "")
        , div [ A.class "exhibition-caption" ]
            [ div [] [ span [ A.class "room-badge live-badge" ] [ text "LIVE EXHIBITION" ], h2 [] [ text "The proving ground" ] ]
            , div [ A.class "exhibition-actions" ]
                [ button
                    [ A.id "exhibition-sound"
                    , A.class "classic-button exhibition-sound-toggle"
                    , A.attribute "aria-label"
                        (if config.sound then
                            "Mute sound"

                         else
                            "Enable sound"
                        )
                    , A.attribute "aria-pressed"
                        (if config.sound then
                            "true"

                         else
                            "false"
                        )
                    , E.onClick config.onToggleSound
                    ]
                    [ soundIcon config.sound
                    , span [ A.class "exhibition-sound-label" ]
                        [ text
                            (if config.sound then
                                "Mute sound"

                             else
                                "Enable sound"
                            )
                        ]
                    ]
                , button [ A.class "classic-button", E.onClick config.onWatch ] [ text "Watch larger" ]
                ]
            ]
        ]


soundIcon : Bool -> Html msg
soundIcon enabled =
    Svg.svg [ S.viewBox "0 0 32 32", S.width "32", S.height "32", A.attribute "aria-hidden" "true", S.fill "none", S.stroke "currentColor", S.strokeWidth "2.5", S.strokeLinecap "round", S.strokeLinejoin "round" ]
        [ Svg.path [ S.d "M4 12H10L17 6V26L10 20H4Z" ] []
        , if enabled then
            Svg.path [ S.d "M22 11Q27 16 22 21M26 6Q35 16 26 26" ] []

          else
            Svg.path [ S.d "M23 12L30 20M30 12L23 20" ] []
        ]
