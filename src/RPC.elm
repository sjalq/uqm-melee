module RPC exposing (lamdera_handleEndpoints)

{-| HTTP RPC for the local-only Jev pilot.

The browser posts `{ request, state }` for one Jev seat. The backend forwards
it to Vercel AI Gateway with the dashboard secret and returns at once; when
the gateway answers, `Backend` pushes the decoded answer to the asking
session (`JevReply`), so the browser never polls. Only the state is taken
from the browser: model and questions are fixed here, so the endpoint cannot
be used to ask Jev arbitrary questions on our key. `Melee.JevDesk` caps calls
in flight per session and overall.

-}

import Env
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import LamderaRPC
import Melee.Jev as Jev
import Melee.JevDesk as Desk
import Types exposing (BackendModel, BackendMsg(..))


lamdera_handleEndpoints : a -> LamderaRPC.HttpRequest -> BackendModel -> ( LamderaRPC.RPCResult, BackendModel, Cmd BackendMsg )
lamdera_handleEndpoints _ request model =
    case ( request.endpoint, request.body ) of
        ( "jev_evaluate", LamderaRPC.BodyJson json ) ->
            case Decode.decodeValue (Decode.map2 Tuple.pair (Decode.field "request" Decode.string) (Decode.field "state" Decode.value)) json of
                Ok ( requestId, state ) ->
                    evaluate request.sessionId requestId state model

                Err _ ->
                    ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Expected { request: string, state: object }", model, Cmd.none )

        ( "jev_evaluate", _ ) ->
            ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Expected JSON body", model, Cmd.none )

        _ ->
            ( LamderaRPC.failWith LamderaRPC.StatusNotFound ("Unknown endpoint: " ++ request.endpoint), model, Cmd.none )


maxStateChars : Int
maxStateChars =
    16000


{-| Jev answers in well under a second; one still silent after this is
reported as a transient failure and the browser asks again with fresh state.
-}
attemptTimeoutMs : Float
attemptTimeoutMs =
    6000


evaluate : String -> String -> Decode.Value -> BackendModel -> ( LamderaRPC.RPCResult, BackendModel, Cmd BackendMsg )
evaluate session requestId state model =
    if String.isEmpty (String.trim Env.aiGatewayApiKey) then
        ( LamderaRPC.failWith LamderaRPC.StatusServiceUnavailable "Jev gateway key not configured (set AI_GATEWAY_API_KEY)", model, Cmd.none )

    else if String.length requestId > 40 || String.length (Encode.encode 0 state) > maxStateChars then
        ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Jev request too large", model, Cmd.none )

    else
        case Desk.start session requestId model.melee.now model.jevDesk of
            Desk.Started key desk ->
                ( LamderaRPC.ResultJson (Encode.object [ ( "status", Encode.string "sent" ) ])
                , { model | jevDesk = desk }
                , Http.request
                    { method = "POST"
                    , headers = [ Http.header "Authorization" ("Bearer " ++ Env.aiGatewayApiKey) ]
                    , url = "https://ai-gateway.vercel.sh/v1/evaluate"
                    , body =
                        Http.jsonBody
                            (Encode.object
                                [ ( "model", Encode.string "typesafe-ai/jev" )
                                , ( "state", state )
                                , ( "questions", Jev.questions )
                                ]
                            )
                    , expect = Http.expectString (JevGatewayResult key)
                    , timeout = Just attemptTimeoutMs
                    , tracker = Nothing
                    }
                )

            Desk.SessionBusy ->
                ( LamderaRPC.failWith LamderaRPC.StatusTooManyRequests "Jev: this session already has its calls in flight", model, Cmd.none )

            Desk.DeskFull ->
                ( LamderaRPC.failWith LamderaRPC.StatusTooManyRequests "Jev: too many calls in flight", model, Cmd.none )
