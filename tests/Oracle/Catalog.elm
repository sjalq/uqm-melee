port module Oracle.Catalog exposing (main)

{-| Machine-readable dump of every immutable catalog table in the simulation:
ship stock, abilities, characteristics, intel ranges, weapon assignment and
the full missile spec list.

`scripts/oracle/gen-catalog.mjs` turns this into
`rust/crates/melee-sim/src/catalog_generated.rs`, so the Rust tables are
generated from the Elm source of truth rather than transcribed by hand.
-}

import Json.Encode as E
import Melee.Arsenal as Arsenal
import Melee.Element
import Melee.Catalog as Catalog
import Melee.Projectile exposing (..)
import Melee.Ship as Ship exposing (Ability, Characteristics, ShipKind(..))
import Melee.Units exposing (Wait(..))
import Platform


port emit : String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), emit (E.encode 2 payload) )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


payload : E.Value
payload =
    E.object
        [ ( "ships", E.list ship Catalog.all )
        , ( "missiles", E.list missile allMissiles )
        , ( "beams", E.list beam allBeams )
        , ( "mmrnmhrmYWing", characteristics Ship.mmrnmhrmYWing )
        ]


wait : Wait -> E.Value
wait (Wait n) =
    E.int n


ship : ShipKind -> E.Value
ship kind =
    let
        s =
            Ship.stock kind

        i =
            Catalog.info kind
    in
    E.object
        [ ( "kind", E.string (shipTag kind) )
        , ( "name", E.string i.name )
        , ( "vessel", E.string i.vessel )
        , ( "sprite", E.string i.sprite )
        , ( "intelRange", E.int (Ship.intelRange kind) )
        , ( "cost", E.int s.cost )
        , ( "maxCrew", E.int s.maxCrew )
        , ( "maxEnergy", E.int s.maxEnergy )
        , ( "startingCrew", E.int s.startingCrew )
        , ( "startingEnergy", E.int s.startingEnergy )
        , ( "ability", ability s.ability )
        , ( "characteristics", characteristics s.characteristics )
        , ( "weapon", weapon (Arsenal.standard kind) )
        ]


ability : Ability -> E.Value
ability a =
    E.object
        [ ( "seekingWeapon", E.bool a.seekingWeapon )
        , ( "seekingSpecial", E.bool a.seekingSpecial )
        , ( "pointDefense", E.bool a.pointDefense )
        , ( "immediateWeapon", E.bool a.immediateWeapon )
        , ( "crewImmune", E.bool a.crewImmune )
        , ( "firesFore", E.bool a.firesFore )
        , ( "firesRight", E.bool a.firesRight )
        , ( "firesAft", E.bool a.firesAft )
        , ( "firesLeft", E.bool a.firesLeft )
        , ( "shieldDefense", E.bool a.shieldDefense )
        , ( "dontChase", E.bool a.dontChase )
        ]


characteristics : Characteristics -> E.Value
characteristics c =
    E.object
        [ ( "maxThrust", E.int c.maxThrust )
        , ( "thrustIncrement", E.int c.thrustIncrement )
        , ( "energyRegeneration", E.int c.energyRegeneration )
        , ( "weaponEnergyCost", E.int c.weaponEnergyCost )
        , ( "specialEnergyCost", E.int c.specialEnergyCost )
        , ( "energyWait", wait c.energyWait )
        , ( "turnWait", wait c.turnWait )
        , ( "thrustWait", wait c.thrustWait )
        , ( "weaponWait", wait c.weaponWait )
        , ( "specialWait", wait c.specialWait )
        , ( "shipMass", E.int c.shipMass )
        ]


weapon : Weapon -> E.Value
weapon w =
    case w of
        Missile spec ->
            E.object [ ( "tag", E.string "missile" ), ( "missile", E.string (missileTag spec.kind) ) ]

        Beam b ->
            E.object [ ( "tag", E.string "beam" ), ( "beam", E.string (beamTag b) ) ]

        Contact c ->
            E.object
                [ ( "tag", E.string "contact" )
                , ( "contact"
                  , E.string
                        (case c of
                            Cone ->
                                "Cone"

                            Tongue ->
                                "Tongue"
                        )
                  )
                ]

        Lightning ->
            E.object [ ( "tag", E.string "lightning" ) ]


missile : MissileKind -> E.Value
missile k =
    let
        s =
            Arsenal.spec k
    in
    E.object
        [ ( "kind", E.string (missileTag s.kind) )
        , ( "requested", E.string (missileTag k) )
        , ( "speed", E.int s.speed )
        , ( "life", E.int s.life )
        , ( "damage", E.int s.damage )
        , ( "hitPoints", E.int s.hitPoints )
        , ( "launch", launch s.launch )
        , ( "directions", E.list E.int s.directions )
        , ( "guidance", guidance s.guidance )
        , ( "animation", animation s.animation )
        , ( "inheritance"
          , E.string
                (case s.inheritance of
                    Independent ->
                        "Independent"

                    InheritVelocity ->
                        "InheritVelocity"
                )
          )
        , ( "blastOffset", E.int s.blastOffset )
        , ( "friendlyFire", E.bool s.friendlyFire )
        , ( "body", E.string (bodyTag (Arsenal.missileBody k)) )
        , ( "homing", E.bool (Arsenal.homing (Arsenal.missileBody k)) )
        , ( "isProjectile", E.bool (Arsenal.isProjectile (Arsenal.missileBody k)) )
        , ( "mounts"
          , E.list
                (\m ->
                    E.object
                        [ ( "forward", E.int m.forward )
                        , ( "sideways", E.int m.sideways )
                        , ( "facingOffset", E.int m.facingOffset )
                        ]
                )
                (Arsenal.mounts s)
          )
        ]


beam : BeamKind -> E.Value
beam b =
    E.object
        [ ( "kind", E.string (beamTag b) )
        , ( "body", E.string (bodyTag (Arsenal.beamBody b)) )
        , ( "isProjectile", E.bool (Arsenal.isProjectile (Arsenal.beamBody b)) )
        ]


launch : Launch -> E.Value
launch l =
    case l of
        Nose forward ->
            E.object [ ( "tag", E.string "nose" ), ( "forward", E.int forward ) ]

        Ports ports ->
            E.object
                [ ( "tag", E.string "ports" )
                , ( "ports"
                  , E.list
                        (\p ->
                            E.object
                                [ ( "forward", E.int p.forward )
                                , ( "sideways", E.int p.sideways )
                                , ( "facingOffset", E.int p.facingOffset )
                                ]
                        )
                        ports
                  )
                ]


guidance : Guidance -> E.Value
guidance g =
    case g of
        Ballistic ->
            E.object [ ( "tag", E.string "ballistic" ) ]

        Tracking t ->
            E.object
                [ ( "tag", E.string "tracking" )
                , ( "wait", E.int t.wait )
                , ( "initialWait", E.int t.initialWait )
                ]

        BubbleFlight ->
            E.object [ ( "tag", E.string "bubble" ) ]

        HeldBlade ->
            E.object [ ( "tag", E.string "heldBlade" ) ]


animation : Animation -> E.Value
animation a =
    case a of
        Directional ->
            E.object [ ( "tag", E.string "directional" ) ]

        Frames f ->
            E.object [ ( "tag", E.string "frames" ), ( "count", E.int f.count ), ( "ticks", E.int f.ticks ) ]

        PlasmaDecay ->
            E.object [ ( "tag", E.string "plasmaDecay" ) ]

        ChargeLevel ->
            E.object [ ( "tag", E.string "chargeLevel" ) ]


allMissiles : List MissileKind
allMissiles =
    [ Bubble, Crystal, Shard, Dogi, Cannon, Nuke, Flame, Saw, Fried, Charge, Confusion, Torpedo, Plasma, Howitzer, Marine, Bug, Dart, SpathiShot, Butt, Pellet, Dagger, Blaster, Napalm, Fusion, Fighter, Lance, Limpet, YehatShot, Spit ]


allBeams : List BeamKind
allBeams =
    [ AutoAim, Megawatt, Twin, Green, PointDefense, Zap, FighterBeam ]


missileTag : MissileKind -> String
missileTag k =
    case k of
        Bubble -> "Bubble"
        Crystal -> "Crystal"
        Shard -> "Shard"
        Dogi -> "Dogi"
        Cannon -> "Cannon"
        Nuke -> "Nuke"
        Flame -> "Flame"
        Saw -> "Saw"
        Fried -> "Fried"
        Charge -> "Charge"
        Confusion -> "Confusion"
        Torpedo -> "Torpedo"
        Plasma -> "Plasma"
        Howitzer -> "Howitzer"
        Marine -> "Marine"
        Bug -> "Bug"
        Dart -> "Dart"
        SpathiShot -> "SpathiShot"
        Butt -> "Butt"
        Pellet -> "Pellet"
        Dagger -> "Dagger"
        Blaster -> "Blaster"
        Napalm -> "Napalm"
        Fusion -> "Fusion"
        Fighter -> "Fighter"
        Lance -> "Lance"
        Limpet -> "Limpet"
        YehatShot -> "YehatShot"
        Spit -> "Spit"


beamTag : BeamKind -> String
beamTag b =
    case b of
        AutoAim -> "AutoAim"
        Megawatt -> "Megawatt"
        Twin -> "Twin"
        Green -> "Green"
        PointDefense -> "PointDefense"
        Zap -> "Zap"
        FighterBeam -> "FighterBeam"


shipTag : ShipKind -> String
shipTag k =
    case k of
        Androsynth -> "Androsynth"
        Arilou -> "Arilou"
        Chenjesu -> "Chenjesu"
        Chmmr -> "Chmmr"
        Druuge -> "Druuge"
        Earthling -> "Earthling"
        Ilwrath -> "Ilwrath"
        KohrAh -> "KohrAh"
        Melnorme -> "Melnorme"
        Mmrnmhrm -> "Mmrnmhrm"
        Mycon -> "Mycon"
        Orz -> "Orz"
        Pkunk -> "Pkunk"
        Shofixti -> "Shofixti"
        Slylandro -> "Slylandro"
        Spathi -> "Spathi"
        Supox -> "Supox"
        Syreen -> "Syreen"
        Thraddash -> "Thraddash"
        Umgah -> "Umgah"
        UrQuan -> "UrQuan"
        Utwig -> "Utwig"
        Vux -> "Vux"
        Yehat -> "Yehat"
        ZoqFotPik -> "ZoqFotPik"


bodyTag : Melee.Element.Body -> String
bodyTag b =
    case b of
        Melee.Element.AndrosynthBubble -> "AndrosynthBubble"
        Melee.Element.ArilouLaser -> "ArilouLaser"
        Melee.Element.ChenjesuPhoton -> "ChenjesuPhoton"
        Melee.Element.ChenjesuFragment -> "ChenjesuFragment"
        Melee.Element.ChenjesuDogi -> "ChenjesuDogi"
        Melee.Element.ChmmrLaser -> "ChmmrLaser"
        Melee.Element.ChmmrZap -> "ChmmrZap"
        Melee.Element.DruugeHotShot -> "DruugeHotShot"
        Melee.Element.EarthlingNuke -> "EarthlingNuke"
        Melee.Element.EarthlingPointDefense -> "EarthlingPointDefense"
        Melee.Element.IlwrathFlame -> "IlwrathFlame"
        Melee.Element.KohrAhSaw -> "KohrAhSaw"
        Melee.Element.KohrAhFried -> "KohrAhFried"
        Melee.Element.MelnormeCharge -> "MelnormeCharge"
        Melee.Element.MelnormeConfusion -> "MelnormeConfusion"
        Melee.Element.MmrnmhrmLaser -> "MmrnmhrmLaser"
        Melee.Element.MmrnmhrmMissile -> "MmrnmhrmMissile"
        Melee.Element.MyconPlasma -> "MyconPlasma"
        Melee.Element.OrzHowitzer -> "OrzHowitzer"
        Melee.Element.OrzMarine -> "OrzMarine"
        Melee.Element.PkunkSpread -> "PkunkSpread"
        Melee.Element.ShofixtiDart -> "ShofixtiDart"
        Melee.Element.SlylandroLightning -> "SlylandroLightning"
        Melee.Element.SpathiForward -> "SpathiForward"
        Melee.Element.SpathiButt -> "SpathiButt"
        Melee.Element.SupoxPellet -> "SupoxPellet"
        Melee.Element.SyreenMissile -> "SyreenMissile"
        Melee.Element.ThraddashBlaster -> "ThraddashBlaster"
        Melee.Element.ThraddashAfterburn -> "ThraddashAfterburn"
        Melee.Element.UmgahCone -> "UmgahCone"
        Melee.Element.UrQuanFusion -> "UrQuanFusion"
        Melee.Element.UrQuanFighter -> "UrQuanFighter"
        Melee.Element.UrQuanFighterLaser -> "UrQuanFighterLaser"
        Melee.Element.UtwigGizmo -> "UtwigGizmo"
        Melee.Element.VuxLaser -> "VuxLaser"
        Melee.Element.VuxLimpet -> "VuxLimpet"
        Melee.Element.YehatMissile -> "YehatMissile"
        Melee.Element.ZoqSpit -> "ZoqSpit"
        Melee.Element.ZoqTongue -> "ZoqTongue"
        _ -> "Other"
