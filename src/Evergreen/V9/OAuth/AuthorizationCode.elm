module Evergreen.V9.OAuth.AuthorizationCode exposing (..)

import Evergreen.V9.OAuth


type alias AuthorizationError =
    { error : Evergreen.V9.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


type alias AuthenticationError =
    { error : Evergreen.V9.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }
