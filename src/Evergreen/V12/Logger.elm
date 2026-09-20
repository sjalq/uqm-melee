module Evergreen.V12.Logger exposing (..)


type LogLevel
    = Debug
    | Info
    | Warn
    | Error


type alias LogEntry =
    { index : Int
    , timestamp : Int
    , level : LogLevel
    , message : String
    }


type alias LogState =
    { entries : List LogEntry
    , nextIndex : Int
    , maxEntries : Int
    }


type Msg
    = GotTimestamp Int Int
