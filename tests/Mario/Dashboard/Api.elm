module Mario.Dashboard.Api exposing
    ( Benchmark
    , Board
    , Bucket
    , Champion
    , Checkpoint
    , Event
    , EvidenceSource(..)
    , Fitness(..)
    , GateCriterion(..)
    , Gene
    , Genome
    , HistoryPoint
    , Matchup
    , Network
    , NoDamagePenalty(..)
    , Node
    , NodeKind(..)
    , OpponentType(..)
    , Overall
    , OverallRound(..)
    , Phase(..)
    , PhaseSplit
    , Population
    , Readiness
    , Resources
    , RoundResult
    , Sampler
    , Scoring
    , Seat(..)
    , ShipPerformance
    , Status
    , Work
    , decodeNetwork
    , decodeStatus
    , empty
    , emptyGenome
    , evidenceIsGate
    , evidenceSourceLabel
    , fitnessLabel
    , gateCriterionLabel
    , gateSuccessNoun
    , gateSuccessPlural
    , nodeKindFromString
    , opponentTypeLabel
    , overallRoundLabel
    , phaseFromString
    , phaseIsLive
    , phaseLabel
    , seatLabel
    , seatPhrase
    )

{-| Decoders for the melee-mario trainer HTTP API (schema_version 4).

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
    than collapsing into a known state, so a future `phase` shows up
    honestly instead of masquerading as something the dashboard already
    understands.

The staged curriculum is gone from the engine and therefore from here:
there is no `curriculum` object, no per-cell mastery vocabulary, no
predeclared per-champion audit block and no regression rehearsal. The
run trains on the whole board from generation one and is graded on one
aggregate, which is `overall`.

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (custom, optional, required)



-- PHASE


{-| Every phase the engine can publish, plus the two the dashboard has to
represent on its own behalf.

There is no error phase. A start that fails exits with the reason on
stderr rather than publishing a document, so an "error" string is
something no build produces and it arrives here as `UnknownPhase` like
any other stranger.

-}
type Phase
    = Initializing
    | Training
    | Auditing
    | Paused
    | Stopped
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



-- SEATS AND EVIDENCE


{-| Which hull a per-ship row groups by.

Both seats count the same thing: **wins by our champion**. `ours` groups
those wins by the hull our champion was flying; `opponent` groups the
very same wins by the hull it was flying against. `opponent` is not the
enemy's win count and is not the inverse of anything, so a low figure
there means our champion struggles against that hull, not that the hull
is losing.

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



-- THE GRADED QUESTION


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


{-| The aggregate gate: one frozen champion's record on a fixed held-out
balanced panel in which all 25 of our hulls and all 25 opponent hulls
are equally represented, each pair played in both seats.

This is an aggregate over a distribution whose paired-seat outcomes are
correlated. It is an operational confidence check, not a formal global
guarantee, and it is deliberately not a per-matchup claim. The view must
never label it as either. `passed` is the engine's own verdict, true
only once both rounds have cleared AND the champion that cleared them is
still the champion; `passedBy` names whoever did clear it, so a gate
opened by an earlier policy is reported rather than inherited.

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
    , championId : Maybe String
    , passed : Bool
    , passedBy : Maybe String
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



-- WHAT IT IS PLAYING


{-| The board every generation trains on, in full, from generation one.

`totalMatchups` is what is ACTIVE. Nothing here is earned and nothing is
mastered: there is no schedule, so a count of cells is a statement about
the size of the problem rather than about progress through it.

-}
type alias Board =
    { totalMatchups : Int }


{-| What the adaptive training sampler is currently drawing from.

`balancedShare` is the share of each training panel reserved for the
balanced rotation. It is a property of how the panel is built, not a
measurement of how much of the 625-cell board has been seen, and the
view must not present it as coverage of the board.

-}
type alias Sampler =
    { panel : Maybe Int
    , balancedShare : Maybe Float
    , cursor : Maybe Int
    , tour : Maybe Int
    }


{-| The cheap screening test that decides when a candidate is worth
spending an expensive audit panel on.
-}
type alias Readiness =
    { threshold : Float
    , games : Int
    , lastRate : Maybe Float
    , period : Int
    }


{-| One row of training exposure for one ordered matchup.

Every number here is training exposure: how much of the next panel the
cell attracts, how many decayed games it has and how they went. None of
it is held-out evidence and none of it gates anything, which is why no
row carries a verdict. `trainingGames` is a decayed count and therefore
fractional; a cell with none has a `Nothing` rate rather than a zero.

-}
type alias Matchup =
    { us : String
    , them : String
    , opponentType : OpponentType
    , sampleWeight : Float
    , trainingGames : Float
    , trainingWinRate : Maybe Float
    }



-- COST AND HEALTH


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

    -- The measured fraction of WALL time the evaluator pool spends working
    -- rather than resting, averaged over its workers. It is a property of the
    -- pool, not of the machine: eight workers at 0.5 and one worker at 0.5
    -- report the same number while occupying very different amounts of the
    -- box. Absent when the engine has not measured it yet.
    , measuredDuty : Maybe Float

    -- All-time wall seconds actually spent computing, across every resume.
    , computeSeconds : Float

    -- How long one fight is allowed to last, in simulation ticks. The
    -- crew ratio is read at this deadline, so the figure is part of what
    -- the score means rather than a scheduling detail. Absent when the
    -- engine does not report it; never guessed at.
    , episodeTicks : Maybe Int

    -- The scheduling penalty this invocation runs under.
    , nice : Int
    }


{-| Machine independent work THIS process has done, and the rates that
make two builds comparable.

Every count is an event count: not one of them moves when the machine
gets busy, when the duty governor rests or when a fight happens to end
early. The two headline rates divide CPU nanoseconds summed over every
thread by those counts, so they are invariant to the worker count as
well, which is exactly what a wall-clock rate is not.

The whole block is absent on a process that has not computed. That is
not a measurement of no work; it is no measurement, so it decodes to
`Nothing` rather than to a page of zeroes.

-}
type alias Work =
    { episodes : Int
    , displayTicks : Int
    , decisions : Int
    , nodeActivations : Int
    , linkActivations : Int
    , elementScans : Int
    , elementsVisited : Int
    , networksCompiled : Int
    , cpuNanosPerDisplayTick : Maybe Float
    , cpuNanosPerLinkActivation : Maybe Float
    , displayTicksPerEpisode : Maybe Float
    , linkActivationsPerDecision : Maybe Float
    , elementsPerScan : Maybe Float
    }


{-| One named phase's seconds, and its share of ACCOUNTED time.

The share denominator is accounted seconds rather than the session, so
the buckets always sum to one. What is left over is reported separately
and signed, which is the only honest way to show a split whose error
term is real.

-}
type alias Bucket =
    { name : String
    , seconds : Float
    , share : Maybe Float
    }


{-| Where this session's CPU seconds went.

`unaccountedSeconds` is SIGNED and both signs mean something. Positive
is CPU nobody put a clock around: the supervisor loop, pool dispatch,
allocation, the server thread. Negative is worker threads preempted
mid-fight, because the in-fight clocks are per-thread wall clocks, so
its size against the accounted total is a contention signal rather than
an error.

-}
type alias PhaseSplit =
    { sessionCpuSeconds : Maybe Float
    , sessionWallSeconds : Float
    , threadsBusy : Maybe Float
    , accountedSeconds : Float
    , accountedShareOfCpu : Maybe Float
    , unaccountedSeconds : Maybe Float
    , unaccountedShareOfCpu : Maybe Float
    , buckets : List Bucket
    }


{-| What this BUILD costs with the machine to itself, as the fixed-work
benchmark last measured it.

It is a reference figure, not a session figure: it does not move while
the trainer runs, and it is only ever quoted for a recorded run of this
exact binary on this exact workload definition. `comparableRows` is how
many recorded results the best was taken over, so a best-of-one cannot
be read as a settled number.

-}
type alias Benchmark =
    { at : Maybe String
    , build : Maybe String
    , definition : Maybe String
    , repetitions : Maybe Int
    , fights : Maybe Int
    , bestSeconds : Maybe Float
    , cpuNanosPerDisplayTick : Maybe Float
    , cpuNanosPerLinkActivation : Maybe Float
    , comparableRows : Int
    }



-- THE CHAMPION


{-| What the champion IS. What it has been shown to do is `overall`, and
nothing here restates it.

No champion means no topology, so every figure is `Nothing` rather than
zero: a zero here would read as a graph with no nodes.

-}
type alias Champion =
    { id : Maybe String
    , nodes : Maybe Int
    , connections : Maybe Int
    , hiddenNodes : Maybe Int
    }



-- SCORING


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

`CrewLead` is the second criterion the trainer can be pointed at, and it
counts something a win is not: a game in which our surviving share of
our starting crew strictly exceeds theirs. A fight that runs to the
cut-off with neither ship destroyed can be a crew lead; it can never be
a win. So every tally gathered under this criterion is a count of leads,
and no figure carrying it may be rendered with the word "win".

-}
type GateCriterion
    = CombatWins
    | CrewLead
    | UnknownGate String


gateFrom : String -> GateCriterion
gateFrom raw =
    case raw of
        "combat-wins" ->
            CombatWins

        "crew-lead" ->
            CrewLead

        other ->
            UnknownGate other


gateCriterionLabel : GateCriterion -> String
gateCriterionLabel criterion =
    case criterion of
        CombatWins ->
            "actual combat wins"

        CrewLead ->
            "strict crew-share leads"

        UnknownGate other ->
            if String.isEmpty other then
                "not reported"

            else
                other


{-| One counted success under the criterion, singular, for the places
the page would otherwise have hard-coded "win".
-}
gateSuccessNoun : GateCriterion -> String
gateSuccessNoun criterion =
    case criterion of
        CombatWins ->
            "win"

        CrewLead ->
            "crew lead"

        UnknownGate _ ->
            "counted success"


gateSuccessPlural : GateCriterion -> String
gateSuccessPlural criterion =
    case criterion of
        CombatWins ->
            "wins"

        CrewLead ->
            "crew leads"

        UnknownGate _ ->
            "counted successes"


{-| The penalty that replaces a genome's fitness when a fight ends with
the opponent no worse off in crew than they started.

It is a conditional replacement, not a bound on the ordinary score:
under that one condition the run's scoring rule is not consulted at all.

Off, and on with a magnitude of zero, are the same run, so they are the
same value here: an absent field, a reported zero and a reported
negative all mean no penalty is applied. That stops the page announcing
a punishment that punishes nothing.

The magnitude is reported positive and the fitness it forces is its
negation. That is the engine's convention, and it is spelled out
wherever the number appears rather than left to be inferred.

-}
type NoDamagePenalty
    = PenaltyOff
    | PenaltyOf Float


noDamagePenaltyFrom : Maybe Float -> NoDamagePenalty
noDamagePenaltyFrom reported =
    case reported of
        Just magnitude ->
            if magnitude > 0 then
                PenaltyOf magnitude

            else
                PenaltyOff

        Nothing ->
            PenaltyOff


type alias Scoring =
    { fitness : Fitness

    -- `Nothing` means the run did not say. A crew-ratio run has no time
    -- term at all, but that is the engine's fact to state, not ours.
    , speedBonus : Maybe Bool
    , gate : GateCriterion

    -- A floor on fitness, independent of the gate above: what breeds is
    -- not what promotes, and this touches only the former.
    , noDamagePenalty : NoDamagePenalty
    }



-- HISTORY AND EVENTS


type alias HistoryPoint =
    { generation : Int
    , trainingWinRate : Maybe Float
    , validationWinRate : Maybe Float
    , species : Int
    , nodes : Int
    , episodes : Int
    }


type alias Event =
    { at : String
    , message : String
    }



-- THE WHOLE DOCUMENT


type alias Status =
    { schemaVersion : Int
    , runId : String
    , phase : Phase
    , message : String
    , generation : Int
    , episodes : Int
    , episodesUnresolved : Int

    -- Factual combat victories over the whole run, whatever the gate
    -- counts. `Nothing` when the engine publishes no such counter.
    , episodesCombatWins : Maybe Int
    , elapsedSeconds : Float
    , episodesPerSecond : Float
    , updatedAt : String
    , stale : Bool

    -- Absent on every run that predates the scoring selector. Absence is
    -- not "unknown rule" and it is certainly not the crew ratio.
    , scoring : Maybe Scoring
    , board : Board
    , champion : Champion
    , population : Population
    , checkpoint : Checkpoint
    , resources : Resources
    , work : Maybe Work
    , phases : Maybe PhaseSplit
    , benchmark : Maybe Benchmark
    , readiness : Readiness
    , history : List HistoryPoint
    , overall : Maybe Overall
    , shipPerformance : List ShipPerformance
    , sampler : Maybe Sampler
    , matchups : List Matchup
    , events : List Event
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


{-| A string field the engine nulls when there is nothing to name. An
empty string means the same thing and is folded into `Nothing`, so no
caller has to test for both.
-}
namedOrNothing : Decoder (Maybe String)
namedOrNothing =
    Decode.nullable Decode.string
        |> Decode.map
            (Maybe.andThen
                (\text ->
                    if String.isEmpty text then
                        Nothing

                    else
                        Just text
                )
            )


decodeStatus : Decoder Status
decodeStatus =
    Decode.succeed Status
        |> optional "schema_version" Decode.int 0
        |> optional "run_id" Decode.string ""
        |> optional "phase" (Decode.map phaseFromString Decode.string) (UnknownPhase "unreported")
        |> optional "message" Decode.string ""
        |> optional "generation" Decode.int 0
        |> optional "episodes" Decode.int 0
        |> optional "episodes_unresolved" Decode.int 0
        |> optional "episodes_combat_wins" (Decode.nullable Decode.int) Nothing
        |> optional "elapsed_seconds" (safeFloat 0) 0
        |> optional "episodes_per_second" (safeFloat 0) 0
        |> optional "updated_at" Decode.string ""
        |> optional "stale" Decode.bool False
        |> optional "scoring" (Decode.nullable decodeScoring) Nothing
        |> optional "board" decodeBoard emptyBoard
        |> optional "champion" decodeChampion emptyChampion
        |> optional "population" decodePopulation emptyPopulation
        |> optional "checkpoint" decodeCheckpoint emptyCheckpoint
        |> optional "resources" decodeResources emptyResources
        |> optional "work" (Decode.nullable decodeWork) Nothing
        |> optional "phases" (Decode.nullable decodePhaseSplit) Nothing
        |> optional "benchmark" (Decode.nullable decodeBenchmark) Nothing
        |> optional "readiness" decodeReadiness emptyReadiness
        |> optional "history" (Decode.list decodeHistoryPoint) []
        |> optional "overall" (Decode.nullable decodeOverall) Nothing
        |> optional "ship_performance" (Decode.list decodeShipPerformance) []
        |> optional "sampler" (Decode.nullable decodeSampler) Nothing
        |> optional "matchups" (Decode.list decodeMatchup) []
        |> optional "events" (Decode.list decodeEvent) []


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
        |> optional "champion_id" namedOrNothing Nothing
        |> optional "passed" Decode.bool False
        |> optional "passed_by" namedOrNothing Nothing
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


emptyBoard : Board
emptyBoard =
    { totalMatchups = 0 }


decodeBoard : Decoder Board
decodeBoard =
    Decode.succeed Board
        |> optional "total_matchups" Decode.int 0


emptyReadiness : Readiness
emptyReadiness =
    { threshold = 0, games = 0, lastRate = Nothing, period = 0 }


decodeReadiness : Decoder Readiness
decodeReadiness =
    Decode.succeed Readiness
        |> optional "threshold" (safeFloat 0) 0
        |> optional "games" Decode.int 0
        |> optional "last_rate" finiteFloat Nothing
        |> optional "period" Decode.int 0


{-| The "nothing has been reported yet" status. Decoding `{}` produces
exactly this, so the view's empty states and this value cannot drift.
-}
empty : Status
empty =
    { schemaVersion = 0
    , runId = ""
    , phase = UnknownPhase "unreported"
    , message = ""
    , generation = 0
    , episodes = 0
    , episodesUnresolved = 0
    , episodesCombatWins = Nothing
    , elapsedSeconds = 0
    , episodesPerSecond = 0
    , updatedAt = ""
    , stale = False
    , scoring = Nothing
    , board = emptyBoard
    , champion = emptyChampion
    , population = emptyPopulation
    , checkpoint = emptyCheckpoint
    , resources = emptyResources
    , work = Nothing
    , phases = Nothing
    , benchmark = Nothing
    , readiness = emptyReadiness
    , history = []
    , overall = Nothing
    , shipPerformance = []
    , sampler = Nothing
    , matchups = []
    , events = []
    }


emptyChampion : Champion
emptyChampion =
    { id = Nothing, nodes = Nothing, connections = Nothing, hiddenNodes = Nothing }


decodeChampion : Decoder Champion
decodeChampion =
    Decode.succeed Champion
        |> optional "id" namedOrNothing Nothing
        |> optional "nodes" (Decode.nullable Decode.int) Nothing
        |> optional "connections" (Decode.nullable Decode.int) Nothing
        |> optional "hidden_nodes" (Decode.nullable Decode.int) Nothing


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
    { workers = 0
    , dutyCycle = 0
    , measuredDuty = Nothing
    , computeSeconds = 0
    , episodeTicks = Nothing
    , nice = 0
    }


decodeResources : Decoder Resources
decodeResources =
    Decode.succeed Resources
        |> optional "workers" Decode.int 0
        |> optional "duty_cycle" (safeFloat 0) 0
        |> optional "measured_duty" finiteFloat Nothing
        |> optional "compute_seconds" (safeFloat 0) 0
        |> optional "episode_ticks" (Decode.nullable Decode.int) Nothing
        |> optional "nice" Decode.int 0


decodeWork : Decoder Work
decodeWork =
    Decode.succeed Work
        |> optional "episodes" Decode.int 0
        |> optional "display_ticks" Decode.int 0
        |> optional "decisions" Decode.int 0
        |> optional "node_activations" Decode.int 0
        |> optional "link_activations" Decode.int 0
        |> optional "element_scans" Decode.int 0
        |> optional "elements_visited" Decode.int 0
        |> optional "networks_compiled" Decode.int 0
        |> optional "cpu_nanoseconds_per_display_tick" finiteFloat Nothing
        |> optional "cpu_nanoseconds_per_link_activation" finiteFloat Nothing
        |> optional "display_ticks_per_episode" finiteFloat Nothing
        |> optional "link_activations_per_decision" finiteFloat Nothing
        |> optional "elements_per_scan" finiteFloat Nothing


{-| The seven buckets, in the order the page shows them: the three paid
inside a fight first, since between them they are almost all of it.
-}
phaseBucketNames : List String
phaseBucketNames =
    [ "simulate", "think", "encode", "compile", "evolve", "checkpoint", "serve" ]


decodeBucket : String -> Decoder Bucket
decodeBucket name =
    Decode.oneOf
        [ Decode.field name
            (Decode.succeed (Bucket name)
                |> optional "seconds" (safeFloat 0) 0
                |> optional "share" finiteFloat Nothing
            )
        , Decode.succeed { name = name, seconds = 0, share = Nothing }
        ]


decodePhaseSplit : Decoder PhaseSplit
decodePhaseSplit =
    Decode.succeed PhaseSplit
        |> optional "session_cpu_seconds" finiteFloat Nothing
        |> optional "session_wall_seconds" (safeFloat 0) 0
        |> optional "threads_busy" finiteFloat Nothing
        |> optional "accounted_seconds" (safeFloat 0) 0
        |> optional "accounted_share_of_cpu" finiteFloat Nothing
        |> optional "unaccounted_seconds" finiteFloat Nothing
        |> optional "unaccounted_share_of_cpu" finiteFloat Nothing
        |> custom
            (phaseBucketNames
                |> List.map decodeBucket
                |> List.foldr (Decode.map2 (::)) (Decode.succeed [])
            )


decodeBenchmark : Decoder Benchmark
decodeBenchmark =
    Decode.succeed Benchmark
        |> optional "at" namedOrNothing Nothing
        |> optional "build" namedOrNothing Nothing
        |> optional "definition" namedOrNothing Nothing
        |> optional "repetitions" (Decode.nullable Decode.int) Nothing
        |> optional "fights" (Decode.nullable Decode.int) Nothing
        |> optional "best_seconds" finiteFloat Nothing
        |> optional "cpu_nanoseconds_per_display_tick" finiteFloat Nothing
        |> optional "cpu_nanoseconds_per_link_activation" finiteFloat Nothing
        |> optional "comparable_rows" Decode.int 0


decodeScoring : Decoder Scoring
decodeScoring =
    Decode.succeed
        (\raw zeroOpponent mutualZero speedBonus gate penalty ->
            { fitness = fitnessFrom raw zeroOpponent mutualZero
            , speedBonus = speedBonus
            , gate = gate
            , noDamagePenalty = noDamagePenaltyFrom penalty
            }
        )
        |> optional "fitness" Decode.string ""
        |> optional "zero_opponent" finiteFloat Nothing
        |> optional "mutual_zero" finiteFloat Nothing
        |> optional "speed_bonus" (Decode.nullable Decode.bool) Nothing
        -- A scoring block that names no gate predates the selector, and
        -- the only gate such a build had was actual combat wins. That is
        -- a documented meaning, not a guess, so it is not `UnknownGate`.
        |> optional "gate" (Decode.map gateFrom Decode.string) CombatWins
        |> optional "no_damage_penalty" finiteFloat Nothing


decodeHistoryPoint : Decoder HistoryPoint
decodeHistoryPoint =
    Decode.succeed HistoryPoint
        |> optional "generation" Decode.int 0
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
    , championId : Maybe String
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


{-| With no champion the engine publishes a null genome rather than an
empty object, so the null is folded into the same empty value the view
already renders as "nothing evolved yet".
-}
decodeNetwork : Decoder Network
decodeNetwork =
    Decode.succeed Network
        |> optional "schema_version" Decode.int 0
        |> optional "champion_id" namedOrNothing Nothing
        |> optional "genome"
            (Decode.nullable decodeGenome |> Decode.map (Maybe.withDefault emptyGenome))
            emptyGenome
