module Neat.Encode exposing (abilityBits, combatSize, hullBitsPerSide, kindSize, kinds, roster, size, threatSlots, threatWidth, vector)

{-| Observation vector shared with `rust/crates/melee-neat/src/encode.rs`.

CROSS-LANGUAGE CONTRACT. That module emits the same 127 numbers in the same
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

One rule shapes every block that describes a moving object: the cyborg
extrapolates with a whole velocity and steers off a whole bearing, so every
object a block describes carries its direction of travel as a cosine and a sine,
its speed, and its bearing relative to our own facing. A block that emitted only
a magnitude or only a cosine would leave the network unable to tell two
mirror-image situations apart, which is the one distinction the cyborg's own
dodging and leading are built from.

LAYOUT, 127 slots.

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
     16..20   own resources against the costs that actually gate abilities
        16 energy >= weaponEnergyCost
        17 energy >= specialEnergyCost
        18 the Umgah approach budget, worldToTurn (160 * energy / special cost)
        19 core specialWait / 64, the live timer, not just whether it expired
        20 characteristics specialWait / 64, the reload constant, which is also
           the slot Umgah overwrites with the approach distance it stashes
     21       own hull mass / (2 * maxShipMass)
     22..32   enemy geometry
        22 dx to foe / half arena width     23 dy to foe / half arena height
        24 distance to foe / longRange      25 closing rate / 200
        26 cos(their facing - ours)         27 sin(their facing - ours)
        28 their speed / their maxThrust
        29 cos(their travel angle - our facing)
        30 sin(their travel angle - our facing)
        31 signed facing delta to foe / 8
        32 foe hull mass / (2 * maxShipMass)
     33..36   enemy visible state
        33 foe element cloaked              34 our own cloak
        35 their energy / their maxEnergy   SUPERSET
        36 their crew / their maxCrew       SUPERSET
     37..41   firing solutions
        37 our firing solution against them, the cyborg's own predicate
        38 our range probe closing on them, 1/(1+t)
        39 their firing solution against us SUPERSET for missile hulls
        40 their range probe closing on us  SUPERSET for missile hulls
        41 their ability.immediateWeapon, which says whether 39 and 40 are the
           cyborg-visible case or the superset case
     42..46   scalar ship comparisons
        42 our intelRange / longRange       43 their intelRange / longRange
        44 maneuverability ours / fastShip  45 maneuverability theirs / fastShip
        46 (our maxThrust - their maxThrust) / 64
     47..60   ability bits, ours 47..53 then theirs 54..60, each in the order
              seekingWeapon, seekingSpecial, immediateWeapon, firesFore,
              firesRight, firesAft, firesLeft
     61..63   gravity concern
        61 planet dx / 4000                 62 planet dy / 4000
        63 1/(1+t) from the cyborg's own three-margin gravity battery
     64..102  the three most urgent hostile projectiles, 13 slots each, base
              64 + 13 * rank. The rank key is considerWeapon's own whichTurn,
              which is the seeking branch's turn count for a homing weapon and
              the coasted intercept for a ballistic one:
        +0 1/(1+t) of that concern turn
        +1 cos(its travel angle - our facing)
        +2 sin(its travel angle - our facing)
        +3 its speed / turnWorld
        +4 cos(its bearing from us - our facing)
        +5 sin(its bearing from us - our facing)
        +6 1/(1+turns) of its straight-line range, seekingWeapon's own measure
        +7 cos(its travel angle - its bearing back to us), the closing test
        +8 sin of that same angle, whose SIGN is the side enticeAvoid dodges
        +9 seeking                         +10 finiteLife
       +11 its mass / our maxCrew          +12 its remaining life / 64
    103..109  crew concern
       103 dx / half width 104 dy / half height 105 1/(1+turns)
       106 cos(its travel angle - our facing)
       107 sin(its travel angle - our facing)
       108 its speed / turnWorld
       109 our ship already targets it
    110..115  neutral-body concern, the nearest parentless body (asteroids)
       110 dx / 4000       111 dy / 4000          112 1/(1+turns)
       113 cos(its travel angle - our facing)
       114 sin(its travel angle - our facing)
       115 its speed / turnWorld
    116      constant 1, the last of the 117 combat sensors
    117..126 hull identity, our 5-bit roster index then theirs, low bit first

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
    117


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
    13


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



-- OWN HULL, SLOTS 0..21


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
    -- same scale as slot 24.
    , ratio (Cyborg.worldToTurn (160 * core.energy // max 1 chars.specialEnergyCost)) 64

    -- Chenjesu fires on specialWait == 1 exactly, which slot 8 cannot say.
    , ratio (clamp 0 64 (waitN core.specialWait)) 64

    -- A DIFFERENT FIELD from the one above. Characteristics.specialWait is the
    -- hull's reload constant, and it is the slot `remember` writes the Umgah
    -- approach distance into; `umgah` then compares the turns to the enemy
    -- against it and `pilot` persists it back into the arena. It is live,
    -- cyborg-visible state that the live timer above cannot express. 255, the
    -- "forget it" sentinel, saturates this ratio at one, which is the same
    -- thing the comparison says.
    , ratio (clamp 0 64 (waitN chars.specialWait)) 64

    -- considerEnemy reads a hull element's raw mass and tests it against
    -- maxShipMass to spot a transformed hull. Halving the scale keeps that
    -- threshold at one half while leaving the ordinary 1..10 range resolvable,
    -- which a bare boolean would throw away.
    , hullMass own
    ]



-- THE OPPONENT, SLOTS 22..41


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

        relTravel =
            Trig.normalizeAngle (travelAngle foe.velocity - faceAng)

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

    -- pursue and entice both extrapolate the opponent with
    -- `displacement whichTurn other.velocity` and enticeTarget reads
    -- `travelAngle other.velocity` outright. The closing scalar above is only
    -- the radial part of that velocity, so without these two the sign of the
    -- tangential part is lost and two opposite circling directions would reach
    -- the network as the same situation.
    , unit relTravel
    , unitS relTravel
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



-- SCALARS AND ABILITY BITS, SLOTS 42..60


scalars : ShipKind -> ShipKind -> State.CombatantCore -> State.CombatantCore -> List Float
scalars ours theirs ownCore foeCore =
    [ ratio (intelRange ours) Cyborg.longRange
    , ratio (intelRange theirs) Cyborg.longRange
    , ratio (Cyborg.maneuverability ownCore.characteristics) Cyborg.fastShip
    , ratio (Cyborg.maneuverability foeCore.characteristics) Cyborg.fastShip

    -- Slots 4 and 28 normalise each side's speed by its own maximum, which
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



-- CONCERNS, SLOTS 61..115


{-| One ranked hostile projectile, in the terms the cyborg classifies it.
-}
type alias Threat =
    { -- considerWeapon's own whichTurn for this projectile at the Awesome
      -- rating: the seeking branch's turn count for a homing weapon, the coasted
      -- intercept for a ballistic one. This is the key the cyborg ranks on.
      concern : Int

    -- Straight-line range in turns, which is what seekingWeapon measures and
    -- what enticeAvoid needs alongside the bearing.
    , turns : Int
    , id : Int
    , travel : Int

    -- Bearing from us to the projectile, and the bearing back from it to us.
    -- enticeAvoid steers off the angle between the second and travel.
    , bearing : Int
    , bearingBack : Int
    , velocity : VelocityDesc
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
        List.repeat (3 + threatSlots * threatWidth + 7 + 6) 0

    else
        let
            scan =
                Dict.foldl (\_ el acc -> consider arena core own el acc)
                    { planet = Nothing, empty = Nothing, crew = Nothing, threats = [] }
                    arena.elements
        in
        gravityBlock arena.space core own scan.planet
            ++ threatBlock core scan.threats
            ++ crewBlock arena.space core own scan.crew
            ++ neutralBlock arena.space core own scan.empty


consider : Arena -> State.CombatantCore -> Element -> Element -> Scan -> Scan
consider arena core own el scan =
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
            { scan | threats = threatOf arena core own el dx dy turns :: scan.threats }

        else
            scan


threatOf : Arena -> State.CombatantCore -> Element -> Element -> Int -> Int -> Int -> Threat
threatOf arena core own el dx dy turns =
    let
        ability =
            case el.parent of
                Just side ->
                    (stock (State.kind (combatant side arena))).ability

                -- considerWeapon's own fallback for a parentless projectile.
                Nothing ->
                    (stock Shofixti).ability

        seeking =
            (ability.seekingWeapon && not (Cyborg.isSpecialBody el.body))
                || (ability.seekingSpecial && Cyborg.isSpecialBody el.body)
    in
    { -- considerWeapon's own split, at the Awesome rating. A homing weapon goes
      -- to seekingWeapon, whose turn count is a straight-line range, and a
      -- ballistic one is coasted against us over its remaining life at the
      -- cyborg's 40-display-unit margin. Scoring every projectile by the
      -- ballistic branch would sort a missile that is turning onto us but not
      -- yet on a collision course behind every shot with a predicted impact,
      -- which is the opposite of the order the cyborg acts in.
      concern =
        if seeking then
            Cyborg.seekingWeaponTurn core.characteristics el dx dy

        else
            Cyborg.plotIntercept arena.space el own (Cyborg.lifeSpan el) (Cyborg.displayToWorld 40)
    , turns = turns
    , id = toInt el.id
    , travel = travelAngle el.velocity
    , bearing = Trig.arctan dx dy
    , bearingBack = Trig.arctan (negate dx) (negate dy)
    , velocity = el.velocity
    , seeking = seeking
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


{-| Both concerns below reach `pursue`, which extrapolates the object with
`displacement whichTurn other.velocity`, so each carries its whole velocity
rather than a position the network would have to differentiate.
-}
crewBlock : WorldExtent -> State.CombatantCore -> Element -> Maybe Near -> List Float
crewBlock space core own near =
    case near of
        Nothing ->
            [ 0, 0, 0, 0, 0, 0, 0 ]

        Just { turns, element } ->
            let
                ( dx, dy ) =
                    nextDelta space own element
            in
            [ clamp11 (toFloat dx / (toFloat space.width / 2))
            , clamp11 (toFloat dy / (toFloat space.height / 2))
            , urgency (max 1 turns)
            ]
                ++ motionOf element.velocity (faceAngle core)
                ++ [ flag (own.target == Just element.id) ]


neutralBlock : WorldExtent -> State.CombatantCore -> Element -> Maybe Near -> List Float
neutralBlock space core own near =
    case near of
        Nothing ->
            [ 0, 0, 0, 0, 0, 0 ]

        Just { turns, element } ->
            let
                ( dx, dy ) =
                    nextDelta space own element
            in
            [ clamp11 (toFloat dx / 4000)
            , clamp11 (toFloat dy / 4000)
            , urgency (max 1 turns)
            ]
                ++ motionOf element.velocity (faceAngle core)


{-| considerWeapon keeps the smallest positive whichTurn, and on a tie it prefers
the Avoid arm, which is the ballistic one. This is that rule: projectiles the
cyborg would score at zero sort behind every one it would act on, then soonest
concern first, then Avoid before Entice, then the nearer object, then element id
so the order is a function of the arena alone.
-}
threatBlock : State.CombatantCore -> List Threat -> List Float
threatBlock core threats =
    let
        ranked =
            threats
                |> List.sortBy
                    (\t ->
                        ( ( ifElse (t.concern <= 0) 1 0, t.concern, ifElse t.seeking 1 0 )
                        , ( t.turns, t.id )
                        )
                    )
                |> List.take threatSlots

        emitted =
            List.concatMap (threatRecord core (faceAngle core)) ranked
    in
    emitted ++ List.repeat ((threatSlots - List.length ranked) * threatWidth) 0


threatRecord : State.CombatantCore -> Int -> Threat -> List Float
threatRecord core faceAng t =
    let
        toward =
            Trig.normalizeAngle (t.bearing - faceAng)

        closingAngle =
            Trig.normalizeAngle (t.travel - t.bearingBack)
    in
    (urgency t.concern :: motionOf t.velocity faceAng)
        ++ [ -- Where the shot is, in our own frame. Without these the network
             -- holds an angle between two of the projectile's own directions
             -- and no idea which side of us it passes.
             unit toward
           , unitS toward
           , urgency (max 1 t.turns)
           , unit closingAngle

           -- enticeAvoid turns `dir = +/-1` on exactly the sign of this sine:
           -- the cosine alone leaves the bearing recoverable only up to a mirror
           -- reflection about the projectile's travel line, which is the one
           -- thing a dodge has to choose between.
           , unitS closingAngle
           , flag t.seeking
           , flag t.finiteLife

           -- Projectile mass is its damage, which Shofixti weighs against its
           -- own remaining crew.
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


faceAngle : State.CombatantCore -> Int
faceAngle core =
    let
        (Facing facing) =
            core.facing
    in
    facing * 4


{-| Speed of an object that has no maxThrust of its own to be measured against.
Cyborg.turnWorld is the distance the cyborg calls one turn, so this reads as the
fraction of a turn's distance the object covers per frame, on the same scale
every worldToTurn slot in this vector already uses.
-}
pace : VelocityDesc -> Float
pace v =
    clamp01 (speed v / toFloat Cyborg.turnWorld)


{-| Direction of travel and speed of an object the cyborg extrapolates with,
expressed in our own frame. `displacement` consumes the whole velocity, so a
block that named only its magnitude would leave two opposite headings
indistinguishable.
-}
motionOf : VelocityDesc -> Int -> List Float
motionOf v faceAng =
    let
        relative =
            Trig.normalizeAngle (travelAngle v - faceAng)
    in
    [ unit relative, unitS relative, pace v ]


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
