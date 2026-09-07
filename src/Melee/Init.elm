module Melee.Init exposing (arena, combatant, emptyFlags, shofixtiArena, sided)

{-| Spawn a Super Melee arena with two Shofixti and a planet.
-}

import Dict
import Melee.Battle exposing (Arena)
import Melee.Element exposing (Body(..), Element, ElementFlags, Life(..), Owner(..), Prim(..))
import Melee.Id exposing (ElementId(..))
import Melee.Input exposing (idle)
import Melee.Rng as Rng exposing (Seed)
import Melee.Ship exposing (ShipKind(..), Stock, mmrnmhrmYWing, stock)
import Melee.ShipState exposing (..)
import Melee.Trig as Trig
import Melee.Units exposing (Facing(..), FrameCount(..), Side(..), Sided, Wait(..), WorldPoint, stockLogSpace)
import Melee.Velocity as Velocity


emptyFlags : ElementFlags
emptyFlags =
    { playerShip = False
    , appearing = False
    , disappearing = False
    , changing = False
    , nonsolid = False
    , collision = False
    , ignoreSimilar = False
    , defyPhysics = False
    , finiteLife = False
    , preProcess = False
    , postProcess = False
    , ignoreVelocity = False
    , crewObject = False
    , backgroundObject = False
    }


zeroMotion : MotionFlags
zeroMotion =
    { lowOnEnergy = False
    , beyondMaxSpeed = False
    , atMaxSpeed = False
    , inGravityWell = False
    , playVictoryDitty = False
    }


sided : a -> a -> Sided a
sided bottom top =
    { bottom = bottom, top = top }


mkImage : WorldPoint -> Int -> { location : WorldPoint, frameIndex : Int }
mkImage location frameIndex =
    { location = location, frameIndex = frameIndex }


zeroIntersect : { lastTimeVal : Int, endPoint : WorldPoint, stampOrigin : WorldPoint }
zeroIntersect =
    { lastTimeVal = 0
    , endPoint = { x = 0, y = 0 }
    , stampOrigin = { x = 0, y = 0 }
    }


planetElement : ElementId -> WorldPoint -> Element
planetElement id location =
    { id = id
    , owner = Neutral
    , parent = Nothing
    , target = Nothing
    , flags = { emptyFlags | appearing = True }
    , life = Persistent 2
    , points = 200
    , mass = 200
    , turnWait = Wait 0
    , thrustWait = Wait 0
    , colorCycleIndex = 0
    , velocity = Velocity.zero
    , intersect = { zeroIntersect | endPoint = location, stampOrigin = location }
    , current = mkImage location 0
    , next = mkImage location 0
    , projectile = Nothing
    , prim = Stamp
    , body = PlanetBody
    }


shipFlags : ElementFlags
shipFlags =
    { emptyFlags
        | playerShip = True
        , appearing = True
        , ignoreSimilar = True
    }


shipElement : ElementId -> Side -> WorldPoint -> Int -> Int -> Element
shipElement id side location crew facing =
    { id = id
    , owner = Owned side
    , parent = Just side
    , target = Nothing
    , flags = shipFlags
    , life = Persistent 1
    , points = crew
    , mass = 1
    , turnWait = Wait 0
    , thrustWait = Wait 0
    , colorCycleIndex = 0
    , velocity = Velocity.zero
    , intersect = { zeroIntersect | endPoint = location, stampOrigin = location }
    , current = mkImage location facing
    , next = mkImage location facing
    , projectile = Nothing
    , prim = Stamp
    , body = ShipBody side
    }


mkCore : ElementId -> Stock -> Int -> CombatantCore
mkCore elementId spec facing =
    { element = elementId
    , characteristics = spec.characteristics
    , energy = spec.startingEnergy
    , maxEnergy = spec.maxEnergy
    , maxCrew = spec.maxCrew
    , weaponWait = Wait 0
    , specialWait = Wait 0
    , energyWait = Wait 0
    , facing = Facing facing
    , input = idle
    , shieldTicks = 0
    , confusedTicks = 0
    , chargeTicks = 0
    , cloaked = False
    , oldInput = idle
    , flags = zeroMotion
    }


placePlanet : Seed -> ( WorldPoint, Seed )
placePlanet seed0 =
    let
        ( rx, s1 ) =
            Rng.next seed0

        ( ry, s2 ) =
            Rng.next s1

        space =
            stockLogSpace

        align4 n =
            n - modBy 4 n

        x =
            align4 (modBy space.width rx)

        y =
            align4 (modBy space.height ry)
    in
    ( { x = x, y = y }, s2 )


shofixtiArena : Seed -> Arena
shofixtiArena seed0 =
    let
        spec =
            stock Shofixti

        ( _, seed1 ) =
            placePlanet seed0

        planetId =
            ElementId 1

        bottomId =
            ElementId 2

        topId =
            ElementId 3

        -- Y-offset so a facing-4 / facing-12 dart flies past the planet
        -- instead of dying in it, while both scouts start inside the well
        -- (GRAVITY_THRESHOLD = 255 display = 1020 world).
        planetAt =
            { x = 4096, y = 3840 }

        bottomAt =
            { x = 3300, y = 3520 }

        topAt =
            { x = 4900, y = 4160 }

        planet =
            planetElement planetId planetAt

        bottomEl =
            shipElement bottomId Bottom bottomAt spec.startingCrew 4

        topEl =
            shipElement topId Top topAt spec.startingCrew 12

        bottom =
            LiveShofixti (mkCore bottomId spec 4) SafetyClosed

        top =
            LiveShofixti (mkCore topId spec 12) SafetyClosed
    in
    { frame = FrameCount 0
    , previousLocations = Dict.empty
    , pumpAcc = 0
    , seed = seed1
    , space = stockLogSpace
    , combatants = sided bottom top
    , elements =
        Dict.fromList
            [ ( 1, planet )
            , ( 2, bottomEl )
            , ( 3, topEl )
            ]
    , queue = [ planetId, bottomId, topId ]
    , nextElementId = 4
    }


arena : ShipKind -> ShipKind -> Seed -> Arena
arena bottomKind topKind seed =
    let
        original =
            shofixtiArena seed

        replace side id kind facing location =
            let
                spec =
                    stock kind

                el =
                    shipElement (ElementId id) side location spec.startingCrew facing
            in
            { el | mass = spec.characteristics.shipMass }
    in
    { original
        | combatants = sided (combatant bottomKind (mkCore (ElementId 2) (stock bottomKind) 4)) (combatant topKind (mkCore (ElementId 3) (stock topKind) 12))
        , elements =
            original.elements
                |> Dict.insert 2 (replace Bottom 2 bottomKind 4 { x = 3200, y = 3200 })
                |> Dict.insert 3 (replace Top 3 topKind 12 { x = 4900, y = 4500 })
    }
        |> satellites Bottom
        |> satellites Top


combatant : ShipKind -> CombatantCore -> Combatant
combatant kind c =
    case kind of
        Androsynth ->
            LiveAndrosynth c Guardian

        Arilou ->
            LiveArilou c Present

        Chenjesu ->
            LiveChenjesu c

        Chmmr ->
            LiveChmmr c TractorIdle

        Druuge ->
            LiveDruuge c

        Earthling ->
            LiveEarthling c

        Ilwrath ->
            LiveIlwrath c

        KohrAh ->
            LiveKohrAh c

        Melnorme ->
            LiveMelnorme c { pump = Pump1, levelCounter = Wait 0 }

        Mmrnmhrm ->
            LiveMmrnmhrm c { form = XWing, otherWing = mmrnmhrmYWing }

        Mycon ->
            LiveMycon c

        Orz ->
            LiveOrz c { turretFacing = Facing 0, turretWait = Wait 0 }

        Pkunk ->
            LivePkunk c Flying

        Shofixti ->
            LiveShofixti c SafetyClosed

        Slylandro ->
            LiveSlylandro c

        Spathi ->
            LiveSpathi c

        Supox ->
            LiveSupox c ForwardOnly

        Syreen ->
            LiveSyreen c

        Thraddash ->
            LiveThraddash c Cruise

        Umgah ->
            LiveUmgah c { prevFacing = c.facing }

        UrQuan ->
            LiveUrQuan c

        Utwig ->
            LiveUtwig c

        Vux ->
            LiveVux c WarpPending

        Yehat ->
            LiveYehat c

        ZoqFotPik ->
            LiveZoqFotPik c


satellites : Side -> Arena -> Arena
satellites side state =
    let
        ship =
            if side == Bottom then
                state.combatants.bottom

            else
                state.combatants.top

        c =
            core ship

        (ElementId shipId) =
            c.element
    in
    if kind ship /= Chmmr then
        state

    else
        case Dict.get shipId state.elements of
            Nothing ->
                state

            Just parent ->
                List.foldl
                    (\index arenaState ->
                        let
                            id =
                                ElementId arenaState.nextElementId

                            angle =
                                index * 21

                            at =
                                Trig.wrapPoint arenaState.space { x = parent.current.location.x + Trig.cosine angle 150, y = parent.current.location.y + Trig.sine angle 150 }

                            image =
                                { location = at, frameIndex = 0 }

                            el =
                                { parent | id = id, body = ChmmrSatellite { orbitFacing = Facing index }, points = 3, mass = 1, flags = { emptyFlags | ignoreSimilar = True, defyPhysics = True }, current = image, next = image }
                        in
                        { arenaState | elements = Dict.insert arenaState.nextElementId el arenaState.elements, queue = arenaState.queue ++ [ id ], nextElementId = arenaState.nextElementId + 1 }
                    )
                    state
                    [ 0, 1, 2 ]
