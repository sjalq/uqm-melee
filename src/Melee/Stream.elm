module Melee.Stream exposing (..)

import Dict
import Melee.Battle exposing (Arena)
import Melee.Element exposing (Element)
import Melee.Id exposing (ElementId)
import Melee.Local as Game
import Melee.ShipState exposing (Combatant)
import Melee.Units exposing (FrameCount, Sided)
import Melee.View as View


type Stage
    = Fighting
    | Arriving Int
    | Stopped
    | Aftermath Int


type alias Delta =
    { stage : Stage, frame : FrameCount, combatants : Sided Combatant, changed : List Element, removed : List Int, queue : List ElementId, sounds : List { id : Int, source : String, age : Int }, interval : Float }


stage phase =
    case phase of
        Game.Combat _ ->
            Just Fighting

        Game.Countdown n _ ->
            Just (Arriving n)

        Game.Paused _ ->
            Just Stopped

        Game.RoundOver n _ ->
            Just (Aftermath n)

        _ ->
            Nothing


between : Float -> Game.Model -> Game.Model -> Maybe Delta
between interval before after =
    case ( Game.phaseArena before.phase, Game.phaseArena after.phase, stage after.phase ) of
        ( Just old, Just next, Just phase ) ->
            if before.round /= after.round then
                Nothing

            else
                Just { stage = phase, frame = next.frame, combatants = next.combatants, changed = Dict.filter (\id el -> Dict.get id old.elements /= Just el) next.elements |> Dict.values, removed = Dict.diff old.elements next.elements |> Dict.keys, queue = next.queue, sounds = after.sounds, interval = interval }

        _ ->
            Nothing


apply : Delta -> Game.Model -> Game.Model
apply delta model =
    case Game.phaseArena model.phase of
        Nothing ->
            model

        Just old ->
            let
                elements =
                    List.foldl (\el -> Dict.insert (Melee.Id.toInt el.id) el) (List.foldl Dict.remove old.elements delta.removed) delta.changed

                arena =
                    { old | frame = delta.frame, combatants = delta.combatants, elements = elements, queue = delta.queue, previousLocations = Dict.map (\_ el -> View.displayLocation old el) old.elements, pumpAcc = 0 }

                phase =
                    case delta.stage of
                        Fighting ->
                            Game.Combat arena

                        Arriving n ->
                            Game.Countdown n arena

                        Stopped ->
                            Game.Paused arena

                        Aftermath n ->
                            Game.RoundOver n arena
            in
            { model | phase = phase, sounds = delta.sounds, presentationClock = 0, presentationStep = clamp 40 250 delta.interval }
