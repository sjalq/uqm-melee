module Melee.Presentation exposing (browserCommands, commands, countdown, effects, remainingSeconds)

import Effect.Command as Command
import Melee.Menu as Menu
import Melee.Room as Melee
import Ports.MeleeBrowser


browserCommands values =
    if List.isEmpty values then
        Command.none

    else
        values |> List.map Ports.MeleeBrowser.send |> Cmd.batch |> Command.fromCmd "Melee browser effects"


countdown model =
    case model.melee of
        Melee.Seated snapshot ->
            snapshot.ranked
                |> Maybe.andThen .deadline
                |> Maybe.map
                    (\deadline ->
                        ( snapshot.code
                        , deadline
                        , remainingSeconds model.meleeNow deadline
                        )
                    )

        _ ->
            Nothing


commands before after =
    let
        audible =
            after.game.sound && after.meleeVisible

        timer =
            if not audible then
                if before.game.sound && before.meleeVisible then
                    [ Menu.stop "countdown", Menu.stop "menu" ]

                else
                    []

            else if countdown before == countdown after then
                []

            else
                case ( countdown before, countdown after ) of
                    ( Just ( oldRoom, oldDeadline, oldSeconds ), Just ( room, deadline, seconds ) ) ->
                        if oldRoom == room && oldDeadline == deadline && oldSeconds - seconds == 1 && seconds > 0 && before.meleeVisible && before.game.sound then
                            [ Menu.play "countdown"
                                ("/sounds/countdown/"
                                    ++ (if seconds <= 5 then
                                            String.fromInt seconds

                                        else
                                            "tick"
                                       )
                                    ++ ".wav"
                                )
                                (if seconds <= 5 then
                                    0.55

                                 else
                                    0.1
                                )
                            ]

                        else
                            [ Menu.stop "countdown" ]

                    _ ->
                        [ Menu.stop "countdown" ]

        notice =
            if audible && after.game.notice /= "" && after.game.notice /= before.game.notice then
                [ Menu.play "menu" "/sounds/menu-3.wav" 0.3 ]

            else
                []
    in
    timer ++ notice


effects before ( after, cmd ) =
    ( after, Command.batch [ cmd, browserCommands (commands before after) ] )


remainingSeconds : Int -> Int -> Int
remainingSeconds now deadline =
    if now == 0 then
        120

    else
        max 0 ((deadline - now + 999) // 1000)
