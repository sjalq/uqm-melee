module Property.WeaponPredictionTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Cyborg as Cyborg
import Melee.Id exposing (toInt)
import Melee.Init as Init
import Melee.Input exposing (CyborgRating(..))
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (ShipKind(..))
import Melee.ShipState as State
import Melee.Trig as Trig
import Melee.Units exposing (Facing(..), Side(..), Wait(..))
import Test exposing (..)


suite =
    fuzz2 (Fuzz.intRange 0 15) (Fuzz.oneOfValues [ 4, 12 ]) "Pkunk recognizes both side guns without needing to turn toward the target" <|
        \facing offset ->
            let
                original =
                    Init.arena Pkunk Umgah (Seed 1)

                core =
                    State.core original.combatants.bottom

                enemy =
                    State.core original.combatants.top

                origin =
                    { x = 3200, y = 3200 }

                target =
                    { x = origin.x + Trig.cosine ((facing + offset) * 4) 250, y = origin.y + Trig.sine ((facing + offset) * 4) 250 }

                place id el =
                    let
                        at =
                            if id == toInt core.element then
                                origin

                            else
                                target
                    in
                    { el | current = { location = at, frameIndex = facing }, next = { location = at, frameIndex = facing }, turnWait = Wait 1, thrustWait = Wait 1 }

                arena =
                    { original | combatants = { bottom = State.setCore { core | facing = Facing facing } original.combatants.bottom, top = original.combatants.top }, elements = Dict.filter (\id _ -> id == toInt core.element || id == toInt enemy.element) original.elements |> Dict.map place }
            in
            Cyborg.think AwesomeCyborg Bottom arena arena.seed |> Tuple.first |> .weapon |> Expect.equal True
