#!/usr/bin/env bash
# Differential check of the Rust port against the Elm simulation.
# Every sweep must match byte for byte; a mismatch is a defect in the port.
#
# Comparison is by content hash rather than `diff`, so a wrapped or aliased
# diff cannot produce a false pass. `diff` is only used to *show* a mismatch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p artifacts/oracle

fail=0

check() {
  local name="$1" module="$2" bin="$3"
  local elm="artifacts/oracle/$name.elm.txt" rust="artifacts/oracle/$name.rust.txt"

  lamdera make "tests/Oracle/$module.elm" --output="artifacts/oracle/$name.js" >/dev/null
  node scripts/oracle/run-elm-oracle.js "artifacts/oracle/$name.js" "Oracle.$module" > "$elm"
  cargo run --quiet --manifest-path rust/Cargo.toml --release --bin "$bin" > "$rust"

  local a b rows
  a="$(shasum -a 256 < "$elm" | cut -d' ' -f1)"
  b="$(shasum -a 256 < "$rust" | cut -d' ' -f1)"
  rows="$(wc -l < "$elm" | tr -d ' ')"
  if [ "$a" = "$b" ]; then
    echo "  ok   $name ($rows rows, sha ${a:0:12})"
  else
    echo "  FAIL $name  elm ${a:0:12} != rust ${b:0:12}"
    diff "$elm" "$rust" | head -20 | cut -c1-200 || true
    fail=1
  fi
}

echo "elm <-> rust differential:"
check primitives  Primitives  oracle_primitives
check maskchecks  MaskChecks  oracle_masks

if [ "$fail" -ne 0 ]; then
  echo "DIVERGENCE: the Rust port does not reproduce the Elm simulation."
fi
exit "$fail"
