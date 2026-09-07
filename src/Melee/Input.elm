module Melee.Input exposing
    ( BattleInput
    , Controller(..)
    , CyborgRating(..)
    , KeyLayout(..)
    , Turn(..)
    , idle
    )

{-| Per-frame input to a ship, and who supplies it.

Source: controls.h (BATTLE\_INPUT\_STATE bits), battle.c ProcessInput,
intel.h (control flags).

-}

import Melee.Units exposing (Side)


{-| battle.c ProcessInput:

        if (InputState & BATTLE_LEFT) ship_input_state |= LEFT;
        else if (InputState & BATTLE_RIGHT) ship_input_state |= RIGHT;

LEFT wins when both keys are held, so "both pressed" is not a state the
simulation can observe. Modelled as a three-way union (MISI).

-}
type Turn
    = NoTurn
    | TurnLeft
    | TurnRight


{-| The only input the melee simulation ever sees for one ship on one
frame. BATTLE\_ESCAPE (flee) exists only in full-game encounters
(battle.c RunAwayAllowed) and BATTLE\_DOWN is menu navigation, so neither
is representable here.

This is also the exact payload exchanged in lockstep netplay
(Packet\_BattleInput carries one BATTLE\_INPUT\_STATE byte).

-}
type alias BattleInput =
    { turn : Turn
    , thrust : Bool
    , weapon : Bool
    , special : Bool
    }


idle : BattleInput
idle =
    { turn = NoTurn
    , thrust = False
    , weapon = False
    , special = False
    }


{-| cyborg.c difficulty. intel.h: STANDARD\_RATING, GOOD\_RATING, AWESOME\_RATING.
The rating changes how far ahead the AI plots intercepts and how often it
re-evaluates, not the ship's abilities.
-}
type CyborgRating
    = StandardCyborg
    | GoodCyborg
    | AwesomeCyborg


{-| Which physical keys a local human uses. UQM supports two keyboard
layouts so that two humans can share one keyboard (hot seat).
-}
type KeyLayout
    = KeyLayoutOne
    | KeyLayoutTwo


{-| Who produces the `BattleInput` for a seat, per frame.

intel.h: HUMAN\_CONTROL, CYBORG\_CONTROL, NETWORK\_CONTROL (PSYTRON is an
unused alias of cyborg). A network seat is a human or cyborg on the other
end; from this client's point of view it is just "inputs arrive over the
wire", which is what determines lockstep behaviour.

-}
type Controller
    = LocalHuman KeyLayout
    | LocalCyborg CyborgRating
    | Remote


{-| Convenience for the common case of the sim needing "the input for
`side` on this frame".
-}
type alias InputFor =
    Side -> BattleInput
