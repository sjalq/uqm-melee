module Mario.Dashboard.Copy exposing
    ( allTips
    , benchmark
    , board
    , championId
    , checkpointGeneration
    , checkpointPath
    , checkpointResumable
    , checkpointSaved
    , combatVictories
    , controls
    , elapsed
    , episodes
    , episodesPerSecond
    , fightLimit
    , fitnessRule
    , freshness
    , gateCriterion
    , generation
    , heatmap
    , meanConnections
    , meanNodes
    , nextGate
    , noDamagePenalty
    , nodesChart
    , nowPlaying
    , observedNeeded
    , overallGate
    , overallPanel
    , overallRound
    , phase
    , phaseSplit
    , populationPanel
    , populationSize
    , readiness
    , resourcesBudget
    , resourcesDuty
    , resourcesWorkers
    , runId
    , sampleAllocation
    , samplerCoverage
    , shipPerformance
    , species
    , structureChart
    , timeline
    , topology
    , unresolved
    , winRateChart
    , workRates
    )

{-| The explanation attached to every number on the dashboard.

Each entry states what the measurement is, what its denominator is, what
time window it covers, and whether it came from training play or from a
fresh audit panel. Those four facts are exactly what separates a gate
you can trust from a number that looks reassuring. They are written here
once, rather than in the view, so no metric can quietly ship without one.

-}

import Mario.Dashboard.Api as Api
import Mario.Dashboard.Scoring as Scoring
import Mario.Dashboard.Tip as Tip exposing (Tip)


{-| The run's own noun for one counted success, and for the rate those
counts make. Every tip below that names what a figure counts asks for
these rather than writing "win", because under a crew-lead gate the
tallies are not wins and a tooltip is exactly where a reader goes to
find out what a number means.
-}
successes : Maybe Api.Scoring -> String
successes =
    Scoring.successPlural


rateOf : Maybe Api.Scoring -> String
rateOf =
    Scoring.rateLabel


t : String -> String -> String -> List ( String, String ) -> Tip
t =
    Tip.tip


{-| Every tip on the dashboard, as the run in front of the reader would
render them. Used by the test suite to assert that each one states its
denominator, its window and its evidence source, under either criterion.
-}
allTips : Maybe Api.Scoring -> List Tip
allTips scoring =
    [ phase
    , runId
    , freshness
    , controls
    , overallGate scoring
    , overallPanel
    , overallRound
    , championId
    , observedNeeded scoring
    , gateCriterion
    , winRateChart scoring
    , nowPlaying
    , board
    , samplerCoverage
    , fitnessRule
    , fightLimit
    , noDamagePenalty
    , nextGate
    , readiness
    , sampleAllocation
    , populationPanel
    , populationSize
    , species
    , meanNodes
    , meanConnections
    , structureChart
    , nodesChart
    , shipPerformance scoring
    , heatmap
    , topology
    , workRates
    , phaseSplit
    , benchmark
    , episodesPerSecond
    , elapsed
    , episodes
    , generation
    , unresolved scoring
    , combatVictories
    , resourcesWorkers
    , resourcesDuty
    , resourcesBudget
    , checkpointSaved
    , checkpointGeneration
    , checkpointResumable
    , checkpointPath
    , timeline
    ]



-- SCORING
--
-- Three tips, not one, because three different things get confused with
-- one another here: the rule that ranks breeding, the deadline the rule
-- is read at, and the separate evidence a promotion is judged on.


fitnessRule : Tip
fitnessRule =
    t "fitness-rule"
        "Scoring rule"
        "What the trainer maximises when it decides which genomes breed. A crew ratio is a ratio of two shares, not a percentage of anything: 1.00 means both sides kept the same share of the crew they started with, and a value above 1.00 says our side kept more, not that the fight was won. It is not a fraction of maximum health, and it is not the gate."
        [ ( "Denominator", "The opponent's surviving share of their starting crew; a ratio of two shares has no percentage denominator of its own." )
        , ( "Window", "Every episode scored in the current generation, read when the fight ends, or at the cut-off if neither side has finished by then." )
        , ( "Source", "Trainer configuration, republished with every status snapshot." )
        ]


fightLimit : Tip
fightLimit =
    t "fight-limit"
        "Fight length"
        "How long a fight may run in the simulation before it is cut off and scored where it stands. A fight that ends is scored when it ends; only one that neither side has finished runs to this limit. Under the crew ratio the two are scored by exactly the same rule, with no bonus for finishing early."
        [ ( "Denominator", "None; simulated time, the reported episode tick budget over 60 simulation ticks per second. It is not machine wall time, and a fight takes far less of that to run." )
        , ( "Window", "Each individual episode." )
        , ( "Source", "Trainer resource caps, field episode_ticks." )
        ]


noDamagePenalty : Tip
noDamagePenalty =
    t "no-damage-penalty"
        "No-damage penalty"
        "A conditional replacement for fitness, not an adjustment to it. When a fight ends with the other side's crew no smaller than the number it started with, the genome's fitness becomes the negative of this magnitude and the run's ordinary scoring rule is not consulted. It reads their crew at the end against their crew at the start, so it says nothing about damage we dealt and later lost to their recovery."
        [ ( "Denominator", "None; it is a fitness value in the run's own scoring units, reported as a positive magnitude and applied negated." )
        , ( "Window", "Each individual episode, judged at the moment the fight stops." )
        , ( "Source", "Trainer scoring block, field no_damage_penalty. Absent or zero means the run applies none." )
        ]


combatVictories : Tip
combatVictories =
    t "combat-victories"
        "Actual combat victories"
        "A count of episodes our side actually resolved in its favour, across the whole population, whatever the run is gated on. It is the one tally on this page that is a win count, and it is deliberately not a rate: it cannot be compared with the champion's gate figure, which is one genome's record on a predeclared panel. When the counter started part-way through a run its baseline is named alongside it, because the run's true total is then unknown."
        [ ( "Denominator", "None; it is a count of episodes, not a share of them. Divide it by nothing on this page." )
        , ( "Window", "Every episode in the counting window the trainer reports, population-wide, cumulative." )
        , ( "Source", "Trainer field episodes_combat_wins_all_time, or the partial counter with its episode baseline when no all-time figure is published." )
        ]


gateCriterion : Tip
gateCriterion =
    t "gate-criterion"
        "Fitness is not the gate"
        "The scoring rule ranks the population for breeding. This gate decides whether the run is allowed to move on, and it is judged on fresh audit evidence which may measure something else entirely. A champion can be the best-scoring genome in the population and still fail this gate, and that is the point of keeping them apart."
        [ ( "Denominator", "The gate's own predeclared panel of audit games." )
        , ( "Window", "The current champion's audit panel only." )
        , ( "Source", "Trainer scoring block, which names the gate criterion alongside the fitness." )
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


nodesChart : Tip
nodesChart =
    t "chart-nodes"
        "Champion node count"
        "Nodes in the champion genome per generation. The first 154 are the fixed 141 inputs and 13 outputs and are present from the very first seeded genome; everything above that line is hidden structure this run actually discovered."
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
        "Episodes resolved per WALL-CLOCK second, which makes it load dependent: it falls when something else uses the machine, rises with more workers, and already reflects the duty governor's deliberate rest. It is a measure of how fast this session happens to be going, never of what the build costs. The nanoseconds-per-unit-of-work figures beside it are the ones that hold still."
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


observedNeeded : Maybe Api.Scoring -> Tip
observedNeeded scoring =
    t "observed-needed"
        ("Observed " ++ successes scoring ++ " the gate actually demands")
        ("The target is a floor on the Wilson lower bound, not on the observed rate, so the raw score a candidate must post is higher than the target. On a panel of 100 against an 80% target, 80 out of 100 fails: the bound on 80/100 is about 71%. It takes 88 counted "
            ++ successes scoring
            ++ " for the bound to clear 80%. Reading the target as though it were an observed rate is the single easiest way to believe a candidate passed when it did not."
        )
        [ ( "Denominator", "The predeclared audit panel size." )
        , ( "Window", "Per audit attempt." )
        , ( "Source", "Computed by the dashboard as the inverse of the Wilson bound at 95% confidence, z = 1.96. The trainer publishes the bound itself; this is the smallest count that reaches it." )
        ]


unresolved : Maybe Api.Scoring -> Tip
unresolved scoring =
    t "unresolved"
        "Unresolved episodes"
        (case Scoring.criterion scoring of
            Api.CrewLead ->
                "Episodes that ended without a resolved combat outcome: the display-tick deadline reached with both ships still flying, and episodes ended by selection or resurrection rather than by a kill. Under this run's gate they are not discarded. They are scored on crew share like any other episode and can count as leads, so a rising count here does not thin out the evidence behind the rates above; it changes what kind of fight most of that evidence describes."

            _ ->
                "Episodes that ended without a real resolved outcome, usually two ships that never finished each other off. These are invalidated, not won. A timeout is not a victory for either side and is never scored as one, so a rising count here means the win rates above rest on fewer real fights than the episode total suggests."
        )
        [ ( "Denominator", "Total episodes in the run." )
        , ( "Window", "Cumulative since the run started." )
        , ( "Source", "Episode outcomes. Counted separately from the gate tallies precisely so it cannot be mistaken for one." )
        ]


readiness : Tip
readiness =
    t "readiness"
        "Readiness screen"
        "A cheap recurring check that decides when a candidate is worth spending an expensive audit panel on. It is a screening test, not gate evidence: passing it only buys the right to be audited, and its rate never counts toward a promotion."
        [ ( "Denominator", "Games in the readiness sample." )
        , ( "Window", "Re-checked every few generations, as given by the period." )
        , ( "Source", "Training-side screening. Never pooled with audit evidence." )
        ]


heatmap : Tip
heatmap =
    t "heatmap"
        "Matchup training exposure"
        "One cell per ordered matchup: our ship in the row, the opponent in the column. Colour follows the sampler's own decayed training rate for that cell, and a cell with no training games is drawn as unmeasured rather than as zero, because never practised and always beaten are very different things. Nothing here is held-out evidence and no cell has a gate of its own; the aggregate target is drawn on the same scale only so the spread can be read against the one number the run is graded on."
        [ ( "Denominator", "Per cell, that cell's decayed training games. The count is fractional because older games decay rather than being dropped." )
        , ( "Window", "Cumulative training play, decayed toward recent generations." )
        , ( "Source", "The training sampler's own tallies. Not audit evidence, and it gates nothing." )
        ]


sampleAllocation : Tip
sampleAllocation =
    t "allocation"
        "Training sample allocation"
        "How the next generation's training panel is weighted across the 625 cells. The mixture deliberately favours cells with little evidence and cells whose outcome is still close, while a coverage floor keeps every cell rehearsed so none is forgotten. Both seat orientations are represented. Every population member is scored on the same sampled panel in a generation, and when the panel changes, elites are rescored rather than keeping a stale fitness."
        [ ( "Denominator", "Share of total sampling weight across all 625 cells." )
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
        "Average node count across the population, including the fixed 141 inputs and 13 outputs. Growth above the fixed 154 is the topology the run has actually discovered."
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
        "How many evaluator threads the pool actually runs, not how many were asked for. One is the legacy single-threaded trainer. More than one means independent fights and networks are evaluated side by side; the work is still planned and reduced in the one serial order, so the count changes how fast a generation finishes and never what it finds."
        [ ( "Denominator", "None; a count of live pool threads." )
        , ( "Window", "Current pool." )
        , ( "Source", "The running pool, reported rather than configured." )
        ]


resourcesDuty : Tip
resourcesDuty =
    t "res-duty"
        "Duty cycle"
        "The fraction of wall time the scheduler spends working rather than resting, enforced by real sleeps between batches rather than a busy wait. It is a scheduling figure, not a CPU measurement: an unbalanced batch can be wall-active the whole time with only one thread of the pool busy, so a full duty cycle never by itself means the threads beside it are full. The measurement accumulates over the whole run rather than over recent batches, so a run resumed under a raised cap reads below that cap until the new history outweighs the hours recorded under the old one. The cores line states the configured budget, threads multiplied by the cap, which is the capacity the run may use and not the load it is measured to draw."
        [ ( "Denominator", "Wall time working over working plus resting, accumulated since the run began." )
        , ( "Window", "Accumulated run history, including earlier sessions and earlier resource settings." )
        , ( "Source", "Evaluator scheduling, measured rather than assumed. Actual CPU load is measured outside the trainer." )
        ]


resourcesBudget : Tip
resourcesBudget =
    t "res-budget"
        "Compute budget"
        "The threads the pool runs multiplied by the duty cap: the share of the machine this run is allowed to occupy, stated in cores. It is a ceiling the scheduler is built to respect and never a measurement of load. What the run actually draws is measured outside the trainer, and an unbalanced batch or a serial stretch will draw less than the budget while the duty cycle still reads full."
        [ ( "Denominator", "Cores; threads multiplied by the duty cap." )
        , ( "Window", "Current pool and configuration." )
        , ( "Source", "Pool size and configured cap. Not a CPU measurement." )
        ]



-- CHARTS


winRateChart : Maybe Api.Scoring -> Tip
winRateChart scoring =
    t "chart-winrate"
        (Scoring.successHeading scoring ++ " over generations")
        ("Two screening measurements, drawn so they cannot be mistaken for each other, and neither of them is gate evidence. The training line is the champion's own "
            ++ rateOf scoring
            ++ " on that generation's sampled training panel, recorded for the champion's member alone rather than averaged over the population. The markers are the recurring readiness probe: the trainer publishes them as the run's validation figure, but the probe only decides when an audit is worth spending, so a marker is never a passed gate. Both ask the same question the gate asks, on the run's own criterion. Every point measures the same whole board, so the only break in either line is an unmeasured generation."
        )
        [ ( "Denominator", "Training: episodes on that generation's sampled panel for the champion's own member. Readiness: games in the probe's own batch." )
        , ( "Window", "Per generation, whole run." )
        , ( "Source", "Training play and the readiness probe, never averaged together. Neither is audit evidence; the gate panel above is. Unmeasured generations leave a gap rather than a zero." )
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



-- NETWORK AND EVENTS


topology : Tip
topology =
    t "topology"
        "Champion network"
        "The champion's evolved graph. The 141 inputs are grouped and individually labelled: 117 combat sensors, our ship's 5 identity bits, the opponent's 5 identity bits, the 5 control bits actually applied last step, the 8 memory channels fed back from last step, and the extra bias. The 13 outputs are the 5 controls and the 8 memory channels. Hidden nodes and every connection between them were produced by structural mutation, not by a fixed layer."
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


overallGate : Maybe Api.Scoring -> Tip
overallGate scoring =
    t "overall-gate"
        ("Overall balanced " ++ rateOf scoring)
        ("The frozen champion's "
            ++ rateOf scoring
            ++ " on a fixed held-out balanced panel: all 25 of our hulls and all 25 opponent hulls equally represented, pairings randomised, every pair played in both seats. The gate is a floor on the Wilson lower bound, cleared on an audit round and then again on an independent confirm round. Because each pair is played in both seats the outcomes are correlated, so this is an operational confidence check on the distribution, not a formal guarantee about every matchup."
        )
        [ ( "Denominator"
          , case Scoring.criterion scoring of
                Api.CrewLead ->
                    "Games on the current round's balanced held-out panel. All games count, including unresolved ones, which are scored on crew share like any other."

                _ ->
                    "Games on the current round's balanced held-out panel. All games count, including timeouts, which count as non-wins."
          )
        , ( "Window", "One round, one frozen champion. Rounds are never added together." )
        , ( "Source", "Held-out gate evidence. Not training play, and not the readiness probe." )
        ]


overallPanel : Tip
overallPanel =
    t "overall-panel"
        "Balanced held-out panel"
        "The predeclared size of each gate round, built as pairs played in both seats so neither seat can be over-represented. The panel does not enumerate all 625 ordered matchups; it draws a balanced sample in which every hull appears equally often on each side."
        [ ( "Denominator", "Games per round, and the pair count behind them." )
        , ( "Window", "Per round; the audit and confirm rounds each get their own panel and their own trial counter." )
        , ( "Source", "Predeclared before the round opens, never resized mid-attempt." )
        ]


overallRound : Tip
overallRound =
    t "overall-round"
        "Gate round"
        "Which of the two rounds is in flight. The audit round comes first; clearing it is provisional. The same frozen champion then has to clear an independent confirm round on a separate panel with its own trial counter before the gate is passed. A round can be abandoned early once the target has become arithmetically unreachable."
        [ ( "Denominator", "None; a phase." )
        , ( "Window", "The current attempt." )
        , ( "Source", "The trainer's declared round." )
        ]


shipPerformance : Maybe Api.Scoring -> Tip
shipPerformance scoring =
    t "ship-performance"
        "Per-hull blind spots"
        ("The same gate evidence broken out by hull. Both columns count OUR champion's "
            ++ successes scoring
            ++ ": the \"when piloting\" rows group those by the hull our champion flew, and the \"when facing\" rows group the very same ones by the hull it flew against. A low \"when facing\" figure means our champion does badly against that hull; it is not that hull's own count and not an inverse. Nothing here gates anything, and there is no per-hull minimum: this table exists to expose where an aggregate pass is hiding a weakness."
        )
        [ ( "Denominator", "Per hull, the games on the current round's balanced panel in that grouping. A hull with no games shows as unmeasured, never as 0%." )
        , ( "Window", "One round, the one currently frozen champion. Never pooled across champions." )
        , ( "Source", "Labelled per row: an audit or confirm round is gate evidence; a readiness row is the cheap 250-game probe and is a diagnostic only." )
        ]


samplerCoverage : Tip
samplerCoverage =
    t "sampler-coverage"
        "Training sampler"
        "How each generation's shared training panel is drawn. One part is a balanced rotation that walks own and opponent hulls evenly across generations from a checkpointed cursor, so coverage cannot drift; the rest is drawn adaptively toward cells that look uncertain or learnable. The balanced share is a property of how the panel is built, not a measurement of how much of the 625-cell board has been seen."
        [ ( "Denominator", "Episodes per generation in the shared panel, and the share of it reserved for the balanced rotation." )
        , ( "Window", "Per generation; the cursor and completed tours are cumulative over the run." )
        , ( "Source", "Training sampler configuration and its checkpointed rotation state. Not gate evidence." )
        ]



-- WHAT IT IS DOING RIGHT NOW


nowPlaying : Tip
nowPlaying =
    t "now-playing"
        "What it is playing"
        "What the trainer is spending its next episodes on: which gate round is in flight if any, how the shared training panel is drawn, and the rules every one of those fights is scored under. None of this says how good the champion is; it says what question is currently being asked of it."
        [ ( "Denominator", "Varies per row; each states its own." )
        , ( "Window", "The generation in flight." )
        , ( "Source", "Trainer scheduling and run configuration, republished with every snapshot." )
        ]


board : Tip
board =
    t "board"
        "Active board"
        "Every ordered matchup the run trains on, and it is all of them from generation one. Our ship against their ship is a different cell from the reverse, so both orientations are counted separately. Nothing here is earned: this is the size of the problem, never progress through it."
        [ ( "Denominator", "None; a count of ordered pairs." )
        , ( "Window", "Fixed for the lifetime of the run." )
        , ( "Source", "The engine's board definition." )
        ]


nextGate : Tip
nextGate =
    t "next-gate"
        "What opens the next gate"
        "The sequence a champion has to walk to clear the gate, in order: pass the cheap readiness probe, then post the demanded count on a full audit panel, then post it again on an independent confirm panel. Stating only the target percentage hides the first and third steps, and hides that the demanded count is higher than the target because the bound has to clear it rather than the raw rate."
        [ ( "Denominator", "The readiness sample for the probe; the predeclared panel size for each round." )
        , ( "Window", "The attempt in flight, or the next one if none is." )
        , ( "Source", "Trainer configuration and the published round state." )
        ]



-- POPULATION AND STRUCTURE


populationPanel : Tip
populationPanel =
    t "population-panel"
        "Population and structure"
        "The state of the evolutionary machinery: how many genomes are alive, how many species they split into, and how large their graphs have grown. These say what the search is doing, not how well it is doing; the gate at the top of the page is the only thing that speaks to quality."
        [ ( "Denominator", "Varies per tile; each states its own." )
        , ( "Window", "Current generation." )
        , ( "Source", "Evolution loop and the genome census." )
        ]



-- COST AND HEALTH


workRates : Tip
workRates =
    t "work-rates"
        "Cost per unit of work"
        "CPU nanoseconds this process spent per simulated display tick, and per link activation in the policy network. Both divide thread-summed CPU time by counts of events, so neither moves when the machine gets busy, when the duty governor rests, or when the worker count changes, and neither is flattered by a policy that learns to win faster and therefore simulates less. These are the figures to optimise against; episodes per second is not."
        [ ( "Denominator", "Display ticks simulated, and link activations evaluated, by this process." )
        , ( "Window", "This process only. The counters start at zero on every resume and are never checkpointed." )
        , ( "Source", "Per-fight work counters over getrusage CPU time summed across all threads." )
        ]


phaseSplit : Tip
phaseSplit =
    t "phase-split"
        "Where the time went"
        "This session's CPU seconds, split across the named phases. Shares are of ACCOUNTED time, so they sum to one and the leftover is reported on its own line rather than folded into a bucket. That leftover is signed and both signs mean something: positive is CPU nobody put a clock around, and negative means worker threads were preempted mid-fight, so its size is a contention signal rather than an error."
        [ ( "Denominator", "Accounted seconds for the shares; session CPU seconds for the unaccounted line." )
        , ( "Window", "This process only, over the span its compute seconds cover." )
        , ( "Source", "Per-fight clocks inside the evaluator, plus the supervisor's own timers." )
        ]


benchmark : Tip
benchmark =
    t "benchmark"
        "Benchmark reference"
        "What this exact binary costs on the fixed benchmark workload, taken as the BEST of several repetitions because unrelated load can only ever make a repetition slower. It is quoted only for recorded runs of this build on this workload definition, so a figure from another binary or another task list can never be compared with it by accident. It does not move while the trainer runs."
        [ ( "Denominator", "Display ticks and link activations of the fixed task list." )
        , ( "Window", "One recorded benchmark run, single threaded, with no duty governor and no nice." )
        , ( "Source", "The append-only bench history beside this run. Absent until this build has been benchmarked." )
        ]
