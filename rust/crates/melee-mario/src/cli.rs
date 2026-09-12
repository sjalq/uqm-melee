//! Command line, run supervision and the duty-cycle governor.
//!
//! The governor is the reason this can run on a laptop that is also being used
//! for something else. A bounded evaluation pool, niced down, and after every
//! unit of work the supervisor sleeps for as long as that work took, scaled by
//! the duty fraction. That cap covers training, readiness probing, auditing and
//! the mixed self-play phase alike, because every one of them is just another
//! unit of work in the same loop.
//!
//! The duty cap governs the SUPERVISOR, which is one thread: it is a fraction
//! of wall time in which the evaluator is allowed to be computing, not a
//! fraction of a core. At `--workers 9 --duty 1` the trainer computes all the
//! time on up to nine cores; at `--workers 1 --duty 0.5` it computes half the
//! time on one. The worker count and the duty cap are independent knobs and
//! the status document reports both without multiplying them together.

use crate::audit::AuditConfig;
use crate::broad::BroadConfig;
use crate::episode::{GateCriterion, Scoring, ScoringConfig, DEFAULT_TICKS};
use crate::neat::NeatConfig;
use crate::pool;
use crate::sampler::SamplerConfig;
use crate::server::{self, Control, Shared};
use crate::status::Phase;
use crate::store::{self, RunLock};
use crate::trainer::{self, Config, Trainer};
use serde_json::Value;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

pub const HELP: &str = "\
melee-mario: MarI/O-style topology evolution for UQM Super Melee.

USAGE
  melee-mario <command> [options]

COMMANDS
  start          Begin a new run in artifacts/mario/<run id>.
  resume         Continue an existing run exactly where it stopped.
  broaden        Fork a STOPPED run into a new any-versus-any run, leaving the
                 original completely untouched. Then resume the new run.
  status         Print one status document and exit. Reads the live server if
                 one is listening, otherwise the last checkpoint, and says so.
  pause          Ask a running trainer to stop computing but keep serving.
  resume-work    Undo a pause.
  stop           Ask a running trainer to checkpoint and exit at a safe point.
  serve          Serve an existing run's last checkpoint without training.
  oracle         Genome oracle: NDJSON in, one {\"outputs\":[13]} line per step.
  bench          Time a few fights and report episodes per second.
  help           This text.

RUN OPTIONS
  --root <path>            Repository root that holds artifacts/ and scripts/.
                           Default: the current directory.
  --run <id>               Run identifier. start defaults to a timestamp,
                           resume and status default to the newest run.
  --seed <n>               Master seed. Default: derived from the run id.
  --port <n>               Loopback port for the dashboard. Default 8788.
  --no-server              Train without listening on anything.
  --allow-rebuild          Resume even though this binary differs from the one
                           that produced the checkpoint. Without it, a rebuilt
                           evaluator refuses to continue someone else's
                           trajectory silently. broaden does not need it and
                           does not accept it: a fork records the source's
                           fingerprint as provenance instead, and an ordinary
                           resume of the new run keeps the guard.

BROADEN OPTIONS
  --from <id>              The STOPPED run to fork. Read under a shared lock, so
                           a trainer still writing it makes the fork fail rather
                           than copy a half-written checkpoint. Never modified.
  --run <id>               Identifier of the NEW run. Must not already have a
                           checkpoint; broaden refuses to overwrite one.
  --reason <text>          Recorded with the transition. Default:
                           \"operator requested any-versus-any\".
  --broad-panel <n>        Fights per genome per generation in broad mode.
                           Default 32. Half are drawn by a balanced rotation
                           over the board, half adaptively.
  --overall-pairs <n>      Ordered pairs in one held-out round; each is played
                           in both seats, so the round is twice this many games.
                           Must be a multiple of 25. Default 500, giving a
                           1000-game round with every hull appearing 20 times on
                           each side.
  --overall-target <r>     Aggregate win rate the Wilson lower bound must clear,
                           on the audit round and again on the confirmation
                           round. Default 0.80.

BUDGET OPTIONS (a bounded local run stops on whichever arrives first)
  --generations <n>        Stop after this many completed generations.
  --episodes <n>           Stop after this many simulated fights.
  --minutes <n>            Stop after this much wall time.

RESOURCE OPTIONS
  --duty <0..1>            Fraction of wall time the evaluator may compute.
                           The share of WALL TIME the trainer may be computing
                           in, not a share of a core: with --workers 9 it paces
                           all nine. Default 0.5, which at the default single
                           worker is one half of one core.
  --workers <n>            Threads evaluating fights. Default 1, which spawns
                           no threads at all. Limited to max(1, cores - 1): a
                           larger request is REJECTED, not quietly reduced. The
                           spare core is capacity left for whatever launched
                           the trainer, not a reservation; nothing is pinned
                           and the OS still places every thread. A single-core
                           host therefore gets one worker and no spare.
                           Training and readiness probing use the pool; audits,
                           confirmations, regression sweeps and broad rounds
                           stay serial because they stop fighting the moment
                           the result is settled. A pure resource knob: the
                           same run at any worker count plays the same fights
                           in the same order and reaches the same state.
  --nice <n>               Scheduling penalty applied to this process.
                           Default 10. Use 0 to leave the priority alone.
                           Applies to the pool: workers inherit it.

TRAINING OPTIONS
  --population <n>         Genomes per generation. Default 300.
  --panel <n>              Fights each genome plays per generation. Default 8.
  --ticks <n>              Display ticks a fight may take. Default 3600, which
                           is one minute of melee. A timeout is never a win.
  --rating <name>          standard, good or awesome. Default awesome.
  --fitness <name>         What the population is RANKED by. Default combat,
                           which is the scorer every existing run used and the
                           meaning of a configuration that names none.
                             combat      a win, plus crew advantage, plus speed.
                             crew-ratio  (our surviving crew / our starting
                                         crew) divided by the same fraction for
                                         them. No win, kill, survival or time
                                         term at all, so a slower fight with the
                                         same end state scores identically. A
                                         score of 1 means both sides kept the
                                         same PERCENTAGE of the crew they
                                         started with; it is a raw ratio, not a
                                         win rate. Fractions are of STARTING
                                         crew, so a hull that gains crew may
                                         legitimately go above 1. Wiping them
                                         out while we still have crew scores
                                         1000, a mutual wipeout scores 1, and
                                         being wiped out ourselves scores 0.
                           This selects; it does NOT gate. What opens a gate is
                           --gate, which is a separate choice.
  --gate <name>            What a stage gate, an audit, a confirmation, a
                           regression sweep, the readiness probe and the
                           sampler's own weakness statistics all COUNT as a
                           success. Default combat-wins, which is what every
                           existing run was gated on and the meaning of a
                           configuration that names none.
                             combat-wins  an actual won-and-resolved fight. A
                                          timeout is not a win and never opens
                                          a gate.
                             crew-lead    we ended STRICTLY ahead on surviving
                                          fraction of STARTING crew, compared
                                          as an exact integer cross product.
                                          Every tie fails, a mutual wipeout
                                          included. A fight that hit the tick
                                          ceiling while we were ahead IS a
                                          success, which is the whole
                                          difference from counting victories.
                           Under crew-lead every win-named rate this run
                           reports counts LEADS, not wins. The factual combat
                           victory count is published separately and is never
                           affected by this flag.
  --no-damage-penalty <m>  Score a fight that left the enemy no worse off at
                           -m instead of whatever the scorer would have said.
                           Default 0, which switches the penalty off entirely
                           and is what every existing run means. Leaving them
                           no worse off is an ENDPOINT comparison, their final
                           crew against their starting crew, not an
                           attribution of damage:
                           crew we did kill and they then regained counts as no
                           net loss. Independent of --fitness and of --gate.
  --audit-panel <n>        Fights per matchup per audit round. Default 100.
  --audit-budget <n>       Fights one audit attempt may spend. Default 200000.
  --readiness-games <n>    Fights in the cheap probe that decides whether an
                           audit is worth opening. Default 128.
  --readiness-threshold <r>  Probe win rate needed to open an audit. Default 0.85.
  --readiness-period <n>   Probe every n generations. Default 5.
  --regression-budget <n>  Fights one mixed-phase regression sweep may spend.
                           Default 4000. A sweep gates nothing; it checks that
                           a policy training against a frozen copy of itself
                           still beats the original cyborgs, and points the
                           sampler at whatever slipped.

NOTES
  The server binds 127.0.0.1 only and serves GET /api/status, GET /api/network,
  POST /api/control {\"action\":\"pause\"|\"resume\"|\"stop\"}, GET / and
  GET /dashboard.js from scripts/mario. There is no option that exposes it.

  BROAD MODE grades one question instead of 625: does the frozen champion clear
  the target on a BALANCED any-versus-any distribution against the Awesome
  cyborg? A held-out audit round and a disjoint confirmation round must each
  clear a Wilson lower bound above the target, every game including timeouts
  counts as played, and per-hull numbers are reported next to the aggregate as
  blind-spot diagnostics that gate nothing. Paired seat outcomes are correlated,
  so this is an operational confidence check on the aggregate, not a formal
  guarantee about every matchup.

  A stage is promoted only when EVERY ordered matchup of that stage clears a
  Wilson lower bound above the target on a fixed withheld panel, and then again
  on a disjoint confirmation panel. On the default 100-fight panel that allows
  at most twelve losses per matchup, an 88% observed rate, because a lower bound
  above 0.8 is a stronger demand than an observed rate above 0.8.
";

pub struct Options {
    pub command: String,
    pub root: PathBuf,
    pub run: Option<String>,
    /// The run `broaden` forks from. Never written to.
    pub from: Option<String>,
    /// Why the scope changed, recorded with the transition.
    pub reason: Option<String>,
    pub seed: Option<u64>,
    pub port: u16,
    pub serve: bool,
    pub nice: i32,
    /// Requested evaluation threads. A property of this invocation, not of the
    /// run: never stored in the run's configuration, never fingerprinted, and
    /// free to differ between a run and its resume.
    pub workers: usize,
    pub generations: Option<u32>,
    pub episodes: Option<u64>,
    pub minutes: Option<f64>,
    pub allow_rebuild: bool,
    /// Flags the operator actually typed. On a resume the run's own stored
    /// configuration is authoritative, so anything typed here that the run
    /// already decided has to be reported rather than silently ignored.
    pub given: Vec<String>,
    pub config: Config,
}

fn parse_value<T: std::str::FromStr>(raw: Option<&String>, name: &str) -> Result<T, String> {
    raw.ok_or_else(|| format!("{name} needs a value"))?
        .parse()
        .map_err(|_| format!("{name} was not a valid value"))
}

pub fn parse(arguments: &[String]) -> Result<Options, String> {
    let command = arguments
        .first()
        .cloned()
        .unwrap_or_else(|| "help".to_string());
    let mut options = Options {
        command,
        root: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
        run: None,
        from: None,
        reason: None,
        seed: None,
        port: server::DEFAULT_PORT,
        serve: true,
        nice: 10,
        workers: 1,
        generations: None,
        episodes: None,
        minutes: None,
        allow_rebuild: false,
        given: Vec::new(),
        config: Config {
            run_id: String::new(),
            salt: 0,
            ticks: DEFAULT_TICKS,
            rating: melee_sim::input::CyborgRating::AwesomeCyborg,
            neat: NeatConfig::default(),
            sampler: SamplerConfig::default(),
            audit: AuditConfig::default(),
            broad: BroadConfig::default(),
            scoring: ScoringConfig::default(),
            duty: 0.5,
            readiness_games: 128,
            readiness_threshold: 0.85,
            readiness_period: 5,
            regression_budget: 4_000,
        },
    };
    let mut at = 1;
    while at < arguments.len() {
        let flag = arguments[at].as_str();
        let next = arguments.get(at + 1);
        let mut consumed = 2;
        if flag.starts_with("--") {
            options.given.push(flag.to_string());
        }
        match flag {
            "--root" => {
                options.root = PathBuf::from(next.ok_or("--root needs a path")?);
            }
            "--run" => options.run = Some(next.ok_or("--run needs an id")?.clone()),
            "--from" => options.from = Some(next.ok_or("--from needs a run id")?.clone()),
            "--reason" => options.reason = Some(next.ok_or("--reason needs text")?.clone()),
            "--broad-panel" => options.config.broad.panel = parse_value(next, "--broad-panel")?,
            "--overall-pairs" => options.config.broad.pairs = parse_value(next, "--overall-pairs")?,
            "--overall-target" => {
                options.config.broad.target = parse_value(next, "--overall-target")?
            }
            "--seed" => options.seed = Some(parse_value(next, "--seed")?),
            "--port" => options.port = parse_value(next, "--port")?,
            "--no-server" => {
                options.serve = false;
                consumed = 1;
            }
            "--allow-rebuild" => {
                options.allow_rebuild = true;
                consumed = 1;
            }
            "--nice" => options.nice = parse_value(next, "--nice")?,
            "--generations" => options.generations = Some(parse_value(next, "--generations")?),
            "--episodes" => options.episodes = Some(parse_value(next, "--episodes")?),
            "--minutes" => options.minutes = Some(parse_value(next, "--minutes")?),
            "--duty" => options.config.duty = parse_value(next, "--duty")?,
            "--workers" => options.workers = parse_value(next, "--workers")?,
            "--population" => options.config.neat.population = parse_value(next, "--population")?,
            "--panel" => options.config.sampler.panel = parse_value(next, "--panel")?,
            "--ticks" => options.config.ticks = parse_value(next, "--ticks")?,
            "--rating" => {
                options.config.rating = trainer::parse_rating(next.ok_or("--rating needs a name")?)
                    .ok_or("--rating must be standard, good or awesome")?;
            }
            "--fitness" => {
                options.config.scoring.fitness =
                    Scoring::parse(next.ok_or("--fitness needs a name")?)
                        .ok_or("--fitness must be combat or crew-ratio")?;
            }
            "--gate" => {
                options.config.scoring.gate =
                    GateCriterion::parse(next.ok_or("--gate needs a name")?)
                        .ok_or("--gate must be combat-wins or crew-lead")?;
            }
            "--no-damage-penalty" => {
                options.config.scoring.no_damage_penalty =
                    parse_value(next, "--no-damage-penalty")?
            }
            "--audit-panel" => options.config.audit.panel = parse_value(next, "--audit-panel")?,
            "--audit-budget" => options.config.audit.budget = parse_value(next, "--audit-budget")?,
            "--readiness-games" => {
                options.config.readiness_games = parse_value(next, "--readiness-games")?
            }
            "--readiness-threshold" => {
                options.config.readiness_threshold = parse_value(next, "--readiness-threshold")?
            }
            "--readiness-period" => {
                options.config.readiness_period = parse_value(next, "--readiness-period")?
            }
            "--regression-budget" => {
                options.config.regression_budget = parse_value(next, "--regression-budget")?
            }
            "--help" | "-h" => {
                options.command = "help".to_string();
                consumed = 1;
            }
            other => return Err(format!("unknown option {other}")),
        }
        at += consumed;
    }
    if !(options.config.duty > 0.0 && options.config.duty <= 1.0) {
        return Err("--duty must be greater than 0 and at most 1".into());
    }
    if options.workers == 0 {
        return Err("--workers must be at least 1".into());
    }
    // Refused rather than reduced: an operator who asked for every core has to
    // be told the limit, not quietly given one fewer worker than they typed.
    let limit = pool::available();
    if options.workers > limit {
        return Err(format!(
            "--workers must be at most {limit}: max(1, cores - 1) on this machine, leaving a \
             core's worth of CAPACITY for whatever launched the trainer. Nothing is pinned to a \
             core, so this is a bound on how much work is in flight, not an affinity reservation"
        ));
    }
    if options.config.ticks <= 0 {
        return Err("--ticks must be positive".into());
    }
    if options.config.neat.population == 0 || options.config.sampler.panel == 0 {
        return Err("--population and --panel must be positive".into());
    }
    if options.config.audit.panel == 0 {
        return Err("--audit-panel must be positive".into());
    }
    // A negative magnitude would REWARD leaving the enemy untouched, which is
    // the opposite of what the flag means, so it is refused rather than
    // clamped into something the operator did not ask for.
    if !ScoringConfig::valid_penalty(options.config.scoring.no_damage_penalty) {
        return Err("--no-damage-penalty must be a finite magnitude of 0 or more; \
                    0 switches the penalty off"
            .into());
    }
    if options.config.broad.panel == 0 {
        return Err("--broad-panel must be positive".into());
    }
    // A pair count that is not a whole number of matchings could not give every
    // hull the same number of appearances, so the panel would not be balanced
    // and the aggregate it measures would not be the declared distribution.
    if options.config.broad.pairs == 0
        || options.config.broad.pairs % melee_sim::catalog::MELEE_SHIP_COUNT != 0
    {
        return Err("--overall-pairs must be a positive multiple of 25".into());
    }
    if !(options.config.broad.target > 0.0 && options.config.broad.target < 1.0) {
        return Err("--overall-target must be between 0 and 1".into());
    }
    if options.command == "broaden" {
        if options.from.is_none() {
            return Err("broaden needs --from <run id>".into());
        }
        if options.run.is_none() {
            return Err("broaden needs --run <new run id>".into());
        }
        if options.from == options.run {
            return Err("broaden needs a DIFFERENT --run; it never writes to --from".into());
        }
        // A fork inherits the source's scorer exactly. Accepting the flag here
        // and ignoring it would leave the operator believing a fork had been
        // rescored when its fitness numbers still mean the old thing.
        if options.given.iter().any(|flag| flag == "--fitness") {
            return Err(
                "broaden does not take --fitness: a fork inherits the source run's scorer, and \
                 fitness recorded under one scorer is not comparable with another. Start a new \
                 run to change what the population is ranked by"
                    .into(),
            );
        }
        // Same reason, for the same kind of number. A fork carries the source's
        // gate evidence and fitness history forward; re-gating or re-penalising
        // it mid-fork would leave the operator believing every stored success
        // count and score meant the new thing when they still mean the old one.
        if options.given.iter().any(|flag| flag == "--gate") {
            return Err(
                "broaden does not take --gate: a fork inherits the source run's gate criterion, \
                 and successes counted under one criterion are not the same measurement as \
                 successes counted under another. Start a new run to change what opens a gate"
                    .into(),
            );
        }
        if options.given.iter().any(|flag| flag == "--no-damage-penalty") {
            return Err(
                "broaden does not take --no-damage-penalty: a fork inherits the source run's \
                 penalty, and fitness recorded with one penalty is not comparable with fitness \
                 recorded under another. Start a new run to change it"
                    .into(),
            );
        }
        if options.allow_rebuild {
            return Err(
                "broaden does not take --allow-rebuild: it records the source evaluator as                  provenance, and the fingerprint guard still applies to resuming the new run"
                    .into(),
            );
        }
    }
    Ok(options)
}

/// How long the evaluator must rest after `worked` seconds of computing to
/// hold its long-run SCHEDULER-ACTIVE WALL FRACTION at `duty`: the share of
/// wall time in which the trainer is allowed to be computing at all.
///
/// Not a share of one core, and not a share of the machine. With one worker
/// the two happen to coincide, which is why a duty of 0.5 used to be described
/// as half a core; with a pool they do not, because the same active wall
/// fraction now covers as many cores as there are workers. The cap paces the
/// supervisor; the worker count decides how wide each paced interval is.
///
/// Pure so the arithmetic can be checked without waiting for a clock.
pub fn rest_owed(worked: Duration, duty: f64) -> Duration {
    if duty >= 1.0 {
        return Duration::ZERO;
    }
    worked.mul_f64((1.0 - duty) / duty)
}

/// How long one slice of governor rest lasts. Short enough that a pause or a
/// stop is acted on promptly, long enough that resting is not itself work.
const REST_SLICE: Duration = Duration::from_millis(200);

/// Ceiling on how often the status document is re-rendered when nothing the
/// dashboard must not miss has changed.
const PUBLISH_EVERY: Duration = Duration::from_secs(1);
/// Generations between checkpoints.
///
/// A checkpoint is the whole run: population, disabled genes, both random
/// streams, species, innovation book, sampler and gate evidence, tens of
/// megabytes of it. Writing that at every generation boundary spends most of a
/// generation's wall clock in the writer while the evaluation pool sits idle,
/// and buys back only the few generations a crash would cost. Every fifth
/// boundary, with [`SAVE_AT_LEAST_EVERY`] underneath it and an unconditional
/// save on the way out, bounds that loss without paying for it continuously.
const SAVE_EVERY_GENERATIONS: u32 = 5;
/// The safeguard under the generation cadence, unchanged: a slow generation
/// must not stretch the gap between checkpoints indefinitely.
const SAVE_AT_LEAST_EVERY: Duration = Duration::from_secs(60);

/// Options that belong to a RUN rather than to one session of it. Changing any
/// of them would change the trajectory, so a resume keeps the stored value and
/// says so instead of quietly obeying the command line.
const RUN_OWNED_FLAGS: [&str; 12] = [
    "--population",
    "--panel",
    "--ticks",
    "--rating",
    // What a run is ranked by cannot change mid-run: fitness is comparable
    // only within one scorer, so a resume would be comparing two things.
    "--fitness",
    // Nor what it is GATED on. Gate evidence, sampler statistics and the whole
    // history of success rates were all counted under one criterion; resuming
    // under another would pool two different measurements into one number.
    "--gate",
    // Nor the penalty, for the same reason as the scorer: it changes what
    // every fitness number already stored in the run means.
    "--no-damage-penalty",
    "--seed",
    "--audit-panel",
    "--audit-budget",
    "--readiness-games",
    "--readiness-threshold",
];

/// Set by the signal handler. The supervisor notices it at the next safe point
/// and shuts down through the ordinary checkpoint path.
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_signal(_signal: i32) {
    INTERRUPTED.store(true, Ordering::SeqCst);
}

fn install_signal_handlers() {
    // Safety: the handler only stores into an atomic, which is async-signal
    // safe; nothing else in this process reinstalls these dispositions.
    unsafe {
        libc::signal(libc::SIGINT, on_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGTERM, on_signal as *const () as libc::sighandler_t);
    }
}

fn apply_nice(increment: i32) {
    if increment == 0 {
        return;
    }
    // Safety: nice(3) only adjusts this process's scheduling priority.
    unsafe {
        libc::nice(increment);
    }
}

fn timestamp_id() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    trainer::iso8601(seconds)
        .replace([':', '-'], "")
        .replace('T', "-")
        .replace('Z', "")
}

fn salt_of(run_id: &str) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in run_id.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash | 1
}

pub fn run(arguments: &[String]) -> i32 {
    let options = match parse(arguments) {
        Ok(options) => options,
        Err(error) => {
            eprintln!("melee-mario: {error}\n\n{HELP}");
            return 2;
        }
    };
    match options.command.as_str() {
        "help" | "--help" | "-h" => {
            print!("{HELP}");
            0
        }
        "oracle" => {
            let mut out = io::BufWriter::new(io::stdout().lock());
            match crate::oracle::run(io::stdin().lock(), &mut out) {
                Ok(()) => 0,
                Err(error) => {
                    eprintln!("melee-mario oracle: {error}");
                    1
                }
            }
        }
        "bench" => bench(&options),
        "pause" => control(&options, "pause"),
        "resume-work" => control(&options, "resume"),
        "stop" => control(&options, "stop"),
        "status" => status(&options),
        "broaden" => match broaden(&options) {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("melee-mario: {error}");
                1
            }
        },
        "start" | "resume" | "serve" => match supervise(options) {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("melee-mario: {error}");
                1
            }
        },
        other => {
            eprintln!("melee-mario: unknown command {other}\n\n{HELP}");
            2
        }
    }
}

fn control(options: &Options, action: &str) -> i32 {
    match server::post_control(options.port, action) {
        Ok(answer) => {
            println!("{answer}");
            0
        }
        Err(error) => {
            eprintln!("melee-mario: no trainer answered on 127.0.0.1:{}: {error}", options.port);
            1
        }
    }
}

fn status(options: &Options) -> i32 {
    if let Ok(live) = server::get(options.port, "/api/status") {
        if !live.trim().is_empty() {
            println!("{live}");
            return 0;
        }
    }
    let Some(run_id) = options
        .run
        .clone()
        .or_else(|| store::runs(&options.root).into_iter().next())
    else {
        eprintln!("melee-mario: no run found under {}", options.root.display());
        return 1;
    };
    let dir = store::run_dir(&options.root, &run_id);
    match load(&dir) {
        Err(error) => {
            eprintln!("melee-mario: {error}");
            1
        }
        Ok(trainer) => {
            // No live trainer, so the numbers come from the last checkpoint and
            // the document says so rather than pretending to be current.
            let document = trainer.status(
                Phase::Stopped,
                "no trainer is running; this is the last checkpoint",
                &dir.join(store::CHECKPOINT).display().to_string(),
                true,
            );
            println!("{document}");
            0
        }
    }
}

/// Forks a stopped run into a new any-versus-any run.
///
/// The ordering is the whole safety argument:
///
///   1. A SHARED lock on the source, which fails outright while a trainer is
///      writing it and writes nothing itself, so the copy can never be of a
///      half-written checkpoint and the source is left byte for byte as found.
///   2. An EXCLUSIVE lock on the destination, so two forks cannot race into the
///      same new run.
///   3. A refusal if the destination already has a checkpoint. A fork never
///      overwrites a run; the operator picks another identifier.
///   4. The transition, then an atomic write of the new configuration and
///      checkpoint. Nothing is ever written to the source directory.
///
/// This is the ONE place a differing evaluator fingerprint is accepted, and it
/// is accepted by recording it rather than by waving it through: the new
/// checkpoint belongs to this binary, the old fingerprint is kept as origin
/// provenance, and an ordinary resume of the new run still enforces the guard.
fn broaden(options: &Options) -> Result<(), String> {
    let source_id = options.from.clone().ok_or("broaden needs --from")?;
    let target_id = options.run.clone().ok_or("broaden needs --run")?;
    let source_dir = store::run_dir(&options.root, &source_id);
    let target_dir = store::run_dir(&options.root, &target_id);
    if !source_dir.join(store::CHECKPOINT).exists() {
        return Err(format!(
            "no checkpoint at {}",
            source_dir.join(store::CHECKPOINT).display()
        ));
    }

    let _reading = RunLock::acquire_shared(&source_dir).map_err(|e| e.to_string())?;
    let _writing = RunLock::acquire(&target_dir).map_err(|e| e.to_string())?;
    let checkpoint = target_dir.join(store::CHECKPOINT);
    if checkpoint.exists() {
        return Err(format!(
            "{} already exists. broaden never overwrites a run; choose another --run",
            checkpoint.display()
        ));
    }

    let mut trainer = load(&source_dir)?;
    let source_evaluator = trainer.evaluator.clone();
    let source_generation = trainer.population.generation;
    let source_episodes = trainer.episodes;
    let source_champion = trainer.champion.as_ref().map(|g| g.fingerprint());

    // Settings that describe broad mode itself come from this command line;
    // everything else about the run is inherited exactly.
    trainer.config.broad = options.config.broad;
    // A balanced readiness probe is much wider than a one-cell ladder probe, so
    // it gets a wider default. An explicit flag still wins.
    if options.given.iter().any(|flag| flag == "--readiness-games") {
        trainer.config.readiness_games = options.config.readiness_games;
    } else {
        trainer.config.readiness_games = 250;
    }
    if options.given.iter().any(|flag| flag == "--readiness-period") {
        trainer.config.readiness_period = options.config.readiness_period;
    }
    if options.given.iter().any(|flag| flag == "--duty") {
        trainer.config.duty = options.config.duty;
    }

    // Broad mode's aggregate is defined against the Awesome cyborg, so a source
    // graded against a weaker one may only be forked if the operator says so
    // explicitly with --rating awesome. The change is recorded; it is never
    // made quietly, because it changes what every number afterwards means.
    if options.given.iter().any(|flag| flag == "--rating") {
        if trainer.config.rating != options.config.rating {
            trainer.note(format!(
                "graded opponent changed at the transition: {} became {}",
                trainer::rating_name(trainer.config.rating),
                trainer::rating_name(options.config.rating)
            ));
            trainer.config.rating = options.config.rating;
        }
    }

    let reason = options
        .reason
        .clone()
        .unwrap_or_else(|| "operator requested any-versus-any".to_string());
    trainer.broaden(&target_id, &reason)?;

    // The checkpoint goes down last, so a crash between the two leaves a
    // directory with no resumable run rather than one with a checkpoint whose
    // configuration is missing.
    store::write_atomic(&target_dir.join(store::CONFIG), &trainer.config.to_json())
        .map_err(|e| e.to_string())?;
    trainer.saved_at = Some(now_iso8601());
    trainer.saved_generation = Some(trainer.population.generation);
    let document = trainer.to_json();
    // The written document has to decode back into a resumable run, or the fork
    // has produced something the operator cannot actually use.
    Trainer::from_json(&document)
        .map_err(|e| format!("the forked checkpoint would not decode: {e}"))?;
    store::write_atomic(&checkpoint, &document).map_err(|e| e.to_string())?;
    if let Some(event) = trainer.events.back() {
        let _ = store::append_line(
            &target_dir.join(store::EVENTS),
            &serde_json::json!({"at": event.at, "message": event.message,
                                "generation": trainer.population.generation,
                                "episodes": trainer.episodes}),
        );
    }

    println!(
        "melee-mario: forked {source_id} generation {source_generation} ({source_episodes} \
         episodes, evaluator {source_evaluator}) into {target_id}.\n  \
         champion {} carried across; {} genome(s) in {} species keep their weights, mutation \
         rates and RNG state.\n  \
         scope is now any-versus-any: all {} ordered Awesome cyborg matchups active, NOTHING \
         mastered, all previous gate evidence and fitness discarded.\n  \
         training panel {} fights per genome, {:.0}% balanced rotation; overall gate {} games \
         per round against a {:.0}% target.\n  \
         a baseline readiness probe of {} balanced games is armed and will run first.\n  \
         {} was not modified. Resume the new run with:\n    \
         melee-mario resume --run {target_id}",
        source_champion.unwrap_or_else(|| "none".into()),
        trainer.population.size(),
        trainer.population.species.len(),
        crate::curriculum::cells(trainer.stage).len(),
        trainer.config.broad.panel,
        trainer.config.broad.coverage * 100.0,
        trainer.config.broad.games(),
        trainer.config.broad.target * 100.0,
        trainer.config.readiness_games,
        source_dir.display(),
    );
    let _ = io::stdout().flush();
    Ok(())
}

fn load(dir: &Path) -> Result<Trainer, String> {
    let raw = store::read_json(&dir.join(store::CHECKPOINT))
        .map_err(|e| format!("cannot read {}: {e}", dir.display()))?;
    Trainer::from_json(&raw)
}

fn bench(options: &Options) -> i32 {
    use crate::curriculum::{cells, Cell};
    use crate::episode::{self, Rival, Task};
    use crate::graph::Network;
    use crate::neat::{Individual, Innovations, MutationRates};
    use crate::rng::Stream;
    use std::sync::Arc;

    let mut rng = Stream::seeded(options.seed.unwrap_or(1));
    let mut book = Innovations::new();
    let mut individual = Individual::seed(&mut rng, MutationRates::default(), &mut book, 0.9);
    for _ in 0..40 {
        individual.mutate(&mut rng, &mut book, 0.9);
    }
    let network = Arc::new(Network::compile(&individual.genome));
    let cell: Cell = cells(0)[0];
    let started = Instant::now();
    let games = 40;
    let mut ticks = 0i64;
    for index in 0..games {
        let task = Task {
            cell,
            swap: index % 2 == 1,
            seed: 1 + index as i64 * 7919,
            ticks: options.config.ticks,
        };
        ticks += episode::run(&task, &network, Rival::Cyborg(options.config.rating)).ticks;
    }
    let elapsed = started.elapsed().as_secs_f64();
    println!(
        "{games} fights in {elapsed:.2}s = {:.1} fights/s ({:.0} display ticks each, \
         {} nodes / {} links)",
        games as f64 / elapsed,
        ticks as f64 / games as f64,
        individual.genome.nodes.len(),
        individual.genome.enabled_count()
    );
    0
}

/// Owns the run directory, the trainer thread's work loop and the server.
fn supervise(options: Options) -> Result<(), String> {
    install_signal_handlers();
    apply_nice(options.nice);

    let serve_only = options.command == "serve";
    let starting = options.command == "start";
    let run_id = match (&options.run, starting) {
        (Some(id), _) => id.clone(),
        (None, true) => timestamp_id(),
        (None, false) => store::runs(&options.root)
            .into_iter()
            .next()
            .ok_or_else(|| format!("no run found under {}", options.root.display()))?,
    };
    let dir = store::run_dir(&options.root, &run_id);
    let checkpoint = dir.join(store::CHECKPOINT);

    // Claimed BEFORE anything in the directory is read or written, so two
    // resumes racing each other cannot both decide the run is free and then
    // both write the checkpoint.
    let _lock = if serve_only {
        None
    } else {
        Some(RunLock::acquire(&dir).map_err(|e| e.to_string())?)
    };

    let mut trainer = if starting {
        if checkpoint.exists() {
            return Err(format!(
                "{} already exists; use resume, or start with a different --run",
                checkpoint.display()
            ));
        }
        let mut config = options.config.clone();
        config.run_id = run_id.clone();
        config.salt = options.seed.unwrap_or_else(|| salt_of(&run_id));
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        store::write_atomic(&dir.join(store::CONFIG), &config.to_json())
            .map_err(|e| e.to_string())?;
        Trainer::fresh(config)
    } else {
        let mut restored = load(&dir)?;
        // The run's own configuration is authoritative from here on, so the
        // governor and the dashboard read the same number. The one exception
        // is an explicit --duty, which is a pure resource knob that cannot
        // change the trajectory; it is written into the run so that what the
        // process does and what the dashboard says stay the same thing.
        if options.given.iter().any(|flag| flag == "--duty") {
            if restored.config.duty != options.config.duty {
                restored.note(format!(
                    "duty cap changed for this session: {:.2} became {:.2}",
                    restored.config.duty, options.config.duty
                ));
            }
            restored.config.duty = options.config.duty;
        }
        let overridden: Vec<&String> = options
            .given
            .iter()
            .filter(|flag| RUN_OWNED_FLAGS.contains(&flag.as_str()))
            .collect();
        if !overridden.is_empty() {
            eprintln!(
                "melee-mario: {overridden:?} describe the run, not the session, so the values \
                 stored in {} are being used instead. Start a new run to change them.",
                checkpoint.display()
            );
        }
        let current = trainer::build_fingerprint();
        if restored.evaluator != current {
            if !options.allow_rebuild {
                return Err(format!(
                    "this run was trained by evaluator {} but this binary is {current}. A rebuilt \
                     evaluator can change results, so resuming would not continue the same \
                     trajectory. Pass --allow-rebuild to continue anyway.",
                    restored.evaluator
                ));
            }
            restored.note(format!(
                "resumed with a different evaluator: {} became {current}",
                restored.evaluator
            ));
            restored.evaluator = current;
        }
        restored
    };

    trainer.nice = options.nice;
    // Applied AFTER the fingerprint guard above, and deliberately not subject
    // to it: the worker count is a resource knob like `nice`, not part of the
    // trajectory, so a run started on one worker may be resumed on nine and
    // back again without any of the state it reaches differing.
    trainer.use_workers(pool::clamp(options.workers));
    let shared = Shared::new(server::asset_dir(&options.root));
    let listener = if options.serve {
        match server::bind(options.port) {
            Ok(listener) => {
                shared.set_port(listener.local_addr().map(|a| a.port()).unwrap_or(options.port));
                let clone = shared.clone();
                std::thread::spawn(move || server::serve(listener, clone));
                println!(
                    "melee-mario: dashboard on http://127.0.0.1:{} for run {run_id}",
                    options.port
                );
                true
            }
            Err(error) => {
                eprintln!(
                    "melee-mario: could not listen on 127.0.0.1:{}: {error}",
                    options.port
                );
                false
            }
        }
    } else {
        false
    };
    let _ = listener;

    let path = checkpoint.display().to_string();
    let publish = |trainer: &Trainer, phase: Phase, message: &str, stale: bool| {
        shared.publish(
            &trainer.status(phase, message, &path, stale),
            &trainer.network(),
        );
    };
    let publish_status = |trainer: &Trainer, phase: Phase, message: &str| {
        shared.publish_status(&trainer.status(phase, message, &path, false));
    };

    if serve_only {
        publish(
            &trainer,
            Phase::Stopped,
            "serving the last checkpoint; no trainer is running",
            true,
        );
        println!("melee-mario: serving checkpoint only. Press Ctrl-C to exit.");
        while !INTERRUPTED.load(Ordering::SeqCst) && shared.control() != Control::Stop {
            std::thread::sleep(Duration::from_millis(250));
        }
        return Ok(());
    }

    publish(&trainer, Phase::Initializing, "starting up", false);

    // A fresh run has nothing on disk yet, and the first cadence save is five
    // generations away, so it goes down once here: a crash in the first few
    // minutes of a run must still leave a run to resume.
    if trainer.saved_generation.is_none() {
        save(&mut trainer, &dir)?;
    }

    let started = Instant::now();
    let started_episodes = trainer.episodes;
    let started_generation = trainer.population.generation;
    let mut last_save = Instant::now();
    // Publishing means serialising the whole status document, which is not free
    // at 625 matchups. It happens at most once a second unless something the
    // dashboard must not miss actually changed.
    let mut last_publish = Instant::now();
    let mut shown_phase = Phase::Initializing;
    let mut shown_champion = String::new();
    let reason;

    loop {
        if INTERRUPTED.load(Ordering::SeqCst) {
            reason = "interrupted; stopping at a safe boundary".into();
            break;
        }
        match shared.control() {
            Control::Stop => {
                reason = "stop requested through the dashboard".into();
                break;
            }
            Control::Pause => {
                if shown_phase != Phase::Paused || last_publish.elapsed() >= PUBLISH_EVERY {
                    publish(&trainer, Phase::Paused, "paused by request", false);
                    shown_phase = Phase::Paused;
                    last_publish = Instant::now();
                }
                // The server keeps answering while this loop idles.
                std::thread::sleep(REST_SLICE);
                continue;
            }
            Control::Run => {}
        }
        if let Some(limit) = options.generations {
            if trainer.population.generation - started_generation >= limit {
                reason = format!("reached the {limit} generation budget");
                break;
            }
        }
        if let Some(limit) = options.episodes {
            if trainer.episodes - started_episodes >= limit {
                reason = format!("reached the {limit} episode budget");
                break;
            }
        }
        if let Some(limit) = options.minutes {
            if started.elapsed().as_secs_f64() >= limit * 60.0 {
                reason = format!("reached the {limit} minute budget");
                break;
            }
        }

        // Everything from here to the rest below is work this process is doing
        // and therefore work the duty cap must pay for: simulating, rendering
        // the status document and writing the checkpoint alike. Measuring only
        // the simulation would let a fast panel with an expensive publish blow
        // straight through the cap.
        let began = Instant::now();
        let unit = trainer.step();

        let phase = match trainer.phase() {
            "auditing" => Phase::Auditing,
            _ => Phase::Training,
        };
        let champion = trainer
            .champion
            .as_ref()
            .map(|g| g.fingerprint())
            .unwrap_or_default();
        if champion != shown_champion {
            // The genome changed, so the network document has to change too.
            publish(&trainer, phase, "training", false);
            shown_champion = champion;
            shown_phase = phase;
            last_publish = Instant::now();
        } else if phase != shown_phase || last_publish.elapsed() >= PUBLISH_EVERY {
            publish_status(&trainer, phase, "training");
            shown_phase = phase;
            last_publish = Instant::now();
        }

        if save_due(
            unit.boundary,
            trainer.population.generation,
            trainer.saved_generation,
            last_save.elapsed(),
        ) {
            save(&mut trainer, &dir)?;
            last_save = Instant::now();
        }

        let worked = began.elapsed();
        trainer.compute += worked.as_secs_f64();

        // The governor. Resting for `worked * (1 - duty) / duty` holds the
        // long-run scheduler-active wall fraction at `duty`, whatever the pool
        // is doing during it. The whole debt is paid, never
        // truncated, because truncating it is exactly how a heavy graph or a
        // long audit would creep past the cap; it is paid in short slices so a
        // pause, a stop or a signal is still noticed promptly.
        // One authoritative duty: the same field the status document reports.
        let mut owed = rest_owed(worked, trainer.config.duty);
        while owed > Duration::ZERO {
            let slice = owed.min(REST_SLICE);
            std::thread::sleep(slice);
            owed -= slice;
            if INTERRUPTED.load(Ordering::SeqCst) || shared.control() == Control::Stop {
                break;
            }
        }
        // Elapsed counts the whole iteration, so episodes_per_second is real
        // throughput and compute / elapsed is the duty actually achieved.
        trainer.elapsed += began.elapsed().as_secs_f64();
    }

    save(&mut trainer, &dir)?;
    publish(&trainer, Phase::Stopped, &reason, false);
    println!(
        "melee-mario: {reason}. generation {}, {} episodes, checkpoint {}",
        trainer.population.generation,
        trainer.episodes,
        checkpoint.display()
    );
    let _ = io::stdout().flush();
    Ok(())
}

/// Whether this iteration has to write a checkpoint.
///
/// Only at a generation boundary, and only once the run has moved
/// [`SAVE_EVERY_GENERATIONS`] past the generation actually on disk, so the
/// cadence is measured against the last SUCCESSFUL save rather than against a
/// counter that a failed write would have advanced anyway. The elapsed
/// safeguard fires on its own terms, whatever the boundary is doing.
fn save_due(boundary: bool, generation: u32, saved: Option<u32>, since: Duration) -> bool {
    let behind = generation.saturating_sub(saved.unwrap_or(0));
    (boundary && behind >= SAVE_EVERY_GENERATIONS) || since >= SAVE_AT_LEAST_EVERY
}

fn now_iso8601() -> String {
    trainer::iso8601(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0),
    )
}

fn save(trainer: &mut Trainer, dir: &Path) -> Result<(), String> {
    // The stamp is STAGED into the document and only committed to the trainer
    // once the write has actually landed. A failed save that had already moved
    // `saved_at` and `saved_generation` forward would leave the dashboard
    // claiming a checkpoint that is not on disk.
    let staged_at = now_iso8601();
    let staged_generation = trainer.population.generation;
    let previous = (trainer.saved_at.clone(), trainer.saved_generation);
    trainer.saved_at = Some(staged_at);
    let document: Value = trainer.to_json();
    if let Err(error) = store::write_atomic(&dir.join(store::CHECKPOINT), &document) {
        (trainer.saved_at, trainer.saved_generation) = previous;
        return Err(error.to_string());
    }
    trainer.saved_generation = Some(staged_generation);
    if let Some(event) = trainer.events.back() {
        let _ = store::append_line(
            &dir.join(store::EVENTS),
            &serde_json::json!({"at": event.at, "message": event.message,
                                "generation": trainer.population.generation,
                                "episodes": trainer.episodes}),
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(raw: &[&str]) -> Vec<String> {
        raw.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn options_parse_and_reject_impossible_resource_settings() {
        let options = parse(&args(&[
            "start",
            "--population",
            "50",
            "--panel",
            "4",
            "--duty",
            "0.25",
            "--ticks",
            "7200",
            "--rating",
            "good",
        ]))
        .unwrap();
        assert_eq!(options.config.neat.population, 50);
        assert_eq!(options.config.sampler.panel, 4);
        assert_eq!(options.config.duty, 0.25);
        assert_eq!(options.config.ticks, 7200);
        assert_eq!(options.port, server::DEFAULT_PORT);

        assert!(parse(&args(&["start", "--duty", "0"])).is_err());
        assert!(parse(&args(&["start", "--duty", "1.5"])).is_err());
        assert!(parse(&args(&["start", "--ticks", "0"])).is_err());
        assert!(parse(&args(&["start", "--population", "0"])).is_err());
        assert!(parse(&args(&["start", "--rating", "godlike"])).is_err());
        assert!(parse(&args(&["start", "--nonsense"])).is_err());
    }

    #[test]
    fn a_checkpoint_is_due_every_fifth_generation_or_every_minute() {
        let quick = Duration::from_secs(1);
        // Mid-generation work never saves, however far ahead the run is.
        assert!(!save_due(false, 40, Some(0), quick));
        // Nor does a boundary that is only a generation or four past disk.
        for generation in 1..SAVE_EVERY_GENERATIONS {
            assert!(!save_due(true, generation, Some(0), quick), "{generation}");
        }
        assert!(save_due(true, SAVE_EVERY_GENERATIONS, Some(0), quick));
        assert!(save_due(true, 327, Some(322), quick));
        assert!(!save_due(true, 326, Some(322), quick));
        // A run that has never saved counts from zero, so a fresh start's
        // first five generations still go down.
        assert!(save_due(true, 5, None, quick));
        // And the safeguard stands on its own, boundary or not.
        assert!(save_due(false, 1, Some(0), SAVE_AT_LEAST_EVERY));
    }

    #[test]
    fn the_scorer_defaults_to_combat_and_rejects_anything_it_does_not_implement() {
        // Typing nothing must leave every existing run's meaning alone.
        assert_eq!(
            parse(&args(&["start"])).unwrap().config.scoring,
            ScoringConfig::default()
        );
        assert_eq!(
            parse(&args(&["start", "--fitness", "crew-ratio"]))
                .unwrap()
                .config
                .scoring,
            ScoringConfig::of(Scoring::CrewRatio)
        );
        assert_eq!(
            parse(&args(&["start", "--fitness", "combat"]))
                .unwrap()
                .config
                .scoring,
            ScoringConfig::default()
        );
        for bad in ["crew_ratio", "ratio", "crew", "kills", ""] {
            assert!(parse(&args(&["start", "--fitness", bad])).is_err(), "{bad}");
        }
        assert!(parse(&args(&["start", "--fitness"])).is_err());

        // It describes the run, not the session, so a resume reports it as
        // stored rather than obeying it.
        assert!(RUN_OWNED_FLAGS.contains(&"--fitness"));

        // And a fork inherits it rather than pretending to rescore.
        assert!(parse(&args(&[
            "broaden",
            "--from",
            "a",
            "--run",
            "b",
            "--fitness",
            "crew-ratio"
        ]))
        .is_err());
        assert!(parse(&args(&["broaden", "--from", "a", "--run", "b"])).is_ok());
    }

    #[test]
    fn the_help_text_documents_every_command_and_the_loopback_rule() {
        for command in [
            "start", "resume", "status", "pause", "stop", "serve", "oracle", "bench",
        ] {
            assert!(HELP.contains(command), "help omits {command}");
        }
        assert!(HELP.contains("127.0.0.1"));
        assert!(HELP.contains("/api/status"));
        assert!(HELP.contains("/api/network"));
        assert!(HELP.contains("/api/control"));
        // The scorer changes what every fitness number in the run means, so
        // the help has to name both choices and say which is the default.
        assert!(HELP.contains("--fitness"));
        assert!(HELP.contains(Scoring::Combat.as_str()));
        assert!(HELP.contains(Scoring::CrewRatio.as_str()));
        // So does the gate criterion, which changes what every SUCCESS number
        // in the run means, and the penalty.
        assert!(HELP.contains("--gate"));
        assert!(HELP.contains(GateCriterion::CombatWins.as_str()));
        assert!(HELP.contains(GateCriterion::CrewLead.as_str()));
        assert!(HELP.contains("--no-damage-penalty"));
    }

    #[test]
    fn the_gate_defaults_to_combat_wins_and_rejects_anything_it_does_not_implement() {
        // Typing nothing must leave every existing run's meaning alone.
        assert_eq!(
            parse(&args(&["start"])).unwrap().config.scoring.gate,
            GateCriterion::CombatWins
        );
        assert_eq!(
            parse(&args(&["start", "--gate", "crew-lead"]))
                .unwrap()
                .config
                .scoring
                .gate,
            GateCriterion::CrewLead
        );
        // And it is genuinely independent of the scorer, in both directions.
        let crossed = parse(&args(&["start", "--fitness", "combat", "--gate", "crew-lead"]))
            .unwrap()
            .config
            .scoring;
        assert_eq!(crossed.fitness, Scoring::Combat);
        assert_eq!(crossed.gate, GateCriterion::CrewLead);

        for bad in ["crew_lead", "crew", "lead", "wins", "combat", ""] {
            assert!(parse(&args(&["start", "--gate", bad])).is_err(), "{bad}");
        }
        assert!(parse(&args(&["start", "--gate"])).is_err());

        // It describes the run, not the session, so a resume reports it as
        // stored rather than obeying it, and a fork inherits it.
        assert!(RUN_OWNED_FLAGS.contains(&"--gate"));
        assert!(parse(&args(&[
            "broaden", "--from", "a", "--run", "b", "--gate", "crew-lead"
        ]))
        .is_err());
    }

    #[test]
    fn the_penalty_defaults_to_off_and_refuses_a_magnitude_it_cannot_honour() {
        assert_eq!(
            parse(&args(&["start"]))
                .unwrap()
                .config
                .scoring
                .no_damage_penalty,
            0.0
        );
        assert!(!parse(&args(&["start"]))
            .unwrap()
            .config
            .scoring
            .penalises_no_damage());
        let armed = parse(&args(&["start", "--no-damage-penalty", "1000"]))
            .unwrap()
            .config
            .scoring;
        assert_eq!(armed.no_damage_penalty, 1000.0);
        assert!(armed.penalises_no_damage());
        // Explicit zero is the same as absent: off, not a penalty of nothing.
        let zero = parse(&args(&["start", "--no-damage-penalty", "0"]))
            .unwrap()
            .config
            .scoring;
        assert_eq!(zero, ScoringConfig::default());

        // A negative magnitude would REWARD leaving the enemy untouched, and
        // an unbounded one would overflow a summed panel.
        for bad in ["-1", "-1000", "1e308", "inf", "nan", "lots", ""] {
            assert!(
                parse(&args(&["start", "--no-damage-penalty", bad])).is_err(),
                "{bad}"
            );
        }
        assert!(parse(&args(&["start", "--no-damage-penalty"])).is_err());

        assert!(RUN_OWNED_FLAGS.contains(&"--no-damage-penalty"));
        assert!(parse(&args(&[
            "broaden",
            "--from",
            "a",
            "--run",
            "b",
            "--no-damage-penalty",
            "1000"
        ]))
        .is_err());
    }

    #[test]
    fn the_staged_run_the_operator_asked_for_parses_into_exactly_those_settings() {
        // The combination the fresh staged run is launched with. If this ever
        // stops meaning what it says, the run is training on something else.
        let parsed = parse(&args(&[
            "start",
            "--fitness",
            "crew-ratio",
            "--gate",
            "crew-lead",
            "--no-damage-penalty",
            "1000",
        ]))
        .unwrap()
        .config
        .scoring;
        assert_eq!(
            parsed,
            ScoringConfig {
                fitness: Scoring::CrewRatio,
                gate: GateCriterion::CrewLead,
                no_damage_penalty: 1000.0,
            }
        );
        // And it survives a round trip through the run's own configuration.
        assert_eq!(
            ScoringConfig::from_json(Some(&parsed.to_json())),
            Some(parsed)
        );
    }

    #[test]
    fn the_governor_pays_the_whole_debt_for_any_duty() {
        let work = Duration::from_millis(100);
        assert_eq!(rest_owed(work, 1.0), Duration::ZERO);
        assert_eq!(rest_owed(work, 0.5), work);
        assert_eq!(rest_owed(work, 0.25), work * 3);
        assert_eq!(rest_owed(work, 0.1), work * 9);
        assert_eq!(rest_owed(Duration::ZERO, 0.5), Duration::ZERO);
        // A long unit owes a long rest; nothing truncates it, because a cap
        // that stops applying to expensive work is not a cap.
        let heavy = Duration::from_secs(30);
        assert_eq!(rest_owed(heavy, 0.5), heavy);
        assert_eq!(rest_owed(heavy, 0.2), heavy * 4);
        // And the debt is paid in slices small enough to notice a stop.
        assert!(REST_SLICE <= Duration::from_millis(200));
        let slices = rest_owed(heavy, 0.2).as_millis() / REST_SLICE.as_millis();
        assert!(slices > 100, "a long rest must still be interruptible");
    }

    #[test]
    fn run_identifiers_produce_stable_non_zero_salts() {
        assert_eq!(salt_of("run-a"), salt_of("run-a"));
        assert_ne!(salt_of("run-a"), salt_of("run-b"));
        assert!(salt_of("") != 0);
    }
}
