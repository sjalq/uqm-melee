module Evergreen.V9.Melee.Picker exposing (..)


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


type Cell
    = RandomShip
    | Exit
    | Ship Column Row
