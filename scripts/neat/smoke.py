#!/usr/bin/env python3
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from layout import N_WEIGHTS  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
os.chdir(ROOT)
w = [0.0] * N_WEIGHTS
job = json.dumps({"weights": w, "seed": 1701, "ticks": 60, "swap": False}) + "\n"
t0 = time.time()
p = subprocess.Popen(
    ["node", os.path.join(HERE, "worker.js")],
    cwd=ROOT,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
out, err = p.communicate(job, timeout=180)
print("elapsed", round(time.time() - t0, 2), "code", p.returncode)
print("stdout", out[:2000])
print("stderr", err[-2000:])
