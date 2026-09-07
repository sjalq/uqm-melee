module Melee.Projectile exposing (..)

{-| Weapon categories and per-projectile state. A missile has flight and durability;
a ray has endpoints and no flight lifetime. Animation age is separate from facing.
Definitions are ported from sc2/src/uqm/weapon.c and ships/_/_.c.
-}

import Melee.Units exposing (Facing, WorldPoint)


type MissileKind
    = Bubble
    | Crystal
    | Shard
    | Dogi
    | Cannon
    | Nuke
    | Flame
    | Saw
    | Fried
    | Charge
    | Confusion
    | Torpedo
    | Plasma
    | Howitzer
    | Marine
    | Bug
    | Dart
    | SpathiShot
    | Butt
    | Pellet
    | Dagger
    | Blaster
    | Napalm
    | Fusion
    | Fighter
    | Lance
    | Limpet
    | YehatShot
    | Spit


type BeamKind
    = AutoAim
    | Megawatt
    | Twin
    | Green
    | PointDefense
    | Zap
    | FighterBeam


type ContactKind
    = Cone
    | Tongue


type Guidance
    = Ballistic
    | Tracking { wait : Int, initialWait : Int }
    | BubbleFlight
    | HeldBlade


type Animation
    = Directional
    | Frames { count : Int, ticks : Int }
    | PlasmaDecay
    | ChargeLevel


type Launch
    = Nose Int
    | Ports (List { forward : Int, sideways : Int, facingOffset : Int })


type Inheritance
    = Independent
    | InheritVelocity


type alias MissileSpec =
    { kind : MissileKind
    , speed : Int
    , life : Int
    , damage : Int
    , hitPoints : Int
    , launch : Launch
    , directions : List Int
    , guidance : Guidance
    , animation : Animation
    , inheritance : Inheritance
    , blastOffset : Int
    , friendlyFire : Bool
    }


type Weapon
    = Missile MissileSpec
    | Beam BeamKind
    | Contact ContactKind
    | Lightning


type State
    = Flying MissileKind { age : Int, facing : Facing, trackingWait : Int }
    | Charging { ticks : Int, facing : Facing }
    | Ray BeamKind { origin : WorldPoint, end : WorldPoint }
    | Attached ContactKind { age : Int, facing : Facing }
    | LightningSegment { origin : WorldPoint, end : WorldPoint }
