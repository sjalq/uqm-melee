port module Neat.Eval exposing (main)

{-| Line-oriented worker. Each stdin JSON line is one episode.
-}

import Helpers.LongGame as LongGame
import Json.Decode as D
import Json.Encode as E
import Melee.Battle exposing (Arena)
import Melee.Catalog as Catalog
import Melee.Input exposing (BattleInput, CyborgRating(..))
import Melee.Local as Game
import Melee.Rng exposing (Seed)
import Melee.Ship exposing (ShipKind(..), stock)
import Melee.ShipState as State
import Melee.Strategy as Strategy
import Melee.Units exposing (Side(..))
import Neat.Encode as Encode
import Neat.Policy as Policy
import Platform


port request : (String -> msg) -> Sub msg


port response : String -> Cmd msg


type alias Job =
    { weights : List Float
    , seed : Int
    , ticks : Int
    , swap : Bool
    , rating : String
    , us : String
    , them : String
    , foe : String
    }


type alias Memory =
    { extraBottom : List Float
    , extraTop : List Float
    , round : Int
    , shipBottom : String
    , shipTop : String
    }


main : Program () () String
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = \raw _ -> ( (), evalLine raw )
        , subscriptions = \_ -> request identity
        }


evalLine : String -> Cmd msg
evalLine raw =
    case D.decodeString jobDecoder raw of
        Err err ->
            fail (D.errorToString err)

        Ok job ->
            case Policy.load job.weights of
                Nothing ->
                    fail
                        ("weight length "
                            ++ String.fromInt (List.length job.weights)
                            ++ " != "
                            ++ String.fromInt Policy.weightCount
                        )

                Just net ->
                    succeed job (runJob job net)


fail : String -> Cmd msg
fail msg =
    response (E.encode 0 (E.object [ ( "error", E.string msg ) ]))


succeed : Job -> LongGame.Report -> Cmd msg
succeed job report =
    let
        ( bottomCrew, topCrew ) =
            report.crew

        ( usSeat, own, enemy ) =
            if job.swap then
                ( "top", topCrew, bottomCrew )

            else
                ( "bottom", bottomCrew, topCrew )

        usKind =
            kindFrom job.us

        themKind =
            kindFrom job.them

        ownStart =
            (stock usKind).startingCrew

        enemyStart =
            (stock themKind).startingCrew

        damage =
            toFloat (max 0 (enemyStart - enemy)) / toFloat (max 1 enemyStart)

        hurt =
            toFloat (max 0 (ownStart - own)) / toFloat (max 1 ownStart)

        engage =
            1 - toFloat report.longestQuietTicks / toFloat (max 1 report.ticks)

        dense =
            1000 * damage - 500 * hurt + 50 * engage - 0.01 * toFloat report.ticks

        won =
            report.winner == usSeat && report.outcome == LongGame.Completed

        lost =
            report.outcome == LongGame.Completed && report.winner /= usSeat && report.winner /= "pending"

        fitness =
            if won then
                1000000 - toFloat report.ticks

            else if enemy == 0 then
                100000 - toFloat report.ticks + dense

            else if lost then
                dense - 3000

            else
                dense
    in
    response
        (E.encode 0
            (E.object
                [ ( "fitness", E.float fitness )
                , ( "ticks", E.int report.ticks )
                , ( "winner", E.string report.winner )
                , ( "own", E.int own )
                , ( "enemy", E.int enemy )
                , ( "own_start", E.int ownStart )
                , ( "enemy_start", E.int enemyStart )
                , ( "damage", E.float damage )
                , ( "hurt", E.float hurt )
                , ( "engage", E.float engage )
                , ( "dense", E.float dense )
                , ( "swap", E.bool job.swap )
                , ( "outcome", E.string (outcome report.outcome) )
                , ( "seed", E.int job.seed )
                , ( "us", E.string job.us )
                , ( "them", E.string job.them )
                , ( "rating", E.string job.rating )
                , ( "foe", E.string job.foe )
                , ( "n_weights", E.int Policy.weightCount )
                ]
            )
        )


runJob : Job -> Policy.Net -> LongGame.Report
runJob job net =
    let
        us =
            if job.swap then
                Top

            else
                Bottom

        usKind =
            kindFrom job.us

        themKind =
            kindFrom job.them

        fleets =
            if job.swap then
                { bottom = [ themKind ], top = [ usKind ] }

            else
                { bottom = [ usKind ], top = [ themKind ] }

        rating =
            cyborgRating job.rating

        ratings =
            { bottom = rating, top = rating }

        memory =
            { extraBottom = Policy.zeroExtra, extraTop = Policy.zeroExtra, round = -1, shipBottom = "", shipTop = "" }
    in
    LongGame.runFold (prep net us job.foe)
        memory
        ratings
        job.ticks
        (LongGame.start job.seed fleets.bottom fleets.top)


prep : Policy.Net -> Side -> String -> Game.Model -> Memory -> ( Strategy.Pilots, Memory )
prep net us foe game memory =
    case game.phase of
        Game.Combat arena ->
            let
                selfPlay =
                    foe == "self"

                ( bottomIn, extraB, nameB ) =
                    think net Bottom arena memory.extraBottom game.round memory.shipBottom memory.round

                ( topIn, extraT, nameT ) =
                    think net Top arena memory.extraTop game.round memory.shipTop memory.round

                pilots =
                    if selfPlay then
                        { bottom = \_ -> Strategy.controls (decide bottomIn)
                        , top = \_ -> Strategy.controls (decide topIn)
                        }

                    else if us == Bottom then
                        { bottom = \_ -> Strategy.controls (decide bottomIn)
                        , top = Strategy.originalRoster
                        }

                    else
                        { bottom = Strategy.originalRoster
                        , top = \_ -> Strategy.controls (decide topIn)
                        }
            in
            ( pilots
            , { extraBottom = extraB
              , extraTop = extraT
              , round = game.round
              , shipBottom = nameB
              , shipTop = nameT
              }
            )

        _ ->
            ( Strategy.originalPilots, memory )


think : Policy.Net -> Side -> Arena -> List Float -> Int -> String -> Int -> ( BattleInput, List Float, String )
think net side arena extra round prevName prevRound =
    let
        ship =
            if side == Bottom then
                arena.combatants.bottom

            else
                arena.combatants.top

        name =
            (Catalog.info (State.kind ship)).name

        extra1 =
            if round /= prevRound || name /= prevName then
                Policy.zeroExtra

            else
                extra

        stepped =
            Policy.step net (Encode.vector side arena) (Policy.actionsFrom (State.core ship).oldInput ++ extra1)
    in
    ( stepped.input, stepped.extra, name )


decide : BattleInput -> Strategy.Context -> ( BattleInput, Seed )
decide input context =
    ( input, context.seed )


outcome : LongGame.Outcome -> String
outcome o =
    case o of
        LongGame.Completed ->
            "completed"

        LongGame.Invalidated ->
            "invalidated"


cyborgRating : String -> CyborgRating
cyborgRating raw =
    case raw of
        "standard" ->
            StandardCyborg

        "good" ->
            GoodCyborg

        _ ->
            AwesomeCyborg


kindFrom : String -> ShipKind
kindFrom raw =
    case String.toLower raw of
        "androsynth" ->
            Androsynth

        "arilou" ->
            Arilou

        "chenjesu" ->
            Chenjesu

        "chmmr" ->
            Chmmr

        "druuge" ->
            Druuge

        "earthling" ->
            Earthling

        "ilwrath" ->
            Ilwrath

        "kohr-ah" ->
            KohrAh

        "kohrah" ->
            KohrAh

        "melnorme" ->
            Melnorme

        "mmrnmhrm" ->
            Mmrnmhrm

        "mycon" ->
            Mycon

        "orz" ->
            Orz

        "pkunk" ->
            Pkunk

        "shofixti" ->
            Shofixti

        "slylandro" ->
            Slylandro

        "spathi" ->
            Spathi

        "supox" ->
            Supox

        "syreen" ->
            Syreen

        "thraddash" ->
            Thraddash

        "umgah" ->
            Umgah

        "ur-quan" ->
            UrQuan

        "urquan" ->
            UrQuan

        "utwig" ->
            Utwig

        "vux" ->
            Vux

        "yehat" ->
            Yehat

        "zoq-fot-pik" ->
            ZoqFotPik

        "zoqfotpik" ->
            ZoqFotPik

        _ ->
            Pkunk


jobDecoder : D.Decoder Job
jobDecoder =
    D.map8 Job
        (D.field "weights" (D.list D.float))
        (D.field "seed" D.int)
        (D.field "ticks" D.int)
        (D.oneOf [ D.field "swap" D.bool, D.succeed False ])
        (D.oneOf [ D.field "rating" D.string, D.succeed "awesome" ])
        (D.oneOf [ D.field "us" D.string, D.succeed "Pkunk" ])
        (D.oneOf [ D.field "them" D.string, D.succeed "Umgah" ])
        (D.oneOf [ D.field "foe" D.string, D.succeed "cyborg" ])
