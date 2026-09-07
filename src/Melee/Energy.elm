module Melee.Energy exposing (deltaCrew, deltaEnergy)

{-| status.c DeltaEnergy / DeltaCrew.
-}

import Melee.Element exposing (Element, Life(..))
import Melee.ShipState exposing (CombatantCore)
import Melee.Units exposing (Wait(..))


deltaEnergy : Int -> Element -> CombatantCore -> ( Bool, Element, CombatantCore )
deltaEnergy energyDelta element core =
    if energyDelta < 0 && -energyDelta > core.energy then
        ( False
        , element
        , { core
            | flags =
                let
                    f =
                        core.flags
                in
                { f | lowOnEnergy = True }
          }
        )

    else
        let
            applied =
                if energyDelta >= 0 then
                    min (core.energy + energyDelta) core.maxEnergy - core.energy

                else
                    energyDelta

            flags =
                core.flags
        in
        ( True
        , element
        , { core
            | energy = core.energy + applied
            , energyWait = core.characteristics.energyWait
            , flags = { flags | lowOnEnergy = False }
          }
        )


deltaCrew : Int -> Element -> CombatantCore -> ( Bool, Element, CombatantCore )
deltaCrew crewDelta element core =
    if crewDelta > 0 then
        let
            next =
                min (element.points + crewDelta) core.maxCrew
        in
        ( True, { element | points = next }, core )

    else if crewDelta < 0 then
        if element.points > -crewDelta then
            ( True, { element | points = element.points + crewDelta }, core )

        else
            ( False
            , { element
                | points = 0
                , life = Finite 0
                , flags =
                    let
                        f =
                            element.flags
                    in
                    { f | nonsolid = True }
              }
            , core
            )

    else
        ( True, element, core )
