#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export NEAT_WORKERS="${NEAT_WORKERS:-2}"
export NEAT_PORT="${NEAT_PORT:-8788}"
PY="${PY:-/home/schalk/git/uqm-ai/.venv/bin/python}"
if [[ ! -x "$PY" ]]; then PY="$(command -v python3)"; fi
# 2 physical cores, 4 GB host RAM. GPU VRAM is separate.
exec systemd-run --user --scope \
  --quiet \
  -p CPUQuota=200% \
  -p MemoryMax=4G \
  -p MemoryHigh=3500M \
  -- \
  taskset -c 6,7 \
  "$PY" -u scripts/neat/train.py
