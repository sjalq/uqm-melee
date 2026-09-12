//! The training state machine.
//!
//! Work is done in small units so that a pause, a stop, a checkpoint or an API
//! request never has to wait for a whole generation. Every unit is a pure
//! function of the checkpointed state, so stopping and resuming reproduces the
//! same trajectory as running straight through, and a process killed mid-batch
//! simply replays that batch deterministically.
//!
//! Three rules run through the whole file:
//!
//!   * Fitness numbers are comparable only inside one panel. Champion
//!     replacement rescores the incumbent on the challenger's own panel.
//!   * Gate evidence belongs to one candidate fingerprint, one stage and one
//!     opponent revision. Any change throws it away rather than pooling it.
//!   * The frozen self-play opponent changes only at a recorded champion
//!     promotion, never inside a generation or an audit.

use crate::audit::{AuditConfig, Gate, Progress, Round, Tally};
use crate::broad::{self, BroadConfig, Evaluation, Overall, Source};
use crate::curriculum::{self, Cell, Opponent};
use crate::episode::{self, Rival, ScoringConfig, Task};
use crate::genome::Genome;
use crate::graph::Network;
use crate::neat::{MutationRates, NeatConfig, Population};
use crate::pool::Pool;
use crate::rng::{episode_seed, Stream, StreamTag};
use crate::sampler::{self, Panel, SamplerConfig, SamplerStats};
use melee_sim::input::CyborgRating;
use serde_json::{json, Value};
use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;

pub const ENGINE_VERSION: &str = "melee-mario/1";
const MAX_HISTORY: usize = 4000;
const MAX_EVENTS: usize = 200;
/// Fights a single-worker unit of training or readiness work plays. The legacy
/// unit, kept exactly so the default configuration is the evaluator it
/// replaced rather than a reshaped one.
const SERIAL_PANEL: usize = 8;
/// How many fights a unit of work queues per worker. More than one, because
/// fights end at wildly different ticks and a worker that draws a short one
/// should have another waiting rather than idling until the batch drains.
const FIGHTS_PER_WORKER: usize = 4;
/// Ceiling on candidates per unit of work, so a large pool or a tiny panel
/// cannot stretch one unit far enough to make a pause, a stop or a status
/// publish wait on it.
const MAX_CANDIDATES: usize = 32;

#[derive(Clone, Debug)]
pub struct Config {
    pub run_id: String,
    pub salt: u64,
    pub ticks: i64,
    pub rating: CyborgRating,
    pub neat: NeatConfig,
    pub sampler: SamplerConfig,
    pub audit: AuditConfig,
    /// What ranks the population, what opens a gate and what a fight that
    /// did the enemy no net harm is worth. A per-run choice, recorded in the
    /// run's configuration so that a checkpoint always says what its fitness
    /// numbers and its success counts mean.
    pub scoring: ScoringConfig,
    /// Settings for [`Ladder::Broad`]. Present in every configuration so a
    /// staged run can be forked into a broad one without a schema change, and
    /// inert while the ladder is anything else.
    pub broad: BroadConfig,
    /// Fraction of wall time the evaluator is allowed to compute.
    pub duty: f64,
    pub readiness_games: usize,
    pub readiness_threshold: f64,
    pub readiness_period: u32,
    /// Episode ceiling for one MIXED-PHASE regression sweep. Much smaller than
    /// an audit budget: a regression sweep is a smoke alarm, not a gate.
    pub regression_budget: u32,
}

impl Config {
    pub fn to_json(&self) -> Value {
        json!({"version": ENGINE_VERSION, "run_id": self.run_id, "salt": self.salt.to_string(),
               "ticks": self.ticks, "rating": rating_name(self.rating),
               "neat": self.neat.to_json(), "sampler": self.sampler.to_json(),
               "audit": self.audit.to_json(), "broad": self.broad.to_json(),
               "scoring": self.scoring.to_json(), "duty": self.duty,
               "readiness_games": self.readiness_games,
               "readiness_threshold": self.readiness_threshold,
               "readiness_period": self.readiness_period,
               "regression_budget": self.regression_budget})
    }

    /// Rejects a configuration document from a different engine version or with
    /// values the trainer cannot honour, rather than clamping into something
    /// the operator did not ask for.
    pub fn from_json(value: &Value) -> Option<Config> {
        if value.get("version")?.as_str()? != ENGINE_VERSION {
            return None;
        }
        let ticks = value.get("ticks")?.as_i64().filter(|t| *t > 0)?;
        let duty = value.get("duty")?.as_f64().filter(|d| *d > 0.0 && *d <= 1.0)?;
        let threshold = value
            .get("readiness_threshold")?
            .as_f64()
            .filter(|t| (0.0..=1.0).contains(t))?;
        Some(Config {
            run_id: value.get("run_id")?.as_str()?.to_string(),
            salt: value.get("salt")?.as_str()?.parse().ok()?,
            ticks,
            rating: parse_rating(value.get("rating")?.as_str()?)?,
            neat: NeatConfig::from_json(value.get("neat")?)?,
            sampler: SamplerConfig::from_json(value.get("sampler")?)?,
            audit: AuditConfig::from_json(value.get("audit")?)?,
            // Checkpoints written before broad mode existed have no settings
            // for it; the defaults describe a run that has never used it.
            broad: match value.get("broad") {
                None => BroadConfig::default(),
                Some(other) => BroadConfig::from_json(other)?,
            },
            // A configuration written before the selector existed names no
            // scorer, gate criterion or penalty, and every such run was trained
            // under the combat scorer and gated on actual wins with no penalty.
            // A block that IS present but names something unknown, or whose
            // penalty this build cannot honour, is rejected rather than
            // silently read as the default.
            scoring: ScoringConfig::from_json(value.get("scoring"))?,
            duty,
            readiness_games: value
                .get("readiness_games")?
                .as_u64()
                .filter(|g| *g > 0)? as usize,
            readiness_threshold: threshold,
            readiness_period: value.get("readiness_period")?.as_u64()?.max(1) as u32,
            regression_budget: match value.get("regression_budget") {
                None => 4_000,
                Some(other) => other.as_u64().filter(|b| *b > 0)? as u32,
            },
        })
    }
}

/// Hash of the running executable. Read once; a rebuild of any crate in the
/// workspace changes the bytes and therefore this value.
pub fn build_fingerprint() -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in ENGINE_VERSION.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    if let Ok(path) = std::env::current_exe() {
        if let Ok(bytes) = std::fs::read(path) {
            for chunk in bytes.chunks(8) {
                let mut word = 0u64;
                for (at, byte) in chunk.iter().enumerate() {
                    word |= (*byte as u64) << (at * 8);
                }
                hash ^= word;
                hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
            }
        }
    }
    format!("b{hash:016x}")
}

pub fn rating_name(rating: CyborgRating) -> &'static str {
    match rating {
        CyborgRating::StandardCyborg => "standard",
        CyborgRating::GoodCyborg => "good",
        CyborgRating::AwesomeCyborg => "awesome",
    }
}

pub fn parse_rating(raw: &str) -> Option<CyborgRating> {
    match raw {
        "standard" => Some(CyborgRating::StandardCyborg),
        "good" => Some(CyborgRating::GoodCyborg),
        "awesome" => Some(CyborgRating::AwesomeCyborg),
        _ => None,
    }
}

/// Where the curriculum is. The ladder is graded; the mixed phase is not.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Ladder {
    /// Climbing the cyborg stages. A stage promotion needs a full gate.
    Climbing,
    /// Every cyborg matchup has been gated. Training now mixes the Awesome
    /// cyborg distribution with a frozen champion snapshot and runs
    /// indefinitely; beating a copy of yourself is not a mastery criterion.
    /// The cyborg board keeps being probed and swept so that a policy drifting
    /// towards beating only its own reflection is caught.
    Mixed,
    /// Every ordered cyborg matchup is ACTIVE at once, and the graded question
    /// is the aggregate SUCCESS rate, under whatever criterion the run is
    /// gated on, over a balanced any-versus-any distribution rather than 625
    /// separate per-cell bounds. The full roster here is
    /// unlocked by an operator transition, not earned cell by cell, so nothing
    /// in this phase may be read as per-matchup mastery.
    Broad,
}

impl Ladder {
    pub fn as_str(self) -> &'static str {
        match self {
            Ladder::Climbing => "climbing",
            Ladder::Mixed => "mixed",
            Ladder::Broad => "broad",
        }
    }

    pub fn parse(raw: &str) -> Option<Ladder> {
        match raw {
            "climbing" => Some(Ladder::Climbing),
            "mixed" => Some(Ladder::Mixed),
            "broad" => Some(Ladder::Broad),
            _ => None,
        }
    }

    /// What the run is graded on. Broad mode, and anything a broad run later
    /// becomes, is graded on the balanced aggregate; the staged ladder is
    /// graded cell by cell.
    pub fn evaluation_scope(self, from_broad: bool) -> &'static str {
        if self == Ladder::Broad || from_broad {
            "overall-balanced"
        } else {
            "per-cell-ladder"
        }
    }
}

/// Where a run came from when it was forked into a different scope.
///
/// Kept for the life of the run, including after a broad run goes on to the
/// mixed phase: the provenance of a policy's roster is not something a later
/// phase gets to forget.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Origin {
    pub run_id: String,
    pub generation: u32,
    /// Build fingerprint of the evaluator that produced the SOURCE checkpoint.
    /// Recorded rather than enforced, because the fork is the one place a
    /// fingerprint change is explicitly accepted.
    pub fingerprint: String,
    pub reason: String,
}

impl Origin {
    pub fn to_json(&self) -> Value {
        json!({"run_id": self.run_id, "generation": self.generation,
               "fingerprint": self.fingerprint, "reason": self.reason})
    }

    pub fn from_json(value: &Value) -> Option<Origin> {
        Some(Origin {
            run_id: value.get("run_id")?.as_str()?.to_string(),
            generation: value.get("generation")?.as_u64()? as u32,
            fingerprint: value.get("fingerprint")?.as_str()?.to_string(),
            reason: value.get("reason")?.as_str()?.to_string(),
        })
    }
}

/// The one piece of work the trainer is currently doing.
#[derive(Clone, Debug)]
pub enum Mode {
    Training,
    /// A cheap fixed probe on its own seed stream, used only to decide whether
    /// an expensive audit is worth opening. It is not evidence for promotion.
    Probing {
        attempt: u64,
        champion: String,
        tasks: Vec<Task>,
        cursor: usize,
        wins: u32,
    },
    Auditing {
        gate: Gate,
    },
    /// One round of the broad aggregate gate on a balanced held-out panel.
    /// Distinct from [`Mode::Auditing`] because it measures a different thing:
    /// one number over a distribution, not 625 numbers over 625 cells.
    Overall {
        gate: Overall,
    },
}

#[derive(Clone, Debug)]
pub struct HistoryRow {
    pub generation: u32,
    pub stage: usize,
    pub training_win_rate: Option<f64>,
    pub validation_win_rate: Option<f64>,
    pub species: usize,
    pub nodes: usize,
    pub episodes: u64,
}

#[derive(Clone, Debug)]
pub struct Event {
    pub at: String,
    pub message: String,
}

pub struct Trainer {
    pub config: Config,
    /// Fingerprint of the executable that produced this state. A rebuild
    /// changes it, and a changed evaluator may not silently continue someone
    /// else's trajectory: the operator has to say so explicitly.
    pub evaluator: String,
    pub evolution: Stream,
    pub sampling: Stream,
    pub population: Population,
    pub stage: usize,
    pub ladder: Ladder,
    /// Bumped only when the frozen self-play opponent is replaced, at a
    /// recorded champion promotion. Audit evidence is versioned by it.
    pub opponent_revision: u32,
    pub frozen_opponent: Option<Genome>,
    pub champion: Option<Genome>,
    /// The mutation rates the champion had drifted to. Carried with it so that
    /// re-entering it as an elite does not reset its search intensity.
    pub champion_rates: MutationRates,
    /// Confirmed audit evidence for the current champion at the current stage.
    pub evidence: BTreeMap<Cell, Tally>,
    /// Cells that failed the most recent gate attempt; audited first next time.
    pub priority: Vec<Cell>,
    pub stats: SamplerStats,
    pub panel: Option<Panel>,
    pub mode: Mode,
    /// Set when this run was forked out of another one into a different scope.
    /// Never cleared afterwards.
    pub origin: Option<Origin>,
    /// How far the broad coverage rotation has walked. Monotonic, and the only
    /// state that schedule needs to resume exactly.
    pub coverage_cursor: u64,
    /// The most recent balanced readiness probe. Diagnostic only.
    pub broad_ready: Option<Evaluation>,
    /// The most recent broad audit round for the CURRENT champion.
    pub broad_audit: Option<Evaluation>,
    /// The most recent broad confirmation round for the CURRENT champion.
    pub broad_confirm: Option<Evaluation>,
    /// The confirmation round that actually cleared the aggregate target,
    /// carrying the fingerprint of the champion that cleared it. Unlike the
    /// three above it survives a later promotion, because it is a fact about
    /// one named policy rather than evidence about the current one; the status
    /// document only reports the gate as passed while that fingerprint is
    /// still the champion.
    pub broad_gate: Option<Evaluation>,
    /// Which of the three drives the per-hull diagnostics table, so a cheap
    /// readiness probe is never displayed as gate evidence.
    pub broad_shown: Option<Source>,
    pub episodes: u64,
    /// Episodes that ended without a victory: the tick ceiling, or the
    /// evaluator's Selecting phase (see `episode`). Counted and reported
    /// rather than quietly folded into losses, because the honest reading is
    /// "no result", not "a loss".
    pub unresolved: u64,
    /// Actual won-and-resolved fights, counted whatever the configured gate
    /// criterion is. Under `crew-lead` every other success count in the run
    /// means something else, so this is the only number that may be called a
    /// combat win. See [`Trainer::combat_counted_since`] for the window it
    /// covers: the pair is meaningless apart.
    pub combat_wins: u64,
    /// The episode total at which `combat_wins` began counting. Zero for a
    /// fresh run, so its count is exact and covers all time. A checkpoint
    /// written before this counter existed carries no history for it, and a
    /// resume of one starts the window at whatever episode total it arrived
    /// with rather than pretending the missing history was zero wins; the
    /// status document then reports no all-time figure at all.
    pub combat_counted_since: u64,
    /// Wall-clock seconds spent inside the run loop, work and governor rest
    /// together, accumulated across every resume.
    pub elapsed: f64,
    /// Of those, the seconds actually spent simulating. The ratio is the
    /// MEASURED duty cycle, which is what the dashboard shows next to the cap.
    pub compute: f64,
    pub audit_attempt: u64,
    pub last_validation: Option<f64>,
    /// The champion's SUCCESS rate on the panel currently being evaluated,
    /// under the run's configured gate criterion rather than always its wins.
    /// Derived from the live panel, so it is rebuilt rather than restored.
    pub last_training_wins: Option<f64>,
    /// Result of the most recent mixed-phase regression sweep, for honest
    /// reporting. Both are zero before the first sweep.
    pub regression_swept: usize,
    pub regression_failed: usize,
    /// Scheduling penalty this PROCESS is running under. A property of the
    /// current invocation rather than of the run, so it is reported from the
    /// live value and never restored from a checkpoint.
    pub nice: i32,
    /// The evaluation pool this PROCESS is running, exactly like `nice` a
    /// property of the invocation rather than of the run: never checkpointed,
    /// never part of the evaluator fingerprint, and never visible in the
    /// trajectory. Changing it changes only how fast the same fights are
    /// played. See [`Trainer::use_workers`].
    pub(crate) pool: Pool,
    pub history: VecDeque<HistoryRow>,
    pub events: VecDeque<Event>,
    pub saved_at: Option<String>,
    /// Compiled graphs are cached here for the length of a panel so the
    /// strongly-connected-component pass is paid once per genome, not once per
    /// fight.
    pub(crate) cache: Option<(String, Arc<Network>)>,
    pub(crate) opponent_cache: Option<(String, Arc<Network>)>,
}

/// One fight, described entirely by owned values.
///
/// Nothing here borrows the trainer, holds a random stream or shares a game
/// arena, so [`Fight::run`] is a pure function that a worker thread may
/// evaluate in any order without the result depending on which worker took it
/// or when. Building one is the boundary where trainer state stops.
struct Fight {
    task: Task,
    ours: Arc<Network>,
    /// The frozen self-play snapshot, resolved before the fight was queued.
    theirs: Option<Arc<Network>>,
    rating: CyborgRating,
}

impl Fight {
    fn run(&self) -> episode::Outcome {
        match &self.theirs {
            Some(theirs) => episode::run(&self.task, &self.ours, Rival::Model(theirs)),
            None => episode::run(&self.task, &self.ours, Rival::Cyborg(self.rating)),
        }
    }
}

/// What one unit of work accomplished, so the caller can pace itself.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Unit {
    pub episodes: u64,
    /// A generation, probe or gate round finished, so this is a safe point to
    /// write a checkpoint.
    pub boundary: bool,
}

impl Trainer {
    pub fn fresh(config: Config) -> Trainer {
        let config_rates = config.neat.seed_rates;
        let mut evolution = Stream::seeded(config.salt ^ 0xe0_1u64);
        let sampling = Stream::seeded(config.salt ^ 0x5a_2u64);
        let population = Population::seed(config.neat, &mut evolution);
        let mut trainer = Trainer {
            config,
            evaluator: build_fingerprint(),
            evolution,
            sampling,
            population,
            stage: 0,
            ladder: Ladder::Climbing,
            opponent_revision: 0,
            frozen_opponent: None,
            champion: None,
            champion_rates: config_rates,
            evidence: BTreeMap::new(),
            priority: Vec::new(),
            stats: SamplerStats::default(),
            panel: None,
            mode: Mode::Training,
            origin: None,
            coverage_cursor: 0,
            broad_ready: None,
            broad_audit: None,
            broad_confirm: None,
            broad_gate: None,
            broad_shown: None,
            episodes: 0,
            unresolved: 0,
            combat_wins: 0,
            combat_counted_since: 0,
            elapsed: 0.0,
            compute: 0.0,
            audit_attempt: 0,
            last_validation: None,
            last_training_wins: None,
            regression_swept: 0,
            regression_failed: 0,
            nice: 0,
            pool: Pool::new(1),
            history: VecDeque::new(),
            events: VecDeque::new(),
            saved_at: None,
            cache: None,
            opponent_cache: None,
        };
        trainer.note(format!(
            "run {} seeded: population {}, stage 0, {} vs {}",
            trainer.config.run_id,
            trainer.config.neat.population,
            curriculum::ours()[0].name(),
            curriculum::theirs()[0].name()
        ));
        trainer
    }

    pub fn note(&mut self, message: String) {
        self.events.push_back(Event {
            at: now(),
            message,
        });
        while self.events.len() > MAX_EVENTS {
            self.events.pop_front();
        }
    }

    /// Cyborg cells of the current stage.
    pub fn cyborg_cells(&self) -> Vec<Cell> {
        curriculum::cells(self.stage)
    }

    /// Frozen-model cells, empty until the ladder has been fully gated.
    pub fn model_cells(&self) -> Vec<Cell> {
        if self.ladder == Ladder::Mixed && self.frozen_opponent.is_some() {
            curriculum::model_cells()
        } else {
            Vec::new()
        }
    }

    fn compiled(&mut self, genome: &Genome) -> Arc<Network> {
        let fingerprint = genome.fingerprint();
        if let Some((cached, network)) = &self.cache {
            if *cached == fingerprint {
                return network.clone();
            }
        }
        let network = Arc::new(Network::compile(genome));
        self.cache = Some((fingerprint, network.clone()));
        network
    }

    fn compiled_opponent(&mut self) -> Option<Arc<Network>> {
        let genome = self.frozen_opponent.clone()?;
        let fingerprint = genome.fingerprint();
        if let Some((cached, network)) = &self.opponent_cache {
            if *cached == fingerprint {
                return Some(network.clone());
            }
        }
        let network = Arc::new(Network::compile(&genome));
        self.opponent_cache = Some((fingerprint, network.clone()));
        Some(network)
    }

    /// Replaces the evaluation pool for this process. A pure resource knob:
    /// the same run at one worker and at nine plays the same fights in the
    /// same order and reaches the same state, so this is safe to change on a
    /// resume without touching the evaluator fingerprint.
    pub fn use_workers(&mut self, workers: usize) {
        if workers != self.pool.workers() {
            self.pool = Pool::new(workers);
        }
    }

    pub fn workers(&self) -> usize {
        self.pool.workers()
    }

    /// Everything one fight needs, owned, so it can be handed to a worker
    /// without borrowing any trainer state.
    fn fight(&mut self, task: Task, ours: &Arc<Network>) -> Fight {
        Fight {
            task,
            ours: ours.clone(),
            // Resolved once, here on the main thread, so every fight in a
            // batch faces the same opponent snapshot whatever order the
            // workers take them in. No snapshot yet falls back to the graded
            // opponent rather than inventing one the evidence would not
            // describe.
            theirs: match task.cell.foe {
                Opponent::Cyborg => None,
                Opponent::Model => self.compiled_opponent(),
            },
            rating: self.config.rating,
        }
    }

    /// Folds one finished fight into the run's counters.
    ///
    /// The single choke point every episode passes through, whichever work
    /// path asked for it: training, an extra species or incumbent evaluation,
    /// a readiness probe, an audit, a confirmation, a regression sweep or a
    /// broad round. Counting here, on the main thread and in the order the
    /// fights were queued, is what makes each episode count exactly once and
    /// count in the same place at every worker setting. A fight computed
    /// speculatively and then discarded never reaches this function and is
    /// therefore never counted.
    fn absorb(&mut self, outcome: episode::Outcome) -> episode::Outcome {
        self.episodes += 1;
        self.unresolved += !outcome.resolved as u64;
        self.combat_wins += outcome.won as u64;
        outcome
    }

    fn play(&mut self, task: &Task, network: &Arc<Network>) -> episode::Outcome {
        let fight = self.fight(*task, network);
        self.absorb(fight.run())
    }

    /// How many fights a unit of work should queue to keep the pool fed, and
    /// exactly [`SERIAL_PANEL`] when there is a single worker.
    fn fight_budget(&self) -> usize {
        match self.pool.workers() {
            1 => SERIAL_PANEL,
            workers => workers * FIGHTS_PER_WORKER,
        }
    }

    /// How many candidates one unit of training work scores.
    ///
    /// Exactly one on a single worker, whatever the panel size, because that
    /// is the legacy unit and the default configuration has to remain the
    /// evaluator it replaced rather than a rescheduled one. Only a real pool
    /// batches, and only far enough to keep its workers fed.
    fn candidates_per_unit(&self, panel: usize) -> usize {
        if self.pool.workers() == 1 {
            return 1;
        }
        self.fight_budget()
            .div_ceil(panel.max(1))
            .clamp(1, MAX_CANDIDATES)
    }

    /// One bounded unit of work.
    pub fn step(&mut self) -> Unit {
        match std::mem::replace(&mut self.mode, Mode::Training) {
            Mode::Training => self.step_training(),
            Mode::Probing {
                attempt,
                champion,
                tasks,
                cursor,
                wins,
            } => self.step_probe(attempt, champion, tasks, cursor, wins),
            Mode::Auditing { gate } => self.step_audit(gate),
            Mode::Overall { gate } => self.step_overall(gate),
        }
    }

    fn step_training(&mut self) -> Unit {
        self.mode = Mode::Training;
        if self.panel.is_none() {
            self.open_panel();
        }
        let ticks = self.config.ticks;
        // Only the tasks are needed here, and the panel is small; cloning the
        // whole panel struct per member would copy the task list once per
        // genome for no reason.
        let (tasks, cursor) = {
            let panel = self.panel.as_ref().expect("panel opened above");
            (panel.tasks.clone(), panel.cursor)
        };
        let members = self.population.size();
        if cursor >= members {
            return self.close_panel();
        }
        // One member's fitness is a pure function of its genome and the panel,
        // so several members can be in flight at once. They are queued in
        // population order and folded back in population order, which is what
        // keeps the trajectory identical at every worker setting: the pool
        // changes only when the arithmetic happens, never what it is or what
        // order it happens in.
        let candidates = self
            .candidates_per_unit(tasks.len())
            .min(members - cursor);
        // Members being scored are looked up by index. Materialising every
        // genome in the population on every unit of work was quadratic in the
        // population size, which at three hundred genomes with a hundred links
        // each was the single largest allocation cost in the loop.
        let batch: Vec<Genome> = self
            .population
            .members()
            .skip(cursor)
            .take(candidates)
            .map(|member| member.genome.clone())
            .collect();
        if batch.is_empty() {
            return self.close_panel();
        }
        let champion = self.champion.as_ref().map(Genome::fingerprint);
        let gate = self.config.scoring.gate;
        // The strongly-connected-component pass is paid once per genome rather
        // than once per fight, exactly as the single-candidate path did.
        let networks: Vec<Arc<Network>> = batch
            .iter()
            .map(|genome| Arc::new(Network::compile(genome)))
            .collect();
        // The self-play snapshot is resolved once for the whole batch rather
        // than once per fight, so every candidate in it faces the same frozen
        // opponent and the genome is fingerprinted once instead of forty times.
        let theirs = self.compiled_opponent();
        let rating = self.config.rating;
        let queued: Vec<Fight> = networks
            .iter()
            .flat_map(|network| tasks.iter().map(move |task| (*task, network.clone())))
            .map(|(task, ours)| Fight {
                task,
                ours,
                theirs: match task.cell.foe {
                    Opponent::Cyborg => None,
                    Opponent::Model => theirs.clone(),
                },
                rating,
            })
            .collect();
        let played = queued.len();
        let outcomes = self.pool.map(queued, |fight| fight.run());
        for (at, genome) in batch.iter().enumerate() {
            // Sampler evidence follows the champion, because the sampler's job
            // is to find where the policy we actually gate on is still weak.
            // Before a champion exists the first member stands in for it.
            let seat = cursor + at;
            let record = champion
                .as_ref()
                .map_or(seat == 0, |c| *c == genome.fingerprint());
            let mut total = 0.0;
            let mut wins = 0u32;
            for (task, outcome) in tasks.iter().zip(&outcomes[at * tasks.len()..]) {
                let outcome = self.absorb(*outcome);
                // The run's configured scorer, so every number that is compared
                // with another, this member, the rescored incumbent and the
                // species references drawn from them, comes from one definition.
                total += outcome.score(self.config.scoring, ticks);
                // The run's configured gate criterion, for the same reason: the
                // sampler must chase weakness in the thing the run is actually
                // graded on. Under `crew-lead` these are LEAD successes, not
                // combat wins; `self.combat_wins` keeps the factual count.
                wins += outcome.succeeded(gate) as u32;
                if record {
                    self.stats
                        .record(task.cell, outcome.succeeded(gate), self.config.sampler.decay);
                }
            }
            let fitness = total / tasks.len().max(1) as f64;
            if let Some(member) = self.population.members_mut().nth(seat) {
                member.fitness = Some(fitness);
            }
            if record {
                self.last_training_wins = Some(wins as f64 / tasks.len().max(1) as f64);
            }
        }
        if let Some(live) = self.panel.as_mut() {
            live.cursor += batch.len();
        }
        Unit {
            episodes: played as u64,
            boundary: false,
        }
    }

    fn open_panel(&mut self) {
        if let Some(champion) = self.champion.clone() {
            self.population.ensure_elite(&champion, self.champion_rates);
        }
        self.population.open_panel();
        let cyborg = self.cyborg_cells();
        let model = self.model_cells();
        let generation = self.population.generation;
        self.stats.admit(&cyborg, generation);
        self.stats.admit(&model, generation);
        // Broad mode draws its own panel: a balanced coverage rotation plus a
        // bounded adaptive remainder over the whole board, rather than the
        // ladder's weakness-and-novelty mix over one stage's cells.
        let panel = if self.ladder == Ladder::Broad {
            let tasks = broad::draw(
                &self.config.broad,
                &mut self.stats,
                &mut self.sampling,
                self.config.salt,
                self.config.ticks,
                &mut self.coverage_cursor,
            );
            Panel::of(tasks)
        } else {
            sampler::draw(
                &self.config.sampler,
                &mut self.stats,
                &mut self.sampling,
                self.config.salt,
                generation,
                self.config.ticks,
                &cyborg,
                &model,
                &self.priority,
            )
        };
        self.panel = Some(panel);
        self.last_training_wins = None;
    }

    fn close_panel(&mut self) -> Unit {
        let generation = self.population.generation;
        let challenger = self
            .population
            .best()
            .map(|m| (m.genome.clone(), m.score()));
        // Paired comparison: the incumbent was rescored on this same panel.
        let incumbent = self.champion.as_ref().and_then(|genome| {
            let fingerprint = genome.fingerprint();
            self.population
                .members()
                .find(|m| m.genome.fingerprint() == fingerprint)
                .and_then(|m| m.fitness)
        });
        let challenger_rates = self
            .population
            .best()
            .map(|m| m.rates)
            .unwrap_or(self.config.neat.seed_rates);
        if let Some((genome, score)) = challenger {
            let better = match (self.champion.as_ref(), incumbent) {
                (None, _) => true,
                (Some(_), None) => false,
                (Some(_), Some(previous)) => score > previous,
            };
            if better {
                self.promote(genome, challenger_rates);
            }
        }
        self.history.push_back(HistoryRow {
            generation,
            stage: self.stage,
            training_win_rate: self.last_training_wins,
            validation_win_rate: self.last_validation.take(),
            species: self.population.species.len(),
            nodes: self
                .champion
                .as_ref()
                .map_or(0, |g| g.nodes.len()),
            episodes: self.episodes,
        });
        while self.history.len() > MAX_HISTORY {
            self.history.pop_front();
        }
        self.population.advance(&mut self.evolution);
        self.panel = None;
        if self.should_probe() {
            self.begin_probe();
        }
        Unit {
            episodes: 0,
            boundary: true,
        }
    }

    /// Records a new champion. This is the ONLY place the frozen self-play
    /// opponent may change, and it always discards the previous candidate's
    /// gate evidence rather than pooling it.
    fn promote(&mut self, genome: Genome, rates: MutationRates) {
        let fingerprint = genome.fingerprint();
        self.champion_rates = rates;
        let nodes = genome.nodes.len();
        let links = genome.enabled_count();
        self.champion = Some(genome.clone());
        self.evidence.clear();
        self.priority.clear();
        // Every measurement in flight described the policy being replaced.
        // `broad_gate` is deliberately NOT cleared: it names the champion that
        // cleared the aggregate target, and the status document reports the
        // gate as passed only while that name is still the champion.
        self.broad_ready = None;
        self.broad_audit = None;
        self.broad_confirm = None;
        self.broad_shown = None;
        if matches!(
            self.mode,
            Mode::Auditing { .. } | Mode::Probing { .. } | Mode::Overall { .. }
        ) {
            self.mode = Mode::Training;
        }
        if self.ladder == Ladder::Mixed {
            self.frozen_opponent = Some(genome);
            self.opponent_revision += 1;
            self.note(format!(
                "champion {fingerprint} promoted; frozen self-play opponent is now revision {}",
                self.opponent_revision
            ));
        } else {
            self.note(format!(
                "champion {fingerprint} promoted ({nodes} nodes, {links} links); gate evidence reset"
            ));
        }
    }

    /// What this run COUNTS, in words, for the event log.
    ///
    /// Every rate the trainer notes is a rate of these, so a log line that
    /// names them cannot later be read as a win rate by someone who did not
    /// check the configuration. Under `crew-lead` these are not victories and
    /// saying "wins" would claim kills that did not happen.
    fn successes(&self) -> &'static str {
        match self.config.scoring.gate.successes_are_combat_wins() {
            true => "won fights",
            false => "crew leads",
        }
    }

    /// A probe runs in BOTH phases. While climbing it decides whether an
    /// expensive gate is worth opening; in the mixed phase it is a regression
    /// alarm on the original Awesome cyborgs, which the frozen self-play
    /// opponent can never test.
    fn should_probe(&self) -> bool {
        self.champion.is_some()
            && self.population.generation % self.config.readiness_period == 0
    }

    /// Opens a readiness probe on the current champion. Public so a scope
    /// transition can take a baseline reading of the policy it inherited
    /// before the first generation of the new distribution is trained.
    pub fn begin_probe(&mut self) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            return;
        };
        let attempt = self.audit_attempt;
        let tasks = if self.ladder == Ladder::Broad {
            // Broad probes the same balanced any-versus-any distribution the
            // gate is graded on, so the cheap reading and the expensive one
            // are answers to the same question.
            self.broad_ready = Some(Evaluation::open(Source::Ready, champion.clone()));
            self.broad_shown = Some(Source::Ready);
            broad::readiness_panel(
                self.config.salt,
                attempt,
                self.config.readiness_games,
                self.config.ticks,
            )
        } else {
            let cells = self.cyborg_cells();
            sampler::readiness_probe(
                self.config.salt,
                attempt,
                self.config.readiness_games,
                self.config.ticks,
                &cells,
            )
        };
        self.mode = Mode::Probing {
            attempt,
            champion,
            tasks,
            cursor: 0,
            wins: 0,
        };
    }

    fn step_probe(
        &mut self,
        attempt: u64,
        champion: String,
        tasks: Vec<Task>,
        cursor: usize,
        wins: u32,
    ) -> Unit {
        let Some(genome) = self.champion.clone() else {
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        };
        if genome.fingerprint() != champion || cursor >= tasks.len() {
            let played = cursor.max(1);
            let rate = wins as f64 / played as f64;
            self.last_validation = Some(rate);
            let same = genome.fingerprint() == champion;
            match (same, self.ladder, rate >= self.config.readiness_threshold) {
                // Climbing and strong enough: spend the audit.
                (true, Ladder::Climbing, true) => {
                    self.note(format!(
                        "readiness {:.1}% {} over {cursor} probe games against cyborgs: \
                         opening an audit",
                        rate * 100.0,
                        self.successes()
                    ));
                    self.begin_gate(Round::Audit);
                }
                // Broad and strong enough on the balanced distribution: spend
                // the held-out rounds. The probe itself proves nothing.
                (true, Ladder::Broad, true) => {
                    self.note(format!(
                        "balanced readiness {:.1}% {} over {cursor} probe games against \
                         Awesome cyborgs: opening an overall audit",
                        rate * 100.0,
                        self.successes()
                    ));
                    self.begin_overall(Round::Audit);
                }
                (true, Ladder::Broad, false) => {
                    self.note(format!(
                        "balanced readiness {:.1}% {} over {cursor} probe games, below the \
                         {:.0}% trigger: continuing to train (diagnostic only, not gate \
                         evidence)",
                        rate * 100.0,
                        self.successes(),
                        self.config.readiness_threshold * 100.0
                    ));
                    self.mode = Mode::Training;
                }
                // Mixed and slipping against the original opponents: sweep.
                (true, Ladder::Mixed, false) => {
                    self.note(format!(
                        "cyborg rehearsal fell to {:.1}% {} over {cursor} probe games: \
                         opening a bounded regression sweep",
                        rate * 100.0,
                        self.successes()
                    ));
                    self.begin_gate(Round::Regression);
                }
                _ => self.mode = Mode::Training,
            }
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        let network = self.compiled(&genome);
        // The probe panel is fixed and played to the end, so a whole slice of
        // it can be queued at once: no fight in the batch is speculative and
        // every one of them is counted.
        let batch = tasks.len().min(cursor + self.fight_budget());
        let mut played = 0;
        let mut won = wins;
        let gate = self.config.scoring.gate;
        let queued: Vec<Fight> = tasks[cursor..batch]
            .iter()
            .map(|task| self.fight(*task, &network))
            .collect();
        let outcomes = self.pool.map(queued, |fight| fight.run());
        for (task, outcome) in tasks[cursor..batch].iter().zip(outcomes) {
            let outcome = self.absorb(outcome);
            // The readiness probe decides whether to spend an audit, so it has
            // to ask the same question the audit will.
            let success = outcome.succeeded(gate);
            won += success as u32;
            played += 1;
            // Per-hull readiness diagnostics accumulate in step with the
            // cursor, so a resume mid-probe keeps the two consistent.
            if let Some(reading) = self.broad_ready.as_mut() {
                if reading.champion == champion {
                    reading.record(task.cell, success);
                }
            }
        }
        self.mode = Mode::Probing {
            attempt,
            champion,
            tasks,
            cursor: batch,
            wins: won,
        };
        Unit {
            episodes: played,
            boundary: false,
        }
    }

    fn begin_gate(&mut self, round: Round) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            self.mode = Mode::Training;
            return;
        };
        // Always the CYBORG board. A frozen copy of ourselves is never gated
        // and never swept; it cannot tell us whether we still beat the
        // original opponents.
        let mut cells = self.cyborg_cells();
        let mut config = self.config.audit;
        if round == Round::Regression {
            // A sweep is bounded far more tightly than a gate, and it visits
            // the cells the sampler currently believes are weakest first, so
            // the budget is spent where a regression would actually be.
            config.budget = self.config.regression_budget;
            config.max_failures = u32::MAX;
            let sampler = self.config.sampler;
            let generation = self.population.generation;
            let stats = &self.stats;
            let priority = &self.priority;
            cells.sort_by(|a, b| {
                let score = |cell: &Cell| {
                    sampler::weight(
                        &sampler,
                        stats.cells.get(cell).unwrap_or(&Default::default()),
                        generation,
                        priority.contains(cell),
                    )
                };
                score(b).total_cmp(&score(a))
            });
        }
        let priority = self.priority.clone();
        self.mode = Mode::Auditing {
            gate: Gate::open(
                champion,
                self.stage,
                self.opponent_revision,
                round,
                config,
                &cells,
                &priority,
            ),
        };
    }

    fn step_audit(&mut self, mut gate: Gate) -> Unit {
        let Some(genome) = self.champion.clone() else {
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        };
        // The candidate is frozen for the whole panel. If it moved, the
        // evidence describes a policy that no longer exists.
        if genome.fingerprint() != gate.champion
            || gate.stage != self.stage
            || gate.opponent_revision != self.opponent_revision
        {
            self.note("audit abandoned: the candidate or opponent changed".into());
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        match gate.progress() {
            Progress::Running => {}
            finished => return self.finish_gate(gate, finished),
        }
        let network = self.compiled(&genome);
        let stream = match gate.round {
            Round::Audit => StreamTag::Audit,
            Round::Confirm => StreamTag::Confirm,
            Round::Regression => StreamTag::Regression,
        };
        let attempt = self.audit_attempt;
        let ticks = self.config.ticks;
        let criterion = self.config.scoring.gate;
        let mut played = 0u64;
        for _ in 0..8 {
            let Some((cell, slot)) = gate.next_task() else {
                break;
            };
            let swap = slot % 2 == 1;
            let task = Task {
                cell,
                swap,
                seed: episode_seed(
                    stream,
                    self.config.salt,
                    cell.key(),
                    swap as u64,
                    attempt * 1_000_000 + self.stage as u64 * 1_000 + slot as u64,
                ),
                ticks,
            };
            let outcome = self.play(&task, &network);
            // Audits, confirmations and regression sweeps all count successes
            // under the run's configured criterion, so the evidence that opens
            // a stage means the same thing the population was selected on.
            gate.record(cell, outcome.succeeded(criterion));
            played += 1;
            if gate.progress() != Progress::Running {
                break;
            }
        }
        let progress = gate.progress();
        if progress == Progress::Running {
            self.mode = Mode::Auditing { gate };
            return Unit {
                episodes: played,
                boundary: false,
            };
        }
        let mut unit = self.finish_gate(gate, progress);
        unit.episodes += played;
        unit
    }

    fn finish_gate(&mut self, gate: Gate, progress: Progress) -> Unit {
        if gate.round == Round::Regression {
            return self.finish_regression(gate);
        }
        match progress {
            Progress::Passed if gate.round == Round::Audit => {
                for (cell, tally) in gate.evidence() {
                    self.evidence.insert(*cell, *tally);
                }
                self.note(format!(
                    "audit panel passed for {} at stage {}: confirming on a disjoint panel",
                    gate.champion, self.stage
                ));
                self.begin_gate(Round::Confirm);
            }
            Progress::Passed => {
                for (cell, tally) in gate.evidence() {
                    self.evidence.insert(*cell, *tally);
                }
                self.advance_stage(&gate.champion);
            }
            Progress::Failed | Progress::Exhausted => {
                self.priority = gate.failed_cells();
                self.audit_attempt += 1;
                for (cell, tally) in gate.evidence() {
                    self.evidence.insert(*cell, *tally);
                }
                let reason = if progress == Progress::Exhausted {
                    "budget exhausted"
                } else {
                    "a matchup could not clear the bound"
                };
                self.note(format!(
                    "{} round ended at stage {}: {reason}; {} cell(s) flagged",
                    gate.round.as_str(),
                    self.stage,
                    self.priority.len()
                ));
                self.mode = Mode::Training;
            }
            Progress::Running => {
                self.mode = Mode::Auditing { gate };
            }
        }
        Unit {
            episodes: 0,
            boundary: true,
        }
    }

    /// A regression sweep decides nothing. It records what it saw, points the
    /// sampler at whatever slipped, and hands the loop back to training.
    fn finish_regression(&mut self, gate: Gate) -> Unit {
        let failed = gate.failed_cells();
        let swept = gate.tallies.len();
        self.regression_swept = swept;
        self.regression_failed = failed.len();
        if failed.is_empty() {
            self.note(format!(
                "regression sweep clear: {swept} cyborg matchup(s) checked over {} fights, \
                 none below the target",
                gate.spent
            ));
            self.priority.clear();
        } else {
            let example = failed
                .first()
                .map(|c| format!("{} against {}", c.our_ship().name(), c.their_ship().name()))
                .unwrap_or_default();
            self.note(format!(
                "regression sweep found {} of {swept} cyborg matchup(s) below the target \
                 (for example {example}); rehearsing them harder",
                failed.len()
            ));
            // Failure turns straight into sampling pressure rather than into a
            // number nobody acts on.
            self.priority = failed;
        }
        // A sweep is evidence about cyborg cells for the current champion, so
        // it is kept and displayed like any other champion audit evidence.
        for (cell, tally) in gate.evidence() {
            self.evidence.insert(*cell, *tally);
        }
        // A later sweep must be fresh evidence, not a replay of this one.
        self.audit_attempt += 1;
        self.mode = Mode::Training;
        Unit {
            episodes: 0,
            boundary: true,
        }
    }

    /// Opens one round of the broad aggregate gate on a fresh balanced
    /// held-out panel. The audit and confirmation rounds draw from different
    /// seed partitions, so the confirmation is genuinely disjoint evidence and
    /// not a replay of the audit.
    fn begin_overall(&mut self, round: Round) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            self.mode = Mode::Training;
            return;
        };
        let config = self.config.broad;
        let stream = match round {
            Round::Confirm => StreamTag::Confirm,
            _ => StreamTag::Audit,
        };
        let tasks = broad::balanced_panel(
            stream,
            self.config.salt,
            self.audit_attempt,
            config.pairs,
            self.config.ticks,
        );
        self.broad_shown = Source::of_round(round);
        self.mode = Mode::Overall {
            gate: Overall::open(self.audit_attempt, round, config.target, champion, tasks),
        };
    }

    fn step_overall(&mut self, mut gate: Overall) -> Unit {
        let Some(genome) = self.champion.clone() else {
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        };
        // The candidate is frozen for the whole attempt. If it moved, the
        // evidence describes a policy that no longer exists.
        if genome.fingerprint() != gate.evaluation.champion {
            self.note("overall round abandoned: the candidate changed".into());
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        if gate.progress() != broad::Progress::Running {
            return self.finish_overall(gate);
        }
        let network = self.compiled(&genome);
        let criterion = self.config.scoring.gate;
        let mut played = 0u64;
        for _ in 0..8 {
            let Some(task) = gate.next_task() else {
                break;
            };
            let outcome = self.play(&task, &network);
            gate.record(outcome.succeeded(criterion));
            played += 1;
            if gate.progress() != broad::Progress::Running {
                break;
            }
        }
        if gate.progress() == broad::Progress::Running {
            self.mode = Mode::Overall { gate };
            return Unit {
                episodes: played,
                boundary: false,
            };
        }
        let mut unit = self.finish_overall(gate);
        unit.episodes += played;
        unit
    }

    fn finish_overall(&mut self, gate: Overall) -> Unit {
        let passed = gate.progress() == broad::Progress::Passed;
        let tally = gate.evaluation.tally();
        let champion = gate.evaluation.champion.clone();
        let rate = tally.rate().unwrap_or(0.0) * 100.0;
        let bound = tally.lower_bound().unwrap_or(0.0) * 100.0;
        let target = self.config.broad.target * 100.0;
        let round = gate.round;
        if round == Round::Confirm {
            self.broad_confirm = Some(gate.evaluation.clone());
        } else {
            self.broad_audit = Some(gate.evaluation.clone());
        }
        if !passed {
            self.audit_attempt += 1;
            self.note(format!(
                "overall {} round failed for {champion}: {}/{} {} = {rate:.1}% on the \
                 balanced held-out panel, lower bound {bound:.1}% against a {target:.0}% \
                 target",
                round.as_str(),
                tally.wins,
                tally.games,
                self.successes()
            ));
            self.mode = Mode::Training;
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        if round != Round::Confirm {
            self.note(format!(
                "overall audit passed for {champion}: {}/{} {} = {rate:.1}%, lower bound \
                 {bound:.1}%; confirming on a disjoint balanced panel",
                tally.wins,
                tally.games,
                self.successes()
            ));
            self.begin_overall(Round::Confirm);
            return Unit {
                episodes: 0,
                boundary: true,
            };
        }
        self.pass_overall(gate.evaluation, tally, rate, bound);
        Unit {
            episodes: 0,
            boundary: true,
        }
    }

    /// Both held-out rounds cleared the aggregate target.
    ///
    /// The run goes on to the existing mixed phase, with its frozen self-play
    /// opponent and every one of its regression safeguards, and keeps its broad
    /// provenance: `origin` survives, the scope stays "overall-balanced", and
    /// `evidence` is deliberately left alone, so a run that never audited a
    /// single cell cannot arrive in the mixed phase claiming 625 mastered
    /// matchups.
    fn pass_overall(&mut self, evidence: Evaluation, tally: Tally, rate: f64, bound: f64) {
        let champion = evidence.champion.clone();
        self.broad_gate = Some(evidence);
        self.audit_attempt += 1;
        self.priority.clear();
        self.ladder = Ladder::Mixed;
        self.frozen_opponent = self.champion.clone();
        self.opponent_revision += 1;
        self.note(format!(
            "overall balanced gate passed by {champion}: {}/{} = {rate:.1}%, lower bound \
             {bound:.1}% over a balanced any-versus-any panel. This is an AGGREGATE result \
             over the whole distribution, not a claim that every matchup is mastered. \
             Entering the mixed phase with frozen opponent revision {} alongside continued \
             Awesome cyborg rehearsal.",
            tally.wins, tally.games, self.opponent_revision
        ));
        self.mode = Mode::Training;
    }

    fn advance_stage(&mut self, champion: &str) {
        self.audit_attempt += 1;
        self.priority.clear();
        if self.stage < curriculum::FINAL_STAGE {
            let (side, ship) = curriculum::next_addition(self.stage);
            self.stage += 1;
            self.note(format!(
                "stage {} mastered by {champion}; adding {} hull {}",
                self.stage - 1,
                side,
                ship.map(|s| s.name()).unwrap_or("none")
            ));
            self.evidence.clear();
        } else {
            self.ladder = Ladder::Mixed;
            self.frozen_opponent = self.champion.clone();
            self.opponent_revision += 1;
            self.note(format!(
                "every ordered cyborg matchup is gated by {champion}; entering the mixed phase \
                 with frozen opponent revision {} alongside continued Awesome cyborg rehearsal",
                self.opponent_revision
            ));
        }
        self.mode = Mode::Training;
    }

    pub fn phase(&self) -> &'static str {
        match self.mode {
            Mode::Training | Mode::Probing { .. } => "training",
            Mode::Auditing { .. } | Mode::Overall { .. } => "auditing",
        }
    }

    /// The round a gate is running, if one is.
    pub fn round(&self) -> Option<Round> {
        match &self.mode {
            Mode::Auditing { gate } => Some(gate.round),
            Mode::Overall { gate } => Some(gate.round),
            _ => None,
        }
    }

    /// Whether this run's scope was set by an operator transition rather than
    /// earned stage by stage. Sticky: a broad run that reaches the mixed phase
    /// is still a broad-origin run.
    pub fn from_broad(&self) -> bool {
        self.ladder == Ladder::Broad || self.origin.is_some()
    }

    /// Forks this run's scope to any-versus-any against the Awesome cyborg.
    ///
    /// What CARRIES ACROSS is everything the policy actually is: every genome
    /// and weight, every per-genome mutation rate, the species structure, the
    /// innovation counter, the champion and its rates, both RNG streams
    /// verbatim, the sampler's decayed per-cell statistics, the episode and
    /// timing totals, and the whole history and event log.
    ///
    /// What is DROPPED is everything that was a measurement of the old scope.
    /// Every fitness number was measured on a panel this run is abandoning, and
    /// all gate evidence was collected on a one-cell board; carrying either
    /// into a 625-cell distribution would compare numbers that answer different
    /// questions. The abandonment is recorded as an event rather than performed
    /// quietly, and the transition writes a history row at the new stage so the
    /// scope change is visible in the chart instead of appearing as a jump.
    ///
    /// The full roster is unlocked here by an operator, NOT earned: `stage`
    /// becomes the final stage so every hull is active, and `evidence` is left
    /// empty so nothing reports 625 mastered matchups.
    ///
    /// Refuses a run graded against anything but the Awesome cyborg. Broad mode
    /// reports its aggregate "against the Awesome cyborg", and a run carrying a
    /// weaker rating would keep producing that label while fighting a weaker
    /// opponent. The caller either fixes the rating
    /// explicitly, which is recorded, or the fork does not happen.
    pub fn broaden(&mut self, run_id: &str, reason: &str) -> Result<(), String> {
        if self.config.rating != CyborgRating::AwesomeCyborg {
            return Err(format!(
                "this run is graded against the {} cyborg, but broad mode's aggregate is \
                 defined against the Awesome cyborg. Pass --rating awesome to change it \
                 explicitly, which is recorded with the transition, or fork a run that is \
                 already on Awesome.",
                rating_name(self.config.rating)
            ));
        }
        let origin = Origin {
            run_id: self.config.run_id.clone(),
            generation: self.population.generation,
            fingerprint: self.evaluator.clone(),
            reason: reason.to_string(),
        };
        let from_stage = self.stage;
        let dropped_cells = self.evidence.len();
        let abandoned = self.panel.as_ref().map_or(0, |panel| panel.tasks.len());
        let in_flight = match &self.mode {
            Mode::Training => "none",
            Mode::Probing { .. } => "a readiness probe",
            Mode::Auditing { .. } => "an audit round",
            Mode::Overall { .. } => "an overall round",
        };

        self.config.run_id = run_id.to_string();
        // Broad mode reads its panel size from its own settings; keeping the
        // staged sampler in step means a later mixed phase does not silently
        // shrink the panel back to the ladder's size.
        self.config.sampler.panel = self.config.broad.panel;
        self.stage = curriculum::FINAL_STAGE;
        self.ladder = Ladder::Broad;
        self.evidence.clear();
        self.priority.clear();
        self.panel = None;
        self.mode = Mode::Training;
        self.population.clear_fitness();
        self.last_training_wins = None;
        self.last_validation = None;
        self.regression_swept = 0;
        self.regression_failed = 0;
        self.broad_ready = None;
        self.broad_audit = None;
        self.broad_confirm = None;
        self.broad_gate = None;
        self.broad_shown = None;
        self.coverage_cursor = 0;
        // A fresh attempt counter, so the new run's held-out panels are drawn
        // at different trial indices from any the source used. Different
        // indices, not provably different seeds: within one stream
        // `episode_seed` hashes into a finite pool and a repeat is possible.
        // The guarantee that matters is the stream partitioning, which is what
        // keeps held-out fights out of training.
        self.audit_attempt += 1;
        self.evaluator = build_fingerprint();
        self.origin = Some(origin.clone());
        self.history.push_back(HistoryRow {
            generation: self.population.generation,
            stage: self.stage,
            training_win_rate: None,
            validation_win_rate: None,
            species: self.population.species.len(),
            nodes: self.champion.as_ref().map_or(0, |g| g.nodes.len()),
            episodes: self.episodes,
        });
        while self.history.len() > MAX_HISTORY {
            self.history.pop_front();
        }
        self.note(format!(
            "scope changed to any-versus-any: {reason}. Forked from run {} at generation {} \
             (evaluator {}), stage {from_stage} became stage {} so all {} ordered Awesome \
             cyborg matchups are ACTIVE. The full roster was unlocked by this transition, \
             not earned: {dropped_cells} cell(s) of gate evidence were discarded and NOTHING \
             is mastered. {in_flight} and a panel of {abandoned} fight(s) were abandoned \
             deliberately, and every fitness score with them, because they measured the old \
             distribution. Genomes, weights, mutation rates, species, the innovation counter, \
             the champion and both RNG streams carry across untouched.",
            origin.run_id,
            origin.generation,
            origin.fingerprint,
            self.stage,
            curriculum::cells(self.stage).len()
        ));
        // A baseline reading of the inherited policy on the new distribution,
        // taken before the first broad generation rather than five generations
        // in. Diagnostic: it reports what was inherited, it gates nothing.
        self.begin_probe();
        Ok(())
    }

    pub fn mastered(&self) -> usize {
        self.evidence
            .values()
            .filter(|t| {
                t.lower_bound()
                    .is_some_and(|b| b > self.config.audit.target)
            })
            .count()
    }
}

fn now() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    iso8601(seconds)
}

/// Days are counted from the Unix epoch with the civil-calendar algorithm, so
/// no dependency is needed for a timestamp the dashboard can parse.
pub fn iso8601(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let rest = seconds % 86_400;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { year + 1 } else { year };
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        rest / 3600,
        (rest % 3600) / 60,
        rest % 60
    )
}
