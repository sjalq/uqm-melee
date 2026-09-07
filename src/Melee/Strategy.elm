module Melee.Strategy exposing (Context, Pilots, Roster, Strategy, controls, original, originalPilots, originalRoster, override, run)

{-| Strategies choose controls; the game engine retains authority over physics,
damage, resources and round transitions. Functions are passed into the loop,
never stored in a Lamdera model or sent over the wire.

Override one ship with `override Pkunk myStrategy originalRoster`, then pass
that roster to `Local.advanceWith` or the long-game simulator. Keep the same
seed and opposing roster when comparing candidates.

-}

import Melee.Battle exposing (Arena)
import Melee.Cyborg as Cyborg
import Melee.Input exposing (BattleInput, CyborgRating)
import Melee.Rng exposing (Seed)
import Melee.Ship exposing (ShipKind)
import Melee.ShipState as State
import Melee.Units exposing (Side(..), Sided)


type alias Context =
    { rating : CyborgRating, side : Side, arena : Arena, seed : Seed }


type Strategy
    = Original
    | Controls (Context -> ( BattleInput, Seed ))


type alias Roster =
    ShipKind -> Strategy


type alias Pilots =
    Sided Roster


original : Strategy
original =
    Original


controls : (Context -> ( BattleInput, Seed )) -> Strategy
controls =
    Controls


originalRoster : Roster
originalRoster _ =
    original


originalPilots : Pilots
originalPilots =
    { bottom = originalRoster, top = originalRoster }


override : ShipKind -> Strategy -> Roster -> Roster
override kind strategy fallback selected =
    if selected == kind then
        strategy

    else
        fallback selected


run : Roster -> CyborgRating -> Side -> Arena -> ( BattleInput, Arena )
run roster rating side arena =
    let
        ship =
            if side == Bottom then
                arena.combatants.bottom

            else
                arena.combatants.top
    in
    case roster (State.kind ship) of
        Original ->
            Cyborg.pilot rating side arena

        Controls decide ->
            let
                ( input, seed ) =
                    decide { rating = rating, side = side, arena = arena, seed = arena.seed }
            in
            ( input, { arena | seed = seed } )
