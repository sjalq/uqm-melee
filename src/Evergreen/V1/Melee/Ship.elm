module Evergreen.V1.Melee.Ship exposing (..)

import Evergreen.V1.Melee.Units


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


type alias Characteristics =
    { maxThrust : Int
    , thrustIncrement : Int
    , energyRegeneration : Int
    , weaponEnergyCost : Int
    , specialEnergyCost : Int
    , energyWait : Evergreen.V1.Melee.Units.Wait
    , turnWait : Evergreen.V1.Melee.Units.Wait
    , thrustWait : Evergreen.V1.Melee.Units.Wait
    , weaponWait : Evergreen.V1.Melee.Units.Wait
    , specialWait : Evergreen.V1.Melee.Units.Wait
    , shipMass : Int
    }
