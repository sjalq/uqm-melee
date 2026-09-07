module Melee.Units exposing
    ( Angle(..)
    , Facing(..)
    , FrameCount(..)
    , FrameTicks
    , Side(..)
    , Sided
    , VelocityDesc
    , Wait(..)
    , WorldExtent
    , WorldPoint
    , Zoom(..)
    , battleFramesPerSecond
    , gravityMassThreshold
    , gravityThreshold
    , maxCrewSize
    , maxEnergySize
    , maxShipMass
    , stockLogSpace
    )

{-| Fixed-point units of the UQM battle simulation.

UQM's melee runs on integers only. Every quantity here is an Int so that
two clients (and the backend, if it replays) reach bit-identical state from
the same inputs. Floats are forbidden in the simulation layer.

Source constants (sc2/src/uqm/units.h, velocity.h, battle.h):

    CIRCLE_SHIFT   = 6   -> FULL_CIRCLE = 64 angle units per revolution
    FACING_SHIFT   = 4   -> 16 ship facings per revolution
    ONE_SHIFT      = 2   -> world coord = display pixel << 2
    MAX_REDUCTION  = 3   -> LOG_SPACE = (display << 2) << 3 (wrap-around field)
    VELOCITY_SHIFT = 5   -> velocity = world << 5 (sub-world fixed point)
    BATTLE_FRAME_RATE = ONE_SECOND / 24
    Display clock is 60 Hz (Melee.Rate.displayHz); physics is still 24 Hz.

-}


{-| Stock 320x240 melee field in world units.

    SPACE_WIDTH  = 320 - 64 = 256
    SPACE_HEIGHT = 240
    LOG_SPACE_*  = DISPLAY_TO_WORLD(SPACE_*) << MAX_REDUCTION(3)

UQM computes these from the runtime screen size. Exact recreation of
stock Super Melee uses this extent. A non-stock window would recompute
the same formula; the live value lives on `Melee.Battle.Arena.space`.

-}
stockLogSpace : WorldExtent
stockLogSpace =
    { width = 8192
    , height = 7680
    }


battleFramesPerSecond : Int
battleFramesPerSecond =
    24


maxCrewSize : Int
maxCrewSize =
    42


maxEnergySize : Int
maxEnergySize =
    42


maxShipMass : Int
maxShipMass =
    10


{-| GRAVITY\_MASS(m) = m > MAX\_SHIP\_MASS \* 10. Planet mass is above this.
-}
gravityMassThreshold : Int
gravityMassThreshold =
    100


gravityThreshold : Int
gravityThreshold =
    255


{-| The two seats of a melee. NUM\_SIDES = 2, never more.

`Bottom` is playerNr 0 (drawn at the bottom of the status bar),
`Top` is playerNr 1. Neutral elements (planet, asteroids, drifting crew)
have no Side; they use `Melee.Element.Owner` = Neutral.

-}
type Side
    = Bottom
    | Top


{-| One value per side. Replaces `array[NUM_SIDES]` so a missing or
extra side is unrepresentable.
-}
type alias Sided a =
    { bottom : a
    , top : a
    }


{-| Angle in 1/64ths of a full circle. Always normalised to 0..63
(NORMALIZE\_ANGLE masks with FULL\_CIRCLE-1). Construction is via the
smart constructor in this module once implemented; the raw constructor is
exposed only for the Lamdera wire codecs.
-}
type Angle
    = Angle Int


{-| Ship facing in 1/16ths of a full circle, normalised to 0..15.
FACING\_TO\_ANGLE f = f << 2, ANGLE\_TO\_FACING a = (a + 2) >> 2.
Sprites exist only for these 16 orientations, so a ship can never face a
non-facing angle. Projectiles however travel along a full 64-unit Angle.
-}
type Facing
    = Facing Int


{-| A location in logical (world) coordinates. One display pixel is 4
world units (DISPLAY\_TO\_WORLD x = x << 2). The battlefield wraps at
LOG\_SPACE\_WIDTH x LOG\_SPACE\_HEIGHT.
-}
type alias WorldPoint =
    { x : Int
    , y : Int
    }


type alias WorldExtent =
    { width : Int
    , height : Int
    }


{-| UQM's VELOCITY\_DESC, verbatim. The engine does not integrate a float
velocity; it keeps an integer vector plus fractional error terms and steps
positions with Bresenham-style accumulation (velocity.c: GetNextVelocityComponents).
Every field is required to reproduce movement exactly, including the
`error` and `fract` accumulators that carry sub-unit remainders across frames.

    travelAngle : direction of travel, 0..63
    vector      : per-frame integer step in world units (dx, dy)
    fract       : fractional remainder of the step (VELOCITY_SHIFT fixed point)
    error       : accumulated rounding error
    incr        : magnitude components, VELOCITY_SHIFT fixed point

-}
type alias VelocityDesc =
    { travelAngle : Angle
    , vector : WorldExtent
    , fract : WorldExtent
    , error : WorldExtent
    , incr : WorldExtent
    }


{-| Count of C battle frames. 24 per second. Used for the lockstep
frame counter and for life spans.
-}
type FrameCount
    = FrameCount Int


type alias FrameTicks =
    Int


{-| Raw C BYTE used as a countdown or a bitfield (asteroid spin lives in
bit 7). Units are 24 Hz C frames. Zero means ready.
-}
type Wait
    = Wait Int


{-| View reduction level (units.h: NUM\_VIEWS = 3). The camera zooms out
as the ships separate. Zoom affects rendering only, never the simulation,
so it lives outside `BattleState`. It is included here because each ship
has a sprite set per view.
-}
type Zoom
    = ZoomClose
    | ZoomMid
    | ZoomFar
