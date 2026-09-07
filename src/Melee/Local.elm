module Melee.Local exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Cyborg as Cyborg
import Melee.Element exposing (Body(..), Owner(..))
import Melee.Graphics exposing (Quality(..))
import Melee.Id exposing (toInt)
import Melee.Init as Init
import Melee.Input exposing (..)
import Melee.Keys as Keys
import Melee.Music as Music
import Melee.Rate as Rate
import Melee.Rng as Rng exposing (Seed(..))
import Melee.Ship exposing (..)
import Melee.ShipState as State
import Melee.Step as Step
import Melee.Units exposing (..)
import Melee.View as View


type Mode
    = Solo
    | Versus
    | Demo
    | ReverseSolo


type Phase
    = Hangar
    | Selecting (Maybe ShipKind) (Maybe ShipKind)
    | Countdown Int Arena
    | Combat Arena
    | Paused Arena
    | RoundOver Int Arena
    | Victory (Maybe Side)


type alias Model =
    { names : Sided String
    , notice : String
    , difficulty : CyborgRating
    , fleets : Sided (List ShipKind)
    , remaining : Sided (List ShipKind)
    , mode : Mode
    , phase : Phase
    , editing : Side
    , seed : Seed
    , graphics : Quality
    , sound : Bool
    , sounds : List { id : Int, source : String, age : Int }
    , clock : Float
    , survivor : Maybe Arena
    , zoomWidth : Float
    , presentationStep : Float
    , presentationClock : Float
    , round : Int
    }


type Msg
    = Edit Side
    | Rename Side String
    | SetDifficulty CyborgRating
    | Add ShipKind
    | Remove Side Int
    | SetMode Mode
    | Start
    | Pick Side Int
    | RandomPick Side
    | TogglePause
    | Menu
    | Rematch
    | QuickStart
    | ToggleGraphics
    | ToggleSound
    | Suspend


{-| One of the 14 Super Melee fleet slots, plus vacant padding.
`Ready` carries the compacted `remaining` index used by `Pick`.
-}
type FleetSlot
    = Vacant
    | Ready Int ShipKind
    | Spent ShipKind


pickColumns : Int
pickColumns =
    7


pickRows : Int
pickRows =
    2


fleetSize : Int
fleetSize =
    14


defaultPickCell : { row : Int, col : Int }
defaultPickCell =
    { row = 0, col = pickColumns }


fleetSlots : List ShipKind -> List ShipKind -> List FleetSlot
fleetSlots fleet remaining =
    let
        marked =
            markSlots 0 fleet remaining
    in
    marked ++ List.repeat (max 0 (fleetSize - List.length marked)) Vacant


slotAt : Int -> List FleetSlot -> FleetSlot
slotAt index slots =
    slots
        |> List.drop index
        |> List.head
        |> Maybe.withDefault Vacant


markSlots : Int -> List ShipKind -> List ShipKind -> List FleetSlot
markSlots liveIndex fleet remaining =
    case fleet of
        [] ->
            []

        ship :: rest ->
            case remaining of
                next :: more ->
                    if ship == next then
                        Ready liveIndex ship :: markSlots (liveIndex + 1) rest more

                    else
                        Spent ship :: markSlots liveIndex rest remaining

                [] ->
                    Spent ship :: markSlots liveIndex rest []


humanNeedsPick : Mode -> Side -> Maybe ShipKind -> Bool
humanNeedsPick mode side selected =
    selected
        == Nothing
        && (case ( mode, side ) of
                ( Versus, _ ) ->
                    True

                ( Solo, Bottom ) ->
                    True

                ( ReverseSolo, Top ) ->
                    True

                _ ->
                    False
           )


init : Model
init =
    let
        fleets =
            { bottom = [ Earthling, Yehat, Orz, Chmmr ], top = [ Spathi, Vux, Mycon, UrQuan ] }
    in
    { names = { bottom = "Gold fleet", top = "Cyan fleet" }, notice = "", difficulty = GoodCyborg, fleets = fleets, remaining = fleets, mode = Solo, phase = Hangar, editing = Bottom, seed = Seed 1701, zoomWidth = 4096, presentationStep = 100, presentationClock = 0, round = 0, survivor = Nothing, graphics = HighDefinition, sound = True, sounds = [], clock = 0 }


get : Side -> Sided a -> a
get side sided =
    if side == Bottom then
        sided.bottom

    else
        sided.top


set : Side -> a -> Sided a -> Sided a
set side value sided =
    if side == Bottom then
        { sided | bottom = value }

    else
        { sided | top = value }


update : Msg -> Model -> Model
update msg model =
    case ( msg, model.phase ) of
        ( ToggleGraphics, _ ) ->
            { model
                | graphics =
                    if model.graphics == Classic then
                        HighDefinition

                    else
                        Classic
            }

        ( ToggleSound, _ ) ->
            { model | sound = not model.sound, sounds = [] }

        ( Suspend, Combat arena ) ->
            { model | phase = Paused arena, sounds = [] }

        ( Menu, _ ) ->
            { model | phase = Hangar }

        ( Rematch, _ ) ->
            begin model

        ( QuickStart, Hangar ) ->
            begin model |> autoPick Bottom |> autoPick Top

        ( Rename side name, Hangar ) ->
            { model | names = set side (String.left 30 name) model.names }

        ( SetDifficulty difficulty, Hangar ) ->
            { model | difficulty = difficulty }

        ( Edit side, Hangar ) ->
            { model | editing = side }

        ( Add ship, Hangar ) ->
            let
                fleet =
                    get model.editing model.fleets
            in
            if List.length fleet < 14 then
                { model | fleets = set model.editing (fleet ++ [ ship ]) model.fleets }

            else
                model

        ( Remove side index, Hangar ) ->
            { model | fleets = set side (get side model.fleets |> List.indexedMap Tuple.pair |> List.filter (\( i, _ ) -> i /= index) |> List.map Tuple.second) model.fleets }

        ( SetMode mode, Hangar ) ->
            { model | mode = mode }

        ( Start, Hangar ) ->
            begin model

        ( Pick side index, Selecting _ _ ) ->
            choose side index model

        ( RandomPick side, Selecting _ _ ) ->
            autoPick side model

        ( TogglePause, Combat arena ) ->
            { model | phase = Paused arena }

        ( TogglePause, Paused arena ) ->
            { model | phase = Combat arena }

        _ ->
            model


begin : Model -> Model
begin model =
    if List.isEmpty model.fleets.bottom || List.isEmpty model.fleets.top then
        model

    else
        { model | remaining = model.fleets, phase = Selecting Nothing Nothing, zoomWidth = 4096, presentationStep = 100, presentationClock = 0, round = 0, survivor = Nothing, sounds = [], clock = 0 } |> chooseComputers


chooseComputers : Model -> Model
chooseComputers model =
    case model.mode of
        Solo ->
            autoPick Top model

        Demo ->
            autoPick Bottom model |> autoPick Top

        ReverseSolo ->
            autoPick Bottom model

        Versus ->
            model


autoPick : Side -> Model -> Model
autoPick side model =
    let
        ( roll, seed ) =
            Rng.next model.seed

        count =
            List.length (get side model.remaining)
    in
    if count == 0 then
        model

    else
        choose side (modBy count roll) { model | seed = seed }


choose : Side -> Int -> Model -> Model
choose side index model =
    case model.phase of
        Selecting bottom top ->
            if
                (if side == Bottom then
                    bottom

                 else
                    top
                )
                    /= Nothing
            then
                model

            else
                case List.drop index (get side model.remaining) |> List.head of
                    Nothing ->
                        model

                    Just ship ->
                        let
                            selection =
                                set side (Just ship) { bottom = bottom, top = top }

                            next =
                                { model | phase = Selecting selection.bottom selection.top }
                        in
                        case ( selection.bottom, selection.top ) of
                            ( Just b, Just t ) ->
                                { next
                                    | phase =
                                        Countdown 60
                                            (let
                                                fresh =
                                                    Init.arena b t next.seed
                                             in
                                             Maybe.map (\old -> carrySurvivors old fresh) model.survivor |> Maybe.withDefault fresh
                                            )
                                    , round = model.round + 1
                                    , sounds = []
                                }

                            _ ->
                                next

        _ ->
            model


crew : State.Combatant -> Arena -> Int
crew ship arena =
    Dict.get (toInt (State.core ship).element) arena.elements |> Maybe.map .points |> Maybe.withDefault 0


tick : Keys.Held -> Model -> Model
tick held model =
    case model.phase of
        Countdown frames arena ->
            if frames <= 1 then
                { model | phase = Combat arena }

            else
                { model | phase = Countdown (frames - 1) arena }

        Combat arena ->
            let
                ( frames, acc ) =
                    Rate.advancePump arena.pumpAcc

                next =
                    List.foldl (\_ a -> battleFrame held model a) { arena | pumpAcc = acc } (List.range 1 frames)
            in
            if crew next.combatants.bottom next == 0 || crew next.combatants.top next == 0 then
                { model | phase = RoundOver (90 + dittyFrames next) next, seed = next.seed, sounds = collectSounds arena next model.sounds }

            else
                { model | phase = Combat next, sounds = collectSounds arena next model.sounds }

        RoundOver frames arena ->
            if frames > 1 then
                { model | phase = RoundOver (frames - 1) (Step.pump { bottom = idle, top = idle } arena) }

            else
                finishRound arena model

        _ ->
            model


removeFirst : a -> List a -> List a
removeFirst item list =
    case list of
        [] ->
            []

        first :: rest ->
            if first == item then
                rest

            else
                first :: removeFirst item rest


finishRound : Arena -> Model -> Model
finishRound arena model =
    let
        bottomAlive =
            crew arena.combatants.bottom arena > 0

        topAlive =
            crew arena.combatants.top arena > 0

        b =
            State.kind arena.combatants.bottom

        t =
            State.kind arena.combatants.top

        remaining =
            { bottom =
                if bottomAlive then
                    model.remaining.bottom

                else
                    removeFirst b model.remaining.bottom
            , top =
                if topAlive then
                    model.remaining.top

                else
                    removeFirst t model.remaining.top
            }

        next =
            { model | remaining = remaining, survivor = Just arena }
    in
    if List.isEmpty remaining.bottom || List.isEmpty remaining.top then
        { next
            | phase =
                Victory
                    (if List.isEmpty remaining.bottom && List.isEmpty remaining.top then
                        Nothing

                     else if List.isEmpty remaining.top then
                        Just Bottom

                     else
                        Just Top
                    )
        }

    else
        { next
            | phase =
                Selecting
                    (if bottomAlive then
                        Just b

                     else
                        Nothing
                    )
                    (if topAlive then
                        Just t

                     else
                        Nothing
                    )
        }
            |> chooseComputers
            |> preserveSurvivor arena


preserveSurvivor : Arena -> Model -> Model
preserveSurvivor old model =
    case model.phase of
        Countdown frames fresh ->
            { model | phase = Countdown frames (carrySurvivors old fresh) }

        _ ->
            model


carrySurvivors : Arena -> Arena -> Arena
carrySurvivors old fresh =
    let
        carry side arena =
            let
                previous =
                    get side old.combatants

                current =
                    get side arena.combatants

                c =
                    State.core current

                pc =
                    State.core previous

                health =
                    crew previous old
            in
            if health > 0 && State.kind previous == State.kind current then
                { arena
                    | combatants = set side (State.setCore { pc | element = c.element, input = idle, oldInput = idle, facing = c.facing, shieldTicks = 0 } previous) arena.combatants
                    , elements = Dict.update (toInt c.element) (Maybe.map (\el -> { el | points = health })) arena.elements
                }

            else
                arena
    in
    fresh |> carry Bottom |> carry Top


{-| One C battle frame. Cyborg thinks here so RNG matches SC2 (once per
24 Hz frame, not once per 60 Hz display tick).
-}
battleFrame : Keys.Held -> Model -> Arena -> Arena
battleFrame held model arena =
    let
        human =
            Keys.inputs held

        computerBottom =
            model.mode == Demo || model.mode == ReverseSolo

        computerTop =
            not (model.mode == Versus || model.mode == ReverseSolo)

        ( bottomIn, seed1 ) =
            if computerBottom then
                Cyborg.think model.difficulty Bottom arena arena.seed

            else
                ( human.bottom, arena.seed )

        arena1 =
            { arena | seed = seed1 }

        ( topIn, seed2 ) =
            if computerTop then
                Cyborg.think model.difficulty Top arena1 seed1

            else
                ( human.top, seed1 )
    in
    Step.tick { bottom = bottomIn, top = topIn } { arena1 | seed = seed2 }


advance : Float -> Keys.Held -> Model -> Model
advance milliseconds held model =
    let
        total =
            model.clock + clamp 0 250 milliseconds

        frames =
            floor (total / (1000 / 60))

        next =
            { model | clock = total - toFloat frames * (1000 / 60) }
    in
    List.foldl (\_ state -> tick held state) next (List.range 1 frames)


collectSounds : Arena -> Arena -> List { id : Int, source : String, age : Int } -> List { id : Int, source : String, age : Int }
collectSounds old next sounds =
    if old.frame == next.frame then
        sounds

    else
        let
            (FrameCount frame) =
                next.frame

            shot side =
                let
                    c =
                        State.core (get side next.combatants)

                    kind =
                        State.kind (get side next.combatants)

                    fired =
                        Dict.values next.elements |> List.any (\el -> el.owner == Owned side && toInt el.id >= old.nextElementId)

                    folder =
                        (Catalog.info kind).sprite |> String.split "/" |> List.take 3 |> String.join "/"
                in
                if fired then
                    [ { id =
                            frame
                                * 4
                                + (if side == Bottom then
                                    0

                                   else
                                    1
                                  )
                      , source = folder ++ "/primary.wav"
                      , age = 0
                      }
                    ]

                else
                    []

            exploded =
                Dict.values next.elements |> List.any (\el -> el.body == ExplosionBody && toInt el.id >= old.nextElementId)

            explosion =
                if exploded then
                    [ { id = frame * 4 + 2, source = "/sounds/explosion.wav", age = 0 } ]

                else
                    []
        in
        (sounds |> List.filter (\sound -> sound.age < 30) |> List.map (\sound -> { sound | age = sound.age + 1 })) ++ shot Bottom ++ shot Top ++ explosion


computer : CyborgRating -> Side -> Arena -> BattleInput
computer rating side arena =
    Cyborg.think rating side arena arena.seed |> Tuple.first


encode : Model -> String
encode model =
    let
        fleet ships =
            Encode.list (\ship -> Encode.string (Catalog.info ship).name) ships

        team side =
            Encode.object [ ( "name", Encode.string (get side model.names) ), ( "ships", fleet (get side model.fleets) ) ]
    in
    Encode.encode 2 (Encode.object [ ( "format", Encode.string "uqm-melee-fleet-v1" ), ( "gold", team Bottom ), ( "cyan", team Top ) ])


load : String -> Model -> Model
load source model =
    let
        shipDecoder =
            Decode.string
                |> Decode.andThen
                    (\name ->
                        case List.filter (\ship -> (Catalog.info ship).name == name) Catalog.all |> List.head of
                            Just ship ->
                                Decode.succeed ship

                            Nothing ->
                                Decode.fail ("Unknown ship: " ++ name)
                    )

        fleetDecoder =
            Decode.list shipDecoder
                |> Decode.andThen
                    (\ships ->
                        if List.length ships <= 14 then
                            Decode.succeed ships

                        else
                            Decode.fail "A fleet can contain at most 14 ships."
                    )

        teamDecoder =
            Decode.map2 Tuple.pair (Decode.field "name" Decode.string |> Decode.map (String.left 30)) (Decode.field "ships" fleetDecoder)

        decoder =
            Decode.field "format" Decode.string
                |> Decode.andThen
                    (\format ->
                        if format == "uqm-melee-fleet-v1" then
                            Decode.map2 Tuple.pair (Decode.field "gold" teamDecoder) (Decode.field "cyan" teamDecoder)

                        else
                            Decode.fail "This is not a Super Melee fleet file."
                    )
    in
    case ( model.phase, Decode.decodeString decoder source ) of
        ( Hangar, Ok ( ( goldName, gold ), ( cyanName, cyan ) ) ) ->
            { model | names = { bottom = goldName, top = cyanName }, fleets = { bottom = gold, top = cyan }, notice = "Fleets loaded." }

        ( Hangar, Err _ ) ->
            { model | notice = "Could not load that fleet file. Choose a Super Melee JSON fleet with up to 14 ships per side." }

        _ ->
            model



-- Keep the original victory tune complete before asking for another ship.


dittyFrames : Arena -> Int
dittyFrames arena =
    if crew arena.combatants.bottom arena > 0 then
        Music.duration (State.kind arena.combatants.bottom)

    else if crew arena.combatants.top arena > 0 then
        Music.duration (State.kind arena.combatants.top)

    else
        0


mapArena : (Arena -> Arena) -> Phase -> Phase
mapArena fn phase =
    case phase of
        Combat arena ->
            Combat (fn arena)

        Countdown frames arena ->
            Countdown frames (fn arena)

        Paused arena ->
            Paused (fn arena)

        RoundOver frames arena ->
            RoundOver frames (fn arena)

        _ ->
            phase


phaseArena : Phase -> Maybe Arena
phaseArena phase =
    case phase of
        Combat arena ->
            Just arena

        Countdown _ arena ->
            Just arena

        Paused arena ->
            Just arena

        RoundOver _ arena ->
            Just arena

        _ ->
            Nothing


animate : Float -> Model -> Model
animate milliseconds model =
    case phaseArena model.phase of
        Nothing ->
            model

        Just arena ->
            let
                target =
                    toFloat (View.camera arena).w

                blend =
                    1 - e ^ (negate (clamp 0 100 milliseconds) / 160)
            in
            { model
                | zoomWidth =
                    if abs (target - model.zoomWidth) < 0.5 then
                        target

                    else
                        model.zoomWidth + (target - model.zoomWidth) * blend
            }


present : Float -> Model -> Model
present milliseconds model =
    let
        clock =
            min model.presentationStep (model.presentationClock + max 0 milliseconds)

        alpha =
            round (clock / model.presentationStep * 60)
    in
    animate milliseconds { model | presentationClock = clock, phase = mapArena (\arena -> { arena | pumpAcc = alpha }) model.phase }
