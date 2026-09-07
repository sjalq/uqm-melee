module Melee.View exposing (camera, displayLocation, viewCockpit, viewCockpitWithControls)

import Dict
import Html exposing (Html, div)
import Html.Attributes as H
import Melee.Art as Art
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Element exposing (..)
import Melee.Graphics exposing (Quality(..))
import Melee.Hires as Hires
import Melee.Id exposing (toInt)
import Melee.Pixel as Pixel
import Melee.Projectile as Projectile
import Melee.ShipState as ShipState exposing (Combatant, core)
import Melee.Space as Space
import Melee.Trig as Trig
import Melee.Units exposing (..)
import Svg exposing (Svg)
import Svg.Attributes as A


type alias Cam =
    { cx : Int, cy : Int, w : Int, h : Int }


viewCockpit : Quality -> Float -> Arena -> Html msg
viewCockpit quality zoom arena =
    viewCockpitWithControls [] quality zoom arena


viewCockpitWithControls : List (Html msg) -> Quality -> Float -> Arena -> Html msg
viewCockpitWithControls controls quality zoom arena =
    div
        [ H.class
            ("melee-cockpit"
                ++ (if List.isEmpty controls then
                        ""

                    else
                        " has-pilot-controls"
                   )
            )
        , H.attribute "data-frame"
            (case arena.frame of
                FrameCount frame ->
                    String.fromInt frame
            )
        ]
        ([ spaceView quality zoom arena
         , Svg.svg [ A.class "melee-status", A.viewBox "0 0 64 240", A.width "20%", A.height "100%", H.attribute "aria-label" "Ship status", A.style "image-rendering:pixelated" ]
            (hudColors :: (panel 0 arena.combatants.top arena ++ panel 120 arena.combatants.bottom arena))
         ]
            ++ (if List.isEmpty controls then
                    []

                else
                    [ div [ H.class "pilot-controls" ] controls ]
               )
        )


spaceView : Quality -> Float -> Arena -> Html msg
spaceView quality zoom arena =
    let
        target =
            camera arena

        width =
            if quality == HighDefinition then
                round zoom

            else
                target.w

        cam =
            { target | w = width, h = width * 240 // 256 }

        (FrameCount frame) =
            arena.frame
    in
    div [ H.style "width" "80%", H.style "height" "100%", H.style "position" "relative", H.style "overflow" "hidden", H.style "background" "black" ]
        [ Space.view (toFloat frame / 24)
        , Svg.svg [ A.viewBox ("0 0 " ++ String.fromInt cam.w ++ " " ++ String.fromInt cam.h), A.width "100%", A.height "100%", A.style "position:relative;display:block;image-rendering:pixelated", A.preserveAspectRatio "xMidYMid meet" ]
            (List.filterMap (\id -> Dict.get (toInt id) arena.elements) arena.queue |> List.map (paint quality cam arena))
        ]


camera : Arena -> Cam
camera arena =
    let
        shipLocation ship =
            Dict.get (toInt (core ship).element) arena.elements |> Maybe.map (displayLocation arena) |> Maybe.withDefault { x = arena.space.width // 2, y = arena.space.height // 2 }

        b =
            shipLocation arena.combatants.bottom

        t =
            shipLocation arena.combatants.top

        dx =
            Trig.wrapDelta (t.x - b.x) arena.space.width

        dy =
            Trig.wrapDelta (t.y - b.y) arena.space.height

        needed =
            max (abs dx + 360) ((abs dy + 360) * 256 // 240)

        width =
            List.filter (\w -> w >= needed) [ 1024, 2048, 4096, 8192 ] |> List.head |> Maybe.withDefault 8192
    in
    { cx = Trig.wrap (b.x + dx // 2) arena.space.width, cy = Trig.wrap (b.y + dy // 2) arena.space.height, w = width, h = width * 240 // 256 }



-- Interpolate the 24 Hz simulation at the 60 Hz presentation clock.
-- Large discontinuities (teleport/warp) snap rather than crossing the arena.


displayLocation : Arena -> Element -> WorldPoint
displayLocation arena el =
    let
        now =
            el.current.location

        before =
            Dict.get (toInt el.id) arena.previousLocations |> Maybe.withDefault now

        dx =
            Trig.wrapDelta (now.x - before.x) arena.space.width

        dy =
            Trig.wrapDelta (now.y - before.y) arena.space.height

        alpha =
            toFloat arena.pumpAcc / 60
    in
    if abs dx + abs dy > 800 then
        now

    else
        Trig.wrapPoint arena.space { x = before.x + round (toFloat dx * alpha), y = before.y + round (toFloat dy * alpha) }


point : Cam -> WorldExtent -> WorldPoint -> ( Int, Int )
point cam space at =
    ( Trig.wrapDelta (at.x - cam.cx) space.width + cam.w // 2, Trig.wrapDelta (at.y - cam.cy) space.height + cam.h // 2 )


classicStamp : String -> Int -> Int -> Svg msg
classicStamp path x y =
    let
        m =
            Art.metrics path
    in
    Svg.image [ A.x (String.fromInt (x - m.x * 4)), A.y (String.fromInt (y - m.y * 4)), A.width (String.fromInt (m.width * 4)), A.height (String.fromInt (m.height * 4)), A.xlinkHref path, A.style "image-rendering:pixelated" ] []


paint : Quality -> Cam -> Arena -> Element -> Svg msg
paint quality cam arena el =
    let
        stamp path px py =
            case ( quality, Hires.get path ) of
                ( HighDefinition, Just sprite ) ->
                    Svg.image [ A.x (String.fromInt (px - sprite.x)), A.y (String.fromInt (py - sprite.y)), A.width (String.fromInt sprite.width), A.height (String.fromInt sprite.height), A.xlinkHref sprite.path, A.style "image-rendering:auto" ] []

                _ ->
                    classicStamp path px py

        ( x, y ) =
            point cam arena.space (displayLocation arena el)

        (FrameCount frame) =
            arena.frame

        framePath prefix index =
            "/classic/" ++ prefix ++ "-big-" ++ String.padLeft 3 '0' (String.fromInt index) ++ ".png"

        life =
            case el.life of
                Finite n ->
                    n

                Persistent n ->
                    n

        age =
            max 0 (el.colorCycleIndex - life)
    in
    case el.body of
        PlanetBody ->
            stamp "/classic/planet.png" x y

        AsteroidBody ->
            stamp (framePath "asteroid" (modBy 21 (frame // 3 + toInt el.id))) x y

        WreckBody side ->
            if age < 15 then
                stamp
                    (Art.ship
                        (if side == Bottom then
                            arena.combatants.bottom

                         else
                            arena.combatants.top
                        )
                        el.current.frameIndex
                    )
                    x
                    y

            else
                Svg.g [] []

        ExplosionBody ->
            stamp (framePath "boom" (min 8 age)) x y

        BlastBody ->
            stamp (framePath "blast" (modBy 8 el.current.frameIndex)) x y

        ShipBody side ->
            let
                ship =
                    if side == Bottom then
                        arena.combatants.bottom

                    else
                        arena.combatants.top

                c =
                    core ship
            in
            Svg.g
                [ A.class "combat-ship"
                , A.transform ("translate(" ++ String.fromInt x ++ "," ++ String.fromInt y ++ ")")
                , A.opacity
                    (if c.cloaked then
                        "0.08"

                     else
                        "1"
                    )
                ]
                ([ stamp (Art.ship ship el.current.frameIndex) 0 0 ]
                    ++ (case ship of
                            ShipState.LiveOrz _ extra ->
                                let
                                    (Facing hull) =
                                        c.facing

                                    (Facing turret) =
                                        extra.turretFacing
                                in
                                [ stamp ("/ships/orz/turret-big-" ++ String.padLeft 3 '0' (String.fromInt (modBy 16 (hull + turret))) ++ ".png") 0 0 ]

                            _ ->
                                []
                       )
                    ++ (if c.shieldTicks > 0 then
                            [ Svg.circle [ A.r "85", A.fill "none", A.stroke "#74fcff", A.strokeWidth "4" ] [] ]

                        else
                            []
                       )
                )

        CrewBody _ ->
            Svg.rect [ A.x (String.fromInt x), A.y (String.fromInt y), A.width "4", A.height "4", A.fill "#00ff00" ] []

        IonTrailBody ->
            Svg.g [] []

        WarpInBody ->
            Svg.rect [ A.x (String.fromInt (x - 40)), A.y (String.fromInt (y - 60)), A.width "80", A.height "120", A.fill "none", A.stroke "#ffffff", A.strokeWidth "4", A.opacity "0.5" ] []

        _ ->
            if el.prim == Line then
                let
                    emitter =
                        case el.owner of
                            Owned side ->
                                Dict.get
                                    (toInt
                                        (core
                                            (if side == Bottom then
                                                arena.combatants.bottom

                                             else
                                                arena.combatants.top
                                            )
                                        ).element
                                    )
                                    arena.elements

                            Neutral ->
                                Nothing

                    shift =
                        emitter
                            |> Maybe.map
                                (\ship ->
                                    let
                                        shown =
                                            displayLocation arena ship
                                    in
                                    { x = Trig.wrapDelta (shown.x - ship.current.location.x) arena.space.width, y = Trig.wrapDelta (shown.y - ship.current.location.y) arena.space.height }
                                )
                            |> Maybe.withDefault { x = 0, y = 0 }

                    ( ax, ay ) =
                        point cam arena.space (Trig.wrapPoint arena.space { x = el.intersect.stampOrigin.x + shift.x, y = el.intersect.stampOrigin.y + shift.y })

                    -- Use the origin's wrapped copy for both endpoints.
                    bx =
                        ax + Trig.wrapDelta (el.intersect.endPoint.x - el.intersect.stampOrigin.x) arena.space.width

                    by =
                        ay + Trig.wrapDelta (el.intersect.endPoint.y - el.intersect.stampOrigin.y) arena.space.height

                    color =
                        case el.projectile of
                            Just (Projectile.Ray Projectile.Green _) ->
                                "#52ff52"

                            Just (Projectile.Ray Projectile.AutoAim _) ->
                                "#ffff52"

                            Just (Projectile.Ray Projectile.Megawatt _) ->
                                if modBy 4 frame == 2 then
                                    "#ff8c00"

                                else
                                    "#ff1900"

                            Just (Projectile.Ray Projectile.Twin _) ->
                                "#ff5252"

                            Just (Projectile.LightningSegment _) ->
                                "#adb5ff"

                            _ ->
                                "#ffffff"
                in
                Svg.line [ A.x1 (String.fromInt ax), A.y1 (String.fromInt ay), A.x2 (String.fromInt bx), A.y2 (String.fromInt by), A.stroke color, A.strokeWidth "4" ] []

            else
                case Art.projectile el.body el.current.frameIndex of
                    Just art ->
                        stamp art.path x y

                    Nothing ->
                        Svg.rect [ A.x (String.fromInt x), A.y (String.fromInt y), A.width "8", A.height "8", A.fill "#ffec46" ] []


hudColors : Svg msg
hudColors =
    Svg.defs []
        (List.map (\( name, ( r, g, b ) ) -> Svg.filter [ A.id name ] [ Svg.feColorMatrix [ A.type_ "matrix", A.values ("0 0 0 0 " ++ r ++ " 0 0 0 0 " ++ g ++ " 0 0 0 0 " ++ b ++ " 0 0 0 1 0") ] [] ])
            [ ( "hud-black", ( "0", "0", "0" ) ), ( "hud-green", ( "0", "0.3", "0" ) ), ( "hud-red", ( "0.5", "0", "0" ) ), ( "hud-yellow", ( "1", "1", "0" ) ) ]
        )


panel : Int -> Combatant -> Arena -> List (Svg msg)
panel offset ship arena =
    let
        c =
            core ship

        health =
            Dict.get (toInt c.element) arena.elements |> Maybe.map .points |> Maybe.withDefault 0

        info =
            Catalog.info (ShipState.kind ship)

        label filter x y value =
            Svg.g [ A.filter ("url(#" ++ filter ++ ")") ] [ Pixel.text x y True value ]

        rect x y w h fill =
            Svg.rect [ A.x (String.fromInt x), A.y (String.fromInt y), A.width (String.fromInt w), A.height (String.fromInt h), A.fill fill ] []

        image path x y w h =
            Svg.image [ A.x x, A.y y, A.width w, A.height h, A.xlinkHref path, A.style "image-rendering:pixelated" ] []

        meters x filled total color =
            rect (x - 1) 14 7 43 "#222222"
                :: (List.range 0 (max 0 (total - 1))
                        |> List.map
                            (\index ->
                                rect (x + modBy 2 index * 3)
                                    (54 - index // 2 * 2)
                                    2
                                    1
                                    (if index < filled then
                                        color

                                     else
                                        "#111111"
                                    )
                            )
                   )
    in
    [ Svg.g [ A.class "classic-panel", A.transform ("translate(0," ++ String.fromInt offset ++ ")") ]
        ([ rect 0 0 64 120 "#555555"
         , Svg.path [ A.d "M 0 120 V 0 H 64 L 62 2 H 2 V 118 Z", A.fill "#858585" ] []
         , Svg.path [ A.d "M 2 118 H 62 V 2 L 64 0 V 120 H 0 Z", A.fill "#303030" ] []
         , label "hud-black" 32 3 (String.toUpper info.name)
         , image (Art.schematic ship) "12" "13" "40" "40"
         , label "hud-black" 32 53 (Art.captain ship)
         , label "hud-green" 15 59 "CREW"
         , label
            (if c.energy < c.maxEnergy // 3 then
                "hud-red"

             else
                "hud-yellow"
            )
            49
            59
            "BATT"
         , rect 3 67 57 32 "#222222"
         , image (Art.portrait ship) "4" "68" "55" "30"
         , Svg.title [] [ Svg.text (info.name ++ ": crew " ++ String.fromInt health ++ "/" ++ String.fromInt c.maxCrew ++ ", battery " ++ String.fromInt c.energy ++ "/" ++ String.fromInt c.maxEnergy ++ ". " ++ info.help) ]
         ]
            ++ List.map
                (\path ->
                    let
                        m =
                            Art.metrics path
                    in
                    image path (String.fromInt (4 - m.x)) (String.fromInt (68 - m.y)) (String.fromInt m.width) (String.fromInt m.height)
                )
                (Art.portraitLayers ship)
            ++ meters 5 health c.maxCrew "#00cf00"
            ++ meters 54 c.energy c.maxEnergy "#ef0000"
        )
    ]
