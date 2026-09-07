module RPC exposing (lamdera_handleEndpoints)

import LamderaRPC
import Types exposing (BackendModel, BackendMsg)


lamdera_handleEndpoints : a -> LamderaRPC.HttpRequest -> BackendModel -> ( LamderaRPC.RPCResult, BackendModel, Cmd BackendMsg )
lamdera_handleEndpoints _ _ model =
    ( LamderaRPC.failWith LamderaRPC.StatusNotFound "Unknown endpoint", model, Cmd.none )
