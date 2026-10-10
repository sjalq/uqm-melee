module Property.SeatTests exposing (suite)

import Expect
import Fuzz exposing (Fuzzer)
import Melee.Input exposing (CyborgRating(..))
import Melee.Local as Game
import Melee.Location as Location
import Melee.Seat as Seat exposing (Seat(..))
import Test exposing (..)
import Url


seat : Fuzzer Seat
seat =
    Fuzz.oneOfValues Seat.all


parse : String -> Maybe Location.Location
parse path =
    Url.fromString ("https://game.test" ++ path) |> Maybe.map Location.fromUrl


suite : Test
suite =
    describe "Local seats"
        [ fuzz seat "every seat survives its URL parameter" <|
            \s -> Seat.fromParam (Seat.toParam s) |> Expect.equal (Just s)
        , fuzz seat "the controller button visits every seat and comes back" <|
            \s ->
                List.foldl (\_ acc -> Seat.cycle acc) s Seat.all
                    |> Expect.equal s
        , test "the controller button steps human, the three cyborgs, then Jev" <|
            \_ ->
                List.foldl (\_ ( acc, current ) -> ( acc ++ [ Seat.cycle current ], Seat.cycle current )) ( [ Human ], Human ) (List.range 1 4)
                    |> Tuple.first
                    |> Expect.equal Seat.all
        , fuzz (Fuzz.pair seat seat) "any pair of seats survives a local URL round trip" <|
            \( bottom, top ) ->
                let
                    base =
                        Location.lobby

                    location =
                        { base | local = True, seats = { bottom = bottom, top = top } }
                in
                parse (Location.toUrl location) |> Expect.equal (Just location)
        , fuzz (Fuzz.pair seat seat) "only human seats read the keyboard" <|
            \( bottom, top ) ->
                let
                    mode =
                        Seat.mode { bottom = bottom, top = top }
                in
                Expect.equal ( bottom == Human, top == Human )
                    ( mode == Game.Solo || mode == Game.Versus, mode == Game.ReverseSolo || mode == Game.Versus )
        , fuzz (Fuzz.pair seat seat) "each cyborg keeps its own rating" <|
            \( bottom, top ) ->
                let
                    rating s =
                        case s of
                            Cyborg r ->
                                Just r

                            _ ->
                                Nothing

                    ratings =
                        Seat.ratings { bottom = bottom, top = top }
                in
                Expect.equal ( rating bottom, rating top )
                    ( rating bottom |> Maybe.map (always ratings.bottom), rating top |> Maybe.map (always ratings.top) )
        , test "links from before per-seat control open the same game" <|
            \_ ->
                Expect.all
                    [ \_ -> parse "/melee?local=1&mode=reverse&ai=awesome" |> Maybe.map .seats |> Expect.equal (Just { bottom = Cyborg AwesomeCyborg, top = Human })
                    , \_ -> parse "/melee?local=1&mode=demo&ai=standard" |> Maybe.map .seats |> Expect.equal (Just { bottom = Cyborg StandardCyborg, top = Cyborg StandardCyborg })
                    , \_ -> parse "/melee?local=1&mode=versus" |> Maybe.map .seats |> Expect.equal (Just { bottom = Human, top = Human })
                    , \_ -> parse "/melee?local=1" |> Maybe.map .seats |> Expect.equal (Just Location.defaultSeats)
                    , \_ -> parse "/melee?local=1&top=jev&mode=demo" |> Maybe.map .seats |> Expect.equal (Just { bottom = Cyborg GoodCyborg, top = Jev })
                    ]
                    ()
        ]
