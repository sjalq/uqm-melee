module Evergreen.V5.OAuth.AuthorizationCode exposing (..)

import Evergreen.V5.OAuth


type alias AuthorizationError =
    { error : Evergreen.V5.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


type alias AuthenticationError =
    { error : Evergreen.V5.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }
