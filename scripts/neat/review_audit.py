"""Independent fresh-seed audit through the unchanged Rust game worker."""
import json
import subprocess
from score import cvar_mean, scenario_win

def audit(worker, weights, pool, seeds, opponents=None):
    jobs = [{"weights": weights, "seed": seed, "ticks": 1800, "swap": swap,
             "rating": "awesome", "us": us, "them": them, "foe": "cyborg", "scoring": "combat-v1"}
            for us in pool for them in (pool if opponents is None else opponents) for seed in seeds for swap in [False, True]]
    completed = subprocess.run([str(worker)], input="".join(json.dumps(j) + "\n" for j in jobs),
                               text=True, capture_output=True, check=True, timeout=120)
    records = [json.loads(line) for line in completed.stdout.splitlines()]
    if len(records) != len(jobs) or any(r.get("error") or r.get("scoring_version") != "combat-v1" for r in records):
        raise RuntimeError("audit evaluator failed")
    flags = [scenario_win(r, 1800) for r in records]
    return {"wins": sum(flags), "fights": len(flags), "fitness": cvar_mean([r["fitness"] for r in records]),
            "flags": flags, "scenarios": records}

