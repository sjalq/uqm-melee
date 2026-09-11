module Mario.Dashboard.Copy exposing
    ( allTips
    , championGames
    , championId
    , championLowerBound
    , championRate
    , championStructure
    , checkpointGeneration
    , checkpointPath
    , checkpointResumable
    , checkpointSaved
    , controls
    , elapsed
    , episodes
    , episodesPerSecond
    , expansionBlocked
    , freshness
    , generation
    , heatmap
    , ladder
    , machine
    , matchupCoverage
    , meanConnections
    , meanNodes
    , nextExpansion
    , nodesChart
    , opponentTypes
    , phase
    , populationSize
    , resourcesDuty
    , resourcesWorkers
    , rosterOurs
    , rosterTheirs
    , runId
    , sampleAllocation
    , species
    , stage
    , structureChart
    , target
    , throughputChart
    , timeline
    , topology
    , unevaluated
    , vitals
    , winRateChart
    )

{-| The explanation attached to every number on the dashboard.

Each entry states what the measurement is, what its denominator is, what
time window it covers, and whether it came from training play or from a
fresh audit panel. Those four facts are exactly what separates a gate
you can trust from a number that looks reassuring. They are written here
once, rather than in the view, so no metric can quietly ship without one.

-}

import Mario.Dashboard.Tip as Tip exposing (Tip)


t : String -> String -> String -> List ( String, String ) -> Tip
t =
    Tip.tip


{-| Every tip on the dashboard. Used by the test suite to assert that
each one states its denominator, its window and its evidence source.
-}
allTips : List Tip
allTips =
    [ phase
    , runId
    , freshness
    , vitals
    , machine
    , unevaluated
    , nodesChart
    , generation
    , episodes
    , episodesPerSecond
    , elapsed
    , championId
    , championRate
    , championLowerBound
    , championGames
    , championStructure
    , target
    , stage
    , rosterOurs
    , rosterTheirs
    , opponentTypes
    , nextExpansion
    , expansionBlocked
    , matchupCoverage
    , ladder
    , heatmap
    , sampleAllocation
    , populationSize
    , species
    , meanNodes
    , meanConnections
    , checkpointSaved
    , checkpointGeneration
    , checkpointResumable
    , checkpointPath
    , resourcesWorkers
    , resourcesDuty
    , winRateChart
    , structureChart
    , throughputChart
    , topology
    , timeline
    , controls
    ]



-- RUN HEADER


phase : Tip
phase =
    t "phase"
        "Trainer phase"
        "What the trainer is doing right now. Training means it is playing sampled episodes and breeding the next generation. Auditing means it has frozen a candidate and is spending its audit budget on fresh gate episodes. Paused means the loop is halted at a safe boundary and can resume exactly."
        [ ( "Denominator", "None; this is a state, not a rate." )
        , ( "Window", "Instantaneous, as of the last successful poll." )
        , ( "Source", "Trainer process state." )
        ]


runId : Tip
runId =
    t "run-id"
        "Run identifier"
        "The immutable identity of this training run. Every artifact, checkpoint and audit record for the run lives under this id. A different id means a different run with its own evidence; nothing is carried across."
        [ ( "Denominator", "None." )
        , ( "Window", "Fixed for the lifetime of the run." )
        , ( "Source", "Run directory under artifacts/mario." )
        ]


freshness : Tip
freshness =
    t "freshness"
        "Snapshot age"
        "How long ago the trainer last wrote this status. The dashboard polls every two seconds while the tab is visible. If this grows while the phase says training or auditing, the trainer is stalled, wedged, or gone, and every number below is stale rather than current."
        [ ( "Denominator", "None; an age in seconds." )
        , ( "Window", "Now minus the reported updated_at." )
        , ( "Source", "Trainer clock, compared against this browser's clock." )
        ]


vitals : Tip
vitals =
    t "vitals"
        "Run vitals"
        "Throughput and progress counters for the run as a whole. None of these say anything about how good the champion is; they say how much work has been done and how fast. The gate figures at the top of the page are the ones that speak to quality."
        [ ( "Denominator", "Varies per tile; each states its own." )
        , ( "Window", "Cumulative for the run unless a tile says otherwise." )
        , ( "Source", "Trainer counters, training and audit work combined." )
        ]


machine : Tip
machine =
    t "machine"
        "Population, checkpoint and resources"
        "The state of the evolutionary machinery and the machine it runs on: how many genomes and species exist, how recently the run was made durable, and how much of this computer the trainer is allowed to take."
        [ ( "Denominator", "Varies per row; each states its own." )
        , ( "Window", "Current generation for population, most recent save for checkpoint." )
        , ( "Source", "Evolution loop, checkpoint writer and evaluator scheduling." )
        ]


unevaluated : Tip
unevaluated =
    t "unevaluated"
        "Unevaluated cells"
        "How many active ordered matchups at this stage have no audit games at all. These are not failures and not zeroes; they are holes in the evidence. The gate cannot pass while any of them remain, because an unplayed cell has not been shown to be won."
        [ ( "Denominator", "Active ordered matchups at the current stage." )
        , ( "Window", "Current stage, current champion." )
        , ( "Source", "Audit evidence. A cell with training play but no audit games still counts as unevaluated here." )
        ]


nodesChart : Tip
nodesChart =
    t "chart-nodes"
        "Champion node count"
        "Nodes in the champion genome per generation. The first 70 are the fixed 57 inputs and 13 outputs and are present from the very first seeded genome; everything above that line is hidden structure this run actually discovered."
        [ ( "Denominator", "None; a count per generation." )
        , ( "Window", "Per generation, whole run." )
        , ( "Source", "Champion genome census. Structure, not performance." )
        ]


generation : Tip
generation =
    t "generation"
        "Generation"
        "How many complete NEAT generations have been bred and scored. One generation evaluates every population member on the same sampled panel, then applies species allocation, crossover and mutation."
        [ ( "Denominator", "None; a count." )
        , ( "Window", "Cumulative since the run started, preserved across resume." )
        , ( "Source", "Evolution loop." )
        ]


episodes : Tip
episodes =
    t "episodes"
        "Episodes resolved"
        "Total melee episodes simulated in this run, counting training play and audit play together. One episode is one ordered matchup played to a real resolved outcome or to the configured display-tick deadline."
        [ ( "Denominator", "None; a count." )
        , ( "Window", "Cumulative since the run started, preserved across resume." )
        , ( "Source", "Training and audit episodes combined. Use the matchup grid for audit-only evidence." )
        ]


episodesPerSecond : Tip
episodesPerSecond =
    t "throughput"
        "Throughput"
        "Episodes resolved per wall-clock second. This is throughput under the configured duty cycle, so it already reflects the deliberate rest periods that keep the machine usable, not the trainer's peak speed."
        [ ( "Denominator", "Wall-clock seconds, including rest periods." )
        , ( "Window", "As reported by the trainer for its recent batches." )
        , ( "Source", "Evaluator scheduling." )
        ]


elapsed : Tip
elapsed =
    t "elapsed"
        "Elapsed"
        "Total wall-clock time this run has spent training, summed across every start and resume. Time while the process was stopped does not count."
        [ ( "Denominator", "None; a duration." )
        , ( "Window", "Cumulative across all sessions of this run." )
        , ( "Source", "Checkpointed elapsed totals." )
        ]



-- CHAMPION GATE


championId : Tip
championId =
    t "champion-id"
        "Current champion"
        "The genome whose audit evidence is shown on this page. Audit evidence belongs to one specific champion fingerprint. When the champion changes, evidence gathered for the previous one is discarded rather than pooled, so a fresh champion legitimately starts again at no samples."
        [ ( "Denominator", "None; an identity." )
        , ( "Window", "Current as of the last poll." )
        , ( "Source", "Frozen candidate under audit." )
        ]


championRate : Tip
championRate =
    t "champion-rate"
        "Champion fresh audit win rate"
        "Wins divided by games on the champion's predeclared audit panel. These are fresh gate episodes on gate seeds, played after the candidate was frozen. They are not training episodes and they are not pooled across the population, so this is the number that actually speaks to whether the champion is any good."
        [ ( "Denominator", "Audit games played by this champion at the current stage." )
        , ( "Window", "The current champion's audit panel only. Reset when the champion changes." )
        , ( "Source", "Audit, on gate seeds separate from the training seeds." )
        ]


championLowerBound : Tip
championLowerBound =
    t "champion-bound"
        "Wilson lower bound"
        "The lower end of a Wilson confidence interval on the champion's audit win rate. Promotion is gated on this bound clearing the target, not on the raw rate, because a raw rate over the target on a handful of games is mostly luck. A small panel produces a low bound even when every game was won."
        [ ( "Denominator", "The same audit games as the win rate above." )
        , ( "Window", "Current champion, current stage." )
        , ( "Source", "Audit. Computed by the trainer, displayed here unchanged." )
        ]


championGames : Tip
championGames =
    t "champion-games"
        "Audit sample size"
        "Wins over games on the champion's audit panel. Panels are predeclared and finite, and audit and confirmation panels do not overlap, so this number rises in fixed steps rather than being extended until the result looks good. Repeated peeking at an arbitrary panel size is exactly how a lucky candidate gets promoted."
        [ ( "Denominator", "Games on the predeclared audit panel." )
        , ( "Window", "Current champion, current stage." )
        , ( "Source", "Audit." )
        ]


championStructure : Tip
championStructure =
    t "champion-structure"
        "Champion topology size"
        "Nodes and enabled connections in the champion genome. Topology is evolved, not fixed: there is no preset hidden layer, so both numbers grow only when a structural mutation survives selection."
        [ ( "Denominator", "None; counts of graph elements." )
        , ( "Window", "Current champion genome." )
        , ( "Source", "Genome served by the network endpoint." )
        ]


target : Tip
target =
    t "target"
        "Gate target"
        "The win rate every active ordered matchup must clear before the curriculum expands. The gate is per cell, not pooled: an overall average above the target means nothing if one matchup is still losing, because the average can hide a weak cell behind many strong ones."
        [ ( "Denominator", "Applied to each ordered matchup separately." )
        , ( "Window", "Current stage." )
        , ( "Source", "Run configuration, immutable for the run." )
        ]



-- CURRICULUM


stage : Tip
stage =
    t "stage"
        "Curriculum stage"
        "How far the roster expansion has progressed. Stage 0 is a single ordered pair, our Pkunk against the opponent Umgah. Each promotion adds one ship, alternating opponent side then our side, until both rosters hold all 25 ships."
        [ ( "Denominator", "None; a stage index." )
        , ( "Window", "Current." )
        , ( "Source", "Curriculum state, checkpointed." )
        ]


rosterOurs : Tip
rosterOurs =
    t "roster-ours"
        "Our roster"
        "The ships the learner may be assigned to fly at this stage, in the frozen expansion order. Pkunk is the fixed seed. The order is fixed up front so the curriculum cannot be quietly reshuffled to make a stuck stage easier."
        [ ( "Denominator", "None; a list." )
        , ( "Window", "Current stage." )
        , ( "Source", "Frozen curriculum order." )
        ]


rosterTheirs : Tip
rosterTheirs =
    t "roster-theirs"
        "Opponent roster"
        "The ships the opponent may fly at this stage, in the frozen expansion order. Umgah is the fixed seed."
        [ ( "Denominator", "None; a list." )
        , ( "Window", "Current stage." )
        , ( "Source", "Frozen curriculum order." )
        ]


opponentTypes : Tip
opponentTypes =
    t "opponent-types"
        "Opponent types in play"
        "Cyborg means the original game's Awesome-rated computer pilot. Frozen model means an immutable snapshot of an earlier champion. Model opponents only join after the full 25 by 25 cyborg gate is passed, and cyborg sampling continues alongside them. A frozen opponent's weights never change during a generation or an audit."
        [ ( "Denominator", "None; a list." )
        , ( "Window", "Current stage." )
        , ( "Source", "Curriculum state. Evidence is versioned by opponent fingerprint." )
        ]


nextExpansion : Tip
nextExpansion =
    t "next-expansion"
        "Next expansion"
        "Which side gains a ship, and which ship, once every active ordered matchup at this stage passes the gate. Expansion alternates opponent side then our side."
        [ ( "Denominator", "None." )
        , ( "Window", "The next promotion." )
        , ( "Source", "Frozen curriculum order." )
        ]


expansionBlocked : Tip
expansionBlocked =
    t "expansion-blocked"
        "Why the roster is not expanding"
        "Expansion requires every active ordered matchup at this stage to clear the gate on fresh audit evidence, in both seat orientations. This lists the cells still holding it back, split by whether they have never been played, are still being trained, are mid-audit, or have been audited and fallen short."
        [ ( "Denominator", "Active ordered matchups at the current stage." )
        , ( "Window", "Current stage, current champion." )
        , ( "Source", "Per-cell audit evidence, not pooled population training results." )
        ]


matchupCoverage : Tip
matchupCoverage =
    t "coverage"
        "Mastered matchups"
        "How many of the active ordered matchups at this stage have cleared the gate on fresh audit evidence. Ordered means our ship against their ship in a specific seat; the reverse pairing is a separate cell that must pass on its own."
        [ ( "Denominator", "All active ordered matchups at the current stage." )
        , ( "Window", "Current stage, current champion." )
        , ( "Source", "Audit. Not an average over cells, but a count of cells that individually passed." )
        ]


ladder : Tip
ladder =
    t "ladder"
        "Curriculum ladder"
        "The roster expansion from the seeded single pair up to the full 25 by 25 grid. The highlighted rung is where the run is now. Every earlier rung was left behind only by passing its gate; rungs above have not been attempted."
        [ ( "Denominator", "Ordered matchups implied by each roster size." )
        , ( "Window", "Whole run." )
        , ( "Source", "Frozen curriculum order plus the current stage." )
        ]


heatmap : Tip
heatmap =
    t "heatmap"
        "Matchup evidence grid"
        "One cell per ordered matchup: our ship in the row, the opponent in the column. Colour follows the Wilson lower bound where one exists, so a cell is only bright when the evidence is genuinely strong. Cells with no games are drawn as unmeasured rather than as zero, because never played and always lost are very different things."
        [ ( "Denominator", "Per cell, the audit games played for that exact ordered pair." )
        , ( "Window", "Current stage and current champion only. Earlier stages and earlier champions are not shown or mixed in." )
        , ( "Source", "Audit evidence for the current champion. This is not population training win rate." )
        ]


sampleAllocation : Tip
sampleAllocation =
    t "allocation"
        "Training sample allocation"
        "How the next generation's training panel is weighted across cells. The mixture deliberately favours weak and uncertain cells and newly added ones, while a coverage floor keeps every active cell rehearsed so old matchups are not forgotten. Both seat orientations are represented. Every population member is scored on the same sampled panel in a generation, and when the panel changes, elites are rescored rather than keeping a stale fitness."
        [ ( "Denominator", "Share of total sampling weight across active cells." )
        , ( "Window", "The upcoming generation's panel." )
        , ( "Source", "Training sampler. Training seeds are separate from gate seeds, and these weights do not feed the gate." )
        ]



-- POPULATION


populationSize : Tip
populationSize =
    t "pop-size"
        "Population"
        "How many genomes are alive in the current generation. Every one of them is evaluated on the same sampled panel each generation, so their scores are comparable within that generation."
        [ ( "Denominator", "None; a count." )
        , ( "Window", "Current generation." )
        , ( "Source", "Evolution loop." )
        ]


species : Tip
species =
    t "species"
        "Species"
        "How many species the population currently splits into under the compatibility measure. Speciation protects a structural innovation long enough to be optimised instead of being out-competed the generation it appears. A collapse toward one species means diversity has been lost."
        [ ( "Denominator", "None; a count." )
        , ( "Window", "Current generation." )
        , ( "Source", "Speciation step." )
        ]


meanNodes : Tip
meanNodes =
    t "mean-nodes"
        "Mean nodes"
        "Average node count across the population, including the fixed 57 inputs and 13 outputs. Growth above the fixed 70 is the topology the run has actually discovered."
        [ ( "Denominator", "Population size." )
        , ( "Window", "Current generation." )
        , ( "Source", "Genome census." )
        ]


meanConnections : Tip
meanConnections =
    t "mean-connections"
        "Mean connections"
        "Average enabled connection count across the population. Networks are seeded minimal and sparse, so this starts small and rises only as link mutations survive selection."
        [ ( "Denominator", "Population size." )
        , ( "Window", "Current generation." )
        , ( "Source", "Genome census." )
        ]



-- CHECKPOINT AND RESOURCES


checkpointSaved : Tip
checkpointSaved =
    t "ckpt-saved"
        "Last checkpoint"
        "When the trainer last wrote a complete, atomic checkpoint. Checkpoints are written at completed batch and generation boundaries and capture the exact RNG state, genomes, species, innovations, curriculum, sampler statistics, pending work, frozen opponents and audit evidence."
        [ ( "Denominator", "None; an instant." )
        , ( "Window", "Most recent save." )
        , ( "Source", "Checkpoint writer." )
        ]


checkpointGeneration : Tip
checkpointGeneration =
    t "ckpt-generation"
        "Checkpointed generation"
        "The generation captured in the last checkpoint. If this lags the live generation, the work since then would be replayed deterministically on resume rather than lost."
        [ ( "Denominator", "None; a count." )
        , ( "Window", "Most recent save." )
        , ( "Source", "Checkpoint writer." )
        ]


checkpointResumable : Tip
checkpointResumable =
    t "ckpt-resumable"
        "Resumable"
        "Whether the trainer can restart from the checkpoint and follow the same trajectory it would have followed uninterrupted. Evolution, sampling and evaluation each use their own generator, so scheduling differences cannot change outcomes."
        [ ( "Denominator", "None; a yes or no." )
        , ( "Window", "Most recent save." )
        , ( "Source", "Checkpoint validation." )
        ]


checkpointPath : Tip
checkpointPath =
    t "ckpt-path"
        "Checkpoint path"
        "Where this run's immutable artifacts live. Every run gets its own directory, so re-running never overwrites earlier evidence."
        [ ( "Denominator", "None; a path." )
        , ( "Window", "Fixed for the run." )
        , ( "Source", "Run configuration." )
        ]


resourcesWorkers : Tip
resourcesWorkers =
    t "res-workers"
        "Evaluator threads"
        "How many evaluator threads the trainer runs. The trainer is deliberately built to occupy about one core so the machine stays usable while it works."
        [ ( "Denominator", "None; a count." )
        , ( "Window", "Current configuration." )
        , ( "Source", "Run configuration." )
        ]


resourcesDuty : Tip
resourcesDuty =
    t "res-duty"
        "Duty cycle"
        "The measured fraction of each batch spent working rather than resting. It is enforced by real sleeps between batches, not by a busy wait, so a duty cycle of one half means the evaluator genuinely idles half the time."
        [ ( "Denominator", "Work time over work plus rest time per batch." )
        , ( "Window", "Recent batches." )
        , ( "Source", "Evaluator scheduling, measured rather than assumed." )
        ]



-- CHARTS


winRateChart : Tip
winRateChart =
    t "chart-winrate"
        "Win rate over generations"
        "Two different measurements, drawn so they cannot be mistaken for each other. The training line is the population's win rate on the sampled training panel, which changes from generation to generation and is not gate evidence. The audit markers are the champion's fresh win rate on a predeclared gate panel. The line breaks at every stage change because a rate measured against a small roster is not comparable with one measured against a larger one."
        [ ( "Denominator", "Training: episodes on that generation's sampled panel. Audit: games on the predeclared gate panel." )
        , ( "Window", "Per generation, whole run, split at stage boundaries." )
        , ( "Source", "Two distinct sources, never averaged together. Unmeasured generations leave a gap rather than a zero." )
        ]


structureChart : Tip
structureChart =
    t "chart-species"
        "Species count"
        "How many species the population splits into, per generation. Speciation is what protects a new structural idea long enough to be optimised. A collapse toward one species alongside rising node counts usually means a single lineage has taken over and structural exploration has stopped."
        [ ( "Denominator", "None; a count per generation." )
        , ( "Window", "Per generation, whole run." )
        , ( "Source", "Speciation step. Deliberately kept off the win rate chart so structure is never read as performance." )
        ]


throughputChart : Tip
throughputChart =
    t "chart-throughput"
        "Episodes per generation"
        "How many episodes each generation consumed. Sharp rises usually mean an audit ran, since audit panels are spent in addition to training play."
        [ ( "Denominator", "Episodes attributed to each generation." )
        , ( "Window", "Per generation, whole run." )
        , ( "Source", "Training and audit episodes combined." )
        ]



-- NETWORK AND EVENTS


topology : Tip
topology =
    t "topology"
        "Champion network"
        "The champion's evolved graph. The 57 inputs are grouped and individually labelled: 33 combat sensors, our ship's 5 identity bits, the opponent's 5 identity bits, the 5 control bits actually applied last step, the 8 memory channels fed back from last step, and the extra bias. The 13 outputs are the 5 controls and the 8 memory channels. Hidden nodes and every connection between them were produced by structural mutation, not by a fixed layer."
        [ ( "Denominator", "None; a graph." )
        , ( "Window", "Current champion genome, as served by the network endpoint." )
        , ( "Source", "Genome. Connection weights are shown as stored; no activations are replayed here." )
        ]


timeline : Tip
timeline =
    t "timeline"
        "Run events"
        "Notable transitions the trainer recorded: promotions, audits started and finished, checkpoints, pauses and errors. This is the run's own account of what happened, in its own clock."
        [ ( "Denominator", "None; a list." )
        , ( "Window", "The most recent events the trainer retains." )
        , ( "Source", "Trainer event log." )
        ]


controls : Tip
controls =
    t "controls"
        "Run controls"
        "Pause halts the loop at a safe boundary, so a resume continues the same trajectory rather than restarting a batch differently. Stop shuts the run down after writing a checkpoint. Both are requests to the trainer: the button shows a pending state until the trainer acknowledges, and a failure is reported rather than silently assumed to have worked."
        [ ( "Denominator", "None; actions." )
        , ( "Window", "Immediate." )
        , ( "Source", "POST to the local control endpoint on the loopback interface." )
        ]
