module Evergreen.V5.Melee.Preview exposing (..)

import Evergreen.V5.Melee.Local
import Evergreen.V5.Melee.Stream


type Preview
    = Snapshot Evergreen.V5.Melee.Local.Model
    | Delta Evergreen.V5.Melee.Stream.Delta
