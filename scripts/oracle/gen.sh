#!/usr/bin/env bash
# Regenerates every Rust table that is derived from the Elm source of truth.
# Run this after changing Melee.Ship, Melee.Arsenal, Melee.Catalog, Melee.Art
# or Melee.Masks. Never hand-edit the *_generated.rs files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p artifacts/oracle

lamdera make tests/Oracle/Catalog.elm --output=artifacts/oracle/catalog.js >/dev/null
node scripts/oracle/run-elm-oracle.js artifacts/oracle/catalog.js Oracle.Catalog \
  > artifacts/oracle/catalog.json
node scripts/oracle/gen-catalog.mjs

lamdera make tests/Oracle/Masks.elm --output=artifacts/oracle/masks.js >/dev/null
node scripts/oracle/run-elm-oracle.js artifacts/oracle/masks.js Oracle.Masks \
  > artifacts/oracle/masks.json
node scripts/oracle/gen-masks.mjs
