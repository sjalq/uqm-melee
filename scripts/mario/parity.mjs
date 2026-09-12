#!/usr/bin/env node
//
// Proves that changing the evaluator's worker count, or rebuilding the
// evaluator itself, does not change where a run goes.
//
// Each arm resumes a COPY of the same starting checkpoint in its own scratch
// root, runs the same bounded budget, and is compared against the first arm's
// final checkpoint. The comparison is the whole point, so the only fields it
// is allowed to ignore are the ones that describe the machine or the binary
// rather than the run:
//
//   saved_at, elapsed_seconds, compute_seconds   wall clock
//   evaluator                                    the binary's own fingerprint
//   events[].at                                  wall clock
//   the "resumed with a different evaluator"      the rebuild notice itself
//   event a rebuilt binary writes
//
// Everything else, the random streams, the population, the champion, the
// per-cell evidence, the sampler stats and cursor, the panel, the mode, the
// episode and win counters and the whole history, is compared exactly. A
// difference anywhere in it fails the run.
//
// Budgets must land on a boundary every arm shares. A unit of work is
// worker-dependent by design (eight fights at one worker, forty at nine), so
// --episodes would stop the arms at different points and diff a difference
// that is only where they were interrupted. --generations is a common
// boundary at every worker count, and is the default here for that reason.
//
// The source run is READ ONLY. Nothing is written outside --scratch, and the
// script refuses to start if --scratch is inside the source tree.
//
// Usage:
//   node scripts/mario/parity.mjs \
//     --source artifacts/mario/mario-ratio-staged-20260912 \
//     --new    rust/target/release/melee-mario \
//     --arm old:1 --arm new:1 --arm new:3 \
//     --generations 2 \
//     --scratch /tmp/mario-parity        # a PARENT; a fresh child is made inside it
//
// `old:N` runs the binary archived beside the source checkpoint; `new:N` runs
// --new, which needs --allow-rebuild and gets it automatically. The first arm
// listed is the baseline every other arm is compared against.

import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile, copyFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const STRIPPED_TOP = ["saved_at", "evaluator", "elapsed_seconds", "compute_seconds"];
// The one event a rebuilt binary writes that a same-binary resume does not.
// Matched on its literal prefix rather than a loose pattern, so a message that
// merely mentions an evaluator is still compared.
const REBUILD_NOTICE = "resumed with a different evaluator: ";

function usage(message) {
  if (message) console.error(`parity.mjs: ${message}`);
  console.error(
    [
      "",
      "usage: node scripts/mario/parity.mjs --source <run dir> --new <binary> [options]",
      "",
      "  --source <dir>     The run to copy a starting checkpoint from. Never written to.",
      "  --new <path>       The rebuilt binary. Required unless every arm is `old`.",
      "  --old <path>       Binary for `old` arms. Default <source>/bin/melee-mario.",
      "  --arm <kind:n>     An arm: `old:1`, `new:1`, `new:9`. Repeatable. The first",
      "                     is the baseline. Default: old:1 new:1. `old` has no",
      "                     pool, so only old:1 is valid for it.",
      "  --from <file>      Checkpoint to start every arm from, inside <source>.",
      "                     Default initial-checkpoint.json.",
      "  --generations <n>  Budget per arm. Default 2. A boundary every arm shares.",
      "  --episodes <n>     Budget per arm. REFUSED unless --unsafe-budget: arms with",
      "                     different worker counts stop at different episode counts.",
      "  --duty <0..1>      Duty cap for every arm. Default 1.",
      "  --nice <n>         Scheduling penalty for every arm. Default 10.",
      "  --scratch <parent> Directory to create a fresh working directory under.",
      "                     Default the system temp directory. The parent is never",
      "                     removed; only the child this run creates is.",
      "  --keep             Leave the scratch roots behind for inspection.",
      "  --dry-run          Print what each arm would run and exit.",
      "",
    ].join("\n"),
  );
  process.exit(message ? 2 : 0);
}

function parseArgs(argv) {
  const options = {
    source: null,
    newBin: null,
    oldBin: null,
    arms: [],
    from: "initial-checkpoint.json",
    generations: null,
    episodes: null,
    duty: "1",
    nice: "10",
    scratch: null,
    keep: false,
    dryRun: false,
    unsafeBudget: false,
  };
  for (let at = 0; at < argv.length; at += 1) {
    const flag = argv[at];
    const next = () => {
      at += 1;
      if (at >= argv.length) usage(`${flag} needs a value`);
      return argv[at];
    };
    switch (flag) {
      case "--source": options.source = next(); break;
      case "--new": options.newBin = next(); break;
      case "--old": options.oldBin = next(); break;
      case "--arm": options.arms.push(next()); break;
      case "--from": options.from = next(); break;
      case "--generations": options.generations = next(); break;
      case "--episodes": options.episodes = next(); break;
      case "--duty": options.duty = next(); break;
      case "--nice": options.nice = next(); break;
      case "--scratch": options.scratch = next(); break;
      case "--keep": options.keep = true; break;
      case "--dry-run": options.dryRun = true; break;
      case "--unsafe-budget": options.unsafeBudget = true; break;
      case "-h":
      case "--help": usage(null); break;
      default: usage(`unknown argument '${flag}'`);
    }
  }
  if (!options.source) usage("--source is required");
  if (options.arms.length === 0) options.arms = ["old:1", "new:1"];
  if (options.generations === null && options.episodes === null) {
    options.generations = "2";
  }
  // The whole proof is that two arms reached the SAME state, so they have to
  // have been stopped at the same place. Worker count changes how many fights
  // one unit of work plays, so an episode budget overshoots by a different
  // amount at each setting and the arms stop somewhere different.
  if (options.episodes !== null && !options.unsafeBudget) {
    usage(
      "--episodes stops arms with different worker counts at different points. " +
        "Use --generations, or pass --unsafe-budget if every arm has the same --workers.",
    );
  }
  return options;
}

function parseArm(raw, at) {
  const [kind, count] = raw.split(":");
  if (kind !== "old" && kind !== "new") usage(`arm '${raw}' must start with old: or new:`);
  const workers = Number(count ?? "1");
  if (!Number.isInteger(workers) || workers < 1) usage(`arm '${raw}' needs a worker count of 1 or more`);
  // The archived binary predates the pool and has no --workers flag at all, so
  // asking it for threads would fail on an unknown argument rather than run
  // the comparison. It is the single-threaded arm by construction.
  if (kind === "old" && workers !== 1) usage(`arm '${raw}': the old binary has no worker pool, use old:1`);
  return { raw, kind, workers, name: kind === "old" ? "old-serial" : `new-w${workers}`, at };
}

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

/** Strips exactly the machine-and-binary fields, and nothing else. */
function normalize(document) {
  const out = { ...document };
  for (const key of STRIPPED_TOP) delete out[key];
  if (Array.isArray(out.events)) {
    out.events = out.events
      .filter((event) => !String(event?.message ?? "").startsWith(REBUILD_NOTICE))
      // Only the timestamp is dropped, and only because it says when the
      // machine got there rather than what happened. Every other field an
      // event carries, including ones added after this was written, stays in
      // the comparison: a normaliser that projects a fixed shape would go
      // quietly blind to whatever the engine starts recording next.
      .map((event) => {
        if (!event || typeof event !== "object") return event;
        const kept = { ...event };
        delete kept.at;
        return kept;
      });
  }
  return out;
}

/** Stable stringify, so key order in the engine's JSON cannot fake a difference. */
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

/** Every path at which two documents differ, deepest first, bounded. */
function differences(left, right, at = "", found = []) {
  if (found.length >= 40) return found;
  const bothObjects =
    left && right && typeof left === "object" && typeof right === "object" &&
    Array.isArray(left) === Array.isArray(right);
  if (!bothObjects) {
    if (canonical(left) !== canonical(right)) {
      found.push({ at: at || "(root)", left, right });
    }
    return found;
  }
  if (Array.isArray(left)) {
    if (left.length !== right.length) {
      found.push({ at: `${at}.length`, left: left.length, right: right.length });
      return found;
    }
    for (let i = 0; i < left.length && found.length < 40; i += 1) {
      differences(left[i], right[i], `${at}[${i}]`, found);
    }
    return found;
  }
  const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort();
  for (const key of keys) {
    if (found.length >= 40) break;
    differences(left[key], right[key], at ? `${at}.${key}` : key, found);
  }
  return found;
}

/** Short enough to read in a terminal, long enough to identify the value. */
function brief(value) {
  const text = canonical(value);
  return text.length > 90 ? `${text.slice(0, 87)}...` : text;
}

function armCommand(arm, options, runId, root) {
  const binary = arm.kind === "old" ? options.oldBin : options.newBin;
  const args = [
    "resume",
    "--root", root,
    "--run", runId,
    "--duty", options.duty,
    "--nice", options.nice,
    "--no-server",
  ];
  // Only the rebuilt binary knows the flag. Passing it to the archived one
  // would be an unknown argument, not a single-threaded run.
  if (arm.kind === "new") args.push("--workers", String(arm.workers));
  if (options.generations !== null) args.push("--generations", options.generations);
  if (options.episodes !== null) args.push("--episodes", options.episodes);
  // The old binary produced the checkpoint, so it resumes under the guard. A
  // rebuilt one cannot, and being allowed past the guard on a scratch copy is
  // the entire question this script exists to answer.
  if (arm.kind === "new") args.push("--allow-rebuild");
  return { binary, args };
}

function runArm(binary, args, label) {
  return new Promise((done) => {
    const began = Date.now();
    const child = spawn(binary, args, { stdio: ["ignore", "pipe", "pipe"] });
    let tail = "";
    const keep = (chunk) => {
      tail = `${tail}${chunk}`.slice(-4000);
    };
    child.stdout.on("data", keep);
    child.stderr.on("data", keep);
    child.on("error", (error) => done({ ok: false, error: String(error), tail, seconds: 0 }));
    child.on("close", (code, signal) => {
      const seconds = (Date.now() - began) / 1000;
      if (code === 0) return done({ ok: true, seconds, tail });
      done({
        ok: false,
        error: `${label} exited with ${signal ? `signal ${signal}` : `code ${code}`}`,
        tail,
        seconds,
      });
    });
  });
}

async function exists(target) {
  try {
    await stat(target);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  // Resolved through every symlink before anything is compared against it. A
  // containment check on unresolved paths is not a check at all: a scratch
  // directory that is a symlink into the source tree passes it.
  if (!(await exists(options.source))) usage(`--source not found: ${options.source}`);
  const source = await realpath(path.resolve(options.source));
  const runId = path.basename(source);
  options.oldBin = path.resolve(options.oldBin ?? path.join(source, "bin", "melee-mario"));
  const arms = options.arms.map(parseArm);
  // Repeating an arm is how the harness shows a binary is reproducible against
  // itself, so the names have to stay distinguishable in the report.
  const seen = new Map();
  for (const arm of arms) {
    const count = (seen.get(arm.name) ?? 0) + 1;
    seen.set(arm.name, count);
    if (count > 1) arm.name = `${arm.name}#${count}`;
  }
  if (arms.some((arm) => arm.kind === "new")) {
    if (!options.newBin) usage("--new is required when any arm is `new`");
    options.newBin = path.resolve(options.newBin);
    if (!(await exists(options.newBin))) usage(`--new binary not found: ${options.newBin}`);
  }
  if (arms.some((arm) => arm.kind === "old") && !(await exists(options.oldBin))) {
    usage(`old binary not found: ${options.oldBin}`);
  }

  // --scratch names a PARENT to work under, never the directory to work in.
  // This script deletes what it creates, so it must only ever be handed a path
  // it created itself: a caller who points --scratch at a directory of their
  // own keeps it, and gets a fresh child inside it. The parent is created if
  // missing and is never removed.
  const parent = path.resolve(options.scratch ?? tmpdir());
  await mkdir(parent, { recursive: true });
  const realParent = await realpath(parent);
  const scratch = await mkdtemp(path.join(realParent, "mario-parity-"));
  const owned = await realpath(scratch);
  // The source run is live evidence, and nothing here may write inside it.
  // Checked on the owned child after resolution, so a symlinked parent cannot
  // smuggle the working directory into the source tree.
  if (owned === source || owned.startsWith(`${source}${path.sep}`)) {
    await rm(owned, { recursive: true, force: true });
    usage("--scratch resolves inside --source; the source run is read-only evidence");
  }

  const from = path.join(source, options.from);
  if (!(await exists(from))) usage(`starting checkpoint not found: ${from}`);
  const startingBytes = await readFile(from);
  const startingHash = sha256(startingBytes);
  const config = path.join(source, "config.json");
  const hasConfig = await exists(config);

  console.log(`parity: run ${runId}`);
  console.log(`parity: from ${path.relative(process.cwd(), from)} sha256 ${startingHash.slice(0, 16)}`);
  const budget = options.generations !== null
    ? `--generations ${options.generations}`
    : `--episodes ${options.episodes} (UNSAFE across worker counts)`;
  console.log(`parity: budget ${budget}, duty ${options.duty}, nice ${options.nice}`);
  console.log(`parity: scratch ${owned}`);

  const results = [];
  for (const arm of arms) {
    const root = path.join(owned, arm.name);
    const dir = path.join(root, "artifacts", "mario", runId);
    const { binary, args } = armCommand(arm, options, runId, root);
    if (options.dryRun) {
      console.log(`parity: ${arm.name}: ${binary} ${args.join(" ")}`);
      continue;
    }
    // The scratch child was just created, so every arm directory is new and
    // there is nothing here to delete.
    await mkdir(dir, { recursive: true });
    await writeFile(path.join(dir, "checkpoint.json"), startingBytes);
    if (hasConfig) await copyFile(config, path.join(dir, "config.json"));

    process.stdout.write(`parity: ${arm.name} running...`);
    const outcome = await runArm(binary, args, arm.name);
    if (!outcome.ok) {
      console.log(" failed");
      console.error(`parity: ${outcome.error}`);
      console.error(outcome.tail.trim());
      process.exit(1);
    }
    const finalPath = path.join(dir, "checkpoint.json");
    const document = JSON.parse(await readFile(finalPath, "utf8"));
    const stripped = normalize(document);
    results.push({
      arm,
      seconds: outcome.seconds,
      document,
      stripped,
      hash: sha256(canonical(stripped)),
    });
    console.log(
      ` ${outcome.seconds.toFixed(1)}s, generation ${document.generation ?? document.population?.generation ?? "?"}` +
        `, ${document.episodes ?? "?"} episodes, ${sha256(canonical(stripped)).slice(0, 16)}`,
    );
  }
  if (options.dryRun) {
    await rm(owned, { recursive: true, force: true });
    return;
  }

  const baseline = results[0];
  let failed = false;
  console.log("");
  console.log(`parity: baseline ${baseline.arm.name} ${baseline.hash.slice(0, 16)}`);
  for (const result of results.slice(1)) {
    if (result.hash === baseline.hash) {
      console.log(`parity: ${result.arm.name} IDENTICAL to ${baseline.arm.name}`);
      continue;
    }
    failed = true;
    const found = differences(baseline.stripped, result.stripped);
    console.log(`parity: ${result.arm.name} DIFFERS from ${baseline.arm.name} at ${found.length} path(s)`);
    for (const one of found.slice(0, 20)) {
      console.log(`  ${one.at}`);
      console.log(`    ${baseline.arm.name}: ${brief(one.left)}`);
      console.log(`    ${result.arm.name}: ${brief(one.right)}`);
    }
  }
  // Stated whether it passed or failed: a reader must be able to see what the
  // comparison was blind to without reading this file.
  console.log("");
  console.log(
    `parity: ignored ${STRIPPED_TOP.join(", ")}, events[].at, and the rebuild notice. ` +
      "Everything else was compared exactly.",
  );
  for (const result of results) {
    const speed = baseline.seconds / result.seconds;
    console.log(
      `parity: ${result.arm.name.padEnd(10)} ${result.seconds.toFixed(1)}s` +
        `  ${speed.toFixed(2)}x baseline wall`,
    );
  }
  // Only the directory this run created is removed, never the parent it was
  // asked to work under.
  if (!options.keep) await rm(owned, { recursive: true, force: true });
  else console.log(`parity: scratch kept at ${owned}`);
  process.exit(failed ? 1 : 0);
}

main().catch((error) => {
  console.error(`parity.mjs: ${error?.stack ?? error}`);
  process.exit(1);
});
