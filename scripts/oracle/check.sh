#!/usr/bin/env bash
# Differential check of the Rust port against the Elm simulation.
# Every sweep below must diff clean; a diff is a defect in the port, not noise.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p artifacts/oracle

fail=0

check() {
  local name="$1" module="$2" bin="$3"
  lamdera make "tests/Oracle/$module.elm" --output="artifacts/oracle/$name.js" >/dev/null
  node scripts/oracle/run-elm-oracle.js "artifacts/oracle/$name.js" "Oracle.$module" \
    > "artifacts/oracle/$name.elm.txt"
  cargo run --quiet --manifest-path rust/Cargo.toml --release --bin "$bin" \
    > "artifacts/oracle/$name.rust.txt"
  if diff -q "artifacts/oracle/$name.elm.txt" "artifacts/oracle/$name.rust.txt" >/dev/null; then
    echo "  ok   $name ($(wc -l < "artifacts/oracle/$name.elm.txt" | tr -d ' ') rows)"
  else
    echo "  FAIL $name"
    diff "artifacts/oracle/$name.elm.txt" "artifacts/oracle/$name.rust.txt" | head -20 | cut -c1-200
    fail=1
  fi
}

echo "elm <-> rust differential:"
check primitives  Primitives  oracle_primitives
check maskchecks  MaskChecks  oracle_masks

exit "$fail"
