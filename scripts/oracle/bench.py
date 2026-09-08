#!/usr/bin/env python3
"""Like-for-like throughput benchmark: Elm kernel vs Rust port.

Both sides run the identical workload (tests/Oracle/Bench.elm and the
oracle_bench bin) and print the same checksums, so a faster run that quietly
did less work shows up as a checksum mismatch rather than as a win.

Process startup is measured separately and subtracted, because the Elm kernel
pays a node boot that the real trainer pays once per worker, not per fight.
"""

import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPS = 7


def timed(cmd):
    """Best-of-REPS wall time in ms, plus the command's stdout."""
    best = float("inf")
    out = ""
    for _ in range(REPS):
        start = time.perf_counter()
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        elapsed = (time.perf_counter() - start) * 1000.0
        if proc.returncode != 0:
            raise SystemExit(f"{' '.join(cmd)} failed:\n{proc.stderr[-500:]}")
        best = min(best, elapsed)
        out = proc.stdout.strip()
    return best, out


def elm(bundle):
    return ["node", "scripts/oracle/run-elm-oracle.js", f"artifacts/oracle/{bundle}", "Oracle.Bench"]


def rust(mode):
    return ["./rust/target/release/oracle_bench", mode]


def main():
    node_floor, _ = timed(["node", "-e", "0"])
    rust_floor, _ = timed(rust("none"))

    rows = []
    for label, elm_cmd, rust_cmd in [
        ("velocity", elm("bench_vel.js"), rust("velocity")),
        ("mask", elm("bench_mask.js"), rust("mask")),
        ("both", elm("bench.js"), rust("both")),
    ]:
        e_ms, e_out = timed(elm_cmd)
        r_ms, r_out = timed(rust_cmd)
        e_net = max(e_ms - node_floor, 0.001)
        r_net = max(r_ms - rust_floor, 0.001)
        same = sorted(e_out.split("\n")) == sorted(o for o in r_out.split("\n") if o)
        rows.append((label, e_net, r_net, e_net / r_net, same))

    print(f"process floor: node {node_floor:.1f} ms, rust {rust_floor:.1f} ms (subtracted)")
    print(f"{'component':10} {'elm ms':>9} {'rust ms':>9} {'speedup':>9}  checksums")
    for label, e, r, ratio, same in rows:
        print(f"{label:10} {e:9.1f} {r:9.2f} {ratio:8.0f}x  {'match' if same else 'MISMATCH'}")


if __name__ == "__main__":
    main()
