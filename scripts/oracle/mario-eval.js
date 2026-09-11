#!/usr/bin/env node
"use strict";
// NDJSON adapter for the Elm MarI/O oracle (tests/Oracle/MarioPolicy.elm).
//
// Reads one request per stdin line and writes ONE LINE PER STEP, in order, the
// same shape `melee-mario` writes. A rejected request writes a single
// {"error":...} line instead, and a request with no steps writes nothing. It is
// the Elm side of scripts/oracle/check-mario.py and needs no trainer artifacts,
// only the compiled worker bundle.
//
//   lamdera make tests/Oracle/MarioPolicy.elm --output=artifacts/oracle/mario-oracle.js
//   node scripts/oracle/mario-eval.js [--bundle <path>] < requests.ndjson
//
// The bundle path defaults to artifacts/oracle/mario-oracle.js relative to the
// repository root, and may also be set through MARIO_ORACLE_BUNDLE.

const fs = require("fs");
const path = require("path");
const readline = require("readline");
const vm = require("vm");

const ROOT = path.join(__dirname, "..", "..");
const DEFAULT_BUNDLE = path.join(ROOT, "artifacts", "oracle", "mario-oracle.js");

function parseArgs(argv) {
  let bundle = process.env.MARIO_ORACLE_BUNDLE || DEFAULT_BUNDLE;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--bundle") {
      bundle = argv[i + 1];
      i += 1;
    } else if (argv[i] === "--help" || argv[i] === "-h") {
      process.stdout.write(
        "usage: mario-eval.js [--bundle <compiled.js>]\n" +
          "reads NDJSON oracle requests on stdin, writes one response per line\n" +
          "build the bundle with:\n" +
          "  lamdera make tests/Oracle/MarioPolicy.elm --output=artifacts/oracle/mario-oracle.js\n"
      );
      process.exit(0);
    } else {
      process.stderr.write(`unknown argument ${argv[i]}\n`);
      process.exit(2);
    }
  }
  return bundle;
}

const bundle = parseArgs(process.argv.slice(2));
if (!bundle || !fs.existsSync(bundle)) {
  process.stderr.write(
    `missing oracle bundle ${bundle}\n` +
      "build it with: lamdera make tests/Oracle/MarioPolicy.elm --output=artifacts/oracle/mario-oracle.js\n"
  );
  process.exit(1);
}

const sandbox = { console, setTimeout, clearTimeout, setInterval, clearInterval };
sandbox.global = sandbox;
sandbox.window = sandbox;
sandbox.self = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(bundle, "utf8"), sandbox);

const root = sandbox.Elm || (typeof sandbox.module === "object" && sandbox.module.exports);
const worker = root && root.Oracle && root.Oracle.MarioPolicy;
if (!worker || !worker.init) {
  process.stderr.write(`${bundle} has no Elm.Oracle.MarioPolicy\n`);
  process.exit(1);
}

const app = worker.init();
app.ports.response.subscribe((lines) => {
  if (lines.length === 0) return;
  process.stdout.write(lines.join("\n") + "\n");
});

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) return;
  app.ports.request.send(line);
});
rl.on("close", () => process.exit(0));
