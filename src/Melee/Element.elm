module Melee.Element exposing
    ( Body(..)
    , Element
    , ElementFlags
    , Image
    , IntersectControl
    , Life(..)
    , Owner(..)
    , Prim(..)
    , maxDisplayElements
    , objectCloaked
    )

{-| One node of the display queue. This is UQM's ELEMENT, with the C
unions split so a planet cannot carry a weapon\_counter and a laser
cannot carry crew (MISI).

Checksum (checksum.c crc\_processELEMENT) walks the queue in order and
CRCs, for every non-BACKGROUND\_OBJECT:

    state_flags, life_span, crew_level, mass_points, turn_wait,
    thrust_wait, velocity, current.location, next.location

Those fields therefore live on every `Element`, even when a particular
`Body` does not conceptually use them. `points` is the C `crew_level`
/ `hit_points` union; `mass` is `mass_points` (damage for weapons,
inertial mass for ships / planet / asteroids).

MAX\_DISPLAY\_ELEMENTS = 150.

-}

import Melee.Id exposing (ElementId)
import Melee.Projectile as Projectile
import Melee.Units exposing (Facing, Side, VelocityDesc, Wait, WorldPoint)


maxDisplayElements : Int
maxDisplayElements =
    150


{-| playerNr: -1 / 0 / 1. Neutral covers the planet, asteroids, and
drifting crew that have not yet been claimed.
-}
type Owner
    = Neutral
    | Owned Side


{-| ELEMENT\_FLAGS as booleans. Bit positions in the C UWORD, for the
CRC reconstruction:

    2 PLAYER_SHIP, 3 APPEARING, 4 DISAPPEARING, 5 CHANGING,
    6 NONSOLID, 7 COLLISION, 8 IGNORE_SIMILAR, 9 DEFY_PHYSICS,
    10 FINITE_LIFE, 11 PRE_PROCESS, 12 POST_PROCESS,
    13 IGNORE_VELOCITY, 14 CREW_OBJECT, 15 BACKGROUND_OBJECT

-}
type alias ElementFlags =
    { playerShip : Bool
    , appearing : Bool
    , disappearing : Bool
    , changing : Bool
    , nonsolid : Bool
    , collision : Bool
    , ignoreSimilar : Bool
    , defyPhysics : Bool
    , finiteLife : Bool
    , preProcess : Bool
    , postProcess : Bool
    , ignoreVelocity : Bool
    , crewObject : Bool
    , backgroundObject : Bool
    }


{-| Ships and the planet are not FINITE\_LIFE; weapons are.
`Persistent` is C life\_span used as NORMAL\_LIFE (1) or as an explosion
frame counter after death. `Finite n` is a countdown; 0 means the
element is dying this preprocess (process.c).
-}
type Life
    = Persistent Int
    | Finite Int


{-| gfxlib.h INTERSECT\_CONTROL. last\_time\_val is the TIME\_VALUE of the
last collision test along this element's motion segment.
-}
type alias IntersectControl =
    { lastTimeVal : Int
    , endPoint : WorldPoint
    , stampOrigin : WorldPoint
    }


{-| Display prim. OBJECT\_CLOAKED is NoPrim or black StampFill, not an
Ilwrath-only tag.
-}
type Prim
    = NoPrim
    | Stamp
    | StampFill { black : Bool }
    | Line


objectCloaked : Prim -> Bool
objectCloaked prim =
    case prim of
        NoPrim ->
            True

        StampFill { black } ->
            black

        Stamp ->
            False

        Line ->
            False


{-| C STATE: location plus the facing/anim index of the stamp.
Collision uses farray[0] + this index; we do not store the bitmap.
-}
type alias Image =
    { location : WorldPoint
    , frameIndex : Int
    }


type alias Element =
    { id : ElementId
    , owner : Owner
    , parent : Maybe Side
    , target : Maybe ElementId
    , flags : ElementFlags
    , life : Life
    , points : Int
    , mass : Int
    , turnWait : Wait
    , thrustWait : Wait
    , colorCycleIndex : Int
    , velocity : VelocityDesc
    , intersect : IntersectControl
    , current : Image
    , next : Image
    , prim : Prim
    , projectile : Maybe Projectile.State
    , body : Body
    }


{-| What this node is. Weapons are per-ship so an Earthling cannot
spawn a DOGI. Homing / animation counters that C stashes in
turn\_wait / thrust\_wait stay on the common `Element` record because
they are checksummed there.

Blast, explosion, and warp-in are engine-generic (weapon.c, tactrans.c).

-}
type Body
    = ShipBody Side
    | WreckBody Side
    | PlanetBody
    | AsteroidBody
    | CrewBody { origin : Side }
    | WeaponImpact Projectile.MissileKind
    | BlastBody
    | ExplosionBody
    | WarpInBody
    | IonTrailBody
    | AndrosynthBubble
    | ArilouLaser
    | ChenjesuPhoton
    | ChenjesuFragment
    | ChenjesuDogi
    | ChmmrLaser
    | ChmmrSatellite { orbitFacing : Facing }
    | ChmmrZap
    | DruugeHotShot
    | EarthlingNuke
    | EarthlingPointDefense
    | IlwrathFlame
    | KohrAhSaw
    | KohrAhFried
    | MelnormeCharge
    | MelnormeConfusion
    | MmrnmhrmLaser
    | MmrnmhrmMissile
    | MyconPlasma
    | OrzHowitzer
    | OrzMarine
    | PkunkSpread
    | ShofixtiDart
    | ShofixtiGlory
    | SlylandroLightning
    | SpathiForward
    | SpathiButt
    | SupoxPellet
    | SyreenMissile
    | ThraddashBlaster
    | ThraddashAfterburn
    | UmgahCone
    | UrQuanFusion
    | UrQuanFighter
    | UrQuanFighterLaser
    | UtwigGizmo
    | VuxLaser
    | VuxLimpet
    | YehatMissile
    | ZoqSpit
    | ZoqTongue
