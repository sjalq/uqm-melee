module Melee.Cyborg exposing (maneuverability, think)

{-| Original Super Melee cyborg (cyborg.c, intel.c, per-ship intelligence_func).

`think` is pure and shared: local hot-seat on the FE and exhibition / computer
seats on the BE both call it. It emits `BattleInput` only. It never allocates
dummy weapons (C `init_weapon_func` + FreeElement); intercepts use the same
circle test the stepper uses.

PlotIntercept is linear coast + circle, not DrawablesIntersect. That is the
env adjustment. Ratings still change intercept margin and Standard still
suppresses specials.

-}

import Dict exposing (Dict)
import Melee.Battle exposing (Arena)
import Melee.Element exposing (Body(..), Element, Life(..), Owner(..), objectCloaked)
import Melee.Id exposing (toInt)
import Melee.Input exposing (BattleInput, CyborgRating(..), Turn(..))
import Melee.Rng as Rng exposing (Seed)
import Melee.Ship exposing (Ability, Characteristics, ShipKind(..), intelRange, stock)
import Melee.ShipState as State exposing (AndrosynthExtra(..), Combatant(..), CombatantCore)
import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), Side(..), Wait(..), WorldExtent, WorldPoint, gravityMassThreshold, maxShipMass)
import Melee.Velocity as Velocity


closeRange : Int
closeRange =
    200


longRange : Int
longRange =
    4000


fastShip : Int
fastShip =
    150


mediumShip : Int
mediumShip =
    45


slowShip : Int
slowShip =
    25


fullCircle : Int
fullCircle =
    64


halfCircle : Int
halfCircle =
    32


quadrant : Int
quadrant =
    16


octant : Int
octant =
    8


displayToWorld : Int -> Int
displayToWorld n =
    n * 4


worldToTurn : Int -> Int
worldToTurn d =
    d // 64


type MoveState
    = NoMovement
    | Pursue
    | Entice
    | Avoid


type alias Eval =
    { object : Maybe Element
    , move : MoveState
    , facing : Int
    , whichTurn : Int
    }


type alias Concerns =
    { enemy : Eval
    , crew : Eval
    , weapon : Eval
    , gravity : Eval
    , empty : Eval
    }


type alias Work =
    { ship : Element
    , core : CombatantCore
    , kind : ShipKind
    , ability : Ability
    , mi : Int
    , range : Int
    , facing : Int
    , velocity : Melee.Units.VelocityDesc
    , next : WorldPoint
    , turnWait : Int
    , thrustWait : Int
    , left : Bool
    , right : Bool
    , thrust : Bool
    , weapon : Bool
    , special : Bool
    , seed : Seed
    , space : WorldExtent
    , rating : CyborgRating
    , moved : Bool
    , fired : Bool
    , arena : Arena
    , side : Side
    }


blank : Eval
blank =
    { object = Nothing, move = NoMovement, facing = 0, whichTurn = 65535 }


maneuverability : Characteristics -> Int
maneuverability chars =
    let
        index =
            chars.maxThrust * chars.thrustIncrement

        divisor =
            waitN chars.turnWait + waitN chars.thrustWait
    in
    if divisor > 0 then
        index // divisor

    else
        index // 2


think : CyborgRating -> Side -> Arena -> Seed -> ( BattleInput, Seed )
think rating side arena seed =
    case Dict.get (toInt (State.core (combatant side arena)).element) arena.elements of
        Nothing ->
            ( idle, seed )

        Just ship ->
            if ship.points == 0 then
                ( idle, seed )

            else
                let
                    core =
                        State.core (combatant side arena)

                    kind =
                        State.kind (combatant side arena)

                    spec =
                        stock kind

                    chars =
                        core.characteristics

                    mi =
                        maneuverability chars

                    (Facing facing) =
                        core.facing

                    work0 =
                        { ship = ship
                        , core = core
                        , kind = kind
                        , ability = spec.ability
                        , mi = mi
                        , range = intelRange kind
                        , facing = facing
                        , velocity = ship.velocity
                        , next = ship.next.location
                        , turnWait = waitN ship.turnWait
                        , thrustWait = waitN ship.thrustWait
                        , left = False
                        , right = False
                        , thrust = False
                        , weapon = False
                        , special = False
                        , seed = seed
                        , space = arena.space
                        , rating = rating
                        , moved = waitN ship.turnWait > 0 && waitN ship.thrustWait > 0
                        , fired = waitN core.weaponWait > 0 || spec.ability.seekingWeapon
                        , arena = arena
                        , side = side
                        }

                    concerns =
                        fillConcerns work0

                    work1 =
                        raceIntelligence work0 concerns
                in
                ( { turn =
                        if work1.left then
                            TurnLeft

                        else if work1.right then
                            TurnRight

                        else
                            NoTurn
                  , thrust = work1.thrust
                  , weapon = work1.weapon
                  , special =
                        if rating == StandardCyborg then
                            False

                        else
                            work1.special
                  }
                , work1.seed
                )


idle : BattleInput
idle =
    { turn = NoTurn, thrust = False, weapon = False, special = False }


combatant : Side -> Arena -> Combatant
combatant side arena =
    case side of
        Bottom ->
            arena.combatants.bottom

        Top ->
            arena.combatants.top


otherSide : Side -> Side
otherSide side =
    case side of
        Bottom ->
            Top

        Top ->
            Bottom


waitN : Wait -> Int
waitN (Wait n) =
    n


weaponReady : Work -> Bool
weaponReady work =
    waitN work.core.weaponWait <= 0


specialReady : Work -> Bool
specialReady work =
    waitN work.core.specialWait <= 0 && work.rating /= StandardCyborg


ultra : Work -> Bool
ultra work =
    work.core.characteristics.thrustIncrement == work.core.characteristics.maxThrust && work.mi >= mediumShip


isGravity : Element -> Bool
isGravity el =
    el.mass > gravityMassThreshold


isCrew : Element -> Bool
isCrew el =
    el.flags.crewObject || isCrewBody el.body


isCrewBody : Body -> Bool
isCrewBody body =
    case body of
        CrewBody _ ->
            True

        _ ->
            False


isShip : Element -> Bool
isShip el =
    el.flags.playerShip


samePlayer : Element -> Element -> Bool
samePlayer a b =
    a.parent == b.parent && a.parent /= Nothing


colliding : Element -> Bool
colliding el =
    not (el.flags.nonsolid || el.flags.disappearing)


radiusWorld : Element -> Int
radiusWorld el =
    case el.body of
        PlanetBody ->
            160

        ShipBody _ ->
            40

        AsteroidBody ->
            24

        CrewBody _ ->
            16

        _ ->
            12


travelAngle : Melee.Units.VelocityDesc -> Int
travelAngle vel =
    case vel.travelAngle of
        Angle a ->
            a


isVelocityZero : Melee.Units.VelocityDesc -> Bool
isVelocityZero vel =
    vel.vector.width == 0 && vel.vector.height == 0


displacement : Int -> Melee.Units.VelocityDesc -> ( Int, Int )
displacement turns vel =
    Velocity.getNext (max 1 turns) vel |> Tuple.first


wrapLoc : WorldExtent -> WorldPoint -> WorldPoint
wrapLoc =
    Trig.wrapPoint


angleToFacing : Int -> Int
angleToFacing a =
    Trig.normalizeFacing ((Trig.normalizeAngle a + 2) // 4)


facingToAngle : Int -> Int
facingToAngle f =
    Trig.normalizeFacing f * 4


marginOfError : CyborgRating -> Int
marginOfError rating =
    case rating of
        AwesomeCyborg ->
            0

        GoodCyborg ->
            displayToWorld 20

        StandardCyborg ->
            displayToWorld 40


{-| Circle-coast intercept. C uses DrawablesIntersect; we use the stepper's
circle, plus `margin` as C's error box.
-}
plotIntercept : WorldExtent -> Element -> Element -> Int -> Int -> Int
plotIntercept space a b maxTurns margin =
    if maxTurns <= 0 then
        0

    else
        plotFrom space a b margin maxTurns 1


plotFrom : WorldExtent -> Element -> Element -> Int -> Int -> Int -> Int
plotFrom space a b margin maxTurns t =
    if t > maxTurns then
        0

    else
        let
            ( dax, day ) =
                displacement t a.velocity

            ( dbx, dby ) =
                displacement t b.velocity

            pa =
                wrapLoc space { x = a.current.location.x + dax, y = a.current.location.y + day }

            pb =
                wrapLoc space { x = b.current.location.x + dbx, y = b.current.location.y + dby }

            dx =
                Trig.wrapDelta (pa.x - pb.x) space.width

            dy =
                Trig.wrapDelta (pa.y - pb.y) space.height

            r =
                radiusWorld a + radiusWorld b + margin
        in
        if dx * dx + dy * dy <= r * r then
            t

        else
            plotFrom space a b margin maxTurns (t + 1)


fillConcerns : Work -> Concerns
fillConcerns work =
    let
        start =
            { enemy = blank, crew = blank, weapon = blank, gravity = blank, empty = blank }
    in
    Dict.foldl (\_ el concerns -> consider work el concerns) start work.arena.elements


consider : Work -> Element -> Concerns -> Concerns
consider work el concerns =
    if el.id == work.ship.id || not (colliding el) || not (colliding work.ship) then
        concerns

    else
        let
            dx =
                Trig.wrapDelta (el.next.location.x - work.ship.next.location.x) work.space.width

            dy =
                Trig.wrapDelta (el.next.location.y - work.ship.next.location.y) work.space.height
        in
        if isGravity el then
            considerGravity work el dx dy concerns

        else if isShip el then
            considerEnemy work el dx dy concerns

        else if el.parent == Nothing then
            considerEmpty work el dx dy concerns

        else if not (samePlayer el work.ship) && not (isCrew el) && concerns.weapon.whichTurn > 1 && lifeSpan el > 0 then
            considerWeapon work el dx dy concerns

        else if isCrew el && concerns.crew.whichTurn > 1 then
            considerCrew work el dx dy concerns

        else
            concerns


lifeSpan : Element -> Int
lifeSpan el =
    case el.life of
        Finite n ->
            n

        Persistent n ->
            n


considerGravity : Work -> Element -> Int -> Int -> Concerns -> Concerns
considerGravity work el _ _ concerns =
    if work.moved then
        concerns

    else
        let
            maneuverTurn =
                if ultra work then
                    16

                else if work.mi <= mediumShip then
                    48

                else
                    32

            bounds =
                80

            hit =
                plotIntercept work.space el work.ship maneuverTurn (displayToWorld (30 + bounds * 3))
        in
        if hit > 0 then
            if hit > 1 || plotIntercept work.space el work.ship 1 (displayToWorld (35 + bounds)) > 0 || plotIntercept work.space el work.ship (maneuverTurn * 2) (displayToWorld (40 + bounds)) > 1 then
                { concerns
                    | gravity =
                        { object = Just el
                        , move =
                            if ultra work then
                                Avoid

                            else
                                Entice
                        , facing = Trig.arctan -(Trig.wrapDelta (el.next.location.x - work.ship.next.location.x) work.space.width) -(Trig.wrapDelta (el.next.location.y - work.ship.next.location.y) work.space.height)
                        , whichTurn = hit
                        }
                }

            else
                concerns

        else
            concerns


considerEnemy : Work -> Element -> Int -> Int -> Concerns -> Concerns
considerEnemy work el dx dy concerns =
    let
        turns =
            max 1 (worldToTurn (Trig.squareRoot (dx * dx + dy * dy)))
    in
    if turns > concerns.enemy.whichTurn then
        concerns

    else
        let
            enemy =
                combatant (otherSide work.side) work.arena

            enemyChars =
                (State.core enemy).characteristics

            foeMi =
                maneuverability enemyChars

            foeRange =
                intelRange (State.kind enemy)

            foeAbility =
                (stock (State.kind enemy)).ability

            shouldPursue =
                work.moved
                    || el.mass > maxShipMass
                    || (work.range < longRange
                            && (work.range <= closeRange
                                    || (foeRange >= longRange && foeAbility.seekingWeapon)
                                    || (work.core.characteristics.maxThrust < enemyChars.maxThrust && work.range < foeRange)
                               )
                       )

            (Facing enemyFacing) =
                (State.core enemy).facing

            facing =
                facingToAngle enemyFacing

            withEnemy =
                { concerns
                    | enemy =
                        { object = Just el
                        , move =
                            if shouldPursue then
                                Pursue

                            else
                                Entice
                        , facing = facing
                        , whichTurn = turns
                        }
                }

            threat =
                { work
                    | kind = State.kind enemy
                    , ability = foeAbility
                    , range = foeRange
                    , facing = enemyFacing
                    , core = State.core enemy
                    , ship = el
                }
        in
        if foeAbility.immediateWeapon && shipWeapons threat work.ship 0 then
            { withEnemy
                | weapon =
                    { object = Just el
                    , move = Avoid
                    , facing = facing
                    , whichTurn = 1
                    }
            }

        else
            withEnemy


considerEmpty : Work -> Element -> Int -> Int -> Concerns -> Concerns
considerEmpty work el dx dy concerns =
    if el.flags.finiteLife then
        concerns

    else
        let
            turns =
                worldToTurn (Trig.squareRoot (dx * dx + dy * dy))
        in
        if turns < concerns.empty.whichTurn then
            { concerns
                | empty =
                    { object = Just el
                    , move = Pursue
                    , facing = travelAngle el.velocity
                    , whichTurn = max 1 turns
                    }
            }

        else
            concerns


considerWeapon : Work -> Element -> Int -> Int -> Concerns -> Concerns
considerWeapon work el dx dy concerns =
    let
        owner =
            case el.parent of
                Just side ->
                    Just (combatant side work.arena)

                Nothing ->
                    Nothing

        ability =
            owner |> Maybe.map (\c -> (stock (State.kind c)).ability) |> Maybe.withDefault (stock Shofixti).ability

        seeking =
            (ability.seekingWeapon && not (isSpecialBody el.body)) || (ability.seekingSpecial && isSpecialBody el.body)

        eval =
            if seeking then
                seekingWeapon work el dx dy

            else if work.rating /= AwesomeCyborg then
                { object = Nothing, move = NoMovement, facing = 0, whichTurn = 0 }

            else
                let
                    hit =
                        plotIntercept work.space el work.ship (lifeSpan el) (displayToWorld 40)
                in
                { object = Just el, move = Avoid, facing = travelAngle el.velocity, whichTurn = hit }
    in
    if eval.whichTurn > 0 && (eval.whichTurn < concerns.weapon.whichTurn || (eval.whichTurn == concerns.weapon.whichTurn && eval.move == Avoid)) then
        { concerns | weapon = eval }

    else
        concerns


seekingWeapon : Work -> Element -> Int -> Int -> Eval
seekingWeapon work el dx dy =
    let
        closing =
            Trig.normalizeAngle (travelAngle el.velocity - Trig.arctan -dx -dy + quadrant) > halfCircle

        turns0 =
            worldToTurn (Trig.squareRoot (dx * dx + dy * dy))

        turns =
            if not el.flags.finiteLife && not el.flags.crewObject && work.core.characteristics.maxThrust > displayToWorld 8 then
                0

            else if closing then
                0

            else if ultra work then
                if turns0 == 0 then
                    1

                else if turns0 > 16 then
                    0

                else
                    turns0

            else if turns0 == 0 then
                1

            else if turns0 > 16 || (work.mi > mediumShip && turns0 > 8) then
                0

            else
                turns0
    in
    if turns > 0 then
        { object = Just el, move = Entice, facing = travelAngle el.velocity, whichTurn = turns }

    else
        { object = Nothing, move = NoMovement, facing = 0, whichTurn = 0 }


isSpecialBody : Body -> Bool
isSpecialBody body =
    case body of
        ChenjesuDogi ->
            True

        ChmmrSatellite _ ->
            True

        ChmmrZap ->
            True

        EarthlingPointDefense ->
            True

        KohrAhFried ->
            True

        MelnormeConfusion ->
            True

        OrzMarine ->
            True

        ShofixtiGlory ->
            True

        SpathiButt ->
            True

        ThraddashAfterburn ->
            True

        UrQuanFighter ->
            True

        VuxLimpet ->
            True

        _ ->
            False


considerCrew : Work -> Element -> Int -> Int -> Concerns -> Concerns
considerCrew work el dx dy concerns =
    let
        ours =
            (not el.flags.ignoreSimilar && samePlayer el work.ship) || isCrew el

        turns =
            max 1 (worldToTurn (Trig.squareRoot (dx * dx + dy * dy)))
    in
    if
        ours
            && concerns.crew.whichTurn > turns
            && (concerns.enemy.whichTurn > 32 || (concerns.enemy.whichTurn > 8 && work.ship.target == Just el.id))
    then
        { concerns | crew = { object = Just el, move = Pursue, facing = 0, whichTurn = turns } }

    else
        concerns


shipIntelligence : Work -> Concerns -> Work
shipIntelligence work0 concerns =
    let
        margin =
            let
                m =
                    marginOfError work0.rating
            in
            if
                concerns.enemy.object
                    |> Maybe.map (\el -> objectCloaked el.prim)
                    |> Maybe.withDefault False
            then
                m + displayToWorld 40

            else
                m

        work1 =
            if work0.turnWait == 0 then
                { work0 | left = False, right = False, moved = False }

            else
                work0

        work2 =
            if work1.thrustWait == 0 then
                { work1 | thrust = False, moved = False }

            else
                work1

        afterGravity =
            moveAndFire work2 concerns.gravity False True margin

        afterWeapon =
            moveAndFire afterGravity concerns.weapon True (concerns.weapon.move /= Avoid) margin

        afterCrew =
            moveAndFire afterWeapon concerns.crew False True margin
    in
    moveAndFire afterCrew concerns.enemy True True margin


moveAndFire : Work -> Eval -> Bool -> Bool -> Int -> Work
moveAndFire work eval fireOk fireTarget margin =
    case eval.object of
        Nothing ->
            work

        Just other ->
            let
                moved =
                    if
                        not work.moved
                            && (not fireOk || eval.move == Pursue || other.flags.crewObject || work.mi >= mediumShip)
                    then
                        shipMovement { work | moved = True } eval

                    else
                        work

                fired =
                    if not moved.fired && fireOk && fireTarget then
                        if shipWeapons moved other margin then
                            { moved | weapon = True, fired = True }

                        else
                            moved

                    else
                        moved
            in
            fired


shipMovement : Work -> Eval -> Work
shipMovement work eval =
    let
        eval1 =
            if eval.whichTurn == 0 then
                { eval | whichTurn = 1 }

            else
                eval
    in
    case eval1.move of
        Pursue ->
            pursue work eval1

        Avoid ->
            entice work eval1

        Entice ->
            entice work eval1

        NoMovement ->
            work


shipWeapons : Work -> Element -> Int -> Bool
shipWeapons work other margin =
    if work.ability.seekingWeapon then
        False

    else if not (weaponReady work) then
        False

    else if work.ability.immediateWeapon then
        let
            dx =
                Trig.wrapDelta (other.current.location.x - work.ship.current.location.x) work.space.width

            dy =
                Trig.wrapDelta (other.current.location.y - work.ship.current.location.y) work.space.height

            dist =
                Trig.squareRoot (dx * dx + dy * dy)

            wanted =
                angleToFacing (Trig.arctan dx dy)

            delta =
                Trig.normalizeFacing (wanted - work.facing)
        in
        dist <= work.range && (delta <= 1 || delta >= 15)

    else
        case shot work.kind of
            Nothing ->
                let
                    dx =
                        Trig.wrapDelta (other.current.location.x - work.ship.current.location.x) work.space.width

                    dy =
                        Trig.wrapDelta (other.current.location.y - work.ship.current.location.y) work.space.height
                in
                Trig.squareRoot (dx * dx + dy * dy) <= work.range && facingAligned work other

            Just spec ->
                let
                    angle =
                        facingToAngle work.facing

                    ship =
                        work.ship

                    ghost : Element
                    ghost =
                        { ship
                            | current =
                                { location =
                                    { x = ship.next.location.x + Trig.cosine angle spec.offset
                                    , y = ship.next.location.y + Trig.sine angle spec.offset
                                    }
                                , frameIndex = work.facing
                                }
                            , velocity = Velocity.setVector spec.speed (Facing work.facing)
                            , body = ShofixtiDart
                        }
                in
                plotIntercept work.space ghost other spec.life margin > 0


facingAligned : Work -> Element -> Bool
facingAligned work other =
    let
        dx =
            Trig.wrapDelta (other.current.location.x - work.ship.current.location.x) work.space.width

        dy =
            Trig.wrapDelta (other.current.location.y - work.ship.current.location.y) work.space.height

        wanted =
            angleToFacing (Trig.arctan dx dy)

        delta =
            Trig.normalizeFacing (wanted - work.facing)
    in
    delta <= 2 || delta >= 14


type alias Shot =
    { speed : Int, life : Int, offset : Int }


shot : ShipKind -> Maybe Shot
shot kind =
    let
        d n =
            displayToWorld n
    in
    case kind of
        Shofixti ->
            Just { speed = d 24, life = 10, offset = d 15 }

        Yehat ->
            Just { speed = d 20, life = 10, offset = d 15 }

        Spathi ->
            Just { speed = d 30, life = 10, offset = d 15 }

        Thraddash ->
            Just { speed = d 30, life = 15, offset = d 15 }

        Druuge ->
            Just { speed = d 30, life = 20, offset = d 15 }

        Pkunk ->
            Just { speed = d 24, life = 5, offset = d 15 }

        Orz ->
            Just { speed = d 30, life = 12, offset = d 15 }

        Chenjesu ->
            Just { speed = d 16, life = 90, offset = d 15 }

        Ilwrath ->
            Just { speed = 25, life = 8, offset = d 15 }

        Utwig ->
            Just { speed = d 30, life = 10, offset = d 15 }

        Supox ->
            Just { speed = d 30, life = 10, offset = d 15 }

        UrQuan ->
            Just { speed = d 20, life = 20, offset = d 15 }

        Syreen ->
            Just { speed = d 30, life = 10, offset = d 15 }

        Mmrnmhrm ->
            Just { speed = d 20, life = 40, offset = d 15 }

        Mycon ->
            Just { speed = d 8, life = 40, offset = d 15 }

        ZoqFotPik ->
            Just { speed = d 10, life = 10, offset = d 15 }

        KohrAh ->
            Just { speed = 64, life = 64, offset = d 15 }

        Earthling ->
            Just { speed = d 20, life = 60, offset = d 15 }

        _ ->
            Nothing


pursue : Work -> Eval -> Work
pursue work eval =
    case eval.object of
        Nothing ->
            work

        Just other ->
            let
                ( shipDx, shipDy ) =
                    displacement eval.whichTurn work.velocity

                ( otherDx, otherDy ) =
                    displacement eval.whichTurn other.velocity

                next =
                    wrapLoc work.space { x = work.ship.current.location.x + shipDx, y = work.ship.current.location.y + shipDy }

                deltaX =
                    Trig.wrapDelta ((other.current.location.x + otherDx) - next.x) work.space.width

                deltaY =
                    Trig.wrapDelta ((other.current.location.y + otherDy) - next.y) work.space.height

                desiredThrust =
                    Trig.arctan deltaX deltaY

                canTurn =
                    work.turnWait == 0

                canThrust =
                    work.thrustWait == 0 && (isShip other || samePlayer other work.ship || isCrew other)

                work1 =
                    { work | next = next }

                work2 =
                    if canTurn then
                        turnShip work1 desiredThrust

                    else
                        work1
            in
            if canThrust then
                thrustShip work2 desiredThrust

            else
                work2


entice : Work -> Eval -> Work
entice work eval =
    case eval.object of
        Nothing ->
            work

        Just other ->
            let
                ( shipDx, shipDy ) =
                    displacement eval.whichTurn work.velocity

                ( otherDx, otherDy ) =
                    displacement eval.whichTurn other.velocity

                next =
                    wrapLoc work.space { x = work.ship.current.location.x + shipDx, y = work.ship.current.location.y + shipDy }

                deltaX =
                    Trig.wrapDelta ((other.current.location.x + otherDx) - next.x) work.space.width

                deltaY =
                    Trig.wrapDelta ((other.current.location.y + otherDy) - next.y) work.space.height

                toward =
                    Trig.arctan deltaX deltaY

                away =
                    Trig.normalizeAngle (toward + halfCircle)

                workN =
                    { work | next = next }

                canTurn =
                    work.turnWait == 0

                canThrust =
                    work.thrustWait == 0
            in
            if eval.move == Avoid then
                enticeAvoid workN eval toward canTurn canThrust

            else if isGravity other then
                enticePlanet workN toward away canTurn canThrust

            else
                enticeTarget workN eval other toward away canTurn canThrust


enticeAvoid : Work -> Eval -> Int -> Bool -> Bool -> Work
enticeAvoid work eval toward canTurn canThrust =
    let
        rel =
            Trig.normalizeAngle (Trig.normalizeAngle (toward + halfCircle) - eval.facing)

        dir =
            if rel <= halfCircle then
                1

            else
                -1

        thrustAngle =
            Trig.normalizeAngle (eval.facing + dir * quadrant - dir * (octant // 2))

        work1 =
            if canTurn then
                turnShip work thrustAngle

            else
                work
    in
    if canThrust then
        thrustShip work1 thrustAngle

    else
        work1


enticePlanet : Work -> Int -> Int -> Bool -> Bool -> Work
enticePlanet work toward away canTurn canThrust =
    let
        planetFacing =
            angleToFacing toward

        cone =
            Trig.normalizeFacing (planetFacing - work.facing + angleToFacing quadrant)

        needsCoast =
            work.core.characteristics.thrustIncrement /= work.core.characteristics.maxThrust

        ( turnAngle, doThrust ) =
            if cone > angleToFacing (quadrant * 2) then
                ( toward, canThrust && not needsCoast )

            else if cone == angleToFacing quadrant then
                ( travelAngle work.velocity, canThrust && not needsCoast )

            else if cone == 0 || cone == angleToFacing (quadrant * 2) then
                ( facingToAngle work.facing, True )

            else
                ( away, canThrust && not needsCoast )

        work1 =
            if canTurn then
                turnShip work turnAngle

            else
                work
    in
    if doThrust && (canThrust || cone == 0 || cone == angleToFacing (quadrant * 2)) then
        thrustShip work1 turnAngle

    else
        work1


enticeTarget : Work -> Eval -> Element -> Int -> Int -> Bool -> Bool -> Work
enticeTarget work eval other toward away canTurn canThrust =
    let
        inRange =
            plotIntercept work.space work.ship other 10 (work.range - work.range // 4)

        tooClose =
            plotIntercept work.space work.ship other 40 (closeRange * 2) > 0

        atSpeed =
            work.core.flags.atMaxSpeed || work.core.flags.beyondMaxSpeed

        turnAngle =
            if tooClose then
                away

            else
                toward

        work1 =
            if canTurn then
                turnShip work turnAngle

            else
                work

        coast =
            work.core.characteristics.thrustIncrement /= work.core.characteristics.maxThrust && atSpeed && not tooClose
    in
    if canThrust && not coast then
        thrustShip work1
            (if inRange > 0 then
                away

             else
                toward
            )

    else
        work1


turnShip : Work -> Int -> Work
turnShip work angle =
    let
        wanted =
            angleToFacing angle

        delta0 =
            Trig.normalizeFacing (wanted - work.facing)

        ( delta, seed1 ) =
            if delta0 == 8 then
                let
                    ( r, s ) =
                        Rng.next work.seed
                in
                if modBy 2 r == 0 then
                    ( Trig.normalizeFacing (delta0 + 1), s )

                else
                    ( Trig.normalizeFacing (delta0 - 1), s )

            else
                ( delta0, work.seed )
    in
    if delta == 0 then
        { work | seed = seed1 }

    else if delta < 8 then
        { work | right = True, left = False, facing = Trig.normalizeFacing (work.facing + 1), seed = seed1 }

    else
        { work | left = True, right = False, facing = Trig.normalizeFacing (work.facing - 1), seed = seed1 }


thrustShip : Work -> Int -> Work
thrustShip work angle =
    let
        velFacing =
            angleToFacing (travelAngle work.velocity)

        aligned =
            Trig.normalizeFacing (angleToFacing angle - velFacing) == 0

        coasting =
            aligned && (work.core.flags.atMaxSpeed || work.core.flags.beyondMaxSpeed) && not work.core.flags.inGravityWell

        cone =
            Trig.normalizeFacing (angleToFacing angle - work.facing + angleToFacing quadrant)

        should =
            work.thrust
                || (not coasting && (cone == angleToFacing quadrant || (work.core.flags.beyondMaxSpeed && cone <= 8)))
    in
    if should then
        { work | thrust = True, velocity = inertial work }

    else
        work


inertial : Work -> Melee.Units.VelocityDesc
inertial work =
    let
        chars =
            work.core.characteristics

        facing =
            work.facing * 4

        incV =
            chars.thrustIncrement * 32

        ( cx, cy ) =
            Velocity.getCurrent work.velocity

        dx =
            cx + Trig.cosine facing incV

        dy =
            cy + Trig.sine facing incV

        maxV =
            chars.maxThrust * 32
    in
    if chars.thrustIncrement == chars.maxThrust then
        Velocity.setVector chars.maxThrust (Facing work.facing)

    else if dx * dx + dy * dy <= maxV * maxV then
        Velocity.setComponents dx dy

    else
        Velocity.setVector chars.maxThrust (Facing work.facing)


enemyMi : Work -> Int
enemyMi work =
    maneuverability (State.core (combatant (otherSide work.side) work.arena)).characteristics


enemyRange : Work -> Int
enemyRange work =
    intelRange (State.kind (combatant (otherSide work.side) work.arena))


enemyAbility : Work -> Ability
enemyAbility work =
    (stock (State.kind (combatant (otherSide work.side) work.arena))).ability


coin : Work -> Int -> ( Bool, Work )
coin work sides =
    let
        ( r, seed ) =
            Rng.next work.seed
    in
    ( modBy sides r == 0, { work | seed = seed } )


raceIntelligence : Work -> Concerns -> Work
raceIntelligence work concerns =
    case work.kind of
        Shofixti ->
            shofixti work concerns

        Yehat ->
            yehat work concerns

        Earthling ->
            earthling work concerns

        Arilou ->
            arilou work concerns

        Pkunk ->
            pkunk work concerns

        Mycon ->
            mycon work concerns

        Spathi ->
            spathi work concerns

        Androsynth ->
            androsynth work concerns

        Chenjesu ->
            chenjesu work concerns

        Ilwrath ->
            ilwrath work concerns

        Thraddash ->
            thraddash work concerns

        Druuge ->
            druuge work concerns

        Slylandro ->
            slylandro work concerns

        Melnorme ->
            melnorme work concerns

        Utwig ->
            utwig work concerns

        Orz ->
            orz work concerns

        Chmmr ->
            chmmr work concerns

        UrQuan ->
            urquan work concerns

        KohrAh ->
            kohrah work concerns

        Vux ->
            vux work concerns

        Umgah ->
            umgah work concerns

        Supox ->
            supox work concerns

        Syreen ->
            syreen work concerns

        Mmrnmhrm ->
            mmrnmhrm work concerns

        ZoqFotPik ->
            zoqfot work concerns


shofixti : Work -> Concerns -> Work
shofixti work0 concerns =
    let
        work =
            shipIntelligence work0 concerns

        ( flip, work1 ) =
            coin work 2
    in
    if not (specialReady work1) then
        { work1 | special = False }

    else
        let
            shipClose =
                concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 4

            weaponHit =
                case concerns.weapon.object of
                    Just el ->
                        (el.flags.playerShip && work1.ship.points == 1)
                            || (plotIntercept work1.space el work1.ship 2 0 > 0 && el.mass >= work1.ship.points && flip)

                    Nothing ->
                        False
        in
        { work1 | special = shipClose || weaponHit }


yehat : Work -> Concerns -> Work
yehat work0 concerns0 =
    let
        ( concerns, shield ) =
            case concerns0.weapon.object of
                Just el ->
                    if concerns0.weapon.move == Entice then
                        if not el.flags.finiteLife && not el.flags.crewObject then
                            ( { concerns0 | weapon = { object = Just el, move = Pursue, facing = concerns0.weapon.facing, whichTurn = concerns0.weapon.whichTurn } }, 0 )

                        else if el.mass /= 0 || el.flags.crewObject then
                            ( { concerns0
                                | weapon =
                                    if el.flags.finiteLife && el.mass /= 0 then
                                        { object = Nothing, move = NoMovement, facing = 0, whichTurn = max 1 (concerns0.weapon.whichTurn // 2) }

                                    else
                                        { object = Just el, move = Pursue, facing = concerns0.weapon.facing, whichTurn = max 1 (concerns0.weapon.whichTurn // 2) }
                              }
                            , 1
                            )

                        else
                            ( concerns0, 0 )

                    else
                        ( concerns0, -1 )

                Nothing ->
                    ( concerns0, -1 )

        ( flip, work1 ) =
            coin work0 4

        work2 =
            if specialReady work1 && shield /= 0 && concerns.weapon.whichTurn <= 2 && flip then
                { work1 | special = True }

            else
                { work1 | special = False }

        concerns2 =
            if (enemyAbility work2).immediateWeapon then
                concerns

            else
                { concerns | enemy = { object = concerns.enemy.object, move = Pursue, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }
    in
    shipIntelligence work2 concerns2


earthling : Work -> Concerns -> Work
earthling work0 concerns =
    let
        wantPd =
            specialReady work0
                && ((concerns.weapon.object /= Nothing && concerns.weapon.whichTurn <= 2)
                        || (concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 4)
                   )

        work1 =
            { work0 | special = wantPd }

        work2 =
            shipIntelligence work1 { concerns | weapon = blank }
    in
    if weaponReady work2 && concerns.enemy.object /= Nothing && (not work2.left && not work2.right || concerns.enemy.whichTurn <= 12) then
        { work2 | weapon = True }

    else
        work2


arilou : Work -> Concerns -> Work
arilou work0 concerns =
    let
        work1 =
            shipIntelligence { work0 | thrust = True } { concerns | enemy = { object = concerns.enemy.object, move = Entice, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }

        ( unlucky, work2 ) =
            coin work1 4

        jump =
            specialReady work2
                && (case concerns.weapon.object of
                        Just _ ->
                            concerns.weapon.whichTurn <= 6 && not unlucky

                        Nothing ->
                            False
                   )
    in
    if jump then
        { work2 | special = True, left = False, right = False, thrust = False, weapon = False }

    else if work2.core.energy <= work2.core.characteristics.specialEnergyCost * 2 then
        { work2 | special = False, weapon = False }

    else
        { work2 | special = False }


pkunk : Work -> Concerns -> Work
pkunk work0 concerns =
    let
        ( sing, work1 ) =
            coin work0 256

        work2 =
            { work1
                | special =
                    work1.core.energy < work1.core.maxEnergy && (specialReady work1 || sing && work1.core.energy < work1.core.maxEnergy)
            }
    in
    shipIntelligence work2 concerns


mycon : Work -> Concerns -> Work
mycon work0 concerns0 =
    let
        concerns =
            case concerns0.weapon.object of
                Just el ->
                    if concerns0.weapon.move == Entice then
                        { concerns0
                            | weapon =
                                { object = Just el
                                , move =
                                    if el.flags.finiteLife && not el.flags.crewObject then
                                        Avoid

                                    else
                                        Pursue
                                , facing = concerns0.weapon.facing
                                , whichTurn = concerns0.weapon.whichTurn
                                }
                        }

                    else
                        concerns0

                Nothing ->
                    concerns0

        work1 =
            shipIntelligence work0 concerns

        work2 =
            if concerns.weapon.move == Pursue then
                { work1 | thrust = False }

            else
                work1
    in
    if weaponReady work2 && concerns.enemy.object /= Nothing && (concerns.enemy.whichTurn <= 16 || work2.ship.points == work2.core.maxCrew) && facingAligned work2 (concerns.enemy.object |> Maybe.withDefault work2.ship) then
        { work2 | weapon = True }

    else
        work2


spathi : Work -> Concerns -> Work
spathi work0 concerns =
    let
        work =
            shipIntelligence work0 concerns
    in
    if not (specialReady work) || concerns.enemy.object == Nothing || concerns.enemy.whichTurn > 24 then
        { work | special = False }

    else
        let
            other =
                concerns.enemy.object |> Maybe.withDefault work.ship

            dx =
                Trig.wrapDelta (other.current.location.x - work.ship.current.location.x) work.space.width

            dy =
                Trig.wrapDelta (other.current.location.y - work.ship.current.location.y) work.space.height

            direction =
                angleToFacing (Trig.arctan dx dy)

            rear =
                Trig.normalizeFacing (work.facing + 8)

            cone =
                Trig.normalizeFacing (direction - rear + 4)
        in
        { work | special = cone <= 8 && concerns.enemy.whichTurn <= 8 }


androsynth : Work -> Concerns -> Work
androsynth work0 concerns =
    let
        blazer =
            case combatant work0.side work0.arena of
                State.LiveAndrosynth _ (State.Blazer _) ->
                    True

                _ ->
                    False
    in
    if blazer then
        let
            concerns1 =
                { concerns
                    | crew = blank
                    , weapon =
                        case concerns.weapon.object of
                            Just el ->
                                if concerns.weapon.move == Entice then
                                    if el.flags.finiteLife && not el.flags.crewObject then
                                        { object = Just el, move = Avoid, facing = concerns.weapon.facing, whichTurn = concerns.weapon.whichTurn }

                                    else
                                        blank

                                else
                                    concerns.weapon

                            Nothing ->
                                concerns.weapon
                }
        in
        shipIntelligence work0 concerns1

    else
        let
            close =
                concerns.enemy.whichTurn <= 16

            lowEnergy =
                work0.core.energy < work0.core.maxEnergy // 3

            concerns1 =
                if close && (not (specialReady work0) || lowEnergy) then
                    { concerns | enemy = { object = concerns.enemy.object, move = Entice, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }

                else
                    concerns

            work1 =
                shipIntelligence work0 concerns1

            blaze =
                specialReady work1
                    && ((concerns.weapon.object /= Nothing && concerns.weapon.whichTurn <= 4)
                            || (concerns.enemy.object /= Nothing && work1.core.energy >= work1.core.maxEnergy // 3 && concerns.enemy.whichTurn < 16)
                       )
        in
        { work1
            | special = blaze
            , weapon =
                if not blaze && weaponReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 4 then
                    True

                else
                    work1.weapon
        }


chenjesu : Work -> Concerns -> Work
chenjesu work0 concerns =
    let
        pursueEnemy =
            concerns.enemy.object
                /= Nothing
                && (concerns.enemy.whichTurn <= 16 && enemyMi work0 >= mediumShip || enemyMi work0 <= slowShip && enemyRange work0 >= longRange * 3 // 4 && (enemyAbility work0).seekingWeapon)

        concerns1 =
            if pursueEnemy then
                { concerns | enemy = { object = concerns.enemy.object, move = Pursue, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }

            else
                concerns

        work1 =
            shipIntelligence { work0 | special = False } concerns1

        dogi =
            waitN work1.core.specialWait == 1 && concerns.weapon.object /= Nothing && concerns.weapon.move == Entice && concerns.weapon.whichTurn <= 8
    in
    { work1 | special = dogi }


ilwrath : Work -> Concerns -> Work
ilwrath work0 concerns =
    let
        concerns1 =
            { concerns
                | enemy = { object = concerns.enemy.object, move = Pursue, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn }
                , weapon =
                    if work0.core.cloaked then
                        blank

                    else
                        concerns.weapon
            }

        work1 =
            shipIntelligence work0 concerns1

        cloak =
            specialReady work1 && not work1.weapon && (concerns.weapon.object /= Nothing && concerns.weapon.whichTurn <= 10 || not work1.core.cloaked)
    in
    { work1 | special = cloak, weapon = weaponReady work1 && concerns.enemy.whichTurn <= 8 && facingAligned work1 (concerns.enemy.object |> Maybe.withDefault work1.ship) || work1.weapon }


thraddash : Work -> Concerns -> Work
thraddash work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        afterburn =
            specialReady work1
                && ((concerns.weapon.object /= Nothing && concerns.weapon.move == Entice)
                        || (concerns.enemy.move == Pursue && work1.core.energy >= work1.core.characteristics.weaponEnergyCost + work1.core.characteristics.specialEnergyCost)
                   )
    in
    { work1 | special = afterburn }


druuge : Work -> Concerns -> Work
druuge work0 concerns =
    let
        concerns1 =
            { concerns | enemy = { object = concerns.enemy.object, move = Entice, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }

        work1 =
            shipIntelligence work0 concerns1

        fire =
            weaponReady work1 && concerns.weapon.object /= Nothing && concerns.weapon.whichTurn <= 6

        sell =
            work1.weapon && work1.core.energy < work1.core.characteristics.weaponEnergyCost
    in
    { work1 | weapon = work1.weapon || fire, special = sell }


slylandro : Work -> Concerns -> Work
slylandro work0 concerns =
    let
        work1 =
            shipIntelligence { work0 | special = False } { concerns | weapon = blank, enemy = { object = concerns.enemy.object, move = Entice, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }
    in
    { work1 | weapon = True, special = False }


melnorme : Work -> Concerns -> Work
melnorme work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        confuse =
            specialReady work1 && work1.core.energy >= work1.core.characteristics.specialEnergyCost && concerns.enemy.whichTurn <= 8
    in
    { work1 | special = confuse }


utwig : Work -> Concerns -> Work
utwig work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        absorb =
            specialReady work1 && concerns.weapon.object /= Nothing && concerns.weapon.whichTurn <= 4
    in
    { work1 | special = absorb }


orz : Work -> Concerns -> Work
orz work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns
    in
    if concerns.enemy.object == Nothing then
        { work1 | special = False }

    else if specialReady work1 && not work1.left && not work1.right && not work1.weapon && concerns.enemy.whichTurn < 24 then
        { work1 | special = True }

    else
        { work1 | special = False }


chmmr : Work -> Concerns -> Work
chmmr work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        tractor =
            specialReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 12
    in
    { work1 | special = tractor }


urquan : Work -> Concerns -> Work
urquan work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        fighters =
            specialReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn > 8 && work1.core.energy >= work1.core.characteristics.specialEnergyCost
    in
    { work1 | special = fighters }


kohrah : Work -> Concerns -> Work
kohrah work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        fry =
            specialReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 20
    in
    { work1 | special = fry }


vux : Work -> Concerns -> Work
vux work0 concerns =
    let
        work1 =
            shipIntelligence work0 { concerns | enemy = { object = concerns.enemy.object, move = Entice, facing = concerns.enemy.facing, whichTurn = concerns.enemy.whichTurn } }

        limpet =
            specialReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 10
    in
    { work1 | special = limpet }


umgah : Work -> Concerns -> Work
umgah work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        zip =
            specialReady work1 && (concerns.weapon.whichTurn <= 4 || concerns.enemy.whichTurn >= 16)
    in
    { work1 | special = zip }


supox : Work -> Concerns -> Work
supox work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        crab =
            specialReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 12 && (work1.left || work1.right)
    in
    { work1 | special = crab }


syreen : Work -> Concerns -> Work
syreen work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        call =
            specialReady work1 && work1.ship.points < work1.core.maxCrew - 2
    in
    { work1 | special = call }


mmrnmhrm : Work -> Concerns -> Work
mmrnmhrm work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        transform =
            specialReady work1 && (concerns.enemy.whichTurn < 8 && work1.range > closeRange || concerns.enemy.whichTurn > 24 && work1.range <= closeRange)
    in
    { work1 | special = transform }


zoqfot : Work -> Concerns -> Work
zoqfot work0 concerns =
    let
        work1 =
            shipIntelligence work0 concerns

        tongue =
            specialReady work1 && concerns.enemy.object /= Nothing && concerns.enemy.whichTurn <= 2
    in
    { work1 | special = tongue, weapon = work1.weapon || (weaponReady work1 && concerns.enemy.whichTurn <= 8) }
