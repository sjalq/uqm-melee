#!/usr/bin/env python3
"""Evolution-strategies trainer with interchangeable Elm and Rust evaluators.

Caps: 2 CPU cores, 4 GB host RAM. GPU is optional (tiny weight updates).
Dashboard: http://0.0.0.0:8788
Hot-reload: scripts/neat/hints.json
"""

from __future__ import annotations

import argparse
import json
import math
import os
import queue
import random
import selectors
import signal
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from layout import ALL_SHIPS, FITNESS_VERSION, N_HIDDEN, N_IN, N_OUT, N_WEIGHTS, START_POOL  # noqa: E402
from score import cvar_mean, centered_ranks, scenario_win  # noqa: E402
from experiment import atomic_json, checked_weights, digest, fork_checkpoint, noise_vector, result_key, source_hashes, tuples

ART = ROOT / "artifacts" / "neat"
HALL = ART / "hall"
HINTS = HERE / "hints.json"
STATUS = ART / "status.json"
METRICS = ART / "metrics.jsonl"
BEST = ART / "best.json"
WORKER = HERE / "worker.js"
KERNEL = HERE / "kernel.js"
EVALUATOR = "elm"
RUST_WORKER = ROOT / "rust" / "target" / "release" / "melee-worker"
PORT = int(os.environ.get("NEAT_PORT", "8788"))
WORKERS = int(os.environ.get("NEAT_WORKERS", "2"))
CONTROL = None
INITIAL = None
MAX_GENERATIONS = None
NO_DASHBOARD = False
RESUME_FROM = None

ART.mkdir(parents=True, exist_ok=True)
HALL.mkdir(parents=True, exist_ok=True)

stop = threading.Event()
lock = threading.Lock()
state = {
    "generation": 0,
    "best_fitness": -1e300,
    "mean_fitness": 0.0,
    "wins": 0,
    "own": 0.0,
    "enemy": 0.0,
    "eval_s": 0.0,
    "lives": 0,
    "sigma": 0.12,
    "pop": 24,
    "episode_ticks": 900,
    "notes": "",
    "history": [],
    "hall": [],
    "error": "",
    "started": time.time(),
    "paused": False,
    "gpu": False,
    "fitness_version": FITNESS_VERSION,
    "n_train": 0,
    "n_hold": 0,
    "pool": list(START_POOL),
    "champion": {},
}


def log(msg: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    with (ART / "train.log").open("a") as f:
        f.write(line + "\n")


def load_hints() -> dict:
    defaults = {
        "sigma": 0.08,
        "lr": 0.08,
        "pop": 24,
        "episode_ticks": 1800,
        "seed": 1701,
        "pause": False,
        "notes": "",
        "us": "Pkunk",
        "them": "Umgah",
        "rating": "awesome",
        "train_seeds": [1701, 2137, 7],
        "hold_seeds": [42, 99, 1234],
        "roster": [],
        "pool": list(START_POOL),
        "expand_at": 0.8,
        "search": "es",
        "auto_expand": False,
    }
    try:
        data = json.loads(HINTS.read_text())
        defaults.update(data)
    except Exception as e:
        raise ValueError(f"cannot read hints; refusing to train with defaults: {e}") from e
    if CONTROL is not None:
        control = json.loads(CONTROL.read_text())
        defaults["pause"] = bool(control.get("pause", True))
    defaults["pop"] = int(max(8, min(32, defaults["pop"])))
    defaults["sigma"] = float(max(0.02, min(0.4, defaults["sigma"])))
    defaults["lr"] = float(max(0.01, min(0.4, defaults.get("lr", 0.08))))
    defaults["episode_ticks"] = int(max(300, min(3600, defaults["episode_ticks"])))
    defaults["train_seeds"] = [int(s) for s in (defaults.get("train_seeds") or [1701, 2137, 7])]
    defaults["hold_seeds"] = [int(s) for s in (defaults.get("hold_seeds") or [42, 99, 1234])]
    if not isinstance(defaults.get("roster"), list):
        defaults["roster"] = []
    if not isinstance(defaults.get("us_roster"), list):
        defaults["us_roster"] = []
    if not isinstance(defaults.get("pool"), list) or not defaults["pool"]:
        defaults["pool"] = list(START_POOL)
    defaults["expand_at"] = float(defaults.get("expand_at") or 0.8)
    if defaults["search"] not in ("es", "block_es"):
        raise ValueError("search must be es or block_es")
    if set(defaults["train_seeds"]) & set(defaults["hold_seeds"]):
        raise ValueError("training and validation seeds must be disjoint")
    if len(set(defaults["pool"])) != len(defaults["pool"]) or any(s not in ALL_SHIPS for s in defaults["pool"]):
        raise ValueError("pool must contain unique, known ships")
    return defaults


def save_status() -> None:
    with lock:
        payload = dict(state)
        payload["uptime_s"] = time.time() - state["started"]
        payload["history"] = state["history"][-200:]
        payload["hall"] = state["hall"][-20:]
        payload["n_weights"] = N_WEIGHTS
        payload["fitness_version"] = FITNESS_VERSION
    if not math.isfinite(payload["best_fitness"]):
        payload["best_fitness"] = -1e300
    atomic_json(STATUS, payload)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path.startswith("/api/status"):
            body = STATUS.read_bytes() if STATUS.exists() else b"{}"
            return self._send(200, "application/json", body)
        if path.startswith("/api/best"):
            if not BEST.exists():
                return self._send(200, "application/json", b"{}")
            data = json.loads(BEST.read_text())
            data.pop("weights", None)
            return self._send(200, "application/json", json.dumps(data).encode())
        if path.startswith("/api/net"):
            if not BEST.exists():
                return self._send(200, "application/json", b"{}")
            data = json.loads(BEST.read_text())
            w = data.get("weights") or []
            body = {
                "generation": data.get("generation") or 0,
                "n_in": N_IN,
                "n_hidden": N_HIDDEN,
                "n_out": N_OUT,
                "n_weights": len(w) if isinstance(w, list) else 0,
                "weights": w if isinstance(w, list) else [],
            }
            return self._send(200, "application/json", json.dumps(body).encode())
        if path in ("/dashboard.js", "/scripts/neat/dashboard.js"):
            js = HERE / "dashboard.js"
            if not js.exists():
                return self._send(404, "text/plain", b"missing dashboard.js")
            return self._send(200, "application/javascript; charset=utf-8", js.read_bytes())
        html = HERE / "index.html"
        if html.exists():
            return self._send(200, "text/html; charset=utf-8", html.read_bytes())
        return self._send(200, "text/html; charset=utf-8", b"<p>missing index.html</p>")

    def _send(self, code: int, mime: str, body: bytes) -> None:
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class KernelPool:
    def __init__(self, n: int, evaluator=None, rust_worker=None):
        self.evaluator = evaluator or EVALUATOR
        self.rust_worker = Path(rust_worker or RUST_WORKER).resolve()
        if self.evaluator not in ("elm", "rust"):
            raise ValueError(f"unknown evaluator {self.evaluator}")
        if self.evaluator == "rust" and not os.access(self.rust_worker, os.X_OK):
            raise FileNotFoundError(f"Rust evaluator is not executable: {self.rust_worker}")
        self.procs = []
        self.lock = threading.Lock()
        self.q: queue.Queue = queue.Queue()
        for i in range(n):
            self._spawn(i)
        for i, p in enumerate(self.procs):
            self.q.put(i)
        self.ex = ThreadPoolExecutor(max_workers=max(1, n))

    def _spawn(self, i: int) -> None:
        env = os.environ.copy()
        env["NODE_OPTIONS"] = "--max-old-space-size=512"
        p = subprocess.Popen(
            [str(self.rust_worker)] if self.evaluator == "rust" else ["node", str(WORKER)],
            cwd=str(HERE),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=(ART / f"worker-{i}.stderr.log").open("a"),
            text=True,
            bufsize=1,
            env=env,
        )
        if i < len(self.procs):
            self.procs[i] = p
        else:
            self.procs.append(p)
        log(f"{self.evaluator} worker {i} pid {p.pid}")

    def eval_job(self, job, timeout=180):
        payload = {
            "weights": [float(x) for x in job["weights"]],
            "seed": int(job["seed"]),
            "ticks": int(job["ticks"]),
            "swap": bool(job.get("swap")),
            "rating": str(job.get("rating") or "awesome"),
            "us": str(job.get("us") or "Pkunk"),
            "them": str(job.get("them") or "Umgah"),
            "foe": str(job.get("foe") or "cyborg"),
        }
        line_in = json.dumps(payload)
        idx = self.q.get()
        try:
            p = self.procs[idx]
            if p.poll() is not None:
                log(f"worker {idx} dead, restarting")
                self._spawn(idx)
                p = self.procs[idx]
            assert p.stdin and p.stdout
            p.stdin.write(line_in + "\n")
            p.stdin.flush()
            with selectors.DefaultSelector() as selector:
                selector.register(p.stdout, selectors.EVENT_READ)
                if not selector.select(timeout):
                    p.kill()
                    p.wait()
                    raise TimeoutError(f"worker {idx} exceeded {timeout}s for {payload['us']} vs {payload['them']}")
            line = p.stdout.readline()
            if not line:
                raise RuntimeError(f"worker {idx} empty stdout; see worker-{idx}.stderr.log")
            rec = json.loads(line)
            if rec.get("error") or not math.isfinite(float(rec.get("fitness", float("nan")))):
                raise RuntimeError(f"invalid worker result: {rec}")
            rec["swap"] = payload["swap"]
            rec["us_ship"] = payload["us"]
            rec["them"] = payload["them"]
            rec["rating"] = payload["rating"]
            rec["foe"] = payload["foe"]
            rec["seed"] = payload["seed"]
            rec["group"] = job.get("group") or ""
            return rec
        finally:
            self.q.put(idx)

    def eval_scenarios(self, weights, scenarios):
        w = [float(x) for x in weights]
        jobs = [{**s, "weights": w} for s in scenarios]
        futs = [self.ex.submit(self.eval_job, job) for job in jobs]
        recs = [f.result() for f in futs]
        err = next((r.get("error") for r in recs if r.get("error")), "")
        if err:
            return {"fitness": 0.0, "own": 0.0, "enemy": 0.0, "winner": "error", "seat_wins": 0, "ticks": 0, "error": err, "scenarios": recs}
        scores = [float(r.get("fitness") or 0) for r in recs]
        budget = int(scenarios[0]["ticks"]) if scenarios else 1800
        wins = int(sum(1 for r in recs if scenario_win(r, budget)))
        dual = bool(recs) and all(scenario_win(r, budget) for r in recs)
        slim = [{k: r.get(k) for k in ("seed", "swap", "us", "them", "foe", "group", "rating", "winner", "outcome", "own", "enemy", "ticks", "fitness", "damage", "hurt", "engage")} for r in recs]
        return {
            "fitness": cvar_mean(scores),
            "mean": sum(scores) / max(1, len(scores)),
            "own": sum(float(r.get("own") or 0) for r in recs) / max(1, len(recs)),
            "enemy": sum(float(r.get("enemy") or 0) for r in recs) / max(1, len(recs)),
            "winner": "us" if dual else "pending",
            "seat_wins": wins,
            "dual": dual,
            "ticks": max(int(r.get("ticks") or 0) for r in recs),
            "error": "",
            "scenarios": slim,
        }

    def close(self):
        try:
            self.ex.shutdown(wait=False, cancel_futures=True)
        except Exception:
            pass
        for p in self.procs:
            try:
                p.terminate()
                p.wait(timeout=5)
            except Exception:
                p.kill()


def pack(us, them, foe, seeds, group, hints, swaps=(False, True)):
    ticks = int(hints["episode_ticks"])
    rating = str(hints.get("rating") or "awesome")
    out = []
    for seed in seeds:
        for swap in swaps:
            out.append(
                {
                    "us": us,
                    "them": them,
                    "foe": foe,
                    "rating": rating,
                    "seed": int(seed),
                    "swap": bool(swap),
                    "ticks": ticks,
                    "group": group,
                }
            )
    return out


def pool_pairs(pool):
    return [(a, b) for a in pool for b in pool]


def make_train_scenarios(hints, gen):
    pool = list(hints.get("pool") or START_POOL)
    seeds = list(hints.get("train_seeds") or [1701])
    seeds = [seeds[gen % len(seeds)]]
    pairs = pool_pairs(pool)
    if len(pairs) > 12:
        rng = __import__("random").Random(gen * 31 + 7)
        rng.shuffle(pairs)
        pairs = pairs[:12]
    out = []
    for us, them in pairs:
        # Share one seat across candidates, then switch seats next generation.
        out += pack(us, them, "cyborg", seeds, f"{us}-{them}", hints, swaps=(bool(gen % 2),))
    return out


def make_hold_scenarios(hints):
    pool = list(hints.get("pool") or START_POOL)
    seeds = list(hints.get("hold_seeds") or [42])
    out = []
    for us, them in pool_pairs(pool):
        out += pack(us, them, "cyborg", seeds, f"{us}-{them}", hints)
    return out


def maybe_expand_pool(hints, hold):
    """Add the next catalog hull only after a saved champion clears expand_at on hold."""
    pool = list(hints.get("pool") or START_POOL)
    if not hints.get("auto_expand", False):
        return pool, False
    n = max(1, len(hold.get("scenarios") or []))
    wins = int(hold.get("seat_wins") or 0)
    rate = wins / n
    if rate < float(hints.get("expand_at") or 0.8) or len(pool) >= 25:
        return pool, False
    rest = [s for s in ALL_SHIPS if s not in pool]
    if not rest:
        return pool, False
    pool.append(rest[0])
    data = dict(hints)
    data["pool"] = pool
    atomic_json(HINTS, data)
    log(f"pool expand +{pool[-1]} size {len(pool)} hold {wins}/{n}")
    return pool, True


def load_best():
    if BEST.exists():
        try:
            data = json.loads(BEST.read_text())
            w = checked_weights(data)
            log("loaded champion from best.json (validation re-scored)")
            return w, float("-inf")
        except Exception as e:
            raise ValueError(f"refusing to discard existing champion: {e}") from e
    if INITIAL is not None:
        return checked_weights(json.loads(INITIAL.read_text())), float("-inf")
    log(f"init zeros width {N_WEIGHTS}")
    return [0.0] * N_WEIGHTS, float("-inf")


def save_best(weights, rec, gen):
    skip = {"weights", "eps"}
    meta = {}
    for k, v in rec.items():
        if k in skip:
            continue
        if hasattr(v, "item"):
            v = v.item()
        meta[k] = v
    if rec.get("core_dual") is None:
        rec["core_dual"] = bool(rec.get("dual"))
    payload = {"generation": gen, "n_weights": N_WEIGHTS, "fitness_version": FITNESS_VERSION, "weights": [float(x) for x in weights], **meta}
    atomic_json(BEST, payload)
    hall = HALL / f"gen{gen:05d}_fit{rec['fitness']:.2f}.json"
    atomic_json(hall, payload)
    with lock:
        state["hall"].append({"gen": gen, "fitness": rec["fitness"], "winner": rec.get("winner"), "own": rec.get("own"), "enemy": rec.get("enemy"), "file": hall.name})
        state["champion"] = {
            "generation": gen,
            "fitness": rec.get("fitness"),
            "core_dual": rec.get("core_dual"),
            "seat_wins": rec.get("seat_wins"),
            "scenarios": rec.get("scenarios") or [],
        }


def run_loop():
    import numpy as np

    hints = load_hints()
    config = {k: v for k, v in hints.items() if k not in ("pause", "notes")}
    provenance = {"config": config, "source_sha256": source_hashes(HERE, EVALUATOR, RUST_WORKER), "fitness_version": FITNESS_VERSION}
    manifest_path = ART / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest["provenance"] != provenance:
            raise ValueError("experiment code or configuration changed; use a new artifacts directory")
        if RESUME_FROM and manifest.get("resumed_from", {}).get("artifacts") != str(RESUME_FROM):
            raise ValueError("existing run was not forked from --resume-from")
    else:
        manifest = {"created_at": time.time(), "provenance": provenance, "initial": str(INITIAL) if INITIAL else None,
                    "initial_sha256": digest(checked_weights(json.loads(INITIAL.read_text()))) if INITIAL else None}
        if RESUME_FROM:
            manifest["resumed_from"] = fork_checkpoint(RESUME_FROM, ART, provenance)
        atomic_json(manifest_path, manifest)
    if INITIAL and manifest.get("initial_sha256") != digest(checked_weights(json.loads(INITIAL.read_text()))):
        raise ValueError("initial policy changed since experiment creation")
    fingerprint = digest(provenance)
    checkpoint_path = ART / "checkpoint.json"
    rng = random.Random(hints["seed"])
    gen = 0
    weights, _ = load_best()
    theta = np.array(weights, dtype=np.float64)
    champion = None
    if checkpoint_path.exists():
        checkpoint = json.loads(checkpoint_path.read_text())
        if checkpoint["fingerprint"] != fingerprint:
            raise ValueError("checkpoint does not belong to this experiment")
        theta = np.array(checked_weights(checkpoint), dtype=np.float64)
        rng.setstate(tuples(checkpoint["rng"]))
        gen = checkpoint["generation"]
        champion = checkpoint["champion"]
        checked_weights(champion)
        state.update(checkpoint["status"])
        state["started"] = time.time()
        state["error"] = ""
        save_best(champion["weights"], champion, champion["generation"])
        log(f"restored exact search state at generation {gen}")
    state.update({"generation": gen, "sigma": hints["sigma"], "pop": hints["pop"],
                  "episode_ticks": hints["episode_ticks"], "notes": hints.get("notes", ""),
                  "pool": hints["pool"], "search": hints["search"], "experiment": str(ART),
                  "phase": "baseline", "paused": hints["pause"], "evaluator": EVALUATOR})
    if not NO_DASHBOARD:
        atomic_json(ROOT / "artifacts/neat/active-run.json", {"run": str(ART), "evaluator": EVALUATOR})
    save_status()

    def wait_if_paused():
        while not stop.is_set():
            current = load_hints()
            if {k: v for k, v in current.items() if k not in ("pause", "notes")} != config:
                raise ValueError("live experiment configuration changed; create a new experiment")
            state["paused"] = current["pause"]
            state["notes"] = current.get("notes", "")
            if not current["pause"]:
                return
            save_status()
            stop.wait(1)

    kernels = KernelPool(WORKERS)

    def eval_weights(w, scenarios):
        wait_if_paused()
        if stop.is_set():
            raise InterruptedError("training stopped at evaluation boundary")
        started = time.monotonic()
        rec = kernels.eval_scenarios(w, scenarios)
        if rec.get("error"):
            raise RuntimeError(rec["error"])
        rec["eval_s"] = time.monotonic() - started
        rec["weights"] = [float(x) for x in w]
        state["lives"] += len(scenarios)
        state["eval_s"] = rec["eval_s"]
        save_status()
        return rec

    def persist():
        atomic_json(checkpoint_path, {
            "fitness_version": FITNESS_VERSION, "fingerprint": fingerprint,
            "generation": gen, "weights": theta.tolist(), "rng": rng.getstate(),
            "champion": champion, "status": state,
        })

    def slim(rec):
        return {k: v for k, v in rec.items() if k != "weights"}

    try:
        hold_scen = make_hold_scenarios(hints)
        if champion is None:
            champion = eval_weights(theta, hold_scen)
            champion.update({"generation": 0, "fitness_version": FITNESS_VERSION})
            save_best(champion["weights"], champion, 0)
            atomic_json(ART / "baseline.json", slim(champion))
            state["best_fitness"] = champion["fitness"]
            log(f"baseline validation {champion['seat_wins']}/{len(hold_scen)} score {champion['fitness']:.2f}")
            persist()
        else:
            state["best_fitness"] = champion["fitness"]
        state["n_hold"] = len(hold_scen)

        while not stop.is_set() and (MAX_GENERATIONS is None or gen < MAX_GENERATIONS):
            wait_if_paused()
            if stop.is_set():
                break
            started = time.monotonic()
            train_scen = make_train_scenarios(hints, gen)
            state.update({"phase": "training", "n_train": len(train_scen), "generation": gen})
            save_status()
            recs, dirs = [], []
            half = hints["pop"] // 2
            for _ in range(half):
                eps = np.array(noise_vector(rng, hints["search"], gen), dtype=np.float64)
                plus = eval_weights(theta + hints["sigma"] * eps, train_scen)
                minus = eval_weights(theta - hints["sigma"] * eps, train_scen)
                recs.extend([plus, minus])
                dirs.extend([eps, -eps])
            fits = [r["fitness"] for r in recs]
            update = np.zeros_like(theta)
            for utility, eps in zip(centered_ranks(fits), dirs):
                update += utility * eps
            theta = theta + (hints["lr"] / len(recs)) * update
            if not np.isfinite(theta).all():
                raise ValueError("search centre contains non-finite weights")
            center = eval_weights(theta, train_scen)
            candidate = max(recs + [center], key=result_key)
            state["phase"] = "validation"
            save_status()
            hold = eval_weights(candidate["weights"], hold_scen)
            promoted = result_key(hold) > result_key(champion)
            if promoted:
                champion = {**hold, "generation": gen + 1, "fitness_version": FITNESS_VERSION}
                save_best(champion["weights"], champion, gen + 1)
                log(f"champion validation {champion['seat_wins']}/{len(hold_scen)} score {champion['fitness']:.2f}")
            gen += 1
            wins = sum(r["seat_wins"] for r in recs)
            mean = sum(fits) / len(fits)
            own = sum(r["own"] for r in recs) / len(recs)
            enemy = sum(r["enemy"] for r in recs) / len(recs)
            elapsed = time.monotonic() - started
            row = {
                "gen": gen, "at": time.time(), "mean": mean, "best": champion["fitness"],
                "own": own, "enemy": enemy, "wins": wins, "train_fights": len(recs) * len(train_scen),
                "train_best_wins": candidate["seat_wins"], "center_train_wins": center["seat_wins"],
                "validation_wins": hold["seat_wins"], "champion_wins": champion["seat_wins"],
                "promoted": promoted, "sigma": hints["sigma"], "lr": hints["lr"],
                "fitness_version": FITNESS_VERSION, "search": hints["search"],
                "n_train": len(train_scen), "n_hold": len(hold_scen), "pool": hints["pool"],
                "train_seed": train_scen[0]["seed"], "generation_s": elapsed,
                "candidate_train": slim(candidate), "candidate_validation": slim(hold),
                "center_train": slim(center), "population": [slim(r) for r in recs],
            }
            state.update({"generation": gen, "mean_fitness": mean, "best_fitness": champion["fitness"],
                          "own": own, "enemy": enemy, "wins": state["wins"] + wins,
                          "train_best_wins": candidate["seat_wins"], "validation_wins": hold["seat_wins"],
                          "champion_wins": champion["seat_wins"], "generation_s": elapsed})
            state["history"] = (state["history"] + [{k: row[k] for k in ("gen", "mean", "best", "own", "enemy", "wins")}])[-200:]
            persist()
            with METRICS.open("a") as f:
                f.write(json.dumps(row, allow_nan=False) + "\n")
                f.flush()
                os.fsync(f.fileno())
            save_status()
            log(f"gen {gen} train-best {candidate['seat_wins']}/{len(train_scen)} validation {hold['seat_wins']}/{len(hold_scen)} champion {champion['seat_wins']}/{len(hold_scen)} seed {train_scen[0]['seed']} {elapsed:.1f}s")
        if not stop.is_set():
            state["phase"] = "complete"
            atomic_json(ART / "complete.json", {
                "generation": gen, "baseline": json.loads((ART / "baseline.json").read_text()),
                "champion": slim(champion), "fingerprint": fingerprint,
            })
            save_status()
    except InterruptedError:
        log("stopped; next start replays any incomplete generation from its checkpoint")
    except Exception as e:
        log(f"loop crash: {e}")
        state["error"] = str(e)
        state["phase"] = "error"
        save_status()
        raise
    finally:
        kernels.close()


def main():
    global ART, HALL, HINTS, STATUS, METRICS, BEST, CONTROL, INITIAL, MAX_GENERATIONS, NO_DASHBOARD
    global EVALUATOR, RUST_WORKER, RESUME_FROM
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path, default=ART)
    parser.add_argument("--hints", type=Path, default=HINTS)
    parser.add_argument("--control", type=Path)
    parser.add_argument("--initial", type=Path)
    parser.add_argument("--generations", type=int)
    parser.add_argument("--no-dashboard", action="store_true")
    parser.add_argument("--evaluator", choices=("elm", "rust"), default="elm")
    parser.add_argument("--rust-worker", type=Path, default=RUST_WORKER)
    parser.add_argument("--resume-from", type=Path, help="fork an exact checkpoint into a new run with identical configuration")
    args = parser.parse_args()
    if args.generations is not None and args.generations < 1:
        parser.error("--generations must be positive")
    ART = args.artifacts.resolve()
    HALL, STATUS, METRICS, BEST = ART / "hall", ART / "status.json", ART / "metrics.jsonl", ART / "best.json"
    HINTS = args.hints.resolve()
    CONTROL = args.control.resolve() if args.control else None
    INITIAL = args.initial.resolve() if args.initial else None
    MAX_GENERATIONS = args.generations
    NO_DASHBOARD = args.no_dashboard
    EVALUATOR = args.evaluator
    RUST_WORKER = args.rust_worker.resolve()
    RESUME_FROM = args.resume_from.resolve() if args.resume_from else None
    ART.mkdir(parents=True, exist_ok=True)
    HALL.mkdir(parents=True, exist_ok=True)
    if EVALUATOR == "elm" and not KERNEL.exists():
        raise FileNotFoundError("kernel.js missing")
    if EVALUATOR == "rust" and not os.access(RUST_WORKER, os.X_OK):
        raise FileNotFoundError(f"Rust evaluator is not executable: {RUST_WORKER}")
    httpd = None
    if not NO_DASHBOARD:
        httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        log(f"dashboard port {PORT}; experiment {ART}")
    def handle(sig, _frm):
        log(f"signal {sig}")
        stop.set()
    signal.signal(signal.SIGINT, handle)
    signal.signal(signal.SIGTERM, handle)
    try:
        run_loop()
    finally:
        if httpd is not None:
            httpd.shutdown()
            httpd.server_close()


if __name__ == "__main__":
    main()
