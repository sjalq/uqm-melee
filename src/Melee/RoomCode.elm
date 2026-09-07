module Melee.RoomCode exposing (generate)

import Char
import Json.Encode as Encode
import SHA256


{-| Derive 40 unpredictable bits from Lamdera's random session/client identifiers.
The serial is domain-separated from those identifiers, never exposed as a code.
-}
generate : String -> String -> Int -> String
generate session client serial =
    Encode.list Encode.string [ "uqmbattle-room-v1", session, client, String.fromInt serial ]
        |> Encode.encode 0
        |> SHA256.fromString
        |> SHA256.toHex
        |> String.left 16
        |> String.toList
        |> pairs
        |> String.fromList


pairs : List Char -> List Char
pairs chars =
    case chars of
        high :: low :: rest ->
            let
                digit c =
                    if Char.isDigit c then
                        Char.toCode c - Char.toCode '0'

                    else
                        Char.toCode c - Char.toCode 'a' + 10

                index =
                    modBy 32 (16 * digit high + digit low)

                letter =
                    String.slice index (index + 1) "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
            in
            (String.uncons letter |> Maybe.map Tuple.first |> Maybe.withDefault '2') :: pairs rest

        _ ->
            []
