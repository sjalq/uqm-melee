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

       0 .. 92   93 combat sensors, slot 92 being the constant 1 the
                 encoder already emits
      93 .. 97   our ship identity, 5 bits, least significant bit first
      98 .. 102  their ship identity, 5 bits, least significant bit first
                 (0..102 together are the 103 observations)
     103 .. 107  the five control bits actually applied on the previous
                 step: left, right, thrust, weapon, special
     108 .. 115  the eight explicit memory channels emitted on the
                 previous step
            116  the extra bias input, always 1
     117 .. 121  control outputs: left, right, thrust, weapon, special
     122 .. 129  memory outputs, channels 0 .. 7
     130 ..      hidden nodes

Sensor names 0..92 mirror the ordering in `Neat.Encode.vector`, whose own
documentation is normative. If that encoder ever changes, this table must
change with it.

-}


sensorCount : Int
sensorCount =
    93


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
    if id >= abilityBase && id < abilityBase + (2 * abilityBits) then
        abilityInfo (id - abilityBase)

    else if id >= threatBase && id < threatBase + (threatSlots * threatWidth) then
        threatInfo ((id - threatBase) // threatWidth) (modBy threatWidth (id - threatBase))

    else
        plainSensor id


abilityBase : Int
abilityBase =
    44


abilityBits : Int
abilityBits =
    7


threatBase : Int
threatBase =
    61


threatSlots : Int
threatSlots =
    3


threatWidth : Int
threatWidth =
    8


{-| The seven ship flags the original cyborg branches on, ours then theirs. The
other four flags in the catalog are deliberately absent: the cyborg never reads
them, so neither does the network.
-}
abilityInfo : Int -> ( String, String )
abilityInfo offset =
    let
        side =
            if offset < abilityBits then
                "our ship"

            else
                "the opponent"

        prefix =
            if offset < abilityBits then
                "us "

            else
                "them "

        ( short, detail ) =
            case modBy abilityBits offset of
                0 ->
                    ( "seek wpn", "primary weapon homes on its target" )

                1 ->
                    ( "seek spec", "special ability homes on its target" )

                2 ->
                    ( "instant wpn", "weapon hits the instant it is fired, with no travel time" )

                3 ->
                    ( "fire fore", "weapon fires forward" )

                4 ->
                    ( "fire right", "weapon fires to the right" )

                5 ->
                    ( "fire aft", "weapon fires backwards" )

                _ ->
                    ( "fire left", "weapon fires to the left" )
    in
    ( prefix ++ short, "1 when " ++ side ++ "'s " ++ detail ++ "." )


{-| Three hostile projectiles, ranked by how soon each is predicted to hit us,
which is the order the cyborg itself ranks them in. Rank 0 is the most urgent.
-}
threatInfo : Int -> Int -> ( String, String )
threatInfo rank field =
    let
        rankName =
            "threat " ++ String.fromInt rank

        ( short, detail ) =
            case field of
                0 ->
                    ( "urgency", "Urgency of the predicted impact. 0 when this projectile is not predicted to reach us, or when there is no such projectile." )

                1 ->
                    ( "travel cos", "Cosine of the direction it is travelling, relative to where we point." )

                2 ->
                    ( "travel sin", "Sine of the direction it is travelling, relative to where we point." )

                3 ->
                    ( "closing", "Cosine of the angle between its travel direction and its bearing to us. Near 1 means it is coming straight at us." )

                4 ->
                    ( "seeking", "1 when it homes, worked out from the ability of the ship that launched it." )

                5 ->
                    ( "finite life", "1 when it expires on a timer rather than persisting." )

                6 ->
                    ( "damage", "Its mass, which is the crew it would cost us, over our maximum crew." )

                _ ->
                    ( "life left", "How much of its flight time remains, over 64." )
    in
    ( rankName ++ " " ++ short
    , "Ranked hostile projectile " ++ String.fromInt rank ++ ", soonest predicted impact first. " ++ detail
    )


plainSensor : Int -> ( String, String )
plainSensor id =
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
            ( "at limit", "1 when we are already at our speed limit. This is the predicate the cyborg coasts on, which the speed ratio at slot 4 cannot express." )

        12 ->
            ( "beyond limit", "1 when we are travelling faster than our own limit, usually after a gravity slingshot." )

        13 ->
            ( "in gravity", "1 while the planet's gravity well has hold of us." )

        14 ->
            ( "uses inertia", "1 for a hull that accelerates gradually rather than snapping to full speed." )

        15 ->
            ( "ultra", "1 for a hull that snaps to full speed and is at least moderately agile. The cyborg treats these differently around gravity and homing missiles." )

        16 ->
            ( "can pay wpn", "1 when we hold at least the energy one shot costs." )

        17 ->
            ( "can pay spec", "1 when we hold at least the energy one special costs." )

        18 ->
            ( "approach fuel", "How many turns of special the energy we hold would pay for, over 64. This is the budget Umgah plans its approach with." )

        19 ->
            ( "special timer", "The special cooldown itself over 64, not just whether it expired. Chenjesu fires on exactly one tick remaining." )

        20 ->
            ( "our hull mass", "Our hull's inertial mass over twice the ordinary maximum, so a transformed hull reads above one half." )

        21 ->
            ( "foe dx", "Horizontal offset to the opponent across the wrapped arena, scaled by half the arena width." )

        22 ->
            ( "foe dy", "Vertical offset to the opponent across the wrapped arena, scaled by half the arena height." )

        23 ->
            ( "foe range", "Straight-line distance to the opponent, scaled by 4000 world units and clamped." )

        24 ->
            ( "closing rate", "How fast the gap to the opponent is shrinking, scaled by 200 and clamped." )

        25 ->
            ( "foe facing cos", "Cosine of the opponent's facing relative to ours." )

        26 ->
            ( "foe facing sin", "Sine of the opponent's facing relative to ours." )

        27 ->
            ( "foe speed", "Opponent speed divided by their maximum thrust speed." )

        28 ->
            ( "aim error", "Signed turn error between our facing and the bearing to the opponent, in facing steps over 8." )

        29 ->
            ( "foe hull mass", "The opponent hull's inertial mass over twice the ordinary maximum, so a transformed hull reads above one half." )

        30 ->
            ( "foe cloak", "1 while the opponent's hull is drawn cloaked, which is what widens the cyborg's aiming margin." )

        31 ->
            ( "we cloak", "1 while our ship is cloaked." )

        32 ->
            ( "foe energy", "Opponent battery charge divided by their maximum. Deliberately more than the cyborg reads." )

        33 ->
            ( "foe crew", "Opponent crew divided by their maximum crew. Deliberately more than the cyborg reads." )

        34 ->
            ( "we can fire", "1 when a shot fired right now would connect, by the cyborg's own firing test." )

        35 ->
            ( "we close in", "Urgency of closing to within three quarters of our own weapon range." )

        36 ->
            ( "they can fire", "1 when a shot the opponent fires now would connect with us. Against a missile hull this is more than the cyborg is told." )

        37 ->
            ( "they close in", "Urgency of the opponent closing to within three quarters of their weapon range." )

        38 ->
            ( "they hit instantly", "1 when the opponent's weapon hits the instant it is fired. This says whether the two slots before it are what the cyborg also sees." )

        39 ->
            ( "our range", "Our weapon's engagement range over 4000 world units." )

        40 ->
            ( "their range", "The opponent's engagement range over 4000 world units." )

        41 ->
            ( "our agility", "Our maneuverability rating over 150, the fast-ship mark." )

        42 ->
            ( "their agility", "The opponent's maneuverability rating over 150." )

        43 ->
            ( "thrust edge", "Our maximum thrust minus theirs, over 64. The raw comparison the cyborg makes, which the two speed ratios destroy." )

        58 ->
            ( "planet dx", "Horizontal offset to the planet, scaled by 4000 world units and clamped." )

        59 ->
            ( "planet dy", "Vertical offset to the planet, scaled by 4000 world units and clamped." )

        60 ->
            ( "planet impact", "Urgency of a predicted collision with the planet, from the cyborg's own three-margin gravity test. 0 when no impact is predicted." )

        85 ->
            ( "crew dx", "Horizontal offset to the nearest floating crew pod, scaled by half the arena width." )

        86 ->
            ( "crew dy", "Vertical offset to the nearest floating crew pod, scaled by half the arena height." )

        87 ->
            ( "crew urgency", "Urgency of reaching the nearest floating crew pod. 0 when there is none." )

        88 ->
            ( "crew targeted", "1 when our ship is already chasing that crew pod." )

        89 ->
            ( "rock dx", "Horizontal offset to the nearest neutral body, an asteroid or debris, scaled by 4000 world units." )

        90 ->
            ( "rock dy", "Vertical offset to the nearest neutral body, scaled by 4000 world units." )

        91 ->
            ( "rock urgency", "Urgency of reaching the nearest neutral body. 0 when there is none." )

        92 ->
            ( "constant 1", "The constant sensor the encoder already emits. Always 1. Distinct from the extra bias input at node 116." )

        _ ->
            ( "sensor " ++ String.fromInt id, "Combat sensor " ++ String.fromInt id ++ "." )
