module Melee.Telemetry exposing (..)

import Dict
import Melee.Local as Game
import Melee.Room as Room


type alias Counters =
    { ticks : Int, inputs : Int, deliveries : Int, probes : Int }


zero : Counters
zero =
    { ticks = 0, inputs = 0, deliveries = 0, probes = 0 }


type alias Snapshot =
    { counters : Counters, rooms : Int, battles : Int, spectators : Int, viewers : Int, queued : Int, saved : Int }


snapshot : Counters -> Room.Host -> Snapshot
snapshot counters host =
    { counters = counters
    , rooms = Dict.size host.rooms
    , battles =
        Dict.foldl
            (\_ room n ->
                n
                    + (if Game.phaseArena room.game.phase /= Nothing then
                        1

                       else
                        0
                      )
            )
            0
            host.rooms
    , spectators = Dict.foldl (\_ room n -> n + Dict.size room.spectators) 0 host.rooms
    , viewers = Dict.size host.previewClients
    , queued = List.length host.queue
    , saved = Dict.size host.roomSetups
    }


type alias Rates =
    { ticks : Float, inputs : Float, deliveries : Float, probes : Float }


type alias Client =
    { elapsed : Float
    , frames : Int
    , fps : Maybe Float
    , frameMs : Maybe Float
    , serial : Int
    , pending : Maybe ( Int, Float )
    , age : Int
    , rtt : Maybe Float
    , sample : Maybe Snapshot
    , previous : Maybe ( Float, Counters )
    , rates : Maybe Rates
    }


init : Client
init =
    { elapsed = 0
    , frames = 0
    , fps = Nothing
    , frameMs = Nothing
    , serial = 0
    , pending = Nothing
    , age = 5
    , rtt = Nothing
    , sample = Nothing
    , previous = Nothing
    , rates = Nothing
    }


frame : Float -> Client -> Client
frame delta model =
    if delta <= 0 then
        { model | elapsed = 0, frames = 0, fps = Nothing, frameMs = Nothing }

    else
        let
            elapsed =
                model.elapsed + delta

            frames =
                model.frames + 1
        in
        if elapsed >= 1000 then
            { model | elapsed = 0, frames = 0, fps = Just (1000 * toFloat frames / elapsed), frameMs = Just (elapsed / toFloat frames) }

        else
            { model | elapsed = elapsed, frames = frames }


received : Float -> Maybe Snapshot -> Client -> Client
received now sample model =
    let
        rates =
            case ( model.previous, sample ) of
                ( Just ( before, old ), Just new ) ->
                    if now > before && new.counters.ticks >= old.ticks then
                        let
                            rate a b =
                                toFloat (a - b) * 1000 / (now - before)
                        in
                        Just { ticks = rate new.counters.ticks old.ticks, inputs = rate new.counters.inputs old.inputs, deliveries = rate new.counters.deliveries old.deliveries, probes = rate new.counters.probes old.probes }

                    else
                        Nothing

                _ ->
                    Nothing
    in
    { model
        | pending = Nothing
        , rtt = Maybe.map (\( _, start ) -> max 0 (now - start)) model.pending
        , sample = sample
        , rates = rates
        , previous = Maybe.map (\s -> ( now, s.counters )) sample
    }


{-| Scheduling stays in Elm. Hidden tabs never probe; a missing reply expires
at the next interval. Serial numbers reject delayed responses.
-}
tick : Bool -> Client -> ( Client, Maybe Int )
tick visible model =
    if not visible then
        ( model, Nothing )

    else if model.age >= 4 then
        let
            next =
                { model
                    | serial = model.serial + 1
                    , age = 0
                    , pending = Nothing
                    , rtt =
                        if model.pending /= Nothing then
                            Nothing

                        else
                            model.rtt
                    , sample =
                        if model.pending /= Nothing then
                            Nothing

                        else
                            model.sample
                    , previous =
                        if model.pending /= Nothing then
                            Nothing

                        else
                            model.previous
                    , rates =
                        if model.pending /= Nothing then
                            Nothing

                        else
                            model.rates
                }
        in
        ( next, Just next.serial )

    else
        ( { model | age = model.age + 1 }, Nothing )


reset : Client -> Client
reset model =
    { init | serial = model.serial + 1, sample = model.sample }
