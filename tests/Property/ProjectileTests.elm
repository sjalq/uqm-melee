module Property.ProjectileTests exposing (suite)

import Dict
import Expect
import Fuzz
import Melee.Art as Art
import Melee.Element exposing (..)
import Melee.Init as Init
import Melee.Input exposing (..)
import Melee.Keys as Keys
import Melee.Local as Game exposing (Phase(..))
import Melee.Masks as Masks
import Melee.Projectile as P
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
    describe "Original UQM weapon contracts"
        [ test "only the four primary beam ships create rays" <|
            \() ->
                [ ( Arilou, 1 ), ( Chmmr, 1 ), ( Mmrnmhrm, 2 ), ( Vux, 1 ), ( Earthling, 0 ), ( Umgah, 0 ), ( ZoqFotPik, 0 ), ( Utwig, 0 ), ( Yehat, 0 ), ( UrQuan, 0 ) ]
                    |> List.map (\( ship, count ) -> ( count, fire ship |> shots |> List.filter (\e -> e.prim == Line) |> List.length ))
                    |> List.all (\( a, b ) -> a == b)
                    |> Expect.equal True
        , test "damage and projectile durability are independent C values" <|
            \() ->
                [ ( Earthling, ( 4, 1 ) ), ( UrQuan, ( 6, 10 ) ), ( Druuge, ( 6, 4 ) ), ( Chenjesu, ( 6, 10 ) ), ( Orz, ( 3, 2 ) ), ( Androsynth, ( 2, 3 ) ) ]
                    |> List.map (\( ship, expected ) -> ( expected, fire ship |> shots |> List.head |> Maybe.map (\e -> ( e.mass, e.points )) ))
                    |> List.all (\( expected, actual ) -> actual == Just expected)
                    |> Expect.equal True
        , fuzz (Fuzz.intRange 0 15) "Chmmr emits one cannon-aligned beam without trails" <|
            \facing ->
                let
                    arena =
                        aimed Chmmr facing

                    next =
                        List.foldl (\_ a -> Step.tick firing a) arena (List.range 1 8)

                    beams =
                        shots next |> List.filter (\e -> e.body == ChmmrLaser)

                    muzzle =
                        Art.metrics ("/ships/chmmr/muzzle-big-" ++ String.padLeft 3 '0' (String.fromInt facing) ++ ".png")
                in
                case ( beams, Dict.get 2 next.elements ) of
                    ( [ beam ], Just source ) ->
                        Expect.equal ( -muzzle.x * 4, -muzzle.y * 4 )
                            ( Trig.wrapDelta (beam.intersect.stampOrigin.x - source.next.location.x) next.space.width
                            , Trig.wrapDelta (beam.intersect.stampOrigin.y - source.next.location.y) next.space.height
                            )

                    _ ->
                        Expect.fail "Expected exactly one current beam"
        , test "Utwig six ports use the original staggered pairs" <|
            \() ->
                fire Utwig
                    |> shots
                    |> List.map (\e -> ( e.current.location.x - 2000, e.current.location.y - 2000 ))
                    |> List.sort
                    |> Expect.equal (List.sort [ ( 20, -72 ), ( -20, -72 ), ( 52, -36 ), ( -52, -36 ), ( 68, -16 ), ( -68, -16 ) ])
        , test "nuke launches 42 pixels forward and accelerates from speed 10" <|
            \() ->
                let
                    arena =
                        fire Earthling

                    next =
                        Step.tick idleBoth arena
                in
                case ( shots arena |> List.head, shots next |> List.head ) of
                    ( Just a, Just b ) ->
                        Expect.equal ( 1832, ( 0, -1280 ), ( 0, -1408 ) ) ( a.current.location.y, Velocity.getCurrent a.velocity, Velocity.getCurrent b.velocity )

                    _ ->
                        Expect.fail "Missing nuke"
        , test "Melnorme charges one visible projectile and releases it" <|
            \() ->
                let
                    pressed =
                        fire Melnorme

                    charged =
                        List.foldl (\_ a -> Step.tick firing a) pressed (List.range 1 145)

                    released =
                        Step.tick idleBoth charged

                    charges a =
                        shots a |> List.filter (\e -> e.body == MelnormeCharge)
                in
                case ( charges pressed, charges charged, charges released ) of
                    ( [ first ], [ held ], [ releasedShot ] ) ->
                        Expect.all
                            [ \_ -> Expect.equal 8 held.mass
                            , \_ -> Expect.equal ( 0, 0 ) (Velocity.getCurrent held.velocity)
                            , \_ -> Expect.equal ( 0, -5760 ) (Velocity.getCurrent releasedShot.velocity)
                            , \_ -> Expect.equal 37 (State.core pressed.combatants.bottom).energy
                            , \_ -> Expect.equal 2 first.mass
                            ]
                            ()

                    _ ->
                        Expect.fail "Charging must preserve one projectile"
        , test "cone and tongue have their original collision masks" <|
            \() ->
                [ ( UmgahCone, "/ships/umgah/cone-big-000.png" ), ( ZoqTongue, "/ships/zoqfotpik/proboscis-big-000.png" ) ]
                    |> List.all (\( body, path ) -> (Art.projectile body 0 |> Maybe.map .path) == Just path && Masks.get path /= Nothing)
                    |> Expect.equal True
        , test "ray disappears on the first frame after release" <|
            \() ->
                fire Chmmr |> Step.tick idleBoth |> shots |> List.filter (\e -> e.body == ChmmrLaser) |> Expect.equal []
        , test "ship death emits bursts and the whole sequence expires" <|
            \() ->
                let
                    initial =
                        aimed Chmmr 0

                    target =
                        Dict.update 3 (Maybe.map (\e -> { e | points = 1, current = { location = { x = 2000, y = 1650 }, frameIndex = 0 }, next = { location = { x = 2000, y = 1650 }, frameIndex = 0 } })) initial.elements

                    dead =
                        Step.tick firing { initial | elements = target }

                    after frames =
                        List.foldl (\_ a -> Step.tick idleBoth a) dead (List.range 1 frames)

                    bursts arena =
                        Dict.values arena.elements |> List.filter (\e -> e.body == ExplosionBody)
                in
                Expect.all
                    [ \_ -> Expect.equal 0 (Game.crew dead.combatants.top dead)
                    , \_ -> Expect.greaterThan 3 (List.length (bursts (after 10)))
                    , \_ -> Expect.equal [] (bursts (after 48))
                    , \_ -> Expect.equal Nothing (Dict.get 3 (after 48).elements)
                    ]
                    ()
        , test "round-end arena continues advancing" <|
            \() ->
                let
                    base =
                        Game.init

                    arena =
                        aimed Chmmr 0

                    next =
                        Game.advance 200 Keys.none { base | phase = RoundOver 90 arena }
                in
                case next.phase of
                    RoundOver _ current ->
                        Expect.notEqual arena.frame current.frame

                    _ ->
                        Expect.fail "Expected aftermath"
        ]


idleBoth =
    { bottom = idle, top = idle }


firing =
    { bottom = { idle | weapon = True }, top = idle }


shots arena =
    Dict.values arena.elements |> List.filter (\el -> el.owner == Owned Bottom && el.projectile /= Nothing)


fire ship =
    Step.tick firing (aimed ship 0)


aimed ship facing =
    let
        initial =
            Init.arena ship UrQuan (Seed 1)

        both =
            initial.combatants

        c =
            State.core both.bottom

        position id x y elements =
            Dict.update id (Maybe.map (\e -> { e | current = { location = { x = x, y = y }, frameIndex = facing }, next = { location = { x = x, y = y }, frameIndex = facing } })) elements
    in
    { initial
        | combatants = { both | bottom = State.setCore { c | facing = Facing facing } both.bottom }
        , elements = initial.elements |> position 2 2000 2000 |> position 3 5000 5000
    }
