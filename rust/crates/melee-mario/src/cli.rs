//! Command line, run supervision and the duty-cycle governor.
//!
//! The governor is the reason this can run on a laptop that is also being used
//! for something else. One evaluator thread, niced down, and after every unit
//! of work the supervisor sleeps for as long as that work took, scaled by the
//! duty fraction. That cap covers training, readiness probing, auditing and
//! the mixed self-play phase alike, because every one of them is just another
//! unit of work in the same loop.

use crate::audit::AuditConfig;
use crate::episode::DEFAULT_TICKS;
use crate::neat::NeatConfig;
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
                           trajectory silently.

BUDGET OPTIONS (a bounded local run stops on whichever arrives first)
  --generations <n>        Stop after this many completed generations.
  --episodes <n>           Stop after this many simulated fights.
  --minutes <n>            Stop after this much wall time.

RESOURCE OPTIONS
  --duty <0..1>            Fraction of wall time the evaluator may compute.
                           Default 0.5, which is one half of one core.
  --nice <n>               Scheduling penalty applied to this process.
                           Default 10. Use 0 to leave the priority alone.

TRAINING OPTIONS
  --population <n>         Genomes per generation. Default 300.
  --panel <n>              Fights each genome plays per generation. Default 8.
  --ticks <n>              Display ticks a fight may take. Default 3600, which
                           is one minute of melee. A timeout is never a win.
  --rating <name>          standard, good or awesome. Default awesome.
  --audit-panel <n>        Fights per matchup per audit round. Default 100.
  --audit-budget <n>       Fights one audit attempt may spend. Default 200000.
  --readiness-games <n>    Fights in the cheap probe that decides whether an
                           audit is worth opening. Default 128.
  --readiness-threshold <r>  Probe win rate needed to open an audit. Default 0.85.
  --readiness-period <n>   Probe every n generations. Default 5.

NOTES
  The server binds 127.0.0.1 only and serves GET /api/status, GET /api/network,
  POST /api/control {\"action\":\"pause\"|\"resume\"|\"stop\"}, GET / and
  GET /dashboard.js from scripts/mario. There is no option that exposes it.

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
    pub seed: Option<u64>,
    pub port: u16,
    pub serve: bool,
    pub nice: i32,
    pub generations: Option<u32>,
    pub episodes: Option<u64>,
    pub minutes: Option<f64>,
    pub allow_rebuild: bool,
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
        seed: None,
        port: server::DEFAULT_PORT,
        serve: true,
        nice: 10,
        generations: None,
        episodes: None,
        minutes: None,
        allow_rebuild: false,
        config: Config {
            run_id: String::new(),
            salt: 0,
            ticks: DEFAULT_TICKS,
            rating: melee_sim::input::CyborgRating::AwesomeCyborg,
            neat: NeatConfig::default(),
            sampler: SamplerConfig::default(),
            audit: AuditConfig::default(),
            duty: 0.5,
            readiness_games: 128,
            readiness_threshold: 0.85,
            readiness_period: 5,
        },
    };
    let mut at = 1;
    while at < arguments.len() {
        let flag = arguments[at].as_str();
        let next = arguments.get(at + 1);
        let mut consumed = 2;
        match flag {
            "--root" => {
                options.root = PathBuf::from(next.ok_or("--root needs a path")?);
            }
            "--run" => options.run = Some(next.ok_or("--run needs an id")?.clone()),
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
            "--population" => options.config.neat.population = parse_value(next, "--population")?,
            "--panel" => options.config.sampler.panel = parse_value(next, "--panel")?,
            "--ticks" => options.config.ticks = parse_value(next, "--ticks")?,
            "--rating" => {
                options.config.rating = trainer::parse_rating(next.ok_or("--rating needs a name")?)
                    .ok_or("--rating must be standard, good or awesome")?;
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
    if options.config.ticks <= 0 {
        return Err("--ticks must be positive".into());
    }
    if options.config.neat.population == 0 || options.config.sampler.panel == 0 {
        return Err("--population and --panel must be positive".into());
    }
    if options.config.audit.panel == 0 {
        return Err("--audit-panel must be positive".into());
    }
    Ok(options)
}

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

    let shared = Shared::new(server::asset_dir(&options.root));
    let listener = if options.serve {
        match server::bind(options.port) {
            Ok(listener) => {
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

    let publish = |trainer: &Trainer, phase: Phase, message: &str, stale: bool| {
        shared.publish(
            &trainer.status(phase, message, &checkpoint.display().to_string(), stale),
            &trainer.network(),
        );
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

    let _lock = RunLock::acquire(&dir).map_err(|e| e.to_string())?;
    publish(&trainer, Phase::Initializing, "starting up", false);

    let started = Instant::now();
    let started_episodes = trainer.episodes;
    let started_generation = trainer.population.generation;
    let mut last_save = Instant::now();
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
                publish(&trainer, Phase::Paused, "paused by request", false);
                // The server keeps answering while this loop idles.
                std::thread::sleep(Duration::from_millis(200));
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

        let began = Instant::now();
        let unit = trainer.step();
        let worked = began.elapsed();
        trainer.compute += worked.as_secs_f64();

        let phase = match trainer.phase() {
            "auditing" => Phase::Auditing,
            _ => Phase::Training,
        };
        publish(&trainer, phase, "training", false);

        if unit.boundary || last_save.elapsed() >= Duration::from_secs(60) {
            save(&mut trainer, &dir)?;
            last_save = Instant::now();
            publish(&trainer, phase, "training", false);
        }

        // The governor. Sleeping for `worked * (1 - duty) / duty` holds the
        // long-run share of one core at `duty`, whatever the unit was doing.
        let rest = worked.mul_f64((1.0 - options.config.duty) / options.config.duty);
        if rest > Duration::ZERO {
            std::thread::sleep(rest.min(Duration::from_secs(5)));
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

fn save(trainer: &mut Trainer, dir: &Path) -> Result<(), String> {
    trainer.saved_at = Some(trainer::iso8601(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0),
    ));
    let document: Value = trainer.to_json();
    store::write_atomic(&dir.join(store::CHECKPOINT), &document).map_err(|e| e.to_string())?;
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
    }

    #[test]
    fn run_identifiers_produce_stable_non_zero_salts() {
        assert_eq!(salt_of("run-a"), salt_of("run-a"));
        assert_ne!(salt_of("run-a"), salt_of("run-b"));
        assert!(salt_of("") != 0);
    }
}
