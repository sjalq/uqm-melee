module RPC exposing (lamdera_handleEndpoints)

{-| HTTP RPC for the local-only Jev survival pilot.

Browser posts compact combat state → backend proxies to Vercel AI Gateway
with the dashboard secret → browser polls the token. No ToBackend journal
traffic and no browser-held API keys.
-}

import Dict
import Env
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import LamderaRPC
import Types exposing (BackendModel, BackendMsg(..), PollingStatus(..))


lamdera_handleEndpoints : a -> LamderaRPC.HttpRequest -> BackendModel -> ( LamderaRPC.RPCResult, BackendModel, Cmd BackendMsg )
lamdera_handleEndpoints _ request model =
    case request.endpoint of
        "jev_evaluate" ->
            case request.body of
                LamderaRPC.BodyJson json ->
                    case Decode.decodeValue (Decode.field "state" Decode.string) json of
                        Ok state ->
                            if String.isEmpty (String.trim Env.aiGatewayApiKey) then
                                ( LamderaRPC.ResultJson
                                    (Encode.object
                                        [ ( "error", Encode.string "Jev gateway key not configured (set AI_GATEWAY_API_KEY)" )
                                        ]
                                    )
                                , model
                                , Cmd.none
                                )

                            else if String.length state > 8000 then
                                ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Jev state too large"
                                , model
                                , Cmd.none
                                )

                            else
                                jevStart model state

                        Err _ ->
                            ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Expected { state: string }"
                            , model
                            , Cmd.none
                            )

                _ ->
                    ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Expected JSON body"
                    , model
                    , Cmd.none
                    )

        "jev_poll" ->
            case request.body of
                LamderaRPC.BodyJson json ->
                    case Decode.decodeValue (Decode.field "token" Decode.string) json of
                        Ok token ->
                            case Dict.get token model.pollingJobs of
                                Just Busy ->
                                    ( LamderaRPC.ResultJson (Encode.object [ ( "status", Encode.string "busy" ) ])
                                    , model
                                    , Cmd.none
                                    )

                                Just (BusyWithTime _) ->
                                    ( LamderaRPC.ResultJson (Encode.object [ ( "status", Encode.string "busy" ) ])
                                    , model
                                    , Cmd.none
                                    )

                                Just (Ready (Ok data)) ->
                                    case Decode.decodeString Decode.value data of
                                        Ok value ->
                                            ( LamderaRPC.ResultJson
                                                (Encode.object
                                                    [ ( "status", Encode.string "ready" )
                                                    , ( "data", value )
                                                    ]
                                                )
                                            , { model | pollingJobs = Dict.remove token model.pollingJobs }
                                            , Cmd.none
                                            )

                                        Err _ ->
                                            ( LamderaRPC.ResultJson
                                                (Encode.object
                                                    [ ( "status", Encode.string "error" )
                                                    , ( "error", Encode.string "Malformed gateway payload" )
                                                    ]
                                                )
                                            , { model | pollingJobs = Dict.remove token model.pollingJobs }
                                            , Cmd.none
                                            )

                                Just (Ready (Err err)) ->
                                    ( LamderaRPC.ResultJson
                                        (Encode.object
                                            [ ( "status", Encode.string "error" )
                                            , ( "error", Encode.string err )
                                            ]
                                        )
                                    , { model | pollingJobs = Dict.remove token model.pollingJobs }
                                    , Cmd.none
                                    )

                                Nothing ->
                                    ( LamderaRPC.failWith LamderaRPC.StatusNotFound "Unknown Jev token"
                                    , model
                                    , Cmd.none
                                    )

                        Err _ ->
                            ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Expected { token: string }"
                            , model
                            , Cmd.none
                            )

                _ ->
                    ( LamderaRPC.failWith LamderaRPC.StatusBadRequest "Expected JSON body"
                    , model
                    , Cmd.none
                    )

        _ ->
            ( LamderaRPC.failWith LamderaRPC.StatusNotFound ("Unknown endpoint: " ++ request.endpoint)
            , model
            , Cmd.none
            )


jevStart : BackendModel -> String -> ( LamderaRPC.RPCResult, BackendModel, Cmd BackendMsg )
jevStart model state =
    let
        token =
            "jev-" ++ String.fromInt (Dict.size model.pollingJobs) ++ "-" ++ String.fromInt (String.length state)

        body =
            Encode.object
                [ ( "model", Encode.string "typesafe-ai/jev" )
                , ( "state", Encode.string state )
                , ( "questions"
                  , Encode.object
                        [ ( "survivalButton"
                          , Encode.object
                                [ ( "type", Encode.string "choice" )
                                , ( "instructions"
                                  , Encode.string "Which single control should this pilot press next to survive?"
                                  )
                                , ( "criteria"
                                  , Encode.object
                                        [ ( "idle", Encode.string "Coast / no input; only if truly safe" )
                                        , ( "left", Encode.string "Turn left" )
                                        , ( "right", Encode.string "Turn right" )
                                        , ( "thrust", Encode.string "Thrust forward" )
                                        , ( "fire", Encode.string "Fire primary weapon" )
                                        , ( "special", Encode.string "Use special ability" )
                                        ]
                                  )
                                ]
                          )
                        , ( "danger"
                          , Encode.object
                                [ ( "type", Encode.string "score" )
                                , ( "instructions", Encode.string "How immediate is lethal danger right now" )
                                , ( "criteria"
                                  , Encode.list Encode.string
                                        [ "Safe distance"
                                        , "Caution"
                                        , "Urgent threat"
                                        , "Critical survival"
                                        ]
                                  )
                                ]
                          )
                        ]
                  )
                ]
    in
    ( LamderaRPC.ResultJson
        (Encode.object
            [ ( "token", Encode.string token )
            , ( "status", Encode.string "busy" )
            ]
        )
    , { model | pollingJobs = Dict.insert token Busy model.pollingJobs }
    , Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ Env.aiGatewayApiKey)
            ]
        , url = "https://ai-gateway.vercel.sh/v1/evaluate"
        , body = Http.jsonBody body
        , expect = Http.expectString (JevGatewayResult token)
        , timeout = Just 20000
        , tracker = Nothing
        }
    )
