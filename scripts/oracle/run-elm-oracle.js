#!/usr/bin/env node
"use strict";
// Runs a compiled Elm oracle worker and prints its single `emit` payload.
// Usage: node run-elm-oracle.js <compiled.js> <Module.Path>
const fs = require("fs");
const vm = require("vm");

const [, , bundle, modulePath] = process.argv;
if (!bundle || !modulePath) {
  process.stderr.write("usage: run-elm-oracle.js <compiled.js> <Module.Path>\n");
  process.exit(2);
}

const sandbox = { console, setTimeout, clearTimeout, setInterval, clearInterval };
sandbox.global = sandbox;
sandbox.window = sandbox;
sandbox.self = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(bundle, "utf8"), sandbox);

const root = sandbox.Elm || (typeof sandbox.module === "object" && sandbox.module.exports);
const app = modulePath.split(".").reduce((acc, part) => acc && acc[part], root);
if (!app || !app.init) {
  process.stderr.write(`bundle has no Elm.${modulePath}\n`);
  process.exit(1);
}

const instance = app.init();
instance.ports.emit.subscribe((payload) => {
  process.stdout.write(payload);
  process.stdout.write("\n");
  process.exit(0);
});
