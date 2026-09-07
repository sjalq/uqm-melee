module Melee.Battle exposing
    ( Arena
    , Fight
    , Match
    , Outcome
    , Round(..)
    )

{-| A Super Melee fight: two live combatants, the display queue, the
lockstep ledger.

The planet is an element (`PlanetBody`), not a side-channel. Asteroids
spawn from it over time (misc.c spawn\_asteroid) and are also elements.
There is no third combatant.

Checksum of a frame is CRC32(RNG seed after a dummy TFB\_SeedRandom(0)
round-trip, then every non-background element in `queue` order).

-}

import Dict exposing (Dict)
import Melee.Element exposing (Element)
import Melee.Fleet exposing (Fleet, Team)
import Melee.Id exposing (ElementId)
import Melee.Input exposing (Controller)
import Melee.Netplay exposing (ChecksumLedger, InputDelay, InputLedger)
import Melee.Rng exposing (Seed)
import Melee.ShipState exposing (Combatant)
import Melee.Units exposing (FrameCount, Side, Sided, WorldExtent, WorldPoint)


{-| The two teams plus which fleet slots are still unused. A used slot
is `EmptySlot`. Winning the match means the opponent's remaining fleet
has no `ShipSlot` left after their last ship dies.
-}
type alias Match =
    { teams : Sided Team
    , remaining : Sided Fleet
    }


{-| Display queue plus the two STARSHIPs.

    frame          C battleFrameCount (24 Hz), starting at 0 on warp-in
    pumpAcc        60 Hz accumulator; see Melee.Rate.advancePump
    seed           battle RNG (Park-Miller). Consumed in a fixed order
                   (asteroids, Pkunk phoenix, Melnorme confusion, cyborg, VUX random, ...)
    space          LOG_SPACE_WIDTH x LOG_SPACE_HEIGHT
    combatants     the two ships currently in the arena
    elements       id -> node. Invariant: keys == queue as a set
    queue          process / CRC order (C disp_q)
    nextElementId  next unused handle; never 0, never reused within a round

-}
type alias Arena =
    { frame : FrameCount
    , previousLocations : Dict Int WorldPoint
    , pumpAcc : Int
    , seed : Seed
    , space : WorldExtent
    , combatants : Sided Combatant
    , elements : Dict Int Element
    , queue : List ElementId
    , nextElementId : Int
    }


{-| One round, including the lockstep buffers. The backend stores this
so a late joiner or the backend itself can replay.
-}
type alias Fight =
    { match : Match
    , arena : Arena
    , controllers : Sided Controller
    , ledger : InputLedger
    , checksums : ChecksumLedger
    , inputDelay : InputDelay
    }


{-| Warp-in is ship\_preprocess's APPEARING path: no turn, no thrust, no
weapon. Fighting is the 24 Hz C loop, pumped at 60 Hz. You cannot fire during warp-in
because this tag is not `Fighting` (MITI).
-}
type Round
    = Warping Fight
    | Fighting Fight


{-| Match over. `Nothing` is a draw (last ships died on the same frame).
-}
type alias Outcome =
    { teams : Sided Team
    , remaining : Sided Fleet
    , winner : Maybe Side
    }
