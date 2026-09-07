module Pages.Default exposing (..)

import Html exposing (Html)
import Pages.Melee
import Theme
import Types exposing (..)


init : FrontendModel -> ( FrontendModel, Cmd FrontendMsg )
init =
    Pages.Melee.init


view : FrontendModel -> Theme.Colors -> Html FrontendMsg
view =
    Pages.Melee.view
