module Property.JevTests exposing (suite)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Melee.Input exposing (Turn(..))
import Melee.Jev as Jev
import Test exposing (..)


suite : Test
suite =
    describe "Local Jev survival pilot"
        [ test "button mapping is mutually exclusive" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal { turn = NoTurn, thrust = False, weapon = False, special = False } (Jev.buttonToInput Jev.Idle)
                    , \_ -> Expect.equal { turn = TurnLeft, thrust = False, weapon = False, special = False } (Jev.buttonToInput Jev.Left)
                    , \_ -> Expect.equal { turn = TurnRight, thrust = False, weapon = False, special = False } (Jev.buttonToInput Jev.Right)
                    , \_ -> Expect.equal { turn = NoTurn, thrust = True, weapon = False, special = False } (Jev.buttonToInput Jev.Thrust)
                    , \_ -> Expect.equal { turn = NoTurn, thrust = False, weapon = True, special = False } (Jev.buttonToInput Jev.Fire)
                    , \_ -> Expect.equal { turn = NoTurn, thrust = False, weapon = False, special = True } (Jev.buttonToInput Jev.Special)
                    ]
                    ()
        , test "gateway reply decodes survival button" <|
            \_ ->
                let
                    payload =
                        Encode.object
                            [ ( "answers"
                              , Encode.object
                                    [ ( "survivalButton"
                                      , Encode.object
                                            [ ( "type", Encode.string "choice" )
                                            , ( "choice", Encode.string "thrust" )
                                            , ( "confidence", Encode.float 0.91 )
                                            ]
                                      )
                                    , ( "danger"
                                      , Encode.object
                                            [ ( "type", Encode.string "score" )
                                            , ( "score", Encode.float 2.2 )
                                            ]
                                      )
                                    ]
                              )
                            ]
                in
                case Jev.decodeReply payload of
                    Ok answer ->
                        Expect.all
                            [ \_ -> Expect.equal Jev.Thrust answer.button
                            , \_ -> Expect.equal (Just 0.91) answer.confidence
                            , \_ -> Expect.equal (Just 2.2) answer.danger
                            ]
                            ()

                    Err err ->
                        Expect.fail err
        , test "toggle arms and disarms without leaking pending tokens" <|
            \_ ->
                let
                    on =
                        Jev.toggle Jev.empty

                    pending =
                        Jev.beginRequest 1000 on |> Jev.awaitToken "jev-1"

                    off =
                        Jev.toggle pending
                in
                Expect.all
                    [ \_ -> Expect.equal True on.enabled
                    , \_ -> Expect.equal (Just "jev-1") pending.token
                    , \_ -> Expect.equal False off.enabled
                    , \_ -> Expect.equal Nothing off.token
                    , \_ -> Expect.equal False off.pending
                    ]
                    ()
        , test "request body asks for the survival choice" <|
            \_ ->
                let
                    body =
                        Jev.encodeRequest "NOW: own Earthling crew=12"
                in
                Decode.decodeValue (Decode.at [ "questions", "survivalButton", "type" ] Decode.string) body
                    |> Expect.equal (Ok "choice")
        ]
