module Melee.Location exposing (..)

import Dict
import Melee.Input exposing (CyborgRating(..))
import Melee.Local as Game
import Url exposing (Url)


type alias Location =
    { room : Maybe String, watching : Bool, local : Bool, watchingList : Bool, page : Int, roster : Int, mode : Game.Mode, difficulty : CyborgRating }


lobby : Location
lobby =
    { room = Nothing, watching = False, local = False, watchingList = False, page = 0, roster = 0, mode = Game.Solo, difficulty = GoodCyborg }


fromUrl : Url -> Location
fromUrl url =
    let
        params =
            url.query
                |> Maybe.withDefault ""
                |> String.split "&"
                |> List.filterMap
                    (\part ->
                        case String.split "=" part of
                            [ key, value ] ->
                                Just ( key, Url.percentDecode value |> Maybe.withDefault value )

                            _ ->
                                Nothing
                    )
                |> Dict.fromList

        flag key =
            Dict.get key params == Just "1"

        number key =
            Dict.get key params |> Maybe.andThen String.toInt |> Maybe.withDefault 0 |> max 0
    in
    { room =
        Dict.get "room" params
            |> Maybe.map (String.trim >> String.toUpper)
            |> Maybe.andThen
                (\s ->
                    if String.isEmpty s then
                        Nothing

                    else
                        Just s
                )
    , watching = flag "watch"
    , local = flag "local"
    , watchingList = flag "live"
    , page = number "page"
    , mode =
        case Dict.get "mode" params of
            Just "versus" ->
                Game.Versus

            Just "demo" ->
                Game.Demo

            Just "reverse" ->
                Game.ReverseSolo

            _ ->
                Game.Solo
    , difficulty =
        case Dict.get "ai" params of
            Just "standard" ->
                StandardCyborg

            Just "awesome" ->
                AwesomeCyborg

            _ ->
                GoodCyborg
    , roster = number "roster"
    }


toUrl : Location -> String
toUrl location =
    let
        params =
            [ Maybe.map (\room -> "room=" ++ Url.percentEncode room) location.room
            , if location.watching then
                Just "watch=1"

              else
                Nothing
            , if location.local then
                Just "local=1"

              else
                Nothing
            , if location.local then
                case location.mode of
                    Game.Solo ->
                        Nothing

                    Game.Versus ->
                        Just "mode=versus"

                    Game.Demo ->
                        Just "mode=demo"

                    Game.ReverseSolo ->
                        Just "mode=reverse"

              else
                Nothing
            , if location.local then
                case location.difficulty of
                    GoodCyborg ->
                        Nothing

                    StandardCyborg ->
                        Just "ai=standard"

                    AwesomeCyborg ->
                        Just "ai=awesome"

              else
                Nothing
            , if location.watchingList then
                Just "live=1"

              else
                Nothing
            , if location.page > 0 then
                Just ("page=" ++ String.fromInt location.page)

              else
                Nothing
            , if location.roster > 0 then
                Just ("roster=" ++ String.fromInt location.roster)

              else
                Nothing
            ]
                |> List.filterMap identity
    in
    "/melee"
        ++ (if List.isEmpty params then
                ""

            else
                "?" ++ String.join "&" params
           )


configure : Location -> Game.Model -> Game.Model
configure location game =
    if location.local then
        { game | mode = location.mode, difficulty = location.difficulty }

    else
        game
