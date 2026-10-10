module Melee.Location exposing (..)

import Dict
import Melee.Input exposing (CyborgRating(..))
import Melee.Local as Game
import Melee.Seat as Seat exposing (Seat(..))
import Melee.Units exposing (Sided)
import Url exposing (Url)


type alias Location =
    { room : Maybe String, watching : Bool, local : Bool, watchingList : Bool, page : Int, roster : Int, seats : Sided Seat }


lobby : Location
lobby =
    { room = Nothing, watching = False, local = False, watchingList = False, page = 0, roster = 0, seats = defaultSeats }


defaultSeats : Sided Seat
defaultSeats =
    { bottom = Human, top = Cyborg GoodCyborg }


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
    , seats = seatsFrom (Dict.get "bottom" params) (Dict.get "top" params) (Dict.get "mode" params) (Dict.get "ai" params)
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
            , if location.local && location.seats.bottom /= defaultSeats.bottom then
                Just ("bottom=" ++ Seat.toParam location.seats.bottom)

              else
                Nothing
            , if location.local && location.seats.top /= defaultSeats.top then
                Just ("top=" ++ Seat.toParam location.seats.top)

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
        { game | mode = Seat.mode location.seats }

    else
        game


{-| `bottom=` and `top=` name each seat. Links from before per-seat control
used `mode=` (which sides are human) and one shared `ai=` rating; those still
open the same game.
-}
seatsFrom : Maybe String -> Maybe String -> Maybe String -> Maybe String -> Sided Seat
seatsFrom bottom top legacyMode legacyRating =
    let
        rating =
            case legacyRating of
                Just "standard" ->
                    StandardCyborg

                Just "awesome" ->
                    AwesomeCyborg

                _ ->
                    GoodCyborg

        computer =
            Cyborg rating

        legacy =
            case legacyMode of
                Just "versus" ->
                    { bottom = Human, top = Human }

                Just "demo" ->
                    { bottom = computer, top = computer }

                Just "reverse" ->
                    { bottom = computer, top = Human }

                _ ->
                    { bottom = Human, top = computer }

        pick param fallback =
            param |> Maybe.andThen Seat.fromParam |> Maybe.withDefault fallback
    in
    { bottom = pick bottom legacy.bottom, top = pick top legacy.top }
