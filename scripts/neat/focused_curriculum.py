#!/usr/bin/env python3
"""Persistent varied-seed lessons, fresh expansion gates and guarded promotion."""
import argparse
import collections
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def read(path):
    return json.loads(Path(path).read_text())


def seeds(label, count=20):
    # Disjoint from the sampler's 1..999,999,999 training namespace.
    domain = label.rsplit(":", 1)[-1]
    lower, width = {"validation": (1_000_000_000, 100_000_000),
                    "audit": (1_200_000_000, 400_000_000),
                    "confirmation": (1_700_000_000, 400_000_000)}.get(domain, (1_100_000_000, 100_000_000))
    start = lower + int.from_bytes(hashlib.sha256(label.encode()).digest()[:8], "big") % (width - count)
    return list(range(start, start + count))


def lesson_score(result, pairs):
    if len(result["scenarios"]) != len(result["flags"]):
        raise ValueError("Audit scenario and outcome counts differ")
    wanted = {tuple(pair) for pair in pairs}
    counts = collections.defaultdict(lambda: [0, 0])
    for record, won in zip(result["scenarios"], result["flags"]):
        pair = (record["us"], record["them"])
        if pair in wanted:
            counts[pair][0] += bool(won)
            counts[pair][1] += 1
    if set(counts) != wanted or any(n == 0 for _, n in counts.values()):
        raise ValueError("Audit does not cover every lesson")
    wins = sum(w for w, _ in counts.values())
    fights = sum(n for _, n in counts.values())
    return {"wins": wins, "fights": fights,
            "pair_fights": sorted((pair, n) for pair, (_, n) in counts.items()),
            "minimum_pair_rate": min(w / n for w, n in counts.values())}


def lesson_passes(candidate, reference, pairs):
    c, r = lesson_score(candidate, pairs), lesson_score(reference, pairs)
    new, old = lesson_score(candidate, pairs[-1:]), lesson_score(reference, pairs[-1:])
    learned = ((new["wins"] - old["wins"]) * 10 >= new["fights"] or
               (old["wins"] * 10 >= 6 * old["fights"] and new["wins"] >= old["wins"]))
    return (c["pair_fights"] == r["pair_fights"] and c["wins"] * 10 >= 6 * c["fights"]
            and c["minimum_pair_rate"] >= .4
            and new["wins"] * 10 >= 6 * new["fights"] and learned)


def broad_passes(results, confirmation=False):
    margin = 0 if confirmation else 8
    c = results["candidate"]
    return all(c["fights"] == results[name]["fights"] and
               (c["wins"] > results[name]["wins"] if confirmation else
                c["wins"] >= results[name]["wins"] + margin)
               for name in ["original", "live"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("/home/schalk/git/uqm-melee"))
    parser.add_argument("--batch", type=int, default=200)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--no-promote", action="store_true", help="Exercise audits without changing live deployment")
    args = parser.parse_args()
    if args.batch < 1:
        parser.error("batch must be positive")
    art = args.root / "artifacts/neat"
    home = art / "focused"
    release = art / "releases/focused-v1"
    monitor = art / "releases/monitor-v1/scripts/neat"
    worker = art / "releases/scoring-v1/rust/target/release/melee-worker"
    home.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(monitor))
    from experiment import atomic_json, digest
    from review_audit import audit
    env = {**os.environ, "NEAT_WORKERS": "2", "OPENBLAS_NUM_THREADS": "1", "OMP_NUM_THREADS": "1"}
    state_path = home / "state.json"
    state = read(state_path) if state_path.exists() else {}

    def save(phase, **fields):
        state.update(enabled=True, phase=phase, updated=time.time(), error="", **fields)
        atomic_json(state_path, state)
        print(json.dumps({k: state.get(k) for k in ["phase", "stage", "attempt", "target_generations", "last_result"]}), flush=True)

    def live_run():
        return Path(read(art / "active-run.json")["run"])

    def paused():
        return read(args.root / "scripts/neat/hints.json").get("pause", True)

    def train_run(run, initial, config, target):
        run.mkdir(parents=True, exist_ok=True)
        if not (run / "hints.json").exists():
            atomic_json(run / "initial.json", initial)
            atomic_json(run / "hints.json", config)
        elif read(run / "hints.json") != config:
            raise ValueError("Refusing to resume with changed lesson configuration")
        command = [sys.executable, str(release / "scripts/neat/train.py"),
                   "--artifacts", str(run), "--hints", str(run / "hints.json"),
                   "--initial", str(run / "initial.json"), "--control", str(args.root / "scripts/neat/hints.json"),
                   "--evaluator", "rust", "--rust-worker", str(worker), "--scoring-version", "combat-v1",
                   "--no-dashboard", "--generations", str(target)]
        with (run / "run.log").open("a") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, env=env)
        progress = read(run / "status.json")
        if progress.get("phase") != "complete" or progress["generation"] != target:
            raise RuntimeError(f"Lesson trainer failed: {progress.get('error', progress.get('phase'))}")
        return read(run / "best.json")

    def audits(path, label, policies, pool, selected_seeds):
        file = path / (label + ".json")
        key = {"weights": {k: digest(v["weights"]) for k, v in policies.items()}, "seeds": selected_seeds}
        if file.exists():
            saved = read(file)
            if saved["inputs"] == key:
                return saved["results"]
            raise ValueError("Attempt to reuse an audit with different inputs")
        cache, results = {}, {}
        for name, policy in policies.items():
            hashed = digest(policy["weights"])
            if hashed not in cache:
                cache[hashed] = audit(worker, policy["weights"], pool, selected_seeds)
            results[name] = cache[hashed]
        atomic_json(file, {"inputs": key, "results": results})
        return results

    def promote(candidate, current, current_run, path, config):
        current_config = read(current_run / "manifest.json")["provenance"]["config"]
        if (current_config["pool"] != config["pool"] or
                current_config.get("opponent_pool", current_config["pool"]) != config["pool"]):
            return "live roster changed; candidate lacks full coverage"
        # Stage validation is not the 54-fight production score. Re-score explicitly.
        fixed = audits(path, "fixed", {"candidate": candidate, "live": current}, config["pool"], config["hold_seeds"])
        if fixed["candidate"]["wins"] < fixed["live"]["wins"]:
            return "fixed validation regression"
        out = path / "promotion"
        broad = {**config, "training_pairs": state["pair_order"], "focused_full_validation": True,
                 "fresh_seed_base": seeds(str(path) + ":live", 1)[0]}
        # Preserve the exact tested weights as the live initial champion. Starting
        # the normal service scores them before its first update.
        out.mkdir(exist_ok=True)
        atomic_json(out / "initial.json", candidate)
        atomic_json(out / "hints.json", broad)
        if paused() or live_run() != current_run or digest(read(current_run / "best.json")["weights"]) != digest(current["weights"]):
            return "live champion changed or training paused"
        deployment = art / "deployment.json"
        previous = read(deployment)
        atomic_json(path / "previous-deployment.json", previous)
        atomic_json(deployment, {"release": str(release), "worker": str(worker), "run": str(out),
                                 "hints": str(out / "hints.json"), "initial": str(out / "initial.json")})
        try:
            subprocess.run(["bash", str(monitor / "start.sh")], check=True, timeout=100, stdout=subprocess.DEVNULL)
            if live_run() != out or subprocess.run(["systemctl", "--user", "is-active", "--quiet", "uqm-neat.service"]).returncode:
                raise RuntimeError("Promoted trainer failed to start")
        except Exception:
            atomic_json(deployment, previous)
            subprocess.run(["bash", str(monitor / "start.sh")], check=True, timeout=100, stdout=subprocess.DEVNULL)
            raise
        return "promoted"

    try:
        with (home / "controller.lock").open("a") as own_lock:
            fcntl.flock(own_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            while True:
                if paused():
                    save("paused")
                    if args.once:
                        return
                    time.sleep(10)
                    continue
                with (art / "reviews/review.lock").open("a") as review_lock:
                    try:
                        fcntl.flock(review_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        save("waiting")
                        if args.once:
                            return
                        time.sleep(10)
                        continue
                    if "original" not in state:
                        live = live_run()
                        config = read(live / "manifest.json")["provenance"]["config"]
                        if config["pool"] != ["Pkunk", "Umgah", "Yehat"] or config.get("opponent_pool", config["pool"]) != config["pool"]:
                            raise ValueError("Focused lessons require the existing three-by-three roster")
                        atomic_json(home / "original.json", read(live / "best.json"))
                        # First two are the demonstrated learnable losing matchups.
                        first = [["Pkunk", "Umgah"], ["Umgah", "Pkunk"]]
                        order = first + [[a, b] for a in config["pool"] for b in config["pool"] if [a, b] not in first]
                        state.update(original=str(home / "original.json"), base_config=config, stage=0, attempt=0,
                                     pair_order=order, initial=str(home / "original.json"), target_generations=args.batch,
                                     last_candidate_hash="", run=None)
                    stage, attempt = state["stage"], state["attempt"]
                    pairs = state["pair_order"][:stage + 1]
                    run = home / f"stage-{stage:02d}" / f"attempt-{attempt:03d}"
                    stage_reference_path = run.parent / "reference.json"
                    run.parent.mkdir(parents=True, exist_ok=True)
                    if not stage_reference_path.exists():
                        atomic_json(stage_reference_path, read(state["initial"]))
                    config = dict(state["base_config"])
                    config.pop("opponent_pool", None)
                    config.pop("practice_pairs", None)
                    config.pop("focused_full_validation", None)
                    config.update(training_pairs=pairs, validation_seeds=seeds(str(run) + ":validation", 8),
                                  fresh_seed_base=seeds(str(run) + ":train", 1)[0], seed=seeds(str(run) + ":noise", 1)[0],
                                  pop=32, sigma=[.04, .08, .12][attempt % 3], lr=.1, search="es", auto_expand=False,
                                  pause=False, notes="Focused lessons; fresh training seeds and both seats")
                    target = state["target_generations"]
                    save("training", run=str(run), active_pairs=pairs)
                    candidate = train_run(run, read(state["initial"]), config, target)
                    candidate_hash = digest(candidate["weights"])
                    passed = False
                    result = {"stage": stage, "generation": target, "validation_wins": candidate["seat_wins"],
                              "validation_fights": len(candidate["scenarios"]), "decision": "continue"}
                    if candidate_hash != state["last_candidate_hash"]:
                        save("audit")
                        path = run / f"check-{target:06d}"
                        path.mkdir(exist_ok=True)
                        # Freeze references before opening either fresh audit.
                        refs_path = path / "references.json"
                        if not refs_path.exists():
                            live = live_run()
                            atomic_json(refs_path, {"run": str(live), "live": read(live / "best.json")})
                        refs = read(refs_path)
                        policies = {"candidate": candidate, "reference": read(stage_reference_path),
                                    "original": read(state["original"]), "live": refs["live"]}
                        a = audits(path, "audit", policies, config["pool"], seeds(str(path) + ":audit"))
                        score = lesson_score(a["candidate"], pairs)
                        result.update(fresh_wins=score["wins"], fresh_fights=score["fights"],
                                      broad_wins=a["candidate"]["wins"], broad_live_wins=a["live"]["wins"], broad_fights=a["candidate"]["fights"])
                        first_pass = lesson_passes(a["candidate"], a["reference"], pairs)
                        broad_pass = broad_passes(a)
                        if first_pass or broad_pass:
                            b = audits(path, "confirmation", policies, config["pool"], seeds(str(path) + ":confirmation"))
                            passed = first_pass and lesson_passes(b["candidate"], b["reference"], pairs)
                            confirmed = lesson_score(b["candidate"], pairs)
                            result.update(confirmation_wins=confirmed["wins"], confirmation_fights=confirmed["fights"])
                            if broad_pass and broad_passes(b, confirmation=True) and not args.no_promote:
                                result["promotion"] = promote(candidate, refs["live"], Path(refs["run"]), path, config)
                                if result["promotion"] == "promoted":
                                    result["decision"] = "promoted; continue lesson"
                        atomic_json(path / "result.json", result)
                    state["last_candidate_hash"] = candidate_hash
                    if passed and stage + 1 < len(state["pair_order"]):
                        state.update(stage=stage + 1, attempt=0, initial=str(run / "best.json"),
                                     target_generations=args.batch, last_candidate_hash="", run=None)
                        result["decision"] = "expanded lesson"
                    elif target >= 1000:
                        # Recenter on the saved policy and try a different mutation
                        # scale and validation panel instead of drifting indefinitely.
                        state.update(attempt=attempt + 1, initial=str(run / "best.json"),
                                     target_generations=args.batch, last_candidate_hash="", run=None)
                        result["decision"] = "restart from best with new seeds and mutation scale"
                    else:
                        state["target_generations"] += args.batch
                    with (home / "checks.jsonl").open("a") as log:
                        log.write(json.dumps({"at": time.time(), **result}) + "\n")
                    save("waiting", last_result=result)
                if args.once:
                    return
    except Exception as error:
        state.update(enabled=True, phase="error", error=str(error), updated=time.time())
        atomic_json(state_path, state)
        raise


if __name__ == "__main__":
    main()
