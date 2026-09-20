module Melee.Jev exposing
    ( Button(..)
    , Client
    , Memory
    , Sight
    , agoOf
    , applyReply
    , beginRequest
    , buttonLabel
    , buttonToInput
    , decodeReply
    , empty
    , encodeRequest
    , focusSide
    , memories
    , noteArena
    , nowOf
    , observe
    , pilots
    , prompt
    , promptFrom
    , requestDue
    , awaitToken
    , toggle
    )

{-| Local-only Jev survival pilot.

Jev is not a cyborg rewrite. It sees a compact text state built from the
current arena and the arena from one second earlier, plus short durable
memories, and answers one Choice: which single button is most likely to
keep the ship alive. The answer is cached and applied as `BattleInput`
on computer seats in local games only.

-}

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Element exposing (Body(..), Element, Owner(..))
import Melee.Id exposing (toInt)
import Melee.Input exposing (BattleInput, Turn(..))
import Melee.Ship exposing (ShipKind)
import Melee.ShipState as State
import Melee.Strategy as Strategy
import Melee.Trig as Trig
import Melee.Units exposing (Facing(..), FrameCount(..), Side(..), Wait(..))


{-| One mutually exclusive survival control. Matches Jev Choice codes.
-}
type Button
    = Idle
    | Left
    | Right
    | Thrust
    | Fire
    | Special


type alias Memory =
    String


type alias ShipSight =
    { kind : ShipKind
    , name : String
    , crew : Int
    , energy : Int
    , maxEnergy : Int
    , facing : Int
    , x : Int
    , y : Int
    , speed : Int
    , weaponReady : Bool
    , specialReady : Bool
    }


type alias Threat =
    { label : String
    , x : Int
    , y : Int
    , range : Int
    }


type alias Sight =
    { frame : Int
    , side : Side
    , own : ShipSight
    , foe : ShipSight
    , bearing : Int
    , range : Int
    , threats : List Threat
    }


type alias Client =
    { enabled : Bool
    , button : Button
    , pending : Bool
    , token : Maybe String
    , lastAskedMs : Float
    , status : String
    , memories : List Memory
    , history : List Sight
    }


empty : Client
empty =
    { enabled = False
    , button = Idle
    , pending = False
    , token = Nothing
    , lastAskedMs = -1.0 / 0.0
    , status = "Jev off"
    , memories = bootstrapMemories
    , history = []
    }


toggle : Client -> Client
toggle client =
    if client.enabled then
        { client
            | enabled = False
            , pending = False
            , token = Nothing
            , status = "Jev off"
            , history = []
        }

    else
        { client
            | enabled = True
            , token = Nothing
            , status = "Jev arming…"
            , memories = bootstrapMemories
        }


bootstrapMemories : List Memory
bootstrapMemories =
    [ "Prefer lateral thrust over sitting still under fire."
    , "Turn into the threat cone before thrusting past it."
    , "Fire only with a clear nose shot; thrusters beat panic volleys."
    , "Special is a last-ditch survival tool, not an opening move."
    , "Gravity wells steal speed — skim, do not park."
    ]


buttonLabel : Button -> String
buttonLabel button =
    case button of
        Idle ->
            "idle"

        Left ->
            "left"

        Right ->
            "right"

        Thrust ->
            "thrust"

        Fire ->
            "fire"

        Special ->
            "special"


buttonToInput : Button -> BattleInput
buttonToInput button =
    case button of
        Idle ->
            { turn = NoTurn, thrust = False, weapon = False, special = False }

        Left ->
            { turn = TurnLeft, thrust = False, weapon = False, special = False }

        Right ->
            { turn = TurnRight, thrust = False, weapon = False, special = False }

        Thrust ->
            { turn = NoTurn, thrust = True, weapon = False, special = False }

        Fire ->
            { turn = NoTurn, thrust = False, weapon = True, special = False }

        Special ->
            { turn = NoTurn, thrust = False, weapon = False, special = True }


{-| Computer seats in local games apply the cached Jev button.
Human seats still read the keyboard via `Local.battleFrameUsing`.
-}
pilots : Button -> Strategy.Pilots
pilots button =
    let
        roster _ =
            Strategy.controls
                (\context ->
                    ( buttonToInput button, context.seed )
                )
    in
    { bottom = roster, top = roster }


observe : Side -> Arena -> Maybe Sight
observe side arena =
    let
        ownShip =
            if side == Bottom then
                arena.combatants.bottom

            else
                arena.combatants.top

        foeShip =
            if side == Bottom then
                arena.combatants.top

            else
                arena.combatants.bottom
    in
    Maybe.map2
        (\ownEl foeEl ->
            let
                own =
                    shipSight ownShip ownEl

                foe =
                    shipSight foeShip foeEl

                dx =
                    Trig.wrapDelta (foe.x - own.x) arena.space.width

                dy =
                    Trig.wrapDelta (foe.y - own.y) arena.space.height

                (FrameCount frame) =
                    arena.frame
            in
            { frame = frame
            , side = side
            , own = own
            , foe = foe
            , bearing = Trig.arctan dx dy
            , range = Trig.squareRoot (dx * dx + dy * dy)
            , threats = threats side own arena
            }
        )
        (Dict.get (toInt (State.core ownShip).element) arena.elements)
        (Dict.get (toInt (State.core foeShip).element) arena.elements)


shipSight : State.Combatant -> Element -> ShipSight
shipSight ship el =
    let
        c =
            State.core ship

        kind =
            State.kind ship

        (Facing facing) =
            c.facing

        (Wait weaponWait) =
            c.weaponWait

        (Wait specialWait) =
            c.specialWait

        speed =
            abs el.velocity.vector.width + abs el.velocity.vector.height
    in
    { kind = kind
    , name = (Catalog.info kind).name
    , crew = el.points
    , energy = c.energy
    , maxEnergy = c.maxEnergy
    , facing = facing
    , x = el.current.location.x
    , y = el.current.location.y
    , speed = speed
    , weaponReady = weaponWait <= 0
    , specialReady = specialWait <= 0
    }


threats : Side -> ShipSight -> Arena -> List Threat
threats side own arena =
    arena.elements
        |> Dict.values
        |> List.filterMap (threatFrom side own arena.space.width arena.space.height)
        |> List.sortBy .range
        |> List.take 4


threatFrom : Side -> ShipSight -> Int -> Int -> Element -> Maybe Threat
threatFrom side own width height el =
    case el.body of
        PlanetBody ->
            Just (mkThreat "gravity-well" own el width height)

        AsteroidBody ->
            Just (mkThreat "asteroid" own el width height)

        ShipBody other ->
            if other == side then
                Nothing

            else
                Just (mkThreat "enemy-ship" own el width height)

        body ->
            if hostile side el then
                Just (mkThreat (weaponName body) own el width height)

            else
                Nothing


hostile : Side -> Element -> Bool
hostile side el =
    case el.owner of
        Owned owner ->
            owner /= side

        Neutral ->
            case el.body of
                PlanetBody ->
                    True

                AsteroidBody ->
                    True

                _ ->
                    False


weaponName : Body -> String
weaponName body =
    case body of
        PlanetBody ->
            "gravity-well"

        AsteroidBody ->
            "asteroid"

        ShipBody _ ->
            "enemy-ship"

        WreckBody _ ->
            "wreck"

        CrewBody _ ->
            "crew"

        WeaponImpact _ ->
            "impact"

        BlastBody ->
            "blast"

        ExplosionBody ->
            "explosion"

        WarpInBody ->
            "warp"

        IonTrailBody ->
            "trail"

        AndrosynthBubble ->
            "bubble"

        ArilouLaser ->
            "laser"

        ChenjesuPhoton ->
            "photon"

        ChenjesuFragment ->
            "shard"

        ChenjesuDogi ->
            "dogi"

        ChmmrLaser ->
            "laser"

        ChmmrSatellite _ ->
            "satellite"

        ChmmrZap ->
            "zap"

        DruugeHotShot ->
            "cannon"

        EarthlingNuke ->
            "nuke"

        EarthlingPointDefense ->
            "pd"

        IlwrathFlame ->
            "flame"

        KohrAhSaw ->
            "blade"

        KohrAhFried ->
            "ring"

        MelnormeCharge ->
            "charge"

        MelnormeConfusion ->
            "confusion"

        MmrnmhrmLaser ->
            "laser"

        MmrnmhrmMissile ->
            "missile"

        MyconPlasma ->
            "plasma"

        OrzHowitzer ->
            "howitzer"

        OrzMarine ->
            "marine"

        PkunkSpread ->
            "spread"

        ShofixtiDart ->
            "dart"

        ShofixtiGlory ->
            "glory"

        SlylandroLightning ->
            "lightning"

        SpathiForward ->
            "missile"

        SpathiButt ->
            "butt"

        SupoxPellet ->
            "pellet"

        SyreenMissile ->
            "syreen"

        ThraddashBlaster ->
            "blaster"

        ThraddashAfterburn ->
            "afterburn"

        UmgahCone ->
            "cone"

        UrQuanFusion ->
            "fusion"

        UrQuanFighter ->
            "fighter"

        UrQuanFighterLaser ->
            "fighter-laser"

        UtwigGizmo ->
            "gizmo"

        VuxLaser ->
            "vux-laser"

        VuxLimpet ->
            "limpet"

        YehatMissile ->
            "yehat"

        ZoqSpit ->
            "spit"

        ZoqTongue ->
            "tongue"


mkThreat : String -> ShipSight -> Element -> Int -> Int -> Threat
mkThreat label own el width height =
    let
        dx =
            Trig.wrapDelta (el.current.location.x - own.x) width

        dy =
            Trig.wrapDelta (el.current.location.y - own.y) height
    in
    { label = label
    , x = el.current.location.x
    , y = el.current.location.y
    , range = Trig.squareRoot (dx * dx + dy * dy)
    }


{-| Keep a one-second ring of battle-frame sights for the computer seat.
-}
noteArena : Side -> Arena -> Client -> Client
noteArena side arena client =
    if not client.enabled then
        client

    else
        case observe side arena of
            Nothing ->
                client

            Just sight ->
                let
                    history =
                        case client.history of
                            previous :: rest ->
                                if previous.frame == sight.frame then
                                    sight :: rest

                                else
                                    sight :: List.take 30 client.history

                            [] ->
                                [ sight ]

                    ago =
                        historyAtLeast 24 history

                    nextMemories =
                        memories sight ago client.memories
                in
                { client | history = history, memories = nextMemories }


historyAtLeast : Int -> List Sight -> Maybe Sight
historyAtLeast frames history =
    case history of
        newest :: _ ->
            history
                |> List.filter (\s -> newest.frame - s.frame >= frames)
                |> List.head
                |> (\found ->
                        case found of
                            Just sight ->
                                Just sight

                            Nothing ->
                                List.reverse history |> List.head
                   )

        [] ->
            Nothing


memories : Sight -> Maybe Sight -> List Memory -> List Memory
memories now ago prior =
    let
        fresh =
            case ago of
                Nothing ->
                    [ "Acquiring baseline on " ++ now.own.name ++ "." ]

                Just past ->
                    List.filterMap identity
                        [ crewMemory now past
                        , rangeMemory now past
                        , energyMemory now past
                        , threatMemory now
                        , geometryMemory now
                        ]
    in
    (fresh ++ prior)
        |> unique
        |> List.take 8


crewMemory : Sight -> Sight -> Maybe Memory
crewMemory now past =
    let
        lost =
            past.own.crew - now.own.crew
    in
    if lost >= 3 then
        Just ("Took heavy crew loss on " ++ now.own.name ++ " — prioritize evasion over trades.")

    else if lost > 0 then
        Just ("Leaking crew (" ++ String.fromInt lost ++ "). Stop eating hits.")

    else if now.own.crew <= max 3 (now.own.crew // 4) then
        Just "Crew critical. Survive first; scoring second."

    else
        Nothing


rangeMemory : Sight -> Sight -> Maybe Memory
rangeMemory now past =
    let
        closing =
            past.range - now.range
    in
    if now.range < 600 && closing > 200 then
        Just "Foe is diving hard — break the intercept line."

    else if now.range > 2500 && closing < -150 then
        Just "Opening range. Re-close only with nose authority."

    else if now.range < 400 then
        Just "Knife fight. Small turns and thrust pulses beat long holds."

    else
        Nothing


energyMemory : Sight -> Sight -> Maybe Memory
energyMemory now past =
    if now.own.energy <= now.own.maxEnergy // 4 && past.own.energy > now.own.energy then
        Just "Energy starved. Thrust and special over weapon spam."

    else if now.own.energy == now.own.maxEnergy && now.own.weaponReady then
        Just "Batteries full and gun hot — spend a shot if nose is clean."

    else
        Nothing


threatMemory : Sight -> Maybe Memory
threatMemory now =
    case List.head now.threats of
        Just threat ->
            if threat.range < 500 then
                Just ("Imminent " ++ threat.label ++ " at " ++ String.fromInt threat.range ++ "u.")

            else if threat.label == "gravity-well" && threat.range < 1200 then
                Just "Gravity well nearby — keep speed up on the skim."

            else
                Nothing

        Nothing ->
            Nothing


geometryMemory : Sight -> Maybe Memory
geometryMemory now =
    let
        noseDelta =
            modBy 16 (((now.bearing + 2) // 4) - now.own.facing)
    in
    if noseDelta == 0 || noseDelta == 15 || noseDelta == 1 then
        Just "Nose is on target — thrust or fire beats turning."

    else if noseDelta >= 6 && noseDelta <= 10 then
        Just "Foe is aft. Turn hard or burn past; do not idle."

    else
        Nothing


unique : List String -> List String
unique items =
    List.foldl
        (\item acc ->
            if List.member item acc then
                acc

            else
                acc ++ [ item ]
        )
        []
        items


prompt : Sight -> Maybe Sight -> List Memory -> String
prompt now ago mems =
    String.join "\n"
        [ "Local Super Melee survival decision. Pick ONE button that best keeps this ship alive next."
        , "NOW: " ++ describeSight now
        , case ago of
            Just past ->
                "1S_AGO: " ++ describeSight past

            Nothing ->
                "1S_AGO: (warming up — no prior sample yet)"
        , "MEMORIES:"
        , mems
            |> List.indexedMap (\i m -> "  " ++ String.fromInt (i + 1) ++ ". " ++ m)
            |> String.join "\n"
        , "Rules: single button only; survival over aggression; idle only if truly safe."
        ]


describeSight : Sight -> String
describeSight sight =
    let
        sideName =
            if sight.side == Bottom then
                "gold"

            else
                "cyan"

        threatText =
            if List.isEmpty sight.threats then
                "none"

            else
                sight.threats
                    |> List.map (\t -> t.label ++ "@" ++ String.fromInt t.range)
                    |> String.join ", "
    in
    String.join " "
        [ "seat=" ++ sideName
        , "frame=" ++ String.fromInt sight.frame
        , "own=" ++ sight.own.name
        , "crew=" ++ String.fromInt sight.own.crew
        , "energy=" ++ String.fromInt sight.own.energy ++ "/" ++ String.fromInt sight.own.maxEnergy
        , "facing=" ++ String.fromInt sight.own.facing
        , "pos=(" ++ String.fromInt sight.own.x ++ "," ++ String.fromInt sight.own.y ++ ")"
        , "speed=" ++ String.fromInt sight.own.speed
        , "gun=" ++ ready sight.own.weaponReady
        , "special=" ++ ready sight.own.specialReady
        , "foe=" ++ sight.foe.name
        , "foeCrew=" ++ String.fromInt sight.foe.crew
        , "foePos=(" ++ String.fromInt sight.foe.x ++ "," ++ String.fromInt sight.foe.y ++ ")"
        , "bearing=" ++ String.fromInt sight.bearing
        , "range=" ++ String.fromInt sight.range
        , "threats=[" ++ threatText ++ "]"
        ]


ready : Bool -> String
ready flag =
    if flag then
        "ready"

    else
        "wait"


encodeRequest : String -> Encode.Value
encodeRequest state =
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


decodeReply : Decode.Value -> Result String { button : Button, danger : Maybe Float, confidence : Maybe Float }
decodeReply value =
    Decode.decodeValue replyDecoder value
        |> Result.mapError Decode.errorToString


replyDecoder : Decode.Decoder { button : Button, danger : Maybe Float, confidence : Maybe Float }
replyDecoder =
    Decode.map3
        (\button danger confidence ->
            { button = button, danger = danger, confidence = confidence }
        )
        (Decode.at [ "answers", "survivalButton", "choice" ] buttonDecoder)
        (Decode.maybe (Decode.at [ "answers", "danger", "score" ] Decode.float))
        (Decode.maybe (Decode.at [ "answers", "survivalButton", "confidence" ] Decode.float))


buttonDecoder : Decode.Decoder Button
buttonDecoder =
    Decode.string
        |> Decode.andThen
            (\code ->
                case code of
                    "idle" ->
                        Decode.succeed Idle

                    "left" ->
                        Decode.succeed Left

                    "right" ->
                        Decode.succeed Right

                    "thrust" ->
                        Decode.succeed Thrust

                    "fire" ->
                        Decode.succeed Fire

                    "special" ->
                        Decode.succeed Special

                    other ->
                        Decode.fail ("Unknown Jev button: " ++ other)
            )


requestDue : Float -> Float -> Client -> Bool
requestDue nowMs minIntervalMs client =
    client.enabled
        && not client.pending
        && (nowMs - client.lastAskedMs >= minIntervalMs)
        && (List.length client.history >= 1)


beginRequest : Float -> Client -> Client
beginRequest nowMs client =
    { client | pending = True, token = Nothing, lastAskedMs = nowMs }


awaitToken : String -> Client -> Client
awaitToken token client =
    { client | pending = True, token = Just token, status = "Jev thinking…" }


applyReply : Result String { button : Button, danger : Maybe Float, confidence : Maybe Float } -> Client -> Client
applyReply result client =
    case result of
        Ok answer ->
            let
                conf =
                    answer.confidence
                        |> Maybe.map (\c -> " conf=" ++ String.fromFloat (round100 c))
                        |> Maybe.withDefault ""

                danger =
                    answer.danger
                        |> Maybe.map (\d -> " danger=" ++ String.fromFloat (round100 d))
                        |> Maybe.withDefault ""
            in
            { client
                | pending = False
                , token = Nothing
                , button = answer.button
                , status = "Jev → " ++ buttonLabel answer.button ++ conf ++ danger
            }

        Err err ->
            { client
                | pending = False
                , token = Nothing
                , status = "Jev error: " ++ String.left 80 err
            }


round100 : Float -> Float
round100 n =
    toFloat (round (n * 100)) / 100


{-| Primary computer seat for Solo (top) / ReverseSolo (bottom).
Demo applies the same cached button to both seats via `pilots`.
-}
focusSide : { reverse : Bool } -> Side
focusSide flags =
    if flags.reverse then
        Bottom

    else
        Top


agoOf : Client -> Maybe Sight
agoOf client =
    historyAtLeast 24 client.history


nowOf : Client -> Maybe Sight
nowOf client =
    List.head client.history


promptFrom : Client -> Maybe String
promptFrom client =
    case nowOf client of
        Just now ->
            Just (prompt now (agoOf client) client.memories)

        Nothing ->
            Nothing
