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
    , fightLimit
    , combatVictories
    , fitnessRule
    , freshness
    , gateCriterion
    , generation
    , auditPanel
    , heatmap
    , ladder
    , ladderPhase
    , machine
    , observedNeeded
    , opponentRevision
    , readiness
    , regression
    , broadMode
    , matchupCoverage
    , meanConnections
    , meanNodes
    , nextExpansion
    , noDamagePenalty
    , originRun
    , overallGate
    , overallPanel
    , overallRound
    , samplerCoverage
    , shipPerformance
    , nodesChart
    , opponentTypes
    , phase
    , populationSize
    , resourcesBudget
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
    , unresolved
    , vitals
    , winRateChart
    , worstCell
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
    , vitals
    , machine
    , unevaluated
    , nodesChart
    , ladderPhase
    , opponentRevision
    , auditPanel scoring
    , observedNeeded scoring
    , readiness
    , regression scoring
    , worstCell
    , unresolved scoring
    , generation
    , episodes
    , episodesPerSecond
    , elapsed
    , championId
    , championRate scoring
    , championLowerBound scoring
    , championGames scoring
    , championStructure
    , target scoring
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
    , resourcesBudget
    , winRateChart scoring
    , structureChart
    , throughputChart
    , topology
    , timeline
    , controls
    , overallGate scoring
    , overallPanel
    , overallRound
    , shipPerformance scoring
    , broadMode scoring
    , samplerCoverage
    , originRun
    , fitnessRule
    , fightLimit
    , gateCriterion
    , noDamagePenalty
    , combatVictories
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


vitals : Tip
vitals =
    t "vitals"
        "Run vitals"
        "Throughput and progress counters for the run as a whole, plus the rule that work is scored by and the deadline each fight is scored at. None of these say anything about how good the champion is; they say how much work has been done, how fast, and what it was ranked on. The gate figures at the top of the page are the ones that speak to quality."
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


championRate : Maybe Api.Scoring -> Tip
championRate scoring =
    t "champion-rate"
        ("Champion fresh audit " ++ rateOf scoring)
        ("Counted "
            ++ successes scoring
            ++ " divided by games on the champion's predeclared audit panel. These are fresh gate episodes on gate seeds, played after the candidate was frozen. They are not training episodes and they are not pooled across the population, so this is the number that actually speaks to whether the champion is any good."
        )
        [ ( "Denominator", "Audit games played by this champion at the current stage." )
        , ( "Window", "The current champion's audit panel only. Reset when the champion changes." )
        , ( "Source", "Audit, on gate seeds separate from the training seeds." )
        ]


championLowerBound : Maybe Api.Scoring -> Tip
championLowerBound scoring =
    t "champion-bound"
        "Wilson lower bound"
        ("The lower end of a Wilson confidence interval on the champion's audit "
            ++ rateOf scoring
            ++ ". Promotion is gated on this bound clearing the target, not on the raw rate, because a raw rate over the target on a handful of games is mostly luck. A small panel produces a low bound even when every game counted."
        )
        [ ( "Denominator", "The same audit games as the rate above." )
        , ( "Window", "Current champion, current stage." )
        , ( "Source", "Audit. Computed by the trainer, displayed here unchanged." )
        ]


championGames : Maybe Api.Scoring -> Tip
championGames scoring =
    t "champion-games"
        "Audit sample size"
        ("Counted "
            ++ successes scoring
            ++ " over games on the champion's audit panel. Panels are predeclared and finite, and audit and confirmation panels do not overlap, so this number rises in fixed steps rather than being extended until the result looks good. Repeated peeking at an arbitrary panel size is exactly how a lucky candidate gets promoted."
        )
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


target : Maybe Api.Scoring -> Tip
target scoring =
    t "target"
        "Gate target"
        ("The "
            ++ rateOf scoring
            ++ " every active ordered matchup must clear before the curriculum expands. The gate is per cell, not pooled: an overall average above the target means nothing if one matchup is still short, because the average can hide a weak cell behind many strong ones."
        )
        [ ( "Denominator", "Applied to each ordered matchup separately." )
        , ( "Window", "Current stage." )
        , ( "Source", "Run configuration, immutable for the run." )
        ]



-- CURRICULUM


ladderPhase : Tip
ladderPhase =
    t "ladder-phase"
        "Ladder phase"
        "How the curriculum is currently growing. Climbing walks the frozen expansion order one ship at a time, alternating the opponent side and our side. Mixed plays an assembled roster rather than extending it. The phase decides what a promotion means, so a rate measured in one phase is not interchangeable with one measured in the other."
        [ ( "Denominator", "None; a mode." )
        , ( "Window", "Current." )
        , ( "Source", "Curriculum state, checkpointed." )
        ]


opponentRevision : Tip
opponentRevision =
    t "opponent-revision"
        "Frozen opponent revision"
        "Which generation of frozen opponent this evidence was gathered against, with its fingerprint. A challenger never faces changing opponent weights inside a generation or an audit, and evidence is versioned by this fingerprint. When the revision moves, results collected against the previous one no longer describe the current gate and are not pooled with it."
        [ ( "Denominator", "None; a revision counter and a fingerprint." )
        , ( "Window", "Current. Revision 0 with no fingerprint means no frozen model opponent is in play yet, only the original game's cyborg." )
        , ( "Source", "Curriculum state. All audit evidence on this page belongs to this revision." )
        ]


auditPanel : Maybe Api.Scoring -> Tip
auditPanel scoring =
    t "audit-panel"
        "Audit panel"
        ("The predeclared, fixed-size panel a frozen candidate is judged on, and the number of games it can fail to count and still reach the target. Those are survivable: on a panel of 100 needing 88 counted "
            ++ successes scoring
            ++ ", 12 uncounted games still leave exactly 88 reachable, and it is the next one after the cap that makes the target arithmetically unreachable and ends the attempt. The panel size is fixed before the audit starts and does not overlap the confirmation panel, so evidence cannot be extended until it happens to look good."
        )
        [ ( "Denominator", "Games in the predeclared panel." )
        , ( "Window", "Per audit attempt, for the current frozen candidate." )
        , ( "Source", "Run configuration, fixed for the run. Budget is the total audit spend allowed." )
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


regression : Maybe Api.Scoring -> Tip
regression scoring =
    t "regression"
        "Regression rehearsal"
        ("Periodic re-checking of cells that already passed the gate, so that progress at a later stage cannot quietly break an earlier one. A sweep is judged on the same criterion as the gate itself. A sweep that finds failed cells means mastery was lost and those cells are back in contention, which is exactly the kind of silent backsliding an aggregate "
            ++ rateOf scoring
            ++ " would hide."
        )
        [ ( "Denominator", "Previously mastered cells re-checked in the last sweep." )
        , ( "Window", "The most recent sweep, not the whole run." )
        , ( "Source", "Audit-style rehearsal play, separate from the current stage's gate evidence." )
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


worstCell : Tip
worstCell =
    t "worst-cell"
        "Weakest cell's bound"
        "The lowest Wilson lower bound across the champion's active ordered matchups. This is the number the per-cell gate actually turns on, because every cell must clear the target individually. It is always at or below the overall bound, and the gap between the two is exactly the weakness an aggregate figure would hide."
        [ ( "Denominator", "The audit games of whichever single cell is weakest." )
        , ( "Window", "Current stage, current champion." )
        , ( "Source", "Audit. A minimum across cells, never an average of them." )
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
            ++ " on that generation's sampled training panel, recorded for the champion's member alone rather than averaged over the population. The markers are the recurring readiness probe: the trainer publishes them as the run's validation figure, but the probe only decides when an audit is worth spending, so a marker is never a passed gate. Both ask the same question the gate asks, on the run's own criterion. The line breaks at every stage change because a rate measured against a small roster is not comparable with one measured against a larger one."
        )
        [ ( "Denominator", "Training: episodes on that generation's sampled panel for the champion's own member. Readiness: games in the probe's own batch." )
        , ( "Window", "Per generation, whole run, split at stage boundaries." )
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


throughputChart : Tip
throughputChart =
    t "chart-throughput"
        "Cumulative episodes"
        "The running total of episodes the run has resolved, plotted against generation. This is a cumulative counter, so the line only ever rises and its height is total work done, not work done in that generation. The per-generation cost is the step between two adjacent points, and a visibly steeper step usually means an audit ran, since gate panels are spent on top of training play."
        [ ( "Denominator", "Episodes resolved since the run started, as a running total." )
        , ( "Window", "Cumulative over the whole run, sampled once per generation." )
        , ( "Source", "Training and gate episodes combined." )
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



-- BROAD MODE
--
-- A broad run is gated on one aggregate figure over a balanced held-out
-- distribution, not cell by cell. These tips exist so that difference is
-- stated wherever a broad-mode number appears, rather than left for the
-- reader to infer from a heading.


broadMode : Maybe Api.Scoring -> Tip
broadMode scoring =
    t "broad-mode"
        "Broad any-versus-any mode"
        ("Every ship is active against every ship at once. There is no staged unlock and no per-matchup gate: the run is judged on one overall "
            ++ rateOf scoring
            ++ " against Awesome cyborgs over a balanced distribution. The per-cell grid stays on the page as a diagnostic that shows where the champion is weak, which is exactly what an aggregate target hides."
        )
        [ ( "Denominator", "None; a mode, not a measurement." )
        , ( "Window", "From the operator transition onward." )
        , ( "Source", "The trainer's declared curriculum ladder and evaluation scope." )
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


originRun : Tip
originRun =
    t "origin-run"
        "Carried-over provenance"
        "This run did not start from scratch. Genomes, weights, mutation rates, species, the innovation counter and the RNG states were copied from an earlier run at a recorded generation. What was deliberately not copied is evidence: the in-flight panel was abandoned at the transition and every fitness, probe and gate result was cleared, because results measured under the old distribution say nothing about this one."
        [ ( "Denominator", "None; an identifier and a generation number." )
        , ( "Window", "Fixed at the transition." )
        , ( "Source", "The transition event recorded in the checkpoint." )
        ]
