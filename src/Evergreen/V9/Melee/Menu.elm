module Evergreen.V9.Melee.Menu exposing (..)


type alias Target =
    { id : String
    , label : String
    , x : Float
    , y : Float
    }


type Event
    = Click String
    | Key String String Bool (List Target)
    | Ignored
