module Evergreen.V9.Melee.Preview exposing (..)

import Evergreen.V9.Melee.Local
import Evergreen.V9.Melee.Stream


type Preview
    = Snapshot Evergreen.V9.Melee.Local.Model
    | Delta Evergreen.V9.Melee.Stream.Delta
