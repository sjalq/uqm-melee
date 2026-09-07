module Melee.Keys exposing (Held, inputs, none, press, release)

{-| Hot-seat keys. Bottom is layout one, top is layout two. LEFT wins.
-}

import Melee.Input exposing (BattleInput, Turn(..))
import Melee.Units exposing (Sided)


type alias Held =
    { bottomLeft : Bool
    , bottomRight : Bool
    , bottomThrust : Bool
    , bottomWeapon : Bool
    , bottomSpecial : Bool
    , topLeft : Bool
    , topRight : Bool
    , topThrust : Bool
    , topWeapon : Bool
    , topSpecial : Bool
    }


none : Held
none =
    { bottomLeft = False
    , bottomRight = False
    , bottomThrust = False
    , bottomWeapon = False
    , bottomSpecial = False
    , topLeft = False
    , topRight = False
    , topThrust = False
    , topWeapon = False
    , topSpecial = False
    }


press : String -> Held -> Held
press =
    set True


release : String -> Held -> Held
release =
    set False


set : Bool -> String -> Held -> Held
set down key held =
    case key of
        "ArrowLeft" ->
            { held | bottomLeft = down }

        "ArrowRight" ->
            { held | bottomRight = down }

        "ArrowUp" ->
            { held | bottomThrust = down }

        "Enter" ->
            { held | bottomWeapon = down }

        "Shift" ->
            { held | bottomSpecial = down }

        "a" ->
            { held | topLeft = down }

        "A" ->
            { held | topLeft = down }

        "d" ->
            { held | topRight = down }

        "D" ->
            { held | topRight = down }

        "w" ->
            { held | topThrust = down }

        "W" ->
            { held | topThrust = down }

        "j" ->
            { held | topWeapon = down }

        "J" ->
            { held | topWeapon = down }

        "k" ->
            { held | topSpecial = down }

        "K" ->
            { held | topSpecial = down }

        _ ->
            held


inputs : Held -> Sided BattleInput
inputs held =
    { bottom =
        { turn = turn held.bottomLeft held.bottomRight
        , thrust = held.bottomThrust
        , weapon = held.bottomWeapon
        , special = held.bottomSpecial
        }
    , top =
        { turn = turn held.topLeft held.topRight
        , thrust = held.topThrust
        , weapon = held.topWeapon
        , special = held.topSpecial
        }
    }


turn : Bool -> Bool -> Turn
turn left right =
    if left then
        TurnLeft

    else if right then
        TurnRight

    else
        NoTurn
