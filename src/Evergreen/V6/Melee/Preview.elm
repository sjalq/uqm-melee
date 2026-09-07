module Evergreen.V6.Melee.Preview exposing (..)

import Evergreen.V6.Melee.Local
import Evergreen.V6.Melee.Stream


type Preview
    = Snapshot Evergreen.V6.Melee.Local.Model
    | Delta Evergreen.V6.Melee.Stream.Delta
