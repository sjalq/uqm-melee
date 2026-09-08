port module Oracle.Masks exposing (main)

{-| Resolves every sprite the collision code can ask for into its mask, so the
Rust port never handles sprite path strings at runtime.

Collision masks are addressed by `(body, frameIndex)` and, for ships, by
`(kind, variant, facing)`. Both are enumerable, so we enumerate them here and
emit a lookup table plus the deduplicated mask bodies.
`scripts/oracle/gen-masks.mjs` turns this into
`rust/crates/melee-sim/src/masks_generated.rs`.
-}

import Array
import Json.Encode as E
import Melee.Art as Art
import Melee.Catalog as Catalog
import Melee.Element exposing (Body(..))
import Melee.Masks as Masks
import Melee.Projectile exposing (..)
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Side(..))
import Platform


port emit : String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), emit (E.encode 0 payload) )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


{-| Widest frame index any body can present. Weapon impacts index their sprite
strip directly (no modulo), so this must cover the whole strip.
-}
maxFrames : Int
maxFrames =
    64


payload : E.Value
payload =
    E.object
        [ ( "maximumDimension", E.int Masks.maximumDimension )
        , ( "projectiles", E.list projectileRow projectileBodies )
        , ( "ships", E.list shipRow shipVariants )
        ]


{-| Every body the sprite table can answer for, tagged the way the Rust `Body`
enum names it. `ChmmrSatellite`'s facing payload does not affect the path.
-}
projectileBodies : List ( String, Body )
projectileBodies =
    [ ( "UmgahCone", UmgahCone )
    , ( "ZoqTongue", ZoqTongue )
    , ( "OrzMarine", OrzMarine )
    , ( "AndrosynthBubble", AndrosynthBubble )
    , ( "ChenjesuPhoton", ChenjesuPhoton )
    , ( "ChenjesuFragment", ChenjesuFragment )
    , ( "ChenjesuDogi", ChenjesuDogi )
    , ( "DruugeHotShot", DruugeHotShot )
    , ( "EarthlingNuke", EarthlingNuke )
    , ( "IlwrathFlame", IlwrathFlame )
    , ( "KohrAhSaw", KohrAhSaw )
    , ( "KohrAhFried", KohrAhFried )
    , ( "MelnormeCharge", MelnormeCharge )
    , ( "MelnormeConfusion", MelnormeConfusion )
    , ( "MmrnmhrmMissile", MmrnmhrmMissile )
    , ( "MyconPlasma", MyconPlasma )
    , ( "OrzHowitzer", OrzHowitzer )
    , ( "PkunkSpread", PkunkSpread )
    , ( "ShofixtiDart", ShofixtiDart )
    , ( "SpathiForward", SpathiForward )
    , ( "SpathiButt", SpathiButt )
    , ( "SupoxPellet", SupoxPellet )
    , ( "SyreenMissile", SyreenMissile )
    , ( "ThraddashBlaster", ThraddashBlaster )
    , ( "ThraddashAfterburn", ThraddashAfterburn )
    , ( "UrQuanFusion", UrQuanFusion )
    , ( "UrQuanFighter", UrQuanFighter )
    , ( "UtwigGizmo", UtwigGizmo )
    , ( "VuxLimpet", VuxLimpet )
    , ( "YehatMissile", YehatMissile )
    , ( "ZoqSpit", ZoqSpit )
    , ( "ChmmrSatellite", ChmmrSatellite { orbitFacing = Melee.Units.Facing 0 } )
    , ( "ArilouLaser", ArilouLaser )
    , ( "ChmmrLaser", ChmmrLaser )
    , ( "ChmmrZap", ChmmrZap )
    , ( "MmrnmhrmLaser", MmrnmhrmLaser )
    , ( "VuxLaser", VuxLaser )
    , ( "EarthlingPointDefense", EarthlingPointDefense )
    , ( "UrQuanFighterLaser", UrQuanFighterLaser )
    , ( "SlylandroLightning", SlylandroLightning )
    , ( "ShofixtiGlory", ShofixtiGlory )
    , ( "Blast", BlastBody )
    , ( "Explosion", ExplosionBody )
    , ( "WarpIn", WarpInBody )
    , ( "IonTrail", IonTrailBody )
    , ( "Planet", PlanetBody )
    , ( "Asteroid", AsteroidBody )
    ]
        ++ List.map (\( tag, m ) -> ( "WeaponImpact:" ++ tag, WeaponImpact m )) impactKinds


impactKinds : List ( String, MissileKind )
impactKinds =
    [ ( "Bubble", Bubble ), ( "Crystal", Crystal ), ( "Shard", Shard ), ( "Dogi", Dogi )
    , ( "Cannon", Cannon ), ( "Nuke", Nuke ), ( "Flame", Flame ), ( "Saw", Saw )
    , ( "Fried", Fried ), ( "Charge", Charge ), ( "Confusion", Confusion ), ( "Torpedo", Torpedo )
    , ( "Plasma", Plasma ), ( "Howitzer", Howitzer ), ( "Marine", Marine ), ( "Bug", Bug )
    , ( "Dart", Dart ), ( "SpathiShot", SpathiShot ), ( "Butt", Butt ), ( "Pellet", Pellet )
    , ( "Dagger", Dagger ), ( "Blaster", Blaster ), ( "Napalm", Napalm ), ( "Fusion", Fusion )
    , ( "Fighter", Fighter ), ( "Lance", Lance ), ( "Limpet", Limpet ), ( "YehatShot", YehatShot )
    , ( "Spit", Spit )
    ]


projectileRow : ( String, Body ) -> E.Value
projectileRow ( tag, body ) =
    E.object
        [ ( "body", E.string tag )
        , ( "frames"
          , E.list
                (\frame ->
                    Art.projectile body frame
                        |> Maybe.andThen (\sprite -> Masks.get sprite.path)
                        |> maskValue
                )
                (List.range 0 (maxFrames - 1))
          )
        ]


{-| Ship sprites depend on the live combatant, because the Androsynth blazer
and the Mmrnmhrm Y-wing swap the sprite strip.
-}
shipVariants : List ( ShipKind, String )
shipVariants =
    List.concatMap
        (\kind ->
            case kind of
                Androsynth ->
                    [ ( kind, "normal" ), ( kind, "alt" ) ]

                Mmrnmhrm ->
                    [ ( kind, "normal" ), ( kind, "alt" ) ]

                _ ->
                    [ ( kind, "normal" ) ]
        )
        Catalog.all


shipRow : ( ShipKind, String ) -> E.Value
shipRow ( kind, variant ) =
    E.object
        [ ( "kind", E.string (kindTag kind) )
        , ( "variant", E.string variant )
        , ( "facings"
          , E.list
                (\facing -> Masks.get (shipSpritePath kind variant facing) |> maskValue)
                (List.range 0 15)
          )
        ]


{-| `Melee.Art.ship`, without needing a live combatant: the only variants that
change the sprite strip are the Androsynth blazer and the Mmrnmhrm Y-wing.
-}
shipSpritePath : ShipKind -> String -> Int -> String
shipSpritePath kind variant facing =
    let
        frame =
            String.padLeft 3 '0' (String.fromInt (modBy 16 facing))
    in
    case ( kind, variant ) of
        ( Androsynth, "alt" ) ->
            "/ships/androsynth/blazer-big-" ++ frame ++ ".png"

        ( Mmrnmhrm, "alt" ) ->
            "/ships/mmrnmhrm/ywing-big-" ++ frame ++ ".png"

        _ ->
            Catalog.sprite kind facing


maskValue : Maybe Masks.Mask -> E.Value
maskValue maybeMask =
    case maybeMask of
        Nothing ->
            E.null

        Just m ->
            E.object
                [ ( "width", E.int m.width )
                , ( "height", E.int m.height )
                , ( "x", E.int m.x )
                , ( "y", E.int m.y )
                , ( "rows"
                  , E.list (E.list (\( a, b ) -> E.list E.int [ a, b ])) (Array.toList m.rows)
                  )
                ]


kindTag : ShipKind -> String
kindTag k =
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
