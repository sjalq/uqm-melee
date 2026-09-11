port module Oracle.NeatTrace exposing (main)

{-| Streaming differential oracle for the Rust evaluator. Each stdin job uses
the same policy preparation and `LongGame.nextEvent` path as `Neat.Eval`, then
emits one compact JSON line per event.
-}

import Dict
import Helpers.LongGame as LongGame
import Json.Decode as D
import Json.Encode as E
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Element exposing (..)
import Melee.Id exposing (ElementId(..), toInt)
import Melee.Input exposing (BattleInput, CyborgRating(..), Turn(..))
import Melee.Local as Game
import Melee.Projectile as Projectile
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (Characteristics, ShipKind(..))
import Melee.ShipState as State exposing (..)
import Melee.Strategy as Strategy
import Melee.Units exposing (Facing(..), Side(..), VelocityDesc, Wait(..), WorldExtent, WorldPoint)
import Neat.Encode as Encode
import Neat.Policy as Policy
import Platform


port request : (String -> msg) -> Sub msg


port response : String -> Cmd msg


port advance : (() -> msg) -> Sub msg


type alias Job =
    { weights : List Float
    , seed : Int
    , ticks : Int
    , swap : Bool
    , rating : String
    , us : String
    , them : String
    , foe : String
    }


type alias Memory =
    { extraBottom : List Float
    , extraTop : List Float
    , round : Int
    , shipBottom : String
    , shipTop : String
    }


type Model
    = Idle
    | Running Run


type alias Run =
    { job : Job
    , net : Policy.Net
    , us : Side
    , ratings : { bottom : CyborgRating, top : CyborgRating }
    , game : Game.Model
    , memory : Memory
    , ticks : Int
    , event : Int
    , started : Bool
    }


type Msg
    = Start String
    | Continue


type alias PolicyTrace =
    { bottom : SideTrace
    , top : SideTrace
    }


type alias SideTrace =
    { observation : List Float
    , feedbackIn : List Float
    , input : BattleInput
    , extra : List Float
    , feedbackOut : List Float
    , ship : String
    }


main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( Idle, Cmd.none )
        , update = update
        , subscriptions = \_ -> Sub.batch [ request Start, advance (\_ -> Continue) ]
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Start raw ->
            case D.decodeString jobDecoder raw of
                Err err ->
                    ( model, emit (E.object [ ( "type", E.string "error" ), ( "error", E.string (D.errorToString err) ) ]) )

                Ok job ->
                    case Policy.load job.weights of
                        Nothing ->
                            ( model
                            , emit
                                (E.object
                                    [ ( "type", E.string "error" )
                                    , ( "error", E.string ("weight length " ++ String.fromInt (List.length job.weights) ++ " != " ++ String.fromInt Policy.weightCount) )
                                    ]
                                )
                            )

                        Just net ->
                            let
                                run =
                                    begin job net
                            in
                            ( Running run, emit (header run) )

        Continue ->
            case model of
                Idle ->
                    ( Idle, Cmd.none )

                Running run ->
                    if not run.started then
                        let
                            started =
                                { run | started = True }
                        in
                        ( Running started, emit (snapshot "event" 0 0 Nothing started) )

                    else if finished run then
                        ( Idle, emit (done run) )

                    else
                        let
                            ( pilots, memory, policy ) =
                                prepare run.net run.us run.job.foe run.game run.memory

                            ( elapsed, game ) =
                                LongGame.nextEvent pilots run.ratings (run.job.ticks - run.ticks) run.game

                            next =
                                { run
                                    | game = game
                                    , memory = memory
                                    , ticks = run.ticks + elapsed
                                    , event = run.event + 1
                                }

                        in
                        ( Running next, emit (snapshot "event" next.event elapsed policy next) )


emit : E.Value -> Cmd msg
emit value =
    response (E.encode 0 value)


begin : Job -> Policy.Net -> Run
begin job net =
    let
        us =
            if job.swap then
                Top

            else
                Bottom

        usKind =
            kindFrom job.us

        themKind =
            kindFrom job.them

        fleets =
            if job.swap then
                { bottom = [ themKind ], top = [ usKind ] }

            else
                { bottom = [ usKind ], top = [ themKind ] }

        rating =
            cyborgRating job.rating
    in
    { job = job
    , net = net
    , us = us
    , ratings = { bottom = rating, top = rating }
    , game = LongGame.start job.seed fleets.bottom fleets.top
    , memory = { extraBottom = Policy.zeroExtra, extraTop = Policy.zeroExtra, round = -1, shipBottom = "", shipTop = "" }
    , ticks = 0
    , event = 0
    , started = False
    }


finished : Run -> Bool
finished run =
    run.ticks >= run.job.ticks
        || (case run.game.phase of
                Game.Victory _ ->
                    True

                _ ->
                    False
           )


prepare : Policy.Net -> Side -> String -> Game.Model -> Memory -> ( Strategy.Pilots, Memory, Maybe PolicyTrace )
prepare net us foe game memory =
    case game.phase of
        Game.Combat arena ->
            let
                bottom =
                    policySide net Bottom arena memory.extraBottom game.round memory.shipBottom memory.round

                top =
                    policySide net Top arena memory.extraTop game.round memory.shipTop memory.round

                pilots =
                    if foe == "self" then
                        { bottom = \_ -> Strategy.controls (decide bottom.input)
                        , top = \_ -> Strategy.controls (decide top.input)
                        }

                    else if us == Bottom then
                        { bottom = \_ -> Strategy.controls (decide bottom.input)
                        , top = Strategy.originalRoster
                        }

                    else
                        { bottom = Strategy.originalRoster
                        , top = \_ -> Strategy.controls (decide top.input)
                        }
            in
            ( pilots
            , { extraBottom = bottom.extra
              , extraTop = top.extra
              , round = game.round
              , shipBottom = bottom.ship
              , shipTop = top.ship
              }
            , Just { bottom = bottom, top = top }
            )

        _ ->
            ( Strategy.originalPilots, memory, Nothing )


policySide : Policy.Net -> Side -> Arena -> List Float -> Int -> String -> Int -> SideTrace
policySide net side arena extra round previousName previousRound =
    let
        ship =
            if side == Bottom then
                arena.combatants.bottom

            else
                arena.combatants.top

        name =
            (Catalog.info (State.kind ship)).name

        extraIn =
            if round /= previousRound || name /= previousName then
                Policy.zeroExtra

            else
                extra

        observation =
            Encode.vector side arena

        feedbackIn =
            Policy.actionsFrom (State.core ship).oldInput ++ extraIn

        stepped =
            Policy.step net observation feedbackIn
    in
    { observation = observation
    , feedbackIn = feedbackIn
    , input = stepped.input
    , extra = stepped.extra
    , feedbackOut = stepped.feedback
    , ship = name
    }


decide : BattleInput -> Strategy.Context -> ( BattleInput, Seed )
decide input context =
    ( input, context.seed )


header : Run -> E.Value
header run =
    E.object
        [ ( "type", E.string "header" )
        , ( "schema", E.string "uqm-neat-trace-v1" )
        , ( "seed", E.int run.job.seed )
        , ( "tick_limit", E.int run.job.ticks )
        , ( "swap", E.bool run.job.swap )
        , ( "rating", E.string run.job.rating )
        , ( "us", E.string run.job.us )
        , ( "them", E.string run.job.them )
        , ( "foe", E.string run.job.foe )
        , ( "weight_count", E.int (List.length run.job.weights) )
        ]


done : Run -> E.Value
done run =
    E.object
        [ ( "type", E.string "done" )
        , ( "events", E.int run.event )
        , ( "display_ticks", E.int run.ticks )
        , ( "phase", E.string (phaseName run.game.phase) )
        , ( "round", E.int run.game.round )
        ]


snapshot : String -> Int -> Int -> Maybe PolicyTrace -> Run -> E.Value
snapshot recordType event elapsed policy run =
    let
        game =
            run.game

        ( arenaSource, arena ) =
            arenaFor game
    in
    E.object
        [ ( "type", E.string recordType )
        , ( "event", E.int event )
        , ( "display_ticks", E.int run.ticks )
        , ( "elapsed", E.int elapsed )
        , ( "round", E.int game.round )
        , ( "phase", phase game.phase )
        , ( "game_seed", seed game.seed )
        , ( "remaining", sided (E.list shipKind game.remaining.bottom) (E.list shipKind game.remaining.top) )
        , ( "arena_source", E.string arenaSource )
        , ( "arena", maybe arenaValue arena )
        , ( "memory", memoryValue run.memory )
        , ( "policy", maybe policyValue policy )
        ]


arenaFor : Game.Model -> ( String, Maybe Arena )
arenaFor game =
    case Game.phaseArena game.phase of
        Just arena ->
            ( "phase", Just arena )

        Nothing ->
            case game.survivor of
                Just arena ->
                    ( "survivor", Just arena )

                Nothing ->
                    ( "none", Nothing )


memoryValue : Memory -> E.Value
memoryValue memory =
    E.object
        [ ( "extra_bottom", E.list E.float memory.extraBottom )
        , ( "extra_top", E.list E.float memory.extraTop )
        , ( "round", E.int memory.round )
        , ( "ship_bottom", E.string memory.shipBottom )
        , ( "ship_top", E.string memory.shipTop )
        ]


policyValue : PolicyTrace -> E.Value
policyValue policy =
    sided (sideTrace policy.bottom) (sideTrace policy.top)


sideTrace : SideTrace -> E.Value
sideTrace trace =
    E.object
        [ ( "ship", E.string trace.ship )
        , ( "observation", E.list E.float trace.observation )
        , ( "feedback_in", E.list E.float trace.feedbackIn )
        , ( "input", battleInput trace.input )
        , ( "extra", E.list E.float trace.extra )
        , ( "feedback_out", E.list E.float trace.feedbackOut )
        ]


arenaValue : Arena -> E.Value
arenaValue arena =
    let
        (Seed seedValue) =
            arena.seed
    in
    E.object
        [ ( "frame", frameCount arena.frame )
        , ( "pump_acc", E.int arena.pumpAcc )
        , ( "seed", E.int seedValue )
        , ( "space", extent arena.space )
        , ( "combatants", sided (combatant arena.combatants.bottom) (combatant arena.combatants.top) )
        , ( "elements", E.list element (Dict.values arena.elements) )
        , ( "queue", E.list (\id -> E.int (toInt id)) arena.queue )
        , ( "next_element_id", E.int arena.nextElementId )
        , ( "previous_locations"
          , E.list
                (\( id, location ) -> E.list identity [ E.int id, point location ])
                (Dict.toList arena.previousLocations)
          )
        ]


combatant : Combatant -> E.Value
combatant live =
    let
        tagged name extra =
            E.object [ ( "tag", E.string name ), ( "core", core (State.core live) ), ( "extra", extra ) ]
    in
    case live of
        LiveAndrosynth _ Guardian ->
            tagged "Androsynth" (tag "Guardian")

        LiveAndrosynth _ (Blazer data) ->
            tagged "Androsynth" (E.object [ ( "tag", E.string "Blazer" ), ( "guardian", characteristics data.guardian ) ])

        LiveArilou _ Present ->
            tagged "Arilou" (tag "Present")

        LiveArilou _ (Teleporting wait) ->
            tagged "Arilou" (E.object [ ( "tag", E.string "Teleporting" ), ( "wait", waitValue wait ) ])

        LiveChenjesu _ ->
            tagged "Chenjesu" E.null

        LiveChmmr _ extra ->
            tagged "Chmmr" (tag (if extra == TractorIdle then "TractorIdle" else "TractorOn"))

        LiveDruuge _ ->
            tagged "Druuge" E.null

        LiveEarthling _ ->
            tagged "Earthling" E.null

        LiveIlwrath _ ->
            tagged "Ilwrath" E.null

        LiveKohrAh _ ->
            tagged "KohrAh" E.null

        LiveMelnorme _ extra ->
            tagged "Melnorme"
                (E.object
                    [ ( "pump", E.string (pumpLevel extra.pump) )
                    , ( "level_counter", waitValue extra.levelCounter )
                    ]
                )

        LiveMmrnmhrm _ extra ->
            tagged "Mmrnmhrm"
                (E.object
                    [ ( "form", E.string (if extra.form == XWing then "XWing" else "YWing") )
                    , ( "other_wing", characteristics extra.otherWing )
                    ]
                )

        LiveMycon _ ->
            tagged "Mycon" E.null

        LiveOrz _ extra ->
            tagged "Orz" (E.object [ ( "turret_facing", facingValue extra.turretFacing ), ( "turret_wait", waitValue extra.turretWait ) ])

        LivePkunk _ Flying ->
            tagged "Pkunk" (tag "Flying")

        LivePkunk _ (Phoenix id) ->
            tagged "Pkunk" (E.object [ ( "tag", E.string "Phoenix" ), ( "element", E.int (toInt id) ) ])

        LiveShofixti _ extra ->
            tagged "Shofixti" (tag (shofixtiExtra extra))

        LiveSlylandro _ ->
            tagged "Slylandro" E.null

        LiveSpathi _ ->
            tagged "Spathi" E.null

        LiveSupox _ ForwardOnly ->
            tagged "Supox" (tag "ForwardOnly")

        LiveSupox _ (Strafing turn) ->
            tagged "Supox" (E.object [ ( "tag", E.string "Strafing" ), ( "turn", E.string (turnValue turn) ) ])

        LiveSyreen _ ->
            tagged "Syreen" E.null

        LiveThraddash _ Cruise ->
            tagged "Thraddash" (tag "Cruise")

        LiveThraddash _ (Afterburning data) ->
            tagged "Thraddash"
                (E.object
                    [ ( "tag", E.string "Afterburning" )
                    , ( "saved_max_thrust", E.int data.savedMaxThrust )
                    , ( "saved_thrust_increment", E.int data.savedThrustIncrement )
                    ]
                )

        LiveUmgah _ extra ->
            tagged "Umgah" (E.object [ ( "prev_facing", facingValue extra.prevFacing ) ])

        LiveUrQuan _ ->
            tagged "UrQuan" E.null

        LiveUtwig _ ->
            tagged "Utwig" E.null

        LiveVux _ extra ->
            tagged "Vux" (tag (if extra == WarpPending then "WarpPending" else "OnField"))

        LiveYehat _ ->
            tagged "Yehat" E.null

        LiveZoqFotPik _ ->
            tagged "ZoqFotPik" E.null


core : CombatantCore -> E.Value
core value =
    E.object
        [ ( "element", E.int (toInt value.element) )
        , ( "characteristics", characteristics value.characteristics )
        , ( "energy", E.int value.energy )
        , ( "max_energy", E.int value.maxEnergy )
        , ( "max_crew", E.int value.maxCrew )
        , ( "weapon_wait", waitValue value.weaponWait )
        , ( "special_wait", waitValue value.specialWait )
        , ( "energy_wait", waitValue value.energyWait )
        , ( "facing", facingValue value.facing )
        , ( "input", battleInput value.input )
        , ( "shield_ticks", E.int value.shieldTicks )
        , ( "confused_ticks", E.int value.confusedTicks )
        , ( "charge_ticks", E.int value.chargeTicks )
        , ( "cloaked", E.bool value.cloaked )
        , ( "old_input", battleInput value.oldInput )
        , ( "flags", motionFlags value.flags )
        ]


characteristics : Characteristics -> E.Value
characteristics value =
    E.object
        [ ( "max_thrust", E.int value.maxThrust )
        , ( "thrust_increment", E.int value.thrustIncrement )
        , ( "energy_regeneration", E.int value.energyRegeneration )
        , ( "weapon_energy_cost", E.int value.weaponEnergyCost )
        , ( "special_energy_cost", E.int value.specialEnergyCost )
        , ( "energy_wait", waitValue value.energyWait )
        , ( "turn_wait", waitValue value.turnWait )
        , ( "thrust_wait", waitValue value.thrustWait )
        , ( "weapon_wait", waitValue value.weaponWait )
        , ( "special_wait", waitValue value.specialWait )
        , ( "ship_mass", E.int value.shipMass )
        ]


motionFlags : MotionFlags -> E.Value
motionFlags value =
    E.object
        [ ( "low_on_energy", E.bool value.lowOnEnergy )
        , ( "beyond_max_speed", E.bool value.beyondMaxSpeed )
        , ( "at_max_speed", E.bool value.atMaxSpeed )
        , ( "in_gravity_well", E.bool value.inGravityWell )
        , ( "play_victory_ditty", E.bool value.playVictoryDitty )
        ]


element : Element -> E.Value
element value =
    E.object
        [ ( "id", E.int (toInt value.id) )
        , ( "owner", owner value.owner )
        , ( "parent", maybe sideValue value.parent )
        , ( "target", maybe (\id -> E.int (toInt id)) value.target )
        , ( "flags", elementFlags value.flags )
        , ( "life", life value.life )
        , ( "points", E.int value.points )
        , ( "mass", E.int value.mass )
        , ( "turn_wait", waitValue value.turnWait )
        , ( "thrust_wait", waitValue value.thrustWait )
        , ( "color_cycle_index", E.int value.colorCycleIndex )
        , ( "velocity", velocity value.velocity )
        , ( "intersect", intersect value.intersect )
        , ( "current", image value.current )
        , ( "next", image value.next )
        , ( "prim", prim value.prim )
        , ( "projectile", maybe projectile value.projectile )
        , ( "body", body value.body )
        ]


elementFlags : ElementFlags -> E.Value
elementFlags value =
    E.object
        [ ( "player_ship", E.bool value.playerShip )
        , ( "appearing", E.bool value.appearing )
        , ( "disappearing", E.bool value.disappearing )
        , ( "changing", E.bool value.changing )
        , ( "nonsolid", E.bool value.nonsolid )
        , ( "collision", E.bool value.collision )
        , ( "ignore_similar", E.bool value.ignoreSimilar )
        , ( "defy_physics", E.bool value.defyPhysics )
        , ( "finite_life", E.bool value.finiteLife )
        , ( "pre_process", E.bool value.preProcess )
        , ( "post_process", E.bool value.postProcess )
        , ( "ignore_velocity", E.bool value.ignoreVelocity )
        , ( "crew_object", E.bool value.crewObject )
        , ( "background_object", E.bool value.backgroundObject )
        ]


velocity : VelocityDesc -> E.Value
velocity value =
    E.object
        [ ( "travel_angle", angleValue value.travelAngle )
        , ( "vector", extent value.vector )
        , ( "fract", extent value.fract )
        , ( "error", extent value.error )
        , ( "incr", extent value.incr )
        ]


intersect : IntersectControl -> E.Value
intersect value =
    E.object
        [ ( "last_time_val", E.int value.lastTimeVal )
        , ( "end_point", point value.endPoint )
        , ( "stamp_origin", point value.stampOrigin )
        ]


image : Image -> E.Value
image value =
    E.object [ ( "location", point value.location ), ( "frame_index", E.int value.frameIndex ) ]


projectile : Projectile.State -> E.Value
projectile value =
    case value of
        Projectile.Flying kind data ->
            E.object
                [ ( "tag", E.string "Flying" )
                , ( "kind", E.string (missileKind kind) )
                , ( "age", E.int data.age )
                , ( "facing", facingValue data.facing )
                , ( "tracking_wait", E.int data.trackingWait )
                ]

        Projectile.Charging data ->
            E.object [ ( "tag", E.string "Charging" ), ( "ticks", E.int data.ticks ), ( "facing", facingValue data.facing ) ]

        Projectile.Ray kind data ->
            E.object [ ( "tag", E.string "Ray" ), ( "kind", E.string (beamKind kind) ), ( "origin", point data.origin ), ( "end", point data.end ) ]

        Projectile.Attached kind data ->
            E.object [ ( "tag", E.string "Attached" ), ( "kind", E.string (contactKind kind) ), ( "age", E.int data.age ), ( "facing", facingValue data.facing ) ]

        Projectile.LightningSegment data ->
            E.object [ ( "tag", E.string "LightningSegment" ), ( "origin", point data.origin ), ( "end", point data.end ) ]


body : Body -> E.Value
body value =
    case value of
        ShipBody side ->
            payload "Ship" "side" (sideValue side)

        WreckBody side ->
            payload "Wreck" "side" (sideValue side)

        CrewBody data ->
            payload "Crew" "origin" (sideValue data.origin)

        WeaponImpact kind ->
            payload "WeaponImpact" "kind" (E.string (missileKind kind))

        ChmmrSatellite data ->
            payload "ChmmrSatellite" "orbit_facing" (facingValue data.orbitFacing)

        PlanetBody ->
            tag "Planet"

        AsteroidBody ->
            tag "Asteroid"

        BlastBody ->
            tag "Blast"

        ExplosionBody ->
            tag "Explosion"

        WarpInBody ->
            tag "WarpIn"

        IonTrailBody ->
            tag "IonTrail"

        AndrosynthBubble -> tag "AndrosynthBubble"
        ArilouLaser -> tag "ArilouLaser"
        ChenjesuPhoton -> tag "ChenjesuPhoton"
        ChenjesuFragment -> tag "ChenjesuFragment"
        ChenjesuDogi -> tag "ChenjesuDogi"
        ChmmrLaser -> tag "ChmmrLaser"
        ChmmrZap -> tag "ChmmrZap"
        DruugeHotShot -> tag "DruugeHotShot"
        EarthlingNuke -> tag "EarthlingNuke"
        EarthlingPointDefense -> tag "EarthlingPointDefense"
        IlwrathFlame -> tag "IlwrathFlame"
        KohrAhSaw -> tag "KohrAhSaw"
        KohrAhFried -> tag "KohrAhFried"
        MelnormeCharge -> tag "MelnormeCharge"
        MelnormeConfusion -> tag "MelnormeConfusion"
        MmrnmhrmLaser -> tag "MmrnmhrmLaser"
        MmrnmhrmMissile -> tag "MmrnmhrmMissile"
        MyconPlasma -> tag "MyconPlasma"
        OrzHowitzer -> tag "OrzHowitzer"
        OrzMarine -> tag "OrzMarine"
        PkunkSpread -> tag "PkunkSpread"
        ShofixtiDart -> tag "ShofixtiDart"
        ShofixtiGlory -> tag "ShofixtiGlory"
        SlylandroLightning -> tag "SlylandroLightning"
        SpathiForward -> tag "SpathiForward"
        SpathiButt -> tag "SpathiButt"
        SupoxPellet -> tag "SupoxPellet"
        SyreenMissile -> tag "SyreenMissile"
        ThraddashBlaster -> tag "ThraddashBlaster"
        ThraddashAfterburn -> tag "ThraddashAfterburn"
        UmgahCone -> tag "UmgahCone"
        UrQuanFusion -> tag "UrQuanFusion"
        UrQuanFighter -> tag "UrQuanFighter"
        UrQuanFighterLaser -> tag "UrQuanFighterLaser"
        UtwigGizmo -> tag "UtwigGizmo"
        VuxLaser -> tag "VuxLaser"
        VuxLimpet -> tag "VuxLimpet"
        YehatMissile -> tag "YehatMissile"
        ZoqSpit -> tag "ZoqSpit"
        ZoqTongue -> tag "ZoqTongue"


phase : Game.Phase -> E.Value
phase value =
    case value of
        Game.Selecting bottom top ->
            E.object
                [ ( "tag", E.string "Selecting" )
                , ( "bottom", maybe shipKind bottom )
                , ( "top", maybe shipKind top )
                ]

        Game.Countdown ticks _ ->
            payload "Countdown" "ticks" (E.int ticks)

        Game.RoundOver ticks _ ->
            payload "RoundOver" "ticks" (E.int ticks)

        Game.Victory winner ->
            payload "Victory" "winner" (maybe sideValue winner)

        Game.Hangar -> tag "Hangar"
        Game.Combat _ -> tag "Combat"
        Game.Paused _ -> tag "Paused"


phaseName : Game.Phase -> String
phaseName value =
    case value of
        Game.Hangar -> "Hangar"
        Game.Selecting _ _ -> "Selecting"
        Game.Countdown _ _ -> "Countdown"
        Game.Combat _ -> "Combat"
        Game.Paused _ -> "Paused"
        Game.RoundOver _ _ -> "RoundOver"
        Game.Victory _ -> "Victory"


life : Life -> E.Value
life value =
    case value of
        Persistent ticks -> payload "Persistent" "ticks" (E.int ticks)
        Finite ticks -> payload "Finite" "ticks" (E.int ticks)


owner : Owner -> E.Value
owner value =
    case value of
        Neutral -> E.int -1
        Owned side -> sideValue side


prim : Prim -> E.Value
prim value =
    case value of
        NoPrim -> tag "NoPrim"
        Stamp -> tag "Stamp"
        StampFill data -> E.object [ ( "tag", E.string "StampFill" ), ( "black", E.bool data.black ) ]
        Line -> tag "Line"


battleInput : BattleInput -> E.Value
battleInput value =
    E.object
        [ ( "turn", E.string (turnValue value.turn) )
        , ( "thrust", E.bool value.thrust )
        , ( "weapon", E.bool value.weapon )
        , ( "special", E.bool value.special )
        ]


turnValue : Turn -> String
turnValue value =
    case value of
        NoTurn -> "NoTurn"
        TurnLeft -> "TurnLeft"
        TurnRight -> "TurnRight"


point : WorldPoint -> E.Value
point value =
    E.list E.int [ value.x, value.y ]


extent : WorldExtent -> E.Value
extent value =
    E.list E.int [ value.width, value.height ]


seed : Seed -> E.Value
seed (Seed value) =
    E.int value


frameCount value =
    case value of
        Melee.Units.FrameCount ticks ->
            E.int ticks


waitValue : Wait -> E.Value
waitValue (Wait value) =
    E.int value


facingValue : Facing -> E.Value
facingValue (Facing value) =
    E.int value


angleValue value =
    case value of
        Melee.Units.Angle angle ->
            E.int angle


sideValue : Side -> E.Value
sideValue value =
    E.int
        (case value of
            Bottom -> 0
            Top -> 1
        )


sided : E.Value -> E.Value -> E.Value
sided bottom top =
    E.object [ ( "bottom", bottom ), ( "top", top ) ]


maybe : (a -> E.Value) -> Maybe a -> E.Value
maybe encode value =
    Maybe.map encode value |> Maybe.withDefault E.null


tag : String -> E.Value
tag name =
    E.object [ ( "tag", E.string name ) ]


payload : String -> String -> E.Value -> E.Value
payload name field value =
    E.object [ ( "tag", E.string name ), ( field, value ) ]


pumpLevel : PumpLevel -> String
pumpLevel value =
    case value of
        Pump1 -> "Pump1"
        Pump2 -> "Pump2"
        Pump3 -> "Pump3"
        Pump4 -> "Pump4"


shofixtiExtra : ShofixtiExtra -> String
shofixtiExtra value =
    case value of
        SafetyClosed -> "SafetyClosed"
        OpeningSafety -> "OpeningSafety"
        SafetyOpen -> "SafetyOpen"
        ArmingDevice -> "ArmingDevice"
        Armed -> "Armed"
        GloryDevice -> "GloryDevice"


shipKind : ShipKind -> E.Value
shipKind value =
    E.string (Catalog.info value).name


missileKind : Projectile.MissileKind -> String
missileKind value =
    Debug.toString value


beamKind : Projectile.BeamKind -> String
beamKind value =
    Debug.toString value


contactKind : Projectile.ContactKind -> String
contactKind value =
    Debug.toString value


cyborgRating : String -> CyborgRating
cyborgRating raw =
    case raw of
        "standard" -> StandardCyborg
        "good" -> GoodCyborg
        _ -> AwesomeCyborg


kindFrom : String -> ShipKind
kindFrom raw =
    case String.toLower raw of
        "androsynth" -> Androsynth
        "arilou" -> Arilou
        "chenjesu" -> Chenjesu
        "chmmr" -> Chmmr
        "druuge" -> Druuge
        "earthling" -> Earthling
        "ilwrath" -> Ilwrath
        "kohr-ah" -> KohrAh
        "kohrah" -> KohrAh
        "melnorme" -> Melnorme
        "mmrnmhrm" -> Mmrnmhrm
        "mycon" -> Mycon
        "orz" -> Orz
        "pkunk" -> Pkunk
        "shofixti" -> Shofixti
        "slylandro" -> Slylandro
        "spathi" -> Spathi
        "supox" -> Supox
        "syreen" -> Syreen
        "thraddash" -> Thraddash
        "umgah" -> Umgah
        "ur-quan" -> UrQuan
        "urquan" -> UrQuan
        "utwig" -> Utwig
        "vux" -> Vux
        "yehat" -> Yehat
        "zoq-fot-pik" -> ZoqFotPik
        "zoqfotpik" -> ZoqFotPik
        _ -> Pkunk


jobDecoder : D.Decoder Job
jobDecoder =
    D.map8 Job
        (D.field "weights" (D.list D.float))
        (D.field "seed" D.int)
        (D.field "ticks" D.int)
        (D.oneOf [ D.field "swap" D.bool, D.succeed False ])
        (D.oneOf [ D.field "rating" D.string, D.succeed "awesome" ])
        (D.oneOf [ D.field "us" D.string, D.succeed "Pkunk" ])
        (D.oneOf [ D.field "them" D.string, D.succeed "Umgah" ])
        (D.oneOf [ D.field "foe" D.string, D.succeed "cyborg" ])
