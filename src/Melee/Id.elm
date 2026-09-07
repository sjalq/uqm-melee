module Melee.Id exposing
    ( ElementId(..)
    , RoomId(..)
    , toInt
    )

{-| Stable handles. UQM uses HELEMENT / HSTARSHIP pool links; we use
monotonic ints so a target, parent, or phoenix can be named after the
display-queue node it points at.

`ElementId` 0 is never allocated (C uses 0 as the null HLINK).

-}


{-| Identity of one node in the display queue. Allocated from
`Melee.Battle.Arena.nextElementId`.
-}
type ElementId
    = ElementId Int


toInt : ElementId -> Int
toInt (ElementId n) =
    n


{-| A Super Melee room on the Lamdera backend.
-}
type RoomId
    = RoomId String
