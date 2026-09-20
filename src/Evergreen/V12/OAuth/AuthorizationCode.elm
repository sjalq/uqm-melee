module Evergreen.V12.OAuth.AuthorizationCode exposing (..)

import Evergreen.V12.OAuth


type alias AuthorizationError =
    { error : Evergreen.V12.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


type alias AuthenticationError =
    { error : Evergreen.V12.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }
