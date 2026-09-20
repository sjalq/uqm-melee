module Env exposing (Mode(..), aiGatewayApiKey, mode)


{-| Per-environment config. Dashboard secrets override these on deploy.
See https://dashboard.lamdera.app/docs/environment
-}


type Mode
    = Development
    | Production


mode : Mode
mode =
    Production


{-| Vercel AI Gateway key for the local-only Jev survival pilot.
Empty disables the RPC proxy (frontend falls back to cached / idle input).
Set `AI_GATEWAY_API_KEY` in the Lamdera dashboard for production.
-}
aiGatewayApiKey : String
aiGatewayApiKey =
    ""
