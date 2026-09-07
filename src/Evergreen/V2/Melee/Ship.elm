module Evergreen.V2.Melee.Ship exposing (..)

import Evergreen.V2.Melee.Units


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
    , energyWait : Evergreen.V2.Melee.Units.Wait
    , turnWait : Evergreen.V2.Melee.Units.Wait
    , thrustWait : Evergreen.V2.Melee.Units.Wait
    , weaponWait : Evergreen.V2.Melee.Units.Wait
    , specialWait : Evergreen.V2.Melee.Units.Wait
    , shipMass : Int
    }
