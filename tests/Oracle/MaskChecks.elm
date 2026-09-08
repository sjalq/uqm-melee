port module Oracle.MaskChecks exposing (main)

{-| Differential sweep of `Melee.Masks.overlap` / `opaque` over real sprite
pairs. The Rust port emits the same dump from `masks_generated.rs`; any diff is
a collision-geometry defect. Enumeration order must stay in step with
`Oracle.Masks`, which is what generates the Rust tables.
-}

import Melee.Art as Art
import Melee.Catalog as Catalog
import Melee.Element exposing (Body(..))
import Melee.Masks as Masks
import Melee.Projectile exposing (MissileKind(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.Units exposing (Facing(..))
import Platform


port emit : String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), emit (String.join "\n" dump) )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


{-| Probe sprites: every ship hull at four facings, plus a spread of weapon
sprites whose masks differ in size and row shape.
-}
probes : List ( String, Maybe Masks.Mask )
probes =
    List.concatMap
        (\kind ->
            List.map
                (\facing ->
                    ( "ship:" ++ tag kind ++ ":" ++ String.fromInt facing
                    , Masks.get (Catalog.sprite kind facing)
                    )
                )
                [ 0, 3, 7, 11 ]
        )
        Catalog.all
        ++ List.map
            (\( name, body, frame ) ->
                ( "proj:" ++ name ++ ":" ++ String.fromInt frame
                , Art.projectile body frame |> Maybe.andThen (\s -> Masks.get s.path)
                )
            )
            projectileProbes


projectileProbes : List ( String, Body, Int )
projectileProbes =
    List.concatMap
        (\( name, body ) -> List.map (\f -> ( name, body, f )) [ 0, 1, 5 ])
        [ ( "PkunkSpread", PkunkSpread )
        , ( "UmgahCone", UmgahCone )
        , ( "YehatMissile", YehatMissile )
        , ( "ChenjesuDogi", ChenjesuDogi )
        , ( "KohrAhSaw", KohrAhSaw )
        , ( "MyconPlasma", MyconPlasma )
        , ( "EarthlingNuke", EarthlingNuke )
        , ( "VuxLimpet", VuxLimpet )
        , ( "ChmmrSatellite", ChmmrSatellite { orbitFacing = Facing 0 } )
        , ( "WeaponImpact:Bug", WeaponImpact Bug )
        ]


offsets : List Int
offsets =
    List.map (\i -> i * 7 - 63) (List.range 0 18)


dump : List String
dump =
    List.map opaqueRow probes ++ overlapRows


opaqueRow : ( String, Maybe Masks.Mask ) -> String
opaqueRow ( name, maybeMask ) =
    case maybeMask of
        Nothing ->
            "opaque " ++ name ++ " none"

        Just mask ->
            "opaque "
                ++ name
                ++ " "
                ++ String.fromInt mask.width
                ++ "x"
                ++ String.fromInt mask.height
                ++ "@"
                ++ String.fromInt mask.x
                ++ ","
                ++ String.fromInt mask.y
                ++ " "
                ++ bits
                    (List.concatMap
                        (\y -> List.map (\x -> Masks.opaque mask x y) (List.range -20 20))
                        (List.range -20 20)
                    )


{-| Every probe against every fourth probe, so the sweep stays large but bounded.
-}
overlapRows : List String
overlapRows =
    let
        indexed =
            List.indexedMap Tuple.pair probes
    in
    List.concatMap
        (\( i, ( nameA, a ) ) ->
            List.filterMap
                (\( j, ( nameB, b ) ) ->
                    if modBy 4 (i + j) /= 0 then
                        Nothing

                    else
                        Just
                            ("overlap "
                                ++ nameA
                                ++ " "
                                ++ nameB
                                ++ " "
                                ++ (case ( a, b ) of
                                        ( Just ma, Just mb ) ->
                                            bits
                                                (List.concatMap
                                                    (\dy -> List.map (\dx -> Masks.overlap ma mb dx dy) offsets)
                                                    offsets
                                                )

                                        _ ->
                                            "none"
                                   )
                            )
                )
                indexed
        )
        indexed


{-| Pack booleans into hex nibbles so the dump stays small and diffs stay legible.
-}
bits : List Bool -> String
bits values =
    let
        go rest acc pending count =
            case rest of
                [] ->
                    if count == 0 then
                        String.reverse acc

                    else
                        String.reverse (nibble (pending * 2 ^ (4 - count)) ++ acc)

                v :: more ->
                    let
                        next =
                            pending
                                * 2
                                + (if v then
                                    1

                                   else
                                    0
                                  )
                    in
                    if count == 3 then
                        go more (nibble next ++ acc) 0 0

                    else
                        go more acc next (count + 1)
    in
    go values "" 0 0


nibble : Int -> String
nibble n =
    case n of
        0 -> "0"
        1 -> "1"
        2 -> "2"
        3 -> "3"
        4 -> "4"
        5 -> "5"
        6 -> "6"
        7 -> "7"
        8 -> "8"
        9 -> "9"
        10 -> "a"
        11 -> "b"
        12 -> "c"
        13 -> "d"
        14 -> "e"
        _ -> "f"


tag : ShipKind -> String
tag k =
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
