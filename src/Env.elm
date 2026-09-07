module Env exposing (Mode(..), mode)


type Mode
    = Development
    | Production


mode : Mode
mode =
    Production
