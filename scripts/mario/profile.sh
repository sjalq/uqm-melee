#!/usr/bin/env bash
# Profile the MarI/O evaluator with samply and a flamegraph you can read.
#
# WHY A SEPARATE PROFILE. The release profile uses fat LTO and one codegen
# unit, which inlines tick_authoritative, collide_all, sprites_hit,
# cyborg::decide and Network::activate into each other until a flamegraph is
# two frames tall. rust/Cargo.toml carries a [profile.profiling] that inherits
# release, keeps opt-level 3 and panic = "abort", and trades fat LTO and one
# codegen unit for thin LTO, sixteen codegen units and full DWARF, so the
# functions survive as symbols the profiler can attribute to.
#
# READ THIS BEFORE QUOTING A NUMBER. That trade moves throughput by a few
# percent. Use this script to find out WHERE the time goes; use
#   scripts/mario/run.sh bench
# on the release build to find out HOW MUCH. Never quote a profiling-profile
# figure as the release figure.
#
# WHAT IS PROFILED BY DEFAULT. The fixed-work benchmark, because it is the one
# workload that is identical from run to run: a checked-in genome over a fixed
# roster-spanning task list, single threaded, with no duty governor and no
# nice. Profiling the real loop instead needs --run, and needs the governor
# disabled, or half the samples land in the supervisor's sleep.
#
# Usage:
#   scripts/mario/profile.sh                     # the fixed-work benchmark
#   scripts/mario/profile.sh --repetitions 2     # fewer replays, shorter trace
#   scripts/mario/profile.sh --rate 2000         # finer sampling
#   scripts/mario/profile.sh --run               # a throwaway training run
#   scripts/mario/profile.sh --run --episodes 4000 --workers 4
#   scripts/mario/profile.sh --no-open           # write the profile, do not serve
#
# Anything after the recognised flags is passed straight to melee-mario.
#
# macOS: samply needs to sample another process, which the first run authorises
# by asking for your password. Nothing is installed and nothing persists.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
samply="${SAMPLY:-$HOME/.cargo/bin/samply}"
binary="$root/rust/target/profiling/melee-mario"

rate=1000
mode="bench"
open=1
passthrough=()

while [ $# -gt 0 ]; do
  case "$1" in
    --run)
      mode="run"
      shift
      ;;
    --rate)
      if [ $# -lt 2 ]; then
        echo "profile.sh: --rate needs a number" >&2
        exit 2
      fi
      rate="$2"
      shift 2
      ;;
    --no-open)
      open=0
      shift
      ;;
    -h|--help)
      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      passthrough+=("$1")
      shift
      ;;
  esac
done

if [ ! -x "$samply" ]; then
  echo "profile.sh: samply is not at $samply." >&2
  echo "            Install it with 'cargo install samply', or set SAMPLY to its path." >&2
  exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "profile.sh: written for macOS; on Linux samply also needs" >&2
  echo "            /proc/sys/kernel/perf_event_paranoid to be 1 or lower." >&2
fi

# Frame pointers cannot be set per profile in Cargo.toml (there is no stable
# per-profile rustflags), so they are forced here. Without them the aarch64 ABI
# omits the frame pointer for some leaf functions and samply's stacks go wrong
# inside exactly the tight loops worth profiling.
export RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes"

echo "profile.sh: building melee-mario with the profiling profile" >&2
(cd "$root/rust" && cargo build --profile profiling -p melee-mario >&2)

if [ ! -x "$binary" ]; then
  echo "profile.sh: $binary is missing after the build" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out_dir="$root/artifacts/profiling"
mkdir -p "$out_dir"
profile="$out_dir/$mode-$stamp.json.gz"

if [ "$mode" = "bench" ]; then
  target=(bench --root "$root")
  # One replay of the fixed list runs for a fraction of a second, which at
  # 1000 Hz is a couple of hundred samples and far too few to attribute
  # anything to. More replays are more samples of the SAME work, which is
  # exactly what a profile wants. The operator's own --repetitions wins.
  case " ${passthrough[*]-} " in
    *" --repetitions "*) ;;
    *) target+=(--repetitions 40) ;;
  esac
else
  # A throwaway run directory, never a trajectory anyone cares about: a
  # profiling build is a different executable, so its build fingerprint
  # differs and resuming a real run under it would need --allow-rebuild and
  # would write "resumed with a different evaluator" into that run's history.
  #
  # --duty 1 makes the governor's owed rest zero, so no sample lands in
  # std::thread::sleep. --no-server keeps the dashboard's serialisation out of
  # the profile. Start at --workers 1 so every sample is on one stack and the
  # attribution is clean, then re-run with the real worker count to see what
  # the pool itself costs.
  target=(start --root "$root" --run "profiling-$stamp" --no-server \
          --duty 1 --workers 1 --nice 0 --episodes 2000)
fi

echo "profile.sh: recording at ${rate} Hz" >&2
# Recorded with --save-only unconditionally, so the profile is on disk before
# anything opens a browser: a viewer that fails to start must not cost the
# operator the run they just waited for.
"$samply" record --rate "$rate" --save-only --output "$profile" \
  -- "$binary" "${target[@]}" "${passthrough[@]+"${passthrough[@]}"}"

echo >&2
echo "profile.sh: profile written to $profile" >&2
echo "profile.sh: open it with" >&2
echo "              $samply load $profile" >&2
echo "profile.sh: in the viewer, turn on 'Invert call stack' to find the" >&2
echo "            self-time hot spots, and expand inlined frames to see through" >&2
echo "            thin LTO. Attribution only: quote magnitudes from" >&2
echo "            'scripts/mario/run.sh bench' on the release build." >&2

if [ "$open" -eq 1 ]; then
  exec "$samply" load "$profile"
fi
