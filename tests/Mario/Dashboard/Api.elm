module Mario.Dashboard.Api exposing
    ( Audit
    , Champion
    , Checkpoint
    , Curriculum
    , EvaluationScope(..)
    , EvidenceSource(..)
    , Event
    , Fitness(..)
    , GateCriterion(..)
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
    , Overall
    , OverallRound(..)
    , Phase(..)
    , Population
    , Readiness
    , Regression
    , Resources
    , RoundResult
    , Sampler
    , Scoring
    , Seat(..)
    , ShipPerformance
    , Status
    , decodeNetwork
    , decodeStatus
    , empty
    , emptyGenome
    , evaluationScopeLabel
    , evidenceIsGate
    , evidenceSourceLabel
    , fitnessLabel
    , gateCriterionLabel
    , isBroad
    , ladderLabel
    , matchupStatusLabel
    , nextSideLabel
    , nodeKindFromString
    , opponentTypeLabel
    , overallRoundLabel
    , phaseFromString
    , phaseIsLive
    , phaseLabel
    , seatLabel
    , seatPhrase
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
side at a time up the frozen order; "mixed" plays an assembled roster;
"broad" abandons staged expansion entirely and samples any ship against
any ship, gated on one overall balanced result rather than per cell.
-}
type Ladder
    = Climbing
    | Mixed
    | Broad
    | UnknownLadder String


ladderFromString : String -> Ladder
ladderFromString raw =
    case raw of
        "climbing" ->
            Climbing

        "mixed" ->
            Mixed

        "broad" ->
            Broad

        other ->
            UnknownLadder other


ladderLabel : Ladder -> String
ladderLabel ladder =
    case ladder of
        Climbing ->
            "climbing"

        Mixed ->
            "mixed"

        Broad ->
            "broad, any ship versus any ship"

        UnknownLadder other ->
            other


{-| What the run is actually being judged on.

Per-cell gating and overall balanced gating are different claims, and
the dashboard must never present one as the other. The scope is read
from `evaluation_scope` where the engine publishes it, and falls back to
the ladder when it does not, because a broad ladder that has not yet
grown the field is still not being gated per cell.

-}
type EvaluationScope
    = PerCellScope
    | OverallBalancedScope
    | UnknownScope String


evaluationScopeFromString : String -> EvaluationScope
evaluationScopeFromString raw =
    case raw of
        "per-cell-ladder" ->
            PerCellScope

        "overall-balanced" ->
            OverallBalancedScope

        other ->
            UnknownScope other


evaluationScopeLabel : EvaluationScope -> String
evaluationScopeLabel scope =
    case scope of
        PerCellScope ->
            "per ordered matchup"

        OverallBalancedScope ->
            "overall, balanced any-versus-any"

        UnknownScope other ->
            other


{-| True when this run is judged on one aggregate balanced result rather
than cell by cell. Either signal is enough on its own: an engine that
declares the scope is believed, and a broad ladder is broad whether or
not the scope field arrived.
-}
isBroad : Curriculum -> Bool
isBroad curriculum =
    (curriculum.evaluationScope == OverallBalancedScope)
        || (curriculum.ladder == Broad)


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
    , evaluationScope : EvaluationScope
    , stageUnlockedExternally : Bool
    , transitionReason : Maybe String
    , originRunId : Maybe String
    , originGeneration : Maybe Int
    , originFingerprint : Maybe String
    }


{-| Which hull a per-ship row groups by.

Both seats count the same thing: **wins by our champion**. `ours` groups
those wins by the hull our champion was flying; `opponent` groups the
very same wins by the hull it was flying against. `opponent` is not the
enemy's win count and is not the inverse of anything, so a low figure
there means our champion struggles against that hull, not that the hull
is losing.

Keeping the two apart matters because they answer different questions,
and pooling them or inverting one would silently reverse the meaning of
half the table.

-}
type Seat
    = OurSeat
    | OpponentSeat
    | UnknownSeat String


seatFromString : String -> Seat
seatFromString raw =
    case raw of
        "ours" ->
            OurSeat

        "opponent" ->
            OpponentSeat

        other ->
            UnknownSeat other


seatLabel : Seat -> String
seatLabel seat =
    case seat of
        OurSeat ->
            "ours"

        OpponentSeat ->
            "opponent"

        UnknownSeat other ->
            other


{-| How a row reads in a sentence, spelled out so no reader has to guess
what "opponent" means. Always phrased from our champion's point of view,
because that is whose wins are being counted.
-}
seatPhrase : Seat -> String
seatPhrase seat =
    case seat of
        OurSeat ->
            "when piloting"

        OpponentSeat ->
            "when facing"

        UnknownSeat other ->
            other


{-| Which round of the overall gate the reported figures belong to. The
audit round and the independent confirm round are separate panels with
separate trial counters, so their evidence is never added together.
-}
type OverallRound
    = AuditRound
    | ConfirmRound
    | UnknownRound String


overallRoundFromString : String -> OverallRound
overallRoundFromString raw =
    case raw of
        "audit" ->
            AuditRound

        "confirm" ->
            ConfirmRound

        other ->
            UnknownRound other


overallRoundLabel : OverallRound -> String
overallRoundLabel round =
    case round of
        AuditRound ->
            "audit"

        ConfirmRound ->
            "confirm"

        UnknownRound other ->
            other


{-| One round's record on the balanced panel. Audit and confirm are kept
as separate values with separate counters, because adding them together
would turn two independent rounds into one larger sample and destroy the
whole point of confirming.
-}
type alias RoundResult =
    { wins : Int
    , games : Int
    , winRate : Maybe Float
    , lowerBound : Maybe Float
    , passed : Bool
    }


{-| The aggregate gate for a broad run: one frozen champion's record on a
fixed held-out balanced panel in which all 25 of our hulls and all 25
opponent hulls are equally represented, each pair played in both seats.

This is an aggregate over a distribution whose paired-seat outcomes are
correlated. It is an operational confidence check, not a formal global
guarantee, and it is deliberately not a per-matchup claim. The view must
never label it as either. `passed` is the engine's own verdict, true
only once both rounds have cleared; the dashboard shows it beside the
published bound rather than recomputing a pass of its own.

-}
type alias Overall =
    { scope : String
    , target : Float
    , panel : Int
    , pairs : Int
    , round : Maybe OverallRound
    , wins : Int
    , games : Int
    , winRate : Maybe Float
    , lowerBound : Maybe Float
    , championId : String
    , passed : Bool
    , audit : RoundResult
    , confirm : RoundResult
    , attempt : Int
    }


{-| Per-hull diagnostics from the same evidence, one entry per ship per
seat.

`wins` is always our champion's wins, in both seats. A `side = OurSeat`
row is that record grouped by the hull our champion flew; a
`side = OpponentSeat` row is the same record grouped by the hull it flew
against. Neither row ever reports the enemy's wins.

Every figure here comes from the current frozen policy's balanced
evaluation evidence only. Results from an earlier champion, and plays
from the adaptive training pool, are never mixed in.

These expose blind spots; they do not gate anything, and a hull with no
games carries `Nothing`, never a zero win rate.

-}
type alias ShipPerformance =
    { side : Seat
    , ship : String
    , wins : Int
    , games : Int
    , winRate : Maybe Float
    , lowerBound : Maybe Float
    , source : EvidenceSource
    }


{-| Which stream produced a per-hull row.

The gate rounds and the cheap readiness probe are both balanced and both
report win rates, which is exactly why they have to be told apart on
screen. A readiness row is a diagnostic that triggers an audit; it is
never gate evidence, and rendering one as audit evidence would overstate
what has actually been proved.

-}
type EvidenceSource
    = FromAudit
    | FromConfirm
    | FromReadiness
    | UnknownSource String


evidenceSourceFromString : String -> EvidenceSource
evidenceSourceFromString raw =
    case raw of
        "audit" ->
            FromAudit

        "confirm" ->
            FromConfirm

        "ready" ->
            FromReadiness

        other ->
            UnknownSource other


evidenceSourceLabel : EvidenceSource -> String
evidenceSourceLabel source =
    case source of
        FromAudit ->
            "audit round"

        FromConfirm ->
            "confirm round"

        FromReadiness ->
            "readiness probe"

        UnknownSource other ->
            other


{-| True only for a stream the overall gate is actually decided on.
Readiness rows are excluded, because a readiness result triggers an
audit rather than standing in for one.
-}
evidenceIsGate : EvidenceSource -> Bool
evidenceIsGate source =
    case source of
        FromAudit ->
            True

        FromConfirm ->
            True

        FromReadiness ->
            False

        UnknownSource _ ->
            False


{-| What the adaptive training sampler is currently drawing from.

`balancedShare` is the share of each training panel reserved for the
balanced rotation. It is a property of how the panel is built, not a
measurement of how much of the 625-cell board has been seen, and the
view must not present it as coverage of the board.

Every field is optional, and the block is absent entirely outside broad
mode, so the view shows nothing rather than inventing a figure.

-}
type alias Sampler =
    { panel : Maybe Int
    , balancedShare : Maybe Float
    , cursor : Maybe Int
    , tour : Maybe Int
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
    , purpose : Maybe String
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

    -- How long one fight is allowed to last, in simulation ticks. The
    -- crew ratio is read at this deadline, so the figure is part of what
    -- the score means rather than a scheduling detail. Absent when the
    -- engine does not report it; never guessed at.
    , episodeTicks : Maybe Int
    }


{-| How a genome's score was computed, as the engine reports it.

Three rules govern this block, because getting any of them wrong would
print a confident lie about what the run is optimising.

1.  Absence means the original combat fitness. The selector is newer
    than the runs it can be applied to, so a status without a `scoring`
    block came from a build that had exactly one rule. The dashboard
    says so in those words rather than showing the crew ratio, which
    that run never used.

2.  The ratio's edge-case constants are read, never assumed. A
    crew-ratio run declares what a dead opponent scores and what a
    mutual wipe scores; if it does not, the dashboard says the constant
    was not reported instead of printing the documented default as if
    it had been measured.

3.  The fitness is not the gate. `gate` is a separate field and stays a
    separate sentence on the page, because a run can breed on the crew
    ratio while promotion still turns on actual wins.

-}
type Fitness
    = Combat
    | {- The caps live inside the constructor, so no combat run can carry
         a crew-ratio constant and no crew-ratio run can lose one.
      -}
      CrewRatio
        { zeroOpponent : Maybe Float
        , mutualZero : Maybe Float
        }
    | UnknownFitness String


fitnessFrom : String -> Maybe Float -> Maybe Float -> Fitness
fitnessFrom raw zeroOpponent mutualZero =
    case raw of
        "combat" ->
            Combat

        "crew-ratio" ->
            CrewRatio { zeroOpponent = zeroOpponent, mutualZero = mutualZero }

        other ->
            UnknownFitness other


fitnessLabel : Fitness -> String
fitnessLabel fitness =
    case fitness of
        Combat ->
            "combat"

        CrewRatio _ ->
            "crew ratio"

        UnknownFitness other ->
            if String.isEmpty other then
                "not reported"

            else
                other


{-| What a promotion is actually judged on. Kept as its own type so the
page can never rephrase an unfamiliar criterion as "wins".
-}
type GateCriterion
    = CombatWins
    | UnknownGate String


gateFrom : String -> GateCriterion
gateFrom raw =
    case raw of
        "combat-wins" ->
            CombatWins

        other ->
            UnknownGate other


gateCriterionLabel : GateCriterion -> String
gateCriterionLabel criterion =
    case criterion of
        CombatWins ->
            "actual combat wins"

        UnknownGate other ->
            if String.isEmpty other then
                "not reported"

            else
                other


type alias Scoring =
    { fitness : Fitness

    -- `Nothing` means the run did not say. A crew-ratio run has no time
    -- term at all, but that is the engine's fact to state, not ours.
    , speedBonus : Maybe Bool
    , gate : GateCriterion
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
    , overall : Maybe Overall
    , shipPerformance : List ShipPerformance
    , sampler : Maybe Sampler

    -- Absent on every run that predates the scoring selector. Absence is
    -- not "unknown rule" and it is certainly not the crew ratio; see
    -- `Scoring` below.
    , scoring : Maybe Scoring
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
        |> optional "overall" (Decode.nullable decodeOverall) Nothing
        |> optional "ship_performance" (Decode.list decodeShipPerformance) []
        |> optional "sampler" (Decode.nullable decodeSampler) Nothing
        |> optional "scoring" (Decode.nullable decodeScoring) Nothing


emptyRoundResult : RoundResult
emptyRoundResult =
    { wins = 0, games = 0, winRate = Nothing, lowerBound = Nothing, passed = False }


decodeRoundResult : Decoder RoundResult
decodeRoundResult =
    Decode.succeed RoundResult
        |> optional "wins" Decode.int 0
        |> optional "games" Decode.int 0
        |> optional "win_rate" finiteFloat Nothing
        |> optional "lower_bound" finiteFloat Nothing
        |> optional "passed" Decode.bool False


decodeOverall : Decoder Overall
decodeOverall =
    Decode.succeed Overall
        |> optional "scope" Decode.string ""
        |> optional "target" (safeFloat 0.8) 0.8
        |> optional "panel" Decode.int 0
        |> optional "pairs" Decode.int 0
        |> optional "round" (Decode.nullable (Decode.map overallRoundFromString Decode.string)) Nothing
        |> optional "wins" Decode.int 0
        |> optional "games" Decode.int 0
        |> optional "win_rate" finiteFloat Nothing
        |> optional "lower_bound" finiteFloat Nothing
        |> optional "champion_id" Decode.string ""
        |> optional "passed" Decode.bool False
        |> optional "audit" decodeRoundResult emptyRoundResult
        |> optional "confirm" decodeRoundResult emptyRoundResult
        |> optional "attempt" Decode.int 0


decodeShipPerformance : Decoder ShipPerformance
decodeShipPerformance =
    Decode.succeed ShipPerformance
        |> optional "side" (Decode.map seatFromString Decode.string) (UnknownSeat "unreported")
        |> optional "ship" Decode.string ""
        |> optional "wins" Decode.int 0
        |> optional "games" Decode.int 0
        |> optional "win_rate" finiteFloat Nothing
        |> optional "lower_bound" finiteFloat Nothing
        |> optional "source" (Decode.map evidenceSourceFromString Decode.string) (UnknownSource "unreported")


decodeSampler : Decoder Sampler
decodeSampler =
    Decode.succeed Sampler
        |> optional "panel" (Decode.nullable Decode.int) Nothing
        |> optional "coverage" finiteFloat Nothing
        |> optional "cursor" (Decode.nullable Decode.int) Nothing
        |> optional "tour" (Decode.nullable Decode.int) Nothing


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
    { games = 0, period = 0, threshold = 0, lastRate = Nothing, purpose = Nothing }


decodeReadiness : Decoder Readiness
decodeReadiness =
    Decode.succeed Readiness
        |> optional "games" Decode.int 0
        |> optional "period" Decode.int 0
        |> optional "threshold" (safeFloat 0) 0
        |> optional "last_rate" finiteFloat Nothing
        |> optional "purpose" (Decode.nullable Decode.string) Nothing


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
    , overall = Nothing
    , shipPerformance = []
    , sampler = Nothing
    , scoring = Nothing
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
    , evaluationScope = UnknownScope "unreported"
    , stageUnlockedExternally = False
    , transitionReason = Nothing
    , originRunId = Nothing
    , originGeneration = Nothing
    , originFingerprint = Nothing
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
        |> optional "evaluation_scope" (Decode.map evaluationScopeFromString Decode.string) (UnknownScope "unreported")
        |> optional "stage_unlocked_externally" Decode.bool False
        |> optional "transition_reason" (Decode.nullable Decode.string) Nothing
        |> optional "origin_run_id" (Decode.nullable Decode.string) Nothing
        |> optional "origin_generation" (Decode.nullable Decode.int) Nothing
        |> optional "origin_fingerprint" (Decode.nullable Decode.string) Nothing


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
    { workers = 0, dutyCycle = 0, episodeTicks = Nothing }


decodeResources : Decoder Resources
decodeResources =
    Decode.succeed Resources
        |> optional "workers" Decode.int 0
        |> optional "duty_cycle" (safeFloat 0) 0
        |> optional "episode_ticks" (Decode.nullable Decode.int) Nothing


decodeScoring : Decoder Scoring
decodeScoring =
    Decode.succeed (\raw zeroOpponent mutualZero speedBonus gate ->
        { fitness = fitnessFrom raw zeroOpponent mutualZero
        , speedBonus = speedBonus
        , gate = gate
        }
    )
        |> optional "fitness" Decode.string ""
        |> optional "zero_opponent" finiteFloat Nothing
        |> optional "mutual_zero" finiteFloat Nothing
        |> optional "speed_bonus" (Decode.nullable Decode.bool) Nothing
        |> optional "gate" (Decode.map gateFrom Decode.string) (UnknownGate "")


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
