module Evergreen.V1.Melee.Input exposing (..)


type CyborgRating
    = StandardCyborg
    | GoodCyborg
    | AwesomeCyborg


type Turn
    = NoTurn
    | TurnLeft
    | TurnRight


type alias BattleInput =
    { turn : Turn
    , thrust : Bool
    , weapon : Bool
    , special : Bool
    }
