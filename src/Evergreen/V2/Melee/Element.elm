module Evergreen.V2.Melee.Element exposing (..)

import Evergreen.V2.Melee.Id
import Evergreen.V2.Melee.Projectile
import Evergreen.V2.Melee.Units


type Owner
    = Neutral
    | Owned Evergreen.V2.Melee.Units.Side


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


type Life
    = Persistent Int
    | Finite Int


type alias IntersectControl =
    { lastTimeVal : Int
    , endPoint : Evergreen.V2.Melee.Units.WorldPoint
    , stampOrigin : Evergreen.V2.Melee.Units.WorldPoint
    }


type alias Image =
    { location : Evergreen.V2.Melee.Units.WorldPoint
    , frameIndex : Int
    }


type Prim
    = NoPrim
    | Stamp
    | StampFill
        { black : Bool
        }
    | Line


type Body
    = ShipBody Evergreen.V2.Melee.Units.Side
    | WreckBody Evergreen.V2.Melee.Units.Side
    | PlanetBody
    | AsteroidBody
    | CrewBody
        { origin : Evergreen.V2.Melee.Units.Side
        }
    | WeaponImpact Evergreen.V2.Melee.Projectile.MissileKind
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
    | ChmmrSatellite
        { orbitFacing : Evergreen.V2.Melee.Units.Facing
        }
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


type alias Element =
    { id : Evergreen.V2.Melee.Id.ElementId
    , owner : Owner
    , parent : Maybe Evergreen.V2.Melee.Units.Side
    , target : Maybe Evergreen.V2.Melee.Id.ElementId
    , flags : ElementFlags
    , life : Life
    , points : Int
    , mass : Int
    , turnWait : Evergreen.V2.Melee.Units.Wait
    , thrustWait : Evergreen.V2.Melee.Units.Wait
    , colorCycleIndex : Int
    , velocity : Evergreen.V2.Melee.Units.VelocityDesc
    , intersect : IntersectControl
    , current : Image
    , next : Image
    , prim : Prim
    , projectile : Maybe Evergreen.V2.Melee.Projectile.State
    , body : Body
    }
