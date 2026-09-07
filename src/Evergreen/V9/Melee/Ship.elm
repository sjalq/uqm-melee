module Evergreen.V9.Melee.Ship exposing (..)

import Evergreen.V9.Melee.Units


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
    , energyWait : Evergreen.V9.Melee.Units.Wait
    , turnWait : Evergreen.V9.Melee.Units.Wait
    , thrustWait : Evergreen.V9.Melee.Units.Wait
    , weaponWait : Evergreen.V9.Melee.Units.Wait
    , specialWait : Evergreen.V9.Melee.Units.Wait
    , shipMass : Int
    }
