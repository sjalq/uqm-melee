module Melee.Audio exposing (effects, music)

import Html exposing (..)
import Html.Attributes as A
import Html.Keyed
import Melee.Local as Game exposing (Phase(..))
import Melee.Music as Music
import Melee.ShipState as ShipState


music : Game.Model -> Html msg
music game =
    let
        ditty arena =
            let
                ship =
                    if Game.crew arena.combatants.bottom arena > 0 then
                        arena.combatants.bottom

                    else
                        arena.combatants.top
            in
            if Game.dittyFrames arena == 0 then
                ""

            else
                Music.ditty (ShipState.kind ship)

        ( source, playing, looping ) =
            case game.phase of
                Combat _ ->
                    ( "/music/battle.m4a", True, True )

                Countdown _ _ ->
                    ( "/music/battle.m4a", True, True )

                Paused _ ->
                    ( "/music/battle.m4a", False, True )

                RoundOver frames arena ->
                    if frames > Game.dittyFrames arena then
                        ( "", False, False )

                    else
                        ( ditty arena, True, False )

                Victory _ ->
                    ( game.survivor |> Maybe.map ditty |> Maybe.withDefault "", True, False )

                _ ->
                    ( "", False, False )

        flag value =
            if value then
                "true"

            else
                "false"
    in
    Html.node "uqm-music" [ A.attribute "src" source, A.attribute "playing" (flag playing), A.attribute "muted" (flag (not game.sound)), A.attribute "loop" (flag looping) ] []


effects : Game.Model -> Html msg
effects game =
    Html.Keyed.node "div"
        [ A.style "display" "none" ]
        (if game.sound then
            List.map (\sound -> ( String.fromInt sound.id, audio [ A.src sound.source, A.autoplay True ] [] )) game.sounds

         else
            []
        )
