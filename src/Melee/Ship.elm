module Melee.Ship exposing
    ( Ability
    , Characteristics
    , ShipKind(..)
    , Stock
    , intelRange
    , meleeShipCount
    , mmrnmhrmYWing
    , stock
    )

{-| The 25 Super Melee ships and their stock CHARACTERISTIC\_STUFF / SHIP\_INFO.

Source: supermelee/meleeship.h (`MeleeShip`, NUM\_MELEE\_SHIPS = 25) and
each `ships/<race>/<race>.c` RACE\_DESC. SIS, Sa-Matra, and the Ur-Quan
probe are not melee ships and have no constructor here.

`stock` is the immutable catalog. Live battles copy it into
`Melee.ShipState.CombatantCore.characteristics` and then mutate that
copy (VUX limpets, Thraddash afterburner, Mmrnmhrm transform, Androsynth
blazer). The catalog itself never changes.

-}

import Melee.Units exposing (Wait(..))


{-| Closed set of Super Melee ships. Constructor order matches
`MeleeShip` in meleeship.h so a fleet file / wire tag is stable.
-}
type ShipKind
    = Androsynth
    | Arilou
    | Chenjesu
    | Chmmr
    | Druuge
    | Earthling
    | Ilwrath
    | KohrAh
    | Melnorme
    | Mmrnmhrm
    | Mycon
    | Orz
    | Pkunk
    | Shofixti
    | Slylandro
    | Spathi
    | Supox
    | Syreen
    | Thraddash
    | Umgah
    | UrQuan
    | Utwig
    | Vux
    | Yehat
    | ZoqFotPik


meleeShipCount : Int
meleeShipCount =
    25


{-| INTEL\_STUFF.WeaponRange in world units (24 Hz catalog). Cyborg uses this.
-}
intelRange : ShipKind -> Int
intelRange kind =
    case kind of
        Androsynth ->
            1000

        Arilou ->
            218

        Chenjesu ->
            4000

        Chmmr ->
            200

        Druuge ->
            2400

        Earthling ->
            4000

        Ilwrath ->
            200

        KohrAh ->
            200

        Melnorme ->
            1800

        Mmrnmhrm ->
            200

        Mycon ->
            3200

        Orz ->
            1440

        Pkunk ->
            201

        Shofixti ->
            960

        Slylandro ->
            400

        Spathi ->
            1200

        Supox ->
            600

        Syreen ->
            800

        Thraddash ->
            900

        Umgah ->
            16000

        UrQuan ->
            1600

        Utwig ->
            200

        Vux ->
            200

        Yehat ->
            266

        ZoqFotPik ->
            400


{-| SHIP\_INFO.ship\_flags, as individual booleans so an unused bit cannot
sneak in. PLAYER\_CAPTAIN is full-game only and is not representable.
-}
type alias Ability =
    { seekingWeapon : Bool
    , seekingSpecial : Bool
    , pointDefense : Bool
    , immediateWeapon : Bool
    , crewImmune : Bool
    , firesFore : Bool
    , firesRight : Bool
    , firesAft : Bool
    , firesLeft : Bool
    , shieldDefense : Bool
    , dontChase : Bool
    }


{-| Live CHARACTERISTIC\_STUFF. BYTE waits are `Wait` (0..255).
`energyRegeneration` is signed: Androsynth blazer writes -1 here
(androsyn.c casts BYTE(-1) and ship.c treats regen < 0 as "always apply").
-}
type alias Characteristics =
    { maxThrust : Int
    , thrustIncrement : Int
    , energyRegeneration : Int
    , weaponEnergyCost : Int
    , specialEnergyCost : Int
    , energyWait : Wait
    , turnWait : Wait
    , thrustWait : Wait
    , weaponWait : Wait
    , specialWait : Wait
    , shipMass : Int
    }


{-| Immutable catalog row for one `ShipKind`.

    cost            Super Melee point value (display only; no cap)
    maxCrew         SHIP_INFO.max_crew (Syreen is 42, starts at 12)
    maxEnergy       SHIP_INFO.max_energy (Utwig is 20, starts at 10)
    startingCrew    crew when the ship enters the arena
    startingEnergy  energy when the ship enters the arena

-}
type alias Stock =
    { kind : ShipKind
    , cost : Int
    , maxCrew : Int
    , maxEnergy : Int
    , startingCrew : Int
    , startingEnergy : Int
    , ability : Ability
    , characteristics : Characteristics
    }


none : Ability
none =
    { seekingWeapon = False
    , seekingSpecial = False
    , pointDefense = False
    , immediateWeapon = False
    , crewImmune = False
    , firesFore = False
    , firesRight = False
    , firesAft = False
    , firesLeft = False
    , shieldDefense = False
    , dontChase = False
    }


fore : Ability
fore =
    { none | firesFore = True }


stock : ShipKind -> Stock
stock kind =
    case kind of
        Androsynth ->
            { kind = Androsynth
            , cost = 15
            , maxCrew = 20
            , maxEnergy = 24
            , startingCrew = 20
            , startingEnergy = 24
            , ability = { fore | seekingWeapon = True }
            , characteristics =
                { maxThrust = 24
                , thrustIncrement = 3
                , energyRegeneration = 1
                , weaponEnergyCost = 3
                , specialEnergyCost = 2
                , energyWait = Wait 8
                , turnWait = Wait 4
                , thrustWait = Wait 0
                , weaponWait = Wait 0
                , specialWait = Wait 0
                , shipMass = 6
                }
            }

        Arilou ->
            { kind = Arilou
            , cost = 16
            , maxCrew = 6
            , maxEnergy = 20
            , startingCrew = 6
            , startingEnergy = 20
            , ability = { none | immediateWeapon = True }
            , characteristics =
                { maxThrust = 40
                , thrustIncrement = 40
                , energyRegeneration = 1
                , weaponEnergyCost = 2
                , specialEnergyCost = 3
                , energyWait = Wait 6
                , turnWait = Wait 0
                , thrustWait = Wait 0
                , weaponWait = Wait 1
                , specialWait = Wait 2
                , shipMass = 1
                }
            }

        Chenjesu ->
            { kind = Chenjesu
            , cost = 28
            , maxCrew = 36
            , maxEnergy = 30
            , startingCrew = 36
            , startingEnergy = 30
            , ability =
                { fore | seekingWeapon = True, seekingSpecial = True }
            , characteristics =
                { maxThrust = 27
                , thrustIncrement = 3
                , energyRegeneration = 1
                , weaponEnergyCost = 5
                , specialEnergyCost = 30
                , energyWait = Wait 4
                , turnWait = Wait 6
                , thrustWait = Wait 4
                , weaponWait = Wait 0
                , specialWait = Wait 0
                , shipMass = 10
                }
            }

        Chmmr ->
            { kind = Chmmr
            , cost = 30
            , maxCrew = 42
            , maxEnergy = 42
            , startingCrew = 42
            , startingEnergy = 42
            , ability =
                { fore
                    | immediateWeapon = True
                    , seekingSpecial = True
                    , pointDefense = True
                }
            , characteristics =
                { maxThrust = 35
                , thrustIncrement = 7
                , energyRegeneration = 1
                , weaponEnergyCost = 2
                , specialEnergyCost = 1
                , energyWait = Wait 1
                , turnWait = Wait 3
                , thrustWait = Wait 5
                , weaponWait = Wait 0
                , specialWait = Wait 0
                , shipMass = 10
                }
            }

        Druuge ->
            { kind = Druuge
            , cost = 17
            , maxCrew = 14
            , maxEnergy = 32
            , startingCrew = 14
            , startingEnergy = 32
            , ability = fore
            , characteristics =
                { maxThrust = 20
                , thrustIncrement = 2
                , energyRegeneration = 1
                , weaponEnergyCost = 4
                , specialEnergyCost = 16
                , energyWait = Wait 50
                , turnWait = Wait 4
                , thrustWait = Wait 1
                , weaponWait = Wait 10
                , specialWait = Wait 30
                , shipMass = 5
                }
            }

        Earthling ->
            { kind = Earthling
            , cost = 11
            , maxCrew = 18
            , maxEnergy = 18
            , startingCrew = 18
            , startingEnergy = 18
            , ability =
                { fore | seekingWeapon = True, pointDefense = True }
            , characteristics =
                { maxThrust = 24
                , thrustIncrement = 3
                , energyRegeneration = 1
                , weaponEnergyCost = 9
                , specialEnergyCost = 4
                , energyWait = Wait 8
                , turnWait = Wait 1
                , thrustWait = Wait 4
                , weaponWait = Wait 10
                , specialWait = Wait 9
                , shipMass = 6
                }
            }

        Ilwrath ->
            { kind = Ilwrath
            , cost = 10
            , maxCrew = 22
            , maxEnergy = 16
            , startingCrew = 22
            , startingEnergy = 16
            , ability = fore
            , characteristics =
                { maxThrust = 25
                , thrustIncrement = 5
                , energyRegeneration = 4
                , weaponEnergyCost = 1
                , specialEnergyCost = 3
                , energyWait = Wait 4
                , turnWait = Wait 2
                , thrustWait = Wait 0
                , weaponWait = Wait 0
                , specialWait = Wait 13
                , shipMass = 7
                }
            }

        KohrAh ->
            { kind = KohrAh
            , cost = 30
            , maxCrew = 42
            , maxEnergy = 42
            , startingCrew = 42
            , startingEnergy = 42
            , ability = fore
            , characteristics =
                { maxThrust = 30
                , thrustIncrement = 6
                , energyRegeneration = 1
                , weaponEnergyCost = 6
                , specialEnergyCost = 21
                , energyWait = Wait 4
                , turnWait = Wait 4
                , thrustWait = Wait 6
                , weaponWait = Wait 6
                , specialWait = Wait 9
                , shipMass = 10
                }
            }

        Melnorme ->
            { kind = Melnorme
            , cost = 18
            , maxCrew = 20
            , maxEnergy = 42
            , startingCrew = 20
            , startingEnergy = 42
            , ability = fore
            , characteristics =
                { maxThrust = 36
                , thrustIncrement = 6
                , energyRegeneration = 1
                , weaponEnergyCost = 5
                , specialEnergyCost = 20
                , energyWait = Wait 4
                , turnWait = Wait 4
                , thrustWait = Wait 4
                , weaponWait = Wait 1
                , specialWait = Wait 20
                , shipMass = 7
                }
            }

        Mmrnmhrm ->
            { kind = Mmrnmhrm
            , cost = 19
            , maxCrew = 20
            , maxEnergy = 10
            , startingCrew = 20
            , startingEnergy = 10
            , ability = { fore | immediateWeapon = True }
            , characteristics =
                { maxThrust = 20
                , thrustIncrement = 5
                , energyRegeneration = 2
                , weaponEnergyCost = 1
                , specialEnergyCost = 10
                , energyWait = Wait 6
                , turnWait = Wait 2
                , thrustWait = Wait 1
                , weaponWait = Wait 0
                , specialWait = Wait 0
                , shipMass = 3
                }
            }

        Mycon ->
            { kind = Mycon
            , cost = 21
            , maxCrew = 20
            , maxEnergy = 40
            , startingCrew = 20
            , startingEnergy = 40
            , ability = { fore | seekingWeapon = True }
            , characteristics =
                { maxThrust = 27
                , thrustIncrement = 9
                , energyRegeneration = 1
                , weaponEnergyCost = 20
                , specialEnergyCost = 40
                , energyWait = Wait 4
                , turnWait = Wait 6
                , thrustWait = Wait 6
                , weaponWait = Wait 5
                , specialWait = Wait 0
                , shipMass = 7
                }
            }

        Orz ->
            { kind = Orz
            , cost = 23
            , maxCrew = 16
            , maxEnergy = 20
            , startingCrew = 16
            , startingEnergy = 20
            , ability = { fore | seekingSpecial = True }
            , characteristics =
                { maxThrust = 35
                , thrustIncrement = 5
                , energyRegeneration = 1
                , weaponEnergyCost = 6
                , specialEnergyCost = 0
                , energyWait = Wait 6
                , turnWait = Wait 1
                , thrustWait = Wait 0
                , weaponWait = Wait 4
                , specialWait = Wait 12
                , shipMass = 4
                }
            }

        Pkunk ->
            { kind = Pkunk
            , cost = 20
            , maxCrew = 8
            , maxEnergy = 12
            , startingCrew = 8
            , startingEnergy = 12
            , ability = { fore | firesLeft = True, firesRight = True }
            , characteristics =
                { maxThrust = 64
                , thrustIncrement = 16
                , energyRegeneration = 0
                , weaponEnergyCost = 1
                , specialEnergyCost = 2
                , energyWait = Wait 0
                , turnWait = Wait 0
                , thrustWait = Wait 0
                , weaponWait = Wait 0
                , specialWait = Wait 16
                , shipMass = 1
                }
            }

        Shofixti ->
            { kind = Shofixti
            , cost = 5
            , maxCrew = 6
            , maxEnergy = 4
            , startingCrew = 6
            , startingEnergy = 4
            , ability = fore
            , characteristics =
                { maxThrust = 35
                , thrustIncrement = 5
                , energyRegeneration = 1
                , weaponEnergyCost = 1
                , specialEnergyCost = 0
                , energyWait = Wait 9
                , turnWait = Wait 1
                , thrustWait = Wait 0
                , weaponWait = Wait 3
                , specialWait = Wait 0
                , shipMass = 1
                }
            }

        Slylandro ->
            { kind = Slylandro
            , cost = 17
            , maxCrew = 12
            , maxEnergy = 20
            , startingCrew = 12
            , startingEnergy = 20
            , ability = { none | seekingWeapon = True, crewImmune = True }
            , characteristics =
                { maxThrust = 60
                , thrustIncrement = 60
                , energyRegeneration = 0
                , weaponEnergyCost = 2
                , specialEnergyCost = 0
                , energyWait = Wait 10
                , turnWait = Wait 0
                , thrustWait = Wait 0
                , weaponWait = Wait 17
                , specialWait = Wait 20
                , shipMass = 1
                }
            }

        Spathi ->
            { kind = Spathi
            , cost = 18
            , maxCrew = 30
            , maxEnergy = 10
            , startingCrew = 30
            , startingEnergy = 10
            , ability =
                { fore
                    | firesAft = True
                    , seekingSpecial = True
                    , dontChase = True
                }
            , characteristics =
                { maxThrust = 48
                , thrustIncrement = 12
                , energyRegeneration = 1
                , weaponEnergyCost = 2
                , specialEnergyCost = 3
                , energyWait = Wait 10
                , turnWait = Wait 1
                , thrustWait = Wait 1
                , weaponWait = Wait 0
                , specialWait = Wait 7
                , shipMass = 5
                }
            }

        Supox ->
            { kind = Supox
            , cost = 16
            , maxCrew = 12
            , maxEnergy = 16
            , startingCrew = 12
            , startingEnergy = 16
            , ability = fore
            , characteristics =
                { maxThrust = 40
                , thrustIncrement = 8
                , energyRegeneration = 1
                , weaponEnergyCost = 1
                , specialEnergyCost = 1
                , energyWait = Wait 4
                , turnWait = Wait 1
                , thrustWait = Wait 0
                , weaponWait = Wait 2
                , specialWait = Wait 0
                , shipMass = 4
                }
            }

        Syreen ->
            { kind = Syreen
            , cost = 13
            , maxCrew = 42
            , maxEnergy = 16
            , startingCrew = 12
            , startingEnergy = 16
            , ability = fore
            , characteristics =
                { maxThrust = 36
                , thrustIncrement = 9
                , energyRegeneration = 1
                , weaponEnergyCost = 1
                , specialEnergyCost = 5
                , energyWait = Wait 6
                , turnWait = Wait 1
                , thrustWait = Wait 1
                , weaponWait = Wait 8
                , specialWait = Wait 20
                , shipMass = 2
                }
            }

        Thraddash ->
            { kind = Thraddash
            , cost = 10
            , maxCrew = 8
            , maxEnergy = 24
            , startingCrew = 8
            , startingEnergy = 24
            , ability = fore
            , characteristics =
                { maxThrust = 28
                , thrustIncrement = 7
                , energyRegeneration = 1
                , weaponEnergyCost = 2
                , specialEnergyCost = 1
                , energyWait = Wait 6
                , turnWait = Wait 1
                , thrustWait = Wait 0
                , weaponWait = Wait 12
                , specialWait = Wait 0
                , shipMass = 7
                }
            }

        Umgah ->
            { kind = Umgah
            , cost = 7
            , maxCrew = 10
            , maxEnergy = 30
            , startingCrew = 10
            , startingEnergy = 30
            , ability = { fore | immediateWeapon = True }
            , characteristics =
                { maxThrust = 18
                , thrustIncrement = 6
                , energyRegeneration = 30
                , weaponEnergyCost = 0
                , specialEnergyCost = 1
                , energyWait = Wait 150
                , turnWait = Wait 4
                , thrustWait = Wait 3
                , weaponWait = Wait 0
                , specialWait = Wait 2
                , shipMass = 1
                }
            }

        UrQuan ->
            { kind = UrQuan
            , cost = 30
            , maxCrew = 42
            , maxEnergy = 42
            , startingCrew = 42
            , startingEnergy = 42
            , ability = { fore | seekingSpecial = True }
            , characteristics =
                { maxThrust = 30
                , thrustIncrement = 6
                , energyRegeneration = 1
                , weaponEnergyCost = 6
                , specialEnergyCost = 8
                , energyWait = Wait 4
                , turnWait = Wait 4
                , thrustWait = Wait 6
                , weaponWait = Wait 6
                , specialWait = Wait 9
                , shipMass = 10
                }
            }

        Utwig ->
            { kind = Utwig
            , cost = 22
            , maxCrew = 20
            , maxEnergy = 20
            , startingCrew = 20
            , startingEnergy = 10
            , ability =
                { fore | pointDefense = True, shieldDefense = True }
            , characteristics =
                { maxThrust = 36
                , thrustIncrement = 6
                , energyRegeneration = 0
                , weaponEnergyCost = 0
                , specialEnergyCost = 1
                , energyWait = Wait 255
                , turnWait = Wait 1
                , thrustWait = Wait 6
                , weaponWait = Wait 7
                , specialWait = Wait 12
                , shipMass = 8
                }
            }

        Vux ->
            { kind = Vux
            , cost = 12
            , maxCrew = 20
            , maxEnergy = 40
            , startingCrew = 20
            , startingEnergy = 40
            , ability =
                { fore | seekingSpecial = True, immediateWeapon = True }
            , characteristics =
                { maxThrust = 21
                , thrustIncrement = 7
                , energyRegeneration = 1
                , weaponEnergyCost = 1
                , specialEnergyCost = 2
                , energyWait = Wait 8
                , turnWait = Wait 6
                , thrustWait = Wait 4
                , weaponWait = Wait 0
                , specialWait = Wait 7
                , shipMass = 6
                }
            }

        Yehat ->
            { kind = Yehat
            , cost = 23
            , maxCrew = 20
            , maxEnergy = 10
            , startingCrew = 20
            , startingEnergy = 10
            , ability = { fore | shieldDefense = True }
            , characteristics =
                { maxThrust = 30
                , thrustIncrement = 6
                , energyRegeneration = 2
                , weaponEnergyCost = 1
                , specialEnergyCost = 3
                , energyWait = Wait 6
                , turnWait = Wait 2
                , thrustWait = Wait 2
                , weaponWait = Wait 0
                , specialWait = Wait 2
                , shipMass = 3
                }
            }

        ZoqFotPik ->
            { kind = ZoqFotPik
            , cost = 6
            , maxCrew = 10
            , maxEnergy = 10
            , startingCrew = 10
            , startingEnergy = 10
            , ability = fore
            , characteristics =
                { maxThrust = 40
                , thrustIncrement = 10
                , energyRegeneration = 1
                , weaponEnergyCost = 1
                , specialEnergyCost = 7
                , energyWait = Wait 4
                , turnWait = Wait 1
                , thrustWait = Wait 0
                , weaponWait = Wait 0
                , specialWait = Wait 6
                , shipMass = 5
                }
            }


{-| Y-wing CHARACTERISTIC\_STUFF swapped in on Mmrnmhrm transform
(mmrnmhrm.c YWING\_\*). X-wing values are `stock Mmrnmhrm`.
-}
mmrnmhrmYWing : Characteristics
mmrnmhrmYWing =
    { maxThrust = 50
    , thrustIncrement = 10
    , energyRegeneration = 1
    , weaponEnergyCost = 1
    , specialEnergyCost = 10
    , energyWait = Wait 6
    , turnWait = Wait 14
    , thrustWait = Wait 0
    , weaponWait = Wait 20
    , specialWait = Wait 0
    , shipMass = 3
    }
