module Melee.Room exposing (..)

import Dict exposing (Dict)
import Melee.Catalog as Catalog
import Melee.Input as Input exposing (BattleInput, Turn(..))
import Melee.Keys as Keys
import Melee.Local as Game
import Melee.Preview as Preview
import Melee.Ranking as Ranking
import Melee.Rate as Rate
import Melee.Rng exposing (Seed(..))
import Melee.RoomCode as RoomCode
import Melee.Ship exposing (ShipKind)
import Melee.Stream as Stream
import Melee.Units exposing (Side(..), Sided)


type Client
    = Browsing
    | Seated Snapshot
    | Watching SpectatorSnapshot


type LocalMsg
    = Tick
    | KeyDown String
    | KeyUp String
    | Restart


type ToHost
    = Identify
    | FindMatch
    | CancelSearch
    | SetPlayerName String
    | DiscoverRooms
    | CreateRoom
    | JoinRoom String
    | WatchRoom String
    | LeaveRoom
    | Rename String
    | Add ShipKind
    | Remove Int
    | ReplaceFleet String (List ShipKind)
    | Visit String Bool
    | PreviewSubscription Bool
    | SetController Side SeatControl
    | Ready
    | Pick Int
    | RandomPick
    | Controls BattleInput
    | Pause
    | Suspend
    | Hangar
    | Rematch


type ToSeat
    = PlayerStatus Ranking.Profile Bool
    | MatchFound Snapshot
    | RoomsAvailable (List Listing)
    | CombatDelta String Int Stream.Delta
    | ArenaPreview Preview.Preview
    | GamesAvailable (List GameListing)
    | SpectatorView SpectatorSnapshot
    | RoomSnapshot Snapshot
    | RoomLeft
    | RoomError String


type alias Snapshot =
    { code : String
    , side : Side
    , game : Game.Model
    , connected : Sided Bool
    , controllers : Sided SeatControl
    , ready : Sided Bool
    , revision : Int
    , ranked : Maybe Ranking.View
    }


type alias Seat =
    { session : String, client : Maybe String }


type alias Room =
    { code : String
    , seats : Sided (Maybe Seat)
    , game : Game.Model
    , inputs : Sided BattleInput
    , controllers : Sided SeatControl
    , ready : Sided Bool
    , revision : Int
    , lastBroadcast : Maybe Game.Model
    , broadcastAt : Int
    , spectators : Dict String String
    , touched : Int
    , ranked : Maybe Ranking.Match
    }


type alias RoomSetup =
    { names : Sided String
    , fleets : Sided (List ShipKind)
    , controllers : Sided SeatControl
    }


type alias Host =
    { rooms : Dict String Room, roomSetups : Dict String RoomSetup, clientRooms : Dict String String, nextId : Int, now : Int, previewClients : Dict String String, previewAt : Int, previewGame : Maybe Game.Model, players : Dict String Ranking.Profile, queue : List { session : String, client : String } }


type alias Delivery =
    { client : String, message : ToSeat }


init : Host
init =
    { rooms = Dict.singleton "ARENA" (exhibition 0), roomSetups = Dict.empty, clientRooms = Dict.empty, nextId = 1, now = 0, previewClients = Dict.empty, previewAt = 0, previewGame = Nothing, players = Dict.empty, queue = [] }


connected : Maybe Seat -> Bool
connected seat =
    seat |> Maybe.andThen .client |> (/=) Nothing


bothConnected : Room -> Bool
bothConnected room =
    (room.controllers.bottom == Computer || connected room.seats.bottom) && (room.controllers.top == Computer || connected room.seats.top)


findSeat : String -> String -> Room -> Maybe Side
findSeat session client room =
    [ Bottom, Top ]
        |> List.filter (\side -> Game.get side room.seats |> Maybe.map (\seat -> seat.session == session && seat.client == Just client) |> Maybe.withDefault False)
        |> List.head


findRoom : String -> String -> Host -> Maybe ( Room, Side )
findRoom session client host =
    Dict.get client host.clientRooms
        |> Maybe.andThen (\code -> Dict.get code host.rooms)
        |> Maybe.andThen (\room -> findSeat session client room |> Maybe.map (Tuple.pair room))


deliver : Room -> List Delivery
deliver room =
    ([ Bottom, Top ]
        |> List.filterMap
            (\side ->
                Game.get side room.seats
                    |> Maybe.andThen .client
                    |> Maybe.map
                        (\client ->
                            { client = client
                            , message = RoomSnapshot { code = room.code, side = side, game = room.game, connected = { bottom = connected room.seats.bottom, top = connected room.seats.top }, controllers = room.controllers, ready = room.ready, revision = room.revision, ranked = Maybe.map Ranking.view room.ranked }
                            }
                        )
            )
    )
        ++ (Dict.keys room.spectators |> List.map (\client -> { client = client, message = SpectatorView { code = room.code, game = room.game, connected = { bottom = connected room.seats.bottom, top = connected room.seats.top }, controllers = room.controllers, revision = room.revision } }))


save : Room -> Host -> ( Host, List Delivery )
save room host =
    let
        next =
            { room
                | revision = room.revision + 1
                , touched =
                    if room.code == "ARENA" then
                        room.touched

                    else
                        host.now
                , lastBroadcast = Just room.game
                , broadcastAt = host.now
            }
    in
    ( { host
        | rooms = Dict.insert room.code next host.rooms
        , clientRooms =
            let
                oldClients =
                    Dict.get room.code host.rooms |> Maybe.map seatClients |> Maybe.withDefault []

                cleared =
                    List.foldl Dict.remove host.clientRooms oldClients
            in
            List.foldl (\client -> Dict.insert client room.code) cleared (seatClients next)
        , roomSetups =
            if room.code /= "ARENA" && room.ranked == Nothing then
                Dict.insert room.code { names = room.game.names, fleets = room.game.fleets, controllers = room.controllers } host.roomSetups

            else
                host.roomSetups
      }
    , deliver next
    )


handleRoom : String -> String -> ToHost -> Host -> ( Host, List Delivery )
handleRoom session client message host =
    let
        reject reason =
            ( host, [ { client = client, message = RoomError reason } ] )

        join room side =
            let
                restored =
                    { room | seats = Game.set side (Just { session = session, client = Just client }) room.seats, spectators = Dict.remove client room.spectators, ranked = Maybe.map (\ranked -> { ranked | away = Game.set side Nothing ranked.away }) room.ranked }

                game =
                    restored.game

                resumed =
                    case game.phase of
                        Game.Paused _ ->
                            if restored.ranked /= Nothing && bothConnected restored then
                                Game.update Game.TogglePause game

                            else
                                game

                        _ ->
                            game
            in
            save { restored | game = resumed } (removeSpectator client host)
    in
    case ( message, findRoom session client host ) of
        ( DiscoverRooms, _ ) ->
            ( host, [ { client = client, message = RoomsAvailable (discover host) }, { client = client, message = GamesAvailable (games host) } ] )

        ( PreviewSubscription enabled, _ ) ->
            ( { host
                | previewClients =
                    if enabled then
                        Dict.insert client session host.previewClients

                    else
                        Dict.remove client host.previewClients
              }
            , if enabled then
                [ { client = client, message = RoomsAvailable (discover host) }, { client = client, message = GamesAvailable (games host) } ]
                    ++ (host.previewGame |> Maybe.map (\game -> [ { client = client, message = ArenaPreview (Preview.Snapshot game) } ]) |> Maybe.withDefault [])

              else
                []
            )

        ( Visit code watching, _ ) ->
            case findRoom session client host of
                Just ( room, _ ) ->
                    if room.code == code && not watching then
                        ( host, deliver room )

                    else
                        let
                            ( left, messages ) =
                                handle session client LeaveRoom host

                            ( joined, arrivals ) =
                                handle session
                                    client
                                    (if watching then
                                        WatchRoom code

                                     else
                                        JoinRoom code
                                    )
                                    left
                        in
                        ( joined, List.filter (\d -> d.client /= client) messages ++ arrivals )

                Nothing ->
                    handle session
                        client
                        (if watching then
                            WatchRoom code

                         else
                            JoinRoom code
                        )
                        host

        ( Controls input, Just ( room, side ) ) ->
            let
                next =
                    act side (Controls input) room
            in
            ( { host | rooms = Dict.insert room.code next host.rooms }, [] )

        ( Suspend, Just ( room, side ) ) ->
            ( { host | rooms = Dict.insert room.code (act side Suspend room) host.rooms }, [] )

        ( LeaveRoom, Just ( room, side ) ) ->
            let
                next =
                    { room | seats = Game.set side Nothing room.seats, inputs = Game.set side Input.idle room.inputs, ready = Game.set side False room.ready, game = Game.update Game.Suspend room.game }

                ( updated, messages ) =
                    save next host
            in
            ( { updated
                | rooms =
                    if not (connected next.seats.bottom || connected next.seats.top) then
                        Dict.remove room.code updated.rooms

                    else
                        updated.rooms
              }
            , { client = client, message = RoomLeft }
                :: (if not (connected next.seats.bottom || connected next.seats.top) then
                        List.map (\viewer -> { client = viewer, message = RoomLeft }) (Dict.keys next.spectators) ++ List.filter (\delivery -> not (Dict.member delivery.client next.spectators)) messages

                    else
                        messages
                   )
            )

        ( LeaveRoom, Nothing ) ->
            ( removeSpectator client host, [ { client = client, message = RoomLeft } ] )

        ( WatchRoom code, Nothing ) ->
            case Dict.get code host.rooms of
                Just room ->
                    if room.code == "ARENA" || connected room.seats.bottom || connected room.seats.top then
                        save { room | spectators = Dict.insert client session room.spectators } (removeSpectator client host)

                    else
                        reject "This match is no longer available."

                Nothing ->
                    reject "This match is no longer available."

        ( WatchRoom _, Just _ ) ->
            reject "Leave your player seat before watching another match."

        ( CreateRoom, Nothing ) ->
            let
                ( code, allocated ) =
                    allocateCode session client host

                room =
                    customRoom code host.now { names = Game.init.names, fleets = Game.init.fleets, controllers = { bottom = Human, top = Human } }
            in
            save { room | seats = { bottom = Just { session = session, client = Just client }, top = Nothing } } (removeSpectator client allocated)

        ( JoinRoom rawCode, Nothing ) ->
            case Dict.get (String.toUpper (String.trim rawCode)) host.rooms of
                Nothing ->
                    let
                        code =
                            String.toUpper (String.trim rawCode)
                    in
                    case Dict.get code host.roomSetups of
                        Just setup ->
                            join (customRoom code host.now setup) Bottom

                        Nothing ->
                            reject "Room not found. Check the room code."

                Just room ->
                    let
                        detached =
                            [ Bottom, Top ] |> List.filter (\side -> Game.get side room.seats |> Maybe.map (\seat -> seat.session == session && seat.client == Nothing) |> Maybe.withDefault False) |> List.head

                        empty =
                            [ Bottom, Top ] |> List.filter (\side -> Game.get side room.seats == Nothing && Game.get side room.controllers == Human) |> List.head
                    in
                    case ( detached, empty, room.game.phase ) of
                        ( Just side, _, _ ) ->
                            join room side

                        ( _, Just side, Game.Hangar ) ->
                            join room side

                        _ ->
                            reject "Room is full or the match has already started."

        ( _, Just ( room, side ) ) ->
            case message of
                CreateRoom ->
                    reject "Leave your current room first."

                JoinRoom _ ->
                    reject "Leave your current room first."

                _ ->
                    act side message room
                        |> (\next ->
                                if next == room then
                                    ( host, [] )

                                else
                                    save { next | inputs = Game.set side Input.idle next.inputs } host
                           )

        _ ->
            reject "Join a room before playing online."


act : Side -> ToHost -> Room -> Room
act side message room =
    let
        game =
            room.game

        apply msg =
            { room | game = Game.update msg game }

        edit msg =
            if game.phase == Game.Hangar then
                { room | game = Game.update msg { game | editing = side }, ready = { bottom = False, top = False } }

            else
                room
    in
    case message of
        Rename name ->
            edit (Game.Rename side name)

        Add ship ->
            edit (Game.Add ship)

        Remove index ->
            edit (Game.Remove side index)

        ReplaceFleet name fleet ->
            if game.phase == Game.Hangar && List.length fleet <= 14 then
                { room | game = { game | names = Game.set side (String.left 30 name) game.names, fleets = Game.set side fleet game.fleets }, ready = { bottom = False, top = False } }

            else
                room

        SetController target controller ->
            if game.phase == Game.Hangar && (target == side || Game.get target room.seats == Nothing) then
                let
                    controllers =
                        Game.set target controller room.controllers
                in
                { room | controllers = controllers, ready = { bottom = False, top = False }, game = { game | mode = modeFor controllers } }

            else
                room

        Ready ->
            if game.phase == Game.Hangar && not (List.isEmpty (Game.get side game.fleets)) then
                let
                    ready =
                        Game.set side (not (Game.get side room.ready)) room.ready
                in
                { room
                    | ready = ready
                    , game =
                        if (ready.bottom || room.controllers.bottom == Computer) && (ready.top || room.controllers.top == Computer) && bothConnected room then
                            Game.update Game.Start game

                        else
                            game
                }

            else
                room

        Pick index ->
            if index >= 0 && Game.get side room.controllers == Human then
                apply (Game.Pick side index)

            else
                room

        RandomPick ->
            if Game.get side room.controllers == Human then
                apply (Game.RandomPick side)

            else
                room

        Controls input ->
            case game.phase of
                Game.Combat _ ->
                    { room | inputs = Game.set side input room.inputs }

                Game.Countdown _ _ ->
                    { room | inputs = Game.set side input room.inputs }

                _ ->
                    { room | inputs = Game.set side Input.idle room.inputs }

        Pause ->
            if bothConnected room then
                { room | game = Game.update Game.TogglePause game, inputs = { bottom = Input.idle, top = Input.idle } }

            else
                room

        Suspend ->
            { room | inputs = Game.set side Input.idle room.inputs }

        Hangar ->
            { room | game = Game.update Game.Menu game, ready = { bottom = False, top = False }, inputs = { bottom = Input.idle, top = Input.idle } }

        Rematch ->
            case game.phase of
                Game.Victory _ ->
                    { room | game = Game.update Game.Menu game, ready = { bottom = False, top = False }, inputs = { bottom = Input.idle, top = Input.idle } }

                _ ->
                    room

        _ ->
            room


held : Sided BattleInput -> Keys.Held
held inputs =
    { bottomLeft = inputs.bottom.turn == TurnLeft
    , bottomRight = inputs.bottom.turn == TurnRight
    , bottomThrust = inputs.bottom.thrust
    , bottomWeapon = inputs.bottom.weapon
    , bottomSpecial = inputs.bottom.special
    , topLeft = inputs.top.turn == TurnLeft
    , topRight = inputs.top.turn == TurnRight
    , topThrust = inputs.top.thrust
    , topWeapon = inputs.top.weapon
    , topSpecial = inputs.top.special
    }


clockInterval : Host -> Maybe Float
clockInterval host =
    Dict.foldl
        (\_ room fastest ->
            let
                interval =
                    if room.code == "ARENA" then
                        if exhibitionWatched host room then
                            Just (1000 / toFloat Rate.cBattleFramesPerSecond)

                        else
                            Nothing

                    else if bothConnected room && running room.game.phase then
                        Just (1000 / toFloat Rate.cBattleFramesPerSecond)

                    else if (room.ranked |> Maybe.map (\ranked -> ranked.outcome == Nothing) |> Maybe.withDefault False) || not (connected room.seats.bottom || connected room.seats.top) then
                        Just 1000

                    else
                        Nothing
            in
            case ( fastest, interval ) of
                ( Nothing, _ ) ->
                    interval

                ( _, Nothing ) ->
                    fastest

                ( Just a, Just b ) ->
                    Just (min a b)
        )
        Nothing
        host.rooms


exhibitionWatched : Host -> Room -> Bool
exhibitionWatched host room =
    not (Dict.isEmpty host.previewClients && Dict.isEmpty room.spectators)


tickRooms : Int -> Host -> ( Host, List Delivery )
tickRooms now host =
    let
        elapsed =
            if host.now == 0 then
                0

            else
                toFloat (clamp 0 250 (now - host.now))

        step _ room ( rooms, messages ) =
            if room.code /= "ARENA" && not (connected room.seats.bottom || connected room.seats.top) && now - room.touched > 600000 then
                ( rooms, List.foldl (::) messages (List.map (\viewer -> { client = viewer, message = RoomLeft }) (Dict.keys room.spectators)) )

            else
                let
                    game =
                        if room.code == "ARENA" && not (exhibitionWatched host room) then
                            room.game

                        else if room.code == "ARENA" && isVictory room.game.phase && now - room.touched >= 4000 then
                            (exhibition room.revision).game

                        else if room.code == "ARENA" then
                            let
                                current =
                                    room.game
                            in
                            Game.advance elapsed (held room.inputs) { current | difficulty = Input.AwesomeCyborg }

                        else if bothConnected room && running room.game.phase then
                            Game.advance elapsed (held room.inputs) room.game

                        else
                            room.game

                    next =
                        if game == room.game then
                            room

                        else
                            { room
                                | game = game
                                , revision = room.revision + 1
                                , touched =
                                    if isVictory game.phase && not (isVictory room.game.phase) then
                                        now

                                    else
                                        room.touched
                            }

                    due =
                        now - room.broadcastAt >= 100 && room.lastBroadcast /= Just game && not (List.isEmpty (recipients next))

                    packet =
                        if due then
                            room.lastBroadcast |> Maybe.andThen (\before -> Stream.between (toFloat (now - room.broadcastAt)) before game)

                        else
                            Nothing

                    deliveries =
                        if not due then
                            []

                        else
                            case packet of
                                Just delta ->
                                    List.map (\client -> { client = client, message = CombatDelta room.code next.revision delta }) (recipients next)

                                Nothing ->
                                    deliver next

                    stored =
                        if due then
                            { next | lastBroadcast = Just game, broadcastAt = now }

                        else
                            next
                in
                ( Dict.insert room.code stored rooms, List.foldl (::) messages deliveries )

        rooms0 =
            if Dict.member "ARENA" host.rooms then
                host.rooms

            else
                Dict.insert "ARENA" (exhibition 0) host.rooms

        ( nextRooms, tickDeliveries ) =
            Dict.foldl step ( Dict.empty, [] ) rooms0
    in
    let
        previewDue =
            now > host.previewAt

        preview =
            if previewDue && not (Dict.isEmpty host.previewClients) then
                Dict.get "ARENA" nextRooms |> Maybe.map .game

            else
                Nothing

        previews =
            if previewDue then
                preview
                    |> Maybe.map
                        (\game ->
                            let
                                update =
                                    host.previewGame
                                        |> Maybe.andThen (\previous -> Stream.between (toFloat (now - host.previewAt)) previous game)
                                        |> Maybe.map Preview.Delta
                                        |> Maybe.withDefault (Preview.Snapshot game)
                            in
                            Dict.keys host.previewClients |> List.map (\client -> { client = client, message = ArenaPreview update })
                        )
                    |> Maybe.withDefault []

            else
                []
    in
    ( { host
        | rooms = nextRooms
        , previewGame =
            if Dict.isEmpty host.previewClients then
                Nothing

            else
                case preview of
                    Just game ->
                        Just game

                    Nothing ->
                        host.previewGame
        , now = now
        , previewAt =
            if previewDue then
                now

            else
                host.previewAt
      }
    , previews ++ tickDeliveries
    )


disconnect : String -> String -> Host -> ( Host, List Delivery )
disconnect session client originalHost =
    let
        host =
            removeSpectator client { originalHost | queue = List.filter (\entry -> entry.client /= client) originalHost.queue }
    in
    case findRoom session client host of
        Nothing ->
            ( host, [] )

        Just ( room, side ) ->
            save
                { room
                    | ranked = Maybe.map (\ranked -> { ranked | away = Game.set side (Just host.now) ranked.away }) room.ranked
                    , seats = Game.set side (Just { session = session, client = Nothing }) room.seats
                    , ready =
                        if room.ranked /= Nothing then
                            room.ready

                        else
                            Game.set side False room.ready
                    , inputs = { bottom = Input.idle, top = Input.idle }
                    , game = Game.update Game.Suspend room.game
                }
                host


reconnect : String -> String -> Host -> ( Host, List Delivery )
reconnect session client host =
    let
        matches =
            Dict.values host.rooms |> List.filterMap (\room -> [ Bottom, Top ] |> List.filter (\side -> Game.get side room.seats |> Maybe.map (\seat -> seat.session == session && seat.client == Nothing) |> Maybe.withDefault False) |> List.head |> Maybe.map (Tuple.pair room))
    in
    case matches of
        [ ( room, side ) ] ->
            let
                restored =
                    { room | ranked = Maybe.map (\ranked -> { ranked | away = Game.set side Nothing ranked.away }) room.ranked, seats = Game.set side (Just { session = session, client = Just client }) room.seats }

                game =
                    restored.game
            in
            save
                { restored
                    | game =
                        if restored.ranked /= Nothing && bothConnected restored then
                            Game.update Game.TogglePause game

                        else
                            game
                }
                host

        _ ->
            ( host, [] )


running : Game.Phase -> Bool
running phase =
    case phase of
        Game.Combat _ ->
            True

        Game.Countdown _ _ ->
            True

        Game.RoundOver _ _ ->
            True

        _ ->
            False


type alias Listing =
    { code : String, name : String, ships : Int, points : Int, fleet : List ShipKind }


discover : Host -> List Listing
discover host =
    Dict.values host.rooms
        |> List.filterMap
            (\room ->
                let
                    waitingSide =
                        if connected room.seats.bottom && room.seats.top == Nothing && room.controllers.top == Human then
                            Just Bottom

                        else if connected room.seats.top && room.seats.bottom == Nothing && room.controllers.bottom == Human then
                            Just Top

                        else
                            Nothing
                in
                if room.game.phase /= Game.Hangar then
                    Nothing

                else
                    waitingSide
                        |> Maybe.map
                            (\side ->
                                let
                                    fleet =
                                        Game.get side room.game.fleets
                                in
                                { code = room.code, name = Game.get side room.game.names, ships = List.length fleet, fleet = fleet, points = fleet |> List.map (Melee.Ship.stock >> .cost) |> List.sum }
                            )
            )


type alias SpectatorSnapshot =
    { code : String, game : Game.Model, connected : Sided Bool, controllers : Sided SeatControl, revision : Int }


type alias GameListing =
    { code : String, names : Sided String, stage : String, viewers : Int }


games : Host -> List GameListing
games host =
    Dict.values host.rooms
        |> List.filter (\room -> room.code == "ARENA" || connected room.seats.bottom || connected room.seats.top)
        |> List.map (\room -> { code = room.code, names = room.game.names, stage = stage room.game.phase, viewers = Dict.size room.spectators })


stage : Game.Phase -> String
stage phase =
    case phase of
        Game.Hangar ->
            "Fleet selection"

        Game.Selecting _ _ ->
            "Choosing ships"

        Game.Countdown _ _ ->
            "Warping in"

        Game.Combat _ ->
            "Live combat"

        Game.Paused _ ->
            "Paused"

        Game.RoundOver _ _ ->
            "Round complete"

        Game.Victory _ ->
            "Match complete"


removeSpectator : String -> Host -> Host
removeSpectator client host =
    { host | rooms = Dict.map (\_ room -> { room | spectators = Dict.remove client room.spectators }) host.rooms, previewClients = Dict.remove client host.previewClients }


type SeatControl
    = Human
    | Computer


modeFor : Sided SeatControl -> Game.Mode
modeFor controllers =
    case ( controllers.bottom, controllers.top ) of
        ( Human, Human ) ->
            Game.Versus

        ( Human, Computer ) ->
            Game.Solo

        ( Computer, Human ) ->
            Game.ReverseSolo

        ( Computer, Computer ) ->
            Game.Demo


recipients : Room -> List String
recipients room =
    ([ room.seats.bottom, room.seats.top ] |> List.filterMap (Maybe.andThen .client)) ++ Dict.keys room.spectators


isVictory phase =
    case phase of
        Game.Victory _ ->
            True

        _ ->
            False


exhibition : Int -> Room
exhibition cycle =
    let
        offset =
            modBy 25 cycle

        roster =
            List.drop offset Catalog.all ++ List.take offset Catalog.all

        base =
            Game.init

        fleets =
            { bottom = List.take 6 roster, top = List.take 6 (List.drop 6 roster) }

        game =
            Game.update Game.QuickStart { base | names = { bottom = "Solar Squadron", top = "Nebula Raiders" }, fleets = fleets, mode = Game.Demo, difficulty = Input.AwesomeCyborg, seed = Seed (1701 + cycle) }
    in
    { code = "ARENA", seats = { bottom = Nothing, top = Nothing }, controllers = { bottom = Computer, top = Computer }, game = game, inputs = { bottom = Input.idle, top = Input.idle }, ready = { bottom = True, top = True }, revision = cycle, touched = 0, spectators = Dict.empty, lastBroadcast = Nothing, broadcastAt = 0, ranked = Nothing }


identify : String -> String -> Host -> ( Host, List Delivery )
identify session client host =
    let
        profile =
            Dict.get session host.players |> Maybe.withDefault (Ranking.initial (Dict.size host.players + 1))
    in
    ( { host | players = Dict.insert session profile host.players }, [ { client = client, message = PlayerStatus profile (List.any (\entry -> entry.session == session && entry.client == client) host.queue) } ] )


handle : String -> String -> ToHost -> Host -> ( Host, List Delivery )
handle session client message host =
    case message of
        Identify ->
            identify session client host

        SetPlayerName name ->
            let
                ( known, _ ) =
                    identify session client host

                old =
                    Dict.get session known.players |> Maybe.withDefault (Ranking.initial 1)

                clean =
                    String.trim name |> String.left 24

                profile =
                    { old
                        | name =
                            if clean == "" then
                                old.name

                            else
                                clean
                    }
            in
            identify session client { known | players = Dict.insert session profile known.players }

        CancelSearch ->
            identify session client { host | queue = List.filter (\entry -> entry.session /= session) host.queue }

        FindMatch ->
            findMatch session client host

        _ ->
            let
                changingRoom =
                    case message of
                        CreateRoom ->
                            True

                        JoinRoom _ ->
                            True

                        Visit _ _ ->
                            True

                        WatchRoom _ ->
                            True

                        LeaveRoom ->
                            True

                        _ ->
                            False

                cleaned =
                    if changingRoom then
                        { host | queue = List.filter (\entry -> entry.session /= session) host.queue }

                    else
                        host

                queueMessages =
                    if cleaned.queue /= host.queue then
                        identify session client cleaned |> Tuple.second

                    else
                        []

                result =
                    case findRoom session client cleaned of
                        Just ( room, side ) ->
                            case room.ranked of
                                Just ranked ->
                                    rankedAction session client side message room ranked cleaned

                                Nothing ->
                                    handleRoom session client message cleaned

                        Nothing ->
                            handleRoom session client message cleaned
            in
            result |> Tuple.mapSecond (\messages -> queueMessages ++ messages)


findMatch : String -> String -> Host -> ( Host, List Delivery )
findMatch session client original =
    let
        ( host, status ) =
            identify session client original

        occupied =
            Dict.values host.rooms |> List.any (\room -> [ room.seats.bottom, room.seats.top ] |> List.any (\seat -> Maybe.map .session seat == Just session))
    in
    if occupied then
        ( host, [ { client = client, message = RoomError "Leave your current room before finding a match." } ] )

    else if List.any (\entry -> entry.session == session) host.queue then
        if List.any (\entry -> entry.session == session && entry.client == client) host.queue then
            ( host, status )

        else
            ( host, [ { client = client, message = RoomError "This browser is already searching in another tab." } ] )

    else
        pairWaiting { host | queue = host.queue ++ [ { session = session, client = client } ] }
            |> (\( next, messages ) -> ( next, (identify session client next |> Tuple.second) ++ messages ))


pairWaiting : Host -> ( Host, List Delivery )
pairWaiting host =
    case host.queue of
        bottom :: top :: remaining ->
            let
                bp =
                    Dict.get bottom.session host.players |> Maybe.withDefault (Ranking.initial 1)

                tp =
                    Dict.get top.session host.players |> Maybe.withDefault (Ranking.initial 2)

                ( code, allocated ) =
                    allocateCode bottom.session bottom.client host

                base =
                    Game.init

                game =
                    { base | mode = Game.Versus, names = { bottom = bp.name, top = tp.name }, fleets = { bottom = base.fleets.bottom, top = base.fleets.bottom } }

                room =
                    { code = code, seats = { bottom = Just { session = bottom.session, client = Just bottom.client }, top = Just { session = top.session, client = Just top.client } }, game = game, inputs = { bottom = Input.idle, top = Input.idle }, controllers = { bottom = Human, top = Human }, ready = { bottom = False, top = False }, revision = 0, lastBroadcast = Nothing, broadcastAt = host.now, spectators = Dict.empty, touched = host.now, ranked = Just { players = { bottom = bottom.session, top = top.session }, ratings = { bottom = bp.rating, top = tp.rating }, deadline = Just (host.now + 120000), started = False, away = { bottom = Nothing, top = Nothing }, outcome = Nothing } }

                clean =
                    removeSpectator bottom.client (removeSpectator top.client { allocated | queue = remaining })

                ( next, messages ) =
                    save room clean
            in
            ( next
            , List.map
                (\delivery ->
                    { delivery
                        | message =
                            case delivery.message of
                                RoomSnapshot snapshot ->
                                    MatchFound snapshot

                                other ->
                                    other
                    }
                )
                messages
            )

        _ ->
            ( host, [] )


rankedAction : String -> String -> Side -> ToHost -> Room -> Ranking.Match -> Host -> ( Host, List Delivery )
rankedAction session client side message room ranked host =
    let
        locked =
            ( host, [ { client = client, message = RoomError "Your ranked fleet is locked. Ready up or leave the match." } ] )

        edit =
            if ranked.started || Game.get side room.ready then
                locked

            else
                let
                    changed =
                        act side message room
                in
                if List.isEmpty (Game.get side changed.game.fleets) then
                    ( host, [ { client = client, message = RoomError "Keep at least one ship in your fleet." } ] )

                else
                    save { changed | ready = room.ready } host
    in
    case message of
        LeaveRoom ->
            let
                game =
                    room.game

                forfeited =
                    if ranked.outcome == Nothing then
                        { room
                            | game =
                                { game
                                    | phase =
                                        Game.Victory
                                            (Just
                                                (if side == Bottom then
                                                    Top

                                                 else
                                                    Bottom
                                                )
                                            )
                                }
                        }

                    else
                        room

                ( marked, first ) =
                    save forfeited host

                ( scored, awards ) =
                    settle room.code marked

                ( next, last ) =
                    handleRoom session client LeaveRoom scored
            in
            ( next, first ++ awards ++ last )

        Ready ->
            if ranked.started || Game.get side room.ready then
                ( host, [] )

            else
                let
                    next =
                        { room | ready = Game.set side True room.ready }
                in
                save
                    (if next.ready.bottom && next.ready.top then
                        launchRanked next

                     else
                        next
                    )
                    host

        Add _ ->
            edit

        Remove _ ->
            edit

        SetController _ _ ->
            locked

        Rename _ ->
            locked

        ReplaceFleet _ _ ->
            locked

        Hangar ->
            locked

        Rematch ->
            locked

        Pause ->
            ( host, [ { client = client, message = RoomError "Ranked matches cannot be paused. Disconnects have a 60-second reconnect window." } ] )

        _ ->
            handleRoom session client message host


launchRanked : Room -> Room
launchRanked room =
    { room | game = room.game |> Game.update Game.Start |> Game.update (Game.Pick Bottom 0) |> Game.update (Game.Pick Top 0), ranked = Maybe.map (\ranked -> { ranked | started = True, deadline = Nothing }) room.ranked, ready = { bottom = True, top = True } }


prepareRanked : Int -> Room -> Room
prepareRanked now room =
    case room.ranked of
        Nothing ->
            room

        Just ranked ->
            let
                game =
                    room.game

                expired value =
                    Maybe.map (\at -> now - at >= 60000) value |> Maybe.withDefault False

                choosing =
                    case game.phase of
                        Game.Selecting _ _ ->
                            True

                        _ ->
                            False
            in
            if ranked.outcome /= Nothing || isVictory game.phase then
                room

            else if expired ranked.away.bottom || expired ranked.away.top then
                { room
                    | game =
                        { game
                            | phase =
                                Game.Victory
                                    (if connected room.seats.bottom then
                                        Just Bottom

                                     else if connected room.seats.top then
                                        Just Top

                                     else
                                        Nothing
                                    )
                        }
                    , ranked = Just { ranked | started = ranked.started && (connected room.seats.bottom || connected room.seats.top), deadline = Nothing }
                }

            else if Maybe.map (\deadline -> now >= deadline) ranked.deadline == Just True && bothConnected room then
                if not ranked.started then
                    launchRanked room

                else
                    { room | game = game |> Game.update (Game.Pick Bottom 0) |> Game.update (Game.Pick Top 0), ranked = Just { ranked | deadline = Nothing } }

            else if ranked.started && choosing && ranked.deadline == Nothing then
                { room | ranked = Just { ranked | deadline = Just (now + 120000) } }

            else if ranked.started && not choosing && ranked.deadline /= Nothing then
                { room | ranked = Just { ranked | deadline = Nothing } }

            else
                room


settle : String -> Host -> ( Host, List Delivery )
settle code host =
    case Dict.get code host.rooms of
        Nothing ->
            ( host, [] )

        Just room ->
            case ( room.ranked, room.game.phase ) of
                ( Just ranked, Game.Victory winner ) ->
                    if ranked.outcome /= Nothing then
                        ( host, [] )

                    else
                        let
                            bp =
                                Dict.get ranked.players.bottom host.players |> Maybe.withDefault (Ranking.initial 1)

                            tp =
                                Dict.get ranked.players.top host.players |> Maybe.withDefault (Ranking.initial 2)

                            ( bottom, top, outcome ) =
                                if ranked.started then
                                    Ranking.rate winner bp tp

                                else
                                    ( bp, tp, Ranking.Cancelled )

                            profiles =
                                Dict.insert ranked.players.bottom bottom (Dict.insert ranked.players.top top host.players)

                            ( next, messages ) =
                                save { room | ranked = Just { ranked | outcome = Just outcome, deadline = Nothing } } { host | players = profiles }

                            updates =
                                [ ( room.seats.bottom, bottom ), ( room.seats.top, top ) ] |> List.filterMap (\( seat, profile ) -> seat |> Maybe.andThen .client |> Maybe.map (\client -> { client = client, message = PlayerStatus profile False }))
                        in
                        ( next, messages ++ updates )

                _ ->
                    ( host, [] )


sweepRanked : Int -> Host -> ( Host, List Delivery )
sweepRanked now host =
    Dict.keys host.rooms
        |> List.foldl
            (\code ( current, messages ) ->
                case Dict.get code current.rooms of
                    Nothing ->
                        ( current, messages )

                    Just room ->
                        if room.ranked == Nothing then
                            ( current, messages )

                        else
                            let
                                next =
                                    prepareRanked now room

                                ( saved, changes ) =
                                    if next == room then
                                        ( current, [] )

                                    else
                                        save next current

                                ( scored, awards ) =
                                    settle code saved
                            in
                            ( scored, List.reverse awards ++ List.reverse changes ++ messages )
            )
            ( host, [] )
        |> Tuple.mapSecond List.reverse


tick : Int -> Host -> ( Host, List Delivery )
tick now host =
    let
        ( prepared, before ) =
            sweepRanked now host

        ( advanced, during ) =
            tickRooms now prepared

        ( settled, after ) =
            sweepRanked now advanced
    in
    ( settled, before ++ during ++ after )


allocateCode : String -> String -> Host -> ( String, Host )
allocateCode session client host =
    let
        code =
            RoomCode.generate session client host.nextId

        advanced =
            { host | nextId = host.nextId + 1 }
    in
    if Dict.member code host.rooms || Dict.member code host.roomSetups then
        allocateCode session client advanced

    else
        ( code, advanced )


customRoom : String -> Int -> RoomSetup -> Room
customRoom code now setup =
    let
        base =
            Game.init
    in
    { code = code
    , seats = { bottom = Nothing, top = Nothing }
    , game = { base | names = setup.names, fleets = setup.fleets, mode = modeFor setup.controllers }
    , inputs = { bottom = Input.idle, top = Input.idle }
    , controllers = setup.controllers
    , ready = { bottom = False, top = False }
    , revision = 0
    , lastBroadcast = Nothing
    , broadcastAt = now
    , spectators = Dict.empty
    , touched = now
    , ranked = Nothing
    }


seatClients : Room -> List String
seatClients room =
    [ room.seats.bottom, room.seats.top ] |> List.filterMap (Maybe.andThen .client)
