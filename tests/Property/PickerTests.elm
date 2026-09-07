module Property.PickerTests exposing (suite)

import Expect
import Fuzz
import Melee.Input as Input
import Melee.Keys as Keys
import Melee.Picker as Picker
import Test exposing (..)


suite : Test
suite =
    describe "Ship selection and pilot controls"
        [ fuzz2 Fuzz.int Fuzz.int "every constructed selector stays within the original two rows and eight columns" <|
            \row col ->
                let
                    cell =
                        Picker.coordinates (Picker.fromCoordinates row col)
                in
                Expect.equal True (cell.row >= 0 && cell.row < 2 && cell.col >= 0 && cell.col < 8)
        , fuzz2 Fuzz.int Fuzz.int "opposite moves restore the selection" <|
            \row col ->
                let
                    cell =
                        Picker.fromCoordinates row col
                in
                Expect.all
                    [ \_ -> Expect.equal cell (cell |> Picker.move Picker.Left |> Picker.move Picker.Right)
                    , \_ -> Expect.equal cell (cell |> Picker.move Picker.Up |> Picker.move Picker.Down)
                    ]
                    ()
        , test "both human layouts hold thrust independently and release independently" <|
            \() ->
                let
                    both =
                        Keys.none |> Keys.press "ArrowUp" |> Keys.press "w"

                    released =
                        Keys.release "ArrowUp" both
                in
                Expect.equal ( ( True, True ), ( False, True ) )
                    ( ( (Keys.layout Input.KeyLayoutOne both).thrust, (Keys.layout Input.KeyLayoutTwo both).thrust )
                    , ( (Keys.layout Input.KeyLayoutOne released).thrust, (Keys.layout Input.KeyLayoutTwo released).thrust )
                    )
        , test "selection confirms only for the owning keyboard layout" <|
            \() ->
                Expect.equal [ Just Keys.Confirm, Nothing, Just Keys.Confirm, Nothing ]
                    [ Keys.pickKey Input.KeyLayoutOne "Enter"
                    , Keys.pickKey Input.KeyLayoutTwo "Enter"
                    , Keys.pickKey Input.KeyLayoutTwo "j"
                    , Keys.pickKey Input.KeyLayoutOne "j"
                    ]
        ]
