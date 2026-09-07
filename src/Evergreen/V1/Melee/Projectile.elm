module Evergreen.V1.Melee.Projectile exposing (..)

import Evergreen.V1.Melee.Units


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


type State
    = Flying
        MissileKind
        { age : Int
        , facing : Evergreen.V1.Melee.Units.Facing
        , trackingWait : Int
        }
    | Charging
        { ticks : Int
        , facing : Evergreen.V1.Melee.Units.Facing
        }
    | Ray
        BeamKind
        { origin : Evergreen.V1.Melee.Units.WorldPoint
        , end : Evergreen.V1.Melee.Units.WorldPoint
        }
    | Attached
        ContactKind
        { age : Int
        , facing : Evergreen.V1.Melee.Units.Facing
        }
    | LightningSegment
        { origin : Evergreen.V1.Melee.Units.WorldPoint
        , end : Evergreen.V1.Melee.Units.WorldPoint
        }
