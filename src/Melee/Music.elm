module Melee.Music exposing (ditty, duration)

import Dict
import Melee.Catalog as Catalog
import Melee.Ship exposing (ShipKind)


folder : ShipKind -> String
folder ship =
    String.split "/" (Catalog.info ship).sprite |> List.drop 2 |> List.head |> Maybe.withDefault "human"


ditty : ShipKind -> String
ditty ship =
    "/music/" ++ folder ship ++ ".m4a"


duration : ShipKind -> Int
duration ship =
    Dict.get (folder ship) durations |> Maybe.withDefault 180


durations : Dict.Dict String Int
durations =
    Dict.fromList
        [ ( "androsynth", 261 ), ( "arilou", 179 ), ( "chenjesu", 119 ), ( "chmmr", 250 ), ( "druuge", 215 ), ( "human", 168 ), ( "ilwrath", 276 ), ( "kohrah", 316 ), ( "melnorme", 180 ), ( "mmrnmhrm", 204 ), ( "mycon", 222 ), ( "orz", 244 ), ( "pkunk", 194 ), ( "shofixti", 227 ), ( "slylandro", 216 ), ( "spathi", 189 ), ( "supox", 149 ), ( "syreen", 222 ), ( "thraddash", 126 ), ( "umgah", 194 ), ( "urquan", 285 ), ( "utwig", 336 ), ( "vux", 230 ), ( "yehat", 136 ), ( "zoqfotpik", 287 ) ]
