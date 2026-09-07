module Evergreen.V2.OAuth.AuthorizationCode exposing (..)

import Evergreen.V2.OAuth


type alias AuthorizationError =
    { error : Evergreen.V2.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    , state : Maybe String
    }


type alias AuthenticationError =
    { error : Evergreen.V2.OAuth.ErrorCode
    , errorDescription : Maybe String
    , errorUri : Maybe String
    }
