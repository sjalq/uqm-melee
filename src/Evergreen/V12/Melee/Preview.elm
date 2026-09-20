module Evergreen.V12.Melee.Preview exposing (..)

import Evergreen.V12.Melee.Local
import Evergreen.V12.Melee.Stream


type Preview
    = Snapshot Evergreen.V12.Melee.Local.Model
    | Delta Evergreen.V12.Melee.Stream.Delta
