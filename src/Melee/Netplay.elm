module Melee.Netplay exposing
    ( Checksum(..)
    , ChecksumLedger
    , DesyncReport
    , FrameInputs
    , InputDelay(..)
    , InputLedger
    , ReadyState(..)
    , SeatAssignment
    , checksumInterval
    )

{-| Lockstep synchronisation types.

UQM netplay (supermelee/netplay/\*, doc/devel/netplay/protocol) is a
peer-to-peer deterministic lockstep:

  - both peers run the full simulation;
  - each peer sends its own `BattleInput` every frame (PACKET\_BATTLEINPUT);
  - inputs are delayed by `InputDelay` frames through a per-side
    BattleInputBuffer, so frame N consumes the input each side produced
    on frame N - delay;
  - every NETPLAY\_CHECKSUM\_INTERVAL frames each peer CRCs its state
    (RNG seed + display queue) and sends it; a mismatch aborts with
    ResetReason\_syncLoss.

Here the Lamdera backend replaces the peer link. It never simulates by
necessity, but it is the single ordering authority: it receives each
side's input for a frame, stores it in the `InputLedger`, and forwards the
pair. Because the ledger plus the seed plus the two fleets fully determine
the battle, any client (or the backend itself) can replay or resume from it.

Space-pew-pew's split is kept: simulation runs in the frontend at the
battle frame rate; the backend relays and persists.

-}

import Dict exposing (Dict)
import Lamdera exposing (ClientId)
import Melee.Input exposing (BattleInput)
import Melee.Units exposing (Side, Sided)


{-| Frames of latency hiding. UQM negotiates it in NetState\_preBattle
(PACKET\_INPUTDELAY); both sides send a value and the maximum wins.
Invariant: >= 0. With delay d, the ledger for frames 0..d-1 is pre-filled
with `Melee.Input.idle` on both sides.
-}
type InputDelay
    = InputDelay Int


{-| The inputs consumed by one simulation frame. A frame cannot run until
both are present, hence a plain record instead of Maybe per side: the
ledger stores `Sided (Maybe BattleInput)` while pending and a frame is
only handed to the simulation once it has been promoted to `FrameInputs`.
-}
type alias FrameInputs =
    Sided BattleInput


{-| The canonical record of the battle. Key: frame number (starting at 0
for the frame on which a newly selected ship pair enters the arena).

    complete : every frame < nextFrame has both inputs
    pending  : frames >= nextFrame for which only one side has arrived

The two-map shape makes "a completed frame missing an input" unrepresentable.

-}
type alias InputLedger =
    { complete : Dict Int FrameInputs
    , pending : Dict Int (Sided (Maybe BattleInput))
    , nextFrame : Int
    }


{-| CRC32 over the simulation state (checksum.c). Stored as an Int
holding a uint32.
-}
type Checksum
    = Checksum Int


checksumInterval : Int
checksumInterval =
    1


{-| Checksums each side reported for a frame. UQM verifies frame
(N - delay) at frame N. A frame with both sides present and differing
values is a desync.
-}
type alias ChecksumLedger =
    Dict Int (Sided (Maybe Checksum))


type alias DesyncReport =
    { frame : Int
    , reported : Sided Checksum
    }


{-| The "Ready" negotiation from the protocol doc: both sides must say
ready before leaving preBattle / interBattle / endingBattle states.
-}
type ReadyState
    = NeitherReady
    | OnlyReady Side
    | BothReady


{-| Which connected client sits on which side. A client can hold at most
one seat; a seat can be empty while waiting for an opponent (the backend
fills it with a cyborg only if the host asks).
-}
type alias SeatAssignment =
    Sided (Maybe ClientId)
