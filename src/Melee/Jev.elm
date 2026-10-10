module Melee.Jev exposing
    ( Answer
    , Call(..)
    , Client
    , Failure(..)
    , Latency
    , Past
    , answerDecoder
    , answerToInput
    , backoffMs
    , due
    , empty
    , failed
    , landed
    , latencyAlpha
    , latencySamples
    , noteLatency
    , questions
    , remember
    , roster
    , sent
    , state
    , statusLine
    , timeoutMs
    )

{-| Local-only Jev pilot for one seat.

Jev is TypeSafe's structured decision model. Each call sends a JSON picture
of the duel built from the same facts the cyborg reads (exact positions,
velocities, cooldowns, energy, weapon reach, every live hazard), tells Jev
how stale its answer will be when it lands (the measured moving-average
round trip, in battle frames, with every object projected forward by that
much), and asks four questions at once: which way to turn, and whether to
thrust, fire and use the special. The four answers together are one
`BattleInput`, so any combination of keys can be held, exactly like a human
or the cyborg. The input is held until the next answer lands, and the next
call leaves as soon as it does.

Failures never replay old state: a transient error backs off briefly and the
next call describes the arena as it is then.

-}

import Dict
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Melee.Arsenal as Arsenal
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Element exposing (Body(..), Element, Owner(..))
import Melee.Id exposing (toInt)
import Melee.Input exposing (BattleInput, Turn(..))
import Melee.Projectile as Projectile
import Melee.ShipState as State
import Melee.Strategy as Strategy
import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), FrameCount(..), Side(..), Wait(..))
import Melee.Velocity as Velocity



-- CLIENT


{-| Where this seat's conversation with Jev stands. A call is only ever in
flight while `Waiting`, so a seat cannot have two, and a stale answer (one
whose id no longer matches) is simply ignored.
-}
type Call
    = Idle
    | Waiting { id : String, sentAt : Float }
    | Backoff { until : Float }


type Failure
    = Transient String
    | Permanent String


type alias Answer =
    { turn : Turn
    , thrust : Float
    , fire : Float
    , special : Float
    , turnConfidence : Float
    }


{-| `average` is an exponentially weighted moving average of round trips;
`recent` keeps the last `latencySamples` for the distribution readout.
-}
type alias Latency =
    { average : Maybe Float
    , recent : List Float
    , answered : Int
    , failures : Int
    }


type alias Client =
    { past : List Past
    , input : BattleInput
    , answer : Maybe Answer
    , call : Call
    , nextId : Int
    , consecutiveFailures : Int
    , latency : Latency
    , status : String
    }


empty : Client
empty =
    { past = []
    , input = Melee.Input.idle
    , answer = Nothing
    , call = Idle
    , nextId = 0
    , consecutiveFailures = 0
    , latency = { average = Nothing, recent = [], answered = 0, failures = 0 }
    , status = "Jev arming…"
    }


latencyAlpha : Float
latencyAlpha =
    0.25


latencySamples : Int
latencySamples =
    20


{-| A call with no answer after this long is abandoned and a fresh one sent.
Longer than the backend's own gateway timeout, so a slow answer usually
still arrives as an explicit failure first.
-}
timeoutMs : Float
timeoutMs =
    10000


backoffMs : Int -> Float
backoffMs consecutiveFailures =
    min 2000 (150 * toFloat (2 ^ max 0 (consecutiveFailures - 1)))


{-| Ready to send now? True when idle, when a backoff has run out, or when
the call in flight has timed out.
-}
due : Float -> Client -> Bool
due nowMs client =
    case client.call of
        Idle ->
            True

        Backoff { until } ->
            nowMs >= until

        Waiting { sentAt } ->
            nowMs - sentAt >= timeoutMs


{-| Record that a call left; returns the id the answer must echo.
-}
sent : String -> Float -> Client -> ( String, Client )
sent prefix nowMs client =
    let
        id =
            prefix ++ "-" ++ String.fromInt client.nextId
    in
    ( id, { client | call = Waiting { id = id, sentAt = nowMs }, nextId = client.nextId + 1 } )


noteLatency : Float -> Latency -> Latency
noteLatency sample latency =
    { average =
        Just
            (case latency.average of
                Just previous ->
                    previous + latencyAlpha * (sample - previous)

                Nothing ->
                    sample
            )
    , recent = List.take latencySamples (sample :: latency.recent)
    , answered = latency.answered + 1
    , failures = latency.failures
    }


{-| An answer arrived. Ignored unless it answers the call still in flight.
-}
landed : String -> Float -> Answer -> Client -> Client
landed id nowMs answer client =
    case client.call of
        Waiting waiting ->
            if waiting.id == id then
                let
                    latency =
                        noteLatency (nowMs - waiting.sentAt) client.latency
                in
                { client
                    | input = answerToInput answer
                    , answer = Just answer
                    , call = Idle
                    , consecutiveFailures = 0
                    , latency = latency
                    , status = statusLine latency
                }

            else
                client

        _ ->
            client


{-| A call failed. The held input stays; the next call describes the arena
as it is then, after a short backoff.
-}
failed : Maybe String -> Float -> Failure -> Client -> Client
failed id nowMs failure client =
    let
        matches =
            case ( id, client.call ) of
                ( Nothing, Waiting _ ) ->
                    True

                ( Just answerId, Waiting waiting ) ->
                    waiting.id == answerId

                _ ->
                    False

        latency =
            client.latency

        streak =
            client.consecutiveFailures + 1

        ( wait, message ) =
            case failure of
                Transient text ->
                    ( backoffMs streak, "Jev retrying: " ++ String.left 60 text )

                Permanent text ->
                    ( 5000, "Jev error: " ++ String.left 60 text )
    in
    if matches then
        { client
            | call = Backoff { until = nowMs + wait }
            , consecutiveFailures = streak
            , latency = { latency | failures = latency.failures + 1 }
            , status = message
        }

    else
        client


statusLine : Latency -> String
statusLine latency =
    let
        sorted =
            List.sort latency.recent

        count =
            List.length sorted

        median =
            List.drop (count // 2) sorted |> List.head

        ms value =
            String.fromInt (round value)
    in
    case ( latency.average, median ) of
        ( Just average, Just middle ) ->
            "ping avg "
                ++ ms average
                ++ "ms · last "
                ++ String.fromInt count
                ++ ": max "
                ++ ms (List.maximum sorted |> Maybe.withDefault middle)
                ++ " med "
                ++ ms middle
                ++ " min "
                ++ ms (List.minimum sorted |> Maybe.withDefault middle)
                ++ " · "
                ++ String.fromInt latency.answered
                ++ " answers, "
                ++ String.fromInt latency.failures
                ++ " failures"

        _ ->
            "Jev arming…"


answerToInput : Answer -> BattleInput
answerToInput answer =
    { turn = answer.turn
    , thrust = answer.thrust >= 0.5
    , weapon = answer.fire >= 0.5
    , special = answer.special >= 0.5
    }


{-| The pilot roster for a Jev seat: every ship holds the latest answer until
the next one lands. The seed passes through untouched, so the cyborg RNG
stream stays exactly where the original game would have it.
-}
roster : BattleInput -> Strategy.Roster
roster input _ =
    Strategy.controls (\context -> ( input, context.seed ))



-- STATE


battleFramesPerSecond : Float
battleFramesPerSecond =
    24


type alias Body_ =
    { x : Float, y : Float, vx : Float, vy : Float }


{-| Position in world units, velocity in world units per battle frame.
-}
kinematics : Element -> Body_
kinematics el =
    let
        ( vx, vy ) =
            Velocity.getCurrent el.velocity
    in
    { x = toFloat el.current.location.x
    , y = toFloat el.current.location.y
    , vx = toFloat vx / 32
    , vy = toFloat vy / 32
    }


{-| How much a snapshot says. `Live` is the moment being decided on: it adds
each ship's fixed characteristics and projects everything forward by the
round trip. `Memory` is a past moment: only what changes.
-}
type Detail
    = Live Float
    | Memory


{-| Everything relative to our ship, with wraparound: range, bearing off our
nose (degrees, positive to starboard), closing speed, relative velocity and
closest approach; live snapshots add range and bearing once our input lands.
-}
relative : Detail -> { width : Int, height : Int } -> Int -> Body_ -> Body_ -> List ( String, Encode.Value )
relative detail space facing own other =
    let
        dx =
            toFloat (Trig.wrapDelta (round (other.x - own.x)) space.width)

        dy =
            toFloat (Trig.wrapDelta (round (other.y - own.y)) space.height)

        rvx =
            other.vx - own.vx

        rvy =
            other.vy - own.vy

        range =
            sqrt (dx * dx + dy * dy)

        speedSq =
            rvx * rvx + rvy * rvy

        tca =
            if speedSq <= 0.0001 then
                0

            else
                max 0 (-(dx * rvx + dy * rvy) / speedSq)

        missX =
            dx + rvx * tca

        missY =
            dy + rvy * tca

        closing =
            if range <= 0 then
                0

            else
                -(dx * rvx + dy * rvy) / range

        core =
            [ ( "range", int range )
            , ( "bearing", int (offNose facing dx dy) )
            , ( "closing", num closing )
            , ( "relVel", Encode.list num [ rvx, rvy ] )
            , ( "cpaFrames", int tca )
            , ( "cpaDist", int (sqrt (missX * missX + missY * missY)) )
            ]
    in
    case detail of
        Live leadFrames ->
            let
                leadX =
                    dx + rvx * leadFrames

                leadY =
                    dy + rvy * leadFrames
            in
            core
                ++ [ ( "rangeAtLanding", int (sqrt (leadX * leadX + leadY * leadY)) )
                   , ( "bearingAtLanding", int (offNose facing leadX leadY) )
                   ]

        Memory ->
            core


{-| Screen y grows downward; UQM angle 0 points up and turns clockwise.
-}
compassDeg : Float -> Float -> Float
compassDeg dx dy =
    toFloat (Trig.arctan (round dx) (round dy)) * 360 / 64


facingDeg : Int -> Float
facingDeg facing =
    toFloat facing * 22.5


offNose : Int -> Float -> Float -> Float
offNose facing dx dy =
    let
        raw =
            compassDeg dx dy - facingDeg facing
    in
    raw - 360 * toFloat (floor ((raw + 180) / 360))


int : Float -> Encode.Value
int value =
    Encode.int (round value)


num : Float -> Encode.Value
num value =
    Encode.float (toFloat (round (value * 10)) / 10)


waitFrames : Wait -> Int
waitFrames (Wait frames) =
    frames


weaponFacts : State.Combatant -> List ( String, Encode.Value )
weaponFacts ship =
    case Arsenal.primary ship of
        Projectile.Missile missile ->
            [ ( "kind", Encode.string "projectile" )
            , ( "speed", Encode.int missile.speed )
            , ( "lifeFrames", Encode.int missile.life )
            , ( "reach", Encode.int (missile.speed * missile.life) )
            , ( "damage", Encode.int missile.damage )
            , ( "homing", Encode.bool (missile.guidance /= Projectile.Ballistic) )
            , ( "barrels", Encode.int (List.length (Arsenal.mounts missile)) )
            ]

        Projectile.Beam _ ->
            [ ( "kind", Encode.string "instant beam along the nose, short to medium range" ) ]

        Projectile.Contact _ ->
            [ ( "kind", Encode.string "contact weapon at the nose only" ) ]

        Projectile.Lightning ->
            [ ( "kind", Encode.string "short-range lightning arc" ) ]


shipFacts : Detail -> State.Combatant -> Element -> Body_ -> List ( String, Encode.Value )
shipFacts detail ship el body =
    let
        core =
            State.core ship

        c =
            core.characteristics

        (Facing facing) =
            core.facing

        speed =
            sqrt (body.vx * body.vx + body.vy * body.vy)

        changing =
            [ ( "crew", Encode.int el.points )
            , ( "energy", Encode.int core.energy )
            , ( "noseDeg", int (facingDeg facing) )
            , ( "travelDeg"
              , if speed < 0.05 then
                    Encode.null

                else
                    int (compassDeg body.vx body.vy)
              )
            , ( "speed", num speed )
            , ( "weaponReadyIn", Encode.int (max 0 (waitFrames core.weaponWait)) )
            , ( "specialReadyIn", Encode.int (max 0 (waitFrames core.specialWait)) )
            ]
    in
    case detail of
        Live _ ->
            let
                info =
                    Catalog.info (State.kind ship)
            in
            [ ( "ship", Encode.string (info.name ++ " " ++ info.vessel ++ ": " ++ info.help) ) ]
                ++ changing
                ++ [ ( "maxCrew", Encode.int core.maxCrew )
                   , ( "maxEnergy", Encode.int core.maxEnergy )
                   , ( "maxSpeed", Encode.int c.maxThrust )
                   , ( "turnFramesPerStep", Encode.int (waitFrames c.turnWait + 1) )
                   , ( "canFire", Encode.bool (waitFrames core.weaponWait <= 0 && core.energy >= c.weaponEnergyCost) )
                   , ( "canSpecial", Encode.bool (waitFrames core.specialWait <= 0 && core.energy >= c.specialEnergyCost) )
                   , ( "weapon", Encode.object (( "energyCost", Encode.int c.weaponEnergyCost ) :: weaponFacts ship) )
                   , ( "specialEnergyCost", Encode.int c.specialEnergyCost )
                   ]

        Memory ->
            changing


hazardLabel : Body -> String
hazardLabel body =
    case body of
        PlanetBody ->
            "planet"

        AsteroidBody ->
            "asteroid"

        CrewBody _ ->
            "crew pod"

        _ ->
            "enemy weapon"


{-| Hostile or neutral-dangerous elements. One pass over the arena.
-}
hazards : Side -> Arena -> List Element
hazards side arena =
    arena.elements
        |> Dict.values
        |> List.filter
            (\el ->
                case el.body of
                    ShipBody _ ->
                        False

                    WreckBody _ ->
                        False

                    ExplosionBody ->
                        False

                    BlastBody ->
                        False

                    WarpInBody ->
                        False

                    IonTrailBody ->
                        False

                    PlanetBody ->
                        True

                    AsteroidBody ->
                        True

                    CrewBody _ ->
                        True

                    _ ->
                        el.owner /= Owned side
            )


maxHazards : Int
maxHazards =
    10


{-| One moment of the duel from `side`'s seat: frame, both ships and the
nearest hazards. `Nothing` when a ship is missing (between rounds).
-}
snapshot : Detail -> Side -> Arena -> Maybe Encode.Value
snapshot detail side arena =
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

        element ship =
            Dict.get (toInt (State.core ship).element) arena.elements
    in
    Maybe.map2
        (\ownEl foeEl ->
            let
                own =
                    kinematics ownEl

                foe =
                    kinematics foeEl

                (Facing facing) =
                    (State.core ownShip).facing

                (Facing foeFacing) =
                    (State.core foeShip).facing

                rel =
                    relative detail arena.space facing own

                hazardRows =
                    hazards side arena
                        |> List.map
                            (\el ->
                                let
                                    body =
                                        kinematics el

                                    dx =
                                        toFloat (Trig.wrapDelta (round (body.x - own.x)) arena.space.width)

                                    dy =
                                        toFloat (Trig.wrapDelta (round (body.y - own.y)) arena.space.height)
                                in
                                ( dx * dx + dy * dy, el, body )
                            )
                        |> List.sortBy (\( rangeSq, _, _ ) -> rangeSq)
                        |> List.take maxHazards
                        |> List.map (\( _, el, body ) -> Encode.object (( "what", Encode.string (hazardLabel el.body) ) :: rel body))

                (FrameCount frame) =
                    arena.frame

                foeToUs =
                    offNose foeFacing
                        (toFloat (Trig.wrapDelta (round (own.x - foe.x)) arena.space.width))
                        (toFloat (Trig.wrapDelta (round (own.y - foe.y)) arena.space.height))
            in
            Encode.object
                [ ( "frame", Encode.int frame )
                , ( "you", Encode.object (shipFacts detail ownShip ownEl own) )
                , ( "enemy", Encode.object (shipFacts detail foeShip foeEl foe ++ rel foe ++ [ ( "youOffItsNoseDeg", int foeToUs ) ]) )
                , ( "hazards", Encode.list identity hazardRows )
                ]
        )
        (element ownShip)
        (element foeShip)


{-| An arena as it was when an earlier call left.
-}
type alias Past =
    { atMs : Float, arena : Arena }


{-| Keep enough history to reach back past three seconds, newest first.
Bounded both by age and by count, so it never grows with game length.
-}
remember : Float -> Arena -> List Past -> List Past
remember nowMs arena past =
    { atMs = nowMs, arena = arena }
        :: List.filter (\entry -> nowMs - entry.atMs <= historyMs) past
        |> List.take maxPast


historyMs : Float
historyMs =
    4000


maxPast : Int
maxPast =
    16


{-| The past moment closest to (but at least) three seconds back, or the
oldest one kept while the fight is younger than that.
-}
threeSecondsBack : Float -> List Past -> Maybe Past
threeSecondsBack nowMs past =
    case List.filter (\entry -> nowMs - entry.atMs >= 3000) past of
        found :: _ ->
            Just found

        [] ->
            List.reverse past |> List.head


{-| The full state for one call: rules and timing once, the live moment,
the moment sent with the previous call and the one about three seconds ago.
-}
state : Float -> Maybe Float -> Side -> Arena -> List Past -> Maybe Encode.Value
state nowMs averagePingMs side arena past =
    let
        pingMs =
            Maybe.withDefault 500 averagePingMs

        leadFrames =
            pingMs / 1000 * battleFramesPerSecond

        earlier label entry =
            case entry of
                Just moment ->
                    case snapshot Memory side moment.arena of
                        Just picture ->
                            [ ( label
                              , Encode.object
                                    [ ( "secondsAgo", num ((nowMs - moment.atMs) / 1000) )
                                    , ( "snapshot", picture )
                                    ]
                              )
                            ]

                        Nothing ->
                            []

                Nothing ->
                    []
    in
    snapshot (Live leadFrames) side arena
        |> Maybe.map
            (\now ->
                Encode.object
                    ([ ( "game", Encode.string "Star Control II: The Ur-Quan Masters, Super Melee: a 1v1 starship duel in a wrapping arena, seen from above. Win by reducing the enemy's crew (hit points) to 0 before yours. Energy regenerates and pays for weapon and special. Ships drift with inertia; thrust accelerates along the nose; planet gravity can fling ships past max speed." )
                     , ( "units", Encode.string "Distances in world units; speeds in world units per battle frame (24 frames per second); angles in degrees, compass 0 = up, clockwise. bearing = degrees off your nose, 0 dead ahead, positive to your right. closing > 0 means approaching. cpa = closest point of approach if nothing changes. *ReadyIn in frames." )
                     , ( "timing"
                       , Encode.object
                            [ ( "avgRoundTripMs", int pingMs )
                            , ( "inputLandsInFrames", int leadFrames )
                            , ( "note", Encode.string "Your answer is applied about inputLandsInFrames after 'now' and held until the next answer: aim and dodge for rangeAtLanding / bearingAtLanding." )
                            ]
                       )
                     , ( "now", now )
                     ]
                        ++ earlier "previous" (List.head past)
                        ++ earlier "threeSecondsAgo" (threeSecondsBack nowMs past)
                    )
            )



-- QUESTIONS


questions : Encode.Value
questions =
    let
        yesNo instructions yes no =
            Encode.object
                [ ( "type", Encode.string "boolean" )
                , ( "instructions", Encode.string instructions )
                , ( "criteria", Encode.object [ ( "true", Encode.string yes ), ( "false", Encode.string no ) ] )
                ]
    in
    Encode.object
        [ ( "turn"
          , Encode.object
                [ ( "type", Encode.string "choice" )
                , ( "instructions", Encode.string "You are piloting the ship called 'you' in this Star Control II melee. Which way should you rotate for the next moment?" )
                , ( "criteria"
                  , Encode.object
                        [ ( "none", Encode.string "Hold heading: the nose already points where you want to shoot or fly" )
                        , ( "left", Encode.string "Rotate counter-clockwise (toward negative bearingFromNoseDeg)" )
                        , ( "right", Encode.string "Rotate clockwise (toward positive bearingFromNoseDeg)" )
                        ]
                  )
                ]
          )
        , ( "thrust", yesNo "Should you hold thrust (accelerate along your nose) for the next moment?" "Accelerating along the current nose direction helps you close for a kill, escape a threat, dodge an incoming projectile, or avoid the planet" "Coasting is better: thrusting would carry you into danger, overshoot, or waste the moment" )
        , ( "fire", yesNo "Should you hold fire on your primary weapon for the next moment?" "The weapon can fire and a shot along the nose is likely to hit the enemy where it will be, or you need to shoot down incoming projectiles" "The shot would miss, the weapon is not ready, or the energy is better saved" )
        , ( "special", yesNo "Should you use your special ability for the next moment?" "The special is ready and using it now clearly helps: it would hit, save you, or turn the fight" "Save it: it would be wasted or the energy is needed" )
        ]


answerDecoder : Decoder Answer
answerDecoder =
    let
        probability name =
            Decode.at [ "answers", name, "probability" ] Decode.float

        turn =
            Decode.at [ "answers", "turn", "choice" ] Decode.string
                |> Decode.andThen
                    (\code ->
                        case code of
                            "none" ->
                                Decode.succeed NoTurn

                            "left" ->
                                Decode.succeed TurnLeft

                            "right" ->
                                Decode.succeed TurnRight

                            other ->
                                Decode.fail ("Unknown Jev turn: " ++ other)
                    )
    in
    Decode.map5 Answer
        turn
        (probability "thrust")
        (probability "fire")
        (probability "special")
        (Decode.oneOf [ Decode.at [ "answers", "turn", "confidence" ] Decode.float, Decode.succeed 0 ])
