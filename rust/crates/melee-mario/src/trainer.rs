//! The training state machine.
//!
//! Work is done in small units so that a pause, a stop, a checkpoint or an API
//! request never has to wait for a whole generation. Every unit is a pure
//! function of the checkpointed state, so stopping and resuming reproduces the
//! same trajectory as running straight through, and a process killed mid-batch
//! simply replays that batch deterministically.
//!
//! Two rules run through the whole file:
//!
//!   * Fitness numbers are comparable only inside one panel. Champion
//!     replacement rescores the incumbent on the challenger's own panel.
//!   * Gate evidence belongs to one candidate fingerprint. A champion
//!     replacement throws it away rather than pooling it across candidates.

use crate::audit::{Round, Tally};
use crate::broad::{self, BroadConfig, Evaluation, Overall, Source};
use crate::episode::{self, Rival, ScoringConfig, Task};
use crate::genome::Genome;
use crate::graph::Network;
use crate::neat::{MutationRates, NeatConfig, Population};
use crate::pool::Pool;
use crate::rng::Stream;
use crate::sampler::{Panel, SamplerStats};
use melee_sim::input::CyborgRating;
use serde_json::{json, Value};
use std::collections::VecDeque;
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
    /// What ranks the population, what opens a gate and what a fight that
    /// did the enemy no net harm is worth. A per-run choice, recorded in the
    /// run's configuration so that a checkpoint always says what its fitness
    /// numbers and its success counts mean.
    pub scoring: ScoringConfig,
    /// How the training panel is drawn and what the balanced gate demands.
    pub broad: BroadConfig,
    /// Fraction of wall time the evaluator is allowed to compute.
    pub duty: f64,
    pub readiness_games: usize,
    pub readiness_threshold: f64,
    pub readiness_period: u32,
}

impl Config {
    pub fn to_json(&self) -> Value {
        json!({"version": ENGINE_VERSION, "run_id": self.run_id, "salt": self.salt.to_string(),
               "ticks": self.ticks, "rating": rating_name(self.rating),
               "neat": self.neat.to_json(), "broad": self.broad.to_json(),
               "scoring": self.scoring.to_json(), "duty": self.duty,
               "readiness_games": self.readiness_games,
               "readiness_threshold": self.readiness_threshold,
               "readiness_period": self.readiness_period})
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
            broad: BroadConfig::from_json(value.get("broad")?)?,
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

/// The one piece of work the trainer is currently doing.
#[derive(Clone, Debug)]
pub enum Mode {
    Training,
    /// A cheap fixed probe on its own seed stream, used only to decide whether
    /// an expensive held-out round is worth opening. It is never evidence for
    /// one.
    Probing {
        attempt: u64,
        champion: String,
        tasks: Vec<Task>,
        cursor: usize,
        wins: u32,
    },
    /// One round of the aggregate gate on a balanced held-out panel. It
    /// measures ONE number over a distribution, never a number per matchup.
    Overall {
        gate: Overall,
    },
}

#[derive(Clone, Debug)]
pub struct HistoryRow {
    pub generation: u32,
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
    pub champion: Option<Genome>,
    /// The mutation rates the champion had drifted to. Carried with it so that
    /// re-entering it as an elite does not reset its search intensity.
    pub champion_rates: MutationRates,
    pub stats: SamplerStats,
    pub panel: Option<Panel>,
    pub mode: Mode,
    /// How far the coverage rotation has walked. Monotonic, and the only
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
    /// combat win. It covers the whole run, always: it is seeded at zero and
    /// only ever incremented, and a document that predates it is refused by
    /// schema version rather than resumed with a partial window.
    pub combat_wins: u64,
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
    /// The generation that is actually ON DISK, or `None` while nothing has
    /// been saved yet.
    ///
    /// Derived at runtime and never persisted: a checkpoint that stored this
    /// field would be storing a claim about itself, and a saved copy of a
    /// stale value would outlive the fact it described. A decoded run takes it
    /// from the population it actually restored, and a live run only advances
    /// it once a save has returned successfully, so the dashboard's
    /// "checkpoint generation" is the generation a resume would really start
    /// from rather than the one the trainer has reached in memory.
    pub saved_generation: Option<u32>,
    /// Compiled graphs are cached here for the length of a panel so the
    /// strongly-connected-component pass is paid once per genome, not once per
    /// fight.
    pub(crate) cache: Option<(String, Arc<Network>)>,
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
    rating: CyborgRating,
}

impl Fight {
    fn run(&self) -> episode::Outcome {
        episode::run(&self.task, &self.ours, Rival::Cyborg(self.rating))
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
            champion: None,
            champion_rates: config_rates,
            stats: SamplerStats::default(),
            panel: None,
            mode: Mode::Training,
            coverage_cursor: 0,
            broad_ready: None,
            broad_audit: None,
            broad_confirm: None,
            broad_gate: None,
            broad_shown: None,
            episodes: 0,
            unresolved: 0,
            combat_wins: 0,
            elapsed: 0.0,
            compute: 0.0,
            audit_attempt: 0,
            last_validation: None,
            last_training_wins: None,
            nice: 0,
            pool: Pool::new(1),
            history: VecDeque::new(),
            events: VecDeque::new(),
            saved_at: None,
            saved_generation: None,
            cache: None,
        };
        trainer.note(format!(
            "run {} seeded: population {}, all {} ordered matchups active from \
             generation one, graded on the balanced aggregate against the {} cyborg",
            trainer.config.run_id,
            trainer.config.neat.population,
            broad::BOARD,
            rating_name(trainer.config.rating)
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
    fn fight(&self, task: Task, ours: &Arc<Network>) -> Fight {
        Fight {
            task,
            ours: ours.clone(),
            rating: self.config.rating,
        }
    }

    /// Folds one finished fight into the run's counters.
    ///
    /// The single choke point every episode passes through, whichever work
    /// path asked for it: training, a readiness probe, an audit round or a
    /// confirmation round. Counting here, on the main thread and in the order the
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
        let rating = self.config.rating;
        let queued: Vec<Fight> = networks
            .iter()
            .flat_map(|network| tasks.iter().map(move |task| (*task, network.clone())))
            .map(|(task, ours)| Fight { task, ours, rating })
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
                        .record(task.cell, outcome.succeeded(gate), self.config.broad.decay);
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
        // A balanced coverage rotation over the whole board, plus a bounded
        // adaptive remainder. Coverage is earned over generations rather than
        // bought by enumerating 625 matchups every generation.
        let tasks = broad::draw(
            &self.config.broad,
            &mut self.stats,
            &mut self.sampling,
            self.config.salt,
            self.config.ticks,
            &mut self.coverage_cursor,
        );
        self.panel = Some(Panel::of(tasks));
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

    /// Records a new champion, discarding the previous candidate's gate
    /// evidence rather than pooling it.
    fn promote(&mut self, genome: Genome, rates: MutationRates) {
        let fingerprint = genome.fingerprint();
        self.champion_rates = rates;
        let nodes = genome.nodes.len();
        let links = genome.enabled_count();
        self.champion = Some(genome);
        // Every measurement in flight described the policy being replaced.
        // `broad_gate` is deliberately NOT cleared: it names the champion that
        // cleared the aggregate target, and the status document reports the
        // gate as passed only while that name is still the champion.
        self.broad_ready = None;
        self.broad_audit = None;
        self.broad_confirm = None;
        self.broad_shown = None;
        if matches!(self.mode, Mode::Probing { .. } | Mode::Overall { .. }) {
            self.mode = Mode::Training;
        }
        self.note(format!(
            "champion {fingerprint} promoted ({nodes} nodes, {links} links); gate evidence reset"
        ));
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

    /// A probe means exactly one thing: is this champion worth spending a
    /// held-out balanced round on. It gates nothing and proves nothing.
    ///
    /// A champion that has already cleared both rounds has nothing left to
    /// ask, so it is never probed again and never re-audited: doing so would
    /// spend withheld evidence re-answering a question this run has already
    /// answered. A promotion makes the question live once more, because the
    /// proof names the policy it was measured on.
    fn should_probe(&self) -> bool {
        self.champion.is_some()
            && !self.gate_passed()
            && self.population.generation % self.config.readiness_period == 0
    }

    /// Opens a readiness probe on the current champion: a cheap balanced
    /// reading on its own seed stream, over the same any-versus-any
    /// distribution the gate is graded on, so the cheap answer and the
    /// expensive one answer the same question.
    fn begin_probe(&mut self) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            return;
        };
        let attempt = self.audit_attempt;
        self.broad_ready = Some(Evaluation::open(Source::Ready, champion.clone()));
        self.broad_shown = Some(Source::Ready);
        let tasks = broad::readiness_panel(
            self.config.salt,
            attempt,
            self.config.readiness_games,
            self.config.ticks,
        );
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
            match (same, rate >= self.config.readiness_threshold) {
                (true, true) => {
                    self.note(format!(
                        "balanced readiness {:.1}% {} over {cursor} probe games against \
                         {} cyborgs: opening a held-out audit round",
                        rate * 100.0,
                        self.successes(),
                        rating_name(self.config.rating)
                    ));
                    self.begin_overall(Round::Audit);
                }
                (true, false) => {
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

    /// Opens one round of the aggregate gate on a fresh balanced held-out
    /// panel. The audit and confirmation rounds draw from different seed
    /// partitions, so the confirmation is genuinely disjoint evidence and not
    /// a replay of the audit.
    fn begin_overall(&mut self, round: Round) {
        let Some(champion) = self.champion.as_ref().map(Genome::fingerprint) else {
            self.mode = Mode::Training;
            return;
        };
        let config = self.config.broad;
        let tasks = broad::balanced_panel(
            Overall::stream(round),
            self.config.salt,
            self.audit_attempt,
            config.pairs,
            self.config.ticks,
        );
        self.broad_shown = Some(Source::of_round(round));
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
    /// The champion that cleared it is recorded by NAME and the run keeps
    /// training. There is no further phase to enter: the result is an
    /// aggregate over the whole distribution, not a claim that any particular
    /// matchup is mastered, and the population can still get better at it.
    /// [`Trainer::gate_passed`] is what stops the run re-auditing the same
    /// champion forever; a promotion makes it false again, because the proof
    /// names the policy it was measured on.
    fn pass_overall(&mut self, evidence: Evaluation, tally: Tally, rate: f64, bound: f64) {
        let champion = evidence.champion.clone();
        self.broad_gate = Some(evidence);
        self.audit_attempt += 1;
        self.note(format!(
            "overall balanced gate passed by {champion}: {}/{} {} = {rate:.1}%, lower bound \
             {bound:.1}% over a balanced any-versus-any panel. This is an AGGREGATE result \
             over the whole distribution, not a claim that every matchup is mastered. \
             Training continues; a future champion has to clear it again on its own evidence.",
            tally.wins,
            tally.games,
            self.successes()
        ));
        self.mode = Mode::Training;
    }

    /// Whether the CURRENT champion is the one that cleared both held-out
    /// rounds. The proof outlives the champion that earned it, so this compares
    /// names rather than assuming a stored proof is about whoever holds the
    /// title now.
    pub fn gate_passed(&self) -> bool {
        match (&self.broad_gate, &self.champion) {
            (Some(proof), Some(genome)) => proof.champion == genome.fingerprint(),
            _ => false,
        }
    }

    pub fn phase(&self) -> &'static str {
        match self.mode {
            Mode::Training | Mode::Probing { .. } => "training",
            Mode::Overall { .. } => "auditing",
        }
    }

    /// The round a gate is running, if one is.
    pub fn round(&self) -> Option<Round> {
        match &self.mode {
            Mode::Overall { gate } => Some(gate.round),
            _ => None,
        }
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
