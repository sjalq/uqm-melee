module Neat.Encode exposing (abilityBits, combatSize, hullBitsPerSide, kindSize, kinds, roster, size, threatSlots, threatWidth, vector)

{-| Observation vector shared with `rust/crates/melee-neat/src/encode.rs`.

CROSS-LANGUAGE CONTRACT. That module emits the same 103 numbers in the same
order from the same arena, and `Mario.Dashboard.Slots` names them. A change here
is a change to all three, plus `Mario.Genome.observationCount` on this side and
`policy::N_OBS` and `melee_mario::genome::{N_OBS, N_INPUT}` on the other. It also
invalidates every stored genome and checkpoint, because the input width is part
of a genome's meaning.

WHAT THIS VECTOR IS ALLOWED TO CONTAIN. Every slot must be something the original
cyborg (`Melee.Cyborg`) also reads out of the arena, so that a network and a
cyborg can be compared on equal footing. There are exactly five deliberate
exceptions, each marked SUPERSET below and each justified where it is emitted.
Two further extras live outside this vector and are out of scope here: the five
previous-tick controls and the eight memory channels, both appended by the
policy, not by this encoder.

WHAT IT DELIBERATELY DOES NOT REPRODUCE: the cyborg's gating. The cyborg ignores
gravity while `moved` is latched, ignores crew while the enemy is near, and
ignores ballistic projectiles below Awesome rating. Those gates are decisions
taken over facts it has already read, and every input to them is itself a slot
here. This encoder emits the facts and leaves the gating to the network, which is
what makes the comparison a comparison of policies rather than of eyesight.

LAYOUT, 103 slots.

      0..10   own hull state
         0 energy / maxEnergy
         1 crew / maxCrew
         2 cos(facing angle)
         3 sin(facing angle)
         4 speed / maxThrust
         5 cos(travel angle - facing angle)
         6 sin(travel angle - facing angle)
         7 weaponWait <= 0
         8 specialWait <= 0
         9 turnWait <= 0
        10 thrustWait <= 0
     11..15   own motion predicates
        11 atLimit          12 beyondLimit      13 inGravityWell
        14 usesInertia      15 ultra
     16..19   own resources against the costs that actually gate abilities
        16 energy >= weaponEnergyCost
        17 energy >= specialEnergyCost
        18 the Umgah approach budget, worldToTurn (160 * energy / special cost)
        19 specialWait / 64, the exact timer, not just whether it expired
     20       own hull mass / (2 * maxShipMass)
     21..29   enemy geometry
        21 dx to foe / half arena width     22 dy to foe / half arena height
        23 distance to foe / longRange      24 closing rate / 200
        25 cos(their facing - ours)         26 sin(their facing - ours)
        27 their speed / their maxThrust    28 signed facing delta to foe / 8
        29 foe hull mass / (2 * maxShipMass)
     30..33   enemy visible state
        30 foe element cloaked              31 our own cloak
        32 their energy / their maxEnergy   SUPERSET
        33 their crew / their maxCrew       SUPERSET
     34..38   firing solutions
        34 our firing solution against them, the cyborg's own predicate
        35 our range probe closing on them, 1/(1+t)
        36 their firing solution against us SUPERSET for missile hulls
        37 their range probe closing on us  SUPERSET for missile hulls
        38 their ability.immediateWeapon, which says whether 36 and 37 are the
           cyborg-visible case or the superset case
     39..43   scalar ship comparisons
        39 our intelRange / longRange       40 their intelRange / longRange
        41 maneuverability ours / fastShip  42 maneuverability theirs / fastShip
        43 (our maxThrust - their maxThrust) / 64
     44..57   ability bits, ours 44..50 then theirs 51..57, each in the order
              seekingWeapon, seekingSpecial, immediateWeapon, firesFore,
              firesRight, firesAft, firesLeft
     58..60   gravity concern
        58 planet dx / 4000                 59 planet dy / 4000
        60 1/(1+t) from the cyborg's own three-margin gravity battery
     61..84   the three most urgent hostile projectiles, 8 slots each,
              base 61 + 8 * rank:
        +0 1/(1+t) of the predicted impact  +1 cos(its travel angle - our facing)
        +2 sin(its travel angle - our facing)
        +3 cos(its travel angle - its bearing to us), the cyborg's closing test
        +4 seeking                          +5 finiteLife
        +6 its mass / our maxCrew           +7 its remaining life / 64
     85..88   crew concern
        85 dx / half width  86 dy / half height  87 1/(1+turns)
        88 our ship already targets it
     89..91   neutral-body concern, the nearest parentless body (asteroids)
        89 dx / 4000        90 dy / 4000           91 1/(1+turns)
     92       constant 1, the last of the 93 combat sensors
     93..102  hull identity, our 5-bit roster index then theirs, low bit first

-}

import Dict
import Melee.Battle exposing (Arena)
import Melee.Cyborg as Cyborg
import Melee.Element as Element exposing (Element)
import Melee.Id exposing (toInt)
import Melee.Motion as Motion
import Melee.Ship exposing (Ability, ShipKind(..), intelRange, stock)
import Melee.ShipState as State
import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), Side(..), VelocityDesc, Wait(..), WorldExtent, maxShipMass)


{-| Sensors before the two hull identities, the constant 1 included.
-}
combatSize : Int
combatSize =
    93


kindBits : Int
kindBits =
    5


hullBitsPerSide : Int
hullBitsPerSide =
    kindBits


kindSize : Int
kindSize =
    kindBits * 2


size : Int
size =
    combatSize + kindSize


{-| Hostile projectiles ranked and emitted, and the width of one record.
-}
threatSlots : Int
threatSlots =
    3


threatWidth : Int
threatWidth =
    8


{-| Ability bits emitted per side, in `abilityOf` order.
-}
abilityBits : Int
abilityBits =
    7


roster : List ShipKind
roster =
    [ Androsynth
    , Arilou
    , Chenjesu
    , Chmmr
    , Druuge
    , Earthling
    , Ilwrath
    , KohrAh
    , Melnorme
    , Mmrnmhrm
    , Mycon
    , Orz
    , Pkunk
    , Shofixti
    , Slylandro
    , Spathi
    , Supox
    , Syreen
    , Thraddash
    , Umgah
    , UrQuan
    , Utwig
    , Vux
    , Yehat
    , ZoqFotPik
    ]


indexOf : ShipKind -> Int
indexOf kind =
    roster
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, k ) -> k == kind)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault 0


fiveBits : Int -> List Float
fiveBits n =
    List.map (\i -> toFloat (modBy 2 (n // (2 ^ i)))) (List.range 0 (kindBits - 1))


kinds : ShipKind -> ShipKind -> List Float
kinds us them =
    fiveBits (indexOf us) ++ fiveBits (indexOf them)


vector : Side -> Arena -> List Float
vector side arena =
    let
        ownC =
            combatant side arena

        foeC =
            combatant (other side) arena

        ownCore =
            State.core ownC

        foeCore =
            State.core foeC

        identity_ =
            1 :: kinds (State.kind ownC) (State.kind foeC)
    in
    case ( Dict.get (toInt ownCore.element) arena.elements, Dict.get (toInt foeCore.element) arena.elements ) of
        ( Just own, Just foe ) ->
            ownState ownCore own
                ++ enemyBlock arena side ownCore foeCore own foe
                ++ scalars (State.kind ownC) (State.kind foeC) ownCore foeCore
                ++ abilitiesOf (State.kind ownC) (State.kind foeC)
                ++ concernBlocks arena ownCore own
                ++ identity_

        _ ->
            -- Without both hulls in the arena there is no geometry to read; the
            -- roster bits and the constant are the whole truth this tick.
            List.repeat (combatSize - 1) 0 ++ identity_



-- OWN HULL, SLOTS 0..20


ownState : State.CombatantCore -> Element -> List Float
ownState core own =
    let
        chars =
            core.characteristics

        (Facing facing) =
            core.facing

        faceAng =
            facing * 4

        travel =
            Trig.normalizeAngle (travelAngle own.velocity - faceAng)
    in
    [ ratio core.energy core.maxEnergy
    , ratio own.points core.maxCrew
    , unit faceAng
    , unitS faceAng

    -- The cyborg has no speed scalar, but it does read the whole velocity and
    -- extrapolate with it. Slots 11 and 12 carry the predicates it actually
    -- branches on, which this ratio cannot express.
    , clamp01 (speed own.velocity / toFloat (max 1 chars.maxThrust))
    , unit travel
    , unitS travel
    , flag (waitN core.weaponWait <= 0)
    , flag (waitN core.specialWait <= 0)
    , flag (waitN own.turnWait <= 0)
    , flag (waitN own.thrustWait <= 0)
    , flag (Motion.atLimit own.velocity core.flags)
    , flag (Motion.beyondLimit own.velocity core.flags)
    , flag core.flags.inGravityWell
    , flag (chars.thrustIncrement /= chars.maxThrust)
    , flag (Cyborg.isUltra chars)
    , flag (core.energy >= chars.weaponEnergyCost)
    , flag (core.energy >= chars.specialEnergyCost)

    -- Umgah spends energy by the turn on its approach and compares this budget
    -- against the turns to the enemy, so the quantity is a turn count on the
    -- same scale as slot 23.
    , ratio (Cyborg.worldToTurn (160 * core.energy // max 1 chars.specialEnergyCost)) 64

    -- Chenjesu fires on specialWait == 1 exactly and Umgah compares the timer
    -- against a value it stashed, neither of which slot 8 can say.
    , ratio (clamp 0 64 (waitN core.specialWait)) 64

    -- considerEnemy reads a hull element's raw mass and tests it against
    -- maxShipMass to spot a transformed hull. Halving the scale keeps that
    -- threshold at one half while leaving the ordinary 1..10 range resolvable,
    -- which a bare boolean would throw away.
    , hullMass own
    ]



-- THE OPPONENT, SLOTS 21..38


enemyBlock : Arena -> Side -> State.CombatantCore -> State.CombatantCore -> Element -> Element -> List Float
enemyBlock arena side ownCore foeCore own foe =
    let
        space =
            arena.space

        ( dx, dy ) =
            nextDelta space own foe

        dist =
            Trig.squareRoot (dx * dx + dy * dy)

        (Facing facing) =
            ownCore.facing

        (Facing foeFacing) =
            foeCore.facing

        faceAng =
            facing * 4

        relFace =
            Trig.normalizeAngle (foeFacing * 4 - faceAng)

        turnErr =
            shortestFacing (angleToFacing (Trig.arctan dx dy) - facing)

        theirAbility =
            (stock (State.kind (combatant (other side) arena))).ability
    in
    [ clamp11 (toFloat dx / (toFloat space.width / 2))
    , clamp11 (toFloat dy / (toFloat space.height / 2))
    , clamp01 (toFloat dist / toFloat Cyborg.longRange)

    -- The cyborg holds no closing scalar, only the positions it re-extrapolates.
    -- This is a one-slot summary of that same geometry, kept because it is cheap
    -- and well conditioned, not because the cyborg computes it.
    , clamp11 (closing own.velocity foe.velocity dx dy / 200)
    , unit relFace
    , unitS relFace
    , clamp01 (speed foe.velocity / toFloat (max 1 foeCore.characteristics.maxThrust))
    , clamp11 (toFloat turnErr / 8)
    , hullMass foe
    , flag (Element.objectCloaked foe.prim)
    , flag ownCore.cloaked

    -- SUPERSET. considerEnemy clones the opponent's core but consumes only its
    -- weaponWait, ability, range and facing; the opponent's energy is read
    -- nowhere in Melee.Cyborg. Kept deliberately: knowing when a Chmmr laser or
    -- an Ur-Quan fighter launch has become affordable is exactly the judgement
    -- the cyborg lacks and a policy should be free to learn.
    , ratio foeCore.energy foeCore.maxEnergy

    -- SUPERSET. The opponent's element is read for mass, position, velocity,
    -- flags and prim, never for points. Kept for the same reason: knowing the
    -- opponent is one hit from death is a real tactical fact, and withholding it
    -- would cap the policy at the cyborg's blind spots.
    , ratio foe.points foeCore.maxCrew
    , flag (Cyborg.firingSolution arena side foe 0)
    , urgency (Cyborg.rangeProbe space own foe (intelRange (State.kind (combatant side arena))))

    -- SUPERSET, conditionally. considerEnemy runs this same probe from the
    -- opponent's seat only when their ability is immediateWeapon; for a missile
    -- hull the cyborg gets no warning until the missile exists as an element.
    -- Kept because dropping it would hand every missile hull an unearned
    -- advantage over the network. Slot 38 tells the network which case it is.
    , flag (Cyborg.firingSolution arena (other side) own 0)
    , urgency (Cyborg.rangeProbe space foe own (intelRange (State.kind (combatant (other side) arena))))
    , flag theirAbility.immediateWeapon
    ]



-- SCALARS AND ABILITY BITS, SLOTS 39..57


scalars : ShipKind -> ShipKind -> State.CombatantCore -> State.CombatantCore -> List Float
scalars ours theirs ownCore foeCore =
    [ ratio (intelRange ours) Cyborg.longRange
    , ratio (intelRange theirs) Cyborg.longRange
    , ratio (Cyborg.maneuverability ownCore.characteristics) Cyborg.fastShip
    , ratio (Cyborg.maneuverability foeCore.characteristics) Cyborg.fastShip

    -- Slots 4 and 27 normalise each side's speed by its own maximum, which
    -- destroys the raw comparison considerEnemy and enticeTarget make. This
    -- restores it.
    , clamp11 (toFloat (ownCore.characteristics.maxThrust - foeCore.characteristics.maxThrust) / 64)
    ]


abilitiesOf : ShipKind -> ShipKind -> List Float
abilitiesOf ours theirs =
    -- Only the seven the cyborg branches on. pointDefense, crewImmune,
    -- shieldDefense and dontChase appear nowhere in Melee.Cyborg, so they are
    -- not this network's to see.
    abilityOf (stock ours).ability ++ abilityOf (stock theirs).ability


abilityOf : Ability -> List Float
abilityOf ability =
    [ flag ability.seekingWeapon
    , flag ability.seekingSpecial
    , flag ability.immediateWeapon
    , flag ability.firesFore
    , flag ability.firesRight
    , flag ability.firesAft
    , flag ability.firesLeft
    ]



-- CONCERNS, SLOTS 58..91


{-| One ranked hostile projectile, in the terms the cyborg classifies it.
-}
type alias Threat =
    { hit : Int
    , turns : Int
    , id : Int
    , travel : Int
    , bearingBack : Int
    , seeking : Bool
    , finiteLife : Bool
    , mass : Int
    , life : Int
    }


type alias Near =
    { turns : Int, element : Element }


type alias Scan =
    { planet : Maybe Element
    , empty : Maybe Near
    , crew : Maybe Near
    , threats : List Threat
    }


{-| One pass over the arena applying the cyborg's own `consider` dispatch, then
the gravity, threat, crew and neutral blocks it feeds.
-}
concernBlocks : Arena -> State.CombatantCore -> Element -> List Float
concernBlocks arena core own =
    if not (Cyborg.colliding own) then
        List.repeat (3 + threatSlots * threatWidth + 4 + 3) 0

    else
        let
            scan =
                Dict.foldl (\_ el acc -> consider arena own el acc)
                    { planet = Nothing, empty = Nothing, crew = Nothing, threats = [] }
                    arena.elements
        in
        gravityBlock arena.space core own scan.planet
            ++ threatBlock core scan.threats
            ++ crewBlock arena.space own scan.crew
            ++ neutralBlock arena.space own scan.empty


consider : Arena -> Element -> Element -> Scan -> Scan
consider arena own el scan =
    if el.id == own.id || not (Cyborg.colliding el) then
        scan

    else
        let
            ( dx, dy ) =
                nextDelta arena.space own el

            turns =
                Cyborg.worldToTurn (Trig.squareRoot (dx * dx + dy * dy))

            nearer existing =
                case existing of
                    Nothing ->
                        True

                    Just best ->
                        turns < best.turns
        in
        if Cyborg.isGravity el then
            -- The last qualifying body wins, as it does in fillConcerns.
            { scan | planet = Just el }

        else if el.flags.playerShip then
            -- The enemy hull already has its own block.
            scan

        else if Cyborg.isCrew el then
            -- consider's chain tests `parent == Nothing` before it tests isCrew,
            -- and every crew object this simulation makes is parentless, so the
            -- cyborg's own crew concern can never fire: the object falls into
            -- considerEmpty, which drops it for being finiteLife. The cyborg
            -- still measures the object's displacement on the way there, so the
            -- fact is one it holds. Classify by the predicate, not by the order,
            -- and the network can see it.
            if nearer scan.crew then
                { scan | crew = Just { turns = turns, element = el } }

            else
                scan

        else if el.parent == Nothing then
            -- considerEmpty narrows this to bodies that are not finiteLife, and
            -- every asteroid this simulation spawns IS finiteLife, so the
            -- cyborg's empty concern never fires here either. consider measures
            -- the displacement of every colliding element before it dispatches,
            -- so the fact is the cyborg's; the narrowing is its policy. A
            -- drifting rock is a real hazard and the network sees it.
            if nearer scan.empty then
                { scan | empty = Just { turns = turns, element = el } }

            else
                scan

        else if el.parent /= own.parent && Cyborg.lifeSpan el > 0 then
            { scan | threats = threatOf arena own el dx dy turns :: scan.threats }

        else
            scan


threatOf : Arena -> Element -> Element -> Int -> Int -> Int -> Threat
threatOf arena own el dx dy turns =
    let
        ability =
            case el.parent of
                Just side ->
                    (stock (State.kind (combatant side arena))).ability

                -- considerWeapon's own fallback for a parentless projectile.
                Nothing ->
                    (stock Shofixti).ability
    in
    { -- considerWeapon's Awesome branch: the projectile coasted against us over
      -- its own remaining life, at the cyborg's 40-display-unit margin.
      hit = Cyborg.plotIntercept arena.space el own (Cyborg.lifeSpan el) (Cyborg.displayToWorld 40)
    , turns = turns
    , id = toInt el.id
    , travel = travelAngle el.velocity
    , bearingBack = Trig.arctan (negate dx) (negate dy)
    , seeking =
        (ability.seekingWeapon && not (Cyborg.isSpecialBody el.body))
            || (ability.seekingSpecial && Cyborg.isSpecialBody el.body)
    , finiteLife = el.flags.finiteLife
    , mass = el.mass
    , life = Cyborg.lifeSpan el
    }


gravityBlock : WorldExtent -> State.CombatantCore -> Element -> Maybe Element -> List Float
gravityBlock space core own planet =
    case planet of
        Nothing ->
            [ 0, 0, 0 ]

        Just p ->
            let
                ( dx, dy ) =
                    nextDelta space own p
            in
            [ clamp11 (toFloat dx / 4000)
            , clamp11 (toFloat dy / 4000)
            , urgency (Cyborg.gravityIntercept space p own core.characteristics)
            ]


crewBlock : WorldExtent -> Element -> Maybe Near -> List Float
crewBlock space own near =
    case near of
        Nothing ->
            [ 0, 0, 0, 0 ]

        Just { turns, element } ->
            let
                ( dx, dy ) =
                    nextDelta space own element
            in
            [ clamp11 (toFloat dx / (toFloat space.width / 2))
            , clamp11 (toFloat dy / (toFloat space.height / 2))
            , urgency (max 1 turns)
            , flag (own.target == Just element.id)
            ]


neutralBlock : WorldExtent -> Element -> Maybe Near -> List Float
neutralBlock space own near =
    case near of
        Nothing ->
            [ 0, 0, 0 ]

        Just { turns, element } ->
            let
                ( dx, dy ) =
                    nextDelta space own element
            in
            [ clamp11 (toFloat dx / 4000)
            , clamp11 (toFloat dy / 4000)
            , urgency (max 1 turns)
            ]


{-| The cyborg keeps the soonest predicted impact, not the nearest object, so
that is the primary key. Projectiles with no predicted impact sort after every
one that has an impact, and among themselves by the distance the seeking branch
measures in turns. Element id breaks the last tie so the order is a function of
the arena alone.
-}
threatBlock : State.CombatantCore -> List Threat -> List Float
threatBlock core threats =
    let
        (Facing facing) =
            core.facing

        ranked =
            threats
                |> List.sortBy (\t -> ( ( ifElse (t.hit <= 0) 1 0, t.hit ), ( t.turns, t.id ) ))
                |> List.take threatSlots

        emitted =
            List.concatMap (threatRecord core (facing * 4)) ranked
    in
    emitted ++ List.repeat ((threatSlots - List.length ranked) * threatWidth) 0


threatRecord : State.CombatantCore -> Int -> Threat -> List Float
threatRecord core faceAng t =
    let
        relative =
            Trig.normalizeAngle (t.travel - faceAng)

        closingAngle =
            Trig.normalizeAngle (t.travel - t.bearingBack)
    in
    [ urgency t.hit
    , unit relative
    , unitS relative
    , unit closingAngle
    , flag t.seeking
    , flag t.finiteLife

    -- Projectile mass is its damage, which Shofixti weighs against its own
    -- remaining crew.
    , ratio t.mass core.maxCrew
    , ratio (clamp 0 64 t.life) 64
    ]



-- SMALL SHARED PIECES


ifElse : Bool -> a -> a -> a
ifElse condition yes no =
    if condition then
        yes

    else
        no


flag : Bool -> Float
flag b =
    ifElse b 1 0


clamp01 : Float -> Float
clamp01 x =
    max 0 (min 1 x)


clamp11 : Float -> Float
clamp11 x =
    max -1 (min 1 x)


ratio : Int -> Int -> Float
ratio numerator denominator =
    clamp01 (toFloat numerator / toFloat (max 1 denominator))


{-| Urgency of a predicted event `t` turns away. A `t` of zero means the probe
predicted nothing, which reads as no urgency at all rather than as maximum.
-}
urgency : Int -> Float
urgency t =
    if t <= 0 then
        0

    else
        1 / (1 + toFloat t)


hullMass : Element -> Float
hullMass el =
    ratio el.mass (2 * maxShipMass)


unit : Int -> Float
unit ang =
    toFloat (Trig.cosine ang 100) / 100


unitS : Int -> Float
unitS ang =
    toFloat (Trig.sine ang 100) / 100


waitN : Wait -> Int
waitN (Wait n) =
    n


combatant : Side -> Arena -> State.Combatant
combatant side arena =
    if side == Bottom then
        arena.combatants.bottom

    else
        arena.combatants.top


other : Side -> Side
other side =
    if side == Bottom then
        Top

    else
        Bottom


speed : VelocityDesc -> Float
speed vel =
    toFloat (Trig.squareRoot (vel.vector.width * vel.vector.width + vel.vector.height * vel.vector.height))


travelAngle : VelocityDesc -> Int
travelAngle vel =
    case vel.travelAngle of
        Angle a ->
            a


closing : VelocityDesc -> VelocityDesc -> Int -> Int -> Float
closing a b dx dy =
    let
        n =
            max 1 (Trig.squareRoot (dx * dx + dy * dy))
    in
    toFloat ((b.vector.width - a.vector.width) * dx + (b.vector.height - a.vector.height) * dy) / toFloat n


angleToFacing : Int -> Int
angleToFacing a =
    Trig.normalizeFacing ((Trig.normalizeAngle a + 2) // 4)


shortestFacing : Int -> Int
shortestFacing d0 =
    let
        d =
            Trig.normalizeFacing d0
    in
    if d > 8 then
        d - 16

    else
        d


{-| The cyborg reads every displacement off `next.location` inside its concern
scan, so everything derived from a concern uses the same tick.
-}
nextDelta : WorldExtent -> Element -> Element -> ( Int, Int )
nextDelta space a b =
    ( Trig.wrapDelta (b.next.location.x - a.next.location.x) space.width
    , Trig.wrapDelta (b.next.location.y - a.next.location.y) space.height
    )
