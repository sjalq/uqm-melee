module Property.MeleeGameplayTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Element exposing (..)
import Melee.Id exposing (ElementId(..), toInt)
import Melee.Init as Init
import Melee.Input exposing (..)
import Melee.Keys as Keys
import Melee.Local as Game exposing (Mode(..), Phase(..))
import Melee.Rng exposing (Seed(..))
import Melee.Ship exposing (..)
import Melee.ShipState as State
import Melee.Step as Step
import Melee.Trig as Trig
import Melee.Units exposing (..)
import Melee.Velocity as Velocity
import Test exposing (..)


suite : Test
suite =
    describe "Playable melee"
        [ test "fleet files round-trip with names and ship order" <|
            \() ->
                let
                    original =
                        Game.update (Game.Rename Bottom "Gold Command") Game.init

                    restored =
                        Game.load (Game.encode original) Game.init
                in
                Expect.equal ( original.names, original.fleets ) ( restored.names, restored.fleets )
        , test "invalid fleet files preserve the existing fleet" <|
            \() ->
                (Game.load "{ broken" Game.init).fleets |> Expect.equal Game.init.fleets
        , test "Druuge and Pkunk can recharge from an empty battery" <|
            \() ->
                [ Druuge, Pkunk ]
                    |> List.map
                        (\ship ->
                            let
                                original =
                                    Init.arena ship UrQuan (Seed 1)

                                both =
                                    original.combatants

                                c =
                                    State.core both.bottom

                                empty =
                                    { original | combatants = { both | bottom = State.setCore { c | energy = 0 } both.bottom } }

                                next =
                                    Step.tick { bottom = { idle | special = True }, top = idle } empty
                            in
                            (State.core next.combatants.bottom).energy > 0
                        )
                    |> Expect.equal [ True, True ]
        , test "beam aiming matches the north-zero facing system in every direction" <|
            \() ->
                List.range 0 15
                    |> List.map
                        (\facing ->
                            let
                                original =
                                    Init.arena Chmmr UrQuan (Seed 1) |> position 2 2000 2000 |> position 3 (2000 + Trig.cosine (facing * 4) 400) (2000 + Trig.sine (facing * 4) 400)

                                both =
                                    original.combatants

                                c =
                                    State.core both.bottom

                                aimed =
                                    { original | combatants = { both | bottom = State.setCore { c | facing = Facing facing } both.bottom } }

                                next =
                                    Step.tick { bottom = { idle | weapon = True }, top = idle } aimed
                            in
                            Game.crew next.combatants.top next < 42
                        )
                    |> Expect.equal (List.repeat 16 True)
        , test "default fleets complete a computer match" <|
            \() ->
                let
                    initial =
                        Game.init

                    final =
                        runGame 90000 (Game.update Game.Start { initial | mode = Demo })
                in
                case final.phase of
                    Victory _ ->
                        Expect.pass

                    _ ->
                        Expect.fail ("Default fleets stalled in round " ++ String.fromInt final.round)
        , test "every ship spawns its own combatant and stock crew" <|
            \() ->
                Catalog.all
                    |> List.map
                        (\ship ->
                            let
                                a =
                                    Init.arena ship ship (Seed 1)
                            in
                            ( State.kind a.combatants.bottom, Game.crew a.combatants.bottom a )
                        )
                    |> Expect.equal (List.map (\ship -> ( ship, (stock ship).startingCrew )) Catalog.all)
        , test "all 25 ships survive simulated combat without breaking arena invariants" <|
            \() ->
                Catalog.all |> List.filter (\ship -> not (valid (simulate 900 (Init.arena ship Shofixti (Seed 72))))) |> Expect.equal []
        , fuzz (Fuzz.intRange 1 2147483646) "simulation replays deterministically" <|
            \seed ->
                let
                    initial =
                        Init.arena Earthling Spathi (Seed seed)
                in
                simulate 100 initial |> Expect.equal (simulate 100 initial)
        , test "a full one-ship computer match reaches the results screen" <|
            \() ->
                let
                    initial =
                        Game.init

                    game =
                        Game.update Game.Start { initial | mode = Demo, fleets = { bottom = [ Shofixti ], top = [ Shofixti ] } }

                    final =
                        runGame 18000 game
                in
                case final.phase of
                    Victory _ ->
                        Expect.pass

                    _ ->
                        Expect.fail ("Match did not end; round " ++ String.fromInt final.round)
        , test "human replacement selection preserves the survivor's crew and battery" <|
            \() ->
                let
                    initial =
                        Init.arena Earthling Shofixti (Seed 1)

                    c =
                        State.core initial.combatants.bottom

                    survivors =
                        initial.combatants

                    damaged =
                        { initial | elements = Dict.remove 3 initial.elements |> Dict.update 2 (Maybe.map (\el -> { el | points = 7 })), combatants = { survivors | bottom = State.setCore { c | energy = 3 } survivors.bottom } }

                    base =
                        Game.init

                    game =
                        { base | mode = Versus, remaining = { bottom = [ Earthling ], top = [ Shofixti, Vux ] }, phase = RoundOver 0 damaged }

                    next =
                        Game.finishRound damaged game |> Game.update (Game.Pick Top 0)
                in
                case next.phase of
                    Countdown _ arena ->
                        Expect.equal ( 7, 3 ) ( Game.crew arena.combatants.bottom arena, (State.core arena.combatants.bottom).energy )

                    _ ->
                        Expect.fail "Replacement did not start"
        , test "glory device damages a dreadnought without erasing surviving crew" <|
            \() ->
                let
                    initial =
                        Init.arena Shofixti UrQuan (Seed 1) |> position 2 2000 2000 |> position 3 2300 2000

                    next =
                        List.foldl (\pressed arena -> Step.tick { bottom = { idle | special = pressed }, top = idle } arena) initial [ True, False, True, False, True ]
                in
                Expect.all [ \a -> Expect.equal 0 (Game.crew a.combatants.bottom a), \a -> Expect.greaterThan 0 (Game.crew a.combatants.top a), \a -> Expect.lessThan 42 (Game.crew a.combatants.top a) ] next
        , test "a special can activate on the same frame as a primary weapon" <|
            \() ->
                let
                    a =
                        Step.tick { bottom = { idle | weapon = True, special = True }, top = idle } (Init.arena Yehat UrQuan (Seed 1))
                in
                Expect.greaterThan 0 (State.core a.combatants.bottom).shieldTicks
        , test "pause freezes the arena" <|
            \() ->
                let
                    base =
                        Game.init

                    arena =
                        Init.arena Orz Vux (Seed 1)

                    paused =
                        { base | phase = Paused arena }
                in
                Game.advance 250 (Keys.press "Enter" Keys.none) paused |> .phase |> Expect.equal (Paused arena)
        , test "fleet construction enforces fourteen slots and empty fleets cannot start" <|
            \() ->
                let
                    base =
                        Game.init

                    empty =
                        { base | fleets = { bottom = [], top = [] } }

                    full =
                        List.foldl (\_ g -> Game.update (Game.Add Earthling) g) empty (List.range 1 20)
                in
                Expect.equal ( 14, Hangar ) ( List.length full.fleets.bottom, (Game.update Game.Start full).phase )
        , test "swept collision catches a shot that crosses a ship between frames" <|
            \() ->
                let
                    initial =
                        Init.arena Earthling UrQuan (Seed 1) |> position 2 1000 1000 |> position 3 2000 2000

                    source =
                        Dict.get 2 initial.elements

                    withShot =
                        case source of
                            Nothing ->
                                initial

                            Just el ->
                                let
                                    shot =
                                        { el | id = ElementId 4, body = ShofixtiDart, mass = 1, points = 1, life = Finite 10, flags = projectileFlags, current = { location = { x = 1940, y = 2000 }, frameIndex = 0 }, next = { location = { x = 1940, y = 2000 }, frameIndex = 0 }, velocity = Velocity.setComponents (120 * 32) 0 }
                                in
                                { initial | elements = Dict.insert 4 shot initial.elements, queue = initial.queue ++ [ ElementId 4 ], nextElementId = 5 }
                in
                Step.tick { bottom = idle, top = idle } withShot |> (\a -> Game.crew a.combatants.top a) |> Expect.equal 41
        ]


position : Int -> Int -> Int -> Arena -> Arena
position id x y arena =
    { arena
        | elements =
            Dict.update id
                (Maybe.map
                    (\el ->
                        let
                            image =
                                { location = { x = x, y = y }, frameIndex = el.current.frameIndex }
                        in
                        { el | current = image, next = image }
                    )
                )
                arena.elements
    }


simulate : Int -> Arena -> Arena
simulate frames arena =
    if frames <= 0 || Game.crew arena.combatants.bottom arena == 0 || Game.crew arena.combatants.top arena == 0 then
        arena

    else
        simulate (frames - 1) (Step.tick { bottom = Game.ai Bottom arena, top = Game.ai Top arena } arena)


valid : Arena -> Bool
valid arena =
    let
        shipValid ship =
            let
                c =
                    State.core ship
            in
            c.energy >= 0 && c.energy <= c.maxEnergy && Game.crew ship arena >= 0 && Game.crew ship arena <= c.maxCrew
    in
    shipValid arena.combatants.bottom
        && shipValid arena.combatants.top
        && (List.sort (List.map toInt arena.queue) == Dict.keys arena.elements)
        && List.all (\el -> el.current.location.x >= 0 && el.current.location.y >= 0 && el.current.location.x < arena.space.width && el.current.location.y < arena.space.height) (Dict.values arena.elements)


runGame : Int -> Game.Model -> Game.Model
runGame frames game =
    if frames <= 0 then
        game

    else
        case game.phase of
            Victory _ ->
                game

            _ ->
                runGame (frames - 1) (Game.tick Keys.none game)


projectileFlags : ElementFlags
projectileFlags =
    let
        flags =
            Init.emptyFlags
    in
    { flags | finiteLife = True, ignoreSimilar = True, defyPhysics = True }
