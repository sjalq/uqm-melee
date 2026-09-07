module Melee.Step exposing (pump, tick)

import Dict exposing (Dict)
import Melee.Arsenal as Arsenal
import Melee.Art as Art
import Melee.Battle exposing (Arena)
import Melee.Element exposing (Body(..), Element, Life(..), Owner(..), Prim(..), objectCloaked)
import Melee.Energy as Energy
import Melee.Id exposing (ElementId(..), toInt)
import Melee.Init exposing (emptyFlags)
import Melee.Input exposing (BattleInput, Turn(..))
import Melee.Masks as Masks
import Melee.Projectile as Projectile exposing (Animation(..), BeamKind(..), ContactKind(..), Guidance(..), Inheritance(..), Launch(..), MissileKind(..), Weapon(..))
import Melee.Rate as Rate
import Melee.Rng as Rng
import Melee.Ship as Ship exposing (ShipKind(..))
import Melee.ShipState exposing (..)
import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), FrameCount(..), Side(..), Sided, Wait(..), WorldExtent, WorldPoint)
import Melee.Velocity as Velocity


tick : Sided BattleInput -> Arena -> Arena
tick inputs arena =
    { arena | previousLocations = Dict.map (\_ el -> el.current.location) arena.elements }
        |> applyInputs inputs
        |> prepareAbilities
        |> preprocessAll
        |> auxiliaries
        |> collideAll
        |> gravityAll
        |> postprocessAll
        |> explosions
        |> environment
        |> bumpFrame


{-| One 60 Hz display tick. Runs as many 24 Hz C frames as the
accumulator funds (usually 0 or 1).
-}
pump : Sided BattleInput -> Arena -> Arena
pump inputs arena =
    let
        ( frames, acc ) =
            Rate.advancePump arena.pumpAcc

        stepped =
            List.foldl (\_ a -> tick inputs a) { arena | pumpAcc = acc } (List.range 1 frames)
    in
    stepped


applyInputs : Sided BattleInput -> Arena -> Arena
applyInputs inputs arena =
    let
        set side combatant =
            let
                c =
                    core combatant
            in
            setCore { c | oldInput = c.input, input = sideInput side inputs } combatant
    in
    { arena
        | combatants =
            { bottom = set Bottom arena.combatants.bottom
            , top = set Top arena.combatants.top
            }
    }


sideInput : Side -> Sided BattleInput -> BattleInput
sideInput side inputs =
    case side of
        Bottom ->
            inputs.bottom

        Top ->
            inputs.top


bumpFrame : Arena -> Arena
bumpFrame arena =
    let
        (FrameCount n) =
            arena.frame
    in
    { arena | frame = FrameCount (n + 1) }


getEl : ElementId -> Arena -> Maybe Element
getEl id arena =
    Dict.get (toInt id) arena.elements


putEl : Element -> Arena -> Arena
putEl el arena =
    { arena | elements = Dict.insert (toInt el.id) el arena.elements }


mapCombatant : Side -> (Combatant -> Combatant) -> Arena -> Arena
mapCombatant side fn arena =
    let
        cs =
            arena.combatants
    in
    { arena
        | combatants =
            case side of
                Bottom ->
                    { cs | bottom = fn cs.bottom }

                Top ->
                    { cs | top = fn cs.top }
    }


combatantOf : Owner -> Arena -> Maybe Combatant
combatantOf owner arena =
    case owner of
        Neutral ->
            Nothing

        Owned Bottom ->
            Just arena.combatants.bottom

        Owned Top ->
            Just arena.combatants.top


preprocessAll : Arena -> Arena
preprocessAll arena =
    List.foldl preprocessOne arena arena.queue


preprocessOne : ElementId -> Arena -> Arena
preprocessOne id arena =
    case getEl id arena of
        Nothing ->
            arena

        Just el ->
            if lifeTicks el.life == 0 then
                putEl
                    { el
                        | flags =
                            let
                                f =
                                    el.flags
                            in
                            { f | disappearing = True }
                    }
                    arena

            else
                let
                    appearing =
                        el.flags.appearing

                    afterAppear =
                        if appearing then
                            { el
                                | next = el.current
                                , flags =
                                    let
                                        f =
                                            el.flags
                                    in
                                    { f | appearing = False }
                            }

                        else
                            el

                    afterShip =
                        if afterAppear.flags.playerShip then
                            shipPre arena afterAppear

                        else
                            steerWithSeed arena afterAppear

                    ( arena1, moved ) =
                        applyVelocity (Tuple.first afterShip) (Tuple.second afterShip)

                    aged =
                        if moved.flags.finiteLife then
                            { moved | life = decLife moved.life }

                        else
                            moved

                    flagged =
                        let
                            f =
                                aged.flags
                        in
                        { aged
                            | flags =
                                { f
                                    | preProcess = True
                                    , postProcess = False
                                    , collision = False
                                }
                        }
                in
                putEl flagged arena1


lifeTicks : Life -> Int
lifeTicks life =
    case life of
        Persistent n ->
            n

        Finite n ->
            n


decLife : Life -> Life
decLife life =
    case life of
        Persistent n ->
            Persistent n

        Finite n ->
            Finite (max 0 (n - 1))


applyVelocity : Arena -> Element -> ( Arena, Element )
applyVelocity arena el =
    if el.flags.ignoreVelocity || el.flags.disappearing then
        ( arena, el )

    else
        let
            ( ( dx, dy ), vel ) =
                Velocity.getNext 1 el.velocity

            nextLoc =
                if dx == 0 && dy == 0 then
                    el.next.location

                else
                    Trig.wrapPoint arena.space
                        { x = el.next.location.x + dx
                        , y = el.next.location.y + dy
                        }

            next =
                el.next
        in
        ( arena
        , { el
            | velocity = vel
            , next = { next | location = nextLoc }
            , flags =
                let
                    f =
                        el.flags
                in
                { f | changing = f.changing || dx /= 0 || dy /= 0 }
          }
        )


shipPre : Arena -> Element -> ( Arena, Element )
shipPre arena el =
    case combatantOf el.owner arena of
        Nothing ->
            ( arena, el )

        Just combatant ->
            let
                c0 =
                    let
                        c =
                            core combatant
                    in
                    { c | shieldTicks = max 0 (c.shieldTicks - 1), confusedTicks = max 0 (c.confusedTicks - 1) }

                input =
                    if c0.confusedTicks > 0 then
                        let
                            i =
                                c0.input
                        in
                        { i | turn = TurnRight }

                    else
                        c0.input

                ( energyOk, _, cEnergy ) =
                    if waitReady c0.energyWait then
                        if c0.energy < c0.maxEnergy || c0.characteristics.energyRegeneration < 0 then
                            Energy.deltaEnergy c0.characteristics.energyRegeneration el c0

                        else
                            ( True, el, c0 )

                    else
                        ( True, el, { c0 | energyWait = decWait c0.energyWait } )

                turned =
                    turnShip
                        (if input.special && List.member (kind combatant) [ Supox, Orz ] then
                            { input | turn = NoTurn }

                         else
                            input
                        )
                        cEnergy
                        el

                cTurn =
                    { cEnergy | facing = turned.facing }

                ( elThrust, cThrust ) =
                    if waitReady el.turnWait then
                        ( { el
                            | turnWait = turned.turnWait
                            , next = { location = el.next.location, frameIndex = turned.frame }
                            , flags =
                                let
                                    f =
                                        el.flags
                                in
                                { f | changing = turned.changing || f.changing }
                          }
                        , cTurn
                        )

                    else
                        ( { el | turnWait = decWait el.turnWait }, cTurn )

                ( el2, c2 ) =
                    thrustShip
                        (if kind combatant == Supox && input.special then
                            { input | thrust = False }

                         else
                            input
                        )
                        elThrust
                        cThrust
            in
            ( mapCombatant (ownerSide el.owner) (setCore c2) arena, el2 )


ownerSide : Owner -> Side
ownerSide owner =
    case owner of
        Owned side ->
            side

        Neutral ->
            Bottom


waitReady : Wait -> Bool
waitReady (Wait n) =
    n <= 0


decWait : Wait -> Wait
decWait (Wait n) =
    Wait (max 0 (n - 1))


turnShip :
    BattleInput
    -> CombatantCore
    -> Element
    -> { facing : Facing, turnWait : Wait, frame : Int, changing : Bool }
turnShip input c el =
    let
        (Facing f0) =
            c.facing

        noTurn =
            { facing = c.facing, turnWait = el.turnWait, frame = el.next.frameIndex, changing = False }
    in
    if not (waitReady el.turnWait) then
        noTurn

    else
        case input.turn of
            NoTurn ->
                noTurn

            TurnLeft ->
                let
                    f =
                        Trig.normalizeFacing (f0 - 1)
                in
                { facing = Facing f, turnWait = c.characteristics.turnWait, frame = f, changing = True }

            TurnRight ->
                let
                    f =
                        Trig.normalizeFacing (f0 + 1)
                in
                { facing = Facing f, turnWait = c.characteristics.turnWait, frame = f, changing = True }


thrustShip : BattleInput -> Element -> CombatantCore -> ( Element, CombatantCore )
thrustShip input el c =
    if not (waitReady el.thrustWait) then
        ( { el | thrustWait = decWait el.thrustWait }, c )

    else if not input.thrust then
        ( el, c )

    else
        let
            ( vel, motion ) =
                inertialThrust el.velocity c

            flags =
                c.flags
        in
        ( { el
            | velocity = vel
            , thrustWait = c.characteristics.thrustWait
          }
        , { c
            | flags =
                { flags
                    | atMaxSpeed = motion.atMaxSpeed
                    , beyondMaxSpeed = motion.beyondMaxSpeed
                    , inGravityWell = False
                }
          }
        )


inertialThrust : Melee.Units.VelocityDesc -> CombatantCore -> ( Melee.Units.VelocityDesc, { atMaxSpeed : Bool, beyondMaxSpeed : Bool } )
inertialThrust vel c =
    let
        chars =
            c.characteristics

        (Facing facing) =
            c.facing

        currentAngle =
            facing * 4

        (Angle travelA) =
            vel.travelAngle
    in
    if chars.thrustIncrement == chars.maxThrust then
        ( Velocity.setVector chars.maxThrust c.facing
        , { atMaxSpeed = True, beyondMaxSpeed = False }
        )

    else if travelA == currentAngle && (c.flags.atMaxSpeed || c.flags.beyondMaxSpeed) && not c.flags.inGravityWell then
        ( vel, { atMaxSpeed = c.flags.atMaxSpeed, beyondMaxSpeed = c.flags.beyondMaxSpeed } )

    else
        let
            incV =
                chars.thrustIncrement * 32

            ( cx, cy ) =
                Velocity.getCurrent vel

            dx =
                cx + Trig.cosine currentAngle incV

            dy =
                cy + Trig.sine currentAngle incV

            desired =
                dx * dx + dy * dy

            maxV =
                chars.maxThrust * 32

            maxSpeed =
                maxV * maxV

            currentSpeed =
                cx * cx + cy * cy
        in
        if desired <= maxSpeed then
            ( Velocity.setComponents dx dy, { atMaxSpeed = False, beyondMaxSpeed = False } )

        else if travelA == currentAngle then
            ( Velocity.setVector chars.maxThrust c.facing
            , { atMaxSpeed = True, beyondMaxSpeed = False }
            )

        else
            let
                desiredSpeed =
                    max 1 (Trig.squareRoot desired)

                limit =
                    max maxV (Trig.squareRoot currentSpeed)
            in
            ( Velocity.setComponents (dx * limit // desiredSpeed) (dy * limit // desiredSpeed)
            , { atMaxSpeed = limit == maxV, beyondMaxSpeed = limit > maxV }
            )


collideAll : Arena -> Arena
collideAll arena =
    collideFrom arena.queue arena


collideFrom : List ElementId -> Arena -> Arena
collideFrom ids arena =
    case ids of
        [] ->
            arena

        id0 :: rest ->
            collideFrom rest (collideAgainst id0 rest arena)


collideAgainst : ElementId -> List ElementId -> Arena -> Arena
collideAgainst id0 others arena =
    case others of
        [] ->
            arena

        id1 :: rest ->
            collideAgainst id0 rest (tryCollide id0 id1 arena)


tryCollide : ElementId -> ElementId -> Arena -> Arena
tryCollide id0 id1 arena =
    case ( getEl id0 arena, getEl id1 arena ) of
        ( Just e0, Just e1 ) ->
            if collisionPossible e0 e1 && spritesHit arena e0 e1 then
                bounce arena e0 e1

            else
                arena

        _ ->
            arena


collisionPossible : Element -> Element -> Bool
collisionPossible e0 e1 =
    let
        colliding e =
            not (e.flags.nonsolid || e.flags.disappearing)
    in
    colliding e0
        && colliding e1
        && not (e0.flags.collision && e1.flags.collision)
        && (not (e0.flags.ignoreSimilar && e1.flags.ignoreSimilar) || e0.parent /= e1.parent)
        && (e0.mass /= 0 || e1.mass /= 0)
        && not (List.member e0.body [ OrzMarine, UrQuanFighter, ChenjesuDogi ] && e1.flags.playerShip)
        && not (List.member e1.body [ OrzMarine, UrQuanFighter, ChenjesuDogi ] && e0.flags.playerShip)


radiusDisplay : Element -> Int
radiusDisplay el =
    case el.body of
        PlanetBody ->
            40

        AsteroidBody ->
            6

        ShipBody _ ->
            10 + min 10 el.mass

        ShofixtiDart ->
            3

        ShofixtiGlory ->
            20

        MyconPlasma ->
            12

        KohrAhSaw ->
            7

        MelnormeCharge ->
            8

        _ ->
            4


spritePath : Arena -> Element -> Maybe String
spritePath arena el =
    case el.body of
        ShipBody side ->
            Just
                (Art.ship
                    (if side == Bottom then
                        arena.combatants.bottom

                     else
                        arena.combatants.top
                    )
                    el.next.frameIndex
                )

        _ ->
            Art.projectile el.body el.next.frameIndex |> Maybe.map .path


spritesHit : Arena -> Element -> Element -> Bool
spritesHit arena a b =
    case ( spritePath arena a |> Maybe.andThen Masks.get, spritePath arena b |> Maybe.andThen Masks.get ) of
        ( Just ma, Just mb ) ->
            let
                dx =
                    Trig.wrapDelta (b.current.location.x - a.current.location.x) arena.space.width

                dy =
                    Trig.wrapDelta (b.current.location.y - a.current.location.y) arena.space.height

                vx =
                    Trig.wrapDelta (b.next.location.x - b.current.location.x) arena.space.width - Trig.wrapDelta (a.next.location.x - a.current.location.x) arena.space.width

                vy =
                    Trig.wrapDelta (b.next.location.y - b.current.location.y) arena.space.height - Trig.wrapDelta (a.next.location.y - a.current.location.y) arena.space.height

                extent =
                    (max ma.width ma.height + max mb.width mb.height) * 4

                steps =
                    max 1 ((max (abs vx) (abs vy) + 3) // 4)

                at i =
                    Masks.overlap ma mb ((dx + vx * i // steps) // 4) ((dy + vy * i // steps) // 4)
            in
            abs dx <= extent + abs vx && abs dy <= extent + abs vy && List.any at (List.range 0 steps)

        _ ->
            circlesHit arena.space a b


circlesHit : WorldExtent -> Element -> Element -> Bool
circlesHit space e0 e1 =
    let
        dx =
            toFloat (Trig.wrapDelta (e0.current.location.x - e1.current.location.x) space.width)

        dy =
            toFloat (Trig.wrapDelta (e0.current.location.y - e1.current.location.y) space.height)

        vx =
            toFloat (Trig.wrapDelta (e0.next.location.x - e0.current.location.x) space.width - Trig.wrapDelta (e1.next.location.x - e1.current.location.x) space.width)

        vy =
            toFloat (Trig.wrapDelta (e0.next.location.y - e0.current.location.y) space.height - Trig.wrapDelta (e1.next.location.y - e1.current.location.y) space.height)

        time =
            if vx * vx + vy * vy == 0 then
                0

            else
                clamp 0 1 (-(dx * vx + dy * vy) / (vx * vx + vy * vy))

        x =
            dx + time * vx

        y =
            dy + time * vy

        radius =
            toFloat ((radiusDisplay e0 + radiusDisplay e1) * 4)
    in
    x * x + y * y <= radius * radius


bounce : Arena -> Element -> Element -> Arena
bounce arena e0 e1 =
    if isWeapon e0 then
        if e0.owner == e1.owner && e0.owner /= Neutral && e0.flags.ignoreSimilar then
            arena

        else
            applyHit (Just { weapon = e0, target = e1 }) arena

    else if isWeapon e1 then
        if e0.owner == e1.owner && e0.owner /= Neutral && e1.flags.ignoreSimilar then
            arena

        else
            applyHit (Just { weapon = e1, target = e0 }) arena

    else if e0.body == AsteroidBody || e1.body == AsteroidBody || e0.body == PlanetBody || e1.body == PlanetBody then
        let
            bounceShip ship other state =
                if ship.flags.playerShip then
                    let
                        dx =
                            Trig.wrapDelta (ship.next.location.x - other.next.location.x) state.space.width

                        dy =
                            Trig.wrapDelta (ship.next.location.y - other.next.location.y) state.space.height

                        angle =
                            Trig.arctan dx dy

                        moved =
                            Trig.wrapPoint state.space { x = ship.next.location.x + Trig.cosine angle 60, y = ship.next.location.y + Trig.sine angle 60 }

                        image =
                            ship.next
                    in
                    state
                        |> damageShip
                            (if other.body == PlanetBody then
                                1

                             else
                                0
                            )
                            ship
                        |> updateElement ship.id (\el -> { el | velocity = Velocity.setComponents (Trig.cosine angle 1800) (Trig.sine angle 1800), next = { image | location = moved } })

                else
                    state
        in
        arena |> bounceShip e0 e1 |> bounceShip e1 e0

    else if e0.flags.playerShip && e1.flags.playerShip then
        let
            ( x0, y0 ) =
                Velocity.getCurrent e0.velocity

            ( x1, y1 ) =
                Velocity.getCurrent e1.velocity

            m0 =
                max 1 e0.mass

            m1 =
                max 1 e1.mass

            exchange a b =
                ((m0 - m1) * a + 2 * m1 * b) // (m0 + m1)

            angle =
                bearing arena e1.next.location e0.next.location * 4

            move dx dy ship =
                let
                    image =
                        ship.next
                in
                { ship | next = { image | location = Trig.wrapPoint arena.space { x = image.location.x + dx, y = image.location.y + dy } } }
        in
        arena
            |> putEl (move (Trig.cosine angle 20) (Trig.sine angle 20) { e0 | velocity = Velocity.setComponents (exchange x0 x1) (exchange y0 y1) })
            |> putEl (move (Trig.cosine angle -20) (Trig.sine angle -20) { e1 | velocity = Velocity.setComponents (((m1 - m0) * x1 + 2 * m0 * x0) // (m0 + m1)) (((m1 - m0) * y1 + 2 * m0 * y0) // (m0 + m1)) })

    else
        collectCrew e0 e1 (collectCrew e1 e0 arena)


type alias Hit =
    { weapon : Element
    , target : Element
    }


weaponHit : Element -> Element -> Maybe Hit
weaponHit a b =
    if isWeapon a && not (isWeapon b) then
        Just { weapon = a, target = b }

    else
        Nothing


isWeapon : Element -> Bool
isWeapon el =
    Arsenal.isProjectile el.body


applyHit : Maybe Hit -> Arena -> Arena
applyHit maybeHit arena =
    case maybeHit of
        Nothing ->
            arena

        Just { weapon, target } ->
            let
                hit =
                    if target.flags.playerShip then
                        case combatantOf target.owner arena of
                            Nothing ->
                                arena

                            Just combatant ->
                                let
                                    c =
                                        core combatant
                                in
                                if c.shieldTicks > 0 then
                                    if kind combatant == Utwig then
                                        mapCombatant (ownerSide target.owner) (setCore { c | energy = min c.maxEnergy (c.energy + weapon.mass) }) arena

                                    else
                                        arena

                                else if weapon.body == VuxLimpet then
                                    let
                                        ch =
                                            c.characteristics
                                    in
                                    mapCombatant (ownerSide target.owner)
                                        (setCore
                                            { c
                                                | characteristics =
                                                    { ch
                                                        | maxThrust = max 4 (ch.maxThrust * 7 // 8)
                                                        , thrustIncrement = max 1 (ch.thrustIncrement * 7 // 8)
                                                        , turnWait =
                                                            let
                                                                (Wait w) =
                                                                    ch.turnWait
                                                            in
                                                            Wait (w + 1)
                                                    }
                                            }
                                        )
                                        arena

                                else if weapon.body == MelnormeConfusion then
                                    mapCombatant (ownerSide target.owner) (setCore { c | confusedTicks = 120 }) arena

                                else if weapon.body == ChenjesuDogi then
                                    mapCombatant (ownerSide target.owner) (setCore { c | energy = max 0 (c.energy - 10) }) arena

                                else
                                    damageShip weapon.mass target arena

                    else if target.body == PlanetBody then
                        arena

                    else if target.points > weapon.mass then
                        putEl { target | points = target.points - weapon.mass } arena

                    else
                        removeEl target.id arena

                withBlast =
                    impact weapon target hit

                survives =
                    not target.flags.playerShip && target.body /= PlanetBody && weapon.points > target.mass
            in
            if survives then
                updateElement weapon.id (\e -> { e | points = e.points - target.mass }) hit

            else
                removeEl weapon.id withBlast


impact : Element -> Element -> Arena -> Arena
impact weapon target arena =
    let
        ( vx, vy ) =
            Velocity.getCurrent weapon.velocity

        angle =
            Trig.arctan vx vy

        (Facing facing) =
            Trig.angleToFacing (Angle (angle + 32))

        frame =
            (facing // 4)
                * 2
                + (if modBy 4 facing == 0 then
                    0

                   else
                    1
                  )

        offset =
            case weapon.projectile of
                Just (Projectile.Flying missile _) ->
                    (Arsenal.spec missile).blastOffset * 4

                _ ->
                    4

        at =
            Trig.wrapPoint arena.space { x = weapon.next.location.x + Trig.cosine angle offset, y = weapon.next.location.y + Trig.sine angle offset }

        id =
            ElementId arena.nextElementId

        burst missile first count =
            let
                spawned =
                    effect (WeaponImpact missile) target.next.location count arena
            in
            updateElement id (\e -> { e | current = { location = target.next.location, frameIndex = first }, next = { location = target.next.location, frameIndex = first }, thrustWait = Wait first }) spawned

        generic =
            effect BlastBody at 2 arena |> updateElement id (\e -> { e | current = { location = at, frameIndex = frame }, next = { location = at, frameIndex = frame } })
    in
    case weapon.projectile of
        Just (Projectile.Flying missile _) ->
            case missile of
                Nuke ->
                    burst Nuke 16 9

                Cannon ->
                    burst Cannon 16 8

                Fusion ->
                    burst Fusion 16 8

                Crystal ->
                    burst Crystal 2 9

                Shard ->
                    burst Shard 2 9

                Charge ->
                    burst Charge 20 6

                Plasma ->
                    burst Plasma 11 (max 1 ((weapon.mass * 8 + 9) // 10) * 2 - 1)

                _ ->
                    generic

        _ ->
            generic


damageShip : Int -> Element -> Arena -> Arena
damageShip amount target arena =
    case combatantOf target.owner arena of
        Nothing ->
            arena

        Just combatant ->
            let
                c =
                    core combatant

                ( alive, damaged, nextCore ) =
                    Energy.deltaCrew -amount target c
            in
            if c.shieldTicks > 0 then
                arena

            else if alive then
                putEl damaged arena

            else
                let
                    ( roll, seed ) =
                        Rng.next arena.seed

                    next =
                        { arena | seed = seed }
                in
                if kind combatant == Pkunk && modBy 2 roll == 0 then
                    next
                        |> putEl { target | points = c.maxCrew }
                        |> mapCombatant (ownerSide target.owner) (setCore { nextCore | energy = c.maxEnergy, shieldTicks = 36 })
                        |> effect WarpInBody target.next.location 24

                else
                    startExplosion target next


startExplosion : Element -> Arena -> Arena
startExplosion ship arena =
    putEl
        { ship
            | body = WreckBody (ownerSide ship.owner)
            , points = 0
            , life = Finite 36
            , colorCycleIndex = 36
            , flags = { emptyFlags | finiteLife = True, nonsolid = True }
            , velocity = Velocity.zero
            , projectile = Nothing
        }
        arena


explosions : Arena -> Arena
explosions arena =
    let
        emit wreck state =
            let
                age =
                    36 - lifeTicks wreck.life

                count =
                    if age > 25 then
                        0

                    else if age <= 2 || age >= 20 then
                        1

                    else if age <= 5 || age >= 18 then
                        2

                    else
                        3

                spark _ a =
                    let
                        ( r1, seed1 ) =
                            Rng.next a.seed

                        ( r2, seed2 ) =
                            Rng.next seed1

                        angle =
                            modBy 64 (r1 // 65536)

                        radius =
                            (modBy 8 r1
                                + (if modBy 256 (r1 // 256) < 85 then
                                    8

                                   else
                                    0
                                  )
                            )
                                * 4

                        at =
                            Trig.wrapPoint a.space { x = wreck.current.location.x + Trig.cosine angle radius, y = wreck.current.location.y + Trig.sine angle radius }

                        id =
                            ElementId a.nextElementId

                        spawned =
                            effect ExplosionBody at 9 { a | seed = seed2 }

                        speed =
                            modBy 5 (r2 // 256) * 4 * 32
                    in
                    updateElement id (\el -> { el | velocity = Velocity.setComponents (Trig.cosine r2 speed) (Trig.sine r2 speed) }) spawned
            in
            List.foldl spark state (List.range 1 count)
    in
    Dict.values arena.elements
        |> List.filter
            (\el ->
                case el.body of
                    WreckBody _ ->
                        True

                    _ ->
                        False
            )
        |> List.foldl emit arena


updateElement : ElementId -> (Element -> Element) -> Arena -> Arena
updateElement id fn arena =
    case getEl id arena of
        Just el ->
            putEl (fn el) arena

        Nothing ->
            arena


gravityAll : Arena -> Arena
gravityAll arena =
    case findPlanet arena.queue arena of
        Just planet ->
            List.foldl (pullToward planet) arena arena.queue

        Nothing ->
            arena


findPlanet : List ElementId -> Arena -> Maybe Element
findPlanet ids arena =
    case ids of
        [] ->
            Nothing

        id :: rest ->
            case getEl id arena of
                Just el ->
                    if isPlanet el then
                        Just el

                    else
                        findPlanet rest arena

                Nothing ->
                    findPlanet rest arena


isPlanet : Element -> Bool
isPlanet el =
    el.body == PlanetBody


pullToward : Element -> ElementId -> Arena -> Arena
pullToward planet id arena =
    case getEl id arena of
        Nothing ->
            arena

        Just el ->
            if el.id == planet.id || el.mass > 100 || el.flags.defyPhysics then
                arena

            else
                let
                    dx =
                        Trig.wrapDelta (planet.next.location.x - el.next.location.x) arena.space.width

                    dy =
                        Trig.wrapDelta (planet.next.location.y - el.next.location.y) arena.space.height

                    adx =
                        abs dx // 4

                    ady =
                        abs dy // 4
                in
                if adx <= 255 && ady <= 255 && adx * adx + ady * ady <= 255 * 255 then
                    let
                        angle =
                            Trig.arctan dx dy

                        vel =
                            Velocity.delta
                                (Trig.cosine angle 32)
                                (Trig.sine angle 32)
                                el.velocity

                        arena1 =
                            putEl { el | velocity = vel } arena
                    in
                    if el.flags.playerShip then
                        mapCombatant (ownerSide el.owner)
                            (\c ->
                                let
                                    co =
                                        core c

                                    f =
                                        co.flags
                                in
                                setCore { co | flags = { f | atMaxSpeed = False, inGravityWell = True } } c
                            )
                            arena1

                    else
                        arena1

                else
                    arena


postprocessAll : Arena -> Arena
postprocessAll arena =
    List.foldl postprocessOne arena arena.queue


postprocessOne : ElementId -> Arena -> Arena
postprocessOne id arena =
    case getEl id arena of
        Nothing ->
            arena

        Just el ->
            if el.flags.disappearing then
                removeEl id arena

            else
                let
                    ( arena1, el1 ) =
                        if el.flags.playerShip then
                            shipPost arena el

                        else
                            ( arena, el )
                in
                if el1.flags.disappearing then
                    removeEl id arena1

                else
                    let
                        copied =
                            { el1
                                | current = el1.next
                                , flags =
                                    let
                                        f =
                                            el1.flags
                                    in
                                    { f | preProcess = False, changing = False, appearing = False, postProcess = True }
                            }
                    in
                    putEl copied arena1


removeEl : ElementId -> Arena -> Arena
removeEl id arena =
    { arena
        | elements = Dict.remove (toInt id) arena.elements
        , queue = List.filter (\q -> q /= id) arena.queue
    }


shipPost : Arena -> Element -> ( Arena, Element )
shipPost arena el =
    if el.points == 0 then
        ( arena, el )

    else
        case combatantOf el.owner arena of
            Nothing ->
                ( arena, el )

            Just combatant ->
                let
                    c0 =
                        core combatant

                    aimed =
                        case combatant of
                            LiveOrz c extra ->
                                let
                                    (Facing facing) =
                                        extra.turretFacing

                                    rotate =
                                        c.input.special && c.input.turn /= NoTurn && waitReady extra.turretWait

                                    delta =
                                        if c.input.turn == TurnRight then
                                            1

                                        else
                                            -1
                                in
                                LiveOrz c
                                    { extra
                                        | turretFacing =
                                            if rotate then
                                                Facing (modBy 16 (facing + delta))

                                            else
                                                extra.turretFacing
                                        , turretWait =
                                            if rotate then
                                                Wait 3

                                            else
                                                decWait extra.turretWait
                                    }

                            _ ->
                                combatant

                    ( c1, arena1, el1 ) =
                        fireWeapon (mapCombatant (ownerSide el.owner) (\_ -> aimed) arena) el c0 aimed
                in
                ( mapCombatant (ownerSide el.owner) (setCore c1) arena1, el1 )


fireWeapon : Arena -> Element -> CombatantCore -> Combatant -> ( CombatantCore, Arena, Element )
fireWeapon arena el original combatant =
    let
        c =
            { original | weaponWait = decWait original.weaponWait, specialWait = decWait original.specialWait }

        wantsFire =
            c.input.weapon
                && not (kind combatant == Orz && c.input.special)
                && (kind combatant
                        /= Melnorme
                        || not
                            (Dict.values arena.elements
                                |> List.any
                                    (\e ->
                                        e.owner
                                            == el.owner
                                            && (case e.projectile of
                                                    Just (Projectile.Charging _) ->
                                                        True

                                                    _ ->
                                                        False
                                               )
                                    )
                            )
                   )

        canFire =
            waitReady original.weaponWait
                && (kind combatant /= Chenjesu || not (Dict.values arena.elements |> List.any (\e -> e.owner == el.owner && e.body == ChenjesuPhoton)))
                && wantsFire
                && c.energy
                >= c.characteristics.weaponEnergyCost
                && (case combatant of
                        LiveAndrosynth _ (Blazer _) ->
                            False

                        _ ->
                            True
                   )

        afterFire =
            if canFire then
                let
                    spent =
                        { c | energy = c.energy - c.characteristics.weaponEnergyCost, weaponWait = c.characteristics.weaponWait, chargeTicks = 0, cloaked = False }

                    base =
                        Arsenal.primary combatant

                    weapon =
                        base

                    fired =
                        fire weapon
                            el
                            (case combatant of
                                LiveOrz _ extra ->
                                    { spent
                                        | facing =
                                            let
                                                (Facing facing) =
                                                    spent.facing
                                            in
                                            let
                                                (Facing offset) =
                                                    extra.turretFacing
                                            in
                                            Facing (modBy 16 (facing + offset))
                                    }

                                _ ->
                                    spent
                            )
                            arena

                    recoil =
                        if kind combatant == Druuge then
                            let
                                (Facing f) =
                                    c.facing
                            in
                            { el | velocity = Velocity.delta (Trig.cosine (f * 4) -1800) (Trig.sine (f * 4) -1800) el.velocity }

                        else
                            el
                in
                ( spent, fired, recoil )

            else
                ( c, arena, el )

        ( c1, firedArena, e1 ) =
            afterFire

        a1 =
            if kind combatant == Slylandro && not (waitReady original.weaponWait) then
                fireLightning el c firedArena

            else
                firedArena
    in
    if kind combatant == Shofixti && c1.input.special /= c1.oldInput.special then
        special combatant e1 c1 a1

    else if c1.input.special && kind combatant /= Shofixti && waitReady original.specialWait && (c1.energy >= c1.characteristics.specialEnergyCost || List.member (kind combatant) [ Druuge, Pkunk, Supox ]) then
        special combatant e1 c1 a1

    else
        ( c1, a1, e1 )


spawnDart : Arena -> Element -> CombatantCore -> ( Arena, ElementId )
spawnDart arena ship c =
    let
        id =
            ElementId arena.nextElementId

        (Facing facing) =
            c.facing

        angle =
            facing * 4

        pix =
            15 * 4

        speed =
            24 * 4

        loc0 =
            { x = ship.next.location.x + Trig.cosine angle pix
            , y = ship.next.location.y + Trig.sine angle pix
            }

        dx =
            Trig.cosine angle (speed * 32)

        dy =
            Trig.sine angle (speed * 32)

        vel =
            Velocity.setComponents dx dy

        loc =
            { x = loc0.x - (dx // 32)
            , y = loc0.y - (dy // 32)
            }

        dart : Element
        dart =
            { id = id
            , owner = ship.owner
            , parent = ship.parent
            , target = Nothing
            , flags =
                { emptyFlags
                    | appearing = True
                    , finiteLife = True
                    , ignoreSimilar = True
                }
            , life = Finite 10
            , points = 1
            , mass = 1
            , turnWait = Wait 0
            , thrustWait = Wait 0
            , colorCycleIndex = 0
            , velocity = vel
            , intersect =
                { lastTimeVal = 0
                , endPoint = loc
                , stampOrigin = loc
                }
            , current = { location = loc, frameIndex = facing }
            , next = { location = loc, frameIndex = facing }
            , projectile = Nothing
            , prim = Stamp
            , body = ShofixtiDart
            }
    in
    ( { arena
        | elements = Dict.insert (toInt id) dart arena.elements
        , queue = arena.queue ++ [ id ]
        , nextElementId = arena.nextElementId + 1
      }
    , id
    )


glory : Arena -> Element -> CombatantCore -> Combatant -> ( CombatantCore, Arena, Element )
glory arena el c combatant =
    let
        range =
            180

        damaged =
            List.foldl (gloryOne el.id el.next.location range) arena arena.queue

        deadShip =
            { el
                | points = 0
                , life = Finite 0
                , flags =
                    let
                        f =
                            el.flags
                    in
                    { f | nonsolid = True, disappearing = True }
            }
    in
    ( { c | specialWait = c.characteristics.specialWait }
    , startExplosion deadShip damaged
    , deadShip
    )


gloryOne : ElementId -> WorldPoint -> Int -> ElementId -> Arena -> Arena
gloryOne self origin rangeDisp id arena =
    case getEl id arena of
        Nothing ->
            arena

        Just obj ->
            if obj.id == self || obj.flags.nonsolid || obj.mass > 100 then
                arena

            else
                let
                    dx =
                        abs (Trig.wrapDelta (obj.next.location.x - origin.x) arena.space.width) // 4

                    dy =
                        abs (Trig.wrapDelta (obj.next.location.y - origin.y) arena.space.height) // 4

                    distSq =
                        dx * dx + dy * dy
                in
                if dx <= rangeDisp && dy <= rangeDisp && distSq <= rangeDisp * rangeDisp then
                    let
                        destruction =
                            1 + (18 * (rangeDisp - Trig.squareRoot distSq)) // rangeDisp
                    in
                    if obj.flags.playerShip then
                        damageShip destruction obj arena

                    else if isWeapon obj then
                        removeEl obj.id arena

                    else
                        arena

                else
                    arena


fire : Weapon -> Element -> CombatantCore -> Arena -> Arena
fire weapon el c arena =
    if Dict.size arena.elements >= 150 then
        arena

    else
        case weapon of
            Beam beam ->
                fireBeam beam el c arena

            Lightning ->
                fireLightning el c arena

            Contact contact ->
                fireContact contact el c arena

            Missile spec ->
                let
                    (Facing facing) =
                        c.facing

                    ports =
                        case spec.launch of
                            Nose forward ->
                                List.map (\offset -> { forward = forward, sideways = 0, facingOffset = offset }) spec.directions

                            Ports values ->
                                values

                    launch mount state =
                        let
                            direction =
                                modBy 16 (facing + mount.facingOffset)

                            angle =
                                (if List.length spec.directions > 1 then
                                    direction

                                 else
                                    facing
                                )
                                    * 4

                            at =
                                Trig.wrapPoint state.space
                                    { x = el.next.location.x + Trig.cosine angle (mount.forward * 4) + Trig.cosine (angle + 16) (mount.sideways * 4)
                                    , y = el.next.location.y + Trig.sine angle (mount.forward * 4) + Trig.sine (angle + 16) (mount.sideways * 4)
                                    }
                        in
                        spawnMissile spec el { c | facing = Facing direction } at state |> Tuple.first
                in
                limitSaws spec.kind el.owner (List.foldl launch arena ports)


limitSaws : MissileKind -> Owner -> Arena -> Arena
limitSaws missile owner arena =
    if missile /= Saw then
        arena

    else
        let
            existing =
                Dict.values arena.elements |> List.filter (\el -> el.owner == owner && el.body == KohrAhSaw) |> List.sortBy (\el -> toInt el.id)

            expired =
                List.take (max 0 (List.length existing - 8)) existing
        in
        List.foldl (\el state -> removeEl el.id state) arena expired


spawnMissile : Projectile.MissileSpec -> Element -> CombatantCore -> WorldPoint -> Arena -> ( Arena, ElementId )
spawnMissile spec ship c at arena =
    let
        ( spawned, id ) =
            spawnDart arena ship c

        (Facing facing) =
            c.facing

        ( inheritedX, inheritedY ) =
            case spec.inheritance of
                InheritVelocity ->
                    Velocity.getCurrent ship.velocity

                Independent ->
                    ( 0, 0 )

        image =
            { location = at, frameIndex = animationFrame spec.animation facing 0 spec.damage }

        trackingWait =
            case spec.guidance of
                Tracking tracking ->
                    tracking.initialWait

                _ ->
                    0
    in
    ( updateElement id
        (\el ->
            { el
                | body = Arsenal.missileBody spec.kind
                , projectile =
                    Just
                        (if spec.kind == Charge && c.input.weapon then
                            Projectile.Charging { ticks = 0, facing = c.facing }

                         else
                            Projectile.Flying spec.kind { age = 0, facing = Facing facing, trackingWait = trackingWait }
                        )
                , current = image
                , next = image
                , mass = spec.damage
                , points = spec.hitPoints
                , life =
                    Finite
                        (if spec.kind == Charge && c.input.weapon then
                            2

                         else
                            spec.life
                        )
                , velocity =
                    if spec.kind == Charge && c.input.weapon then
                        Velocity.zero

                    else
                        Velocity.setComponents (Trig.cosine (facing * 4) (spec.speed * 32) + inheritedX) (Trig.sine (facing * 4) (spec.speed * 32) + inheritedY)
                , flags = { emptyFlags | appearing = True, finiteLife = True, ignoreSimilar = not spec.friendlyFire }
            }
        )
        spawned
    , id
    )


animationFrame : Animation -> Int -> Int -> Int -> Int
animationFrame animation facing age damage =
    case animation of
        Directional ->
            facing

        Frames timing ->
            modBy timing.count (age // timing.ticks)

        PlasmaDecay ->
            min 10 (age // 13)

        ChargeLevel ->
            (if damage >= 16 then
                3

             else if damage >= 8 then
                2

             else if damage >= 4 then
                1

             else
                0
            )
                * 5
                + (let
                    phase =
                        modBy 8 age
                   in
                   if phase <= 4 then
                    phase

                   else
                    8 - phase
                  )


beamGeometry : BeamKind -> Int -> WorldPoint -> List ( WorldPoint, WorldPoint )
beamGeometry beam facing center =
    let
        offset forward sideways =
            { x = center.x + Trig.cosine (facing * 4) forward + Trig.cosine (facing * 4 + 16) sideways
            , y = center.y + Trig.sine (facing * 4) forward + Trig.sine (facing * 4 + 16) sideways
            }

        ray start finish =
            [ ( offset start 0, offset finish 0 ) ]
    in
    case beam of
        AutoAim ->
            ray 36 436

        Megawatt ->
            let
                -- GetFrameRect(muzzle-big[face]).corner in chmmr.c.
                ( x, y ) =
                    List.drop facing [ ( 0, -22 ), ( 11, -20 ), ( 16, -17 ), ( 21, -10 ), ( 22, 0 ), ( 22, 10 ), ( 17, 16 ), ( 11, 20 ), ( 0, 22 ), ( -11, 20 ), ( -17, 16 ), ( -22, 10 ), ( -23, 0 ), ( -22, -10 ), ( -17, -16 ), ( -11, -20 ) ] |> List.head |> Maybe.withDefault ( 0, -22 )

                origin =
                    { x = center.x + x * 4, y = center.y + y * 4 }
            in
            [ ( origin, { x = origin.x + Trig.cosine (facing * 4) 600, y = origin.y + Trig.sine (facing * 4) 600 } ) ]

        Twin ->
            [ ( offset 16 40, offset 580 0 ), ( offset 16 -40, offset 580 0 ) ]

        Green ->
            ray 48 648

        PointDefense ->
            ray 0 400

        Zap ->
            ray 0 200

        FighterBeam ->
            ray 16 176


fireBeam : BeamKind -> Element -> CombatantCore -> Arena -> Arena
fireBeam beam el c arena =
    let
        (Facing facing) =
            c.facing

        direction =
            if List.member beam [ AutoAim, PointDefense, Zap, FighterBeam ] then
                enemy el.owner arena |> Maybe.map (\other -> bearing arena el.next.location other.next.location) |> Maybe.withDefault facing

            else
                facing

        cast ( origin, end ) state =
            castRay (Just beam) origin end el c state
    in
    List.foldl cast arena (beamGeometry beam direction el.next.location)


castRay : Maybe BeamKind -> WorldPoint -> WorldPoint -> Element -> CombatantCore -> Arena -> Arena
castRay beam origin end source c arena =
    let
        damage =
            if beam == Just Megawatt then
                2

            else
                1

        candidates =
            Dict.values arena.elements
                |> List.filter (\other -> other.id /= source.id && not other.flags.nonsolid && not other.flags.disappearing && other.owner /= source.owner)
                |> List.filterMap (\other -> rayIntersection arena origin end other |> Maybe.map (\t -> ( t, other )))
                |> List.sortBy Tuple.first

        first =
            List.head candidates

        stop =
            case first of
                Just ( t, _ ) ->
                    { x = origin.x + round (toFloat (end.x - origin.x) * t), y = origin.y + round (toFloat (end.y - origin.y) * t) }

                Nothing ->
                    end

        hit =
            case first of
                Just ( _, other ) ->
                    if other.flags.playerShip then
                        case combatantOf other.owner arena of
                            Just ship ->
                                if (core ship).shieldTicks > 0 then
                                    if kind ship == Utwig then
                                        mapCombatant (ownerSide other.owner)
                                            (\live ->
                                                let
                                                    co =
                                                        core live
                                                in
                                                setCore { co | energy = min co.maxEnergy (co.energy + damage) } live
                                            )
                                            arena

                                    else
                                        arena

                                else
                                    damageShip damage other arena

                            Nothing ->
                                arena

                    else if other.body == PlanetBody then
                        arena

                    else if other.points > damage then
                        putEl { other | points = other.points - damage } arena

                    else
                        removeEl other.id arena

                Nothing ->
                    arena

        ( spawned, id ) =
            spawnDart hit source c

        start =
            Trig.wrapPoint arena.space origin

        finish =
            Trig.wrapPoint arena.space stop

        visual =
            case beam of
                Just which ->
                    Projectile.Ray which { origin = start, end = finish }

                Nothing ->
                    Projectile.LightningSegment { origin = start, end = finish }
    in
    updateElement id
        (\el ->
            { el
                | body = Maybe.map Arsenal.beamBody beam |> Maybe.withDefault SlylandroLightning
                , projectile = Just visual
                , prim = Line
                , life = Finite 0
                , mass = damage
                , current = { location = start, frameIndex = 0 }
                , next = { location = start, frameIndex = 0 }
                , velocity = Velocity.zero
                , flags = { emptyFlags | finiteLife = True, nonsolid = True }
                , intersect = { lastTimeVal = 0, stampOrigin = start, endPoint = finish }
            }
        )
        spawned


rayIntersection : Arena -> WorldPoint -> WorldPoint -> Element -> Maybe Float
rayIntersection arena origin end target =
    case spritePath arena target |> Maybe.andThen Masks.get of
        Just mask ->
            let
                dx =
                    end.x - origin.x

                dy =
                    end.y - origin.y

                tx =
                    Trig.wrapDelta (target.next.location.x - origin.x) arena.space.width

                ty =
                    Trig.wrapDelta (target.next.location.y - origin.y) arena.space.height

                steps =
                    max 1 ((max (abs dx) (abs dy) + 3) // 4)

                at i =
                    Masks.opaque mask ((dx * i // steps - tx) // 4) ((dy * i // steps - ty) // 4)
            in
            List.range 0 steps |> List.filter at |> List.head |> Maybe.map (\i -> toFloat i / toFloat steps)

        Nothing ->
            rayCircle arena.space origin end target


rayCircle : WorldExtent -> WorldPoint -> WorldPoint -> Element -> Maybe Float
rayCircle space origin end target =
    let
        dx =
            toFloat (end.x - origin.x)

        dy =
            toFloat (end.y - origin.y)

        tx =
            toFloat (Trig.wrapDelta (target.next.location.x - origin.x) space.width)

        ty =
            toFloat (Trig.wrapDelta (target.next.location.y - origin.y) space.height)

        lengthSquared =
            dx * dx + dy * dy

        projection =
            (tx * dx + ty * dy) / max 1 lengthSquared

        radius =
            toFloat (radiusDisplay target * 4)

        perpendicular =
            tx * tx + ty * ty - projection * projection * lengthSquared

        entry =
            projection - sqrt (max 0 (radius * radius - perpendicular) / max 1 lengthSquared)
    in
    if perpendicular <= radius * radius && projection >= 0 && entry <= 1 then
        Just (max 0 entry)

    else
        Nothing


fireContact : ContactKind -> Element -> CombatantCore -> Arena -> Arena
fireContact contact ship c arena =
    let
        ( spawned, id ) =
            spawnDart arena ship c

        (Facing facing) =
            c.facing

        image =
            { location = ship.next.location, frameIndex = facing }
    in
    updateElement id
        (\el ->
            { el
                | body =
                    if contact == Cone then
                        UmgahCone

                    else
                        ZoqTongue
                , projectile = Just (Projectile.Attached contact { age = 0, facing = c.facing })
                , current = image
                , next = image
                , velocity = Velocity.zero
                , mass =
                    if contact == Cone then
                        1

                    else
                        12
                , points =
                    if contact == Cone then
                        100

                    else
                        1
                , life =
                    Finite
                        (if contact == Cone then
                            1

                         else
                            7
                        )
                , flags = { emptyFlags | finiteLife = True, ignoreSimilar = True, defyPhysics = True }
            }
        )
        spawned


fireLightning : Element -> CombatantCore -> Arena -> Arena
fireLightning ship c arena =
    let
        (Facing facing) =
            c.facing

        direction =
            enemy ship.owner arena |> Maybe.map (\other -> bearing arena ship.next.location other.next.location) |> Maybe.withDefault facing

        segment _ ( origin, state, stopped ) =
            if stopped then
                ( origin, state, True )

            else
                let
                    ( random, seed ) =
                        Rng.next state.seed

                    angle =
                        direction * 4 + modBy 7 random - 3

                    length =
                        (4 + modBy 32 (random // 256)) * 4

                    end =
                        { x = origin.x + Trig.cosine angle length, y = origin.y + Trig.sine angle length }

                    id =
                        ElementId state.nextElementId

                    next =
                        castRay Nothing origin end ship c { state | seed = seed }

                    collided =
                        getEl id next |> Maybe.map (\beam -> beam.intersect.endPoint /= Trig.wrapPoint state.space end) |> Maybe.withDefault True
                in
                ( end, next, collided )

        (Wait wait) =
            c.weaponWait

        segments =
            if wait > 8 then
                17 - wait

            else
                wait
    in
    List.foldl segment ( ship.next.location, arena, False ) (List.range 0 segments) |> (\( _, result, _ ) -> result)


enemy : Owner -> Arena -> Maybe Element
enemy owner arena =
    let
        c =
            if owner == Owned Bottom then
                arena.combatants.top

            else
                arena.combatants.bottom
    in
    if (core c).cloaked then
        Nothing

    else
        getEl (core c).element arena


bearing : Arena -> WorldPoint -> WorldPoint -> Int
bearing arena from to =
    modBy 16 ((Trig.arctan (Trig.wrapDelta (to.x - from.x) arena.space.width) (Trig.wrapDelta (to.y - from.y) arena.space.height) + 2) // 4)


distance : Arena -> WorldPoint -> WorldPoint -> Int
distance arena from to =
    let
        dx =
            Trig.wrapDelta (to.x - from.x) arena.space.width

        dy =
            Trig.wrapDelta (to.y - from.y) arena.space.height
    in
    Trig.squareRoot (dx * dx + dy * dy)


effect : Body -> WorldPoint -> Int -> Arena -> Arena
effect body at life arena =
    let
        id =
            ElementId arena.nextElementId

        image =
            { location = at, frameIndex = 0 }

        el =
            { id = id
            , owner = Neutral
            , parent = Nothing
            , target = Nothing
            , flags = { emptyFlags | finiteLife = True, nonsolid = True, defyPhysics = True, appearing = True }
            , life = Finite life
            , points = 0
            , mass = 0
            , turnWait = Wait 0
            , thrustWait = Wait 0
            , colorCycleIndex = life
            , velocity = Velocity.zero
            , intersect = { lastTimeVal = 0, endPoint = at, stampOrigin = at }
            , current = image
            , next = image
            , projectile = Nothing
            , prim = Stamp
            , body = body
            }
    in
    { arena | elements = Dict.insert (toInt id) el arena.elements, queue = arena.queue ++ [ id ], nextElementId = arena.nextElementId + 1 }


special : Combatant -> Element -> CombatantCore -> Arena -> ( CombatantCore, Arena, Element )
special combatant el c arena =
    let
        paid =
            { c | energy = c.energy - c.characteristics.specialEnergyCost, specialWait = c.characteristics.specialWait }

        (Facing facing) =
            c.facing

        launch weapon direction =
            ( paid, fire weapon el { paid | facing = Facing direction } arena, el )

        radial _ damage speed life =
            launch
                (Missile
                    (let
                        spec =
                            Arsenal.spec Fried
                     in
                     { spec | damage = damage, speed = speed, life = life }
                    )
                )
                facing

        near range other =
            distance arena el.next.location other.next.location < range
    in
    case combatant of
        LiveShofixti _ safety ->
            let
                advanceSafety next =
                    ( c, mapCombatant (ownerSide el.owner) (\_ -> LiveShofixti c next) arena, el )
            in
            case safety of
                SafetyClosed ->
                    advanceSafety OpeningSafety

                OpeningSafety ->
                    advanceSafety SafetyOpen

                SafetyOpen ->
                    advanceSafety ArmingDevice

                ArmingDevice ->
                    advanceSafety Armed

                Armed ->
                    glory arena el c combatant

                GloryDevice ->
                    ( c, arena, el )

        LiveArilou _ _ ->
            let
                ( x, s1 ) =
                    Rng.next arena.seed

                ( y, s2 ) =
                    Rng.next s1

                at =
                    { x = modBy arena.space.width x, y = modBy arena.space.height y }

                moved =
                    { el | current = { location = at, frameIndex = facing }, next = { location = at, frameIndex = facing }, velocity = Velocity.zero }
            in
            ( { paid | shieldTicks = 5 }, effect WarpInBody at 10 { arena | seed = s2 }, moved )

        LiveAndrosynth _ form ->
            case form of
                Guardian ->
                    let
                        ch =
                            c.characteristics
                    in
                    ( { paid | characteristics = { ch | maxThrust = 60, thrustIncrement = 60, turnWait = Wait 1 }, specialWait = Wait 1 }
                    , mapCombatant (ownerSide el.owner) (\_ -> LiveAndrosynth paid (Blazer { guardian = ch })) arena
                    , el
                    )

                Blazer _ ->
                    ( c, arena, el )

        LiveChenjesu _ ->
            if countOwned ChenjesuDogi el.owner arena >= 4 then
                ( c, arena, el )

            else
                launch (Missile (Arsenal.spec Dogi)) facing

        LiveChmmr _ _ ->
            let
                pulled =
                    case enemy el.owner arena of
                        Just other ->
                            let
                                angle =
                                    bearing arena other.next.location el.next.location * 4
                            in
                            putEl { other | velocity = Velocity.delta (Trig.cosine angle 240) (Trig.sine angle 240) other.velocity } arena

                        Nothing ->
                            arena
            in
            ( paid, effect IonTrailBody el.next.location 3 pulled, el )

        LiveDruuge _ ->
            if el.points > 1 && c.energy < c.maxEnergy then
                ( { paid | energy = min c.maxEnergy (c.energy + 16), specialWait = Wait 8 }, arena, { el | points = el.points - 1 } )

            else
                ( c, arena, el )

        LiveEarthling _ ->
            let
                targets =
                    Dict.values arena.elements
                        |> List.filter (\other -> other.id /= el.id && not other.flags.nonsolid && not other.flags.disappearing && near 400 other)
                        |> List.filter (\other -> combatantOf other.owner arena |> Maybe.map (core >> .cloaked >> not) |> Maybe.withDefault True)

                shoot other state =
                    let
                        origin =
                            el.next.location

                        end =
                            { x = origin.x + Trig.wrapDelta (other.next.location.x - origin.x) arena.space.width, y = origin.y + Trig.wrapDelta (other.next.location.y - origin.y) arena.space.height }
                    in
                    castRay (Just PointDefense) origin end el paid state
            in
            if List.isEmpty targets then
                ( c, arena, el )

            else
                ( paid, List.foldl shoot arena targets, el )

        LiveIlwrath _ ->
            if c.oldInput.special then
                ( c, arena, el )

            else
                ( { paid | cloaked = not c.cloaked }, arena, el )

        LiveKohrAh _ ->
            radial KohrAhFried 3 70 16

        LiveMelnorme _ _ ->
            launch (Missile (Arsenal.spec Confusion)) facing

        LiveMmrnmhrm _ extra ->
            let
                switched =
                    { paid | characteristics = extra.otherWing, specialWait = Wait 12 }

                form =
                    if extra.form == XWing then
                        YWing

                    else
                        XWing
            in
            ( switched, mapCombatant (ownerSide el.owner) (\_ -> LiveMmrnmhrm switched { form = form, otherWing = c.characteristics }) arena, { el | velocity = Velocity.zero } )

        LiveMycon _ ->
            if el.points < c.maxCrew then
                ( paid, arena, { el | points = min c.maxCrew (el.points + 4) } )

            else
                ( c, arena, el )

        LiveOrz _ _ ->
            if c.input.weapon && el.points > 1 && countOwned OrzMarine el.owner arena < 8 then
                let
                    ( next, a, _ ) =
                        launch (Missile (Arsenal.spec Marine)) (modBy 16 (facing + 8))
                in
                ( next, a, { el | points = el.points - 1 } )

            else
                ( c, arena, el )

        LivePkunk _ _ ->
            ( { paid | energy = min c.maxEnergy (c.energy + 2), specialWait = Wait 8 }, arena, el )

        LiveSlylandro _ ->
            let
                rocks =
                    Dict.values arena.elements |> List.filter (\other -> other.body == AsteroidBody && near 700 other)
            in
            if List.isEmpty rocks then
                ( c, arena, el )

            else
                ( { paid | energy = c.maxEnergy }, List.foldl (\rock state -> removeEl rock.id state) arena rocks, el )

        LiveSpathi _ ->
            launch (Missile (Arsenal.spec Butt)) (modBy 16 (facing + 8))

        LiveSupox _ _ ->
            let
                offset =
                    case ( c.input.thrust, c.input.turn ) of
                        ( True, TurnLeft ) ->
                            10

                        ( True, TurnRight ) ->
                            6

                        ( True, NoTurn ) ->
                            8

                        ( False, TurnLeft ) ->
                            -4

                        ( False, TurnRight ) ->
                            4

                        ( False, NoTurn ) ->
                            0

                ( velocity, _ ) =
                    inertialThrust el.velocity { c | facing = Facing (modBy 16 (facing + offset)) }
            in
            ( c
            , arena
            , if offset == 0 then
                el

              else
                { el | velocity = velocity }
            )

        LiveSyreen _ ->
            case enemy el.owner arena of
                Just other ->
                    if near 800 other && other.points > 1 then
                        let
                            count =
                                min 8 (other.points - 1)

                            crewShip =
                                { other | points = other.points - count }

                            release n state =
                                let
                                    at =
                                        Trig.wrapPoint state.space { x = other.next.location.x + Trig.cosine (n * 8) 90, y = other.next.location.y + Trig.sine (n * 8) 90 }

                                    id =
                                        ElementId state.nextElementId

                                    spawned =
                                        effect (CrewBody { origin = ownerSide other.owner }) at 240 state
                                in
                                updateElement id (\e -> { e | points = 1, mass = 1, flags = { emptyFlags | finiteLife = True, defyPhysics = True, crewObject = True } }) spawned
                        in
                        ( paid, List.foldl release (putEl crewShip arena) (List.range 1 count), el )

                    else
                        ( c, arena, el )

                Nothing ->
                    ( c, arena, el )

        LiveThraddash _ _ ->
            let
                burned =
                    fire (Missile (Arsenal.spec Napalm)) el c arena
            in
            ( { paid | specialWait = Wait 1 }, burned, { el | velocity = Velocity.setVector 80 c.facing } )

        LiveUmgah _ _ ->
            ( paid, arena, { el | velocity = Velocity.setVector 160 (Facing (modBy 16 (facing + 8))) } )

        LiveUrQuan _ ->
            if el.points > 2 && countOwned UrQuanFighter el.owner arena <= 6 then
                let
                    ( next, a, _ ) =
                        launch
                            (Missile
                                (let
                                    spec =
                                        Arsenal.spec Fighter
                                 in
                                 { spec | directions = [ -2, 2 ] }
                                )
                            )
                            facing
                in
                ( next, a, { el | points = el.points - 2 } )

            else
                ( c, arena, el )

        LiveUtwig _ ->
            ( { paid | shieldTicks = 12 }, arena, el )

        LiveVux _ _ ->
            launch
                (Missile
                    (let
                        spec =
                            Arsenal.spec Limpet
                     in
                     { spec | directions = [ 8 ] }
                    )
                )
                facing

        LiveYehat _ ->
            ( { paid | shieldTicks = 3 }, arena, el )

        LiveZoqFotPik _ ->
            launch (Contact Tongue) facing


steerWithSeed : Arena -> Element -> ( Arena, Element )
steerWithSeed arena el =
    case el.projectile of
        Just (Projectile.Flying Bubble flight) ->
            let
                (Wait animationWait) =
                    el.turnWait

                ( animationRandom, afterAnimation ) =
                    if animationWait == 0 then
                        Rng.next arena.seed

                    else
                        ( 0, arena.seed )

                ( turnRandom, seed ) =
                    if flight.trackingWait == 0 then
                        Rng.next afterAnimation

                    else
                        ( 0, afterAnimation )

                (Facing oldFacing) =
                    flight.facing

                target =
                    enemy el.owner arena

                desired =
                    target |> Maybe.map (\other -> bearing arena el.next.location other.next.location) |> Maybe.withDefault oldFacing

                delta =
                    modBy 16 (desired - oldFacing)

                facing =
                    if flight.trackingWait > 0 then
                        oldFacing

                    else
                        case target of
                            Nothing ->
                                modBy 16 turnRandom

                            Just _ ->
                                modBy 16
                                    (oldFacing
                                        + (if delta <= 8 then
                                            modBy 8 turnRandom

                                           else
                                            -(modBy 8 turnRandom)
                                          )
                                    )

                image =
                    el.next

                frame =
                    if animationWait == 0 then
                        modBy 3 (image.frameIndex + 1)

                    else
                        image.frameIndex
            in
            ( { arena | seed = seed }
            , { el
                | next = { image | frameIndex = frame }
                , turnWait =
                    Wait
                        (if animationWait == 0 then
                            modBy 4 animationRandom

                         else
                            animationWait - 1
                        )
                , projectile =
                    Just
                        (Projectile.Flying Bubble
                            { age = flight.age + 1
                            , facing = Facing facing
                            , trackingWait =
                                if flight.trackingWait == 0 then
                                    2

                                else
                                    flight.trackingWait - 1
                            }
                        )
                , velocity = Velocity.setComponents (Trig.cosine (facing * 4) 1024) (Trig.sine (facing * 4) 1024)
              }
            )

        _ ->
            ( arena, steer arena el )


steer : Arena -> Element -> Element
steer arena el =
    case el.projectile of
        Just (Projectile.Charging charge) ->
            case combatantOf el.owner arena of
                Just ship ->
                    let
                        c =
                            core ship

                        (Facing facing) =
                            c.facing

                        parent =
                            getEl c.element arena

                        at =
                            parent |> Maybe.map (\p -> Trig.wrapPoint arena.space { x = p.next.location.x + Trig.cosine (facing * 4) 96, y = p.next.location.y + Trig.sine (facing * 4) 96 }) |> Maybe.withDefault el.next.location

                        ticks =
                            charge.ticks + 1

                        damage =
                            2 * 2 ^ min 3 (ticks // 72)

                        image =
                            { location = at, frameIndex = animationFrame ChargeLevel facing (ticks // 2) damage }
                    in
                    { el
                        | current = image
                        , next = image
                        , mass = damage
                        , points = damage
                        , life =
                            Finite
                                (if c.input.weapon then
                                    2

                                 else
                                    10
                                )
                        , projectile =
                            Just
                                (if c.input.weapon then
                                    Projectile.Charging { ticks = ticks, facing = c.facing }

                                 else
                                    Projectile.Flying Charge { age = 0, facing = c.facing, trackingWait = 0 }
                                )
                        , velocity =
                            if c.input.weapon then
                                Velocity.zero

                            else
                                Velocity.setComponents (Trig.cosine (facing * 4) (180 * 32)) (Trig.sine (facing * 4) (180 * 32))
                    }

                Nothing ->
                    el

        Just (Projectile.Flying missile flight) ->
            flyMissile missile flight arena el

        Just (Projectile.Attached contact state) ->
            case combatantOf el.owner arena of
                Just ship ->
                    case getEl (core ship).element arena of
                        Just parent ->
                            let
                                (Facing facing) =
                                    (core ship).facing

                                age =
                                    state.age + 1

                                reach =
                                    if contact == Tongue then
                                        min 3 age * 32

                                    else
                                        0

                                at =
                                    Trig.wrapPoint arena.space { x = parent.next.location.x + Trig.cosine (facing * 4) reach, y = parent.next.location.y + Trig.sine (facing * 4) reach }
                            in
                            { el
                                | next =
                                    { location = at
                                    , frameIndex =
                                        facing
                                            + (if contact == Cone then
                                                modBy 3 age * 16

                                               else
                                                0
                                              )
                                    }
                                , projectile = Just (Projectile.Attached contact { age = age, facing = Facing facing })
                            }

                        Nothing ->
                            el

                Nothing ->
                    el

        _ ->
            case el.body of
                WeaponImpact missile ->
                    let
                        age =
                            el.colorCycleIndex - lifeTicks el.life

                        (Wait first) =
                            el.thrustWait

                        image =
                            el.next

                        frame =
                            if missile == Plasma then
                                first + min age (el.colorCycleIndex - 1 - age)

                            else
                                first + age
                    in
                    { el | next = { image | frameIndex = frame } }

                _ ->
                    steerLegacy arena el


flyMissile : MissileKind -> { age : Int, facing : Facing, trackingWait : Int } -> Arena -> Element -> Element
flyMissile missile flight arena el =
    let
        spec =
            Arsenal.spec missile

        age =
            flight.age + 1

        (Facing oldFacing) =
            flight.facing

        target =
            enemy el.owner arena

        desired =
            target |> Maybe.map (\other -> bearing arena el.next.location other.next.location) |> Maybe.withDefault oldFacing

        turn wanted =
            let
                delta =
                    modBy 16 (wanted - oldFacing)
            in
            modBy 16
                (oldFacing
                    + (if delta == 0 then
                        0

                       else if delta <= 8 then
                        1

                       else
                        -1
                      )
                )

        ( facing, trackingWait ) =
            case spec.guidance of
                Tracking tracking ->
                    if flight.trackingWait > 0 then
                        ( oldFacing, flight.trackingWait - 1 )

                    else
                        ( turn desired, tracking.wait )

                BubbleFlight ->
                    if modBy 3 age == 0 then
                        ( turn desired, 0 )

                    else
                        ( oldFacing, 0 )

                _ ->
                    ( oldFacing, 0 )

        frame =
            if missile == Shard then
                1

            else if missile == Spit then
                min 12 ((age + 2) // 3)

            else
                animationFrame spec.animation facing age el.mass

        remaining =
            lifeTicks el.life

        plasmaLife =
            if missile == Plasma && el.points < el.mass then
                el.points * 13

            else
                remaining

        plasmaDamage =
            max 1 ((plasmaLife * 10 + 142) // 143)

        speed =
            case missile of
                Nuke ->
                    min 80 (40 + age * 4)

                Spit ->
                    max 0 ((13 - min 12 ((age + 2) // 3)) * 8)

                _ ->
                    spec.speed

        velocity =
            case spec.guidance of
                HeldBlade ->
                    if combatantOf el.owner arena |> Maybe.map (core >> .input >> .weapon) |> Maybe.withDefault False then
                        el.velocity

                    else
                        let
                            ( vx, vy ) =
                                Velocity.getCurrent el.velocity
                        in
                        if abs vx + abs vy > 32 then
                            Velocity.setComponents (vx // 2) (vy // 2)

                        else if target |> Maybe.map (\other -> distance arena el.next.location other.next.location < 200 * 4) |> Maybe.withDefault False then
                            Velocity.setComponents (Trig.cosine (desired * 4) 256) (Trig.sine (desired * 4) 256)

                        else
                            Velocity.zero

                Tracking _ ->
                    Velocity.setComponents (Trig.cosine (facing * 4) (speed * 32)) (Trig.sine (facing * 4) (speed * 32))

                BubbleFlight ->
                    Velocity.setComponents (Trig.cosine (facing * 4) (speed * 32)) (Trig.sine (facing * 4) (speed * 32))

                Ballistic ->
                    if missile == Spit then
                        Velocity.setComponents (Trig.cosine (facing * 4) (speed * 32)) (Trig.sine (facing * 4) (speed * 32))

                    else
                        el.velocity

        image =
            el.next
    in
    { el
        | projectile = Just (Projectile.Flying missile { age = age, facing = Facing facing, trackingWait = trackingWait })
        , next =
            { image
                | frameIndex =
                    if missile == Plasma then
                        min 10 (11 - (plasmaLife + 12) // 13)

                    else
                        frame
            }
        , velocity = velocity
        , points =
            if missile == Plasma then
                plasmaDamage

            else
                el.points
        , mass =
            if missile == Plasma then
                plasmaDamage

            else
                el.mass
        , life =
            if missile == Plasma then
                Finite plasmaLife

            else if missile == Crystal then
                Finite (remaining + 1)

            else if missile == Saw && not (combatantOf el.owner arena |> Maybe.map (core >> .input >> .weapon) |> Maybe.withDefault False) then
                Finite (remaining + 1)

            else
                el.life
    }


steerLegacy : Arena -> Element -> Element
steerLegacy arena el =
    let
        target =
            case el.body of
                CrewBody _ ->
                    Dict.values arena.elements |> List.filter (\ship -> ship.flags.playerShip) |> List.sortBy (\ship -> distance arena el.next.location ship.next.location) |> List.head

                _ ->
                    enemy el.owner arena
    in
    if Arsenal.homing el.body || el.flags.crewObject then
        case target of
            Nothing ->
                el

            Just other ->
                let
                    wanted =
                        bearing arena el.next.location other.next.location

                    difference =
                        modBy 16 (wanted - el.next.frameIndex)

                    facing =
                        modBy 16
                            (el.next.frameIndex
                                + (if difference == 0 then
                                    0

                                   else if difference <= 8 then
                                    1

                                   else
                                    -1
                                  )
                            )

                    image =
                        el.next

                    ( vx, vy ) =
                        Velocity.getCurrent el.velocity

                    speed =
                        if el.flags.crewObject then
                            12 * 32

                        else
                            max 640 (Trig.squareRoot (vx * vx + vy * vy))
                in
                { el | next = { image | frameIndex = facing }, velocity = Velocity.setComponents (Trig.cosine (facing * 4) speed) (Trig.sine (facing * 4) speed) }

    else if el.body == KohrAhSaw then
        case combatantOf el.owner arena of
            Just combatant ->
                if not (core combatant).input.weapon then
                    { el | velocity = Velocity.zero }

                else
                    el

            Nothing ->
                el

    else
        el


collectCrew : Element -> Element -> Arena -> Arena
collectCrew ship crew arena =
    if ship.flags.playerShip && crew.flags.crewObject then
        case combatantOf ship.owner arena of
            Just combatant ->
                if ship.points < (core combatant).maxCrew then
                    arena |> putEl { ship | points = ship.points + 1 } |> removeEl crew.id

                else
                    arena

            Nothing ->
                arena

    else
        arena


prepareAbilities : Arena -> Arena
prepareAbilities arena =
    let
        prepare side state =
            let
                combatant =
                    if side == Bottom then
                        state.combatants.bottom

                    else
                        state.combatants.top

                c =
                    core combatant
            in
            case getEl c.element state of
                Nothing ->
                    state

                Just el ->
                    case combatant of
                        LiveAndrosynth _ (Blazer saved) ->
                            if c.energy <= 0 then
                                mapCombatant side (\_ -> LiveAndrosynth { c | characteristics = saved.guardian } Guardian) state

                            else
                                let
                                    burned =
                                        { c | energy = max 0 (c.energy - 1) }

                                    hit =
                                        case enemy el.owner state of
                                            Just other ->
                                                if distance state el.next.location other.next.location < 110 then
                                                    damageShip 3 other state

                                                else
                                                    state

                                            Nothing ->
                                                state
                                in
                                hit |> mapCombatant side (setCore burned) |> updateElement el.id (\e -> { e | velocity = Velocity.setVector 60 c.facing })

                        LiveChenjesu _ ->
                            if c.oldInput.weapon && not c.input.weapon then
                                Dict.values state.elements
                                    |> List.filter (\e -> e.owner == el.owner && e.body == ChenjesuPhoton)
                                    |> List.foldl (\crystal a -> fire (Missile (Arsenal.spec Shard)) crystal c (removeEl crystal.id a)) state

                            else
                                state

                        LiveVux _ WarpPending ->
                            case enemy el.owner state of
                                Just target ->
                                    let
                                        angle =
                                            bearing state target.next.location el.next.location * 4

                                        at =
                                            Trig.wrapPoint state.space { x = target.next.location.x + Trig.cosine angle 420, y = target.next.location.y + Trig.sine angle 420 }

                                        facing =
                                            bearing state at target.next.location

                                        image =
                                            { location = at, frameIndex = facing }
                                    in
                                    state |> putEl { el | current = image, next = image } |> mapCombatant side (\_ -> LiveVux { c | facing = Facing facing } OnField)

                                Nothing ->
                                    state

                        LiveSlylandro _ ->
                            updateElement el.id
                                (\e ->
                                    { e
                                        | velocity = Velocity.setVector c.characteristics.maxThrust c.facing
                                        , flags =
                                            let
                                                f =
                                                    e.flags
                                            in
                                            { f | defyPhysics = True }
                                    }
                                )
                                state

                        LiveArilou _ _ ->
                            updateElement el.id
                                (\e ->
                                    { e
                                        | velocity =
                                            if c.input.thrust then
                                                e.velocity

                                            else
                                                Velocity.zero
                                        , flags =
                                            let
                                                f =
                                                    e.flags
                                            in
                                            { f | defyPhysics = True }
                                    }
                                )
                                state

                        _ ->
                            state
    in
    List.foldl prepare arena [ Bottom, Top ]


environment : Arena -> Arena
environment arena =
    let
        (FrameCount frame) =
            arena.frame

        rocks =
            Dict.values arena.elements |> List.filter (\e -> e.body == AsteroidBody) |> List.length
    in
    if modBy 120 frame == 0 && rocks < 5 then
        let
            ( x, s1 ) =
                Rng.next arena.seed

            ( y, s2 ) =
                Rng.next s1

            at =
                { x = modBy arena.space.width x, y = modBy arena.space.height y }

            id =
                ElementId arena.nextElementId

            spawned =
                effect AsteroidBody at 1200 { arena | seed = s2 }
        in
        updateElement id (\e -> { e | points = 3, mass = 3, flags = { emptyFlags | finiteLife = True }, velocity = Velocity.setVector 12 (Facing (modBy 16 x)) }) spawned

    else
        arena


auxiliaries : Arena -> Arena
auxiliaries arena =
    let
        act id state =
            case getEl id state of
                Nothing ->
                    state

                Just pet ->
                    if isSatellite pet then
                        case combatantOf pet.owner state of
                            Just ship ->
                                case getEl (core ship).element state of
                                    Nothing ->
                                        removeEl pet.id state

                                    Just parent ->
                                        let
                                            (FrameCount frame) =
                                                state.frame

                                            orbitIndex =
                                                case pet.body of
                                                    ChmmrSatellite extra ->
                                                        let
                                                            (Facing index) =
                                                                extra.orbitFacing
                                                        in
                                                        index

                                                    _ ->
                                                        0

                                            angle =
                                                frame + orbitIndex * 21

                                            at =
                                                Trig.wrapPoint state.space { x = parent.next.location.x + Trig.cosine angle 150, y = parent.next.location.y + Trig.sine angle 150 }

                                            image =
                                                { location = at, frameIndex = modBy 16 frame }

                                            moved =
                                                { pet | current = image, next = image }

                                            next =
                                                putEl moved state

                                            threats =
                                                Dict.values next.elements |> List.filter (\e -> e.owner /= pet.owner && (isWeapon e || e.flags.playerShip) && distance next at e.next.location < 220)
                                        in
                                        if modBy 6 frame == orbitIndex then
                                            List.foldl
                                                (\target result ->
                                                    if target.flags.playerShip then
                                                        damageShip 1 target result

                                                    else
                                                        removeEl target.id result
                                                )
                                                next
                                                threats

                                        else
                                            next

                            Nothing ->
                                state

                    else if List.member pet.body [ OrzMarine, UrQuanFighter, ChenjesuDogi ] then
                        case enemy pet.owner state of
                            Just target ->
                                let
                                    range =
                                        if pet.body == UrQuanFighter then
                                            220

                                        else
                                            95

                                    close =
                                        distance state pet.next.location target.next.location < range
                                in
                                if not (waitReady pet.thrustWait) then
                                    putEl { pet | thrustWait = decWait pet.thrustWait } state

                                else if close then
                                    let
                                        hit =
                                            if pet.body == ChenjesuDogi then
                                                case combatantOf target.owner state of
                                                    Just ship ->
                                                        let
                                                            c =
                                                                core ship
                                                        in
                                                        mapCombatant (ownerSide target.owner) (setCore { c | energy = max 0 (c.energy - 10) }) state

                                                    Nothing ->
                                                        state

                                            else
                                                damageShip
                                                    (if pet.body == OrzMarine then
                                                        1

                                                     else
                                                        pet.mass
                                                    )
                                                    target
                                                    state

                                        next =
                                            { pet
                                                | thrustWait =
                                                    Wait
                                                        (if pet.body == OrzMarine then
                                                            18

                                                         else
                                                            12
                                                        )
                                                , velocity =
                                                    if pet.body == ChenjesuDogi then
                                                        Velocity.setVector 50 (Facing (modBy 16 (pet.next.frameIndex + 8)))

                                                    else
                                                        pet.velocity
                                            }
                                    in
                                    effect BlastBody target.next.location 4 (putEl next hit)

                                else
                                    state

                            Nothing ->
                                let
                                    opponent =
                                        if pet.owner == Owned Bottom then
                                            state.combatants.top

                                        else
                                            state.combatants.bottom
                                in
                                if getEl (core opponent).element state /= Nothing then
                                    state

                                else
                                    case combatantOf pet.owner state of
                                        Nothing ->
                                            state

                                        Just ship ->
                                            case getEl (core ship).element state of
                                                Nothing ->
                                                    removeEl pet.id state

                                                Just parent ->
                                                    if distance state pet.next.location parent.next.location < 120 then
                                                        state
                                                            |> removeEl pet.id
                                                            |> putEl
                                                                { parent
                                                                    | points =
                                                                        min (core ship).maxCrew
                                                                            (parent.points
                                                                                + (if pet.body == ChenjesuDogi then
                                                                                    0

                                                                                   else
                                                                                    1
                                                                                  )
                                                                            )
                                                                }

                                                    else
                                                        putEl { pet | velocity = Velocity.setVector 48 (Facing (bearing state pet.next.location parent.next.location)) } state

                    else
                        state
    in
    List.foldl act arena arena.queue


isSatellite : Element -> Bool
isSatellite element =
    case element.body of
        ChmmrSatellite _ ->
            True

        _ ->
            False


countOwned : Body -> Owner -> Arena -> Int
countOwned body owner arena =
    Dict.values arena.elements |> List.filter (\el -> el.owner == owner && el.body == body) |> List.length
