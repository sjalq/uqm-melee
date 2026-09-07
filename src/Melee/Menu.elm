module Melee.Menu exposing (Event(..), Target, decode, play, respond, stop)

import Json.Decode as D
import Json.Encode as E


type alias Target =
    { id : String, label : String, x : Float, y : Float }


target : D.Decoder Target
target =
    D.map4 Target (D.field "id" D.string) (D.field "label" D.string) (D.field "x" D.float) (D.field "y" D.float)


command : String -> String -> E.Value
command op id =
    E.object [ ( "op", E.string op ), ( "id", E.string id ) ]


play : String -> String -> Float -> E.Value
play channel src volume =
    E.object [ ( "op", E.string "play" ), ( "channel", E.string channel ), ( "src", E.string src ), ( "volume", E.float volume ) ]


stop : String -> E.Value
stop channel =
    E.object [ ( "op", E.string "stop" ), ( "channel", E.string channel ) ]


isBack : String -> Bool
isBack label =
    List.any (\prefix -> String.startsWith prefix label) [ "Back", "Leave", "Return", "Fleet hangar", "Online arena" ]


type Event
    = Click String
    | Key String String Bool (List Target)
    | Ignored


decode : E.Value -> Event
decode value =
    D.decodeValue
        (D.field "event" D.string
            |> D.andThen
                (\event ->
                    case event of
                        "click" ->
                            D.map Click (D.field "label" D.string)

                        "key" ->
                            D.map4 Key (D.field "key" D.string) (D.field "active" D.string) (D.field "editing" D.bool) (D.field "nodes" (D.list target))

                        _ ->
                            D.succeed Ignored
                )
        )
        value
        |> Result.withDefault Ignored


respond : Bool -> Event -> List E.Value
respond sound event =
    let
        cue index =
            if sound then
                [ play "menu" ("/sounds/menu-" ++ String.fromInt index ++ ".wav") 0.3 ]

            else
                []
    in
    case event of
        Click label ->
            cue
                (if isBack label then
                    4

                 else
                    2
                )

        Key key activeId editing nodes ->
            let
                active =
                    List.filter (\node -> node.id == activeId) nodes |> List.head

                dx =
                    if key == "ArrowRight" then
                        1

                    else if key == "ArrowLeft" then
                        -1

                    else
                        0

                dy =
                    if key == "ArrowDown" then
                        1

                    else if key == "ArrowUp" then
                        -1

                    else
                        0

                choose current =
                    let
                        candidate node best =
                            let
                                vx =
                                    node.x - current.x

                                vy =
                                    node.y - current.y

                                along =
                                    vx * dx + vy * dy

                                score =
                                    along + abs (vx * dy - vy * dx) * 4
                            in
                            if along > 2 && node.id /= current.id && (best |> Maybe.map (\( previousScore, _ ) -> score < previousScore) |> Maybe.withDefault True) then
                                Just ( score, node )

                            else
                                best

                        fallback =
                            if dx + dy > 0 then
                                List.head nodes

                            else
                                List.reverse nodes |> List.head
                    in
                    List.foldl candidate Nothing nodes |> Maybe.map (Tuple.second >> Just) |> Maybe.withDefault fallback

                selected =
                    active |> Maybe.map choose |> Maybe.withDefault (List.head nodes)
            in
            if key == "Escape" then
                if editing then
                    [ command "blur" "" ]

                else
                    List.filter (\node -> isBack node.label) nodes |> List.head |> Maybe.map (\node -> [ command "activate" node.id ]) |> Maybe.withDefault []

            else
                selected |> Maybe.map (\node -> command "focus" node.id :: cue 1) |> Maybe.withDefault []

        _ ->
            []
