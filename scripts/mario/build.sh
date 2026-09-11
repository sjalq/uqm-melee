#!/bin/bash
#
# Build the MarI/O mission control dashboard.
#
# Produces scripts/mario/dashboard.js, which the melee-mario binary serves
# at /dashboard.js alongside scripts/mario/index.html at /.
#
# Usage:
#   scripts/mario/build.sh            # optimized build (default)
#   scripts/mario/build.sh --debug    # unoptimized, keeps the Elm debugger off
#                                     # but leaves names readable for debugging
#   scripts/mario/build.sh --output PATH
#
# The Elm sources live in tests/Mario/Dashboard.elm plus tests/Mario/Dashboard/*.
# tests/ is already an elm.json source-directory, so no elm.json change is needed.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

entry="tests/Mario/Dashboard.elm"
output="$here/dashboard.js"
optimize=1

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      optimize=0
      shift
      ;;
    --output)
      if [ $# -lt 2 ]; then
        echo "build.sh: --output needs a path" >&2
        exit 2
      fi
      output="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "build.sh: unknown argument '$1' (try --help)" >&2
      exit 2
      ;;
  esac
done

if ! command -v lamdera >/dev/null 2>&1; then
  echo "build.sh: 'lamdera' is not on PATH. This project compiles Elm with the Lamdera compiler." >&2
  exit 1
fi

cd "$root"

if [ ! -f "$entry" ]; then
  echo "build.sh: missing entry point $entry" >&2
  exit 1
fi

tmp="$(mktemp -t mario-dashboard.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

if [ "$optimize" -eq 1 ]; then
  lamdera make "$entry" --optimize --output="$tmp.js"
else
  lamdera make "$entry" --output="$tmp.js"
fi

mv "$tmp.js" "$output"

bytes="$(wc -c < "$output" | tr -d ' ')"
echo "build.sh: wrote $output ($bytes bytes)"
