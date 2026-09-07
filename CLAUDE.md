## General engineering requirements

- MISI (Make Impossible States Impossible): use opaque types and discriminated unions for valid domain states. Derive facts from their authoritative data rather than storing contradictory copies. Preserve valid original-game states, including the C engine's combined speed flags.
- MITI (Make Impossible Transitions Impossible): centralize state transitions and permit actions only in their valid phases. A new round must carry only the original game's surviving state, and reset transient input, motion, and presentation state appropriately.
- DRY (Don't Repeat Yourself): human pilots, cyborgs, online matches, previews, and local matches must share the same authoritative rules and calculations. Keep keyboard ownership and selection geometry in one place.
- Avoid Big-O crimes: reason about growth with rooms, players, elements, and messages. Avoid repeated full traversals, list appends in folds, quadratic membership scans, and allocating full snapshots when a compact delta suffices. Measure representative workloads before increasing frequency or payload size.
- Respect Lamdera/Elm's operating model: every BackendMsg and ToBackend message is journaled. Keep both ultra-light. Do not drive backend messages from browser animation frames, send unchanged held inputs, or create update cascades and message ping-pong. Batch useful work, bound payloads, and avoid unnecessary idle subscriptions. Keep any maintenance clock slow; the current one-second idle heartbeat keeps server time fresh for draft and reconnect deadlines. Keep visual interpolation, animation, and UI-only state on the frontend. Server authority does not require server messages at rendering frequency.
- Protect the backend: advance simulation only when a room needs work, send only to actual subscribers, preserve input-change coalescing, and avoid duplicating the same simulation for different viewers. Evaluate journal growth and total work across all simultaneous games, rather than optimizing only one browser's FPS.
- Authority and capacity: all online games and the shared exhibition are resolved on the Lamdera backend. Browsers send player intent and render server results; they never decide online movement, hits, damage, or outcomes. Two humans sharing one browser and local solo-versus-bot games may resolve in that browser. Optimize backend scheduling, algorithms, payloads, and allocations to support as many simultaneous games as possible without weakening server authority.
- Original-game fidelity: reproduce the original UQM C behavior for every original ship, weapon, special ability, AI rating, collision, gravity interaction, timing, resource cost, and round transition. Use `/Users/sjalq/git/uqm/sc2/src/uqm/` as the local reference. Do not substitute approximate dynamics, balance changes, arbitrary unsticking behavior, or visual animation for simulation correctness. Verify changes against the C implementation and regression tests; do not claim full parity from compilation alone.
- UI fidelity: match original Super Melee screenshots and asset coordinates for existing screens. Use the original palette, pixel assets, proportions, and control treatment as the basis for new online features. Verify desktop, mobile, keyboard, and both online seats in an actual browser.

## Strategy simulation and regression workflow

`Melee.Strategy` defines pure ship strategies. `Strategy.controls` receives a context (side, rating, arena, seed) and returns controls plus the next seed; it cannot directly mutate combat state. Use `Strategy.override ShipKind candidate Strategy.originalRoster` for a single-ship experiment. Pass separate bottom/top rosters to `Game.advanceWith`. Default online and local play still use `Strategy.originalPilots`. Never store strategy functions in Lamdera models or messages.

`Helpers.LongGame.runWith` executes the real 60 Hz update loop, including the 24 Hz physics pump, natural deaths, selection and survivor transitions. It accepts separate bottom/top cyborg ratings and returns `Completed` or `Invalidated` at an explicit display-tick budget, plus the round, ships, crew and longest interval without crew/round changes. Random properties must fuzz both ships, both ratings and the seed. An invalidation is a diagnostic result, not proof of an impossible loop. Compare the same seeds and fleets in both seat orientations. Do not add forced damage, arbitrary unsticking or timeouts to production to make a simulation pass.

```sh
elm-test-rs --compiler lamdera tests/Property/LongGameTests.elm tests/Property/StrategyTests.elm --fuzz 100 --workers 8
```

Run the short smoke test for all 5,625 ordered ship and independent prowess combinations with `elm-test-rs --compiler lamdera tests/Exhaustive/ShipProwessMatrixTests.elm --workers 8 --fuzz 1`. Each case includes the one-second countdown and five seconds of combat. The fixed eight-worker limit leaves two cores free on the ten-core development machine. Keep long endurance coverage in `Property.LongGameTests` rather than making every exhaustive case long.

`tests/Strategies/DirectPursuit.elm` is a deliberately simple experimental template, not a production replacement. Add candidate strategies under `tests/Strategies`, inject them with `Strategy.override`, and compare identical seeds through `LongGame.runWith`. Add focused properties that fail before a fix, and replay full games after it. AI intercept probes and real missiles share `Arsenal.mounts`, `mountPosition` and `launchState`; do not reintroduce a separate approximate weapon catalog.

At the start of each session, make sure you read the .cursor/*.mdc files so you know how to operate this project. Please note, you can do compiler checks with ./compile.sh

**IMPORTANT**: Always use `http://localhost:8000` instead of `http://0.0.0.0:8000` when accessing the Lamdera development server. The 0.0.0.0 binding is for the server to listen on all interfaces, but clients should connect via localhost.

## Property-Based Testing

This Lamdera project uses property-based tests with elm-explorations/test. Since Lamdera uses lamdera/codecs which is incompatible with standard elm-test, you must use the Lamdera compiler.

### Running Tests

```bash
elm-test-rs --compiler lamdera "tests/**/*.elm"
```

**Note**: Use `elm-test-rs` (not `elm-test`) as it properly handles Lamdera's codecs and other Lamdera-specific packages. The standard `elm-test` may fail to discover tests.

### Test Structure

Tests are organized in the `tests/` directory:

```
tests/
├── Tests.elm              # Main test entry point
├── Property/              # Pure function property tests
│   ├── RouteTests.elm
│   ├── RoleTests.elm
│   ├── PermissionsTests.elm
│   ├── LoggerTests.elm
│   └── ThemeTests.elm
├── Fuzzers/              # Shared fuzzer modules
│   └── DomainFuzzers.elm
├── Helpers/              # Test utilities
│   └── TestModels.elm
├── CodegenTests.elm      # Signature parser tests
└── Wire3*.elm            # Wire3 constructor-tag proofs
```

Example test module:

```elm
module Property.RouteTests exposing (suite)

import Test exposing (Test)

suite : Test
suite =
    Test.describe "Route Properties"
        [ -- your tests here
        ]
```

### elm.json Configuration

The main `elm.json` should have `elm-explorations/test` in `test-dependencies`:

```json
"test-dependencies": {
    "direct": {
        "elm-explorations/test": "2.2.0"
    },
    "indirect": {}
}
```

`elm-test-rs` automatically handles test configuration and source directories.

### Example Property-Based Test

```elm
module ExampleTests exposing (..)

import Expect
import Fuzz exposing (Fuzzer)
import Test exposing (..)

suite : Test
suite =
    describe "Example Property Tests"
        [ fuzz Fuzz.int "reversing twice returns original" <|
            \num ->
                num
                    |> negate
                    |> negate
                    |> Expect.equal num
        ]
```

## Reading Production Logs

There are two log systems available. See `LAMDERA-LOGS.md` for full details on the Lamdera.log system.

### Lamdera.log (disk-backed, recommended for debugging)

Every `Debug.log` call in backend code is automatically captured to a disk-backed log file by the Lamdera runtime, with timestamps added. This includes all `Logger.logInfo`/`logWarn`/`logError`/`logDebug` calls since they use `Debug.log` internally. The log file is served via an authenticated HTTP endpoint.

```bash
# CLI tool (recommended)
node scripts/node/lamdera-logs.mjs read --lines 50
node scripts/node/lamdera-logs.mjs read --lines 500 --grep "ERROR"
node scripts/node/lamdera-logs.mjs count

# Or curl directly (URL-encode the key: + -> %2B, = -> %3D, / -> %2F)
curl -s "https://YOUR_APP.lamdera.app/_logs/read?key=URL_ENCODED_KEY&lines=100&direction=tail"
```

The CLI tool reads the app name from `.lamdera-app` or `package.json`, and the key from `LAMDERA_LOG_KEY` env var or `.env.logkey` file. Use `--app` and `--key` to override.

### RPC endpoint (in-memory Logger.LogState)

The in-memory `Logger.LogState` in BackendModel is also available via RPC. This is capped at 2000 entries and resets on restart, but provides structured JSON with log levels.

```bash
curl -s -X POST "https://YOUR_APP.lamdera.app/_r/getLogs/" \
  -H "Content-Type: application/json" \
  -H "x-lamdera-model-key: YOUR_MODEL_KEY" \
  -d '{}' | jq -r '.[-30:][] | .m'
```

The `x-lamdera-model-key` header must match the value in your Env.elm for authentication.

## RPC Endpoint Conventions

### Creating RPC Endpoints

RPC endpoints are defined in `src/RPC.elm`. To add a new endpoint:

1. Create your handler function with one of these signatures:
   - **JSON endpoints**: `SessionId -> BackendModel -> Headers -> Json.Value -> ( Result Http.Error Json.Value, BackendModel, Cmd BackendMsg )`
   - **Raw endpoints**: `SessionId -> BackendModel -> HttpRequest -> ( RPCResult, BackendModel, Cmd msg )`

2. Register it in `lamdera_handleEndpoints` in `RPC.elm`:

```elm
lamdera_handleEndpoints rawReq args model =
    case args.endpoint of
        "myEndpoint" ->
            LamderaRPC.handleEndpointJson myHandler args model
        -- ...
```

### URL Structure

All RPC endpoints are available at `/_r/{endpointName}`:

- `/_r/getModel` - Get the entire BackendModel (requires auth header)
- `/_r/setModel` - Set the entire BackendModel (requires auth header)
- `/_r/getLogs` - Get server logs as JSON (requires auth header)
- `/_r/getPrice` - Example async endpoint (starts polling job)
- `/_r/getPriceResult` - Example async endpoint (polls for result)

### Async/Long-Running Endpoints

For endpoints that take longer than Lamdera's timeout, use the polling pattern in `AsyncRPC.elm`. See `EndpointExample/Price.elm` for a complete example.

## Lamdera REPL (Labs Feature)

The Lamdera REPL allows live inspection and modification of frontend and backend models during `lamdera live` sessions. This is extremely powerful for rapid development and debugging.

### Opening the REPL

1. Run `lamdera live`
2. Open browser to `http://localhost:8000`
3. Click "Show Repl" button in the developer bar

### Available Functions

In all tabs:
```elm
fem      : Types.FrontendModel          -- Get current frontend model
setFem   : FrontendModel -> FrontendModel  -- Set frontend model
updateFE : FrontendMsg -> FrontendMsg   -- Send FrontendMsg to update
sendToBE : ToBackend -> ToBackend       -- Send message to backend
capture  : a -> a                       -- Snapshot a live value
```

In leader tab only (green dot):
```elm
bem       : Types.BackendModel          -- Get current backend model
setBem    : BackendModel -> BackendModel   -- Set backend model
updateBE  : BackendMsg -> BackendMsg    -- Send BackendMsg to update
sendToFE  : ClientId -> ToFrontend -> ToFrontend  -- Send to specific client
broadcast : ToFrontend -> ToFrontend    -- Send to all clients
```

### LLM Agent Development Acceleration

**1. Rapid State Inspection**
Instead of adding Debug.log statements and recompiling, directly inspect models:
```elm
> bem.users
> fem.currentRoute
> bem.logState |> Logger.toList |> List.take 5
```

**2. Test Message Handlers Without UI**
Trigger any message directly to test your update functions:
```elm
> updateBE (GotLogTime someLoggerMsg)
> updateFE ToggleDarkMode
> sendToBE (Admin_FetchLogs "error")
```

**3. Simulate User Actions**
Test flows without clicking through UI:
```elm
> sendToBE (EmailPasswordAuthToBackend (EmailPasswordLoginToBackend "test@test.com" "password"))
> broadcast (Admin_Logs_ToFrontend [])
```

**4. Hot-Patch State for Testing**
Modify state directly to test edge cases:
```elm
> setBem { bem | users = Dict.empty }
> setFem { fem | currentUser = Nothing }
```

**5. Debug Data Transformations**
Test pure functions with actual model data:
```elm
> bem.users |> Dict.values |> List.filter (\u -> u.email == "test@test.com")
> Logger.toList bem.logState |> List.length
```

### Important: Live Values Warning

`fem` and `bem` return **current** values each time called. To snapshot:
```elm
> oldModel = capture bem    -- Correct: captures current value
> oldModel = bem            -- Wrong: will always equal current bem
```

### CLI Backend Access

Inspect backend model from command line (useful for scripting):
```bash
# Print entire backend model
lamdera backend

# Evaluate specific expression
lamdera backend --eval='Dict.size model.users'

# With imports
lamdera backend --import='import Dict' --eval='Dict.keys model.users'

# Start REPL session
lamdera backend --repl
```

### Agent Workflow Tips

1. **Before implementing a feature**: Use `bem` and `fem` to understand current state structure
2. **After code changes**: Use `updateFE`/`updateBE` to verify message handling works
3. **Debugging failures**: Inspect state with `bem`/`fem` to see what went wrong
4. **Testing edge cases**: Use `setBem`/`setFem` to create specific scenarios
5. **Create helper module**: Define custom functions for common REPL operations (pass model as parameter since REPL functions aren't available in modules)

## Program Testing with lamdera/program-test

Program tests allow testing full Lamdera applications as integrated units, simulating user interactions with both frontend and backend. This is more robust than unit tests for verifying complete user flows.

### Overview

`lamdera/program-test` (pre-release WIP) enables:
- End-to-end tests simulating user interactions
- Frontend/backend message flow testing
- HTTP request/response simulation
- Time-based behavior testing
- Port communication testing

### Critical Requirement: Effect Module Migration

**All standard `Cmd`/`Sub` must be replaced with `Command`/`Subscription`**, and these modules must use `Effect.*` equivalents:

| Original Module | Effect Replacement |
|-----------------|-------------------|
| `Browser.Dom` | `Effect.Browser.Dom` |
| `Browser.Events` | `Effect.Browser.Events` |
| `Browser.Navigation` | `Effect.Browser.Navigation` |
| `File` | `Effect.File` |
| `File.Download` | `Effect.File.Download` |
| `File.Select` | `Effect.File.Select` |
| `Http` | `Effect.Http` |
| `Lamdera` | `Effect.Lamdera` |
| `Process` | `Effect.Process` |
| `Task` | `Effect.Task` |
| `Time` | `Effect.Time` |

### Automated Migration

Run the upgrade tool to convert most imports automatically:
```bash
npx elm-review --template lamdera/program-test/upgrade --fix-all
```

**Note**: Some compiler errors may require manual fixes after migration.

### elm.json Dependencies

Add to direct dependencies:
```json
{
  "lamdera/program-test": "3.0.0",
  "lamdera/core": "1.0.0",
  "lamdera/codecs": "1.0.0",
  "elm-explorations/test": "2.2.0"
}
```

### Effect.Lamdera API

Core functions for Lamdera-specific testing:

```elm
-- Frontend app setup
frontend : (toBackend -> Cmd frontendMsg) -> {...} -> {...}

-- Backend app setup
backend : (toFrontend -> Cmd backendMsg) -> (String -> toFrontend -> Cmd backendMsg) -> {...} -> {...}

-- Message routing
sendToBackend : toBackend -> Command FrontendOnly toBackend frontendMsg
sendToFrontend : ClientId -> toFrontend -> Command BackendOnly toFrontend backendMsg
sendToFrontends : SessionId -> toFrontend -> Command BackendOnly toFrontend backendMsg
broadcast : toFrontend -> Command BackendOnly toFrontend backendMsg

-- Connection events
onConnect : (SessionId -> ClientId -> backendMsg) -> Subscription BackendOnly backendMsg
onDisconnect : (SessionId -> ClientId -> backendMsg) -> Subscription BackendOnly backendMsg
```

### ProgramTest API Reference

**Program Creation:**
```elm
createSandbox : {...} -> ProgramDefinition
createElement : {...} -> ProgramDefinition
createDocument : {...} -> ProgramDefinition
createApplication : {...} -> ProgramDefinition
start : flags -> ProgramDefinition -> ProgramTest
```

**User Interaction Simulation:**
```elm
clickButton : String -> ProgramTest -> ProgramTest
clickLink : String -> String -> ProgramTest -> ProgramTest
fillIn : String -> String -> String -> ProgramTest -> ProgramTest
fillInTextarea : String -> ProgramTest -> ProgramTest
check : String -> String -> Bool -> ProgramTest -> ProgramTest
selectOption : String -> String -> String -> String -> ProgramTest -> ProgramTest
```

**View Assertions:**
```elm
expectView : (Query.Single msg -> Expectation) -> ProgramTest -> Expectation
expectViewHas : List Selector -> ProgramTest -> Expectation
expectViewHasNot : List Selector -> ProgramTest -> Expectation
ensureView : (Query.Single msg -> Expectation) -> ProgramTest -> ProgramTest
ensureViewHas : List Selector -> ProgramTest -> ProgramTest
```

**HTTP Testing:**
```elm
simulateHttpOk : String -> String -> String -> ProgramTest -> ProgramTest
simulateHttpResponse : String -> String -> Http.Response String -> ProgramTest -> ProgramTest
expectHttpRequestWasMade : String -> String -> ProgramTest -> Expectation
expectHttpRequest : String -> String -> (HttpRequest -> Expectation) -> ProgramTest -> Expectation
```

**Time & Navigation:**
```elm
advanceTime : Int -> ProgramTest -> ProgramTest
routeChange : String -> ProgramTest -> ProgramTest
expectBrowserUrl : (String -> Expectation) -> ProgramTest -> Expectation
expectPageChange : String -> ProgramTest -> Expectation
```

**Port Testing:**
```elm
simulateIncomingPort : String -> Json.Encode.Value -> ProgramTest -> ProgramTest
expectOutgoingPortValues : String -> Decoder a -> (List a -> Expectation) -> ProgramTest -> Expectation
```

### Example: HTTP Testing

```elm
test "fetches data on button click" <|
    \() ->
        start
            |> ProgramTest.clickButton "Load Data"
            |> ProgramTest.simulateHttpOk "GET"
                "https://api.example.com/data"
                """{"items": ["a", "b", "c"]}"""
            |> ProgramTest.expectViewHas [ text "3 items loaded" ]
```

### Example: Form Validation

```elm
test "shows validation error for invalid input" <|
    \() ->
        start
            |> fillIn "email" "Email" "not-an-email"
            |> clickButton "Submit"
            |> expectViewHas [ text "Please enter a valid email" ]
```

### Example: Navigation Testing

```elm
test "navigates after delay" <|
    \() ->
        start "/page-one"
            |> clickButton "Navigate in 3 seconds"
            |> ProgramTest.advanceTime 3000
            |> expectBrowserUrl (Expect.equal "https://example.com/page-two")
```

### Effect Pattern for Production/Test Compatibility

Structure your app to support both production and test modes:

```elm
type Effect
    = NoEffect
    | SendHttp { method : String, url : String, body : Value, onResult : Result Error Data -> Msg }
    | NavigateTo String

-- Production: convert to real Cmd
perform : Effect -> Cmd Msg
perform effect =
    case effect of
        NoEffect -> Cmd.none
        SendHttp params -> Http.post { ... }
        NavigateTo url -> Nav.pushUrl key url

-- Testing: convert to simulated effects
simulateEffects : Effect -> SimulatedEffect Msg
simulateEffects effect =
    case effect of
        NoEffect -> SimulatedEffect.Cmd.none
        SendHttp params -> SimulatedEffect.Http.post { ... }
        NavigateTo url -> SimulatedEffect.Navigation.pushUrl url
```

### Running Program Tests

```bash
elm-test-rs --compiler lamdera "tests/**/*.elm"
```

### Visual Test Viewer

To see tests render the actual frontend UI:

1. **Compile the viewer:**
   ```bash
   lamdera make tests/TestViewer.elm --output=tests/viewer.js
   ```

2. **Serve the tests directory:**
   ```bash
   cd tests && python3 -m http.server 8888 --bind 0.0.0.0
   ```

3. **Open:** `http://localhost:8888/viewer.html`

4. **View rendered frontend:** Click a test, then click the **@** marker in the timeline to see the snapshot.

**Key:** Use `frontend.snapshotView` in tests to capture rendered views:
```elm
Test.connectFrontend 0 sessionId "/" { width = 1920, height = 1080 }
    (\frontend -> [ frontend.snapshotView 100 { name = "Home Page" } ])
```

### Resources

- [lamdera/program-test GitHub](https://github.com/lamdera/program-test)
- [elm-program-test Guide](https://elm-program-test.netlify.app/) (base library documentation)
- [avh4/elm-program-test](https://github.com/avh4/elm-program-test) (foundational patterns)
