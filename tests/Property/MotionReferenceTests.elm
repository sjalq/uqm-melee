module Property.MotionReferenceTests exposing (suite)

import Bitwise
import Expect
import Fixtures.ThrustReference as Reference
import Melee.Init as Init
import Melee.Motion as Motion
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.ShipState as State
import Melee.Units exposing (Facing(..))
import Melee.Velocity as Velocity
import Test exposing (describe, test)


suite =
    describe "Original C thrust dynamics"
        [ test "all 25 ship characteristics, 16 facings, acceleration, coasting, gravity and deceleration match C" <|
            \_ ->
                let
                    mismatch ( ship, ( facing, ( x, y ), status ), expected ) =
                        let
                            core =
                                State.core (Init.arena ship Shofixti (Seed 1)).combatants.bottom

                            flags =
                                core.flags

                            motion =
                                Motion.thrust (Velocity.setComponents x y)
                                    { core | facing = Facing facing, flags = { flags | atMaxSpeed = Bitwise.and status 1 /= 0, beyondMaxSpeed = Bitwise.and status 2 /= 0, inGravityWell = Bitwise.and status 4 /= 0 } }

                            result =
                                Motion.flags motion

                            ( dx, dy ) =
                                Velocity.getCurrent (Motion.velocity motion)

                            actual =
                                ( dx
                                , dy
                                , (if result.atMaxSpeed then
                                    1

                                   else
                                    0
                                  )
                                    + (if result.beyondMaxSpeed then
                                        2

                                       else
                                        0
                                      )
                                )
                        in
                        if actual == expected then
                            Nothing

                        else
                            Just ( ( ship, facing, status ), expected, actual )
                in
                Reference.cases |> List.filterMap mismatch |> List.take 5 |> Expect.equal []
        , test "stationary motion cannot retain either speed-limit flag" <|
            \_ ->
                let
                    core =
                        State.core (Init.arena Supox Shofixti (Seed 1)).combatants.bottom

                    flags =
                        core.flags

                    stale =
                        { flags | atMaxSpeed = True, beyondMaxSpeed = True }
                in
                Expect.equal ( False, False ) ( Motion.atLimit Velocity.zero stale, Motion.beyondLimit Velocity.zero stale )
        ]
