module Mario.Dashboard.Slots exposing
    ( Group(..)
    , Slot
    , biasIndex
    , controlNames
    , groupLabel
    , groupOf
    , groups
    , hiddenFirst
    , inputCount
    , memoryChannels
    , observationCount
    , outputCount
    , outputFirst
    , sensorCount
    , shipBits
    , slot
    )

{-| Stable node-id to label mapping for the MarI/O genome.

The trainer, the Elm oracle and this dashboard all agree on one fixed
input assembly. Writing it down once here keeps the topology view
honest: every circle on the left edge is named, and the two 5-bit ship
identity groups and the eight memory channels are separately
identifiable rather than disappearing into an anonymous stack of 57
inputs.

Layout (node ids):

      0 .. 32   33 combat sensors, slot 32 being the constant 1 the
                existing encoder already emits
     33 .. 37   our ship identity, 5 bits, least significant bit first
     38 .. 42   their ship identity, 5 bits, least significant bit first
                (0..42 together are the 43 observations)
     43 .. 47   the five control bits actually applied on the previous
                step: left, right, thrust, weapon, special
     48 .. 55   the eight explicit memory channels emitted on the
                previous step
           56   the extra bias input, always 1
     57 .. 61   control outputs: left, right, thrust, weapon, special
     62 .. 69   memory outputs, channels 0 .. 7
     70 ..      hidden nodes

Sensor names 0..32 mirror the ordering in `Neat.Encode.encode`. If that
encoder ever changes, this table must change with it.

-}


sensorCount : Int
sensorCount =
    33


shipBits : Int
shipBits =
    5


observationCount : Int
observationCount =
    sensorCount + (shipBits * 2)


controlCount : Int
controlCount =
    5


memoryChannels : Int
memoryChannels =
    8


biasIndex : Int
biasIndex =
    observationCount + controlCount + memoryChannels


inputCount : Int
inputCount =
    biasIndex + 1


outputFirst : Int
outputFirst =
    inputCount


outputCount : Int
outputCount =
    controlCount + memoryChannels


hiddenFirst : Int
hiddenFirst =
    outputFirst + outputCount


type Group
    = Sensors
    | OurShipBits
    | TheirShipBits
    | PriorControls
    | PriorMemory
    | Bias
    | ControlOutputs
    | MemoryOutputs
    | Hidden


groups : List Group
groups =
    [ Sensors, OurShipBits, TheirShipBits, PriorControls, PriorMemory, Bias, Hidden, ControlOutputs, MemoryOutputs ]


groupLabel : Group -> String
groupLabel group =
    case group of
        Sensors ->
            "Combat sensors"

        OurShipBits ->
            "Our ship id (5 bits)"

        TheirShipBits ->
            "Their ship id (5 bits)"

        PriorControls ->
            "Previous controls (5)"

        PriorMemory ->
            "Previous memory (8)"

        Bias ->
            "Bias"

        ControlOutputs ->
            "Control outputs (5)"

        MemoryOutputs ->
            "Memory outputs (8)"

        Hidden ->
            "Hidden"


groupOf : Int -> Group
groupOf id =
    if id < 0 then
        Hidden

    else if id < sensorCount then
        Sensors

    else if id < sensorCount + shipBits then
        OurShipBits

    else if id < observationCount then
        TheirShipBits

    else if id < observationCount + controlCount then
        PriorControls

    else if id < biasIndex then
        PriorMemory

    else if id == biasIndex then
        Bias

    else if id < outputFirst + controlCount then
        ControlOutputs

    else if id < hiddenFirst then
        MemoryOutputs

    else
        Hidden


controlNames : List String
controlNames =
    [ "left", "right", "thrust", "weapon", "special" ]


{-| Short display name plus a one-line explanation of what the slot
carries. `short` is what fits next to a node; `detail` is what the
tooltip says.
-}
type alias Slot =
    { id : Int
    , group : Group
    , short : String
    , detail : String
    }


slot : Int -> Slot
slot id =
    let
        group =
            groupOf id
    in
    case group of
        Sensors ->
            let
                ( short, detail ) =
                    sensorInfo id
            in
            Slot id group short detail

        OurShipBits ->
            let
                bit =
                    id - sensorCount
            in
            Slot id
                group
                ("us b" ++ String.fromInt bit)
                ("Bit " ++ String.fromInt bit ++ " (value " ++ String.fromInt (2 ^ bit) ++ ") of our ship's index in the 25-ship roster, least significant bit first.")

        TheirShipBits ->
            let
                bit =
                    id - (sensorCount + shipBits)
            in
            Slot id
                group
                ("them b" ++ String.fromInt bit)
                ("Bit " ++ String.fromInt bit ++ " (value " ++ String.fromInt (2 ^ bit) ++ ") of the opponent ship's index in the 25-ship roster, least significant bit first.")

        PriorControls ->
            let
                idx =
                    id - observationCount

                name =
                    nth idx controlNames "control"
            in
            Slot id
                group
                ("prev " ++ name)
                ("The " ++ name ++ " control bit actually applied on the previous step, 1 or 0. This is the applied bit, not the raw output, so the left/right conflict rule is already resolved.")

        PriorMemory ->
            let
                channel =
                    id - (observationCount + controlCount)
            in
            Slot id
                group
                ("prev mem " ++ String.fromInt channel)
                ("Memory channel " ++ String.fromInt channel ++ " as emitted on the previous step, fed straight back in. Bounded to -1..1.")

        Bias ->
            Slot id group "bias" "The extra bias input. Always exactly 1, on every step of every episode."

        ControlOutputs ->
            let
                idx =
                    id - outputFirst

                name =
                    nth idx controlNames "control"
            in
            Slot id
                group
                name
                ("Control output for " ++ name ++ ". Applied when greater than zero. If left and right are both positive the ship does not turn.")

        MemoryOutputs ->
            let
                channel =
                    id - (outputFirst + controlCount)
            in
            Slot id
                group
                ("mem " ++ String.fromInt channel)
                ("Memory output channel " ++ String.fromInt channel ++ ". Bounded, stored, and fed back in as input " ++ String.fromInt (observationCount + controlCount + channel) ++ " on the next step.")

        Hidden ->
            Slot id group ("h" ++ String.fromInt id) ("Hidden node " ++ String.fromInt id ++ ", added by a structural mutation.")


nth : Int -> List String -> String -> String
nth index list fallback =
    list |> List.drop index |> List.head |> Maybe.withDefault fallback


sensorInfo : Int -> ( String, String )
sensorInfo id =
    case id of
        0 ->
            ( "our energy", "Our battery charge divided by our maximum, 0 to 1." )

        1 ->
            ( "our crew", "Our surviving crew divided by our maximum crew, 0 to 1." )

        2 ->
            ( "facing cos", "Cosine of the direction our ship points." )

        3 ->
            ( "facing sin", "Sine of the direction our ship points." )

        4 ->
            ( "our speed", "Our speed divided by our maximum thrust speed, 0 to 1." )

        5 ->
            ( "drift cos", "Cosine of the angle between where we are travelling and where we point." )

        6 ->
            ( "drift sin", "Sine of the angle between where we are travelling and where we point." )

        7 ->
            ( "weapon ready", "1 when the primary weapon cooldown has expired." )

        8 ->
            ( "special ready", "1 when the special ability cooldown has expired." )

        9 ->
            ( "turn ready", "1 when the turn cooldown has expired." )

        10 ->
            ( "thrust ready", "1 when the thrust cooldown has expired." )

        11 ->
            ( "foe dx", "Horizontal offset to the opponent across the wrapped arena, scaled by half the arena width." )

        12 ->
            ( "foe dy", "Vertical offset to the opponent across the wrapped arena, scaled by half the arena height." )

        13 ->
            ( "foe range", "Straight-line distance to the opponent, scaled by 4000 world units and clamped." )

        14 ->
            ( "closing rate", "How fast the gap to the opponent is shrinking, scaled by 200 and clamped." )

        15 ->
            ( "foe facing cos", "Cosine of the opponent's facing relative to ours." )

        16 ->
            ( "foe facing sin", "Sine of the opponent's facing relative to ours." )

        17 ->
            ( "foe energy", "Opponent battery charge divided by their maximum." )

        18 ->
            ( "foe crew", "Opponent crew divided by their maximum crew." )

        19 ->
            ( "foe speed", "Opponent speed divided by their maximum thrust speed." )

        20 ->
            ( "we cloak", "1 while our ship is cloaked." )

        21 ->
            ( "we hit now", "Urgency that a shot fired now from our current mount would connect." )

        22 ->
            ( "we hit soon", "Urgency that a shot fired shortly from now would connect." )

        23 ->
            ( "aim error", "Signed turn error between our facing and the bearing to the opponent, in facing steps over 8." )

        24 ->
            ( "they hit now", "Urgency that an opponent shot fired now would connect with us." )

        25 ->
            ( "they hit soon", "Urgency that an opponent shot fired shortly would connect with us." )

        26 ->
            ( "planet dx", "Horizontal offset to the planet, scaled by 4000 world units and clamped." )

        27 ->
            ( "planet dy", "Vertical offset to the planet, scaled by 4000 world units and clamped." )

        28 ->
            ( "planet impact", "Urgency of a predicted collision with the planet. 0 when no impact is predicted." )

        29 ->
            ( "incoming urgency", "Urgency of the nearest hostile projectile reaching us. 0 when nothing is inbound." )

        30 ->
            ( "incoming cos", "Cosine of the bearing to the nearest hostile projectile." )

        31 ->
            ( "incoming sin", "Sine of the bearing to the nearest hostile projectile." )

        32 ->
            ( "constant 1", "The constant sensor the existing encoder already emits. Always 1. Distinct from the extra bias input at node 56." )

        _ ->
            ( "sensor " ++ String.fromInt id, "Combat sensor " ++ String.fromInt id ++ "." )
