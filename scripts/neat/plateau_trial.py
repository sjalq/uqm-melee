#!/usr/bin/env python3
"""One frozen, equal-fight plateau comparison; independent final confirmation."""
import argparse
import collections
import fcntl
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import time


def read(path):
    return json.loads(Path(path).read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("/home/schalk/git/uqm-melee"))
    parser.add_argument("--name", default="plateau-v1")
    args = parser.parse_args()
    root = args.root
    art = root / "artifacts/neat"
    monitor = art / "releases/monitor-v1/scripts/neat"
    release = art / "releases/plateau-v1"
    path = art / "experiments" / args.name
    path.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(monitor))
    from experiment import atomic_json, digest
    from review_audit import audit
    from score import scenario_win
    worker = art / "releases/scoring-v1/rust/target/release/melee-worker"
    timer = ["systemctl", "--user"]
    timer_was_active = subprocess.run(timer + ["is-active", "--quiet", "uqm-review.timer"]).returncode == 0
    state = {"experiment": args.name, "phase": "preparing", "started": time.time()}
    def phase(value, **fields):
        state.update(phase=value, **fields)
        atomic_json(path / "status.json", state)
        print(json.dumps(state), flush=True)
    def live_run():
        return Path(read(art / "active-run.json")["run"])
    def audit_many(policies, seeds):
        cache, result = {}, {}
        for label, policy in policies.items():
            key = digest(policy["weights"])
            if key not in cache:
                cache[key] = audit(worker, policy["weights"], config["pool"], seeds)
            result[label] = cache[key]
        return result
    def train(label, hints, generations):
        out = path / label
        out.mkdir()
        atomic_json(out / "initial.json", original)
        atomic_json(out / "hints.json", hints)
        phase("training", arm=label, target_generations=generations)
        command = [sys.executable, str(release / "scripts/neat/train.py"),
                   "--artifacts", str(out), "--hints", str(out / "hints.json"),
                   "--initial", str(out / "initial.json"), "--evaluator", "rust",
                   "--rust-worker", str(worker), "--scoring-version", "combat-v1",
                   "--control", str(root / "scripts/neat/hints.json"),
                   "--no-dashboard", "--generations", str(generations)]
        with (out / "run.log").open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1800,
                           env={**os.environ, "NEAT_WORKERS": "2", "OPENBLAS_NUM_THREADS": "1", "OMP_NUM_THREADS": "1"})
        rows = [json.loads(line) for line in (out / "metrics.jsonl").read_text().splitlines()]
        budget = len(read(out / "baseline.json")["scenarios"]) + sum(r["train_fights"] + r["n_train"] + r["n_hold"] for r in rows)
        if len(rows) != generations or budget != 44145:
            raise RuntimeError(f"{label}: expected {generations} generations / 44145 fights, got {len(rows)} / {budget}")
        return read(out / "best.json"), budget
    try:
        with (art / "reviews/review.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if read(root / "scripts/neat/hints.json").get("pause", True):
                raise RuntimeError("Training is intentionally paused")
            subprocess.run(timer + ["stop", "uqm-review.timer"], check=True)
            initial_run = live_run()
            original = read(initial_run / "best.json")
            provenance = read(initial_run / "manifest.json")["provenance"]
            config = dict(provenance["config"])
            if config["pool"] != ["Pkunk", "Umgah", "Yehat"] or config.get("opponent_pool", config["pool"]) != config["pool"]:
                raise RuntimeError("Roster changed; this budget assumes the current three-by-three pool")
            if provenance.get("scoring_version") != "combat-v1":
                raise RuntimeError("Unexpected scoring version")
            rng = random.Random(2026090919)
            training_seeds = rng.sample(range(1100000000, 1200000000), 3)
            diagnostic_seeds = rng.sample(range(1200000000, 1300000000), 5)
            audit_seeds = rng.sample(range(1300000000, 1400000000), 20)
            final_seeds = rng.sample(range(1500000000, 1600000000), 40)
            atomic_json(path / "final-seeds.json", final_seeds)
            atomic_json(path / "starting-champion.json", original)
            phase("diagnosis")
            diagnostic = audit_many({"starting": original}, diagnostic_seeds)["starting"]
            atomic_json(path / "diagnostic.json", {"seeds": diagnostic_seeds, **diagnostic})
            groups = collections.defaultdict(list)
            for record in diagnostic["scenarios"]:
                groups[(record["us"], record["them"])].append(record)
            diagnosis = []
            for pair, records in groups.items():
                wins = sum(scenario_win(r, 1800) for r in records)
                diagnosis.append({"pair": list(pair), "wins": wins, "fights": len(records),
                                  "mean_damage": sum(r["damage"] for r in records) / len(records),
                                  "mean_hurt": sum(r["hurt"] for r in records) / len(records),
                                  "timeouts": sum(r["outcome"] != "completed" for r in records)})
            diagnosis.sort(key=lambda r: (r["wins"] / r["fights"], r["mean_damage"], r["pair"]))
            weak_pairs = [r["pair"] for r in diagnosis[:3]]
            atomic_json(path / "diagnosis-summary.json", {"matchups": diagnosis, "practice_pairs": weak_pairs})
            # Save two actual losing replays for examining behavior, not just scores.
            replay_summaries = []
            for index, pair in enumerate(weak_pairs[:2]):
                loss = next(r for r in groups[tuple(pair)] if not scenario_win(r, 1800))
                job = {k: loss[k] for k in ["seed", "swap", "us", "them"]}
                job.update(weights=original["weights"], ticks=1800, rating="awesome", foe="cyborg", scoring="combat-v1", trace=True)
                trace_path = path / f"loss-{index}.jsonl"
                with trace_path.open("w") as out:
                    subprocess.run([str(worker)], input=json.dumps(job)+"\n", text=True, stdout=out, check=True, timeout=90)
                samples = collections.Counter()
                side = "top" if loss["swap"] else "bottom"
                with trace_path.open() as trace:
                    for line in trace:
                        event = json.loads(line)
                        policy = event.get("policy")
                        if isinstance(policy, dict) and side in policy:
                            control = policy[side].get("input", {})
                            samples["decisions"] += 1
                            for key in ["thrust", "weapon", "special"]:
                                samples[key] += bool(control.get(key))
                replay_summaries.append({"pair": pair, "result": loss, "controls": dict(samples), "trace": str(trace_path)})
            atomic_json(path / "loss-replays.json", replay_summaries)
            config.update(pop=16, seed=2026090919, train_seeds=training_seeds, pause=False, auto_expand=False, practice_pairs=[])
            arms = {"control": (dict(config), 213), "population64": ({**config, "pop": 64}, 69),
                    "targeted": ({**config, "practice_pairs": weak_pairs}, 213)}
            plan = {"initial_run": str(initial_run), "starting_weight_hash": digest(original["weights"]),
                    "arms": {name: {"hints": hints, "generations": n, "fights": 44145} for name, (hints, n) in arms.items()},
                    "diagnostic_seeds": diagnostic_seeds, "audit_seeds": audit_seeds,
                    "final_seed_commitment": digest(final_seeds), "final_test_used_for_selection": False,
                    "selection_rule": "At least 8 extra wins over control in 360 fresh fights, no fixed-validation regression against control or starting champion; select at most one candidate.",
                    "confirmation_rule": "Selected candidate must strictly beat control, starting and current live champion on 720 untouched paired fights and retain fixed-validation wins. Never test the runner-up after seeing final results.",
                    "worker_sha256": hashlib.sha256(worker.read_bytes()).hexdigest()}
            atomic_json(path / "plan.json", plan)
            policies, budgets = {"starting": original}, {}
            for label, (hints, n) in arms.items():
                policies[label], budgets[label] = train(label, hints, n)
            phase("selection_audit", budgets=budgets)
            result = audit_many(policies, audit_seeds)
            atomic_json(path / "audit.json", {"seeds": audit_seeds, **result})
            eligible = [name for name in ["population64", "targeted"]
                        if result[name]["wins"] >= result["control"]["wins"] + 8
                        and policies[name]["seat_wins"] >= max(original["seat_wins"], policies["control"]["seat_wins"])]
            evidence = {"experiment": args.name, "budgets": budgets, "audit_wins": {k: v["wins"] for k,v in result.items()},
                        "audit_fights": 360, "fixed_validation_wins": {k:v["seat_wins"] for k,v in policies.items()},
                        "decision": "rejected", "final_test_opened": False, "diagnosis": diagnosis}
            if eligible:
                winner = max(eligible, key=lambda name: (result[name]["wins"], result[name]["fitness"]))
                phase("final_confirmation", selected=winner)
                current_run = live_run(); current = read(current_run / "best.json")
                final = audit_many({"candidate": policies[winner], "control": policies["control"], "starting": original, "live": current}, final_seeds)
                atomic_json(path / "final-audit.json", {"seeds": final_seeds, **final})
                evidence.update(selected=winner, final_test_opened=True, final_wins={k:v["wins"] for k,v in final.items()}, final_fights=720)
                passed = all(final["candidate"]["wins"] > final[name]["wins"] for name in ["control", "starting", "live"]) and policies[winner]["seat_wins"] >= current["seat_wins"]
                if passed and (live_run() != current_run or digest(read(current_run / "best.json")["weights"]) != digest(current["weights"])):
                    evidence["decision"] = "qualified but live champion changed; no deployment"
                elif passed:
                    phase("deploying", selected=winner)
                    deployment = art / "deployment.json"
                    previous = read(deployment) if deployment.exists() else None
                    atomic_json(path / "previous-deployment.json", previous)
                    out = path / winner
                    atomic_json(deployment, {"release": str(release), "worker": str(worker), "run": str(out), "hints": str(out/"hints.json"), "initial": str(out/"initial.json")})
                    try:
                        subprocess.run(["bash", str(monitor / "start.sh")], check=True, timeout=100, stdout=subprocess.DEVNULL)
                        if live_run() != out or subprocess.run(timer + ["is-active", "--quiet", "uqm-neat.service"]).returncode:
                            raise RuntimeError("New run did not become live")
                        evidence["decision"] = "deployed"
                    except Exception:
                        if previous is None: deployment.unlink(missing_ok=True)
                        else: atomic_json(deployment, previous)
                        subprocess.run(["bash", str(monitor / "start.sh")], check=True, timeout=100, stdout=subprocess.DEVNULL)
                        raise
            evidence["finished"] = time.time()
            atomic_json(path / "result.json", evidence)
            with (art / "reviews/review-findings.jsonl").open("a") as journal:
                journal.write(json.dumps({"at": time.time(), "experiment": args.name, "result": str(path/"result.json"), "decision": evidence["decision"], "audit_wins": evidence["audit_wins"]})+"\n")
            phase("complete", decision=evidence["decision"], audit_wins=evidence["audit_wins"])
    except Exception as error:
        phase("error", error=str(error))
        raise
    finally:
        if timer_was_active:
            subprocess.run(timer + ["start", "uqm-review.timer"], check=True)


if __name__ == "__main__":
    main()
