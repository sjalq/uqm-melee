module Evergreen.V4.OAuth.AuthorizationCode exposing (..)

import Evergreen.V4.OAuth


type alias AuthorizationError =
    { error : Evergreen.V4.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


type alias AuthenticationError =
    { error : Evergreen.V4.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }
