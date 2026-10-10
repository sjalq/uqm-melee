module Melee.Seat exposing
    ( Seat(..)
    , all
    , cycle
    , fromParam
    , isHuman
    , label
    , mode
    , ratings
    , toParam
    )

{-| Who flies one side of a local game.

This is the browser's local-play configuration. The shared engine (and every
online room) still speaks `Local.Mode` plus a cyborg rating; `mode` and
`ratings` are the only projections from a seat pair into that vocabulary, so
the two can never disagree. `Jev` exists only here: online rooms have no way
to name it.

-}

import Melee.Input exposing (CyborgRating(..))
import Melee.Local as Game
import Melee.Units exposing (Sided)


type Seat
    = Human
    | Cyborg CyborgRating
    | Jev


{-| Every choice, in the order the original controller button steps through
them (human, then the three cyborg ratings), with Jev appended last.
-}
all : List Seat
all =
    [ Human, Cyborg StandardCyborg, Cyborg GoodCyborg, Cyborg AwesomeCyborg, Jev ]


cycle : Seat -> Seat
cycle seat =
    case seat of
        Human ->
            Cyborg StandardCyborg

        Cyborg StandardCyborg ->
            Cyborg GoodCyborg

        Cyborg GoodCyborg ->
            Cyborg AwesomeCyborg

        Cyborg AwesomeCyborg ->
            Jev

        Jev ->
            Human


isHuman : Seat -> Bool
isHuman seat =
    seat == Human


label : Seat -> String
label seat =
    case seat of
        Human ->
            "Human control"

        Cyborg StandardCyborg ->
            "Standard cyborg"

        Cyborg GoodCyborg ->
            "Good cyborg"

        Cyborg AwesomeCyborg ->
            "Awesome cyborg"

        Jev ->
            "Jev pilot"


toParam : Seat -> String
toParam seat =
    case seat of
        Human ->
            "human"

        Cyborg StandardCyborg ->
            "standard"

        Cyborg GoodCyborg ->
            "good"

        Cyborg AwesomeCyborg ->
            "awesome"

        Jev ->
            "jev"


fromParam : String -> Maybe Seat
fromParam param =
    case param of
        "human" ->
            Just Human

        "standard" ->
            Just (Cyborg StandardCyborg)

        "good" ->
            Just (Cyborg GoodCyborg)

        "awesome" ->
            Just (Cyborg AwesomeCyborg)

        "jev" ->
            Just Jev

        _ ->
            Nothing


{-| Which sides read the keyboard. Jev is a computer seat to the engine; its
buttons arrive through the injected pilot roster instead of the cyborg.
-}
mode : Sided Seat -> Game.Mode
mode seats =
    case ( isHuman seats.bottom, isHuman seats.top ) of
        ( True, True ) ->
            Game.Versus

        ( True, False ) ->
            Game.Solo

        ( False, True ) ->
            Game.ReverseSolo

        ( False, False ) ->
            Game.Demo


{-| Per-side cyborg rating for the engine. Human and Jev sides never consult
it (keyboard and Jev roster respectively), so they carry the default.
-}
ratings : Sided Seat -> Sided CyborgRating
ratings seats =
    let
        rating seat =
            case seat of
                Cyborg value ->
                    value

                _ ->
                    GoodCyborg
    in
    { bottom = rating seats.bottom, top = rating seats.top }
