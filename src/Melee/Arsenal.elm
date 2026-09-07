module Melee.Arsenal exposing (..)

import Melee.Element exposing (..)
import Melee.Projectile exposing (..)
import Melee.Ship exposing (..)
import Melee.ShipState exposing (..)


primary : Combatant -> Weapon
primary ship =
    case ship of
        LiveMmrnmhrm _ extra ->
            if extra.form == YWing then
                Missile (spec Torpedo)

            else
                Beam Twin

        _ ->
            standard (kind ship)


standard : ShipKind -> Weapon
standard ship =
    case ship of
        Androsynth ->
            Missile (spec Bubble)

        Arilou ->
            Beam AutoAim

        Chenjesu ->
            Missile (spec Crystal)

        Chmmr ->
            Beam Megawatt

        Druuge ->
            Missile (spec Cannon)

        Earthling ->
            Missile (spec Nuke)

        Ilwrath ->
            Missile (spec Flame)

        KohrAh ->
            Missile (spec Saw)

        Melnorme ->
            Missile (spec Charge)

        Mmrnmhrm ->
            Beam Twin

        Mycon ->
            Missile (spec Plasma)

        Orz ->
            Missile (spec Howitzer)

        Pkunk ->
            Missile (spec Bug)

        Shofixti ->
            Missile (spec Dart)

        Slylandro ->
            Lightning

        Spathi ->
            Missile (spec SpathiShot)

        Supox ->
            Missile (spec Pellet)

        Syreen ->
            Missile (spec Dagger)

        Thraddash ->
            Missile (spec Blaster)

        Umgah ->
            Contact Cone

        UrQuan ->
            Missile (spec Fusion)

        Utwig ->
            Missile (spec Lance)

        Vux ->
            Beam Green

        Yehat ->
            Missile (spec YehatShot)

        ZoqFotPik ->
            Missile (spec Spit)


spec : MissileKind -> MissileSpec
spec missile =
    case missile of
        Bubble ->
            { kind = Bubble
            , speed = 32
            , life = 200
            , damage = 2
            , hitPoints = 3
            , launch = Nose 14
            , directions = [ 0 ]
            , guidance = BubbleFlight
            , animation = Frames { count = 3, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 3
            , friendlyFire = False
            }

        Crystal ->
            { kind = Crystal
            , speed = 64
            , life = 90
            , damage = 6
            , hitPoints = 10
            , launch = Nose 16
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Frames { count = 1, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Shard ->
            { kind = Shard
            , speed = 64
            , life = 10
            , damage = 2
            , hitPoints = 1
            , launch = Nose 0
            , directions = [ 0, 2, 4, 6, 8, 10, 12, 14 ]
            , guidance = Ballistic
            , animation = Frames { count = 1, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 2
            , friendlyFire = False
            }

        Dogi ->
            { kind = Dogi
            , speed = 32
            , life = 600
            , damage = 0
            , hitPoints = 3
            , launch = Nose 18
            , directions = [ 0 ]
            , guidance = Tracking { wait = 0, initialWait = 0 }
            , animation = Frames { count = 7, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Cannon ->
            { kind = Cannon
            , speed = 120
            , life = 20
            , damage = 6
            , hitPoints = 4
            , launch = Nose 24
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 6
            , friendlyFire = False
            }

        Nuke ->
            { kind = Nuke
            , speed = 40
            , life = 60
            , damage = 4
            , hitPoints = 1
            , launch = Nose 42
            , directions = [ 0 ]
            , guidance = Tracking { wait = 3, initialWait = 3 }
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 8
            , friendlyFire = True
            }

        Flame ->
            { kind = Flame
            , speed = 25
            , life = 8
            , damage = 1
            , hitPoints = 1
            , launch = Nose 29
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Frames { count = 8, ticks = 1 }
            , inheritance = InheritVelocity
            , blastOffset = 0
            , friendlyFire = False
            }

        Saw ->
            { kind = Saw
            , speed = 64
            , life = 64
            , damage = 4
            , hitPoints = 10
            , launch = Nose 28
            , directions = [ 0 ]
            , guidance = HeldBlade
            , animation = Frames { count = 8, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 9
            , friendlyFire = False
            }

        Fried ->
            { kind = Fried
            , speed = 100
            , life = 8
            , damage = 3
            , hitPoints = 100
            , launch = Nose 28
            , directions = [ 0, 2, 4, 6, 8, 10, 12, 14 ]
            , guidance = Ballistic
            , animation = Frames { count = 8, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 2
            , friendlyFire = False
            }

        Charge ->
            { kind = Charge
            , speed = 180
            , life = 10
            , damage = 2
            , hitPoints = 2
            , launch = Nose 24
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = ChargeLevel
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Confusion ->
            { kind = Confusion
            , speed = 120
            , life = 20
            , damage = 0
            , hitPoints = 200
            , launch = Nose 24
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Frames { count = 16, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 4
            , friendlyFire = False
            }

        Torpedo ->
            { kind = Torpedo
            , speed = 80
            , life = 40
            , damage = 1
            , hitPoints = 1
            , launch = Ports [ { forward = 4, sideways = 4, facingOffset = -1 }, { forward = 4, sideways = -4, facingOffset = 1 } ]
            , directions = [ 0 ]
            , guidance = Tracking { wait = 5, initialWait = 5 }
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Plasma ->
            { kind = Plasma
            , speed = 32
            , life = 143
            , damage = 10
            , hitPoints = 10
            , launch = Nose 24
            , directions = [ 0 ]
            , guidance = Tracking { wait = 1, initialWait = 3 }
            , animation = PlasmaDecay
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = True
            }

        Howitzer ->
            { kind = Howitzer
            , speed = 120
            , life = 12
            , damage = 3
            , hitPoints = 2
            , launch = Nose 14
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 1
            , friendlyFire = False
            }

        Marine ->
            { kind = Marine
            , speed = 44
            , life = 600
            , damage = 2
            , hitPoints = 3
            , launch = Nose 14
            , directions = [ 0 ]
            , guidance = Tracking { wait = 0, initialWait = 0 }
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Bug ->
            { kind = Bug
            , speed = 96
            , life = 5
            , damage = 1
            , hitPoints = 1
            , launch = Nose 15
            , directions = [ 0, 4, 12 ]
            , guidance = Ballistic
            , animation = Frames { count = 1, ticks = 1 }
            , inheritance = InheritVelocity
            , blastOffset = 1
            , friendlyFire = False
            }

        Dart ->
            { kind = Dart
            , speed = 96
            , life = 10
            , damage = 1
            , hitPoints = 1
            , launch = Nose 15
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 1
            , friendlyFire = False
            }

        SpathiShot ->
            { kind = SpathiShot
            , speed = 120
            , life = 10
            , damage = 1
            , hitPoints = 1
            , launch = Nose 16
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 1
            , friendlyFire = False
            }

        Butt ->
            { kind = Butt
            , speed = 32
            , life = 30
            , damage = 2
            , hitPoints = 1
            , launch = Nose 20
            , directions = [ 0 ]
            , guidance = Tracking { wait = 1, initialWait = 1 }
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 4
            , friendlyFire = False
            }

        Pellet ->
            { kind = Pellet
            , speed = 120
            , life = 10
            , damage = 1
            , hitPoints = 1
            , launch = Nose 23
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 2
            , friendlyFire = False
            }

        Dagger ->
            { kind = Dagger
            , speed = 120
            , life = 10
            , damage = 2
            , hitPoints = 1
            , launch = Nose 30
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 3
            , friendlyFire = False
            }

        Blaster ->
            { kind = Blaster
            , speed = 120
            , life = 15
            , damage = 1
            , hitPoints = 2
            , launch = Nose 9
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 3
            , friendlyFire = False
            }

        Napalm ->
            { kind = Napalm
            , speed = 0
            , life = 48
            , damage = 2
            , hitPoints = 1
            , launch = Nose 0
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Frames { count = 8, ticks = 6 }
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Fusion ->
            { kind = Fusion
            , speed = 80
            , life = 20
            , damage = 6
            , hitPoints = 10
            , launch = Nose 32
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 8
            , friendlyFire = False
            }

        Fighter ->
            { kind = Fighter
            , speed = 48
            , life = 400
            , damage = 1
            , hitPoints = 1
            , launch = Nose 32
            , directions = [ 0 ]
            , guidance = Tracking { wait = 0, initialWait = 0 }
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        Lance ->
            { kind = Lance
            , speed = 120
            , life = 10
            , damage = 1
            , hitPoints = 1
            , launch = Ports [ { forward = 18, sideways = 5, facingOffset = 0 }, { forward = 18, sideways = -5, facingOffset = 0 }, { forward = 9, sideways = 13, facingOffset = 0 }, { forward = 9, sideways = -13, facingOffset = 0 }, { forward = 4, sideways = 17, facingOffset = 0 }, { forward = 4, sideways = -17, facingOffset = 0 } ]
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 1
            , friendlyFire = False
            }

        Limpet ->
            { kind = Limpet
            , speed = 25
            , life = 80
            , damage = 0
            , hitPoints = 1
            , launch = Nose 8
            , directions = [ 0 ]
            , guidance = Tracking { wait = 0, initialWait = 0 }
            , animation = Frames { count = 4, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }

        YehatShot ->
            { kind = YehatShot
            , speed = 80
            , life = 10
            , damage = 1
            , hitPoints = 1
            , launch = Ports [ { forward = 16, sideways = 8, facingOffset = 0 }, { forward = 16, sideways = -8, facingOffset = 0 } ]
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Directional
            , inheritance = Independent
            , blastOffset = 1
            , friendlyFire = False
            }

        Spit ->
            { kind = Spit
            , speed = 104
            , life = 10
            , damage = 1
            , hitPoints = 1
            , launch = Nose 13
            , directions = [ 0 ]
            , guidance = Ballistic
            , animation = Frames { count = 13, ticks = 1 }
            , inheritance = Independent
            , blastOffset = 0
            , friendlyFire = False
            }


missileBody : MissileKind -> Body
missileBody missile =
    case missile of
        Bubble ->
            AndrosynthBubble

        Crystal ->
            ChenjesuPhoton

        Shard ->
            ChenjesuFragment

        Dogi ->
            ChenjesuDogi

        Cannon ->
            DruugeHotShot

        Nuke ->
            EarthlingNuke

        Flame ->
            IlwrathFlame

        Saw ->
            KohrAhSaw

        Fried ->
            KohrAhFried

        Charge ->
            MelnormeCharge

        Confusion ->
            MelnormeConfusion

        Torpedo ->
            MmrnmhrmMissile

        Plasma ->
            MyconPlasma

        Howitzer ->
            OrzHowitzer

        Marine ->
            OrzMarine

        Bug ->
            PkunkSpread

        Dart ->
            ShofixtiDart

        SpathiShot ->
            SpathiForward

        Butt ->
            SpathiButt

        Pellet ->
            SupoxPellet

        Dagger ->
            SyreenMissile

        Blaster ->
            ThraddashBlaster

        Napalm ->
            ThraddashAfterburn

        Fusion ->
            UrQuanFusion

        Fighter ->
            UrQuanFighter

        Lance ->
            UtwigGizmo

        Limpet ->
            VuxLimpet

        YehatShot ->
            YehatMissile

        Spit ->
            ZoqSpit


beamBody : BeamKind -> Body
beamBody beam =
    case beam of
        AutoAim ->
            ArilouLaser

        Megawatt ->
            ChmmrLaser

        Twin ->
            MmrnmhrmLaser

        Green ->
            VuxLaser

        PointDefense ->
            EarthlingPointDefense

        Zap ->
            ChmmrZap

        FighterBeam ->
            UrQuanFighterLaser


homing : Body -> Bool
homing body =
    List.member body [ AndrosynthBubble, EarthlingNuke, MyconPlasma, MmrnmhrmMissile, SpathiButt, VuxLimpet, ChenjesuDogi, OrzMarine, UrQuanFighter ]


isProjectile : Body -> Bool
isProjectile body =
    case body of
        ShipBody _ ->
            False

        WreckBody _ ->
            False

        PlanetBody ->
            False

        AsteroidBody ->
            False

        CrewBody _ ->
            False

        WeaponImpact _ ->
            False

        BlastBody ->
            False

        ExplosionBody ->
            False

        WarpInBody ->
            False

        IonTrailBody ->
            False

        ChmmrSatellite _ ->
            False

        _ ->
            True
