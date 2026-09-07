port module Ports.MeleeBrowser exposing (receive, send)

import Json.Encode as Encode


port melee_browser_to_js : Encode.Value -> Cmd msg


port melee_browser_from_js : (Encode.Value -> msg) -> Sub msg


send =
    melee_browser_to_js


receive =
    melee_browser_from_js
