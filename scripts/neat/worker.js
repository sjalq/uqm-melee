#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const readline = require("readline");

const kernelPath = path.join(__dirname, "kernel.js");
if (!fs.existsSync(kernelPath)) {
  process.stderr.write("missing kernel.js; compile Neat.Eval first\n");
  process.exit(1);
}

const vm = require("vm");
const sandbox = {
  console,
  setTimeout,
  clearTimeout,
  setInterval,
  clearInterval,
};
sandbox.global = sandbox;
sandbox.window = sandbox;
sandbox.self = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(kernelPath, "utf8"), sandbox);
const Elm = sandbox.Elm || (typeof sandbox.module === "object" && sandbox.module.exports);
if (!Elm || !Elm.Neat || !Elm.Neat.Eval) {
  process.stderr.write("kernel.js has no Elm.Neat.Eval\n");
  process.exit(1);
}

const app = Elm.Neat.Eval.init();
const pending = [];

app.ports.response.subscribe((msg) => {
  const next = pending.shift();
  if (next) next(msg);
  else process.stdout.write(msg + "\n");
});

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) return;
  pending.push((msg) => process.stdout.write(msg + "\n"));
  app.ports.request.send(line);
});
rl.on("close", () => process.exit(0));
