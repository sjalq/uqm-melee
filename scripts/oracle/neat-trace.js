#!/usr/bin/env node
"use strict";

// NDJSON adapter for the separately compiled Oracle.NeatTrace worker. This
// deliberately never reads or writes scripts/neat/kernel.js, which may belong
// to a live evaluator run.

const fs = require("fs");
const path = require("path");
const readline = require("readline");
const vm = require("vm");

const root = path.resolve(__dirname, "../..");
const bundle = path.join(root, "artifacts/oracle/neat-trace-elm.js");

if (!fs.existsSync(bundle)) {
  process.stderr.write(
    "missing artifacts/oracle/neat-trace-elm.js; compile with:\n" +
      "  lamdera make tests/Oracle/NeatTrace.elm --output=artifacts/oracle/neat-trace-elm.js\n",
  );
  process.exit(1);
}

const sandbox = { console, setTimeout, clearTimeout, setInterval, clearInterval };
sandbox.global = sandbox;
sandbox.window = sandbox;
sandbox.self = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(bundle, "utf8"), sandbox);

const Elm = sandbox.Elm || (sandbox.module && sandbox.module.exports);
if (!Elm || !Elm.Oracle || !Elm.Oracle.NeatTrace) {
  process.stderr.write("bundle has no Elm.Oracle.NeatTrace\n");
  process.exit(1);
}

const app = Elm.Oracle.NeatTrace.init();
const jobs = [];
let active = false;

function sendNext() {
  if (active || jobs.length === 0) return;
  active = true;
  app.ports.request.send(jobs.shift());
}

app.ports.response.subscribe((line) => {
  process.stdout.write(line + "\n");
  let record;
  try {
    record = JSON.parse(line);
  } catch (_) {
    process.stderr.write("oracle emitted invalid JSON\n");
    process.exitCode = 1;
    return;
  }
  if (record.type === "done" || record.type === "error") {
    active = false;
    sendNext();
  } else {
    app.ports.advance.send(null);
  }
});

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", (line) => {
  if (!line.trim()) return;
  jobs.push(line);
  sendNext();
});
