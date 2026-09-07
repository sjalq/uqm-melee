module Frontend exposing (..)

import Auth.Common
import Auth.Flow
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Components.LoginModal
import Duration
import Effect.Browser.Events
import Effect.Browser.Navigation
import Effect.Command as Command exposing (Command, FrontendOnly)
import Effect.Lamdera
import Effect.Subscription as Subscription exposing (Subscription)
import Effect.Time
import File
import File.Download
import File.Select
import Html exposing (..)
import Html.Attributes as Attr
import Html.Events as HE
import Json.Decode as Decode
import Lamdera
import Melee.Init
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Location as Location
import Melee.Menu as Menu
import Melee.Presentation as Presentation
import Melee.Preview as Preview
import Melee.Rate as MeleeRate
import Melee.Rng exposing (Seed(..))
import Melee.Room as Melee
import Melee.Ship as Ship
import Melee.Units exposing (Side(..))
import Melee.Step as MeleeStep
import Melee.Stream as Stream
import Melee.Telemetry as Telemetry
import Pages.Admin
import Pages.Default
import Pages.Examples
import Pages.Melee
import Pages.Metrics
import Pages.PageFrame exposing (viewCurrentPage, viewTabs)
import Ports.Clipboard
import Ports.ConsoleLogger
import Ports.MeleeBrowser
import Ports.Telemetry
import Route
import Task
import Theme
import Types exposing (..)
import Url exposing (Url)



-- import Fusion.Patch
-- import Fusion


type alias Model =
    FrontendModel



-- app =
--     Lamdera.frontend
--         { init = initWithAuth
--         , onUrlRequest = UrlClicked
--         , onUrlChange = UrlChanged
--         , update = update
--         , updateFromBackend = updateFromBackend
--         , subscriptions = subscriptions
--         , view = view
--         }


{-| replace with your app function to try it out
-}
app =
    Effect.Lamdera.frontend Lamdera.sendToBackend
        { init = initWithAuth
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = subscriptions
        , view = view
        }


subscriptions : Model -> Subscription FrontendOnly FrontendMsg
subscriptions model =
    Subscription.batch
        [ Subscription.fromJs "melee_browser_from_js" Ports.MeleeBrowser.receive (Menu.decode >> MeleeBrowser)
        , Subscription.fromJs "telemetry_clock" Ports.Telemetry.observed (Ports.Telemetry.decode >> TelemetryClock)
        , Effect.Time.every (Duration.seconds 1) (Effect.Time.posixToMillis >> MeleeClock)
        , Effect.Browser.Events.onAnimationFrameDelta (Duration.inMilliseconds >> MeleeFrame)
        , Effect.Browser.Events.onVisibilityChange (\visibility -> MeleeVisibility (visibility /= Effect.Browser.Events.Hidden))
        , Effect.Browser.Events.onKeyDown
            (Decode.field "repeat" Decode.bool
                |> Decode.andThen
                    (\repeated ->
                        if repeated then
                            Decode.fail "held key"

                        else
                            Decode.map (\k -> MeleeLocal (Melee.KeyDown k)) keyDecoder
                    )
            )
        , Effect.Browser.Events.onKeyUp (Decode.map (\k -> MeleeLocal (Melee.KeyUp k)) keyDecoder)
        ]


keyDecoder : Decode.Decoder String
keyDecoder =
    Decode.field "key" Decode.string


init : Url -> Effect.Browser.Navigation.Key -> ( FrontendModel, Command FrontendOnly ToBackend FrontendMsg )
init url key =
    let
        route =
            Route.fromUrl url

        initialPreferences =
            { darkMode = True }

        initialGame =
            Location.configure (Location.fromUrl url) Game.init

        model =
            { key = key
            , currentRoute = route
            , adminPage =
                { logs = []
                , isAuthenticated = False
                , remoteUrl = ""
                }
            , authFlow = Auth.Common.Idle
            , authRedirectBaseUrl = { url | query = Nothing, fragment = Nothing }
            , login = NotLogged False
            , currentUser = Nothing
            , pendingAuth = False
            , preferences = initialPreferences
            , emailPasswordForm =
                { email = ""
                , password = ""
                , confirmPassword = ""
                , name = ""
                , isSignupMode = False
                , error = Nothing
                }
            , profileDropdownOpen = False
            , loginModalOpen = False
            , melee = Melee.Browsing
            , player = Nothing
            , playerName = ""
            , searching = False
            , meleeVisible = True
            , telemetry = Telemetry.init
            , telemetryReply = Nothing
            , meleeNow = 0
            , creatingRoom = False
            , location = Location.fromUrl url
            , arenaPreview = Nothing
            , showLocalGame = (Location.fromUrl url).local
            , watchableGames = []
            , availableRooms = Nothing
            , roomCode = ""
            , meleeHeld = Keys.none
            , game = { initialGame | sound = False }
            , pickCell = { bottom = Game.defaultPickCell, top = Game.defaultPickCell }
            }
    in
    inits model route
        |> Tuple.mapSecond (\cmd -> Command.batch [ cmd, locationCommand model ])


inits : Model -> Route -> ( Model, Command FrontendOnly ToBackend FrontendMsg )
inits model route =
    case route of
        Admin adminRoute ->
            Pages.Admin.init model adminRoute
                |> Tuple.mapSecond (Command.fromCmd "Admin.init")

        Default ->
            Pages.Default.init model
                |> Tuple.mapSecond (Command.fromCmd "Default.init")

        Examples ->
            Pages.Examples.init model
                |> Tuple.mapSecond (Command.fromCmd "Examples.init")

        Melee ->
            Pages.Melee.init model
                |> Tuple.mapSecond (Command.fromCmd "Melee.init")

        Metrics ->
            ( model, Command.none )

        NotFound ->
            ( model, Command.none )


update : FrontendMsg -> Model -> ( Model, Command FrontendOnly ToBackend FrontendMsg )
update msg model =
    updateCore msg model
        |> Tuple.mapFirst
            (\next ->
                case msg of
                    MeleeFrame delta ->
                        { next | telemetry = Telemetry.frame delta next.telemetry }

                    _ ->
                        next
            )
        |> Presentation.effects model


updateCore msg model =
    case msg of
        NoOpFrontendMsg ->
            ( model, Command.none )

        UrlRequested urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Effect.Browser.Navigation.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Effect.Browser.Navigation.load url
                    )

        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Effect.Browser.Navigation.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Effect.Browser.Navigation.load url
                    )

        UrlChanged url ->
            let
                newModel =
                    { model | currentRoute = Route.fromUrl url, location = Location.fromUrl url, showLocalGame = (Location.fromUrl url).local, game = Location.configure (Location.fromUrl url) model.game }
            in
            inits newModel newModel.currentRoute
                |> Tuple.mapSecond
                    (\cmd ->
                        Command.batch
                            [ cmd
                            , if model.currentRoute == newModel.currentRoute && model.location.room == newModel.location.room && model.location.watching == newModel.location.watching && model.location.local == newModel.location.local then
                                Command.none

                              else
                                locationCommand newModel
                            ]
                    )

        DirectToBackend msg_ ->
            ( model, Effect.Lamdera.sendToBackend msg_ )

        Admin_RemoteUrlChanged url ->
            let
                oldAdminPage =
                    model.adminPage
            in
            ( { model | adminPage = { oldAdminPage | remoteUrl = url } }, Command.none )

        Admin_LogsNavigate params ->
            ( model
            , Effect.Browser.Navigation.pushUrl model.key (Route.toString (Admin (AdminLogs params)))
            )

        Logout ->
            let
                -- Reset form to initial clean state
                cleanForm =
                    { email = ""
                    , password = ""
                    , confirmPassword = ""
                    , name = ""
                    , isSignupMode = False
                    , error = Nothing
                    }
            in
            ( { model
                | login = NotLogged False
                , pendingAuth = False
                , preferences = { darkMode = True }
                , emailPasswordForm = cleanForm
              }
            , Effect.Lamdera.sendToBackend LoggedOut
            )

        Auth0SigninRequested ->
            Auth.Flow.signInRequested "OAuthAuth0" { model | login = NotLogged True, pendingAuth = True } Nothing
                |> Tuple.mapSecond (AuthToBackend >> Lamdera.sendToBackend >> Command.fromCmd "Auth0Signin")

        EmailPasswordAuthMsg authMsg ->
            updateEmailPasswordAuth authMsg model
                |> Tuple.mapSecond (Command.fromCmd "EmailPasswordAuth")

        ToggleDarkMode ->
            let
                newDarkModeState =
                    not model.preferences.darkMode

                -- Explicitly alias the nested record
                currentFrontendPreferences =
                    model.preferences

                updatedFrontendPreferences : Preferences
                updatedFrontendPreferences =
                    { currentFrontendPreferences | darkMode = newDarkModeState }

                -- Update the alias
            in
            ( { model | preferences = updatedFrontendPreferences }
            , Effect.Lamdera.sendToBackend (SetDarkModePreference newDarkModeState)
            )

        ToggleProfileDropdown ->
            ( { model | profileDropdownOpen = not model.profileDropdownOpen }, Command.none )

        ToggleLoginModal ->
            ( { model | loginModalOpen = not model.loginModalOpen }, Command.none )

        CloseLoginModal ->
            ( { model | loginModalOpen = False }, Command.none )

        EmailPasswordAuthError errorMsg ->
            let
                updatedForm =
                    model.emailPasswordForm
                        |> (\form -> { form | error = Just errorMsg })
            in
            ( { model | emailPasswordForm = updatedForm, loginModalOpen = True }, Command.none )

        ConsoleLogClicked ->
            ( model, Command.fromCmd "ConsoleLog" (Ports.ConsoleLogger.log "Hello from Elm!") )

        ConsoleLogReceived message ->
            ( model, Command.none )

        CopyToClipboard text ->
            ( model, Command.fromCmd "Clipboard" (Ports.Clipboard.copyToClipboard text) )

        ClipboardResult result ->
            ( model, Command.none )

        SaveFleets ->
            ( model, Command.fromCmd "Save fleets" (File.Download.string "super-melee-fleets.json" "application/json" (Game.encode model.game)) )

        LoadFleets ->
            ( model, Command.fromCmd "Choose fleets" (File.Select.file [ "application/json" ] FleetFileSelected) )

        FleetFileSelected file ->
            ( model, Command.fromCmd "Read fleets" (Task.perform FleetFileLoaded (File.toString file)) )

        FleetFileLoaded source ->
            case model.melee of
                Melee.Browsing ->
                    ( { model | game = Game.load source model.game }, Command.none )

                _ ->
                    ( model, Command.none )

        PlayerNameChanged name ->
            ( { model | playerName = name }, Command.none )

        MeleeBrowser value ->
            ( model, Presentation.browserCommands (Menu.respond (model.game.sound && model.meleeVisible) value) )

        TelemetryClock ( serial, returning, now ) ->
            let
                t =
                    model.telemetry
            in
            if not model.meleeVisible || serial /= t.serial then
                ( model, Command.none )

            else if returning then
                case t.pending of
                    Just _ ->
                        ( { model | telemetry = Telemetry.received now model.telemetryReply t, telemetryReply = Nothing }, Command.none )

                    Nothing ->
                        ( model, Command.none )

            else
                ( { model | telemetry = { t | pending = Just ( serial, now ) } }
                , Effect.Lamdera.sendToBackend (Probe serial (model.currentRoute == Metrics))
                )

        MeleeClock now ->
            let
                ( next, probe ) =
                    Telemetry.tick model.meleeVisible model.telemetry
            in
            ( { model | meleeNow = now, telemetry = next }
            , probe |> Maybe.map (\serial -> Command.fromCmd "telemetry clock" (Ports.Telemetry.read ( serial, False ))) |> Maybe.withDefault Command.none
            )

        MeleeVisibility visible ->
            let
                ( next, cmd ) =
                    if visible then
                        ( model, Command.none )

                    else
                        gameAction Game.Suspend model
            in
            ( { next | meleeVisible = visible, telemetry = Telemetry.reset next.telemetry }, Command.batch [ cmd, Effect.Lamdera.sendToBackend (MeleeToBackend (Melee.PreviewSubscription (visible && (model.currentRoute == Melee || model.currentRoute == Default) && model.location.room == Nothing && not model.showLocalGame))) ] )

        NavigateMelee location ->
            ( model, Effect.Browser.Navigation.pushUrl model.key (Location.toUrl location) )

        ShowLocalGame local ->
            let
                location =
                    model.location
            in
            update (NavigateMelee { location | room = Nothing, local = local, page = 0 }) model

        RoomCodeChanged code ->
            ( { model | roomCode = code }, Command.none )

        Online message ->
            let
                location =
                    Location.lobby
            in
            case message of
                Melee.JoinRoom code ->
                    update (NavigateMelee { location | room = Just (String.toUpper (String.trim code)) }) model

                Melee.WatchRoom code ->
                    update (NavigateMelee { location | room = Just code, watching = True }) model

                Melee.LeaveRoom ->
                    update (NavigateMelee location) model

                Melee.CreateRoom ->
                    ( { model | creatingRoom = True }, Effect.Lamdera.sendToBackend (MeleeToBackend message) )

                _ ->
                    ( model, Effect.Lamdera.sendToBackend (MeleeToBackend message) )

        MeleeFrame milliseconds ->
            if model.currentRoute == Melee || model.currentRoute == Default then
                let
                    nextGame =
                        case model.melee of
                            Melee.Browsing ->
                                Game.advance milliseconds model.meleeHeld model.game |> Game.animate milliseconds

                            _ ->
                                Game.present milliseconds model.game
                in
                ( { model
                    | arenaPreview =
                        if model.location.room == Nothing && not model.showLocalGame then
                            Maybe.map (Game.present milliseconds) model.arenaPreview

                        else
                            model.arenaPreview
                    , game = nextGame
                    , pickCell = refreshPickCell model.game.phase nextGame.phase model.pickCell
                  }
                , Command.none
                )

            else
                ( model, Command.none )

        GameMsg gameMsg ->
            gameAction gameMsg model

        MeleeLocal Melee.Tick ->
            update (MeleeFrame (1000 / 60)) model

        MeleeLocal (Melee.KeyDown k) ->
            if model.currentRoute /= Melee && model.currentRoute /= Default then
                ( model, Command.none )

            else
                case model.game.phase of
                    Game.Selecting bottom top ->
                        pickKey k bottom top model

                    _ ->
                        if k == "Escape" || k == "p" || k == "P" then
                            gameAction Game.TogglePause model

                        else
                            sendControls (Keys.press k model.meleeHeld) model

        MeleeLocal (Melee.KeyUp k) ->
            sendControls (Keys.release k model.meleeHeld) model

        MeleeLocal Melee.Restart ->
            gameAction Game.Rematch model



-- Admin_FusionPatch patch ->
--     ( { model
--         | fusionState =
--             Fusion.Patch.patch { force = False } patch model.fusionState
--                 |> Result.withDefault model.fusionState
--       }
--     , Lamdera.sendToBackend (Fusion_PersistPatch patch)
--     )
-- Admin_FusionQuery query ->
--     ( model, Lamdera.sendToBackend (Fusion_Query query) )


updateFromBackend : ToFrontend -> Model -> ( Model, Command FrontendOnly ToBackend FrontendMsg )
updateFromBackend msg model =
    updateFromBackendCore msg model |> Presentation.effects model


updateFromBackendCore msg model =
    case msg of
        ProbeReply serial sample ->
            if serial == model.telemetry.serial && model.telemetry.pending /= Nothing then
                ( { model | telemetryReply = sample }, Command.fromCmd "telemetry return clock" (Ports.Telemetry.read ( serial, True )) )

            else
                ( model, Command.none )

        NoOpToFrontend ->
            ( model, Command.none )

        -- Admin page
        Admin_Logs_ToFrontend logs ->
            let
                oldAdminPage =
                    model.adminPage
            in
            ( { model | adminPage = { oldAdminPage | logs = logs } }, Command.none )

        AuthToFrontend authToFrontendMsg ->
            authUpdateFromBackend authToFrontendMsg model
                |> Tuple.mapSecond (Command.fromCmd "AuthToFrontend")

        AuthSuccess userInfo ->
            ( { model | login = LoggedIn userInfo, pendingAuth = False, loginModalOpen = False }
            , Command.batch
                [ Effect.Lamdera.sendToBackend GetUserToBackend
                , Effect.Browser.Navigation.pushUrl model.key "/"
                ]
            )

        UserInfoMsg mUserinfo ->
            case mUserinfo of
                Just userInfo ->
                    ( { model | login = LoggedIn userInfo, pendingAuth = False }, Command.none )

                Nothing ->
                    ( { model | login = NotLogged False, pendingAuth = False, preferences = { darkMode = True } }, Command.none )

        UserDataToFrontend currentUser ->
            ( { model | currentUser = Just currentUser, preferences = currentUser.preferences }, Command.none )

        -- Admin_FusionResponse value ->
        --     ( { model | fusionState = value }, Command.none )
        PermissionDenied _ ->
            -- Simply ignore the denied action without any UI notification
            ( model, Command.none )

        A0 message ->
            -- Log websocket messages for debugging
            ( model, Command.none )

        MeleeToFrontend message ->
            case message of
                Melee.PlayerStatus profile searching ->
                    ( { model | player = Just profile, playerName = profile.name, searching = searching }, Command.none )

                Melee.MatchFound snapshot ->
                    let
                        location =
                            Location.lobby
                    in
                    updateFromBackend (MeleeToFrontend (Melee.RoomSnapshot snapshot)) { model | creatingRoom = True, searching = False, showLocalGame = False, location = { location | room = Just snapshot.code } }

                Melee.RoomsAvailable rooms ->
                    ( { model | availableRooms = Just rooms }, Command.none )

                Melee.ArenaPreview preview ->
                    ( { model | arenaPreview = Preview.apply preview model.arenaPreview }, Command.none )

                Melee.CombatDelta code revision delta ->
                    let
                        game =
                            Stream.apply delta model.game
                    in
                    case model.melee of
                        Melee.Seated snapshot ->
                            if snapshot.code == code && revision > snapshot.revision then
                                ( { model | game = game, melee = Melee.Seated { snapshot | game = game, revision = revision } }, Command.none )

                            else
                                ( model, Command.none )

                        Melee.Watching snapshot ->
                            if snapshot.code == code && revision > snapshot.revision then
                                ( { model | game = game, melee = Melee.Watching { snapshot | game = game, revision = revision } }, Command.none )

                            else
                                ( model, Command.none )

                        _ ->
                            ( model, Command.none )

                Melee.GamesAvailable games ->
                    ( { model | watchableGames = games }, Command.none )

                Melee.SpectatorView snapshot ->
                    let
                        old =
                            model.game

                        game =
                            snapshot.game

                        stale =
                            case model.melee of
                                Melee.Watching previous ->
                                    previous.code == snapshot.code && previous.revision >= snapshot.revision

                                _ ->
                                    False
                    in
                    if stale || model.location.room /= Just snapshot.code || not model.location.watching then
                        ( model, Command.none )

                    else
                        ( { model | melee = Melee.Watching snapshot, meleeHeld = Keys.none, game = { game | graphics = old.graphics, sound = old.sound, zoomWidth = old.zoomWidth, presentationClock = 0 } }, Command.none )

                Melee.RoomSnapshot snapshot ->
                    let
                        stale =
                            case model.melee of
                                Melee.Seated previous ->
                                    previous.code == snapshot.code && previous.revision >= snapshot.revision

                                _ ->
                                    False

                        old =
                            model.game

                        game =
                            snapshot.game
                    in
                    if not model.creatingRoom && (model.location.room /= Just snapshot.code || model.location.watching) then
                        ( model, redirectRoom model )

                    else if stale then
                        ( model, Command.none )

                    else
                        ( { model
                            | melee = Melee.Seated snapshot
                            , creatingRoom = False
                            , roomCode = snapshot.code
                            , pickCell = refreshPickCell old.phase game.phase model.pickCell
                            , game =
                                { game
                                    | graphics = old.graphics
                                    , sound = old.sound
                                    , zoomWidth = old.zoomWidth
                                    , presentationClock =
                                        if Maybe.map .frame (Game.phaseArena old.phase) == Maybe.map .frame (Game.phaseArena game.phase) then
                                            old.presentationClock

                                        else
                                            0
                                    , editing = snapshot.side
                                }
                          }
                        , if model.creatingRoom then
                            let
                                location =
                                    Location.lobby
                            in
                            Effect.Browser.Navigation.pushUrl model.key (Location.toUrl { location | room = Just snapshot.code })

                          else
                            Command.none
                        )

                Melee.RoomLeft ->
                    ( { model | melee = Melee.Browsing, game = Game.update Game.Menu model.game, meleeHeld = Keys.none }, Command.none )

                Melee.RoomError reason ->
                    let
                        game =
                            model.game
                    in
                    ( { model | game = { game | notice = reason } }, Command.none )


view : Model -> Browser.Document FrontendMsg
view model =
    let
        colors =
            Theme.getColors model.preferences.darkMode

        modal =
            Components.LoginModal.view
                { isOpen = model.loginModalOpen
                , colors = colors
                , emailPasswordForm = model.emailPasswordForm
                , onClose = CloseLoginModal
                , onAuth0Login = Auth0SigninRequested
                , onEmailPasswordMsg = EmailPasswordAuthMsg
                , onNoOp = NoOpFrontendMsg
                , isAuthenticating = model.pendingAuth
                }
    in
    { title =
        if model.currentRoute == Melee || model.currentRoute == Default then
            "SUPER MELEE"

        else if model.currentRoute == Metrics then
            "SUPER MELEE / Metrics"

        else
            "Dashboard"
    , body =
        if model.currentRoute == Metrics then
            [ Pages.Metrics.view model.telemetry ]

        else if model.currentRoute == Melee || model.currentRoute == Default then
            [ Pages.Melee.view model colors
            , Pages.Metrics.hud model.telemetry
            , modal
            ]

        else
            [ div
                [ Theme.primaryBg model.preferences.darkMode
                , Theme.primaryText model.preferences.darkMode
                , Attr.style "min-height" "100vh"
                , Attr.class "p-4"
                ]
                [ viewTabs model
                , viewCurrentPage model
                ]
            , modal
            ]
    }


callbackForAuth0Auth : FrontendModel -> Url.Url -> Effect.Browser.Navigation.Key -> ( FrontendModel, Cmd FrontendMsg )
callbackForAuth0Auth model url key =
    Auth.Flow.init model
        "OAuthAuth0"
        url
        (Effect.Browser.Navigation.withRealKey key)
        (\msg -> Lamdera.sendToBackend (AuthToBackend msg))


callbackForGoogleAuth : FrontendModel -> Url.Url -> Effect.Browser.Navigation.Key -> ( FrontendModel, Cmd FrontendMsg )
callbackForGoogleAuth model url key =
    Auth.Flow.init model
        "OAuthGoogle"
        url
        (Effect.Browser.Navigation.withRealKey key)
        (\msg -> Lamdera.sendToBackend (AuthToBackend msg))


authCallbackCmd : FrontendModel -> Url.Url -> Effect.Browser.Navigation.Key -> ( FrontendModel, Cmd FrontendMsg )
authCallbackCmd model url key =
    let
        { path } =
            url
    in
    case path of
        "/login/OAuthGoogle/callback" ->
            callbackForGoogleAuth model url key

        "/login/OAuthAuth0/callback" ->
            callbackForAuth0Auth model url key

        _ ->
            ( model, Cmd.none )


initWithAuth : Url.Url -> Effect.Browser.Navigation.Key -> ( FrontendModel, Command FrontendOnly ToBackend FrontendMsg )
initWithAuth url key =
    let
        ( model, initCmds ) =
            init url key

        ( authModel, authCmd ) =
            authCallbackCmd model url key
    in
    ( authModel
    , Command.batch
        [ initCmds
        , Command.fromCmd "authCallback" authCmd
        , Effect.Lamdera.sendToBackend GetUserToBackend
        ]
    )


updateEmailPasswordAuth : EmailPasswordAuthMsg -> Model -> ( Model, Cmd FrontendMsg )
updateEmailPasswordAuth authMsg model =
    case authMsg of
        EmailPasswordFormMsg formMsg ->
            let
                newForm =
                    updateEmailPasswordForm formMsg model.emailPasswordForm

                -- Check if form was validated and should submit
                cmd =
                    case formMsg of
                        EmailPasswordFormSubmit ->
                            if newForm.error == Nothing then
                                let
                                    backendMsg =
                                        if newForm.isSignupMode then
                                            EmailPasswordSignupToBackend newForm.email
                                                newForm.password
                                                (if String.isEmpty (String.trim newForm.name) then
                                                    Nothing

                                                 else
                                                    Just newForm.name
                                                )

                                        else
                                            EmailPasswordLoginToBackend newForm.email newForm.password
                                in
                                Lamdera.sendToBackend (EmailPasswordAuthToBackend backendMsg)

                            else
                                Cmd.none

                        _ ->
                            Cmd.none

                newModel =
                    if formMsg == EmailPasswordFormSubmit && newForm.error == Nothing then
                        { model | emailPasswordForm = newForm, login = NotLogged True, pendingAuth = True }

                    else
                        { model | emailPasswordForm = newForm }
            in
            ( newModel, cmd )

        EmailPasswordLoginRequested email password ->
            ( { model | login = NotLogged True, pendingAuth = True }
            , Lamdera.sendToBackend (EmailPasswordAuthToBackend (EmailPasswordLoginToBackend email password))
            )

        EmailPasswordSignupRequested email password maybeName ->
            ( { model | login = NotLogged True, pendingAuth = True }
            , Lamdera.sendToBackend (EmailPasswordAuthToBackend (EmailPasswordSignupToBackend email password maybeName))
            )


updateEmailPasswordForm : EmailPasswordFormMsg -> EmailPasswordFormModel -> EmailPasswordFormModel
updateEmailPasswordForm msg model =
    case msg of
        EmailPasswordFormEmailChanged email ->
            { model | email = email, error = Nothing }

        EmailPasswordFormPasswordChanged password ->
            { model | password = password, error = Nothing }

        EmailPasswordFormConfirmPasswordChanged confirmPassword ->
            { model | confirmPassword = confirmPassword, error = Nothing }

        EmailPasswordFormNameChanged name ->
            { model | name = name, error = Nothing }

        EmailPasswordFormToggleMode ->
            { model | isSignupMode = not model.isSignupMode, error = Nothing }

        EmailPasswordFormSubmit ->
            if String.isEmpty (String.trim model.email) || String.isEmpty (String.trim model.password) then
                { model | error = Just "Please fill in all required fields" }

            else if model.isSignupMode && model.password /= model.confirmPassword then
                { model | error = Just "Passwords do not match" }

            else
                model



-- Valid form


viewWithAuth : Model -> Browser.Document FrontendMsg
viewWithAuth model =
    let
        isDark =
            model.preferences.darkMode

        colors =
            Theme.getColors isDark
    in
    { title = "View Auth Test"
    , body =
        [ div
            [ Attr.style "margin" "20px"
            , Attr.style "font-family" "Arial, sans-serif"
            , Theme.primaryBg isDark
            , Theme.primaryText isDark
            ]
            [ h1
                [ Theme.primaryText isDark ]
                [ text "Auth0 Test" ]
            , case model.login of
                LoggedIn userInfo ->
                    div
                        [ Attr.style "padding" "20px"
                        , Attr.style "border" ("1px solid " ++ colors.border)
                        , Attr.style "border-radius" "5px"
                        , Attr.style "background-color" colors.secondaryBg
                        , Attr.style "max-width" "400px"
                        ]
                        [ div
                            [ Attr.style "margin-bottom" "15px"
                            , Attr.style "font-size" "16px"
                            , Attr.style "color" colors.primaryText
                            ]
                            [ text ("👤 Logged in as: " ++ userInfo.email) ]
                        , button
                            [ HE.onClick Logout
                            , Attr.style "background-color" colors.dangerBg
                            , Attr.style "color" colors.buttonText
                            , Attr.style "padding" "10px 15px"
                            , Attr.style "border" "none"
                            , Attr.style "border-radius" "4px"
                            , Attr.style "cursor" "pointer"
                            ]
                            [ text "Logout" ]
                        ]

                _ ->
                    div
                        [ Attr.style "padding" "20px"
                        , Attr.style "border" ("1px solid " ++ colors.border)
                        , Attr.style "border-radius" "5px"
                        , Attr.style "background-color" colors.secondaryBg
                        , Attr.style "max-width" "400px"
                        ]
                        [ p
                            [ Attr.style "margin-bottom" "15px"
                            , Attr.style "color" colors.primaryText
                            ]
                            [ text "Please sign in to continue" ]
                        , button
                            [ HE.onClick Auth0SigninRequested
                            , Attr.style "background-color" colors.buttonBg
                            , Attr.style "color" colors.buttonText
                            , Attr.style "padding" "10px 15px"
                            , Attr.style "border" "none"
                            , Attr.style "border-radius" "4px"
                            , Attr.style "cursor" "pointer"
                            ]
                            [ text "Sign in with Auth0" ]
                        ]
            ]
        ]
    }


authUpdateFromBackend : Auth.Common.ToFrontend -> FrontendModel -> ( FrontendModel, Cmd FrontendMsg )
authUpdateFromBackend authToFrontendMsg model =
    case authToFrontendMsg of
        Auth.Common.AuthInitiateSignin url ->
            if model.pendingAuth then
                let
                    ( newModel, cmd ) =
                        Auth.Flow.startProviderSignin url model
                in
                ( { newModel | pendingAuth = False, login = LoginTokenSent }, cmd )

            else
                ( model, Cmd.none )

        Auth.Common.AuthError err ->
            let
                ( newModel, cmd ) =
                    Auth.Flow.setError model err

                errorMsg =
                    case err of
                        Auth.Common.ErrAuthString msg ->
                            msg

                        _ ->
                            "Authentication failed"

                -- Send error to form via message
                errorCmd =
                    Task.perform identity (Task.succeed (EmailPasswordAuthError errorMsg))
            in
            ( { newModel | pendingAuth = False, login = NotLogged False }, Cmd.batch [ cmd, errorCmd ] )

        Auth.Common.AuthSessionChallenge _ ->
            ( model, Cmd.none )


gameAction : Game.Msg -> Model -> ( Model, Command FrontendOnly ToBackend FrontendMsg )
gameAction message model =
    case model.melee of
        Melee.Browsing ->
            let
                location =
                    model.location

                nextGame =
                    Game.update message model.game

                changed =
                    { model | game = nextGame, meleeHeld = Keys.none, pickCell = refreshPickCell model.game.phase nextGame.phase model.pickCell }
            in
            case message of
                Game.SetMode mode ->
                    update (NavigateMelee { location | mode = mode }) changed

                Game.SetDifficulty difficulty ->
                    update (NavigateMelee { location | difficulty = difficulty }) changed

                _ ->
                    ( changed, Command.none )

        Melee.Watching _ ->
            if message == Game.ToggleGraphics || message == Game.ToggleSound then
                ( { model | game = Game.update message model.game }, Command.none )

            else
                ( model, Command.none )

        Melee.Seated snapshot ->
            let
                send msg =
                    ( { model | meleeHeld = Keys.none }, Effect.Lamdera.sendToBackend (MeleeToBackend msg) )

                own side msg =
                    if side == snapshot.side then
                        send msg

                    else
                        ( model, Command.none )
            in
            case message of
                Game.ToggleGraphics ->
                    ( { model | game = Game.update message model.game }, Command.none )

                Game.ToggleSound ->
                    ( { model | game = Game.update message model.game }, Command.none )

                Game.Rename side name ->
                    own side (Melee.Rename name)

                Game.Add ship ->
                    send (Melee.Add ship)

                Game.Remove side index ->
                    own side (Melee.Remove index)

                Game.Start ->
                    send Melee.Ready

                Game.Pick side index ->
                    own side (Melee.Pick index)

                Game.RandomPick side ->
                    own side Melee.RandomPick

                Game.TogglePause ->
                    send Melee.Pause

                Game.Suspend ->
                    send Melee.Suspend

                Game.Menu ->
                    if snapshot.ranked /= Nothing then
                        update (Online Melee.LeaveRoom) model

                    else
                        send Melee.Hangar

                Game.Rematch ->
                    if snapshot.ranked /= Nothing then
                        update (Online Melee.LeaveRoom) model

                    else
                        send Melee.Rematch

                _ ->
                    ( model, Command.none )


refreshPickCell : Game.Phase -> Game.Phase -> { bottom : { row : Int, col : Int }, top : { row : Int, col : Int } } -> { bottom : { row : Int, col : Int }, top : { row : Int, col : Int } }
refreshPickCell previous next current =
    case ( previous, next ) of
        ( Game.Selecting _ _, Game.Selecting _ _ ) ->
            current

        ( _, Game.Selecting _ _ ) ->
            { bottom = Game.defaultPickCell, top = Game.defaultPickCell }

        _ ->
            current


nudgeCell : Int -> Int -> { row : Int, col : Int } -> { row : Int, col : Int }
nudgeCell drow dcol cell =
    { row = modBy Game.pickRows (cell.row + drow + Game.pickRows)
    , col = modBy (Game.pickColumns + 1) (cell.col + dcol + Game.pickColumns + 1)
    }


pickKey : String -> Maybe Ship.ShipKind -> Maybe Ship.ShipKind -> Model -> ( Model, Command FrontendOnly ToBackend FrontendMsg )
pickKey key bottom top model =
    let
        needs side selected =
            Game.humanNeedsPick model.game.mode side selected
                && (case model.melee of
                        Melee.Seated snapshot ->
                            snapshot.side == side

                        Melee.Watching _ ->
                            False

                        Melee.Browsing ->
                            True
                   )

        move side drow dcol =
            if side == Bottom then
                { model | pickCell = { bottom = nudgeCell drow dcol model.pickCell.bottom, top = model.pickCell.top } }

            else
                { model | pickCell = { bottom = model.pickCell.bottom, top = nudgeCell drow dcol model.pickCell.top } }

        confirm side cell =
            if cell.col == Game.pickColumns then
                if cell.row == 0 then
                    gameAction (Game.RandomPick side) model

                else
                    gameAction Game.Menu model

            else
                case Game.slotAt (cell.row * Game.pickColumns + cell.col) (Game.fleetSlots (Game.get side model.game.fleets) (Game.get side model.game.remaining)) of
                    Game.Ready index _ ->
                        gameAction (Game.Pick side index) model

                    _ ->
                        ( model, Command.none )
    in
    case key of
        "Escape" ->
            gameAction Game.Menu model

        "ArrowLeft" ->
            if needs Bottom bottom then
                ( move Bottom 0 -1, Command.none )

            else
                ( model, Command.none )

        "ArrowRight" ->
            if needs Bottom bottom then
                ( move Bottom 0 1, Command.none )

            else
                ( model, Command.none )

        "ArrowUp" ->
            if needs Bottom bottom then
                ( move Bottom -1 0, Command.none )

            else
                ( model, Command.none )

        "ArrowDown" ->
            if needs Bottom bottom then
                ( move Bottom 1 0, Command.none )

            else
                ( model, Command.none )

        "Enter" ->
            if needs Bottom bottom then
                confirm Bottom model.pickCell.bottom

            else
                ( model, Command.none )

        "a" ->
            if needs Top top then
                ( move Top 0 -1, Command.none )

            else
                ( model, Command.none )

        "A" ->
            if needs Top top then
                ( move Top 0 -1, Command.none )

            else
                ( model, Command.none )

        "d" ->
            if needs Top top then
                ( move Top 0 1, Command.none )

            else
                ( model, Command.none )

        "D" ->
            if needs Top top then
                ( move Top 0 1, Command.none )

            else
                ( model, Command.none )

        "w" ->
            if needs Top top then
                ( move Top -1 0, Command.none )

            else
                ( model, Command.none )

        "W" ->
            if needs Top top then
                ( move Top -1 0, Command.none )

            else
                ( model, Command.none )

        "s" ->
            if needs Top top then
                ( move Top 1 0, Command.none )

            else
                ( model, Command.none )

        "S" ->
            if needs Top top then
                ( move Top 1 0, Command.none )

            else
                ( model, Command.none )

        "j" ->
            if needs Top top then
                confirm Top model.pickCell.top

            else
                ( model, Command.none )

        "J" ->
            if needs Top top then
                confirm Top model.pickCell.top

            else
                ( model, Command.none )

        _ ->
            ( model, Command.none )


sendControls : Keys.Held -> Model -> ( Model, Command FrontendOnly ToBackend FrontendMsg )
sendControls held model =
    ( { model | meleeHeld = held }
    , case model.melee of
        Melee.Browsing ->
            Command.none

        Melee.Watching _ ->
            Command.none

        Melee.Seated _ ->
            if not (Melee.running model.game.phase) || (Keys.inputs held).bottom == (Keys.inputs model.meleeHeld).bottom then
                Command.none

            else
                Effect.Lamdera.sendToBackend (MeleeToBackend (Melee.Controls (Keys.inputs held).bottom))
    )


locationCommand : Model -> Command FrontendOnly ToBackend FrontendMsg
locationCommand model =
    let
        send msg =
            Effect.Lamdera.sendToBackend (MeleeToBackend msg)

        current =
            case model.melee of
                Melee.Seated snapshot ->
                    Just ( snapshot.code, False )

                Melee.Watching snapshot ->
                    Just ( snapshot.code, True )

                Melee.Browsing ->
                    Nothing
    in
    if model.currentRoute /= Melee && model.currentRoute /= Default then
        Command.batch [ send Melee.LeaveRoom, send (Melee.PreviewSubscription False) ]

    else
        case model.location.room of
            Just code ->
                if current == Just ( code, model.location.watching ) then
                    send (Melee.PreviewSubscription False)

                else
                    Command.batch [ send (Melee.Visit code model.location.watching), send (Melee.PreviewSubscription False) ]

            Nothing ->
                Command.batch
                    [ if current /= Nothing then
                        send Melee.LeaveRoom

                      else
                        Command.none
                    , send (Melee.PreviewSubscription (not model.location.local))
                    , send Melee.Identify
                    , send Melee.DiscoverRooms
                    ]


redirectRoom : Model -> Command FrontendOnly ToBackend FrontendMsg
redirectRoom model =
    Effect.Lamdera.sendToBackend
        (MeleeToBackend
            (case model.location.room of
                Nothing ->
                    Melee.LeaveRoom

                Just code ->
                    Melee.Visit code model.location.watching
            )
        )
