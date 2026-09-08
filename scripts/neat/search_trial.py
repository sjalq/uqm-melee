#!/usr/bin/env python3
"""Equal-evaluation-budget search comparison using the production trainer."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from experiment import atomic_json, checked_weights
from score import cvar_mean, scenario_win

HERE = Path(__file__).resolve().parent
AUDIT_SEEDS = [10007, 20011, 30013, 40009, 50021, 60013, 70001, 80021, 90001, 100003,
               110017, 120011, 130003, 140009, 150001, 160001, 170003, 180001, 190027, 200003]


def audit(worker, weights, pool, seeds):
    jobs = [{"weights": weights, "seed": seed, "ticks": 1800, "swap": swap,
             "rating": "awesome", "us": us, "them": them, "foe": "cyborg", "scoring": "combat-v1"}
            for us in pool for them in pool for seed in seeds for swap in [False, True]]
    completed = subprocess.run([str(worker)], input="".join(json.dumps(j) + "\n" for j in jobs),
                               text=True, capture_output=True, check=True, timeout=120)
    records = [json.loads(line) for line in completed.stdout.splitlines()]
    if len(records) != len(jobs) or any(r.get("error") or r.get("scoring_version") != "combat-v1" for r in records):
        raise RuntimeError("audit evaluator failed")
    flags = [scenario_win(r, 1800) for r in records]
    return {"wins": sum(flags), "fights": len(flags), "fitness": cvar_mean([r["fitness"] for r in records]),
            "flags": flags, "scenarios": records}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--initial", type=Path, required=True)
    p.add_argument("--hints", type=Path, required=True)
    p.add_argument("--worker", type=Path, required=True)
    p.add_argument("--baseline-from", type=Path)
    p.add_argument("--stage", choices=["single", "full"], required=True)
    p.add_argument("--generations", type=int, default=160)
    p.add_argument("--seed", type=int, default=20260909)
    p.add_argument("--revision", type=int, default=1)
    args = p.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    initial = json.loads(args.initial.read_text())
    weights = checked_weights(initial)
    frozen = args.root / "initial.json"
    if frozen.exists() and json.loads(frozen.read_text())["weights"] != weights:
        raise ValueError("initial policy changed")
    atomic_json(frozen, initial)
    base = json.loads(args.hints.read_text())
    base.update({"pool": ["Yehat"] if args.stage == "single" else ["Pkunk", "Umgah", "Yehat"],
                 "seed": args.seed, "pop": 16, "auto_expand": False, "pause": False})
    seeds = [seed + (args.revision - 1) * 1000000 for seed in AUDIT_SEEDS]
    results = {}
    for mode in ["block_es", "population"]:
        arm = args.root / mode
        arm.mkdir(exist_ok=True)
        hints = {**base, "search": mode}
        if mode == "population":
            hints["population_revision"] = args.revision
        hint_path = arm / "hints.json"
        atomic_json(hint_path, hints)
        print(f"START {args.stage} {mode} generations={args.generations}", flush=True)
        command = [sys.executable, str(HERE / "train.py"), "--artifacts", str(arm),
                   "--hints", str(hint_path), "--initial", str(frozen), "--evaluator", "rust",
                   "--rust-worker", str(args.worker), "--scoring-version", "combat-v1",
                   "--no-dashboard", "--generations", str(args.generations)]
        started = time.monotonic()
        training_arm = args.baseline_from if mode == "block_es" and args.baseline_from else arm
        if training_arm == arm:
            with (arm / "run.log").open("a") as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True,
                               env={**os.environ, "NEAT_WORKERS": "2", "OPENBLAS_NUM_THREADS": "1", "OMP_NUM_THREADS": "1"})
        else:
            original = json.loads((training_arm / "manifest.json").read_text())
            if original["initial_sha256"] != __import__("experiment").digest(weights):
                raise ValueError("cached baseline used different starting weights")
            actual = json.loads((training_arm / "checkpoint.json").read_text())
            if actual["generation"] != args.generations:
                raise ValueError("cached baseline used a different generation budget")
            expected_config = original["provenance"]["config"]
            if any(expected_config.get(k) != hints[k] for k in ["pool", "seed", "pop", "search", "sigma", "lr", "train_seeds", "hold_seeds", "episode_ticks"]):
                raise ValueError("cached baseline configuration differs")
        champion = json.loads((training_arm / "best.json").read_text())
        evaluation = audit(args.worker, champion["weights"], base["pool"], seeds)
        atomic_json(arm / "audit.json", evaluation)
        rows = [json.loads(line) for line in (training_arm / "metrics.jsonl").read_text().splitlines()]
        fights = len(json.loads((training_arm / "baseline.json").read_text())["scenarios"]) + sum((16 + 1) * row["n_train"] + row["n_hold"] for row in rows)
        results[mode] = {"audit_wins": evaluation["wins"], "audit_fights": evaluation["fights"],
                         "validation_wins": champion["seat_wins"], "training_fights": fights,
                         "elapsed_seconds": time.monotonic() - started, "champion_generation": champion["generation"], "training_source": str(training_arm)}
        print(f"DONE {mode}: {json.dumps(results[mode])}", flush=True)
    before = json.loads((args.root / "block_es/audit.json").read_text())
    after = json.loads((args.root / "population/audit.json").read_text())
    assert results["block_es"]["training_fights"] == results["population"]["training_fights"]
    results["paired"] = {"gained": sum(b and not a for a, b in zip(before["flags"], after["flags"])),
                          "lost": sum(a and not b for a, b in zip(before["flags"], after["flags"]))}
    results["audit_seeds"] = seeds
    results["stage"] = args.stage
    atomic_json(args.root / "comparison.json", results)
    print(json.dumps(results), flush=True)


if __name__ == "__main__":
    main()
