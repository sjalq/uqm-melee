module Melee.Pixel exposing (text)

import Dict
import Svg exposing (Svg)
import Svg.Attributes as A


text : Float -> Float -> Bool -> String -> Svg msg
text x y centered label =
    let
        glyph char =
            Dict.get (Char.toCode char) characters |> Maybe.withDefault ( "00020.png", 3, 6 )

        width =
            String.toList label |> List.map (glyph >> (\( _, w, _ ) -> toFloat w)) |> List.sum

        start =
            if centered then
                x - width / 2

            else
                x

        render char ( offset, images ) =
            let
                ( file, w, h ) =
                    glyph char
            in
            ( offset + toFloat w, images ++ [ Svg.image [ A.x (String.fromFloat offset), A.y (String.fromFloat y), A.width (String.fromInt w), A.height (String.fromInt h), A.xlinkHref ("/classic/font/" ++ file), A.style "image-rendering:pixelated" ] [] ] )
    in
    Svg.g [] (String.toList label |> List.foldl render ( start, [] ) |> Tuple.second)


characters : Dict.Dict Int ( String, Int, Int )
characters =
    Dict.fromList
        [ ( 82, ( "00052.png", 4, 8 ) )
        , ( 70, ( "00046.png", 4, 8 ) )
        , ( 93, ( "0005d.png", 2, 8 ) )
        , ( 74, ( "0004a.png", 4, 8 ) )
        , ( 94, ( "0005e.png", 3, 8 ) )
        , ( 71, ( "00047.png", 4, 8 ) )
        , ( 83, ( "00053.png", 4, 8 ) )
        , ( 69, ( "00045.png", 4, 8 ) )
        , ( 81, ( "00051.png", 4, 8 ) )
        , ( 76, ( "0004c.png", 4, 8 ) )
        , ( 121, ( "00079.png", 4, 8 ) )
        , ( 95, ( "0005f.png", 3, 8 ) )
        , ( 120, ( "00078.png", 4, 8 ) )
        , ( 75, ( "0004b.png", 4, 8 ) )
        , ( 80, ( "00050.png", 4, 8 ) )
        , ( 68, ( "00044.png", 4, 8 ) )
        , ( 79, ( "0004f.png", 4, 8 ) )
        , ( 104, ( "00068.png", 4, 8 ) )
        , ( 91, ( "0005b.png", 2, 8 ) )
        , ( 64, ( "00040.png", 4, 8 ) )
        , ( 84, ( "00054.png", 5, 8 ) )
        , ( 85, ( "00055.png", 4, 8 ) )
        , ( 65, ( "00041.png", 4, 8 ) )
        , ( 92, ( "0005c.png", 3, 8 ) )
        , ( 105, ( "00069.png", 1, 8 ) )
        , ( 90, ( "0005a.png", 4, 8 ) )
        , ( 78, ( "0004e.png", 4, 8 ) )
        , ( 87, ( "00057.png", 5, 8 ) )
        , ( 67, ( "00043.png", 4, 8 ) )
        , ( 66, ( "00042.png", 4, 8 ) )
        , ( 86, ( "00056.png", 5, 8 ) )
        , ( 77, ( "0004d.png", 5, 8 ) )
        , ( 49, ( "00031.png", 4, 8 ) )
        , ( 37, ( "00025.png", 3, 8 ) )
        , ( 44, ( "0002c.png", 2, 8 ) )
        , ( 43, ( "0002b.png", 3, 8 ) )
        , ( 63, ( "0003f.png", 4, 8 ) )
        , ( 36, ( "00024.png", 5, 8 ) )
        , ( 48, ( "00030.png", 4, 8 ) )
        , ( 38, ( "00026.png", 4, 8 ) )
        , ( 50, ( "00032.png", 4, 8 ) )
        , ( 61, ( "0003d.png", 3, 8 ) )
        , ( 62, ( "0003e.png", 3, 8 ) )
        , ( 42, ( "0002a.png", 3, 8 ) )
        , ( 51, ( "00033.png", 4, 8 ) )
        , ( 39, ( "00027.png", 2, 8 ) )
        , ( 46, ( "0002e.png", 1, 8 ) )
        , ( 58, ( "0003a.png", 1, 8 ) )
        , ( 35, ( "00023.png", 5, 8 ) )
        , ( 55, ( "00037.png", 4, 8 ) )
        , ( 54, ( "00036.png", 4, 8 ) )
        , ( 34, ( "00022.png", 3, 8 ) )
        , ( 45, ( "0002d.png", 2, 8 ) )
        , ( 59, ( "0003b.png", 2, 8 ) )
        , ( 47, ( "0002f.png", 5, 8 ) )
        , ( 52, ( "00034.png", 4, 8 ) )
        , ( 32, ( "00020.png", 3, 8 ) )
        , ( 33, ( "00021.png", 1, 8 ) )
        , ( 53, ( "00035.png", 4, 8 ) )
        , ( 60, ( "0003c.png", 3, 8 ) )
        , ( 56, ( "00038.png", 4, 8 ) )
        , ( 57, ( "00039.png", 4, 8 ) )
        , ( 41, ( "00029.png", 2, 8 ) )
        , ( 40, ( "00028.png", 2, 8 ) )
        , ( 115, ( "00073.png", 4, 8 ) )
        , ( 103, ( "00067.png", 4, 8 ) )
        , ( 126, ( "0007e.png", 4, 8 ) )
        , ( 106, ( "0006a.png", 3, 8 ) )
        , ( 125, ( "0007d.png", 3, 8 ) )
        , ( 102, ( "00066.png", 4, 8 ) )
        , ( 114, ( "00072.png", 4, 8 ) )
        , ( 100, ( "00064.png", 4, 8 ) )
        , ( 112, ( "00070.png", 4, 8 ) )
        , ( 107, ( "0006b.png", 4, 8 ) )
        , ( 88, ( "00058.png", 5, 8 ) )
        , ( 89, ( "00059.png", 5, 8 ) )
        , ( 108, ( "0006c.png", 1, 8 ) )
        , ( 113, ( "00071.png", 4, 8 ) )
        , ( 101, ( "00065.png", 4, 8 ) )
        , ( 73, ( "00049.png", 3, 8 ) )
        , ( 124, ( "0007c.png", 1, 8 ) )
        , ( 97, ( "00061.png", 4, 8 ) )
        , ( 117, ( "00075.png", 4, 8 ) )
        , ( 116, ( "00074.png", 3, 8 ) )
        , ( 96, ( "00060.png", 2, 8 ) )
        , ( 123, ( "0007b.png", 3, 8 ) )
        , ( 72, ( "00048.png", 4, 8 ) )
        , ( 111, ( "0006f.png", 4, 8 ) )
        , ( 109, ( "0006d.png", 5, 8 ) )
        , ( 118, ( "00076.png", 4, 8 ) )
        , ( 98, ( "00062.png", 4, 8 ) )
        , ( 99, ( "00063.png", 4, 8 ) )
        , ( 119, ( "00077.png", 5, 8 ) )
        , ( 110, ( "0006e.png", 4, 8 ) )
        , ( 122, ( "0007a.png", 4, 8 ) )
        ]
