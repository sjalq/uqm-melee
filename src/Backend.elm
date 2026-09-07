module Backend exposing (Model, app, init, subscriptions, update, updateFromFrontendCheckingRights)

-- import Fusion.Generated.Types
-- import Fusion.Patch

import Auth.EmailPasswordAuth as EmailPasswordAuth
import Auth.Flow
import Dict
import Duration
import Effect.Command as Command exposing (BackendOnly, Command)
import Effect.Lamdera
import Effect.Subscription as Subscription exposing (Subscription)
import Effect.Time as Time
import Lamdera
import Logger
import Melee.Room as Melee
import Rights.Auth0 exposing (backendConfig)
import Rights.Permissions exposing (sessionCanPerformAction)
import Rights.Role exposing (roleToString)
import Rights.User exposing (createUser, getUserRole, insertUser, isSysAdmin)
import Supplemental exposing (..)
import Task
import Types exposing (..)


type alias Model =
    BackendModel


app =
    Effect.Lamdera.backend Lamdera.broadcast
        Lamdera.sendToFrontend
        { init = init
        , update = update
        , updateFromFrontend = updateFromFrontendCheckingRights
        , subscriptions = subscriptions
        }


subscriptions : Model -> Subscription BackendOnly BackendMsg
subscriptions model =
    Subscription.batch
        [ Effect.Lamdera.onConnect (\session client -> MeleeConnected (Effect.Lamdera.sessionIdToString session) (Effect.Lamdera.clientIdToString client))
        , Effect.Lamdera.onDisconnect (\session client -> MeleeDisconnected (Effect.Lamdera.sessionIdToString session) (Effect.Lamdera.clientIdToString client))
        , if Dict.isEmpty model.melee.rooms then
            Subscription.none

          else
            Time.every (Duration.milliseconds (1000 / 24)) (Time.posixToMillis >> MeleeTick)
        ]


init : ( Model, Command BackendOnly ToFrontend BackendMsg )
init =
    let
        logSize =
            2000

        initialModel =
            { logState = Logger.init logSize
            , pendingAuths = Dict.empty
            , sessions = Dict.empty
            , users = Dict.empty
            , emailPasswordCredentials = Dict.empty
            , pollingJobs = Dict.empty
            , melee = Melee.init
            }

        -- Initialize with test data for development
        modelWithTestData =
            initialModel
    in
    ( modelWithTestData, Command.none )


update : BackendMsg -> Model -> ( Model, Command BackendOnly ToFrontend BackendMsg )
update msg model =
    case msg of
        MeleeTick now ->
            meleeResult model (Melee.tick now model.melee)

        MeleeConnected session client ->
            let
                ( known, identityMessages ) =
                    Melee.identify session client model.melee

                ( resumed, reconnectMessages ) =
                    Melee.reconnect session client known

                ( next, cmd ) =
                    meleeResult model ( resumed, identityMessages ++ reconnectMessages )
            in
            ( next, Command.batch [ cmd, Effect.Lamdera.sendToFrontend (Effect.Lamdera.clientIdFromString client) (MeleeToFrontend (Melee.RoomsAvailable (Melee.discover next.melee))), Effect.Lamdera.sendToFrontend (Effect.Lamdera.clientIdFromString client) (MeleeToFrontend (Melee.GamesAvailable (Melee.games next.melee))) ] )

        MeleeDisconnected session client ->
            meleeResult model (Melee.disconnect session client model.melee)

        NoOpBackendMsg ->
            ( model, Command.none )

        GotLogTime loggerMsg ->
            ( { model | logState = Logger.handleMsg loggerMsg model.logState }
            , Command.none
            )

        GotRemoteModel result ->
            case result of
                Ok model_ ->
                    Logger.logInfo "GotRemoteModel Ok" GotLogTime ( model_, Cmd.none )
                        |> wrapLogCmd

                Err err ->
                    Logger.logError ("GotRemoteModel Err: " ++ httpErrorToString err) GotLogTime ( model, Cmd.none )
                        |> wrapLogCmd

        AuthBackendMsg authMsg ->
            Auth.Flow.backendUpdate (backendConfig model) authMsg
                |> Tuple.mapSecond (Command.fromCmd "AuthBackendMsg")

        EmailPasswordAuthResult result ->
            case result of
                EmailPasswordSignupWithHash browserCookie connectionId email password maybeName salt hash ->
                    EmailPasswordAuth.completeSignup browserCookie connectionId email password maybeName salt hash model
                        |> Tuple.mapSecond (Command.fromCmd "EmailPasswordAuth")

        GotCryptoPriceResult token result ->
            case result of
                Ok priceStr ->
                    let
                        updatedPollingJobs =
                            Dict.insert token (Ready (Ok priceStr)) model.pollingJobs
                    in
                    Logger.logInfo ("Crypto price calculated: " ++ priceStr) GotLogTime ( { model | pollingJobs = updatedPollingJobs }, Cmd.none )
                        |> wrapLogCmd

                Err err ->
                    let
                        updatedPollingJobs =
                            Dict.insert token (Ready (Err (httpErrorToString err))) model.pollingJobs
                    in
                    Logger.logError ("Failed to calculate crypto price: " ++ httpErrorToString err) GotLogTime ( { model | pollingJobs = updatedPollingJobs }, Cmd.none )
                        |> wrapLogCmd

        StoreTaskResult token result ->
            let
                updatedPollingJobs =
                    Dict.insert token (Ready result) model.pollingJobs
            in
            case result of
                Ok _ ->
                    Logger.logInfo ("Task completed successfully: " ++ token) GotLogTime ( { model | pollingJobs = updatedPollingJobs }, Cmd.none )
                        |> wrapLogCmd

                Err err ->
                    Logger.logError ("Task failed: " ++ token ++ " - " ++ err) GotLogTime ( { model | pollingJobs = updatedPollingJobs }, Cmd.none )
                        |> wrapLogCmd

        GotJobTime token timestamp ->
            let
                updatedPollingJobs =
                    Dict.insert token (BusyWithTime timestamp) model.pollingJobs
            in
            Logger.logDebug ("Updated job " ++ token ++ " with timestamp: " ++ String.fromInt timestamp) GotLogTime ( { model | pollingJobs = updatedPollingJobs }, Cmd.none )
                |> wrapLogCmd


{-| Helper to wrap Logger Cmd results into Command
-}
wrapLogCmd : ( Model, Cmd BackendMsg ) -> ( Model, Command BackendOnly ToFrontend BackendMsg )
wrapLogCmd ( m, cmd ) =
    ( m, Command.fromCmd "logger" cmd )


updateFromFrontend : Effect.Lamdera.SessionId -> Effect.Lamdera.ClientId -> ToBackend -> Model -> ( Model, Command BackendOnly ToFrontend BackendMsg )
updateFromFrontend sessionId clientId msg model =
    let
        -- Convert Effect types to strings for compatibility with existing code
        browserCookie =
            Effect.Lamdera.sessionIdToString sessionId

        connectionId =
            Effect.Lamdera.clientIdToString clientId
    in
    case msg of
        NoOpToBackend ->
            ( model, Command.none )

        Admin_FetchLogs searchQuery ->
            let
                allLogs =
                    Logger.toList model.logState

                filteredLogs =
                    if String.isEmpty searchQuery then
                        allLogs

                    else
                        allLogs
                            |> List.filter
                                (\logEntry ->
                                    String.contains (String.toLower searchQuery)
                                        (String.toLower logEntry.message)
                                )
            in
            ( model, Effect.Lamdera.sendToFrontend clientId (Admin_Logs_ToFrontend filteredLogs) )

        Admin_ClearLogs ->
            let
                logSize =
                    2000

                newModel =
                    { model | logState = Logger.init logSize }
            in
            ( newModel, Effect.Lamdera.sendToFrontend clientId (Admin_Logs_ToFrontend []) )

        Admin_FetchRemoteModel _ ->
            -- Remote model fetching removed (was RPC-based)
            ( model, Command.none )

        AuthToBackend authToBackend ->
            Auth.Flow.updateFromFrontend (backendConfig model) connectionId browserCookie authToBackend model
                |> Tuple.mapSecond (Command.fromCmd "AuthToBackend")

        EmailPasswordAuthToBackend authMsg ->
            handleEmailPasswordAuth browserCookie connectionId authMsg model
                |> Tuple.mapSecond (Command.fromCmd "EmailPasswordAuth")

        GetUserToBackend ->
            case Dict.get browserCookie model.sessions of
                Just userInfo ->
                    case getUserFromCookie browserCookie model of
                        Just user ->
                            ( model, Command.batch [ Effect.Lamdera.sendToFrontend clientId <| UserInfoMsg <| Just userInfo, Effect.Lamdera.sendToFrontend clientId <| UserDataToFrontend <| userToFrontend user ] )

                        Nothing ->
                            let
                                initialPreferences =
                                    { darkMode = True }

                                -- Default new users to dark mode
                                user =
                                    createUser userInfo initialPreferences

                                newModel =
                                    insertUser userInfo.email user model
                            in
                            ( newModel, Command.batch [ Effect.Lamdera.sendToFrontend clientId <| UserInfoMsg <| Just userInfo, Effect.Lamdera.sendToFrontend clientId <| UserDataToFrontend <| userToFrontend user ] )

                Nothing ->
                    ( model, Effect.Lamdera.sendToFrontend clientId <| UserInfoMsg Nothing )

        LoggedOut ->
            ( { model | sessions = Dict.remove browserCookie model.sessions }, Command.none )

        SetDarkModePreference preference ->
            case getUserFromCookie browserCookie model of
                Just user ->
                    let
                        -- Explicitly alias the nested record
                        currentPreferences =
                            user.preferences

                        updatedUserPreferences : Preferences
                        updatedUserPreferences =
                            { currentPreferences | darkMode = preference }

                        -- Update the alias
                        updatedUser : User
                        updatedUser =
                            { user | preferences = updatedUserPreferences }

                        updatedUsers =
                            Dict.insert user.email updatedUser model.users
                    in
                    ( { model | users = updatedUsers }, Command.none )

                Nothing ->
                    Logger.logWarn "User or session not found for SetDarkModePreference" GotLogTime ( model, Cmd.none )
                        |> wrapLogCmd

        A message ->
            -- Echo websocket message back to frontend
            ( model, Effect.Lamdera.sendToFrontend clientId (A0 ("Echo: " ++ message)) )

        MeleeToBackend message ->
            let
                directoryChanged =
                    case message of
                        Melee.Controls _ ->
                            False

                        Melee.Suspend ->
                            False

                        Melee.PreviewSubscription _ ->
                            False

                        _ ->
                            True
            in
            meleeResultWithDirectory directoryChanged model (Melee.handle browserCookie connectionId message model.melee)


updateFromFrontendCheckingRights : Effect.Lamdera.SessionId -> Effect.Lamdera.ClientId -> ToBackend -> Model -> ( Model, Command BackendOnly ToFrontend BackendMsg )
updateFromFrontendCheckingRights sessionId clientId msg model =
    let
        browserCookie =
            Effect.Lamdera.sessionIdToString sessionId
    in
    if
        case msg of
            NoOpToBackend ->
                True

            LoggedOut ->
                True

            AuthToBackend _ ->
                True

            EmailPasswordAuthToBackend _ ->
                True

            GetUserToBackend ->
                True

            SetDarkModePreference _ ->
                -- Allow everyone to set their own preference
                True

            _ ->
                sessionCanPerformAction model browserCookie msg
    then
        updateFromFrontend sessionId clientId msg model

    else
        ( model, Effect.Lamdera.sendToFrontend clientId (PermissionDenied msg) )


getUserFromCookie : BrowserCookie -> Model -> Maybe User
getUserFromCookie browserCookie model =
    Dict.get browserCookie model.sessions
        |> Maybe.andThen (\userInfo -> Dict.get userInfo.email model.users)


userToFrontend : User -> UserFrontend
userToFrontend user =
    { email = user.email
    , isSysAdmin = isSysAdmin user
    , role = getUserRole user |> roleToString
    , preferences = user.preferences
    }


handleEmailPasswordAuth : BrowserCookie -> ConnectionId -> EmailPasswordAuthToBackend -> Model -> ( Model, Cmd BackendMsg )
handleEmailPasswordAuth browserCookie connectionId authMsg model =
    case authMsg of
        EmailPasswordLoginToBackend email password ->
            EmailPasswordAuth.handleLogin browserCookie connectionId email password model

        EmailPasswordSignupToBackend email password maybeName ->
            EmailPasswordAuth.handleSignup browserCookie connectionId email password maybeName model


meleeResult : Model -> ( Melee.Host, List Melee.Delivery ) -> ( Model, Command BackendOnly ToFrontend BackendMsg )
meleeResult =
    meleeResultWithDirectory True


meleeResultWithDirectory : Bool -> Model -> ( Melee.Host, List Melee.Delivery ) -> ( Model, Command BackendOnly ToFrontend BackendMsg )
meleeResultWithDirectory checkDirectory model ( host, deliveries ) =
    let
        directory =
            if checkDirectory && not (Dict.isEmpty host.previewClients) then
                let
                    games =
                        Melee.games host

                    rooms =
                        Melee.discover host

                    sendToBrowsers message =
                        Dict.keys host.previewClients
                            |> List.map (\client -> Effect.Lamdera.sendToFrontend (Effect.Lamdera.clientIdFromString client) (MeleeToFrontend message))
                            |> Command.batch
                in
                Command.batch
                    [ if games /= Melee.games model.melee then
                        sendToBrowsers (Melee.GamesAvailable games)

                      else
                        Command.none
                    , if rooms /= Melee.discover model.melee then
                        sendToBrowsers (Melee.RoomsAvailable rooms)

                      else
                        Command.none
                    ]

            else
                Command.none
    in
    ( { model | melee = host }
    , Command.batch
        [ directory
        , deliveries |> List.map (\delivery -> Effect.Lamdera.sendToFrontend (Effect.Lamdera.clientIdFromString delivery.client) (MeleeToFrontend delivery.message)) |> Command.batch
        ]
    )
