module Program.AdminAccessTests exposing (suite)

{-| Program tests for admin access and permissions.

Tests that admin functionality is properly protected and permissions are enforced.

-}

import Dict
import Effect.Lamdera
import Effect.Test as Test
import Helpers.Simulation as Sim
import SeqDict
import Test exposing (Test)
import Types exposing (..)


suite : Test
suite =
    Test.describe "Admin Access"
        [ testAdminPageLoads
        , testBackendHasNoDemoCredentials
        ]


{-| Test that admin page loads correctly.
-}
testAdminPageLoads : Test
testAdminPageLoads =
    Sim.start "admin page loads"
        [ Test.connectFrontend
            0
            (Effect.Lamdera.sessionIdFromString "session1")
            (Sim.testUrl "/admin")
            { width = 1920, height = 1080 }
            (\frontend ->
                [ Test.checkState 0 <|
                    \data ->
                        case SeqDict.get frontend.clientId data.frontends of
                            Just model ->
                                case model.currentRoute of
                                    Admin AdminDefault ->
                                        Ok ()

                                    Admin _ ->
                                        Ok ()

                                    other ->
                                        Err ("Expected Admin route, got: " ++ Debug.toString other)

                            Nothing ->
                                Err "Frontend not found"
                ]
            )
        ]
        |> Test.toTest


{-| Production initialization must not create demo accounts.
-}
testBackendHasNoDemoCredentials : Test
testBackendHasNoDemoCredentials =
    Sim.start "backend has no demo credentials"
        [ Test.checkBackend 0 <|
            \backend ->
                if Dict.isEmpty backend.users && Dict.isEmpty backend.emailPasswordCredentials then
                    Ok ()

                else
                    Err "Starter accounts or demo credentials must not be initialized"
        ]
        |> Test.toTest
