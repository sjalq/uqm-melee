module Evergreen.V4.Melee.Preview exposing (..)

import Evergreen.V4.Melee.Local
import Evergreen.V4.Melee.Stream


type Preview
    = Snapshot Evergreen.V4.Melee.Local.Model
    | Delta Evergreen.V4.Melee.Stream.Delta
