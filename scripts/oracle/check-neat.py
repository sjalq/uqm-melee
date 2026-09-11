#!/usr/bin/env python3
"""Differential complete-episode checks against the existing Elm evaluator.

Uses persistent workers, identical JSON requests, strict discrete comparison and
1e-10 absolute tolerance for score arithmetic. It never accepts different game
outcomes, crew, ticks, or engagement intervals. Reports measured episode latency.
"""
import argparse
import hashlib
import json
import math
import random
import selectors
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/neat"))
from layout import ALL_SHIPS, N_WEIGHTS


class Worker:
    def __init__(self, command):
        self.proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.proc.stdout, selectors.EVENT_READ)

    def evaluate(self, job):
        started = time.perf_counter()
        self.proc.stdin.write(json.dumps(job, allow_nan=False) + "\n")
        self.proc.stdin.flush()
        if not self.selector.select(180):
            raise TimeoutError("evaluator failed to answer within 180 seconds")
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError(f"evaluator exited {self.proc.poll()}")
        result = json.loads(line)
        if "error" in result:
            raise ValueError(result["error"])
        return result, time.perf_counter() - started

    def close(self):
        self.selector.close()
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


def differences(expected, actual):
    result = {}
    floating = {"fitness", "damage", "hurt", "engage", "dense"}
    for key in sorted(set(expected) | set(actual)):
        a, b = expected.get(key), actual.get(key)
        equal = a == b
        if key in floating and isinstance(a, (int, float)) and isinstance(b, (int, float)):
            equal = math.isclose(a, b, rel_tol=0, abs_tol=1e-10)
        if not equal:
            result[key] = {"elm": a, "rust": b}
    return result


def jobs(args):
    rng = random.Random(20260908)
    policies = [[0.0] * N_WEIGHTS, [rng.gauss(0, 0.12) for _ in range(N_WEIGHTS)]]
    controls = [0.0] * N_WEIGHTS
    for output in (2, 3, 4):
        controls[16 * 57 + output * 17 + 16] = 1.0
    policies.append(controls)
    for path in args.weights:
        weights = json.loads(path.read_text())["weights"]
        if len(weights) != N_WEIGHTS or not all(type(w) in (int, float) and math.isfinite(w) for w in weights):
            raise ValueError(f"invalid weights: {path}")
        policies.append(weights)
    ships = ALL_SHIPS if args.matrix else ["Pkunk", "Umgah", "Yehat"]
    seeds = args.seeds or [42, 99, 1234, 1701, 2137, 7]
    index = 0
    for us in ships:
        for them in ships:
            for swap in (False, True):
                for rating in ("standard", "good", "awesome"):
                    pairs = [(seeds[index % len(seeds)], policies[index % len(policies)])] if args.matrix else [(seed, weights) for seed in seeds for weights in policies]
                    for seed, weights in pairs:
                        yield {"us": us, "them": them, "seed": seed, "swap": swap, "rating": rating, "ticks": args.ticks, "weights": weights, "foe": "cyborg"}
                    index += 1


def timing(samples):
    return {"max_s": max(samples), "mean_s": statistics.mean(samples), "median_s": statistics.median(samples), "min_s": min(samples), "total_s": sum(samples)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rust-worker", type=Path, default=ROOT / "rust/target/release/melee-worker")
    parser.add_argument("--elm-worker", type=Path, default=ROOT / "scripts/neat/worker.js")
    parser.add_argument("--weights", type=Path, action="append", default=[])
    parser.add_argument("--matrix", action="store_true", help="all 25 ordered hull pairs, both seats and every rating")
    parser.add_argument("--ticks", type=int, default=1800)
    parser.add_argument("--seeds", type=int, nargs="+")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    rust_sha256 = hashlib.sha256(args.rust_worker.read_bytes()).hexdigest()
    elm_sha256 = hashlib.sha256((args.elm_worker.parent / "kernel.js").read_bytes()).hexdigest()
    workers = []
    failures, times, count = [], {"elm": [], "rust": []}, 0
    try:
        elm = Worker(["node", str(args.elm_worker.resolve())]); workers.append(elm)
        rust = Worker([str(args.rust_worker.resolve())]); workers.append(rust)
        for job in jobs(args):
            # Alternate evaluation order to reduce systematic warm-up bias.
            if count % 2:
                actual, rt = rust.evaluate(job); expected, et = elm.evaluate(job)
            else:
                expected, et = elm.evaluate(job); actual, rt = rust.evaluate(job)
            count += 1
            times["elm"].append(et); times["rust"].append(rt)
            diff = differences(expected, actual)
            if diff:
                failures.append({"index": count - 1, "job": job, "differences": diff})
                print(f"mismatch {count}: {job['us']} vs {job['them']} seed {job['seed']} swap {job['swap']} {job['rating']}: {diff}", file=sys.stderr, flush=True)
            if count % 100 == 0:
                print(f"checked {count}; mismatches {len(failures)}", file=sys.stderr, flush=True)
    finally:
        for worker in workers:
            worker.close()
    report = {"checked": count, "mismatches": len(failures), "failures": failures,
              "rust_sha256": rust_sha256, "elm_sha256": elm_sha256,
              "binary_changed_during_check": hashlib.sha256(args.rust_worker.read_bytes()).hexdigest() != rust_sha256,
              "ticks": args.ticks, "matrix": args.matrix, "timing": {key: timing(values) for key, values in times.items()}}
    report["speedup"] = sum(times["elm"]) / sum(times["rust"])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, allow_nan=False) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "failures"}))
    return bool(failures) or report["binary_changed_during_check"]


if __name__ == "__main__":
    sys.exit(main())
