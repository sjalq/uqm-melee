module Neat.Policy exposing
    ( Net
    , Step
    , actionsFrom
    , extraCount
    , feedbackCount
    , load
    , nControls
    , nExtra
    , nFeedback
    , nHidden
    , nIn
    , nOut
    , step
    , w1Count
    , w2Count
    , weightCount
    , zeroExtra
    , zeroFeedback
    )

{-| Two-layer policy: obs + feedback + bias -> tanh hidden -> controls + extras.
-}

import Array exposing (Array)
import Melee.Input exposing (BattleInput, Turn(..), idle)
import Neat.Encode as Encode


nControls : Int
nControls =
    5


nExtra : Int
nExtra =
    8


nFeedback : Int
nFeedback =
    nControls + nExtra


nHidden : Int
nHidden =
    16


nIn : Int
nIn =
    Encode.size + nFeedback + 1


nOut : Int
nOut =
    nControls + nExtra


w1Count : Int
w1Count =
    nHidden * nIn


w2Count : Int
w2Count =
    nOut * (nHidden + 1)


weightCount : Int
weightCount =
    w1Count + w2Count


extraCount : Int
extraCount =
    nExtra


feedbackCount : Int
feedbackCount =
    nFeedback


{-| hidden: nHidden rows of nIn. out: nOut rows of nHidden+1 (hidden acts + bias).
-}
type alias Net =
    { hidden : Array (Array Float)
    , out : Array (Array Float)
    }


type alias Step =
    { input : BattleInput
    , extra : List Float
    , feedback : List Float
    }


zeroExtra : List Float
zeroExtra =
    List.repeat nExtra 0


zeroFeedback : List Float
zeroFeedback =
    List.repeat nFeedback 0


load : List Float -> Maybe Net
load weights =
    if List.length weights == weightCount then
        Just (toNet (Array.fromList weights))

    else
        Nothing


toNet : Array Float -> Net
toNet flat =
    { hidden =
        List.range 0 (nHidden - 1)
            |> List.map (\h -> slice (h * nIn) nIn flat)
            |> Array.fromList
    , out =
        List.range 0 (nOut - 1)
            |> List.map (\o -> slice (w1Count + o * (nHidden + 1)) (nHidden + 1) flat)
            |> Array.fromList
    }


slice : Int -> Int -> Array Float -> Array Float
slice start len flat =
    List.range 0 (len - 1)
        |> List.map (\i -> Array.get (start + i) flat |> Maybe.withDefault 0)
        |> Array.fromList


actionsFrom : BattleInput -> List Float
actionsFrom input =
    [ flag (input.turn == TurnLeft)
    , flag (input.turn == TurnRight)
    , flag input.thrust
    , flag input.weapon
    , flag input.special
    ]


step : Net -> List Float -> List Float -> Step
step net obs feedback =
    let
        inputs =
            Array.fromList (pad Encode.size obs ++ pad nFeedback feedback ++ [ 1 ])

        hiddenActs =
            Array.initialize nHidden
                (\h ->
                    Array.get h net.hidden
                        |> Maybe.withDefault Array.empty
                        |> dot inputs
                        |> tanh_
                )

        hiddenWithBias =
            Array.push 1 hiddenActs

        outs =
            Array.initialize nOut
                (\o ->
                    Array.get o net.out
                        |> Maybe.withDefault Array.empty
                        |> dot hiddenWithBias
                )

        left =
            at outs 0 > 0

        right =
            at outs 1 > 0

        thrust =
            at outs 2 > 0

        weapon =
            at outs 3 > 0

        special =
            at outs 4 > 0

        extra =
            List.range nControls (nOut - 1)
                |> List.map (\i -> tanh_ (at outs i))

        input =
            { idle
                | turn =
                    if left then
                        TurnLeft

                    else if right then
                        TurnRight

                    else
                        NoTurn
                , thrust = thrust
                , weapon = weapon
                , special = special
            }

        actions =
            actionsFrom input
    in
    { input = input
    , extra = extra
    , feedback = actions ++ extra
    }


dot : Array Float -> Array Float -> Float
dot a b =
    dotFrom 0 0 a b


dotFrom : Int -> Float -> Array Float -> Array Float -> Float
dotFrom i acc a b =
    if i >= Array.length a then
        acc

    else
        let
            x =
                Array.get i a |> Maybe.withDefault 0

            y =
                Array.get i b |> Maybe.withDefault 0
        in
        dotFrom (i + 1) (acc + x * y) a b


at : Array Float -> Int -> Float
at xs i =
    Array.get i xs |> Maybe.withDefault 0


pad : Int -> List Float -> List Float
pad n xs =
    List.take n (xs ++ List.repeat n 0)


flag : Bool -> Float
flag b =
    if b then
        1

    else
        0


tanh_ : Float -> Float
tanh_ x =
    if x >= 20 then
        1

    else if x <= -20 then
        -1

    else
        let
            a =
                e ^ x

            b =
                e ^ -x
        in
        (a - b) / (a + b)
