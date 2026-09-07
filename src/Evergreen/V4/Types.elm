module Evergreen.V4.Types exposing (..)

import Browser
import Dict
import Effect.Browser.Navigation
import Evergreen.V4.Auth.Common
import Evergreen.V4.Logger
import Evergreen.V4.Melee.Keys
import Evergreen.V4.Melee.Local
import Evergreen.V4.Melee.Location
import Evergreen.V4.Melee.Menu
import Evergreen.V4.Melee.Ranking
import Evergreen.V4.Melee.Room
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
    | NotFound


type alias AdminPageModel =
    { logs : List Evergreen.V4.Logger.LogEntry
    , isAuthenticated : Bool
    , remoteUrl : String
    }


type LoginState
    = JustArrived
    | NotLogged Bool
    | LoginTokenSent
    | LoggedIn Evergreen.V4.Auth.Common.UserInfo


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
    , authFlow : Evergreen.V4.Auth.Common.Flow
    , authRedirectBaseUrl : Url.Url
    , login : LoginState
    , currentUser : Maybe UserFrontend
    , pendingAuth : Bool
    , preferences : Preferences
    , emailPasswordForm : EmailPasswordFormModel
    , profileDropdownOpen : Bool
    , loginModalOpen : Bool
    , melee : Evergreen.V4.Melee.Room.Client
    , player : Maybe Evergreen.V4.Melee.Ranking.Profile
    , playerName : String
    , searching : Bool
    , meleeVisible : Bool
    , meleeNow : Int
    , creatingRoom : Bool
    , location : Evergreen.V4.Melee.Location.Location
    , arenaPreview : Maybe Evergreen.V4.Melee.Local.Model
    , showLocalGame : Bool
    , watchableGames : List Evergreen.V4.Melee.Room.GameListing
    , availableRooms : Maybe (List Evergreen.V4.Melee.Room.Listing)
    , roomCode : String
    , meleeHeld : Evergreen.V4.Melee.Keys.Held
    , game : Evergreen.V4.Melee.Local.Model
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
    { logState : Evergreen.V4.Logger.LogState
    , pendingAuths : Dict.Dict Lamdera.SessionId Evergreen.V4.Auth.Common.PendingAuth
    , sessions : Dict.Dict Lamdera.SessionId Evergreen.V4.Auth.Common.UserInfo
    , users : Dict.Dict Email User
    , emailPasswordCredentials : Dict.Dict Email EmailPasswordCredentials
    , pollingJobs : Dict.Dict PollingToken (PollingStatus PollData)
    , melee : Evergreen.V4.Melee.Room.Host
    }


type EmailPasswordAuthToBackend
    = EmailPasswordLoginToBackend String String
    | EmailPasswordSignupToBackend String String (Maybe String)


type ToBackend
    = A String
    | Admin_ClearLogs
    | Admin_FetchLogs String
    | Admin_FetchRemoteModel String
    | AuthToBackend Evergreen.V4.Auth.Common.ToBackend
    | EmailPasswordAuthToBackend EmailPasswordAuthToBackend
    | GetUserToBackend
    | LoggedOut
    | NoOpToBackend
    | SetDarkModePreference Bool
    | MeleeToBackend Evergreen.V4.Melee.Room.ToHost


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
    | MeleeLocal Evergreen.V4.Melee.Room.LocalMsg
    | GameMsg Evergreen.V4.Melee.Local.Msg
    | MeleeFrame Float
    | Online Evergreen.V4.Melee.Room.ToHost
    | RoomCodeChanged String
    | ShowLocalGame Bool
    | NavigateMelee Evergreen.V4.Melee.Location.Location
    | PlayerNameChanged String
    | MeleeBrowser Evergreen.V4.Melee.Menu.Event
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
    | GotLogTime Evergreen.V4.Logger.Msg
    | GotRemoteModel (Result Http.Error BackendModel)
    | AuthBackendMsg Evergreen.V4.Auth.Common.BackendMsg
    | EmailPasswordAuthResult EmailPasswordAuthResult
    | GotJobTime PollingToken Int
    | GotCryptoPriceResult PollingToken (Result Http.Error String)
    | StoreTaskResult PollingToken (Result String String)


type ToFrontend
    = A0 String
    | Admin_Logs_ToFrontend (List Evergreen.V4.Logger.LogEntry)
    | AuthSuccess Evergreen.V4.Auth.Common.UserInfo
    | AuthToFrontend Evergreen.V4.Auth.Common.ToFrontend
    | NoOpToFrontend
    | PermissionDenied ToBackend
    | UserDataToFrontend UserFrontend
    | UserInfoMsg (Maybe Evergreen.V4.Auth.Common.UserInfo)
    | MeleeToFrontend Evergreen.V4.Melee.Room.ToSeat
