module Neat.PolicyTests exposing (suite)

import Array
import Expect
import Fuzz exposing (Fuzzer)
import Melee.Input as Input exposing (Turn(..))
import Melee.Ship exposing (ShipKind(..))
import Neat.Encode as Encode
import Neat.Policy as Policy
import Test exposing (..)


suite : Test
suite =
    describe "Neat recurrent policy step"
        [ test "weightCount is hidden*nIn plus out*(hidden+1)" <|
            \() ->
                Expect.all
                    [ \_ -> Expect.equal Policy.nFeedback (Policy.nControls + Policy.nExtra)
                    , \_ -> Expect.equal Policy.nOut (Policy.nControls + Policy.nExtra)
                    , \_ -> Expect.equal Policy.nIn (Encode.size + Policy.nFeedback + 1)
                    , \_ -> Expect.equal Policy.w1Count (Policy.nHidden * Policy.nIn)
                    , \_ -> Expect.equal Policy.w2Count (Policy.nOut * (Policy.nHidden + 1))
                    , \_ -> Expect.equal Policy.weightCount (Policy.w1Count + Policy.w2Count)
                    , \_ -> Expect.equal (List.length Policy.zeroFeedback) Policy.nFeedback
                    , \_ -> Expect.equal Encode.size (Encode.combatSize + Encode.kindSize)
                    , \_ -> Expect.equal Encode.kindSize 10
                    , \_ -> Expect.equal (List.length Encode.roster) 25
                    ]
                    ()
        , test "our hull and their hull are 5-bit indices in constructor order" <|
            \() ->
                let
                    bits =
                        Encode.kinds Pkunk Umgah

                    ones =
                        List.indexedMap Tuple.pair bits
                            |> List.filter (\( _, x ) -> x == 1)
                            |> List.map Tuple.first
                in
                Expect.all
                    [ \_ -> Expect.equal (List.length bits) 10
                    , \_ -> Expect.equal (List.sum bits) 5
                    , \_ -> Expect.equal ones [ 2, 3, 5, 6, 9 ]
                    ]
                    ()
        , test "first-step feedback is zeros" <|
            \() ->
                Policy.zeroFeedback
                    |> List.all (\x -> x == 0)
                    |> Expect.equal True
        , test "load rejects the wrong width" <|
            \() ->
                Expect.all
                    [ \_ -> Expect.equal Nothing (Policy.load [])
                    , \_ -> Expect.equal Nothing (Policy.load (List.repeat 170 0))
                    , \_ -> Expect.equal Nothing (Policy.load (List.repeat 1261 0))
                    , \_ ->
                        Policy.load (List.repeat Policy.weightCount 0)
                            |> Maybe.map (\n -> Array.length n.hidden)
                            |> Expect.equal (Just Policy.nHidden)
                    , \_ ->
                        Policy.load (List.repeat Policy.weightCount 0)
                            |> Maybe.andThen (\n -> Array.get 0 n.hidden)
                            |> Maybe.map Array.length
                            |> Expect.equal (Just Policy.nIn)
                    , \_ ->
                        Policy.load (List.repeat Policy.weightCount 0)
                            |> Maybe.andThen (\n -> Array.get 0 n.out)
                            |> Maybe.map Array.length
                            |> Expect.equal (Just (Policy.nHidden + 1))
                    ]
                    ()
        , test "idle oldInput encodes as zero action bits" <|
            \() ->
                Expect.equal (Policy.actionsFrom Input.idle) (List.repeat Policy.nControls 0)
        , test "extra outputs are not mapped onto BattleInput on the same step" <|
            \() ->
                let
                    zeros =
                        List.repeat Policy.weightCount 0

                    extrasHot =
                        List.indexedMap
                            (\i w ->
                                if i >= Policy.w1Count + Policy.nControls * (Policy.nHidden + 1) then
                                    w + 8

                                else
                                    w
                            )
                            zeros

                    obs =
                        List.repeat Encode.size 0.25
                in
                case ( Policy.load zeros, Policy.load extrasHot ) of
                    ( Just a, Just b ) ->
                        let
                            sa =
                                Policy.step a obs Policy.zeroFeedback

                            sb =
                                Policy.step b obs Policy.zeroFeedback
                        in
                        Expect.all
                            [ \_ -> Expect.equal sa.input sb.input
                            , \_ -> Expect.equal (List.length sa.extra) Policy.nExtra
                            , \_ -> Expect.equal (List.length sb.extra) Policy.nExtra
                            , \_ -> Expect.notEqual sa.extra sb.extra
                            ]
                            ()

                    _ ->
                        Expect.fail "load"
        , test "previous actions plus extras change the next outputs" <|
            \() ->
                case Policy.load crafted of
                    Nothing ->
                        Expect.fail "crafted width"

                    Just weights ->
                        let
                            obs =
                                List.repeat Encode.size 0

                            first =
                                Policy.step weights obs Policy.zeroFeedback

                            second =
                                Policy.step weights obs first.feedback

                            againZero =
                                Policy.step weights obs Policy.zeroFeedback
                        in
                        Expect.all
                            [ \_ -> Expect.equal first.input.turn TurnLeft
                            , \_ -> Expect.equal first.input.thrust False
                            , \_ -> Expect.equal againZero.input first.input
                            , \_ -> Expect.equal second.input.turn TurnLeft
                            , \_ -> Expect.equal second.input.thrust True
                            , \_ -> Expect.equal (List.length first.feedback) Policy.nFeedback
                            , \_ -> Expect.notEqual first.feedback Policy.zeroFeedback
                            ]
                            ()
        , fuzz stepCase "identical weights, obs, and feedback are deterministic" <|
            \{ weights, obs, feedback } ->
                case Policy.load weights of
                    Nothing ->
                        Expect.fail "width"

                    Just w ->
                        let
                            a =
                                Policy.step w obs feedback

                            b =
                                Policy.step w obs feedback
                        in
                        Expect.all
                            [ \_ -> Expect.equal a.input b.input
                            , \_ -> Expect.equal a.extra b.extra
                            , \_ -> Expect.equal a.feedback b.feedback
                            , \_ -> Expect.equal (List.length a.extra) Policy.nExtra
                            , \_ -> Expect.equal (List.length a.feedback) Policy.nFeedback
                            ]
                            ()
        ]


crafted : List Float
crafted =
    let
        -- Hidden 0 stuck on via input bias. Output turn-L reads hidden 0.
        -- Hidden 1 reads previous left-action. Output thrust reads hidden 1.
        hidN =
            Policy.nHidden + 1

        leftHidBias =
            0 * Policy.nIn + (Policy.nIn - 1)

        leftOut =
            Policy.w1Count + 0 * hidN + 0

        thrustHidFb =
            1 * Policy.nIn + Encode.size

        thrustOut =
            Policy.w1Count + 2 * hidN + 1
    in
    List.indexedMap
        (\i _ ->
            if i == leftHidBias then
                8

            else if i == leftOut then
                8

            else if i == thrustHidFb then
                8

            else if i == thrustOut then
                8

            else
                0
        )
        (List.repeat Policy.weightCount 0)


stepCase : Fuzzer { weights : List Float, obs : List Float, feedback : List Float }
stepCase =
    Fuzz.map3
        (\weights obs feedback -> { weights = weights, obs = obs, feedback = feedback })
        (Fuzz.listOfLength Policy.weightCount (Fuzz.floatRange -2 2))
        (Fuzz.listOfLength Encode.size (Fuzz.floatRange -1 1))
        (Fuzz.listOfLength Policy.nFeedback (Fuzz.floatRange -1 1))
