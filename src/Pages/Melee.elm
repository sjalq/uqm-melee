module Pages.Melee exposing (init, view)

import Components.Exhibition as Exhibition
import Html exposing (..)
import Html.Attributes as A
import Html.Events as E
import Html.Keyed
import Json.Decode as Decode
import Melee.Audio as Audio
import Melee.Battle
import Melee.Catalog as Catalog
import Melee.Graphics exposing (Quality(..))
import Melee.Input exposing (CyborgRating(..))
import Melee.Local as Game exposing (Mode(..), Phase(..))
import Melee.Location as Location
import Melee.Presentation as Presentation
import Melee.Ranking as Ranking
import Melee.Room as Room
import Melee.Ship as Ship exposing (ShipKind)
import Melee.ShipState as ShipState
import Melee.Space as Space
import Melee.Units exposing (FrameCount(..), Side(..))
import Melee.View
import Theme
import Types exposing (..)


init : FrontendModel -> ( FrontendModel, Cmd FrontendMsg )
init model =
    ( model, Cmd.none )


view : FrontendModel -> Theme.Colors -> Html FrontendMsg
view model _ =
    let
        game =
            model.game
    in
    div
        [ A.class ("melee-screen " ++ screenClass model)
        , A.attribute "data-playing"
            (if Room.running game.phase && not (isWatching model.melee) then
                "true"

             else
                "false"
            )
        , A.attribute "data-match"
            (case model.melee of
                Room.Seated snapshot ->
                    if snapshot.ranked /= Nothing then
                        snapshot.code

                    else
                        ""

                _ ->
                    ""
            )
        , A.attribute "data-error" game.notice
        , A.attribute "data-muted"
            (if game.sound then
                "false"

             else
                "true"
            )
        , A.style "height" "100dvh"
        , A.style "background" "#000000"
        , A.style "color" "#eaf3ff"
        , A.style "font-family" "VT323, monospace"
        , A.style "position" "relative"
        , A.tabindex 0
        , A.id "melee-game"
        , E.preventDefaultOn "keydown"
            (Decode.map
                (\key ->
                    ( NoOpFrontendMsg
                    , case game.phase of
                        Combat _ ->
                            not (isWatching model.melee) && List.member key [ "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " ", "Enter" ]

                        Countdown _ _ ->
                            not (isWatching model.melee) && List.member key [ "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " ", "Enter" ]

                        _ ->
                            False
                    )
                )
                (Decode.field "key" Decode.string)
            )
        ]
        [ Audio.music
            { game
                | sound = game.sound && model.meleeVisible
                , phase =
                    if model.melee == Room.Browsing && not model.showLocalGame then
                        model.arenaPreview |> Maybe.map .phase |> Maybe.withDefault game.phase

                    else
                        game.phase
                , survivor =
                    if model.melee == Room.Browsing && not model.showLocalGame then
                        model.arenaPreview |> Maybe.andThen .survivor

                    else
                        game.survivor
            }
        , if model.melee == Room.Browsing && game.phase /= Hangar then
            text ""

          else
            onlinePanel model
        , case game.phase of
            Hangar ->
                case model.melee of
                    Room.Browsing ->
                        if model.showLocalGame then
                            hangar model.location model.melee game

                        else
                            text ""

                    Room.Watching _ ->
                        spectatorWaiting game

                    Room.Seated snapshot ->
                        onlineFleetEditor model.location snapshot.side (snapshot.ranked /= Nothing) (snapshot.ranked /= Nothing && Game.get snapshot.side snapshot.ready) game

            Selecting bottom top ->
                selection model.melee game bottom top

            Countdown frames arena ->
                battle model.melee game arena (Just ( "WARPING IN", String.fromInt (max 1 ((frames + 29) // 30)) ))

            Combat arena ->
                battle model.melee game arena Nothing

            Paused arena ->
                battle model.melee game arena (Just ( "PAUSED", "Take a breath. Your fleet can wait." ))

            RoundOver frames arena ->
                let
                    alive =
                        Game.crew arena.combatants.bottom arena > 0
                in
                battle model.melee
                    game
                    arena
                    (if frames > Game.dittyFrames arena then
                        Nothing

                     else
                        Just
                            ( "SHIP DESTROYED"
                            , if alive then
                                "Gold holds the field"

                              else if Game.crew arena.combatants.top arena > 0 then
                                "Cyan holds the field"

                              else
                                "Mutual destruction"
                            )
                    )

            Victory winner ->
                screen
                    [ eyebrow "ENGAGEMENT COMPLETE"
                    , h1 [ A.style "font-size" "clamp(36px, 7vw, 80px)", A.style "margin" "24px 0" ]
                        [ text
                            (if isCancelled model.melee then
                                "MATCH CANCELLED"

                             else
                                case winner of
                                    Just Bottom ->
                                        "GOLD VICTORIOUS"

                                    Just Top ->
                                        "CYAN VICTORIOUS"

                                    Nothing ->
                                        "MUTUAL DESTRUCTION"
                            )
                        ]
                    , muted ("The battle is over after " ++ String.fromInt game.round ++ " engagements.")
                    , div [ A.style "display" "flex", A.style "gap" "12px", A.style "margin-top" "32px" ]
                        (if isWatching model.melee then
                            []

                         else if isRanked model.melee then
                            [ action "Back to matchmaking" Game.Menu True ]

                         else
                            [ action "Rematch" Game.Rematch True, action "Fleet hangar" Game.Menu False ]
                        )
                    ]
        ]


screen : List (Html FrontendMsg) -> Html FrontendMsg
screen children =
    div [ A.class "classic-secondary" ] children


hangar : Location.Location -> Room.Client -> Game.Model -> Html FrontendMsg
hangar location client game =
    div [ A.class "classic-hangar" ]
        [ div [ A.class "classic-fleet-screen" ]
            [ fleet client game Top
            , fleet client game Bottom
            , button
                [ A.disabled (isOnline client)
                , A.class "classic-controller top-controller"
                , E.onClick
                    (GameMsg
                        (Game.SetMode
                            (if game.mode == Versus then
                                Solo

                             else
                                Versus
                            )
                        )
                    )
                ]
                [ text
                    (if game.mode == Versus then
                        "HUMAN CONTROL"

                     else
                        "CYBORG CONTROL"
                    )
                ]
            , button
                [ A.disabled (isOnline client)
                , A.class "classic-controller bottom-controller"
                , E.onClick
                    (GameMsg
                        (Game.SetMode
                            (if game.mode == Demo then
                                Solo

                             else
                                Demo
                            )
                        )
                    )
                ]
                [ text
                    (if game.mode == Demo then
                        "CYBORG CONTROL"

                     else
                        "HUMAN CONTROL"
                    )
                ]
            , button [ A.id "start-battle", A.class "classic-launch", A.attribute "aria-label" "Choose ships and launch", A.disabled (List.isEmpty game.fleets.bottom || List.isEmpty game.fleets.top), E.onClick (GameMsg Game.Start) ]
                [ img [ A.src "/classic/meleemenu-025.png", A.alt "BATTLE!", A.style "width" "100%", A.style "height" "100%", A.style "image-rendering" "pixelated" ] [] ]
            , button [ A.class "classic-save", A.attribute "aria-label" "Save fleets", E.onClick SaveFleets ] [ text "SAVE" ]
            , button [ A.disabled (isOnline client), A.class "classic-load", A.attribute "aria-label" "Load fleets", E.onClick LoadFleets ] [ text "LOAD" ]
            , button [ A.disabled (isOnline client), A.class "classic-lower-load", A.attribute "aria-label" "Load fleet file", E.onClick LoadFleets ] [ text "LOAD" ]
            , button [ A.class "classic-lower-save", A.attribute "aria-label" "Save fleet file", E.onClick SaveFleets ] [ text "SAVE" ]
            , div [ A.class "classic-quit-cover" ] []
            ]
        , div [ A.class "classic-settings" ]
            [ localAction client "Solo vs computer" (Game.SetMode Solo) (game.mode == Solo)
            , localAction client "Two players" (Game.SetMode Versus) (game.mode == Versus)
            , localAction client "Watch computers" (Game.SetMode Demo) (game.mode == Demo)
            , graphicsButton game
            , select
                [ A.disabled (isOnline client)
                , A.attribute "aria-label" "Computer difficulty"
                , A.class "classic-select"
                , E.onInput
                    (\value ->
                        GameMsg
                            (Game.SetDifficulty
                                (if value == "standard" then
                                    StandardCyborg

                                 else if value == "awesome" then
                                    AwesomeCyborg

                                 else
                                    GoodCyborg
                                )
                            )
                    )
                ]
                [ option [ A.value "standard", A.selected (game.difficulty == StandardCyborg) ] [ text "Standard AI" ]
                , option [ A.value "good", A.selected (game.difficulty == GoodCyborg) ] [ text "Good AI" ]
                , option [ A.value "awesome", A.selected (game.difficulty == AwesomeCyborg) ] [ text "Awesome AI" ]
                ]
            ]
        , if game.notice == "" then
            text ""

          else
            p [ A.class "melee-message", A.attribute "role" "status" ] [ text game.notice ]
        , div [ A.class "hangar-catalog", A.attribute "aria-label" "Ship catalog" ]
            [ div [ A.class "hangar-catalog-title" ] [ span [] [ text "SHIPYARD" ], span [] [ text "25 VESSELS" ] ]
            , div [ A.class "hangar-fleet-targets", A.attribute "aria-label" "Fleet to edit" ]
                (List.map
                    (\side ->
                        button
                            [ A.class
                                (if game.editing == side then
                                    "fleet-target is-target"

                                 else
                                    "fleet-target"
                                )
                            , A.attribute "aria-pressed"
                                (if game.editing == side then
                                    "true"

                                 else
                                    "false"
                                )
                            , E.onClick (GameMsg (Game.Edit side))
                            ]
                            [ text
                                ((if game.editing == side then
                                    "▶ "

                                  else
                                    ""
                                 )
                                    ++ String.toUpper (sideName side)
                                )
                            ]
                    )
                    [ Bottom, Top ]
                )
            , div [ A.class "classic-roster" ] (List.map (hangarShipCard game) Catalog.all)
            , div [ A.class "hangar-catalog-footer", A.attribute "role" "status" ]
                [ span [] [ text (String.fromInt (List.length (Game.get game.editing game.fleets)) ++ " / 14 SHIPS") ]
                , span []
                    [ text
                        (if List.length (Game.get game.editing game.fleets) >= 14 then
                            "FLEET FULL"

                         else
                            "SELECT A SHIP TO ADD"
                        )
                    ]
                ]
            , div [ A.class "hangar-key-hints" ] [ text "ARROWS · MOVE     ENTER · ADD     CLICK FLEET SHIP · REMOVE" ]
            ]
        ]


hangarShipCard : Game.Model -> ShipKind -> Html FrontendMsg
hangarShipCard game ship =
    let
        info =
            Catalog.info ship

        count =
            Game.get game.editing game.fleets |> List.filter ((==) ship) |> List.length
    in
    button
        [ A.class "classic-roster-ship hangar-ship"
        , A.attribute "aria-label" ("Add " ++ info.name)
        , A.title (info.name ++ " / " ++ info.vessel ++ " / " ++ info.help)
        , A.disabled (List.length (Game.get game.editing game.fleets) >= 14)
        , E.onClick (GameMsg (Game.Add ship))
        ]
        [ img [ A.src info.icon, A.alt "" ] []
        , span [ A.class "hangar-ship-name" ] [ text info.name ]
        , small [ A.class "hangar-ship-cost" ] [ text (String.fromInt (Ship.stock ship).cost) ]
        , if count > 0 then
            span [ A.class "hangar-ship-count", A.attribute "aria-label" (String.fromInt count ++ " in fleet") ] [ text ("×" ++ String.fromInt count) ]

          else
            text ""
        ]


fleet : Room.Client -> Game.Model -> Side -> Html FrontendMsg
fleet client game side =
    let
        ships =
            Game.get side game.fleets
    in
    div
        [ A.class
            ("classic-fleet "
                ++ (if game.editing == side then
                        "editing-fleet "

                    else
                        ""
                   )
                ++ (if side == Top then
                        "fleet-top"

                    else
                        "fleet-bottom"
                   )
            )
        ]
        [ div [ A.class "classic-slots" ]
            (List.range 0 13
                |> List.map
                    (\index ->
                        case List.drop index ships |> List.head of
                            Just ship ->
                                button [ A.disabled (not (canEdit client side)), A.class "classic-slot occupied", A.attribute "aria-label" ("Remove " ++ (Catalog.info ship).name ++ " from " ++ sideName side), A.title (Catalog.info ship).help, E.onClick (GameMsg (Game.Remove side index)) ]
                                    [ img [ A.src (Catalog.info ship).icon, A.alt (Catalog.info ship).name ] [] ]

                            Nothing ->
                                button
                                    [ A.disabled (not (canEdit client side))
                                    , A.class
                                        ("classic-slot "
                                            ++ (if game.editing == side && index == List.length ships then
                                                    "selected-fleet"

                                                else
                                                    ""
                                               )
                                        )
                                    , A.attribute "aria-label" ("Add ship to " ++ sideName side)
                                    , E.onClick (GameMsg (Game.Edit side))
                                    ]
                                    [ if game.editing == side && index == List.length ships then
                                        span [ A.class "empty-slot-cursor", A.attribute "aria-hidden" "true" ] [ text "+" ]

                                      else
                                        text ""
                                    ]
                    )
            )
        , div [ A.class "classic-team-name" ]
            [ input [ A.value (Game.get side game.names), A.maxlength 30, A.attribute "aria-label" (sideName side ++ " name"), A.disabled (not (canEdit client side)), E.onInput (GameMsg << Game.Rename side) ] []
            , span [] [ text (String.fromInt (List.sum (List.map (Ship.stock >> .cost) ships))) ]
            ]
        ]


shipCard : Game.Model -> ShipKind -> Html FrontendMsg
shipCard game ship =
    let
        info =
            Catalog.info ship
    in
    button [ A.class "classic-roster-ship", A.attribute "aria-label" ("Add " ++ info.name), A.title (info.name ++ " / " ++ info.vessel ++ " / " ++ info.help), E.onClick (GameMsg (Game.Add ship)), A.disabled (List.length (Game.get game.editing game.fleets) >= 14) ]
        [ img [ A.src info.icon, A.alt "" ] []
        , span [] [ text info.name ]
        , small [] [ text (String.fromInt (Ship.stock ship).cost) ]
        ]


selection : Room.Client -> Game.Model -> Maybe ShipKind -> Maybe ShipKind -> Html FrontendMsg
selection client game bottom top =
    let
        pick side selected =
            div [ A.class "ship-choice-panel", A.style "padding" "24px", A.style "background" "#070730", A.style "border" ("1px solid " ++ accent side), A.style "border-radius" "0px", A.style "flex" "1 1 350px" ]
                [ eyebrow (sideName side)
                , case selected of
                    Just ship ->
                        div [ A.style "margin" "25px 0" ] [ text ((Catalog.info ship).name ++ " ready") ]

                    Nothing ->
                        div [ A.class "ship-pick-options", A.style "display" "flex", A.style "gap" "10px", A.style "flex-wrap" "wrap", A.style "margin-top" "24px" ]
                            (List.indexedMap (\index ship -> seatAction client side (Catalog.info ship).name (Game.Pick side index) False) (Game.get side game.remaining)
                                ++ [ seatAction client side "Random ship" (Game.RandomPick side) True ]
                            )
                ]
    in
    screen
        [ eyebrow "DEPLOYMENT"
        , h1 [ A.style "font-size" "42px", A.style "margin" "24px 0" ] [ text "Choose your next ship" ]
        , muted "The surviving ship keeps its crew and energy. Destroy every opposing ship to win."
        , div [ A.class "ship-choices", A.style "display" "flex", A.style "gap" "24px", A.style "flex-wrap" "wrap", A.style "margin" "32px 0" ] [ pick Bottom bottom, pick Top top ]
        , if isWatching client then
            text ""

          else
            action "Back to hangar" Game.Menu False
        , controls client
        ]


battle : Room.Client -> Game.Model -> Melee.Battle.Arena -> Maybe ( String, String ) -> Html FrontendMsg
battle client game arena overlay =
    div [ A.class "classic-battle-page" ]
        [ Audio.effects game
        , div [ A.class "classic-battle-toolbar" ]
            [ if isWatching client || isRanked client then
                text ""

              else
                action "Pause / resume" Game.TogglePause False
            , graphicsButton game
            , action
                (if game.sound then
                    "Sound on"

                 else
                    "Sound off"
                )
                Game.ToggleSound
                False
            , span [ A.class "round-label" ] [ text ("ROUND " ++ String.fromInt game.round ++ " · " ++ String.fromInt (List.length game.remaining.bottom) ++ " vs " ++ String.fromInt (List.length game.remaining.top)) ]
            ]
        , div [ A.class "classic-battle-frame" ]
            [ Melee.View.viewCockpitWithControls (pilotControls client game) game.graphics game.zoomWidth arena
            , case overlay of
                Nothing ->
                    text ""

                Just ( title, subtitle ) ->
                    div [ A.class "classic-overlay" ]
                        [ eyebrow title
                        , div [] [ text subtitle ]
                        , case game.phase of
                            Paused _ ->
                                if isWatching client then
                                    text "The players have paused this match."

                                else
                                    div [ A.class "classic-settings" ] [ action "Resume" Game.TogglePause True, action "Return to hangar" Game.Menu False ]

                            _ ->
                                text ""
                        ]
            ]
        , div [ A.style "padding" "8px 16px", A.style "font-size" "16px", A.attribute "aria-label" "Ship abilities" ]
            (List.map
                (\side ->
                    let
                        info =
                            Catalog.info (ShipState.kind (Game.get side arena.combatants))
                    in
                    div [] [ text (sideName side ++ " · " ++ info.name ++ ": " ++ info.help) ]
                )
                [ Bottom, Top ]
            )
        , if isWatching client then
            text ""

          else
            div [ A.class "touch-controls" ] (List.map touch [ ( "↶", "ArrowLeft" ), ( "↷", "ArrowRight" ), ( "THRUST", "ArrowUp" ), ( "FIRE", "Enter" ), ( "SPECIAL", "Shift" ) ])
        ]


touch : ( String, String ) -> Html FrontendMsg
touch ( label, key ) =
    button
        (buttonAttrs False
            ++ [ E.on "pointerdown" (Decode.succeed (MeleeLocal (Room.KeyDown key)))
               , E.on "pointerup" (Decode.succeed (MeleeLocal (Room.KeyUp key)))
               , E.on "pointerleave" (Decode.succeed (MeleeLocal (Room.KeyUp key)))
               , E.on "pointercancel" (Decode.succeed (MeleeLocal (Room.KeyUp key)))
               , A.style "touch-action" "none"
               , A.style "user-select" "none"
               , A.style "padding" "10px"
               , A.style "font-size" "11px"
               ]
        )
        [ text label ]


controls : Room.Client -> Html msg
controls client =
    if isWatching client then
        text ""

    else
        div [ A.style "margin-top" "30px", A.style "padding-top" "20px", A.style "border-top" "1px solid #34445b", A.style "font-family" "VT323, monospace", A.style "font-size" "18px", A.style "line-height" "1.9", A.style "color" "#b5c8dd" ]
            [ div []
                [ text
                    (if isOnline client then
                        "YOUR SHIP   ← → turn · ↑ thrust · Enter fire · Shift special"

                     else
                        "GOLD   ← → turn · ↑ thrust · Enter fire · Shift special"
                    )
                ]
            , if isOnline client then
                text ""

              else
                div [] [ text "CYAN   A / D turn · W thrust · J fire · K special" ]
            , div [] [ text "Esc or P to pause. Touch controls are available during battle." ]
            ]


action : String -> Game.Msg -> Bool -> Html FrontendMsg
action label msg primary =
    button (buttonAttrs primary ++ [ E.onClick (GameMsg msg) ]) [ text label ]


buttonAttrs : Bool -> List (Attribute msg)
buttonAttrs primary =
    [ A.class
        (if primary then
            "classic-button active"

         else
            "classic-button"
        )
    ]


eyebrow : String -> Html msg
eyebrow label =
    div [ A.style "font-size" "20px", A.style "letter-spacing" "2px", A.style "color" "#7de5ff", A.style "line-height" "1.8" ] [ text label ]


muted : String -> Html msg
muted label =
    p [ A.style "font-family" "VT323, monospace", A.style "color" "#b0c5df", A.style "font-size" "20px", A.style "line-height" "1.7" ] [ text label ]


sideName : Side -> String
sideName side =
    if side == Bottom then
        "GOLD FLEET"

    else
        "CYAN FLEET"


accent : Side -> String
accent side =
    if side == Bottom then
        "#f2c66d"

    else
        "#d050e8"


graphicsButton : Game.Model -> Html FrontendMsg
graphicsButton game =
    action
        (if game.graphics == HighDefinition then
            "Graphics: HD"

         else
            "Graphics: original"
        )
        Game.ToggleGraphics
        False


onlinePanel : FrontendModel -> Html FrontendMsg
onlinePanel model =
    let
        command label message primary =
            button (buttonAttrs primary ++ [ E.onClick (Online message) ]) [ text label ]

        title name subtitle =
            div [ A.class "room-heading" ] [ h1 [] [ text name ], p [] [ text subtitle ] ]

        location =
            model.location

        openRooms =
            Maybe.withDefault [] model.availableRooms

        seat snapshot side =
            let
                controller =
                    Game.get side snapshot.controllers

                occupied =
                    Game.get side snapshot.connected

                editable =
                    snapshot.ranked == Nothing && (side == snapshot.side || not occupied)

                ready =
                    controller == Room.Computer || Game.get side snapshot.ready
            in
            div
                [ A.class
                    ("room-seat "
                        ++ (if side == Bottom then
                                "gold-seat"

                            else
                                "cyan-seat"
                           )
                    )
                ]
                [ div [ A.class "room-seat-heading" ]
                    [ text (sideName side)
                    , span [ A.class "room-badge" ]
                        [ text
                            (if controller == Room.Computer then
                                "COMPUTER"

                             else if side == snapshot.side then
                                "YOU"

                             else if occupied then
                                "CONNECTED"

                             else
                                "OPEN SEAT"
                            )
                        ]
                    ]
                , h2 [] [ text (Game.get side model.game.names) ]
                , div [ A.class "room-fleet-preview" ] (List.map (\ship -> img [ A.src (Catalog.info ship).icon, A.alt (Catalog.info ship).name, A.title (Catalog.info ship).name ] []) (Game.get side model.game.fleets))
                , case snapshot.ranked of
                    Just ranked ->
                        p [ A.class "room-control-label" ] [ text ("Human pilot · " ++ String.fromInt (Game.get side ranked.ratings) ++ " Elo") ]

                    Nothing ->
                        label [ A.class "room-control-label" ]
                            [ text "Controlled by"
                            , select
                                [ A.class "classic-select"
                                , A.attribute "aria-label" (sideName side ++ " controller")
                                , A.disabled (not editable || model.game.phase /= Hangar)
                                , E.onInput
                                    (\value ->
                                        Online
                                            (Room.SetController side
                                                (if value == "computer" then
                                                    Room.Computer

                                                 else
                                                    Room.Human
                                                )
                                            )
                                    )
                                ]
                                [ option [ A.value "human", A.selected (controller == Room.Human) ] [ text "Human" ], option [ A.value "computer", A.selected (controller == Room.Computer) ] [ text "Computer" ] ]
                            ]
                , p [ A.class "room-seat-status" ]
                    [ text
                        (if controller == Room.Computer then
                            "AI pilot ready"

                         else if not occupied then
                            "Waiting for a player to join"

                         else if ready then
                            "Ready for launch"

                         else
                            "Choosing fleet"
                        )
                    ]
                ]
    in
    section [ A.class "room-shell", A.attribute "aria-label" "Online multiplayer" ]
        (case model.melee of
            Room.Browsing ->
                [ div [ A.class "room-masthead" ]
                    [ title "SUPER MELEE" "Arrows to choose · Enter to select · Esc to return"
                    , div [ A.class "room-tabs" ]
                        [ button (buttonAttrs (not model.showLocalGame) ++ [ E.onClick (ShowLocalGame False) ]) [ text "Online arena" ]
                        , button (buttonAttrs model.showLocalGame ++ [ E.onClick (ShowLocalGame True) ]) [ text "Local play" ]
                        ]
                    ]
                , if model.showLocalGame then
                    text ""

                  else
                    div [ A.class "lobby-layout" ]
                        [ Exhibition.view { game = model.arenaPreview, sound = model.game.sound && model.meleeVisible, onToggleSound = GameMsg Game.ToggleSound, onWatch = Online (Room.WatchRoom "ARENA") }
                        , div [ A.class "room-browser" ]
                            [ matchmaking model
                            , if model.game.notice == "" then
                                text ""

                              else
                                p [ A.class "room-error", A.attribute "role" "alert" ] [ text model.game.notice ]
                            , div [ A.class "room-browser-actions" ]
                                [ div [] [ h2 [] [ text "Find your next battle" ], p [] [ text "Join an open seat, host a match, or watch another crew fight." ] ]
                                , button (buttonAttrs True ++ [ A.id "create-room", E.onClick (Online Room.CreateRoom) ]) [ text "+ Create online room" ]
                                ]
                            , div [ A.class "room-invite" ]
                                [ label [ A.for "invite-code" ] [ text "Have a room code?" ]
                                , input [ A.id "invite-code", A.class "melee-room-code", A.value model.roomCode, A.attribute "aria-label" "Room code", A.placeholder "Room code", E.onInput RoomCodeChanged ] []
                                , button (buttonAttrs False ++ [ A.id "join-room", A.disabled (String.trim model.roomCode == ""), E.onClick (Online (Room.JoinRoom model.roomCode)) ]) [ text "Join room" ]
                                ]
                            , div [ A.class "directory-tabs" ]
                                [ button (buttonAttrs (not location.watchingList) ++ [ E.onClick (NavigateMelee { location | watchingList = False, page = 0 }) ]) [ text ("Open seats · " ++ String.fromInt (List.length openRooms)) ]
                                , button (buttonAttrs location.watchingList ++ [ E.onClick (NavigateMelee { location | watchingList = True, page = 0 }) ]) [ text ("Watch matches · " ++ String.fromInt (List.length model.watchableGames)) ]
                                , command "Refresh rooms" Room.DiscoverRooms False
                                ]
                            , if location.watchingList then
                                text ""

                              else
                                section [ A.id "available-rooms", A.class "room-list", A.attribute "aria-label" "Available rooms" ]
                                    [ div [ A.class "room-list-heading" ] [ h2 [] [ text ("Open seats · " ++ String.fromInt (List.length openRooms)) ] ]
                                    , case model.availableRooms of
                                        Nothing ->
                                            div [ A.class "room-empty", A.attribute "role" "status" ] [ h3 [] [ text "Scanning the arena" ], p [] [ text "Finding available opponents…" ] ]

                                        Just [] ->
                                            div [ A.class "room-empty", A.attribute "role" "status" ] [ h3 [] [ text "The arena is clear" ], p [] [ text "Create a room to invite a human opponent or battle a computer." ] ]

                                        Just rooms ->
                                            div [ A.class "room-rows" ]
                                                (List.map
                                                    (\room ->
                                                        article [ A.class "room-row" ]
                                                            [ div [ A.class "room-ship-icons" ] (List.map (\ship -> img [ A.src (Catalog.info ship).icon, A.alt (Catalog.info ship).name ] []) (List.take 3 room.fleet))
                                                            , div [ A.class "room-row-details" ] [ span [ A.class "room-badge" ] [ text "OPEN SEAT" ], h3 [] [ text (room.name ++ " · " ++ room.code) ], p [] [ text (String.fromInt room.ships ++ " ships · " ++ String.fromInt room.points ++ " fleet points") ] ]
                                                            , div [ A.class "room-row-actions" ] [ button (buttonAttrs True ++ [ A.attribute "aria-label" ("Join " ++ room.code), E.onClick (Online (Room.JoinRoom room.code)) ]) [ text "Join battle" ], button (buttonAttrs False ++ [ E.onClick (Online (Room.WatchRoom room.code)), A.attribute "aria-label" ("Watch " ++ room.code) ]) [ text "Watch" ] ]
                                                            ]
                                                    )
                                                    (pageItems 2 location.page rooms)
                                                )
                                    ]
                            , if not location.watchingList then
                                text ""

                              else
                                section [ A.class "room-list", A.attribute "aria-label" "Watch games" ]
                                    [ div [ A.class "room-list-heading" ] [ h2 [] [ text "Watch the arena" ], span [] [ text "Spectators welcome" ] ]
                                    , if List.isEmpty model.watchableGames then
                                        div [ A.class "room-empty" ] [ p [] [ text "Matches will appear here when a room opens." ] ]

                                      else
                                        div [ A.class "room-rows" ]
                                            (List.map
                                                (\game ->
                                                    article [ A.class "room-row" ]
                                                        [ div [ A.class "room-row-details" ] [ span [ A.class "room-badge live-badge" ] [ text (String.toUpper game.stage) ], h3 [] [ text (game.names.bottom ++ " vs " ++ game.names.top) ], p [] [ text (game.code ++ " · " ++ String.fromInt game.viewers ++ " watching") ] ]
                                                        , button (buttonAttrs False ++ [ E.onClick (Online (Room.WatchRoom game.code)), A.attribute "aria-label" ("Spectate " ++ game.code) ]) [ text "Watch match" ]
                                                        ]
                                                )
                                                (pageItems 2 location.page model.watchableGames)
                                            )
                                    ]
                            , pageControls location
                                False
                                (if location.watchingList then
                                    List.length model.watchableGames

                                 else
                                    List.length openRooms
                                )
                            ]
                        ]
                ]

            Room.Seated snapshot ->
                [ div [ A.class "room-masthead" ]
                    [ title
                        ((if snapshot.ranked /= Nothing then
                            "RANKED "

                          else
                            "ROOM "
                         )
                            ++ snapshot.code
                        )
                        (if snapshot.ranked /= Nothing then
                            "Equal starting fleets. Choose your ships, then ready up."

                         else
                            "Share this code with a friend, or assign a computer pilot."
                        )
                    , command "Leave online room" Room.LeaveRoom False
                    ]
                , span [ A.id "room-status", A.class "room-context" ] [ text ("You: " ++ sideName snapshot.side ++ " · " ++ snapshot.code) ]
                , rankedStatus model snapshot
                , if model.game.phase == Hangar then
                    div []
                        [ div [ A.class "room-seats" ] [ seat snapshot Bottom, seat snapshot Top ]
                        , div [ A.class "room-launch-bar" ]
                            [ p []
                                [ text
                                    (if snapshot.ranked /= Nothing then
                                        "Ready locks your fleet. The first ship in your fleet launches first."

                                     else
                                        "Choose Human or Computer for each side. Human players must both confirm readiness."
                                    )
                                ]
                            , button (buttonAttrs True ++ [ A.id "ready-online", A.disabled (snapshot.ranked /= Nothing && Game.get snapshot.side snapshot.ready), E.onClick (Online Room.Ready) ])
                                [ text
                                    (if snapshot.controllers.bottom == Room.Computer && snapshot.controllers.top == Room.Computer then
                                        "Launch computer battle"

                                     else if Game.get snapshot.side snapshot.ready then
                                        if snapshot.ranked /= Nothing then
                                            "Ready · locked"

                                        else
                                            "Ready · cancel"

                                     else
                                        "Ready to battle"
                                    )
                                ]
                            ]
                        ]

                  else
                    p [ A.class "room-context" ] [ text "Arrows to fly · Enter to fire · Shift for special" ]
                ]

            Room.Watching snapshot ->
                [ div [ A.class "room-masthead" ]
                    [ title "SPECTATOR VIEW" (snapshot.game.names.bottom ++ " vs " ++ snapshot.game.names.top)
                    , command "Back to rooms" Room.LeaveRoom False
                    ]
                , p [ A.class "room-context" ] [ text (snapshot.code ++ " · " ++ Room.stage snapshot.game.phase ++ " · Watching only") ]
                ]
        )


isWatching : Room.Client -> Bool
isWatching client =
    case client of
        Room.Watching _ ->
            True

        _ ->
            False


spectatorWaiting : Game.Model -> Html FrontendMsg
spectatorWaiting game =
    section [ A.class "room-shell room-empty" ]
        [ h2 [] [ text "The pilots are preparing their fleets" ]
        , p [] [ text "The battle will appear here automatically when they launch." ]
        , graphicsButton game
        ]


isOnline : Room.Client -> Bool
isOnline client =
    client /= Room.Browsing


canEdit : Room.Client -> Side -> Bool
canEdit client side =
    case client of
        Room.Browsing ->
            True

        Room.Watching _ ->
            False

        Room.Seated snapshot ->
            snapshot.side == side


seatAction : Room.Client -> Side -> String -> Game.Msg -> Bool -> Html FrontendMsg
seatAction client side label message primary =
    button (buttonAttrs primary ++ [ A.disabled (not (canEdit client side)), E.onClick (GameMsg message) ]) [ text label ]


localAction : Room.Client -> String -> Game.Msg -> Bool -> Html FrontendMsg
localAction client label message primary =
    if isOnline client then
        text ""

    else
        action label message primary


onlineFleetEditor : Location.Location -> Side -> Bool -> Bool -> Game.Model -> Html FrontendMsg
onlineFleetEditor location side ranked locked game =
    fieldset [ A.class "room-shell room-fleet-editor", A.disabled locked ]
        [ div [ A.class "room-list-heading" ] [ h2 [] [ text "Assemble your fleet" ], span [] [ text (String.fromInt (List.length (Game.get side game.fleets)) ++ " / 14 ships") ] ]
        , label [ A.class "room-control-label" ]
            [ text "Fleet name"
            , input [ A.disabled ranked, A.class "melee-room-code", A.value (Game.get side game.names), A.attribute "aria-label" (sideName side ++ " name"), A.maxlength 30, E.onInput (GameMsg << Game.Rename side) ] []
            ]
        , div [ A.class "room-chosen-fleet" ] (List.indexedMap (\index ship -> button [ A.class "room-chosen-ship", A.title ("Remove " ++ (Catalog.info ship).name), A.attribute "aria-label" ("Remove " ++ (Catalog.info ship).name ++ " from " ++ sideName side), E.onClick (GameMsg (Game.Remove side index)) ] [ img [ A.src (Catalog.info ship).icon, A.alt "" ] [], span [] [ text ((Catalog.info ship).name ++ " ×") ] ]) (Game.get side game.fleets))
        , p [ A.class "room-context" ] [ text "Select a ship below to add it. Select a ship in your fleet to remove it." ]
        , div [ A.class "classic-roster" ] (List.map (shipCard game) (pageItems 10 location.roster Catalog.all))
        , pageControls location True 25
        ]


pageItems : Int -> Int -> List a -> List a
pageItems size requested items =
    List.drop (clamp 0 (max 0 ((List.length items - 1) // size)) requested * size) items |> List.take size


pageControls : Location.Location -> Bool -> Int -> Html FrontendMsg
pageControls location roster count =
    let
        size =
            if roster then
                10

            else
                2

        last =
            max 0 ((count - 1) // size)

        page =
            clamp 0
                last
                (if roster then
                    location.roster

                 else
                    location.page
                )

        target n =
            if roster then
                { location | roster = n }

            else
                { location | page = n }
    in
    div [ A.class "menu-pagination" ]
        [ button (buttonAttrs False ++ [ A.disabled (page == 0), E.onClick (NavigateMelee (target (page - 1))) ]) [ text "← Previous" ]
        , span [] [ text (String.fromInt (page + 1) ++ " / " ++ String.fromInt (last + 1)) ]
        , button (buttonAttrs False ++ [ A.disabled (page == last), E.onClick (NavigateMelee (target (page + 1))) ]) [ text "Next →" ]
        ]


screenClass : FrontendModel -> String
screenClass model =
    case model.game.phase of
        Hangar ->
            case model.melee of
                Room.Browsing ->
                    if model.showLocalGame then
                        "local-screen"

                    else
                        "lobby-screen"

                Room.Seated _ ->
                    "setup-screen"

                Room.Watching _ ->
                    "waiting-screen"

        Selecting _ _ ->
            "pick-screen"

        Victory _ ->
            "result-screen"

        _ ->
            "battle-screen"


isRanked : Room.Client -> Bool
isRanked client =
    case client of
        Room.Seated snapshot ->
            snapshot.ranked /= Nothing

        _ ->
            False


isCancelled : Room.Client -> Bool
isCancelled client =
    case client of
        Room.Seated snapshot ->
            (snapshot.ranked |> Maybe.andThen .outcome) == Just Ranking.Cancelled

        _ ->
            False


matchmaking : FrontendModel -> Html FrontendMsg
matchmaking model =
    let
        profile =
            Maybe.withDefault (Ranking.initial 1) model.player

        location =
            Location.lobby
    in
    section [ A.class "matchmaking-panel", A.attribute "aria-label" "Matchmaking" ]
        [ div [ A.class "pilot-profile" ]
            [ label [ A.for "pilot-name" ] [ text "Pilot name" ]
            , input [ A.id "pilot-name", A.value model.playerName, A.maxlength 24, A.placeholder "Optional name", E.onInput PlayerNameChanged ] []
            , button (buttonAttrs False ++ [ A.id "save-pilot-name", A.disabled (model.playerName == profile.name), E.onClick (Online (Room.SetPlayerName model.playerName)) ]) [ text "Save name" ]
            , span [ A.class "pilot-rating" ] [ text (String.fromInt profile.rating ++ " Elo · " ++ String.fromInt profile.wins ++ "W " ++ String.fromInt profile.losses ++ "L") ]
            ]
        , div [ A.class "matchmaking-actions" ]
            [ div [ A.class "queue-status", A.attribute "role" "status" ]
                [ text
                    (if model.searching then
                        "Searching for an opponent…"

                     else
                        "Ranked duel · first available opponent"
                    )
                ]
            , button
                (buttonAttrs True
                    ++ [ A.id "find-match"
                       , E.onClick
                            (Online
                                (if model.searching then
                                    Room.CancelSearch

                                 else
                                    Room.FindMatch
                                )
                            )
                       ]
                )
                [ text
                    (if model.searching then
                        "Cancel search"

                     else
                        "Find match"
                    )
                ]
            , button (buttonAttrs False ++ [ A.id "shared-pc", E.onClick (NavigateMelee { location | local = True, mode = Versus }) ]) [ text "2 players · 1 PC" ]
            ]
        ]


rankedStatus : FrontendModel -> Room.Snapshot -> Html FrontendMsg
rankedStatus model snapshot =
    case snapshot.ranked of
        Nothing ->
            text ""

        Just ranked ->
            div [ A.class "ranked-status", A.attribute "role" "status" ]
                [ case ranked.outcome of
                    Just Ranking.Cancelled ->
                        text "Cancelled before a completed duel. Elo unchanged."

                    Just (Ranking.Scored result) ->
                        let
                            change =
                                Game.get snapshot.side result.changes
                        in
                        text
                            ((if change >= 0 then
                                "+"

                              else
                                ""
                             )
                                ++ String.fromInt change
                                ++ " Elo · Rating "
                                ++ String.fromInt (Game.get snapshot.side result.ratings)
                            )

                    Nothing ->
                        case ranked.deadline of
                            Nothing ->
                                text "Ranked duel · 60 seconds to reconnect if disconnected"

                            Just deadline ->
                                let
                                    seconds =
                                        Presentation.remainingSeconds model.meleeNow deadline
                                in
                                div
                                    [ A.id "draft-timer"
                                    , A.class
                                        ("draft-countdown"
                                            ++ (if seconds <= 10 then
                                                    " countdown-urgent"

                                                else
                                                    ""
                                               )
                                        )
                                    , A.attribute "data-seconds" (String.fromInt seconds)
                                    , A.attribute "data-muted"
                                        (if model.game.sound then
                                            "false"

                                         else
                                            "true"
                                        )
                                    , A.attribute "aria-live" "off"
                                    ]
                                    [ div [ A.class "countdown-copy" ]
                                        [ strong [] [ text "CHOOSE YOUR SHIPS" ]
                                        , small [] [ text "Auto-launch when time runs out" ]
                                        ]
                                    , span [ A.class "countdown-digits", A.attribute "role" "timer", A.attribute "aria-label" (String.fromInt seconds ++ " seconds remaining") ]
                                        [ text (String.fromInt (seconds // 60) ++ ":" ++ String.padLeft 2 '0' (String.fromInt (modBy 60 seconds))) ]
                                    , button
                                        (buttonAttrs False
                                            ++ [ A.class "countdown-sound"
                                               , A.attribute "aria-label"
                                                    (if model.game.sound then
                                                        "Mute countdown and game audio"

                                                     else
                                                        "Enable countdown and game audio"
                                                    )
                                               , E.onClick (GameMsg Game.ToggleSound)
                                               ]
                                        )
                                        [ text
                                            (if model.game.sound then
                                                "Sound on"

                                             else
                                                "Sound off"
                                            )
                                        ]
                                    , div [ A.class "countdown-track", A.attribute "aria-hidden" "true" ] [ div [ A.style "width" (String.fromFloat (clamp 0 100 (toFloat seconds / 120 * 100)) ++ "%") ] [] ]
                                    ]
                ]


pilotControls : Room.Client -> Game.Model -> List (Html FrontendMsg)
pilotControls client game =
    let
        row side =
            let
                pilot =
                    case client of
                        Room.Browsing ->
                            { human =
                                if side == Bottom then
                                    game.mode == Solo || game.mode == Versus

                                else
                                    game.mode == Versus || game.mode == ReverseSolo
                            , connected = True
                            , layoutTwo = side == Top
                            , label =
                                if side == Bottom then
                                    "PLAYER 1"

                                else
                                    "PLAYER 2"
                            }

                        Room.Seated snapshot ->
                            { human = Game.get side snapshot.controllers == Room.Human
                            , connected = Game.get side snapshot.connected
                            , layoutTwo = False
                            , label =
                                if side == snapshot.side then
                                    "YOU"

                                else
                                    "REMOTE PLAYER"
                            }

                        Room.Watching snapshot ->
                            { human = Game.get side snapshot.controllers == Room.Human, connected = Game.get side snapshot.connected, layoutTwo = False, label = "REMOTE PLAYER" }

                keys =
                    if pilot.layoutTwo then
                        [ ( "A D", "Turn" ), ( "W", "Thrust" ), ( "J", "Fire" ), ( "K", "Special" ) ]

                    else
                        [ ( "← →", "Turn" ), ( "↑", "Thrust" ), ( "Enter", "Fire" ), ( "Shift", "Special" ) ]
            in
            div
                [ A.class
                    ("pilot-controls-row "
                        ++ (if side == Bottom then
                                "gold-controls"

                            else
                                "cyan-controls"
                           )
                    )
                , A.attribute "aria-label" (sideName side ++ " controls")
                ]
                [ strong [] [ text (Game.get side game.names) ]
                , small []
                    [ text
                        (if not pilot.human then
                            "COMPUTER"

                         else if not pilot.connected then
                            "DISCONNECTED"

                         else
                            pilot.label
                        )
                    ]
                , if pilot.human && pilot.connected then
                    div [ A.class "pilot-key-list" ] (List.map (\( key, meaning ) -> div [] [ kbd [] [ text key ], span [] [ text meaning ] ]) keys)

                  else
                    text ""
                ]
    in
    [ row Top, row Bottom ]
