module Melee.Keys exposing (Held, PickKey(..), inputs, layout, none, pickKey, press, release)

{-| Hot-seat keys. Bottom is layout one, top is layout two. LEFT wins.
-}

import Melee.Input exposing (BattleInput, KeyLayout(..), Turn(..))
import Melee.Picker as Picker
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


layout : KeyLayout -> Held -> BattleInput
layout selected held =
    case selected of
        KeyLayoutOne ->
            (inputs held).bottom

        KeyLayoutTwo ->
            (inputs held).top


type PickKey
    = Move Picker.Direction
    | Confirm
    | Cancel


pickKey : KeyLayout -> String -> Maybe PickKey
pickKey selected key =
    case ( selected, String.toLower key ) of
        ( _, "escape" ) ->
            Just Cancel

        ( KeyLayoutOne, "arrowleft" ) ->
            Just (Move Picker.Left)

        ( KeyLayoutOne, "arrowright" ) ->
            Just (Move Picker.Right)

        ( KeyLayoutOne, "arrowup" ) ->
            Just (Move Picker.Up)

        ( KeyLayoutOne, "arrowdown" ) ->
            Just (Move Picker.Down)

        ( KeyLayoutOne, "enter" ) ->
            Just Confirm

        ( KeyLayoutTwo, "a" ) ->
            Just (Move Picker.Left)

        ( KeyLayoutTwo, "d" ) ->
            Just (Move Picker.Right)

        ( KeyLayoutTwo, "w" ) ->
            Just (Move Picker.Up)

        ( KeyLayoutTwo, "s" ) ->
            Just (Move Picker.Down)

        ( KeyLayoutTwo, "j" ) ->
            Just Confirm

        _ ->
            Nothing
