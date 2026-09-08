module Neat.Encode exposing (combatSize, kindSize, kinds, roster, size, vector)

{-| Combat facts Cyborg.think uses, plus two 5-bit hull indices (our ship, their ship).
Constructor order matches Melee.Ship. 25 ships need 5 bits each, not 4.
-}

import Dict
import Melee.Arsenal as Arsenal
import Melee.Battle exposing (Arena)
import Melee.Element exposing (Body(..), Element)
import Melee.Id exposing (toInt)
import Melee.Projectile as Projectile
import Melee.Ship exposing (ShipKind(..), intelRange)
import Melee.ShipState as State
import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), Side(..), VelocityDesc, Wait(..), WorldExtent, WorldPoint)
import Melee.Velocity as Velocity


combatSize : Int
combatSize =
    33


kindBits : Int
kindBits =
    5


kindSize : Int
kindSize =
    kindBits * 2


size : Int
size =
    combatSize + kindSize


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
    in
    case ( Dict.get (toInt ownCore.element) arena.elements, Dict.get (toInt foeCore.element) arena.elements ) of
        ( Just own, Just foe ) ->
            encode arena side ownC foeC ownCore foeCore own foe
                ++ kinds (State.kind ownC) (State.kind foeC)

        _ ->
            List.repeat combatSize 0 ++ kinds (State.kind ownC) (State.kind foeC)


encode : Arena -> Side -> State.Combatant -> State.Combatant -> State.CombatantCore -> State.CombatantCore -> Element -> Element -> List Float
encode arena side ownC foeC ownCore foeCore own foe =
    let
        (Facing facing) =
            ownCore.facing

        (Facing foeFacing) =
            foeCore.facing

        dx =
            Trig.wrapDelta (foe.current.location.x - own.current.location.x) arena.space.width

        dy =
            Trig.wrapDelta (foe.current.location.y - own.current.location.y) arena.space.height

        dist =
            toFloat (Trig.squareRoot (dx * dx + dy * dy))

        halfW =
            toFloat arena.space.width / 2

        halfH =
            toFloat arena.space.height / 2

        ownSpeed =
            speed own.velocity

        foeSpeed =
            speed foe.velocity

        maxT =
            max 1 ownCore.characteristics.maxThrust

        foeMaxT =
            max 1 foeCore.characteristics.maxThrust

        toward =
            Trig.arctan dx dy

        faceAng =
            facing * 4

        relFace =
            Trig.normalizeAngle (foeFacing * 4 - faceAng)

        travel =
            travelAngle own.velocity

        (Wait wWait) =
            ownCore.weaponWait

        (Wait sWait) =
            ownCore.specialWait

        (Wait tWait) =
            own.turnWait

        (Wait thWait) =
            own.thrustWait

        ( myNow, mySoon ) =
            hitHints arena ownC own facing foe

        ( theirNow, theirSoon ) =
            hitHints arena foeC foe foeFacing own

        turnErr =
            shortestFacing (angleToFacing toward - facing)

        ( pdx, pdy, phit ) =
            planetVec arena own

        ( sh, sc, ss ) =
            incoming arena side own
    in
    [ clamp01 (toFloat ownCore.energy / toFloat (max 1 ownCore.maxEnergy))
    , clamp01 (toFloat own.points / toFloat (max 1 ownCore.maxCrew))
    , unit faceAng
    , unitS faceAng
    , clamp01 (ownSpeed / toFloat maxT)
    , unit (Trig.normalizeAngle (travel - faceAng))
    , unitS (Trig.normalizeAngle (travel - faceAng))
    , flag (wWait <= 0)
    , flag (sWait <= 0)
    , flag (tWait <= 0)
    , flag (thWait <= 0)
    , clamp11 (toFloat dx / halfW)
    , clamp11 (toFloat dy / halfH)
    , clamp01 (dist / 4000)
    , clamp11 (closing own.velocity foe.velocity dx dy / 200)
    , unit relFace
    , unitS relFace
    , clamp01 (toFloat foeCore.energy / toFloat (max 1 foeCore.maxEnergy))
    , clamp01 (toFloat foe.points / toFloat (max 1 foeCore.maxCrew))
    , clamp01 (foeSpeed / toFloat foeMaxT)
    , flag ownCore.cloaked
    , myNow
    , mySoon
    , clamp11 (toFloat turnErr / 8)
    , theirNow
    , theirSoon
    , pdx
    , pdy
    , phit
    , sh
    , sc
    , ss
    , 1
    ]


flag : Bool -> Float
flag b =
    if b then
        1

    else
        0


clamp01 : Float -> Float
clamp01 x =
    max 0 (min 1 x)


clamp11 : Float -> Float
clamp11 x =
    max -1 (min 1 x)


unit : Int -> Float
unit ang =
    toFloat (Trig.cosine ang 100) / 100


unitS : Int -> Float
unitS ang =
    toFloat (Trig.sine ang 100) / 100


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


displacement : Int -> VelocityDesc -> ( Int, Int )
displacement turns vel =
    Velocity.getNext (max 1 turns) vel |> Tuple.first


hitHints : Arena -> State.Combatant -> Element -> Int -> Element -> ( Float, Float )
hitHints arena shipEl origin facing target =
    case Arsenal.primary shipEl of
        Projectile.Missile spec ->
            let
                best =
                    List.foldl
                        (\mount acc ->
                            let
                                f =
                                    Facing (modBy 16 (facing + mount.facingOffset))

                                launch =
                                    Arsenal.launchState spec f origin.velocity (Arsenal.mountPosition spec facing origin.current.location mount)

                                flags =
                                    origin.flags

                                ghost =
                                    { origin
                                        | current = { location = launch.position, frameIndex = facing }
                                        , velocity = launch.velocity
                                        , flags = { flags | playerShip = False }
                                    }

                                t =
                                    plotIntercept arena.space ghost target spec.life 0
                            in
                            if t > 0 && (acc == 0 || t < acc) then
                                t

                            else
                                acc
                        )
                        0
                        (Arsenal.mounts spec)
            in
            if best <= 0 then
                ( 0, 0 )

            else
                ( 1 / (1 + toFloat best)
                , if best <= spec.life then
                    1

                  else
                    0
                )

        _ ->
            let
                dx =
                    Trig.wrapDelta (target.current.location.x - origin.current.location.x) arena.space.width

                dy =
                    Trig.wrapDelta (target.current.location.y - origin.current.location.y) arena.space.height

                dist =
                    Trig.squareRoot (dx * dx + dy * dy)

                wanted =
                    angleToFacing (Trig.arctan dx dy)

                delta =
                    Trig.normalizeFacing (wanted - facing)

                lined =
                    dist <= intelRange (State.kind shipEl) && (delta <= 2 || delta >= 14)
            in
            if lined then
                ( 1, 1 )

            else
                ( 0, 0 )


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
                wrap space { x = a.current.location.x + dax, y = a.current.location.y + day }

            pb =
                wrap space { x = b.current.location.x + dbx, y = b.current.location.y + dby }

            dx =
                Trig.wrapDelta (pa.x - pb.x) space.width

            dy =
                Trig.wrapDelta (pa.y - pb.y) space.height

            r =
                40 + 40 + margin
        in
        if dx * dx + dy * dy <= r * r then
            t

        else
            plotFrom space a b margin maxTurns (t + 1)


wrap : WorldExtent -> WorldPoint -> WorldPoint
wrap =
    Trig.wrapPoint


planetVec : Arena -> Element -> ( Float, Float, Float )
planetVec arena own =
    let
        planet =
            Dict.foldl
                (\_ el acc ->
                    if el.body == PlanetBody then
                        Just el

                    else
                        acc
                )
                Nothing
                arena.elements
    in
    case planet of
        Nothing ->
            ( 0, 0, 0 )

        Just p ->
            let
                dx =
                    Trig.wrapDelta (p.current.location.x - own.current.location.x) arena.space.width

                dy =
                    Trig.wrapDelta (p.current.location.y - own.current.location.y) arena.space.height

                hit =
                    plotIntercept arena.space own p 32 160
            in
            ( clamp11 (toFloat dx / 4000)
            , clamp11 (toFloat dy / 4000)
            , if hit <= 0 then
                0

              else
                1 / (1 + toFloat hit)
            )


incoming : Arena -> Side -> Element -> ( Float, Float, Float )
incoming arena side own =
    let
        pick =
            Dict.foldl
                (\_ el acc ->
                    if el.flags.playerShip || el.flags.nonsolid || el.parent == Just side || el.parent == Nothing then
                        acc

                    else
                        let
                            dx =
                                Trig.wrapDelta (el.current.location.x - own.current.location.x) arena.space.width

                            dy =
                                Trig.wrapDelta (el.current.location.y - own.current.location.y) arena.space.height

                            d2 =
                                dx * dx + dy * dy

                            cand =
                                { el = el, d2 = d2, dx = dx, dy = dy }
                        in
                        case acc of
                            Nothing ->
                                Just cand

                            Just best ->
                                if d2 < best.d2 then
                                    Just cand

                                else
                                    acc
                )
                Nothing
                arena.elements
    in
    case pick of
        Nothing ->
            ( 0, 0, 0 )

        Just p ->
            let
                hit =
                    plotIntercept arena.space p.el own 16 40

                ang =
                    Trig.arctan p.dx p.dy
            in
            ( if hit <= 0 then
                0

              else
                1 / (1 + toFloat hit)
            , unit ang
            , unitS ang
            )
