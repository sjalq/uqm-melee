module Melee.Space exposing (view)

import Html exposing (Html)
import Html.Attributes as Attr
import Math.Vector2 exposing (Vec2, vec2)
import WebGL exposing (Mesh, Shader)


type alias Vertex =
    { position : Vec2 }


type alias Uniforms =
    { time : Float }


view : Float -> Html msg
view time =
    WebGL.toHtml
        [ Attr.width 256
        , Attr.height 240
        , Attr.style "position" "absolute"
        , Attr.style "inset" "0"
        , Attr.style "width" "100%"
        , Attr.style "height" "100%"
        , Attr.style "pointer-events" "none"
        , Attr.style "image-rendering" "pixelated"
        , Attr.attribute "aria-hidden" "true"
        ]
        [ WebGL.entity vertex fragment mesh { time = time } ]


mesh : Mesh Vertex
mesh =
    let
        v x y =
            { position = vec2 x y }
    in
    WebGL.triangles [ ( v -1 -1, v 1 -1, v 1 1 ), ( v -1 -1, v 1 1, v -1 1 ) ]


vertex : Shader Vertex Uniforms { uv : Vec2 }
vertex =
    [glsl|
        attribute vec2 position;
        varying vec2 uv;
        void main() { uv = position * 0.5 + 0.5; gl_Position = vec4(position, 0.0, 1.0); }
    |]


fragment : Shader {} Uniforms { uv : Vec2 }
fragment =
    [glsl|
        precision highp float;
        uniform float time;
        varying vec2 uv;
        float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 437.585453); }
        void main() {
            vec2 cell = floor(uv * vec2(256.,240.));
            float seed = hash(cell);
            float star = step(0.99965, seed);
            vec3 color = mix(vec3(0.5,0.5,0.5), vec3(0.8,0.12,0.05),hash(cell+17.));
            gl_FragColor = vec4(star * color, 1.0);
        }
    |]
