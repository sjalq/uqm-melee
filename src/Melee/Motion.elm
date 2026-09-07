module Melee.Motion exposing (Motion, atLimit, beyondLimit, flags, thrust, velocity)

import Melee.ShipState exposing (CombatantCore, MotionFlags)
import Melee.Trig as Trig
import Melee.Units exposing (Angle(..), Facing(..), VelocityDesc)
import Melee.Velocity as Velocity


type Motion
    = Stationary
    | Moving VelocityDesc Speed


type Speed
    = BelowLimit
    | AtLimit
    | GravityBoosted
    | BeyondLimit


fromVelocity : VelocityDesc -> Speed -> Motion
fromVelocity v speed =
    if Velocity.getCurrent v == ( 0, 0 ) then
        Stationary

    else
        Moving v speed


current : VelocityDesc -> MotionFlags -> Motion
current v state =
    fromVelocity v
        (case ( state.atMaxSpeed, state.beyondMaxSpeed ) of
            ( False, False ) ->
                BelowLimit

            ( True, False ) ->
                AtLimit

            ( False, True ) ->
                GravityBoosted

            ( True, True ) ->
                BeyondLimit
        )


velocity : Motion -> VelocityDesc
velocity motion =
    case motion of
        Stationary ->
            Velocity.zero

        Moving v _ ->
            v


flags : Motion -> { atMaxSpeed : Bool, beyondMaxSpeed : Bool }
flags motion =
    case motion of
        Stationary ->
            { atMaxSpeed = False, beyondMaxSpeed = False }

        Moving _ speed ->
            { atMaxSpeed = speed == AtLimit || speed == BeyondLimit
            , beyondMaxSpeed = speed == GravityBoosted || speed == BeyondLimit
            }


atLimit : VelocityDesc -> MotionFlags -> Bool
atLimit v state =
    case current v state of
        Stationary ->
            False

        Moving _ speed ->
            speed /= BelowLimit


beyondLimit : VelocityDesc -> MotionFlags -> Bool
beyondLimit v state =
    (flags (current v state)).beyondMaxSpeed


thrust : VelocityDesc -> CombatantCore -> Motion
thrust v c =
    let
        chars =
            c.characteristics

        (Facing facing) =
            c.facing

        angle =
            facing * 4

        (Angle travel) =
            v.travelAngle

        increment =
            chars.thrustIncrement * 32

        ( cx, cy ) =
            Velocity.getCurrent v

        dx =
            cx + Trig.cosine angle increment

        dy =
            cy + Trig.sine angle increment

        desired =
            dx * dx + dy * dy

        maximum =
            chars.maxThrust * 32

        maxSquared =
            maximum * maximum

        currentSquared =
            cx * cx + cy * cy
    in
    if chars.thrustIncrement == chars.maxThrust then
        fromVelocity (Velocity.setVector chars.maxThrust c.facing) AtLimit

    else if travel == angle && atLimit v c.flags && not c.flags.inGravityWell then
        current v c.flags

    else if desired <= maxSquared then
        fromVelocity (Velocity.setComponents dx dy) BelowLimit

    else if (c.flags.inGravityWell && desired <= 2304 * 2304) || desired < currentSquared then
        fromVelocity (Velocity.setComponents dx dy) BeyondLimit

    else if travel == angle then
        fromVelocity
            (if currentSquared <= maxSquared then
                Velocity.setVector chars.maxThrust c.facing

             else
                v
            )
            AtLimit

    else
        let
            turned =
                Velocity.delta
                    (Trig.cosine angle (increment // 2) - Trig.cosine travel increment)
                    (Trig.sine angle (increment // 2) - Trig.sine travel increment)
                    v

            ( tx, ty ) =
                Velocity.getCurrent turned

            turnedSquared =
                tx * tx + ty * ty
        in
        if turnedSquared > maxSquared then
            fromVelocity
                (if turnedSquared < currentSquared then
                    turned

                 else
                    v
                )
                BeyondLimit

        else
            fromVelocity turned BelowLimit
