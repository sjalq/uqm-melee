module Melee.Rate exposing
    ( advancePump
    , cBattleFramesPerSecond
    , displayHz
    )

{-| Physics is one UQM battle frame (24 Hz). That is the game speed.

The frontend clock is 60 Hz. Each display tick adds 24 to an accumulator
and spends 60 to run one C frame:

    60 display ticks * 24 / 60 = 24 C frames per second

Same real-time speed as SC2 melee. No catalog scaling. `tick` is a C
frame; `pump` is the 60 Hz wrapper.

-}


cBattleFramesPerSecond : Int
cBattleFramesPerSecond =
    24


displayHz : Int
displayHz =
    60


{-| One 60 Hz display tick. Returns (cFramesToRun, newAccumulator).
-}
advancePump : Int -> ( Int, Int )
advancePump acc =
    drain (acc + cBattleFramesPerSecond) 0


drain : Int -> Int -> ( Int, Int )
drain acc n =
    if acc >= displayHz then
        drain (acc - displayHz) (n + 1)

    else
        ( n, acc )
