#!/usr/bin/env python3
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from layout import N_WEIGHTS  # noqa: E402

os.chdir(HERE)
job = json.dumps({"weights": [0.0] * N_WEIGHTS, "seed": 1701, "ticks": 900}) + "\n"
t0 = time.time()
p = subprocess.Popen(
    ["node", "worker.js"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
out, err = p.communicate(job, timeout=60)
print("elapsed", round(time.time() - t0, 3), "code", p.returncode)
print("stdout", out.strip()[:400])
if err:
    print("stderr", err[-300:])
