module Mario.Dashboard.Format exposing
    ( awaiting
    , count
    , decimal
    , duration
    , fraction
    , percent
    , percent1
    , ratio
    , shortId
    , signedWeight
    , timeOfDay
    )

{-| Presentation-only number and string formatting.

The single rule that matters: a measurement that does not exist is never
rendered as a number. Callers hold `Maybe Float`, and the view chooses
`awaiting` rather than substituting zero.

-}


{-| The one phrase used everywhere a measurement has not been taken yet.
Kept in one place so "awaiting evidence" can never drift into "0%".
-}
awaiting : String
awaiting =
    "Awaiting evidence"


{-| Round half away from zero at a given number of decimal places, then
render without scientific notation or a trailing ".".
-}
decimal : Int -> Float -> String
decimal places value =
    let
        safePlaces =
            max 0 (min 6 places)

        scaleInt =
            10 ^ safePlaces

        magnitude =
            if isNaN value || isInfinite value then
                0

            else
                abs value

        -- Scale first, round once, then split with integer arithmetic.
        -- Doing the split in floating point can produce 0.9999... for a
        -- value that already rounded up, which drops a whole unit.
        scaled =
            round (magnitude * toFloat scaleInt)

        whole =
            scaled // scaleInt

        frac =
            modBy scaleInt scaled

        digits =
            String.padLeft safePlaces '0' (String.fromInt frac)

        sign =
            if value < 0 && scaled /= 0 then
                "-"

            else
                ""
    in
    if safePlaces == 0 then
        sign ++ String.fromInt whole

    else
        sign ++ String.fromInt whole ++ "." ++ digits


{-| A 0..1 proportion as a percentage with one decimal place.
-}
percent1 : Float -> String
percent1 value =
    decimal 1 (value * 100) ++ "%"


{-| A 0..1 proportion as a whole percentage.
-}
percent : Float -> String
percent value =
    decimal 0 (value * 100) ++ "%"


{-| "17 / 24" style evidence denominators. Always shows the denominator,
because a rate without its sample size hides how weak the evidence is.
-}
fraction : Int -> Int -> String
fraction numerator denominator =
    count numerator ++ " / " ++ count denominator


{-| Wins over games where zero games is stated rather than divided.
-}
ratio : Int -> Int -> String
ratio numerator denominator =
    if denominator <= 0 then
        awaiting

    else
        percent1 (toFloat numerator / toFloat denominator)


{-| Thousands separators, so six-digit episode counts stay readable.
-}
count : Int -> String
count value =
    let
        digits =
            String.fromInt (abs value)

        grouped =
            digits
                |> String.reverse
                |> String.toList
                |> chunk3
                |> List.map String.fromList
                |> String.join ","
                |> String.reverse

        sign =
            if value < 0 then
                "-"

            else
                ""
    in
    sign ++ grouped


chunk3 : List Char -> List (List Char)
chunk3 chars =
    case chars of
        [] ->
            []

        _ ->
            List.take 3 chars :: chunk3 (List.drop 3 chars)


{-| Elapsed seconds as a compact wall-clock span.
-}
duration : Float -> String
duration seconds =
    let
        total =
            max 0 (floor seconds)

        days =
            total // 86400

        hours =
            modBy 24 (total // 3600)

        minutes =
            modBy 60 (total // 60)

        secs =
            modBy 60 total

        pad n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    if days > 0 then
        String.fromInt days ++ "d " ++ pad hours ++ ":" ++ pad minutes ++ ":" ++ pad secs

    else if hours > 0 then
        String.fromInt hours ++ ":" ++ pad minutes ++ ":" ++ pad secs

    else
        pad minutes ++ ":" ++ pad secs


{-| Pull the clock portion out of an ISO 8601 instant for dense rows.
Falls back to the raw string rather than inventing a value.
-}
timeOfDay : String -> String
timeOfDay iso =
    case String.split "T" iso of
        [ _, rest ] ->
            rest
                |> String.replace "Z" ""
                |> String.split "."
                |> List.head
                |> Maybe.withDefault rest

        _ ->
            iso


{-| Long champion identifiers are truncated in the middle so both the
prefix and the discriminating tail stay visible.
-}
shortId : String -> String
shortId raw =
    if String.length raw <= 20 then
        raw

    else
        String.left 10 raw ++ "\u{2026}" ++ String.right 6 raw


{-| Connection weights always carry an explicit sign.
-}
signedWeight : Float -> String
signedWeight w =
    if w >= 0 then
        "+" ++ decimal 3 w

    else
        decimal 3 w
