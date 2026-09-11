#!/usr/bin/env node
//
// Read-only watcher for the melee-mario trainer.
//
// It polls the trainer's local status endpoint, appends one compact NDJSON
// snapshot per poll to a file you name, and says something out loud when the
// run's state changes or stops making progress.
//
// It does not control anything. There is no restart, no retune, no pause, no
// resume, no config write and no request other than a GET against a loopback
// address. If the trainer is wedged, this tells you; fixing it is yours.
//
// Usage:
//   node scripts/mario/watch.mjs --out artifacts/mario/watch.ndjson
//
// Options:
//   --out PATH            NDJSON output path. Required. Appended to, never
//                         truncated, so a restarted watcher keeps the history.
//   --url URL             Trainer base URL. Default http://127.0.0.1:8788
//                         Must be a loopback host; anything else is refused.
//   --interval SECONDS    Poll period. Default 60.
//   --timeout SECONDS     Per-request timeout. Default 10.
//   --summary SECONDS     Stdout summary period. Default 300 (5 minutes).
//   --stall SECONDS       Episode-progress and checkpoint-age alarm threshold
//                         while the trainer says it is working. Default 300.
//   --run RUN_ID          Expect this run id. A different one is an alert
//                         rather than something quietly accepted.
//   --pid PID             Also sample this process's memory and CPU, and check
//                         that its command line really is the expected run.
//   --lead-surface ID     cmux surface to wake on a meaningful alert only.
//                         Rate limited per alert kind (see --alert-cooldown).
//   --notify-surface ID   cmux surface to post passive notifications to.
//   --alert-cooldown SEC  Minimum gap between repeats of the same alert kind
//                         to the lead. Default 900.
//   --once                Poll once, write one line, print the summary, exit.
//   --quiet               Only print alerts and summaries, not every poll.
//
// Exit codes: 0 normal, 2 bad arguments.

import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { execFile } from "node:child_process";

// ---------------------------------------------------------------- arguments

const DEFAULTS = {
  url: "http://127.0.0.1:8788",
  interval: 60,
  timeout: 10,
  summary: 300,
  stall: 300,
  alertCooldown: 900,
};

const FLAGS = new Set(["--once", "--quiet", "-h", "--help"]);

function parseArgs(argv) {
  const out = { ...DEFAULTS, once: false, quiet: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "-h" || arg === "--help") {
      out.help = true;
      continue;
    }
    if (arg === "--once") {
      out.once = true;
      continue;
    }
    if (arg === "--quiet") {
      out.quiet = true;
      continue;
    }
    if (!arg.startsWith("--")) {
      return { error: `unexpected argument '${arg}'` };
    }
    const value = argv[i + 1];
    if (value === undefined || (value.startsWith("--") && FLAGS.has(value))) {
      return { error: `${arg} needs a value` };
    }
    i += 1;
    switch (arg) {
      case "--out":
        out.out = value;
        break;
      case "--url":
        out.url = value.replace(/\/+$/, "");
        break;
      case "--run":
        out.run = value;
        break;
      case "--pid":
        out.pid = Number(value);
        if (!Number.isInteger(out.pid) || out.pid <= 0) {
          return { error: `--pid must be a positive integer, got '${value}'` };
        }
        break;
      case "--lead-surface":
        out.leadSurface = value;
        break;
      case "--notify-surface":
        out.notifySurface = value;
        break;
      case "--interval":
      case "--timeout":
      case "--summary":
      case "--stall":
      case "--alert-cooldown": {
        const key = {
          "--interval": "interval",
          "--timeout": "timeout",
          "--summary": "summary",
          "--stall": "stall",
          "--alert-cooldown": "alertCooldown",
        }[arg];
        const seconds = Number(value);
        if (!Number.isFinite(seconds) || seconds <= 0) {
          return { error: `${arg} must be a positive number of seconds, got '${value}'` };
        }
        out[key] = seconds;
        break;
      }
      default:
        return { error: `unknown option '${arg}'` };
    }
  }
  if (!out.help && !out.out) {
    return { error: "--out PATH is required; the watcher will not guess where to write" };
  }
  return out;
}

// The watcher exists to observe one local trainer. Pointing it at a remote host
// would make it a network client for someone else's data, which is not what it
// is for, so the host is checked rather than trusted.
const LOOPBACK = new Set(["127.0.0.1", "localhost", "::1", "[::1]", "0.0.0.0"]);

function checkLoopback(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return `--url '${rawUrl}' is not a URL`;
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return `--url must be http or https, got '${parsed.protocol}'`;
  }
  const host = parsed.hostname.replace(/^\[|\]$/g, "");
  if (!LOOPBACK.has(host) && !LOOPBACK.has(parsed.hostname)) {
    return `--url host '${parsed.hostname}' is not loopback; this watcher only reads a local trainer`;
  }
  return null;
}

// ------------------------------------------------------------------ reading

async function fetchStatus(url, timeoutSeconds) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutSeconds * 1000);
  try {
    const response = await fetch(`${url}/api/status`, {
      signal: controller.signal,
      headers: { accept: "application/json" },
    });
    if (!response.ok) {
      return { ok: false, error: `HTTP ${response.status}` };
    }
    return { ok: true, status: await response.json() };
  } catch (error) {
    return { ok: false, error: error?.name === "AbortError" ? "timed out" : String(error?.message ?? error) };
  } finally {
    clearTimeout(timer);
  }
}

function run(command, args) {
  return new Promise((done) => {
    execFile(command, args, { timeout: 5000 }, (error, stdout) => {
      done(error ? null : String(stdout));
    });
  });
}

// Memory and CPU for one pid, plus whether its command line actually mentions
// the run we think we are watching. A pid can be recycled, and reporting
// another process's memory as the trainer's would be worse than reporting none.
async function sampleProcess(pid, expectedRun) {
  if (!pid) return null;
  const out = await run("ps", ["-o", "rss=,%cpu=,command=", "-p", String(pid)]);
  if (!out || !out.trim()) {
    return { pid, alive: false };
  }
  const line = out.trim();
  const match = line.match(/^\s*(\d+)\s+([\d.]+)\s+(.*)$/);
  if (!match) {
    return { pid, alive: true };
  }
  const [, rss, cpu, command] = match;
  return {
    pid,
    alive: true,
    rss_mb: Math.round(Number(rss) / 1024),
    cpu_pct: Number(cpu),
    run_matches: expectedRun ? command.includes(expectedRun) : null,
  };
}

// ------------------------------------------------------------------ shaping

function num(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function str(value) {
  return typeof value === "string" ? value : null;
}

// One flat, small record per poll. Deliberately not the whole status payload:
// this file is meant to be greppable and to stay small over days of polling.
function snapshot(at, result, proc) {
  if (!result.ok) {
    return { t: at, ok: false, error: result.error };
  }
  const s = result.status ?? {};
  const curriculum = s.curriculum ?? {};
  const overall = s.overall ?? null;
  const checkpoint = s.checkpoint ?? {};
  const sampler = s.sampler ?? null;
  const resources = s.resources ?? {};
  return {
    t: at,
    ok: true,
    run_id: str(s.run_id),
    phase: str(s.phase),
    generation: num(s.generation),
    episodes: num(s.episodes),
    eps: num(s.episodes_per_second),
    updated_at: str(s.updated_at),
    stale: s.stale === true,
    stage: num(curriculum.stage),
    ladder: str(curriculum.ladder),
    scope: str(curriculum.evaluation_scope),
    origin_run: str(curriculum.origin_run_id),
    champion: str(s.champion?.id),
    overall: overall
      ? {
          round: str(overall.round),
          wins: num(overall.wins),
          games: num(overall.games),
          lower_bound: num(overall.lower_bound),
          passed: overall.passed === true,
        }
      : null,
    checkpoint: {
      generation: num(checkpoint.generation),
      saved_at: str(checkpoint.saved_at),
    },
    sampler: sampler
      ? { panel: num(sampler.panel), coverage: num(sampler.coverage), tour: num(sampler.tour) }
      : null,
    workers: num(resources.workers),
    duty: num(resources.duty_cycle),
    proc: proc ?? null,
  };
}

const WORKING = new Set(["training", "auditing", "initializing"]);

function ageSeconds(iso, now) {
  if (!iso) return null;
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return null;
  return (now - then) / 1000;
}

// Everything worth saying out loud, derived from this snapshot and the last
// one. Each alert carries a `kind` so repeats of the same condition can be
// rate limited without suppressing a genuinely new one.
function alertsFor(current, previous, memory, options, now) {
  const alerts = [];
  const add = (kind, level, message) => alerts.push({ kind, level, message });

  if (!current.ok) {
    add("api_unavailable", "error", `trainer status unreadable at ${options.url}: ${current.error}`);
    return alerts;
  }

  if (options.run && current.run_id && current.run_id !== options.run) {
    add(
      "run_mismatch",
      "error",
      `expected run ${options.run} but the API reports ${current.run_id}`,
    );
  }

  if (current.phase === "stopped") {
    add("phase_stopped", "warn", "trainer reports phase stopped");
  }
  if (current.phase === "error") {
    add("phase_error", "error", "trainer reports phase error");
  }

  if (previous && previous.ok && previous.phase && previous.phase !== current.phase) {
    add("phase_changed", "info", `phase ${previous.phase} -> ${current.phase}`);
  }
  if (previous && previous.ok) {
    if (previous.ladder !== current.ladder || previous.scope !== current.scope) {
      add(
        "curriculum_changed",
        "info",
        `curriculum ${previous.ladder ?? "?"}/${previous.scope ?? "?"} -> ${current.ladder ?? "?"}/${current.scope ?? "?"}`,
      );
    }
    if (previous.stage !== current.stage) {
      add("stage_changed", "info", `stage ${previous.stage} -> ${current.stage}`);
    }
    if (previous.champion !== current.champion) {
      add("champion_changed", "info", `champion ${previous.champion ?? "none"} -> ${current.champion ?? "none"}`);
    }
    if ((previous.overall?.round ?? null) !== (current.overall?.round ?? null)) {
      add(
        "gate_round_changed",
        "info",
        `gate round ${previous.overall?.round ?? "none"} -> ${current.overall?.round ?? "none"}`,
      );
    }
    if (previous.run_id && current.run_id && previous.run_id !== current.run_id) {
      add("run_changed", "warn", `run id ${previous.run_id} -> ${current.run_id}`);
    }
  }

  const working = WORKING.has(current.phase ?? "");

  if (working && memory.lastEpisodeChangeAt) {
    const stalled = (now - memory.lastEpisodeChangeAt) / 1000;
    if (stalled >= options.stall) {
      add(
        "no_episode_progress",
        "warn",
        `episodes stuck at ${current.episodes} for ${Math.round(stalled / 60)} minutes while phase is ${current.phase}`,
      );
    }
  }

  if (working) {
    const age = ageSeconds(current.checkpoint?.saved_at, now);
    if (age !== null && age >= options.stall) {
      add(
        "checkpoint_stale",
        "warn",
        `last checkpoint is ${Math.round(age / 60)} minutes old while phase is ${current.phase}`,
      );
    }
  }

  if (current.stale) {
    add("status_stale", "warn", "trainer marks its own status snapshot as stale");
  }

  if (current.proc && current.proc.alive === false) {
    add("process_gone", "error", `pid ${current.proc.pid} is no longer running`);
  }
  if (current.proc && current.proc.run_matches === false) {
    add(
      "process_mismatch",
      "error",
      `pid ${current.proc.pid} does not look like run ${options.run}; its memory and CPU are not reported as the trainer's`,
    );
  }

  return alerts;
}

// ------------------------------------------------------------------ output

function line(record) {
  return `${JSON.stringify(record)}\n`;
}

function stamp() {
  return new Date().toISOString().replace("T", " ").slice(0, 19);
}

function describe(record) {
  if (!record.ok) return `unreachable: ${record.error}`;
  const parts = [
    record.run_id ?? "no run id",
    record.phase ?? "no phase",
    `gen ${record.generation ?? "?"}`,
    `${record.episodes ?? "?"} episodes`,
  ];
  if (record.ladder) parts.push(record.ladder);
  if (record.overall) {
    const round = record.overall.round ?? "no round";
    const bound = record.overall.lower_bound === null ? "no bound" : `LB ${(record.overall.lower_bound * 100).toFixed(1)}%`;
    parts.push(`${round}: ${record.overall.wins ?? 0}/${record.overall.games ?? 0} ${bound}`);
  }
  if (record.checkpoint?.generation !== null && record.checkpoint?.generation !== undefined) {
    parts.push(`ckpt g${record.checkpoint.generation}`);
  }
  if (record.proc?.rss_mb) parts.push(`${record.proc.rss_mb}MB ${record.proc.cpu_pct}%cpu`);
  return parts.join(" | ");
}

async function cmuxSend(surface, message) {
  const sent = await run("cmux", ["send", "--surface", surface, message]);
  if (sent === null) return false;
  await run("cmux", ["send-key", "--surface", surface, "enter"]);
  return true;
}

async function cmuxNotify(surface, message) {
  const out = await run("cmux", ["notify", "--surface", surface, message]);
  return out !== null;
}

// ------------------------------------------------------------------- driver

async function poll(options, memory) {
  const now = Date.now();
  const at = new Date(now).toISOString();
  const result = await fetchStatus(options.url, options.timeout);
  const proc = await sampleProcess(options.pid, options.run ?? result.status?.run_id);
  const record = snapshot(at, result, proc);

  if (record.ok && record.episodes !== memory.lastEpisodes) {
    memory.lastEpisodes = record.episodes;
    memory.lastEpisodeChangeAt = now;
  }
  if (memory.lastEpisodeChangeAt === null) {
    memory.lastEpisodeChangeAt = now;
  }

  const alerts = alertsFor(record, memory.previous, memory, options, now);
  if (alerts.length > 0) {
    record.alerts = alerts.map((a) => a.kind);
  }

  appendFileSync(memory.outPath, line(record));

  if (!options.quiet || alerts.length > 0) {
    console.log(`[${stamp()}] ${describe(record)}`);
  }
  for (const alert of alerts) {
    console.log(`[${stamp()}] ${alert.level.toUpperCase()}: ${alert.message}`);
  }

  // Only conditions that need a person are worth waking anyone for, and never
  // more than once per cooldown per kind.
  const worthWaking = alerts.filter((a) => a.level !== "info");
  for (const alert of worthWaking) {
    const last = memory.alertedAt.get(alert.kind) ?? 0;
    if (now - last < options.alertCooldown * 1000) continue;
    memory.alertedAt.set(alert.kind, now);
    if (options.leadSurface) {
      await cmuxSend(options.leadSurface, `[WATCH ${alert.level}] ${alert.message}`);
    }
    if (options.notifySurface) {
      await cmuxNotify(options.notifySurface, `${alert.level}: ${alert.message}`);
    }
  }

  if (record.ok) {
    memory.previous = record;
  }

  if (now - memory.lastSummaryAt >= options.summary * 1000) {
    memory.lastSummaryAt = now;
    const polls = memory.polls;
    const failures = memory.failures;
    console.log(
      `[${stamp()}] summary: ${polls} polls, ${failures} unreachable, ${describe(record)}`,
    );
  }

  memory.polls += 1;
  if (!record.ok) memory.failures += 1;

  return record;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.error) {
    console.error(`watch.mjs: ${options.error}`);
    process.exit(2);
  }
  if (options.help) {
    console.log(HELP);
    process.exit(0);
  }
  const urlProblem = checkLoopback(options.url);
  if (urlProblem) {
    console.error(`watch.mjs: ${urlProblem}`);
    process.exit(2);
  }

  const outPath = resolve(options.out);
  mkdirSync(dirname(outPath), { recursive: true });

  const memory = {
    outPath,
    previous: null,
    lastEpisodes: null,
    lastEpisodeChangeAt: null,
    lastSummaryAt: Date.now(),
    alertedAt: new Map(),
    polls: 0,
    failures: 0,
  };

  console.log(
    `[${stamp()}] watching ${options.url} every ${options.interval}s, appending to ${outPath}` +
      (options.run ? `, expecting run ${options.run}` : "") +
      (options.pid ? `, sampling pid ${options.pid}` : ""),
  );
  console.log(`[${stamp()}] read-only: this watcher never starts, stops, restarts or reconfigures anything.`);

  await poll(options, memory);
  if (options.once) return;

  const timer = setInterval(() => {
    poll(options, memory).catch((error) => {
      console.error(`[${stamp()}] watcher error: ${error?.message ?? error}`);
    });
  }, options.interval * 1000);

  const stop = () => {
    clearInterval(timer);
    console.log(`[${stamp()}] stopping after ${memory.polls} polls (${memory.failures} unreachable).`);
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}

const HELP = `watch.mjs - read-only watcher for the melee-mario trainer

  node scripts/mario/watch.mjs --out PATH [options]

  --out PATH            NDJSON output path (required, appended to)
  --url URL             trainer base URL, loopback only (default http://127.0.0.1:8788)
  --interval SECONDS    poll period (default 60)
  --timeout SECONDS     per-request timeout (default 10)
  --summary SECONDS     stdout summary period (default 300)
  --stall SECONDS       episode/checkpoint stall threshold (default 300)
  --run RUN_ID          expected run id; a mismatch is an alert
  --pid PID             sample this process's memory and CPU, verified against --run
  --lead-surface ID     cmux surface to wake on non-informational alerts only
  --notify-surface ID   cmux surface for passive notifications
  --alert-cooldown SEC  minimum gap between repeats of one alert kind (default 900)
  --once                poll once and exit
  --quiet               print only alerts and summaries

This watcher observes. It never starts, stops, restarts, retunes or reconfigures
the trainer, and it makes no request other than a GET against a loopback host.`;

main().catch((error) => {
  console.error(`watch.mjs: ${error?.message ?? error}`);
  process.exit(1);
});
