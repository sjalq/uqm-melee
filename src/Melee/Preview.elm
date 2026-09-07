module Melee.Preview exposing (..)

import Dict
import Html exposing (Html)
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Id
import Melee.Ship exposing (ShipKind)
import Melee.ShipState as State
import Melee.Trig as Trig
import Melee.Units exposing (Facing(..), FrameCount(..))
import Melee.View as View
import Svg exposing (..)
import Svg.Attributes as A


type alias Preview =
    { frame : Int, ships : List { kind : ShipKind, facing : Int, x : Int, y : Int }, shots : List { x : Int, y : Int } }


fromArena : Arena -> Preview
fromArena arena =
    let
        cam =
            View.camera arena

        point location =
            { x = 512 + Trig.wrapDelta (location.x - cam.cx) arena.space.width * 1024 // cam.w, y = 480 + Trig.wrapDelta (location.y - cam.cy) arena.space.height * 960 // cam.h }

        ship live =
            Dict.get (Melee.Id.toInt (State.core live).element) arena.elements
                |> Maybe.map
                    (\el ->
                        let
                            at =
                                point el.current.location

                            (Facing facing) =
                                (State.core live).facing
                        in
                        { kind = State.kind live, facing = facing, x = at.x, y = at.y }
                    )

        frame =
            case arena.frame of
                FrameCount n ->
                    n
    in
    { frame = frame, ships = List.filterMap ship [ arena.combatants.bottom, arena.combatants.top ], shots = Dict.values arena.elements |> List.filter (\el -> el.flags.finiteLife && el.mass > 0) |> List.map (.current >> .location >> point) }


view : Maybe Preview -> Html msg
view preview =
    svg [ A.viewBox "0 0 1024 960", A.width "100%", A.height "100%", A.style "background:#030916" ]
        (List.range 1 35
            |> List.map (\n -> circle [ A.cx (String.fromInt (modBy 1024 (n * 139))), A.cy (String.fromInt (modBy 960 (n * 271))), A.r "2", A.fill "#64829c" ] [])
            |> (\stars ->
                    stars
                        ++ (case preview of
                                Nothing ->
                                    []

                                Just scene ->
                                    List.map (\shot -> circle [ A.cx (String.fromInt shot.x), A.cy (String.fromInt shot.y), A.r "4", A.fill "#ffe091" ] []) scene.shots
                                        ++ List.map (\ship -> g [ A.style ("transform:translate(" ++ String.fromInt ship.x ++ "px," ++ String.fromInt ship.y ++ "px);transition:transform 500ms linear") ] [ image [ A.x "-48", A.y "-48", A.width "96", A.height "96", A.xlinkHref (Catalog.sprite ship.kind ship.facing), A.style "image-rendering:pixelated" ] [] ]) scene.ships
                           )
               )
        )
