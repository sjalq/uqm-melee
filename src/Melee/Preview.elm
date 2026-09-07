module Melee.Preview exposing (Preview(..), apply, view)

import Html exposing (Html, div, text)
import Html.Attributes as A
import Melee.Graphics exposing (Quality(..))
import Melee.Local as Game
import Melee.Rate as Rate
import Melee.Stream as Stream
import Melee.View as View


type Preview
    = Snapshot Game.Model
    | Delta Stream.Delta


apply : Preview -> Maybe Game.Model -> Maybe Game.Model
apply update previous =
    case update of
        Snapshot game ->
            Just game

        Delta delta ->
            Maybe.map
                (\game ->
                    let
                        updated =
                            Stream.apply delta game
                    in
                    { updated | presentationStep = clamp (1000 / toFloat Rate.cBattleFramesPerSecond) 500 delta.interval }
                )
                previous


view : Maybe Game.Model -> Html msg
view preview =
    case preview of
        Nothing ->
            div [ A.class "exhibition-connecting", A.attribute "role" "status" ] [ text "Connecting to the exhibition…" ]

        Just game ->
            case Game.phaseArena game.phase of
                Just arena ->
                    View.viewCockpit HighDefinition game.zoomWidth arena

                Nothing ->
                    div [ A.class "exhibition-connecting", A.attribute "role" "status" ] [ text "Match complete. Next fleets launching…" ]
