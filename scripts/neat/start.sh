#!/usr/bin/env bash
set -euo pipefail

ROOT=/home/schalk/git/uqm-melee
UNIT=uqm-neat.service
PID_FILE="$ROOT/artifacts/neat/train.pid"
LOG_FILE="$ROOT/artifacts/neat/campaign.log"

cd "$ROOT"
mkdir -p artifacts/neat/campaigns

# Keep the previous campaign intact. The first Rust start forks its exact
# checkpoint; subsequent starts restore the new run's own checkpoint.
RUST_WORKER="$ROOT/artifacts/neat/runs/rust-v2/source/melee-worker"
PARENT_RUN=artifacts/neat/runs/rust-v1
RUST_RUN=artifacts/neat/runs/rust-v2
HINTS_FILE=artifacts/neat/campaigns/takeover-v1/runs/block-mutations/hints.json
if [[ ! -x "$RUST_WORKER" || ! -f "$PARENT_RUN/checkpoint.json" ]]; then
  echo "Rust evaluator or parent checkpoint missing; leaving the running service alone" >&2
  exit 1
fi

pid_is_live() {
  local pid=$1
  [[ -d "/proc/$pid" ]] && kill -0 "$pid" 2>/dev/null
}

pid_has_arg() {
  local pid=$1
  local expected=$2
  [[ -r "/proc/$pid/cmdline" ]] &&
    tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fqx -- "$expected"
}

pid_has_cwd() {
  local pid=$1
  local expected=$2
  [[ "$(readlink "/proc/$pid/cwd" 2>/dev/null || true)" == "$expected" ]]
}

legacy_trainer_matches() {
  local pid=$1
  pid_is_live "$pid" &&
    pid_has_cwd "$pid" "$ROOT" &&
    pid_has_arg "$pid" scripts/neat/train.py
}

legacy_worker_matches() {
  local pid=$1
  pid_is_live "$pid" &&
    pid_has_cwd "$pid" "$ROOT/scripts/neat" &&
    pid_has_arg "$pid" "$ROOT/scripts/neat/worker.js"
}

declare -A legacy_workers=()

remember_legacy_workers() {
  local trainer=$1
  local current child children
  local -a pending=("$trainer")

  while ((${#pending[@]})); do
    current=${pending[0]}
    pending=("${pending[@]:1}")
    children="$(pgrep -P "$current" 2>/dev/null || true)"
    for child in $children; do
      pending+=("$child")
      if legacy_worker_matches "$child"; then
        legacy_workers["$child"]=1
      fi
    done
  done
}

stop_legacy_trainer() {
  local pid=$1
  local worker
  local deadline=$((SECONDS + 60))

  remember_legacy_workers "$pid"
  echo "stopping verified legacy trainer pid $pid"
  kill -TERM "$pid"

  while pid_is_live "$pid" && ((SECONDS < deadline)); do
    remember_legacy_workers "$pid"
    sleep 0.2
  done

  if pid_is_live "$pid"; then
    if ! legacy_trainer_matches "$pid"; then
      echo "refusing to signal pid $pid after its identity changed" >&2
      exit 1
    fi
    echo "legacy trainer pid $pid did not stop within 60 seconds; sending SIGKILL"
    kill -KILL "$pid"
  fi

  for worker in "${!legacy_workers[@]}"; do
    if legacy_worker_matches "$worker"; then
      kill -TERM "$worker"
    fi
  done
  sleep 0.2
  for worker in "${!legacy_workers[@]}"; do
    if legacy_worker_matches "$worker"; then
      kill -KILL "$worker"
    fi
  done

  rm -f "$PID_FILE"
}

unit_load_state="$(systemctl --user show -p LoadState --value "$UNIT" 2>/dev/null || true)"
if [[ -n "$unit_load_state" && "$unit_load_state" != "not-found" ]]; then
  echo "stopping existing $UNIT"
  systemctl --user stop "$UNIT"
fi

for _ in {1..20}; do
  [[ "$(systemctl --user show -p LoadState --value "$UNIT" 2>/dev/null || true)" == "not-found" ]] && break
  systemctl --user reset-failed "$UNIT" 2>/dev/null || true
  sleep 0.1
done

if [[ "$(systemctl --user show -p LoadState --value "$UNIT" 2>/dev/null || true)" != "not-found" ]]; then
  echo "refusing to replace $UNIT because the old unit is still loaded" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  IFS= read -r old_pid < "$PID_FILE" || true
  if [[ ! "${old_pid:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "refusing to use malformed legacy PID file: $PID_FILE" >&2
    exit 1
  elif pid_is_live "$old_pid"; then
    if ! legacy_trainer_matches "$old_pid"; then
      echo "refusing to stop pid $old_pid: cmdline or cwd does not match the legacy trainer" >&2
      exit 1
    fi
    stop_legacy_trainer "$old_pid"
  else
    rm -f "$PID_FILE"
  fi
fi

systemd-run --user \
  --unit=uqm-neat \
  --collect \
  --service-type=exec \
  --working-directory="$ROOT" \
  --setenv=NEAT_WORKERS=2 \
  --setenv=NEAT_PORT=8788 \
  --setenv=OPENBLAS_NUM_THREADS=1 \
  --setenv=OMP_NUM_THREADS=1 \
  --property=AllowedCPUs=6,7 \
  --property=CPUQuota=200% \
  --property=MemoryMax=4G \
  --property=MemorySwapMax=0 \
  --property=Restart=on-failure \
  --property=RestartSec=10 \
  --property=StartLimitIntervalSec=300 \
  --property=StartLimitBurst=3 \
  --property=TimeoutStopSec=60 \
  --property=KillMode=control-group \
  --property="StandardOutput=append:$LOG_FILE" \
  --property="StandardError=append:$LOG_FILE" \
  -- \
  /usr/bin/taskset -c 6,7 \
  /usr/bin/python3 -u scripts/neat/train.py \
    --artifacts "$RUST_RUN" \
    --hints "$HINTS_FILE" \
    --control scripts/neat/hints.json \
    --resume-from "$PARENT_RUN" \
    --evaluator rust \
    --rust-worker "$RUST_WORKER"

sleep 2
systemctl --user --no-pager --full status "$UNIT" || true
