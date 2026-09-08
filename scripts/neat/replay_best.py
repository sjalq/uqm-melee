#!/usr/bin/env python3
"""Replay artifacts/neat/best.json both seats on several seeds."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from layout import N_WEIGHTS  # noqa: E402
from score import is_our_win  # noqa: E402

BEST = ROOT / "artifacts" / "neat" / "best.json"
WORKER = HERE / "worker.js"


def eval_one(proc, weights, seed, ticks, swap):
    job = json.dumps({"weights": weights, "seed": int(seed), "ticks": int(ticks), "swap": bool(swap)})
    proc.stdin.write(job + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("worker empty stdout")
    return json.loads(line)


def main():
    args = [int(x) for x in sys.argv[1:]]
    ticks = 1800
    if args and args[0] > 10000:
        ticks = args.pop(0)
    seeds = args or [1701, 2137, 7]
    if not BEST.exists():
        print(json.dumps({"error": "no best.json"}))
        return 2
    data = json.loads(BEST.read_text())
    weights = data.get("weights")
    if not isinstance(weights, list) or len(weights) != N_WEIGHTS:
        print(json.dumps({"error": f"best.json length {0 if not isinstance(weights, list) else len(weights)} want {N_WEIGHTS}"}))
        return 2
    p = subprocess.Popen(
        ["node", str(WORKER)],
        cwd=str(ROOT),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    fights = []
    try:
        for seed in seeds:
            for swap in (False, True):
                rec = eval_one(p, weights, seed, ticks, swap)
                rec["us"] = "top" if swap else "bottom"
                fights.append(rec)
    finally:
        p.stdin.close()
        p.terminate()
    ok = [is_our_win(rec, rec.get("us"), ticks) for rec in fights]
    out = {
        "n_weights": N_WEIGHTS,
        "generation": data.get("generation"),
        "saved_fitness": data.get("fitness"),
        "ticks": ticks,
        "seeds": seeds,
        "fights": fights,
        "dual_seat_wins": all(ok),
        "passed": sum(1 for x in ok if x),
        "total": len(ok),
    }
    print(json.dumps(out))
    return 0 if out["dual_seat_wins"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
