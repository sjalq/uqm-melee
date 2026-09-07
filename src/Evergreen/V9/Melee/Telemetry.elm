module Evergreen.V9.Melee.Telemetry exposing (..)


type alias Counters =
    { ticks : Int
    , inputs : Int
    , deliveries : Int
    , probes : Int
    }


type alias Snapshot =
    { counters : Counters
    , rooms : Int
    , battles : Int
    , spectators : Int
    , viewers : Int
    , queued : Int
    , saved : Int
    }


type alias Rates =
    { ticks : Float
    , inputs : Float
    , deliveries : Float
    , probes : Float
    }


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
