"""Durable experiment state and deterministic mutation schedules."""

import hashlib
import json
import math
import os
from pathlib import Path

from layout import FITNESS_VERSION, N_HIDDEN, N_W1, N_WEIGHTS


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with tmp.open("w") as f:
        json.dump(data, f, allow_nan=False)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def source_hashes(root, evaluator="elm", rust_worker=None):
    files = ["train.py", "score.py", "layout.py", "experiment.py"]
    if evaluator == "elm":
        files += ["worker.js", "kernel.js"]
    elif evaluator != "rust":
        raise ValueError(f"unknown evaluator {evaluator}")
    hashes = {name: hashlib.sha256((Path(root) / name).read_bytes()).hexdigest() for name in files}
    if evaluator == "rust":
        binary = Path(rust_worker) if rust_worker else Path(root).parents[1] / "rust/target/release/melee-worker"
        hashes["melee-worker"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    return hashes


def checked_weights(data):
    if data.get("fitness_version") != FITNESS_VERSION:
        raise ValueError("checkpoint fitness version differs")
    weights = data.get("weights")
    if not isinstance(weights, list) or len(weights) != N_WEIGHTS:
        raise ValueError("checkpoint weight count differs")
    if not all(type(w) in (int, float) and math.isfinite(w) for w in weights):
        raise ValueError("checkpoint contains invalid weights")
    return weights


def tuples(value):
    return tuple(tuples(x) for x in value) if isinstance(value, list) else value


def mutation_indices(mode, generation):
    if mode == "es":
        return range(N_WEIGHTS)
    if mode != "block_es":
        raise ValueError(f"unknown search mode {mode}")
    blocks = [range(0, N_W1)]
    blocks += [range(N_W1 + o * (N_HIDDEN + 1), N_W1 + (o + 1) * (N_HIDDEN + 1)) for o in range(5)]
    blocks += [range(N_W1 + 5 * (N_HIDDEN + 1), N_WEIGHTS)]
    return blocks[generation % len(blocks)]


def noise_vector(rng, mode, generation):
    noise = [rng.gauss(0, 1) for _ in range(N_WEIGHTS)]
    if mode == "es":
        return noise
    active = set(mutation_indices(mode, generation))
    return [x if i in active else 0.0 for i, x in enumerate(noise)]


def result_key(record):
    return (int(record["seat_wins"]), float(record["fitness"]))


def fork_checkpoint(parent, destination, provenance):
    """Explicitly carry search state into a new, separately fingerprinted run.

    Used only after evaluator equivalence checks. The original run is retained;
    its configuration, fingerprint and checkpoint digest document the boundary.
    """
    parent, destination = Path(parent).resolve(), Path(destination).resolve()
    if parent == destination:
        raise ValueError("checkpoint fork requires a different artifacts directory")
    manifest = json.loads((parent / "manifest.json").read_text())
    checkpoint = json.loads((parent / "checkpoint.json").read_text())
    checked_weights(checkpoint)
    checked_weights(checkpoint["champion"])
    if checkpoint["fingerprint"] != digest(manifest["provenance"]):
        raise ValueError("parent checkpoint fingerprint does not match its manifest")
    if manifest["provenance"]["config"] != provenance["config"]:
        raise ValueError("checkpoint fork requires identical search and scenario configuration")
    if manifest["provenance"]["fitness_version"] != provenance["fitness_version"]:
        raise ValueError("checkpoint fork cannot change fitness semantics")
    if manifest["provenance"].get("scoring_version", "legacy") != provenance.get("scoring_version", "legacy"):
        raise ValueError("scoring changes require --initial and a freshly scored run, not --resume-from")
    baseline = json.loads((parent / "baseline.json").read_text())
    lineage = {"artifacts": str(parent), "fingerprint": checkpoint["fingerprint"],
               "checkpoint_sha256": digest(checkpoint), "generation": checkpoint["generation"]}
    checkpoint["fingerprint"] = digest(provenance)
    atomic_json(destination / "checkpoint.json", checkpoint)
    atomic_json(destination / "best.json", checkpoint["champion"])
    atomic_json(destination / "baseline.json", baseline)
    return lineage
