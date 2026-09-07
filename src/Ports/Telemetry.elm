port module Ports.Telemetry exposing (decode, observed, read)

import Json.Decode as Decode
import Json.Encode as Encode


port telemetry_read : ( Int, Bool ) -> Cmd msg


port telemetry_observed : (Encode.Value -> msg) -> Sub msg


read =
    telemetry_read


observed =
    telemetry_observed


decode : Encode.Value -> ( Int, Bool, Float )
decode value =
    Decode.decodeValue (Decode.map3 (\a b c -> ( a, b, c )) (Decode.index 0 Decode.int) (Decode.index 1 Decode.bool) (Decode.index 2 Decode.float)) value
        |> Result.withDefault ( -1, False, 0 )
