#!/usr/bin/env python3
"""Durable sequential experiment campaign for the Neat trainer."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from experiment import atomic_json, checked_weights, digest, result_key, source_hashes  # noqa: E402


active_child: subprocess.Popen | None = None
pending_signal: int | None = None
EVALUATOR = "elm"
RUST_WORKER = HERE.parents[1] / "rust" / "target" / "release" / "melee-worker"


def read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def validate_plan(data: dict) -> dict:
    common = data.get("common")
    arms = data.get("arms")
    audit_seeds = data.get("audit_seeds")
    if not isinstance(common, dict):
        raise ValueError("plan common must be an object")
    if not isinstance(arms, list) or not arms:
        raise ValueError("plan arms must be a non-empty array")
    if not isinstance(audit_seeds, list) or not audit_seeds:
        raise ValueError("plan audit_seeds must be a non-empty array")
    ids = set()
    normalized_arms = []
    for arm in arms:
        if not isinstance(arm, dict):
            raise ValueError("each plan arm must be an object")
        missing = {key for key in ("id", "search", "seed", "generations", "hypothesis", "source", "lane") if key not in arm}
        if missing:
            raise ValueError(f"arm is missing fields: {sorted(missing)}")
        arm_id = arm["id"]
        if not isinstance(arm_id, str) or not arm_id or Path(arm_id).name != arm_id or arm_id in (".", ".."):
            raise ValueError(f"invalid arm id {arm_id!r}")
        if arm_id in ids:
            raise ValueError(f"duplicate arm id {arm_id}")
        ids.add(arm_id)
        search = arm["search"]
        if search not in ("es", "block_es"):
            raise ValueError(f"arm {arm_id} search must be es or block_es")
        generations = int(arm["generations"])
        if generations < 1:
            raise ValueError(f"arm {arm_id} generations must be positive")
        normalized_arms.append({**arm, "seed": int(arm["seed"]), "generations": generations})
    seeds = [int(seed) for seed in audit_seeds]
    if len(set(seeds)) != len(seeds):
        raise ValueError("audit_seeds must be unique")
    used = {int(seed) for key in ("train_seeds", "hold_seeds") for seed in (common.get(key) or [])}
    if used & set(seeds):
        raise ValueError("audit_seeds must be fresh and disjoint from training and validation seeds")
    return {**data, "common": common, "arms": normalized_arms, "audit_seeds": seeds}


def arm_hints(plan: dict, arm: dict) -> dict:
    return {**plan["common"], "search": arm["search"], "seed": arm["seed"]}


def ensure_json(path: Path, expected: dict, label: str) -> None:
    if path.exists():
        actual = read_json(path)
        if digest(actual) != digest(expected):
            raise ValueError(f"refusing to change existing {label}: {path}")
        return
    atomic_json(path, expected)


def load_or_create_state(root: Path, plan: dict, initial: dict) -> dict:
    state_path = root / "campaign.json"
    plan_hash = digest(plan)
    initial_hash = digest(checked_weights(initial))
    if state_path.exists():
        state = read_json(state_path)
        if state.get("plan_hash") != plan_hash:
            raise ValueError("refusing to resume with a changed campaign plan")
        if state.get("initial_hash") != initial_hash:
            raise ValueError("refusing to resume with changed initial weights")
        return state
    if root.exists() and any(root.iterdir()):
        raise ValueError(f"refusing to initialize campaign in non-empty directory {root}")
    root.mkdir(parents=True, exist_ok=True)
    arms = {
        arm["id"]: {
            "status": "pending",
            "config_hash": digest(arm_hints(plan, arm)),
            "initial_hash": initial_hash,
        }
        for arm in plan["arms"]
    }
    state = {
        "version": 1,
        "created_at": now(),
        "updated_at": now(),
        "phase": "arms",
        "current_arm": None,
        "plan_hash": plan_hash,
        "initial_hash": initial_hash,
        "arms": arms,
        "selected_arm": None,
    }
    atomic_json(state_path, state)
    return state


def save_state(root: Path, state: dict) -> None:
    state["updated_at"] = now()
    atomic_json(root / "campaign.json", state)


def wait_while_paused(control: Path) -> None:
    while bool(read_json(control).get("pause", True)):
        time.sleep(1)


def run_trainer(root: Path, arm: dict, hints_path: Path, control: Path, capped: bool) -> None:
    global active_child
    cmd = [
        sys.executable,
        str(HERE / "train.py"),
        "--artifacts",
        str(root / "runs" / arm["id"]),
        "--hints",
        str(hints_path),
        "--control",
        str(control),
        "--initial",
        str(root / "initial.json"),
        "--evaluator", EVALUATOR,
        "--rust-worker", str(RUST_WORKER),
    ]
    if capped:
        cmd += ["--generations", str(arm["generations"])]
    env = os.environ.copy()
    env["NEAT_PORT"] = "8788"
    env["NEAT_WORKERS"] = "2"
    active_child = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, env=env)
    try:
        returncode = active_child.wait()
    finally:
        active_child = None
    if pending_signal is not None:
        raise SystemExit(128 + pending_signal)
    if returncode != 0:
        raise RuntimeError(f"trainer for arm {arm['id']} exited {returncode}")


def validated_completion(root: Path, arm: dict, config: dict, initial_hash: str) -> dict | None:
    run_dir = root / "runs" / arm["id"]
    complete_path = run_dir / "complete.json"
    if not complete_path.exists():
        return None
    manifest_path = run_dir / "manifest.json"
    if not manifest_path.exists():
        raise ValueError(f"arm {arm['id']} has complete.json without manifest.json")
    complete = read_json(complete_path)
    manifest = read_json(manifest_path)
    expected_initial = str((root / "initial.json").resolve())
    if manifest.get("initial") != expected_initial:
        raise ValueError(f"arm {arm['id']} manifest initial path differs")
    if manifest.get("initial_sha256") != initial_hash:
        raise ValueError(f"arm {arm['id']} manifest initial hash differs")
    provenance = manifest.get("provenance")
    if not isinstance(provenance, dict) or complete.get("fingerprint") != digest(provenance):
        raise ValueError(f"arm {arm['id']} completion fingerprint differs")
    expected_config = {key: value for key, value in config.items() if key not in ("pause", "notes")}
    actual_config = provenance.get("config")
    if not isinstance(actual_config, dict) or any(actual_config.get(key) != value for key, value in expected_config.items()):
        raise ValueError(f"arm {arm['id']} manifest configuration differs")
    if provenance.get("source_sha256") != source_hashes(HERE, EVALUATOR, RUST_WORKER):
        raise ValueError(f"arm {arm['id']} source files changed since completion")
    if int(complete.get("generation", -1)) != arm["generations"]:
        raise ValueError(f"arm {arm['id']} completion generation differs from its cap")
    for field in ("baseline", "champion"):
        record = complete.get(field)
        if not isinstance(record, dict):
            raise ValueError(f"arm {arm['id']} completion lacks {field}")
        result_key(record)
    best = read_json(run_dir / "best.json")
    checked_weights(best)
    if result_key(best) != result_key(complete["champion"]):
        raise ValueError(f"arm {arm['id']} best.json differs from completed champion")
    return complete


def result_evidence(arm: dict, complete: dict, config_hash: str, initial_hash: str) -> dict:
    baseline = complete["baseline"]
    champion = complete["champion"]
    return {
        "id": arm["id"],
        "search": arm["search"],
        "seed": arm["seed"],
        "generations": arm["generations"],
        "hypothesis": arm["hypothesis"],
        "source": arm["source"],
        "lane": arm["lane"],
        "config_hash": config_hash,
        "initial_hash": initial_hash,
        "generation": int(complete["generation"]),
        "baseline": {key: baseline.get(key) for key in ("seat_wins", "fitness")},
        "champion": {key: champion.get(key) for key in ("seat_wins", "fitness")},
    }


def audit(root: Path, plan: dict, initial: dict, chosen: dict, control: Path, selected_arm: str) -> dict:
    import train

    audit_dir = root / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)
    train.ART = audit_dir
    hints = {**plan["common"], "hold_seeds": plan["audit_seeds"]}
    scenarios = train.make_hold_scenarios(hints)
    pool = train.KernelPool(2, EVALUATOR, RUST_WORKER)
    try:
        wait_while_paused(control)
        initial_result = pool.eval_scenarios(checked_weights(initial), scenarios)
        wait_while_paused(control)
        chosen_result = pool.eval_scenarios(checked_weights(chosen), scenarios)
    finally:
        pool.close()
    data = {
        "created_at": now(),
        "plan_hash": digest(plan),
        "initial_hash": digest(checked_weights(initial)),
        "chosen_hash": digest(checked_weights(chosen)),
        "selected_arm": selected_arm,
        "fitness_version": initial["fitness_version"],
        "audit_seeds": plan["audit_seeds"],
        "scenario_count": len(scenarios),
        "initial": initial_result,
        "chosen": chosen_result,
    }
    atomic_json(root / "audit.json", data)
    return data


def write_summary(root: Path, state: dict, audit_data: dict) -> None:
    arms = [state["arms"][arm_id]["result"] for arm_id in state["arms"]]
    atomic_json(
        root / "summary.json",
        {
            "created_at": audit_data["created_at"],
            "plan_hash": state["plan_hash"],
            "initial_hash": state["initial_hash"],
            "arms": arms,
            "selected_arm": state["selected_arm"],
            "audit": {
                "audit_seeds": audit_data["audit_seeds"],
                "scenario_count": audit_data["scenario_count"],
                "initial": {key: audit_data["initial"].get(key) for key in ("seat_wins", "fitness")},
                "chosen": {key: audit_data["chosen"].get(key) for key in ("seat_wins", "fitness")},
            },
            "interpretation": "pilot comparison only; no statistical significance claimed",
        },
    )


def install_signal_handlers() -> None:
    def handle(signum, _frame):
        global pending_signal
        pending_signal = signum
        child = active_child
        if child is not None and child.poll() is None:
            try:
                child.send_signal(signum)
                return
            except ProcessLookupError:
                pass
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, handle)
    signal.signal(signal.SIGTERM, handle)


def main() -> None:
    global EVALUATOR, RUST_WORKER
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--control", required=True, type=Path)
    parser.add_argument("--initial", required=True, type=Path)
    parser.add_argument("--evaluator", choices=("elm", "rust"), default="elm")
    parser.add_argument("--rust-worker", type=Path, default=RUST_WORKER)
    args = parser.parse_args()
    EVALUATOR = args.evaluator
    RUST_WORKER = args.rust_worker.resolve()

    plan = validate_plan(read_json(args.plan.resolve()))
    root = args.root.resolve()
    saved_initial = root / "initial.json"
    initial = read_json(saved_initial if (root / "campaign.json").exists() else args.initial.resolve())
    checked_weights(initial)
    control = args.control.resolve()
    read_json(control)
    state = load_or_create_state(root, plan, initial)
    ensure_json(root / "plan.json", plan, "campaign plan snapshot")
    ensure_json(root / "initial.json", initial, "campaign initial weights")
    install_signal_handlers()

    arms_by_id = {arm["id"]: arm for arm in plan["arms"]}
    if state["phase"] == "arms":
        for index, arm in enumerate(plan["arms"]):
            config = arm_hints(plan, arm)
            hints_path = root / "runs" / arm["id"] / "hints.json"
            ensure_json(hints_path, config, f"hints for arm {arm['id']}")
            complete = validated_completion(root, arm, config, state["initial_hash"])
            if complete is None:
                state["current_arm"] = arm["id"]
                state["arms"][arm["id"]]["status"] = "waiting" if index else "running"
                save_state(root, state)
                if index:
                    wait_while_paused(control)
                state["arms"][arm["id"]]["status"] = "running"
                save_state(root, state)
                run_trainer(root, arm, hints_path, control, capped=True)
                complete = validated_completion(root, arm, config, state["initial_hash"])
                if complete is None:
                    raise RuntimeError(f"trainer for arm {arm['id']} exited without complete.json")
            state["arms"][arm["id"]]["status"] = "complete"
            state["arms"][arm["id"]]["result"] = result_evidence(
                arm, complete, digest(config), state["initial_hash"]
            )
            state["current_arm"] = None
            save_state(root, state)
        selected = max(
            plan["arms"],
            key=lambda arm: result_key(read_json(root / "runs" / arm["id"] / "complete.json")["champion"]),
        )
        state["selected_arm"] = selected["id"]
        state["phase"] = "audit"
        save_state(root, state)

    if state["phase"] == "audit":
        selected = arms_by_id[state["selected_arm"]]
        config = arm_hints(plan, selected)
        if validated_completion(root, selected, config, state["initial_hash"]) is None:
            raise ValueError(f"selected arm {selected['id']} is not complete")
        champion = read_json(root / "runs" / selected["id"] / "best.json")
        audit_path = root / "audit.json"
        if audit_path.exists():
            audit_data = read_json(audit_path)
            expected = {
                "plan_hash": state["plan_hash"],
                "initial_hash": state["initial_hash"],
                "chosen_hash": digest(checked_weights(champion)),
                "selected_arm": selected["id"],
            }
            if any(audit_data.get(key) != value for key, value in expected.items()):
                raise ValueError("existing audit.json does not belong to this campaign choice")
        else:
            audit_data = audit(root, plan, initial, champion, control, selected["id"])
        write_summary(root, state, audit_data)
        state["phase"] = "continuation"
        save_state(root, state)

    if state["phase"] != "continuation" or state["selected_arm"] not in arms_by_id:
        raise ValueError(f"invalid campaign phase {state.get('phase')!r}")
    selected = arms_by_id[state["selected_arm"]]
    state["current_arm"] = selected["id"]
    state["arms"][selected["id"]]["status"] = "continuing"
    save_state(root, state)
    run_trainer(root, selected, root / "runs" / selected["id"] / "hints.json", control, capped=False)
    raise RuntimeError(f"continuation trainer for arm {selected['id']} exited unexpectedly")


if __name__ == "__main__":
    main()
