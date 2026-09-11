#!/usr/bin/env bash
# Launcher for the local MarI/O trainer and its dashboard.
#
# Builds the release evaluator, then runs it from the repository root so that
# artifacts/mario/<run> and scripts/mario are where the binary expects them.
# The evaluator lowers its own priority and holds itself to the duty fraction,
# so this script does not need to police it; the nice below is belt and braces
# for the build step and anything the shell spawns.
#
# Usage:
#   scripts/mario/run.sh start   [--minutes 30] [extra melee-mario options]
#   scripts/mario/run.sh resume  [--minutes 30] [...]
#   scripts/mario/run.sh status
#   scripts/mario/run.sh pause | resume-work | stop
#   scripts/mario/run.sh serve
#   scripts/mario/run.sh bench
#
# Any option the binary understands can be passed through; see
#   scripts/mario/run.sh help
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
binary="$root/rust/target/release/melee-mario"

command="${1:-help}"
shift || true

# Two build jobs keeps the machine usable while compiling.
if [ "${MARIO_SKIP_BUILD:-0}" != "1" ]; then
  echo "building melee-mario (release, -j 2)" >&2
  (cd "$root/rust" && nice -n 10 cargo build -j 2 --release -p melee-mario >&2)
fi

if [ ! -x "$binary" ]; then
  echo "scripts/mario/run.sh: $binary is missing; build it first" >&2
  exit 1
fi

cd "$root"
exec "$binary" "$command" --root "$root" "$@"
