#!/usr/bin/env python3
"""OpenAI-ES trainer for the Elm Neat kernel.

Caps: 2 CPU cores, 4 GB host RAM. GPU is optional (tiny weight updates).
Dashboard: http://0.0.0.0:8788
Hot-reload: scripts/neat/hints.json
"""

from __future__ import annotations

import json
import os
import queue
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

ART = ROOT / "artifacts" / "neat"
HALL = ART / "hall"
HINTS = HERE / "hints.json"
STATUS = ART / "status.json"
METRICS = ART / "metrics.jsonl"
BEST = ART / "best.json"
WORKER = HERE / "worker.js"
KERNEL = HERE / "kernel.js"
PORT = int(os.environ.get("NEAT_PORT", "8788"))
WORKERS = int(os.environ.get("NEAT_WORKERS", "2"))

ART.mkdir(parents=True, exist_ok=True)
HALL.mkdir(parents=True, exist_ok=True)

stop = threading.Event()
lock = threading.Lock()
state = {
    "generation": 0,
    "best_fitness": float("-inf"),
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
    }
    try:
        data = json.loads(HINTS.read_text())
        defaults.update(data)
    except Exception as e:
        log(f"hints read failed: {e}")
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
    return defaults


def save_status() -> None:
    with lock:
        payload = dict(state)
        payload["uptime_s"] = time.time() - state["started"]
        payload["history"] = state["history"][-200:]
        payload["hall"] = state["hall"][-20:]
        payload["n_weights"] = N_WEIGHTS
        payload["fitness_version"] = FITNESS_VERSION
    STATUS.write_text(json.dumps(payload, indent=2))


def restore_state() -> None:
    if STATUS.exists():
        try:
            data = json.loads(STATUS.read_text())
            saved_w = data.get("n_weights")
            if saved_w != N_WEIGHTS:
                log(f"status width {saved_w} != {N_WEIGHTS}, starting fresh")
            else:
                saved_v = data.get("fitness_version")
                if saved_v != FITNESS_VERSION:
                    log(f"fitness_version {saved_v} != {FITNESS_VERSION}, ignore status counters")
                else:
                    for k in (
                        "best_fitness",
                        "mean_fitness",
                        "own",
                        "enemy",
                        "lives",
                        "sigma",
                        "pop",
                        "episode_ticks",
                        "notes",
                        "gpu",
                    ):
                        if k in data and data[k] not in (None, [], 0, 0.0, float("-inf")):
                            state[k] = data[k]
                    if isinstance(data.get("champion"), dict) and data["champion"]:
                        state["champion"] = data["champion"]
                    log(f"restored status lives {state.get('lives')} (gen comes from versioned metrics)")
        except Exception as e:
            log(f"status restore: {e}")
    if (not state.get("history")) and METRICS.exists():
        hist = []
        wins_total = 0
        try:
            for line in METRICS.read_text().splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                if row.get("fitness_version") != FITNESS_VERSION:
                    continue
                w = int(row.get("wins") or 0)
                wins_total += w
                hist.append(
                    {
                        "gen": row.get("gen", 0),
                        "mean": row.get("mean", 0),
                        "best": row.get("best", 0),
                        "own": row.get("own", 0),
                        "enemy": row.get("enemy", 0),
                        "wins": w,
                    }
                )
            if hist:
                state["history"] = hist[-200:]
                last = hist[-1]
                state["generation"] = last["gen"]
                state["mean_fitness"] = last["mean"]
                state["best_fitness"] = last["best"]
                state["own"] = last["own"]
                state["enemy"] = last["enemy"]
                if not state.get("wins"):
                    state["wins"] = wins_total
                log(f"restored {len(hist)} {FITNESS_VERSION} gens from metrics.jsonl")
        except Exception as e:
            log(f"metrics restore: {e}")


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
    def __init__(self, n: int):
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
            ["node", str(WORKER)],
            cwd=str(HERE),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        if i < len(self.procs):
            self.procs[i] = p
        else:
            self.procs.append(p)
        log(f"worker {i} pid {p.pid}")

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
            line = p.stdout.readline()
            if not line:
                err = p.stderr.read() if p.stderr else ""
                raise RuntimeError(f"worker {idx} empty stdout {err[-400:]}")
            rec = json.loads(line)
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
            except Exception:
                pass


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
    if len(pool) <= 4:
        seeds = seeds[:1]
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
    seeds = list(hints.get("hold_seeds") or [42])[:1]
    out = []
    for us, them in pool_pairs(pool):
        out += pack(us, them, "cyborg", seeds, f"{us}-{them}", hints)
    return out


def maybe_expand_pool(hints, hold):
    """Add the next catalog hull only after a saved champion clears expand_at on hold."""
    pool = list(hints.get("pool") or START_POOL)
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
    HINTS.write_text(json.dumps(data, indent=2) + "\n")
    log(f"pool expand +{pool[-1]} size {len(pool)} hold {wins}/{n}")
    return pool, True


def load_best():
    if BEST.exists():
        try:
            data = json.loads(BEST.read_text())
            w = data.get("weights")
            if isinstance(w, list) and len(w) == N_WEIGHTS:
                log(f"resumed weights from best.json (fitness re-scored)")
                return w, float("-inf")
            log(f"rejected best.json length {0 if not isinstance(w, list) else len(w)} want {N_WEIGHTS}")
        except Exception as e:
            log(f"best.json: {e}")
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
    BEST.write_text(json.dumps(payload))
    hall = HALL / f"gen{gen:05d}_fit{rec['fitness']:.2f}.json"
    hall.write_text(json.dumps(payload))
    with lock:
        state["hall"].append({"gen": gen, "fitness": rec["fitness"], "winner": rec.get("winner"), "own": rec.get("own"), "enemy": rec.get("enemy"), "file": hall.name})
        state["champion"] = {
            "generation": gen,
            "fitness": rec.get("fitness"),
            "core_dual": rec.get("core_dual"),
            "seat_wins": rec.get("seat_wins"),
            "scenarios": rec.get("scenarios") or [],
        }


def fitness_of(rec):
    return float(rec.get("fitness", 0))


def run_loop():
    restore_state()
    hints = load_hints()
    with lock:
        state["gpu"] = False
        state["sigma"] = hints["sigma"]
        state["pop"] = hints["pop"]
        state["episode_ticks"] = hints["episode_ticks"]
        state["notes"] = hints.get("notes", "")
        state["fitness_version"] = FITNESS_VERSION
    theta, best_f = load_best()
    with lock:
        state["best_fitness"] = best_f
        state["error"] = ""
        state["pool"] = list(hints.get("pool") or START_POOL)
    kernels = KernelPool(WORKERS)
    gen = int(state.get("generation") or 0)
    rng = __import__("random").Random(hints.get("seed", 1701))
    np = __import__("numpy")
    theta = np.array(theta, dtype=np.float64)
    best_wins = -1
    bench_done = False

    def eval_weights(w, scenarios):
        t0 = time.time()
        rec = kernels.eval_scenarios(w, scenarios)
        rec["eval_s"] = time.time() - t0
        rec["weights"] = [float(x) for x in w]
        return rec

    try:
        train_scen = make_train_scenarios(hints, gen)
        hold_scen = make_hold_scenarios(hints)
        baseline = eval_weights(theta.tolist(), hold_scen)
        best_f = float(baseline.get("fitness") or 0)
        best_wins = int(baseline.get("seat_wins") or 0)
        save_best(theta, baseline, gen)
        with lock:
            state["best_fitness"] = best_f
        log(f"baseline hold {best_f:.2f} dual={baseline.get('dual')} seats={best_wins} n={len(hold_scen)}")
        with lock:
            state["n_train"] = len(train_scen)
            state["n_hold"] = len(hold_scen)
        save_status()

        while not stop.is_set():
            hints = load_hints()
            pop = hints["pop"]
            sigma = hints["sigma"]
            lr = hints["lr"]
            ticks = hints["episode_ticks"]
            train_scen = make_train_scenarios(hints, gen)
            hold_scen = make_hold_scenarios(hints)
            with lock:
                state["sigma"] = sigma
                state["pop"] = pop
                state["episode_ticks"] = ticks
                state["notes"] = hints.get("notes", "")
                state["paused"] = bool(hints.get("pause"))
                state["n_train"] = len(train_scen)
                state["n_hold"] = len(hold_scen)
                state["pool"] = list(hints.get("pool") or START_POOL)
            if hints.get("pause"):
                save_status()
                time.sleep(1)
                continue

            half = max(4, pop // 2)
            ship_pool = list(hints.get("pool") or START_POOL)
            noises = [np.array([rng.gauss(0, 1) for _ in range(N_WEIGHTS)]) for _ in range(half)]
            recs = []
            dirs = []
            for eps in noises:
                if stop.is_set():
                    break
                plus = eval_weights((theta + sigma * eps).tolist(), train_scen)
                minus = eval_weights((theta - sigma * eps).tolist(), train_scen)
                recs.extend([plus, minus])
                dirs.extend([eps, -eps])
                with lock:
                    state["lives"] += 2 * len(train_scen)
                    state["eval_s"] = plus.get("eval_s", 0)
                    state["error"] = plus.get("error") or minus.get("error") or state["error"]
                save_status()
                if not bench_done and plus.get("eval_s"):
                    nsc = max(1, len(train_scen))
                    tps = (ticks * nsc) / max(1e-6, plus["eval_s"])
                    log(f"bench {tps:.0f} scenario-ticks/s over {plus['eval_s']:.3f}s x{nsc}")
                    bench_done = True

            if not recs:
                break
            fits = [float(r.get("fitness") or 0) for r in recs]
            ranks = centered_ranks(fits)
            step = np.zeros_like(theta)
            for u, eps in zip(ranks, dirs):
                step += u * eps
            theta = theta + (lr / max(1, len(recs))) * step

            mean = sum(fits) / len(fits)
            own = sum(float(r.get("own") or 0) for r in recs) / len(recs)
            enemy = sum(float(r.get("enemy") or 0) for r in recs) / len(recs)
            wins = int(sum(1 for r in recs if r.get("dual")))
            best_i = max(range(len(recs)), key=lambda i: (int(recs[i].get("seat_wins") or 0), fits[i]))
            cand = recs[best_i]
            hold = eval_weights(cand["weights"], hold_scen)
            with lock:
                state["lives"] += len(hold_scen)
            hold["core_dual"] = bool(hold.get("dual"))
            hold_wins = int(hold.get("seat_wins") or 0)
            hold_fit = float(hold.get("fitness") or 0)
            if (hold_wins, hold_fit) > (best_wins, best_f):
                best_wins = hold_wins
                best_f = hold_fit
                save_best(cand["weights"], hold, gen)
                log(f"champion hold {best_f:.2f} dual={hold.get('dual')} seats={hold_wins}/{len(hold_scen)}")
                ship_pool, grew = maybe_expand_pool(hints, hold)
                if grew:
                    best_f = float("-inf")
                    best_wins = -1
                    hints = load_hints()
                    log("pool grew, reset champion fitness")
            with lock:
                state["pool"] = ship_pool

            gen += 1
            with lock:
                state["generation"] = gen
                state["best_fitness"] = best_f
                state["mean_fitness"] = mean
                state["wins"] += wins
                state["own"] = own
                state["enemy"] = enemy
                state["history"].append({"gen": gen, "mean": mean, "best": best_f, "own": own, "enemy": enemy, "wins": wins})
            with METRICS.open("a") as f:
                f.write(
                    json.dumps(
                        {
                            "gen": gen,
                            "mean": mean,
                            "best": best_f,
                            "own": own,
                            "enemy": enemy,
                            "wins": wins,
                            "sigma": sigma,
                            "fitness_version": FITNESS_VERSION,
                            "n_train": len(train_scen),
                            "n_hold": len(hold_scen),
                            "pool": list(hints.get("pool") or START_POOL),
                        }
                    )
                    + "\n"
                )
            save_status()
            log(f"gen {gen} mean {mean:.2f} best {best_f:.2f} crew {own:.1f}/{enemy:.1f} wins+{wins} nsc={len(train_scen)}")
    except Exception as e:
        log(f"loop crash: {e}")
        with lock:
            state["error"] = str(e)
        save_status()
        raise
    finally:
        kernels.close()


def main():
    if not KERNEL.exists():
        log("kernel.js missing")
        sys.exit(2)
    restore_state()
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    log(f"dashboard http://0.0.0.0:{PORT}")
    save_status()

    def handle(sig, _frm):
        log(f"signal {sig}")
        stop.set()

    signal.signal(signal.SIGINT, handle)
    signal.signal(signal.SIGTERM, handle)
    run_loop()
    httpd.shutdown()


if __name__ == "__main__":
    main()
