module Melee.Ranking exposing (..)

import Melee.Units exposing (Side(..), Sided)


type alias Profile =
    { name : String, rating : Int, wins : Int, losses : Int, draws : Int, lastChange : Int }


initial : Int -> Profile
initial number =
    { name = "Pilot " ++ String.fromInt number, rating = 1000, wins = 0, losses = 0, draws = 0, lastChange = 0 }


type Outcome
    = Cancelled
    | Scored { winner : Maybe Side, changes : Sided Int, ratings : Sided Int }


type alias Match =
    { players : Sided String
    , ratings : Sided Int
    , deadline : Maybe Int
    , started : Bool
    , away : Sided (Maybe Int)
    , outcome : Maybe Outcome
    }


type alias View =
    { ratings : Sided Int, deadline : Maybe Int, outcome : Maybe Outcome }


view : Match -> View
view match =
    { ratings = match.ratings, deadline = match.deadline, outcome = match.outcome }


rate : Maybe Side -> Profile -> Profile -> ( Profile, Profile, Outcome )
rate winner bottom top =
    let
        score =
            case winner of
                Just Bottom ->
                    1

                Just Top ->
                    0

                Nothing ->
                    0.5

        expected =
            1 / (1 + 10 ^ (toFloat (top.rating - bottom.rating) / 400))

        change =
            round (32 * (score - expected))

        update side delta profile =
            { profile
                | rating = profile.rating + delta
                , lastChange = delta
                , wins =
                    profile.wins
                        + (if winner == Just side then
                            1

                           else
                            0
                          )
                , losses =
                    profile.losses
                        + (if winner /= Nothing && winner /= Just side then
                            1

                           else
                            0
                          )
                , draws =
                    profile.draws
                        + (if winner == Nothing then
                            1

                           else
                            0
                          )
            }
    in
    ( update Bottom change bottom, update Top -change top, Scored { winner = winner, changes = { bottom = change, top = -change }, ratings = { bottom = bottom.rating + change, top = top.rating - change } } )
