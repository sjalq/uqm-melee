module Evergreen.V5.Types exposing (..)

import Browser
import Dict
import Effect.Browser.Navigation
import Evergreen.V5.Auth.Common
import Evergreen.V5.Logger
import Evergreen.V5.Melee.Keys
import Evergreen.V5.Melee.Local
import Evergreen.V5.Melee.Location
import Evergreen.V5.Melee.Menu
import Evergreen.V5.Melee.Ranking
import Evergreen.V5.Melee.Room
import Evergreen.V5.Melee.Telemetry
import File
import Http
import Lamdera
import Url


type alias AdminLogsUrlParams =
    { page : Int
    , pageSize : Int
    , search : String
    }


type AdminRoute
    = AdminDefault
    | AdminLogs AdminLogsUrlParams
    | AdminFetchModel


type Route
    = Default
    | Admin AdminRoute
    | Examples
    | Melee
    | Metrics
    | NotFound


type alias AdminPageModel =
    { logs : List Evergreen.V5.Logger.LogEntry
    , isAuthenticated : Bool
    , remoteUrl : String
    }


type LoginState
    = JustArrived
    | NotLogged Bool
    | LoginTokenSent
    | LoggedIn Evergreen.V5.Auth.Common.UserInfo


type alias Email =
    String


type alias Preferences =
    { darkMode : Bool
    }


type alias UserFrontend =
    { email : Email
    , isSysAdmin : Bool
    , role : String
    , preferences : Preferences
    }


type alias EmailPasswordFormModel =
    { email : String
    , password : String
    , confirmPassword : String
    , name : String
    , isSignupMode : Bool
    , error : Maybe String
    }


type alias FrontendModel =
    { key : Effect.Browser.Navigation.Key
    , currentRoute : Route
    , adminPage : AdminPageModel
    , authFlow : Evergreen.V5.Auth.Common.Flow
    , authRedirectBaseUrl : Url.Url
    , login : LoginState
    , currentUser : Maybe UserFrontend
    , pendingAuth : Bool
    , preferences : Preferences
    , emailPasswordForm : EmailPasswordFormModel
    , profileDropdownOpen : Bool
    , loginModalOpen : Bool
    , melee : Evergreen.V5.Melee.Room.Client
    , player : Maybe Evergreen.V5.Melee.Ranking.Profile
    , playerName : String
    , searching : Bool
    , meleeVisible : Bool
    , telemetry : Evergreen.V5.Melee.Telemetry.Client
    , telemetryReply : Maybe Evergreen.V5.Melee.Telemetry.Snapshot
    , meleeNow : Int
    , creatingRoom : Bool
    , location : Evergreen.V5.Melee.Location.Location
    , arenaPreview : Maybe Evergreen.V5.Melee.Local.Model
    , showLocalGame : Bool
    , watchableGames : List Evergreen.V5.Melee.Room.GameListing
    , availableRooms : Maybe (List Evergreen.V5.Melee.Room.Listing)
    , roomCode : String
    , meleeHeld : Evergreen.V5.Melee.Keys.Held
    , game : Evergreen.V5.Melee.Local.Model
    }


type alias User =
    { email : Email
    , name : Maybe String
    , preferences : Preferences
    }


type alias EmailPasswordCredentials =
    { email : String
    , passwordHash : String
    , passwordSalt : String
    , createdAt : Int
    }


type alias PollingToken =
    String


type alias PollData =
    String


type PollingStatus a
    = Busy
    | BusyWithTime Int
    | Ready (Result String a)


type alias BackendModel =
    { logState : Evergreen.V5.Logger.LogState
    , pendingAuths : Dict.Dict Lamdera.SessionId Evergreen.V5.Auth.Common.PendingAuth
    , sessions : Dict.Dict Lamdera.SessionId Evergreen.V5.Auth.Common.UserInfo
    , users : Dict.Dict Email User
    , emailPasswordCredentials : Dict.Dict Email EmailPasswordCredentials
    , pollingJobs : Dict.Dict PollingToken (PollingStatus PollData)
    , counters : Evergreen.V5.Melee.Telemetry.Counters
    , workload : Evergreen.V5.Melee.Telemetry.Snapshot
    , melee : Evergreen.V5.Melee.Room.Host
    }


type EmailPasswordAuthToBackend
    = EmailPasswordLoginToBackend String String
    | EmailPasswordSignupToBackend String String (Maybe String)


type ToBackend
    = A String
    | Admin_ClearLogs
    | Admin_FetchLogs String
    | Admin_FetchRemoteModel String
    | AuthToBackend Evergreen.V5.Auth.Common.ToBackend
    | EmailPasswordAuthToBackend EmailPasswordAuthToBackend
    | GetUserToBackend
    | LoggedOut
    | NoOpToBackend
    | SetDarkModePreference Bool
    | Probe Int Bool
    | MeleeToBackend Evergreen.V5.Melee.Room.ToHost


type EmailPasswordFormMsg
    = EmailPasswordFormEmailChanged String
    | EmailPasswordFormPasswordChanged String
    | EmailPasswordFormConfirmPasswordChanged String
    | EmailPasswordFormNameChanged String
    | EmailPasswordFormToggleMode
    | EmailPasswordFormSubmit


type EmailPasswordAuthMsg
    = EmailPasswordFormMsg EmailPasswordFormMsg
    | EmailPasswordLoginRequested String String
    | EmailPasswordSignupRequested String String (Maybe String)


type FrontendMsg
    = UrlClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | UrlRequested Browser.UrlRequest
    | NoOpFrontendMsg
    | DirectToBackend ToBackend
    | Admin_RemoteUrlChanged String
    | Admin_LogsNavigate AdminLogsUrlParams
    | Auth0SigninRequested
    | EmailPasswordAuthMsg EmailPasswordAuthMsg
    | Logout
    | ToggleDarkMode
    | ToggleProfileDropdown
    | ToggleLoginModal
    | CloseLoginModal
    | EmailPasswordAuthError String
    | ConsoleLogClicked
    | ConsoleLogReceived String
    | CopyToClipboard String
    | ClipboardResult (Result String String)
    | MeleeLocal Evergreen.V5.Melee.Room.LocalMsg
    | GameMsg Evergreen.V5.Melee.Local.Msg
    | MeleeFrame Float
    | Online Evergreen.V5.Melee.Room.ToHost
    | RoomCodeChanged String
    | ShowLocalGame Bool
    | NavigateMelee Evergreen.V5.Melee.Location.Location
    | PlayerNameChanged String
    | MeleeBrowser Evergreen.V5.Melee.Menu.Event
    | TelemetryClock ( Int, Bool, Float )
    | MeleeClock Int
    | MeleeVisibility Bool
    | SaveFleets
    | LoadFleets
    | FleetFileSelected File.File
    | FleetFileLoaded String


type alias BrowserCookie =
    Lamdera.SessionId


type alias ConnectionId =
    Lamdera.ClientId


type EmailPasswordAuthResult
    = EmailPasswordSignupWithHash BrowserCookie ConnectionId String String (Maybe String) String String


type BackendMsg
    = NoOpBackendMsg
    | MeleeTick Int
    | MeleeConnected String String
    | MeleeDisconnected String String
    | GotLogTime Evergreen.V5.Logger.Msg
    | GotRemoteModel (Result Http.Error BackendModel)
    | AuthBackendMsg Evergreen.V5.Auth.Common.BackendMsg
    | EmailPasswordAuthResult EmailPasswordAuthResult
    | GotJobTime PollingToken Int
    | GotCryptoPriceResult PollingToken (Result Http.Error String)
    | StoreTaskResult PollingToken (Result String String)


type ToFrontend
    = A0 String
    | Admin_Logs_ToFrontend (List Evergreen.V5.Logger.LogEntry)
    | AuthSuccess Evergreen.V5.Auth.Common.UserInfo
    | AuthToFrontend Evergreen.V5.Auth.Common.ToFrontend
    | NoOpToFrontend
    | PermissionDenied ToBackend
    | UserDataToFrontend UserFrontend
    | UserInfoMsg (Maybe Evergreen.V5.Auth.Common.UserInfo)
    | ProbeReply Int (Maybe Evergreen.V5.Melee.Telemetry.Snapshot)
    | MeleeToFrontend Evergreen.V5.Melee.Room.ToSeat
