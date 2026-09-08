#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/schalk/git/uqm-melee
cd "$ROOT"
mkdir -p artifacts/neat
if [[ -f artifacts/neat/train.pid ]]; then
  old=$(cat artifacts/neat/train.pid || true)
  if [[ -n "${old}" ]] && kill -0 "$old" 2>/dev/null; then
    kill "$old" 2>/dev/null || true
    sleep 1
    kill -9 "$old" 2>/dev/null || true
  fi
  pkill -f 'scripts/neat/train.py' 2>/dev/null || true
  pkill -f 'scripts/neat/worker.js' 2>/dev/null || true
  sleep 1
fi
export NEAT_WORKERS=2
export NEAT_PORT=8788
# 2 physical cores (6,7), 4 GiB address space. GPU VRAM is not this cap.
nohup taskset -c 6,7 /usr/bin/prlimit --as=4294967296 -- \
  /usr/bin/python3 -u scripts/neat/train.py \
  > artifacts/neat/nohup.out 2>&1 &
echo "$!" > artifacts/neat/train.pid
echo "started pid $(cat artifacts/neat/train.pid)"
sleep 2
tail -30 artifacts/neat/nohup.out || true
