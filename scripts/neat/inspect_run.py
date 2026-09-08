#!/usr/bin/env python3
"""Read-only JSON diagnostics for a NEAT campaign run."""

import argparse
import json
import time
from pathlib import Path

from score import scenario_win


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CAMPAIGN = ROOT / "artifacts" / "neat" / "campaigns" / "takeover-v1"
METRIC_FIELDS = (
    "gen",
    "train_seed",
    "train_best_wins",
    "center_train_wins",
    "validation_wins",
    "champion_wins",
    "generation_s",
)


def read_json(path):
    if not path.is_file():
        return None
    with path.open() as handle:
        return json.load(handle)


def read_recent_metrics(path, count=5):
    if not path.is_file() or path.stat().st_size == 0:
        return [], False

    chunk_size = 64 * 1024
    with path.open("rb") as handle:
        end = handle.seek(0, 2)
        position = end
        data = b""
        while position > 0 and data.count(b"\n") < count + 1:
            size = min(chunk_size, position)
            position -= size
            handle.seek(position)
            data = handle.read(size) + data

    lines = data.split(b"\n")
    if position > 0:
        lines = lines[1:]

    incomplete_ignored = False
    if lines and lines[-1] == b"":
        lines.pop()
    elif lines:
        try:
            json.loads(lines[-1])
        except (UnicodeDecodeError, json.JSONDecodeError):
            lines.pop()
            incomplete_ignored = True

    rows = []
    for line in lines[-count:]:
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError(f"invalid complete metrics line in {path}: {error}") from error
        if not isinstance(row, dict):
            raise ValueError(f"invalid complete metrics line in {path}: expected JSON object")
        rows.append(row)
    return rows, incomplete_ignored


def win_count(scenarios, budget):
    return {
        "wins": sum(1 for scenario in scenarios if scenario_win(scenario, budget)),
        "count": len(scenarios),
    }


def result_summary(record, budget):
    if not isinstance(record, dict):
        return None
    scenarios = record.get("scenarios") or []
    if not isinstance(scenarios, list):
        raise ValueError("result scenarios must be a list")

    by_seed = {}
    by_matchup = {}
    for scenario in scenarios:
        seed = str(scenario.get("seed"))
        matchup = f"{scenario.get('us')} vs {scenario.get('them')}"
        by_seed.setdefault(seed, []).append(scenario)
        by_matchup.setdefault(matchup, []).append(scenario)

    summary = win_count(scenarios, budget)
    summary["by_seed"] = {key: win_count(value, budget) for key, value in sorted(by_seed.items())}
    summary["by_matchup"] = {key: win_count(value, budget) for key, value in sorted(by_matchup.items())}
    return summary


def population_summary(rows, budget):
    scenarios = []
    for row in rows:
        population = row.get("population") or []
        if not isinstance(population, list):
            raise ValueError("metrics population must be a list")
        for candidate in population:
            candidate_scenarios = candidate.get("scenarios") or []
            if not isinstance(candidate_scenarios, list):
                raise ValueError("population scenarios must be a list")
            scenarios.extend(candidate_scenarios)
    result = win_count(scenarios, budget)
    return {"wins": result["wins"], "fights": result["count"]}


def inspect(campaign_path, run_path=None):
    campaign_file = campaign_path / "campaign.json"
    campaign = read_json(campaign_file)
    if campaign is None and run_path is None:
        raise FileNotFoundError(f"campaign record not found: {campaign_file}")
    campaign = campaign or {}
    if not isinstance(campaign, dict):
        raise ValueError(f"campaign record must be a JSON object: {campaign_file}")

    current_arm = campaign.get("current_arm")
    arm = run_path.name if run_path is not None else current_arm
    active_run = run_path if run_path is not None else (campaign_path / "runs" / current_arm if current_arm else None)
    report = {
        "campaign_phase": campaign.get("phase"),
        "arm": arm,
        "run": str(active_run) if active_run is not None else None,
        "status": "waiting",
        "generation": None,
        "error": "",
        "paused": None,
        "baseline": None,
        "champion": None,
        "last_5_generations": [],
        "train_population": {"wins": 0, "fights": 0},
        "checkpoint_generation": None,
        "updated_age_seconds": None,
        "incomplete_metrics_line_ignored": False,
    }
    if active_run is None or not active_run.is_dir():
        return report

    status_path = active_run / "status.json"
    status = read_json(status_path)
    baseline = read_json(active_run / "baseline.json")
    best = read_json(active_run / "best.json")
    checkpoint = read_json(active_run / "checkpoint.json")
    manifest = read_json(active_run / "manifest.json")
    metrics, incomplete_ignored = read_recent_metrics(active_run / "metrics.jsonl")

    config = (((manifest or {}).get("provenance") or {}).get("config") or {})
    budget = int(config.get("episode_ticks") or (status or {}).get("episode_ticks") or 1800)
    champion = best or ((checkpoint or {}).get("champion"))
    report.update(
        {
            "status": (status or {}).get("phase", "waiting"),
            "evaluator": (status or {}).get("evaluator", "elm"),
            "generation": (status or {}).get("generation"),
            "error": (status or {}).get("error", ""),
            "paused": (status or {}).get("paused"),
            "baseline": result_summary(baseline, budget),
            "champion": result_summary(champion, budget),
            "last_5_generations": [{key: row.get(key) for key in METRIC_FIELDS} for row in metrics],
            "train_population": population_summary(metrics, budget),
            "checkpoint_generation": (checkpoint or {}).get("generation"),
            "updated_age_seconds": round(max(0.0, time.time() - status_path.stat().st_mtime), 1)
            if status_path.is_file()
            else None,
            "incomplete_metrics_line_ignored": incomplete_ignored,
        }
    )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign", type=Path)
    parser.add_argument("--run", type=Path)
    args = parser.parse_args()
    run = args.run
    if run is None and args.campaign is None:
        active = read_json(ROOT / "artifacts/neat/active-run.json")
        if active:
            run = Path(active["run"])
    report = inspect((args.campaign or DEFAULT_CAMPAIGN).resolve(), run.resolve() if run else None)
    print(json.dumps(report, separators=(",", ":"), sort_keys=True))


if __name__ == "__main__":
    main()
