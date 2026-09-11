module Mario.Dashboard.Api exposing
    ( Audit
    , Champion
    , Checkpoint
    , Curriculum
    , Event
    , Gene
    , Genome
    , HistoryPoint
    , Ladder(..)
    , Matchup
    , MatchupStatus(..)
    , Network
    , Node
    , NodeKind(..)
    , NextSide(..)
    , OpponentType(..)
    , Phase(..)
    , Population
    , Readiness
    , Regression
    , Resources
    , Status
    , decodeNetwork
    , decodeStatus
    , empty
    , emptyGenome
    , ladderLabel
    , matchupStatusLabel
    , nextSideLabel
    , nodeKindFromString
    , opponentTypeLabel
    , phaseFromString
    , phaseIsLive
    , phaseLabel
    , statusFromString
    )

{-| Decoders for the melee-mario trainer HTTP API (schema_version 1).

Two rules run through every decoder here.

1.  Unknown is not zero. Every field the contract declares as
    `float|null` decodes to `Maybe Float`, and a missing field decodes
    to `Nothing`, never to `0`. The view renders `Nothing` as "awaiting
    evidence". A dashboard that prints `0%` for an unmeasured cell is
    lying about the gate.

2.  Forward compatibility. Structural fields are read with `optional`
    and a conservative default so a newer engine that adds fields, or an
    older engine that has not filled one in yet, still renders. Unknown
    enum strings are preserved verbatim in an `Other` constructor rather
    than collapsing into a known state, so a future `phase` or matchup
    `status` shows up honestly instead of masquerading as something the
    dashboard already understands.

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)



-- PHASE


type Phase
    = Initializing
    | Training
    | Auditing
    | Paused
    | Stopped
    | Errored
    | UnknownPhase String


phaseFromString : String -> Phase
phaseFromString raw =
    case raw of
        "initializing" ->
            Initializing

        "training" ->
            Training

        "auditing" ->
            Auditing

        "paused" ->
            Paused

        "stopped" ->
            Stopped

        "error" ->
            Errored

        other ->
            UnknownPhase other


phaseLabel : Phase -> String
phaseLabel phase =
    case phase of
        Initializing ->
            "Initializing"

        Training ->
            "Training"

        Auditing ->
            "Auditing"

        Paused ->
            "Paused"

        Stopped ->
            "Stopped"

        Errored ->
            "Error"

        UnknownPhase other ->
            other


{-| True while the trainer is doing work that should keep advancing.
Used to decide whether a stale `updated_at` is worth warning about.
-}
phaseIsLive : Phase -> Bool
phaseIsLive phase =
    case phase of
        Training ->
            True

        Auditing ->
            True

        Initializing ->
            True

        Paused ->
            False

        Stopped ->
            False

        Errored ->
            False

        UnknownPhase _ ->
            False



-- OPPONENT TYPE


type OpponentType
    = Cyborg
    | ModelOpponent
    | UnknownOpponent String


opponentTypeFromString : String -> OpponentType
opponentTypeFromString raw =
    case raw of
        "cyborg" ->
            Cyborg

        "model" ->
            ModelOpponent

        other ->
            UnknownOpponent other


opponentTypeLabel : OpponentType -> String
opponentTypeLabel kind =
    case kind of
        Cyborg ->
            "cyborg"

        ModelOpponent ->
            "frozen model"

        UnknownOpponent other ->
            other



-- NEXT SIDE


type NextSide
    = AddOpponent
    | AddOurs
    | AddModel
    | Complete
    | UnknownSide String


nextSideFromString : String -> NextSide
nextSideFromString raw =
    case raw of
        "opponent" ->
            AddOpponent

        "ours" ->
            AddOurs

        "model" ->
            AddModel

        "complete" ->
            Complete

        other ->
            UnknownSide other


nextSideLabel : NextSide -> String
nextSideLabel side =
    case side of
        AddOpponent ->
            "add an opponent ship"

        AddOurs ->
            "add one of our ships"

        AddModel ->
            "add a frozen model opponent"

        Complete ->
            "curriculum complete"

        UnknownSide other ->
            other



-- MATCHUP STATUS


type MatchupStatus
    = Unseen
    | Learning
    | AuditingCell
    | Mastered
    | UnknownStatus String


statusFromString : String -> MatchupStatus
statusFromString raw =
    case raw of
        "unseen" ->
            Unseen

        "learning" ->
            Learning

        "auditing" ->
            AuditingCell

        "mastered" ->
            Mastered

        other ->
            UnknownStatus other


matchupStatusLabel : MatchupStatus -> String
matchupStatusLabel status =
    case status of
        Unseen ->
            "Unseen"

        Learning ->
            "Learning"

        AuditingCell ->
            "Auditing"

        Mastered ->
            "Mastered"

        UnknownStatus other ->
            other



-- RECORDS


{-| How the curriculum is currently expanding. "Climbing" adds ships one
side at a time up the frozen order; "mixed" plays an assembled roster.
-}
type Ladder
    = Climbing
    | Mixed
    | UnknownLadder String


ladderFromString : String -> Ladder
ladderFromString raw =
    case raw of
        "climbing" ->
            Climbing

        "mixed" ->
            Mixed

        other ->
            UnknownLadder other


ladderLabel : Ladder -> String
ladderLabel ladder =
    case ladder of
        Climbing ->
            "climbing"

        Mixed ->
            "mixed"

        UnknownLadder other ->
            other


type alias Curriculum =
    { stage : Int
    , ourRoster : List String
    , opponentRoster : List String
    , opponentTypes : List OpponentType
    , nextSide : NextSide
    , nextShip : Maybe String
    , target : Float
    , masteredMatchups : Int
    , totalMatchups : Int
    , ladder : Ladder
    , opponentRevision : Int
    , opponentFingerprint : Maybe String
    , selfPlayIsGated : Bool
    }


{-| The predeclared audit panel for the frozen candidate. `panel` is the
fixed number of games, `maxLosses` the number of losses the attempt can
absorb and still reach the target (so the cap is survivable and the next
loss after it ends the attempt), `spent` how much of the overall audit
budget has gone.
-}
type alias Audit =
    { panel : Int
    , maxLosses : Int
    , budget : Int
    , spent : Int
    , round : Maybe Int
    }


{-| Rehearsal of already-mastered cells, so a later stage cannot quietly
break an earlier one. Absent entirely on an engine that does not run it,
which is why the status carries a `Maybe`.
-}
type alias Regression =
    { active : Bool
    , sweeping : Bool
    , rehearsing : Int
    , lastSwept : Int
    , lastFailed : Int
    , budget : Int
    }


{-| The cheap screening test that decides when a candidate is worth
spending an expensive audit panel on.
-}
type alias Readiness =
    { games : Int
    , period : Int
    , threshold : Float
    , lastRate : Maybe Float
    }


type alias Champion =
    { id : String
    , validatedWins : Int
    , validatedGames : Int
    , winRate : Maybe Float
    , lowerBound : Maybe Float
    , nodes : Int
    , connections : Int
    , hiddenNodes : Int
    , worstCellLowerBound : Maybe Float
    }


type alias Population =
    { size : Int
    , species : Int
    , meanNodes : Float
    , meanConnections : Float
    }


type alias Checkpoint =
    { savedAt : Maybe String
    , generation : Int
    , resumable : Bool
    , path : String
    }


type alias Resources =
    { workers : Int
    , dutyCycle : Float
    }


type alias HistoryPoint =
    { generation : Int
    , stage : Int
    , trainingWinRate : Maybe Float
    , validationWinRate : Maybe Float
    , species : Int
    , nodes : Int
    , episodes : Int
    }


type alias Matchup =
    { us : String
    , them : String
    , opponentType : OpponentType
    , wins : Int
    , games : Int
    , winRate : Maybe Float
    , lowerBound : Maybe Float
    , status : MatchupStatus
    , sampleWeight : Float
    , trainingGames : Float
    , trainingWinRate : Maybe Float
    }


type alias Event =
    { at : String
    , message : String
    }


type alias Status =
    { schemaVersion : Int
    , runId : String
    , phase : Phase
    , message : String
    , generation : Int
    , episodes : Int
    , elapsedSeconds : Float
    , episodesPerSecond : Float
    , updatedAt : String
    , curriculum : Curriculum
    , champion : Champion
    , population : Population
    , checkpoint : Checkpoint
    , resources : Resources
    , history : List HistoryPoint
    , matchups : List Matchup
    , events : List Event
    , audit : Audit
    , readiness : Readiness
    , stale : Bool
    , episodesUnresolved : Int
    , regression : Maybe Regression
    }



-- DECODERS


{-| A JSON `null`, a missing field, or a non-finite number all mean "not
measured". Infinity and NaN cannot survive JSON round-tripping honestly,
so they are treated as absent rather than plotted.
-}
finiteFloat : Decoder (Maybe Float)
finiteFloat =
    Decode.nullable Decode.float
        |> Decode.map
            (Maybe.andThen
                (\x ->
                    if isNaN x || isInfinite x then
                        Nothing

                    else
                        Just x
                )
            )


safeFloat : Float -> Decoder Float
safeFloat fallback =
    Decode.float
        |> Decode.map
            (\x ->
                if isNaN x || isInfinite x then
                    fallback

                else
                    x
            )


decodeStatus : Decoder Status
decodeStatus =
    Decode.succeed Status
        |> optional "schema_version" Decode.int 1
        |> optional "run_id" Decode.string ""
        |> optional "phase" (Decode.map phaseFromString Decode.string) (UnknownPhase "unreported")
        |> optional "message" Decode.string ""
        |> optional "generation" Decode.int 0
        |> optional "episodes" Decode.int 0
        |> optional "elapsed_seconds" (safeFloat 0) 0
        |> optional "episodes_per_second" (safeFloat 0) 0
        |> optional "updated_at" Decode.string ""
        |> optional "curriculum" decodeCurriculum emptyCurriculum
        |> optional "champion" decodeChampion emptyChampion
        |> optional "population" decodePopulation emptyPopulation
        |> optional "checkpoint" decodeCheckpoint emptyCheckpoint
        |> optional "resources" decodeResources emptyResources
        |> optional "history" (Decode.list decodeHistoryPoint) []
        |> optional "matchups" (Decode.list decodeMatchup) []
        |> optional "events" (Decode.list decodeEvent) []
        |> optional "audit" decodeAudit emptyAudit
        |> optional "readiness" decodeReadiness emptyReadiness
        |> optional "stale" Decode.bool False
        |> optional "episodes_unresolved" Decode.int 0
        |> optional "regression" (Decode.map Just decodeRegression) Nothing


decodeRegression : Decoder Regression
decodeRegression =
    Decode.succeed Regression
        |> optional "active" Decode.bool False
        |> optional "sweeping" Decode.bool False
        |> optional "rehearsing" Decode.int 0
        |> optional "last_swept" Decode.int 0
        |> optional "last_failed" Decode.int 0
        |> optional "budget" Decode.int 0


emptyAudit : Audit
emptyAudit =
    { panel = 0, maxLosses = 0, budget = 0, spent = 0, round = Nothing }


decodeAudit : Decoder Audit
decodeAudit =
    Decode.succeed Audit
        |> optional "panel" Decode.int 0
        |> optional "max_losses" Decode.int 0
        |> optional "budget" Decode.int 0
        |> optional "spent" Decode.int 0
        |> optional "round" (Decode.nullable Decode.int) Nothing


emptyReadiness : Readiness
emptyReadiness =
    { games = 0, period = 0, threshold = 0, lastRate = Nothing }


decodeReadiness : Decoder Readiness
decodeReadiness =
    Decode.succeed Readiness
        |> optional "games" Decode.int 0
        |> optional "period" Decode.int 0
        |> optional "threshold" (safeFloat 0) 0
        |> optional "last_rate" finiteFloat Nothing


{-| The "nothing has been reported yet" status. Decoding `{}` produces
exactly this, so the view's empty states and this value cannot drift.
-}
empty : Status
empty =
    { schemaVersion = 1
    , runId = ""
    , phase = UnknownPhase "unreported"
    , message = ""
    , generation = 0
    , episodes = 0
    , elapsedSeconds = 0
    , episodesPerSecond = 0
    , updatedAt = ""
    , curriculum = emptyCurriculum
    , champion = emptyChampion
    , population = emptyPopulation
    , checkpoint = emptyCheckpoint
    , resources = emptyResources
    , history = []
    , matchups = []
    , events = []
    , audit = emptyAudit
    , readiness = emptyReadiness
    , stale = False
    , episodesUnresolved = 0
    , regression = Nothing
    }


emptyCurriculum : Curriculum
emptyCurriculum =
    { stage = 0
    , ourRoster = []
    , opponentRoster = []
    , opponentTypes = []
    , nextSide = UnknownSide "unreported"
    , nextShip = Nothing
    , target = 0.8
    , masteredMatchups = 0
    , totalMatchups = 0
    , ladder = UnknownLadder "unreported"
    , opponentRevision = 0
    , opponentFingerprint = Nothing
    , selfPlayIsGated = False
    }


decodeCurriculum : Decoder Curriculum
decodeCurriculum =
    Decode.succeed Curriculum
        |> optional "stage" Decode.int 0
        |> optional "our_roster" (Decode.list Decode.string) []
        |> optional "opponent_roster" (Decode.list Decode.string) []
        |> optional "opponent_types" (Decode.list (Decode.map opponentTypeFromString Decode.string)) []
        |> optional "next_side" (Decode.map nextSideFromString Decode.string) (UnknownSide "unreported")
        |> optional "next_ship" (Decode.nullable Decode.string) Nothing
        |> optional "target" (safeFloat 0.8) 0.8
        |> optional "mastered_matchups" Decode.int 0
        |> optional "total_matchups" Decode.int 0
        |> optional "ladder" (Decode.map ladderFromString Decode.string) (UnknownLadder "unreported")
        |> optional "opponent_revision" Decode.int 0
        |> optional "opponent_fingerprint" (Decode.nullable Decode.string) Nothing
        |> optional "self_play_is_gated" Decode.bool False


emptyChampion : Champion
emptyChampion =
    { id = ""
    , validatedWins = 0
    , validatedGames = 0
    , winRate = Nothing
    , lowerBound = Nothing
    , nodes = 0
    , connections = 0
    , hiddenNodes = 0
    , worstCellLowerBound = Nothing
    }


decodeChampion : Decoder Champion
decodeChampion =
    Decode.succeed Champion
        |> optional "id" Decode.string ""
        |> optional "validated_wins" Decode.int 0
        |> optional "validated_games" Decode.int 0
        |> optional "win_rate" finiteFloat Nothing
        |> optional "lower_bound" finiteFloat Nothing
        |> optional "nodes" Decode.int 0
        |> optional "connections" Decode.int 0
        |> optional "hidden_nodes" Decode.int 0
        |> optional "worst_cell_lower_bound" finiteFloat Nothing


emptyPopulation : Population
emptyPopulation =
    { size = 0, species = 0, meanNodes = 0, meanConnections = 0 }


decodePopulation : Decoder Population
decodePopulation =
    Decode.succeed Population
        |> optional "size" Decode.int 0
        |> optional "species" Decode.int 0
        |> optional "mean_nodes" (safeFloat 0) 0
        |> optional "mean_connections" (safeFloat 0) 0


emptyCheckpoint : Checkpoint
emptyCheckpoint =
    { savedAt = Nothing, generation = 0, resumable = False, path = "" }


decodeCheckpoint : Decoder Checkpoint
decodeCheckpoint =
    Decode.succeed Checkpoint
        |> optional "saved_at" (Decode.nullable Decode.string) Nothing
        |> optional "generation" Decode.int 0
        |> optional "resumable" Decode.bool False
        |> optional "path" Decode.string ""


emptyResources : Resources
emptyResources =
    { workers = 0, dutyCycle = 0 }


decodeResources : Decoder Resources
decodeResources =
    Decode.succeed Resources
        |> optional "workers" Decode.int 0
        |> optional "duty_cycle" (safeFloat 0) 0


decodeHistoryPoint : Decoder HistoryPoint
decodeHistoryPoint =
    Decode.succeed HistoryPoint
        |> optional "generation" Decode.int 0
        |> optional "stage" Decode.int 0
        |> optional "training_win_rate" finiteFloat Nothing
        |> optional "validation_win_rate" finiteFloat Nothing
        |> optional "species" Decode.int 0
        |> optional "nodes" Decode.int 0
        |> optional "episodes" Decode.int 0


decodeMatchup : Decoder Matchup
decodeMatchup =
    Decode.succeed Matchup
        |> optional "us" Decode.string ""
        |> optional "them" Decode.string ""
        |> optional "opponent_type" (Decode.map opponentTypeFromString Decode.string) Cyborg
        |> optional "wins" Decode.int 0
        |> optional "games" Decode.int 0
        |> optional "win_rate" finiteFloat Nothing
        |> optional "lower_bound" finiteFloat Nothing
        |> optional "status" (Decode.map statusFromString Decode.string) Unseen
        |> optional "sample_weight" (safeFloat 0) 0
        |> optional "training_games" (safeFloat 0) 0
        |> optional "training_win_rate" finiteFloat Nothing


decodeEvent : Decoder Event
decodeEvent =
    Decode.succeed Event
        |> optional "at" Decode.string ""
        |> optional "message" Decode.string ""



-- NETWORK


type NodeKind
    = InputNode
    | OutputNode
    | HiddenNode
    | UnknownKind String


nodeKindFromString : String -> NodeKind
nodeKindFromString raw =
    case raw of
        "input" ->
            InputNode

        "output" ->
            OutputNode

        "hidden" ->
            HiddenNode

        other ->
            UnknownKind other


type alias Node =
    { id : Int
    , kind : NodeKind
    }


type alias Gene =
    { innovation : Int
    , from : Int
    , to : Int
    , weight : Float
    , enabled : Bool
    }


type alias Genome =
    { schemaVersion : Int
    , nodes : List Node
    , genes : List Gene
    }


type alias Network =
    { schemaVersion : Int
    , championId : String
    , genome : Genome
    }


emptyGenome : Genome
emptyGenome =
    { schemaVersion = 1, nodes = [], genes = [] }


decodeNode : Decoder Node
decodeNode =
    Decode.succeed Node
        |> required "id" Decode.int
        |> optional "kind" (Decode.map nodeKindFromString Decode.string) (UnknownKind "unreported")


decodeGene : Decoder Gene
decodeGene =
    Decode.succeed Gene
        |> optional "innovation" Decode.int 0
        |> required "from" Decode.int
        |> required "to" Decode.int
        |> optional "weight" (safeFloat 0) 0
        |> optional "enabled" Decode.bool True


decodeGenome : Decoder Genome
decodeGenome =
    Decode.succeed Genome
        |> optional "schema_version" Decode.int 1
        |> optional "nodes" (Decode.list decodeNode) []
        |> optional "genes" (Decode.list decodeGene) []


decodeNetwork : Decoder Network
decodeNetwork =
    Decode.succeed Network
        |> optional "schema_version" Decode.int 1
        |> optional "champion_id" Decode.string ""
        |> optional "genome" decodeGenome emptyGenome
