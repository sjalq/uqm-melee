module Melee.Picker exposing (Cell(..), Column(..), Direction(..), Row(..), columns, coordinates, fromCoordinates, initial, move, rows)


type Cell
    = RandomShip
    | Exit
    | Ship Column Row


type Column
    = A
    | B
    | C
    | D
    | E
    | F
    | G


type Row
    = Upper
    | Lower


type Direction
    = Left
    | Right
    | Up
    | Down


columns : Int
columns =
    7


rows : Int
rows =
    2


initial : Cell
initial =
    RandomShip


coordinates : Cell -> { row : Int, col : Int }
coordinates cell =
    case cell of
        RandomShip ->
            { row = 0, col = columns }

        Exit ->
            { row = 1, col = columns }

        Ship col row ->
            { row =
                if row == Upper then
                    0

                else
                    1
            , col =
                case col of
                    A ->
                        0

                    B ->
                        1

                    C ->
                        2

                    D ->
                        3

                    E ->
                        4

                    F ->
                        5

                    G ->
                        6
            }


fromCoordinates : Int -> Int -> Cell
fromCoordinates row col =
    let
        r =
            if modBy rows row == 0 then
                Upper

            else
                Lower
    in
    case modBy (columns + 1) col of
        0 ->
            Ship A r

        1 ->
            Ship B r

        2 ->
            Ship C r

        3 ->
            Ship D r

        4 ->
            Ship E r

        5 ->
            Ship F r

        6 ->
            Ship G r

        _ ->
            if r == Upper then
                RandomShip

            else
                Exit


move : Direction -> Cell -> Cell
move direction cell =
    let
        at =
            coordinates cell
    in
    case direction of
        Left ->
            fromCoordinates at.row (at.col - 1)

        Right ->
            fromCoordinates at.row (at.col + 1)

        Up ->
            fromCoordinates (at.row - 1) at.col

        Down ->
            fromCoordinates (at.row + 1) at.col
