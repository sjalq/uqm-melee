#!/usr/bin/env python3
"""Stop at the first divergent Elm/Rust event and preserve both full states."""
import argparse
import json
import math
import os
import selectors
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def difference(a, b, path="$"):
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return {"path": path, "elm_keys": sorted(a), "rust_keys": sorted(b)}
        for key in a:
            result = difference(a[key], b[key], f"{path}.{key}")
            if result:
                return result
        return None
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return {"path": path, "elm_length": len(a), "rust_length": len(b)}
        for index, (x, y) in enumerate(zip(a, b)):
            result = difference(x, y, f"{path}[{index}]")
            if result:
                return result
        return None
    if a == b and (isinstance(a, bool) == isinstance(b, bool)):
        return None
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and (isinstance(a, float) or isinstance(b, float)):
        if math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12):
            return None
    return {"path": path, "elm": a, "rust": b}


def read(proc):
    buffer = getattr(proc, "_trace_buffer", b"")
    deadline = time.monotonic() + 180
    with selectors.DefaultSelector() as selector:
        selector.register(proc.stdout, selectors.EVENT_READ)
        while b"\n" not in buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise TimeoutError("trace produced no complete record within 180 seconds")
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError(f"trace stream ended before done, exit={proc.poll()}")
            buffer += chunk
    line, proc._trace_buffer = buffer.split(b"\n", 1)
    return json.loads(line)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("job", type=Path)
    parser.add_argument("--rust-worker", type=Path, default=ROOT / "rust/target/release/melee-worker")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    job = {**json.loads(args.job.read_text()), "trace": True}
    workers = []
    count = 0
    result = None
    previous = None
    try:
        for command in (["node", str(ROOT / "scripts/oracle/neat-trace.js")], [str(args.rust_worker.resolve())]):
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
            workers.append(process)
            process.stdin.write(json.dumps(job, allow_nan=False) + "\n")
            process.stdin.flush()
        while True:
            elm, rust = (read(process) for process in workers)
            diff = difference(elm, rust)
            if diff:
                result = {"matched_records": count, "difference": diff, "previous": previous, "elm": elm, "rust": rust, "job": job}
                break
            count += 1
            if elm.get("type") == "error":
                raise ValueError(elm)
            if elm.get("type") == "done":
                result = {"matched_records": count, "difference": None, "job": job}
                break
            previous = {"elm": elm, "rust": rust}
    finally:
        for process in workers:
            process.terminate()
        for process in workers:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, allow_nan=False) + "\n")
    print(json.dumps({"matched_records": count, "difference": result["difference"]}))
    return result["difference"] is not None


if __name__ == "__main__":
    raise SystemExit(main())
