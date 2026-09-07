module Evergreen.V6.OAuth.AuthorizationCode exposing (..)

import Evergreen.V6.OAuth


type alias AuthorizationError =
    { error : Evergreen.V6.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


type alias AuthenticationError =
    { error : Evergreen.V6.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }
