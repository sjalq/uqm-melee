module Strategies.DirectPursuit exposing (strategy)

{-| A deliberately simple experimental strategy. It is never selected by the
live game. Use it as a template and compare against the original on fixed seeds.
-}

import Dict
import Melee.Id exposing (toInt)
import Melee.Input exposing (Turn(..))
import Melee.ShipState as State
import Melee.Strategy as Strategy
import Melee.Trig as Trig
import Melee.Units exposing (Facing(..), Side(..))


strategy : Strategy.Strategy
strategy =
    Strategy.controls <|
        \context ->
            let
                arena =
                    context.arena

                ( own, enemy ) =
                    if context.side == Bottom then
                        ( arena.combatants.bottom, arena.combatants.top )

                    else
                        ( arena.combatants.top, arena.combatants.bottom )

                core =
                    State.core own

                (Facing facing) =
                    core.facing

                target =
                    Maybe.map2 (\self other -> Trig.arctan (Trig.wrapDelta (other.current.location.x - self.current.location.x) arena.space.width) (Trig.wrapDelta (other.current.location.y - self.current.location.y) arena.space.height)) (Dict.get (toInt core.element) arena.elements) (Dict.get (toInt (State.core enemy).element) arena.elements)

                desired =
                    target |> Maybe.map (\angle -> modBy 16 ((angle + 2) // 4)) |> Maybe.withDefault facing

                delta =
                    modBy 16 (desired - facing)
            in
            ( { turn =
                    if delta == 0 then
                        NoTurn

                    else if delta <= 8 then
                        TurnRight

                    else
                        TurnLeft
              , thrust = delta <= 2 || delta >= 14
              , weapon = True
              , special = False
              }
            , context.seed
            )
