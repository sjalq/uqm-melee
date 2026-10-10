module Melee.JevDesk exposing
    ( Desk
    , Job
    , Start(..)
    , empty
    , expire
    , finish
    , globalLimit
    , jobTtlMs
    , sessionLimit
    , start
    )

{-| Backend bookkeeping for Jev gateway calls made through `/_r/jev_evaluate`.

The backend answers by pushing to the session that asked, so there is no
polling and no result storage: a job only remembers who asked, which request
it answers and when it started. Keys come from a counter, so two live jobs
never share one, and because keys grow with time, expiry walks forward from
the oldest key and stops at the first live job; each key is visited once over
its whole life. In-flight counts per session and overall are kept as
counters, so admitting a call never scans the table.

-}

import Dict exposing (Dict)


type alias Job =
    { session : String
    , request : String
    , startedAt : Int
    }


type alias Desk =
    { next : Int
    , oldest : Int
    , live : Int
    , jobs : Dict Int Job
    , perSession : Dict String Int
    }


type Start
    = Started Int Desk
    | SessionBusy
    | DeskFull


empty : Desk
empty =
    { next = 0, oldest = 0, live = 0, jobs = Dict.empty, perSession = Dict.empty }


{-| One local game has at most two Jev seats, each with one call in flight.
-}
sessionLimit : Int
sessionLimit =
    2


globalLimit : Int
globalLimit =
    64


{-| Comfortably longer than the gateway timeout. A job whose answer never
came back is forgotten after this, freeing its session's slot.
-}
jobTtlMs : Int
jobTtlMs =
    15000


start : String -> String -> Int -> Desk -> Start
start session request now desk =
    let
        live =
            expire now desk

        mine =
            Dict.get session live.perSession |> Maybe.withDefault 0
    in
    if mine >= sessionLimit then
        SessionBusy

    else if live.live >= globalLimit then
        DeskFull

    else
        Started live.next
            { live
                | next = live.next + 1
                , live = live.live + 1
                , jobs = Dict.insert live.next { session = session, request = request, startedAt = now } live.jobs
                , perSession = Dict.insert session (mine + 1) live.perSession
            }


{-| Take a job off the desk when its answer (or failure) arrives. `Nothing`
when it already expired.
-}
finish : Int -> Desk -> Maybe ( Job, Desk )
finish key desk =
    Dict.get key desk.jobs |> Maybe.map (\job -> ( job, remove key job desk ))


remove : Int -> Job -> Desk -> Desk
remove key job desk =
    let
        remaining =
            (Dict.get job.session desk.perSession |> Maybe.withDefault 1) - 1
    in
    { desk
        | live = desk.live - 1
        , jobs = Dict.remove key desk.jobs
        , perSession =
            if remaining <= 0 then
                Dict.remove job.session desk.perSession

            else
                Dict.insert job.session remaining desk.perSession
    }


expire : Int -> Desk -> Desk
expire now desk =
    if desk.oldest >= desk.next then
        desk

    else
        case Dict.get desk.oldest desk.jobs of
            Nothing ->
                expire now { desk | oldest = desk.oldest + 1 }

            Just job ->
                if now - job.startedAt >= jobTtlMs then
                    expire now (remove desk.oldest job { desk | oldest = desk.oldest + 1 })

                else
                    desk
