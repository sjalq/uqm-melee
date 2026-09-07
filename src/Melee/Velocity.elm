module Melee.Velocity exposing
    ( delta
    , getCurrent
    , getNext
    , setComponents
    , setVector
    , zero
    )

{-| velocity.c, integer only. `incr` stores MAKE\_WORD packed as Int.
-}

import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), VelocityDesc, WorldExtent)


velocityShift : Int
velocityShift =
    5


velocityScale : Int
velocityScale =
    32


worldToVelocity : Int -> Int
worldToVelocity w =
    w * velocityScale


velocityToWorld : Int -> Int
velocityToWorld v =
    v // velocityScale


remainder : Int -> Int
remainder v =
    modBy velocityScale v


loByte : Int -> Int
loByte x =
    modBy 256 x


hiByte : Int -> Int
hiByte x =
    modBy 256 (x // 256)


sByte : Int -> Int
sByte b =
    if b >= 128 then
        b - 256

    else
        b


makeWord : Int -> Int -> Int
makeWord lo hi =
    modBy 256 lo + modBy 256 hi * 256


zeroExtent : WorldExtent
zeroExtent =
    { width = 0, height = 0 }


zero : VelocityDesc
zero =
    { travelAngle = Angle 0
    , vector = zeroExtent
    , fract = zeroExtent
    , error = zeroExtent
    , incr = zeroExtent
    }


getCurrent : VelocityDesc -> ( Int, Int )
getCurrent v =
    ( worldToVelocity v.vector.width + (v.fract.width - hiByte v.incr.width)
    , worldToVelocity v.vector.height + (v.fract.height - hiByte v.incr.height)
    )


getNext : Int -> VelocityDesc -> ( ( Int, Int ), VelocityDesc )
getNext numFrames v =
    let
        axis err fract vector incr =
            let
                e =
                    err + fract * numFrames

                d =
                    vector
                        * numFrames
                        + sByte (loByte incr)
                        * (e // velocityScale)
            in
            ( d, remainder e )

        ( dx, errX ) =
            axis v.error.width v.fract.width v.vector.width v.incr.width

        ( dy, errY ) =
            axis v.error.height v.fract.height v.vector.height v.incr.height
    in
    ( ( dx, dy )
    , { v | error = { width = errX, height = errY } }
    )


setPacked : Int -> ( Int, Int )
setPacked d =
    if d >= 0 then
        ( velocityToWorld d, makeWord 1 0 )

    else
        let
            ad =
                -d
        in
        ( -(velocityToWorld ad), makeWord 0xFF (remainder ad * 2) )


setComponents : Int -> Int -> VelocityDesc
setComponents dx dy =
    let
        angle =
            Trig.arctan dx dy
    in
    if angle == Trig.fullCircle then
        zero

    else
        let
            ax =
                if dx >= 0 then
                    dx

                else
                    -dx

            ay =
                if dy >= 0 then
                    dy

                else
                    -dy

            ( vw, iw ) =
                setPacked dx

            ( vh, ih ) =
                setPacked dy
        in
        { travelAngle = Angle (Trig.normalizeAngle angle)
        , vector = { width = vw, height = vh }
        , fract = { width = remainder ax, height = remainder ay }
        , error = zeroExtent
        , incr = { width = iw, height = ih }
        }


setVector : Int -> Facing -> VelocityDesc
setVector magnitude (Facing facing) =
    let
        angle =
            Trig.normalizeFacing facing * 4

        magV =
            worldToVelocity magnitude

        dx =
            Trig.cosine angle magV

        dy =
            Trig.sine angle magV
    in
    let
        v =
            setComponents dx dy
    in
    { v | travelAngle = Angle angle }


delta : Int -> Int -> VelocityDesc -> VelocityDesc
delta ddx ddy v =
    let
        ( cx, cy ) =
            getCurrent v
    in
    setComponents (cx + ddx) (cy + ddy)
