#!/usr/bin/env python3
"""Differential check of the Rust MarI/O graph runtime against the Elm oracle.

WHAT IT PROVES

  Both implementations are driven with the same deterministic pseudo-random
  genomes and the same step sequences, and every one of the 13 outputs of every
  step must agree. Cycles, self loops, disabled genes, shuffled gene storage,
  partially declared genomes and deliberately invalid genomes are all generated,
  because those are the cases where two independent ports drift apart.

  Output NUMBERS are compared with an absolute tolerance (default 1e-9) rather
  than bitwise, because Elm reaches the exponential through `e ^ x` and Rust
  through `f64::exp`, so the last unit in the last place may differ.

  The five control outputs are ALSO compared as decisions, exactly. A control is
  asserted when its output is strictly greater than zero, and left and right
  asserted together cancel to no turn, so +1e-18 and -1e-18 are numerically
  indistinguishable yet opposite actions. A decision disagreement fails the run
  however small the numeric gap, which is why the generated cases include
  outputs deliberately parked on zero, genes that cancel exactly, and sums whose
  value depends on the innovation ordering rule.

  The one carve-out is a control whose value sits within --decision-epsilon
  (default 1e-12) of zero on BOTH sides. There the sign is decided by the last
  unit in the last place of the exponential, and the two implementations are not
  required to round it the same way, so the run reports a boundary tie and says
  so in the parity claim rather than pretending the ports agree or that they
  have failed. Set --decision-epsilon 0 to treat every such case as a failure.

  Every record is also replayed to prove the graph state resets between records,
  and which records are rejected must match on both sides.

  Running with --elm-only exercises the Elm side alone and PROVES NOTHING about
  the Rust port; it exists so the oracle can be checked before a binary exists.

SETUP

  1. Build the Elm oracle (or pass --build to do it here):

       lamdera make tests/Oracle/MarioPolicy.elm --output=artifacts/oracle/mario-oracle.js

  2. Build the Rust oracle:

       cargo build --manifest-path rust/Cargo.toml --release --bin melee-mario -j 2

  3. Run the check:

       python3 scripts/oracle/check-mario.py --cases 200 --report artifacts/oracle/mario.json

WIRE CONTRACT

  Request, one NDJSON line:

      {"genome": {"schema_version":1,"nodes":[...],"genes":[...]},
       "steps": [{"observations":[127],"previous":[5],"memory":[8]}, ...]}

  Response, ONE LINE PER STEP in order:

      {"outputs":[13 numbers]}

  A rejected record emits a single {"error":"..."} line instead of that record's
  step lines and reading continues. A record with no steps emits nothing.
"""
import argparse
import hashlib
import json
import math
import queue
import random
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
N_OBS = 127
N_CONTROL = 5
N_MEMORY = 8
N_INPUT = N_OBS + N_CONTROL + N_MEMORY + 1
N_OUTPUT = N_CONTROL + N_MEMORY
OUTPUT_BASE = N_INPUT
HIDDEN_BASE = N_INPUT + N_OUTPUT


class Worker:
    """A persistent NDJSON oracle process.

    Lines are drained by a reader thread rather than by selecting on the pipe.
    A worker can answer a whole record in one write, so several lines often land
    in the stream object's own buffer, where select cannot see them.
    """

    def __init__(self, name, command):
        self.name = name
        self.command = command
        self.proc = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1
        )
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self._pump, daemon=True)
        self.reader.start()

    def _pump(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def _line(self, timeout):
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            return None
        if line is None:
            raise RuntimeError(f"{self.name} exited {self.proc.poll()}")
        return line

    def run(self, record, expected_steps, timeout=120):
        """Returns (result, seconds). Result is {"outputs": [...]} or {"error": str}."""
        started = time.perf_counter()
        self.proc.stdin.write(json.dumps(record, allow_nan=False) + "\n")
        self.proc.stdin.flush()

        # A record with no steps must answer with nothing at all, so the only
        # way to observe that is to wait briefly and see silence.
        first = self._line(timeout if expected_steps else 0.5)
        if first is None:
            result = {"outputs": []} if expected_steps == 0 else {"error": "no output"}
            return result, time.perf_counter() - started

        head = json.loads(first)
        if "error" in head:
            result = {"error": head["error"]}
        else:
            outputs = [head["outputs"]]
            for _ in range(expected_steps - 1):
                more = self._line(timeout)
                if more is None:
                    result = {"error": f"only {len(outputs)} of {expected_steps} step lines"}
                    break
                outputs.append(json.loads(more)["outputs"])
            else:
                result = {"outputs": outputs}

        # Anything still queued means the record emitted more lines than the
        # contract allows, and would desynchronise every later record.
        extra = self._line(0.02)
        if extra is not None:
            result = {"error": f"unexpected extra line {extra.strip()[:80]}"}
        return result, time.perf_counter() - started

    def close(self):
        try:
            self.proc.stdin.close()
        except (BrokenPipeError, ValueError):
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


def node_kind(node_id):
    if node_id < OUTPUT_BASE:
        return "input"
    if node_id < HIDDEN_BASE:
        return "output"
    return "hidden"


def genome(rng, allow_partial=True):
    """A random sparse graph. Cycles and self loops are deliberately likely."""
    hidden = rng.randrange(0, 9)
    hidden_ids = list(range(HIDDEN_BASE, HIDDEN_BASE + hidden))
    output_ids = list(range(OUTPUT_BASE, OUTPUT_BASE + N_OUTPUT))
    input_ids = list(range(0, OUTPUT_BASE))

    declared = set(input_ids) | set(output_ids) | set(hidden_ids)
    if allow_partial and rng.random() < 0.25:
        # Drop a few fixed slots the genome will not reference. Both ports must
        # accept this and read an undeclared output as zero.
        for node_id in rng.sample(input_ids, k=rng.randrange(1, 6)):
            declared.discard(node_id)
        for node_id in rng.sample(output_ids, k=rng.randrange(1, 3)):
            declared.discard(node_id)

    sources = sorted(declared)
    destinations = sorted(n for n in declared if n >= OUTPUT_BASE)
    links = {}
    if destinations:
        for _ in range(rng.randrange(0, 40)):
            frm = rng.choice(sources)
            to = rng.choice(destinations)
            if rng.random() < 0.3 and hidden_ids:
                # Bias the sampler towards back edges and self loops so cyclic
                # components are common rather than accidental.
                frm = rng.choice(hidden_ids + output_ids)
                to = rng.choice(hidden_ids) if hidden_ids else to
                if frm not in declared or to not in declared:
                    continue
            links[(frm, to)] = (rng.gauss(0, 1.4), rng.random() > 0.15)

    innovations = rng.sample(range(1, 4000), k=len(links))
    genes = [
        {"innovation": innovation, "from": frm, "to": to, "weight": weight, "enabled": enabled}
        for innovation, ((frm, to), (weight, enabled)) in zip(innovations, links.items())
    ]
    nodes = [{"id": node_id, "kind": node_kind(node_id)} for node_id in sorted(declared)]
    # Storage order must not matter to either port.
    rng.shuffle(nodes)
    rng.shuffle(genes)
    return {"schema_version": 1, "nodes": nodes, "genes": genes}


def steps(rng, count):
    return [
        {
            "observations": [round(rng.uniform(-1, 1), 6) for _ in range(N_OBS)],
            "previous": [float(rng.randrange(2)) for _ in range(N_CONTROL)],
            "memory": [round(rng.uniform(-1, 1), 6) for _ in range(N_MEMORY)],
        }
        for _ in range(count)
    ]


def wired(genes, hidden=()):
    """A full genome carrying exactly the given genes."""
    ids = list(range(0, HIDDEN_BASE)) + list(hidden)
    return {
        "schema_version": 1,
        "nodes": [{"id": node_id, "kind": node_kind(node_id)} for node_id in ids],
        "genes": [
            {"innovation": innovation, "from": frm, "to": to, "weight": weight, "enabled": True}
            for innovation, frm, to, weight in genes
        ],
    }


def decision_records(rng):
    """Cases parked on the decision boundary, where a tolerance based check
    would pass while the two ports disagreed about what the ship actually does.

    The bias input is always exactly 1.0, so a gene out of node 56 with weight w
    drives its output to sigmoid(w), whose sign is the sign of w.
    """
    plain = steps(rng, 3)
    blank = [
        {"observations": [0.0] * N_OBS, "previous": [0.0] * N_CONTROL, "memory": [0.0] * N_MEMORY}
        for _ in range(2)
    ]
    # Observation slots 0 and 1 driven to exactly 1.0, so several distinct input
    # nodes carry the same value. A genome may not declare the same link twice,
    # so cancelling contributions have to arrive from different sources.
    ones = [0.0] * N_OBS
    ones[0] = 1.0
    ones[1] = 1.0
    unit = [
        {"observations": ones, "previous": [0.0] * N_CONTROL, "memory": [0.0] * N_MEMORY}
        for _ in range(2)
    ]
    bias = N_INPUT - 1
    left, right, thrust = OUTPUT_BASE, OUTPUT_BASE + 1, OUTPUT_BASE + 2
    cases = []

    # Outputs a hair either side of zero, and exactly on it. Below roughly
    # 4.5e-17 the sigmoid's own cancellation flattens the answer to zero, so
    # these weights sit at the smallest magnitude that still carries a sign.
    for label, weight in [
        ("smallest signed positive", 1e-16),
        ("smallest signed negative", -1e-16),
        ("just above the flattening point", 5e-16),
        ("just below the flattening point", -5e-16),
        ("flattened positive", 1e-18),
        ("flattened negative", -1e-18),
        ("exact zero", 0.0),
        ("negative zero", -0.0),
    ]:
        cases.append(
            (
                f"boundary {label}",
                {"genome": wired([(1, bias, left, weight), (2, bias, thrust, weight)]), "steps": blank},
            )
        )

    # Two genes that cancel exactly, so the sum is zero and nothing is asserted.
    cases.append(
        (
            "boundary exact cancellation",
            {"genome": wired([(1, bias, left, 3.25), (2, 0, left, -3.25)]), "steps": unit},
        )
    )
    # Near cancellation: the residue is the only thing deciding the action.
    cases.append(
        (
            "boundary near cancellation",
            {"genome": wired([(1, bias, left, 1.0), (2, 0, left, -0.9999999999999999)]), "steps": unit},
        )
    )
    # Summation order decides the answer: 1e16 + 1 - 1e16 is 0 in innovation
    # order and 1 in any other, so this fails loudly if a port reorders.
    cases.append(
        (
            "boundary order dependent sum",
            {
                "genome": wired([(1, bias, left, 1e16), (2, 0, left, 1.0), (3, 1, left, -1e16)]),
                "steps": unit,
            },
        )
    )
    # Both turns asserted must cancel to no turn on both sides.
    cases.append(
        (
            "boundary both turns asserted",
            {"genome": wired([(1, bias, left, 2.0), (2, bias, right, 2.0)]), "steps": blank},
        )
    )
    # One turn asserted while the other sits exactly on zero.
    cases.append(
        (
            "boundary one turn against a zero",
            {"genome": wired([(1, bias, left, 2.0), (2, bias, right, 0.0)]), "steps": blank},
        )
    )
    # A recurrent path whose feedback drifts across zero over several steps.
    cases.append(
        (
            "boundary recurrent drift",
            {
                "genome": wired(
                    [
                        (1, bias, HIDDEN_BASE, 1e-9),
                        (2, HIDDEN_BASE, HIDDEN_BASE, 40.0),
                        (3, HIDDEN_BASE, left, 1.0),
                        (4, HIDDEN_BASE, right, -1.0),
                    ],
                    hidden=(HIDDEN_BASE,),
                ),
                "steps": [blank[0]] * 8,
            },
        )
    )
    # Saturating weights, where both ports must reach the same clamped value.
    cases.append(
        (
            "boundary saturation",
            {"genome": wired([(1, bias, left, 1e308), (2, bias, right, -1e308)]), "steps": plain},
        )
    )
    return cases


def invalid_records(rng):
    """Records both ports must reject, one way or another."""
    base = genome(rng, allow_partial=False)
    good_steps = steps(rng, 2)

    def mutate(change):
        copy = json.loads(json.dumps(base))
        change(copy)
        return copy

    def add_gene(copy, gene):
        copy["genes"].append(gene)

    cases = [
        ("schema version", {"genome": mutate(lambda g: g.update(schema_version=2)), "steps": good_steps}),
        (
            "gene into an input",
            {
                "genome": mutate(lambda g: add_gene(g, {"innovation": 9001, "from": 56, "to": 3, "weight": 1.0, "enabled": True})),
                "steps": good_steps,
            },
        ),
        (
            "undeclared endpoint",
            {
                "genome": mutate(lambda g: add_gene(g, {"innovation": 9002, "from": 9999, "to": OUTPUT_BASE, "weight": 1.0, "enabled": True})),
                "steps": good_steps,
            },
        ),
        (
            "duplicate node",
            {"genome": mutate(lambda g: g["nodes"].append({"id": OUTPUT_BASE, "kind": "output"})), "steps": good_steps},
        ),
        (
            "kind contradicts id",
            {"genome": mutate(lambda g: g["nodes"].append({"id": 71, "kind": "output"})), "steps": good_steps},
        ),
        (
            "unknown kind",
            {"genome": mutate(lambda g: g["nodes"].append({"id": 72, "kind": "neuron"})), "steps": good_steps},
        ),
        ("short observations", {"genome": base, "steps": [{"observations": [0.0] * 4, "previous": [0.0] * 5, "memory": [0.0] * 8}]}),
        ("missing memory field", {"genome": base, "steps": [{"observations": [0.0] * N_OBS, "previous": [0.0] * 5}]}),
        ("missing genome", {"steps": good_steps}),
    ]
    return cases


def decision(outputs):
    """The controls the simulation would actually receive. A control is asserted
    on a strictly positive output, and both turns asserted cancel to no turn."""
    left = outputs[0] > 0.0
    right = outputs[1] > 0.0
    if left and not right:
        turn = "left"
    elif right and not left:
        turn = "right"
    else:
        turn = "none"
    return [turn, outputs[2] > 0.0, outputs[3] > 0.0, outputs[4] > 0.0]


def compare(expected, actual, tolerance, decision_epsilon):
    """Returns (ok, worst absolute difference, reason, kind).

    `kind` is "decision" for a control disagreement that carries real magnitude,
    "tie" for one where every disagreeing control sits within
    `decision_epsilon` of zero, and "" otherwise. A tie is reported but does not
    fail the run: at that magnitude the sign is decided by the last unit in the
    last place of the exponential, and Elm's `e ^ x` and Rust's `f64::exp` are
    not required to round it the same way. A disagreement anywhere else is a
    defect, however small the numeric gap looks.
    """
    if ("error" in expected) != ("error" in actual):
        return False, None, f"elm {summarise(expected)} vs rust {summarise(actual)}", ""
    if "error" in expected:
        # Both rejected the record. The wording is each port's own business.
        return True, None, "", ""
    a, b = expected["outputs"], actual["outputs"]
    if len(a) != len(b):
        return False, None, f"elm produced {len(a)} steps, rust produced {len(b)}", ""
    worst = 0.0
    tie_reason = ""
    for step, (left, right) in enumerate(zip(a, b)):
        if len(left) != N_OUTPUT or len(right) != N_OUTPUT:
            return False, None, f"step {step} width {len(left)} vs {len(right)}", ""
        # Controls first: a decision disagreement matters however small the gap.
        ours, theirs = decision(left), decision(right)
        if ours != theirs:
            disagreeing = [
                slot
                for slot in range(N_CONTROL)
                if (left[slot] > 0.0) != (right[slot] > 0.0)
            ]
            near_zero = all(
                abs(left[slot]) <= decision_epsilon and abs(right[slot]) <= decision_epsilon
                for slot in disagreeing
            )
            reason = (
                f"step {step} controls {ours} vs {theirs} "
                f"from {left[:N_CONTROL]} vs {right[:N_CONTROL]}"
            )
            if not near_zero:
                return False, None, reason, "decision"
            tie_reason = reason
        for slot, (x, y) in enumerate(zip(left, right)):
            if not (math.isfinite(x) and math.isfinite(y)):
                if x != y and not (math.isnan(x) and math.isnan(y)):
                    return False, None, f"step {step} slot {slot}: {x} vs {y}", ""
                continue
            worst = max(worst, abs(x - y))
            if abs(x - y) > tolerance:
                return False, worst, f"step {step} slot {slot}: {x} vs {y}", ""
    return True, worst, tie_reason, "tie" if tie_reason else ""


def summarise(result):
    if "error" in result:
        return f"error({result['error'][:60]})"
    return f"{len(result['outputs'])} steps"


def self_consistency(elm, rng, cases):
    """Elm only checks: a record is a pure function of itself, and the graph
    state resets between records."""
    failures = []
    for index in range(cases):
        record = {"genome": genome(rng), "steps": steps(rng, rng.randrange(1, 6))}
        expected_steps = len(record["steps"])
        first, _ = elm.run(record, expected_steps)
        second, _ = elm.run(record, expected_steps)
        if first != second:
            failures.append({"index": index, "reason": "the same record answered differently"})
    return failures


def parity_claim(elm_only, failures, ties, epsilon):
    """Exactly what this run does and does not establish."""
    if elm_only:
        return "none: --elm-only exercises the Elm oracle alone and says nothing about Rust"
    if failures:
        return "none: the two ports disagreed, see failures"
    claim = (
        "Rust melee-mario reproduces the Elm oracle on every checked record: "
        "identical control decisions, memory within tolerance, identical rejections"
    )
    if epsilon <= 0.0:
        return "STRICT. " + claim
    return (
        f"NOT STRICT: control sign disagreements were forgiven below a magnitude of {epsilon}, "
        f"and {len(ties)} record(s) actually used that allowance. "
        "Rerun with --decision-epsilon 0 for the contractual claim. " + claim
    )


def timing(samples):
    if not samples:
        return None
    return {
        "max_s": max(samples),
        "mean_s": statistics.mean(samples),
        "median_s": statistics.median(samples),
        "min_s": min(samples),
        "total_s": sum(samples),
    }


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--rust", type=Path, default=ROOT / "rust/target/release/melee-mario",
                        help="Rust oracle binary (default: %(default)s)")
    parser.add_argument("--rust-arg", action="append", default=[],
                        help="extra argument for the Rust binary, repeatable (e.g. --rust-arg oracle)")
    parser.add_argument("--bundle", type=Path, default=ROOT / "artifacts/oracle/mario-oracle.js",
                        help="compiled Elm oracle (default: %(default)s)")
    parser.add_argument("--build", action="store_true", help="compile the Elm oracle first")
    parser.add_argument("--cases", type=int, default=200, help="random genomes to check (default: %(default)s)")
    parser.add_argument("--max-steps", type=int, default=12, help="steps per genome (default: %(default)s)")
    parser.add_argument("--seed", type=int, default=20260911, help="generator seed (default: %(default)s)")
    parser.add_argument("--tolerance", type=float, default=1e-9,
                        help="absolute output tolerance (default: %(default)s)")
    parser.add_argument("--decision-epsilon", type=float, default=0.0,
                        help="DIAGNOSTIC ONLY. Control magnitude below which a sign disagreement is "
                             "downgraded from a failure to a reported boundary tie. The default of 0 "
                             "is the contract: control decisions must match exactly. Any non-zero "
                             "value makes the run non-strict and the parity claim says so "
                             "(default: %(default)s)")
    parser.add_argument("--elm-only", action="store_true",
                        help="run the Elm oracle alone; proves nothing about the Rust port")
    parser.add_argument("--report", type=Path, help="write a JSON report here")
    args = parser.parse_args()

    if args.build:
        subprocess.run(
            ["lamdera", "make", "tests/Oracle/MarioPolicy.elm", f"--output={args.bundle}"],
            cwd=ROOT, check=True,
        )
    if not args.bundle.exists():
        parser.error(
            f"missing {args.bundle}; build it with\n"
            f"  lamdera make tests/Oracle/MarioPolicy.elm --output={args.bundle}"
        )
    if not args.elm_only and not args.rust.exists():
        parser.error(
            f"missing {args.rust}; build it with\n"
            "  cargo build --manifest-path rust/Cargo.toml --release --bin melee-mario -j 2\n"
            "or pass --elm-only, which makes no parity claim at all"
        )

    rng = random.Random(args.seed)
    workers = []
    failures = []
    times = {"elm": [], "rust": []}
    checked = 0
    worst_overall = 0.0
    decision_failures = 0
    replays = 0
    ties = []
    try:
        elm = Worker("elm", ["node", str(ROOT / "scripts/oracle/mario-eval.js"), "--bundle", str(args.bundle)])
        workers.append(elm)
        if args.elm_only:
            failures = self_consistency(elm, rng, args.cases)
            checked = args.cases
        else:
            rust = Worker("rust", [str(args.rust)] + args.rust_arg)
            workers.append(rust)
            records = [
                {"genome": genome(rng), "steps": steps(rng, rng.randrange(0, args.max_steps + 1))}
                for _ in range(args.cases)
            ]
            labelled = [(f"random {i}", record) for i, record in enumerate(records)]
            labelled += decision_records(rng)
            labelled += invalid_records(rng)
            for label, record in labelled:
                expected = len(record.get("steps", []))
                # Alternate which port answers first so neither is systematically
                # favoured by warm-up effects in the timing figures.
                if checked % 2:
                    actual, rt = rust.run(record, expected)
                    reference, et = elm.run(record, expected)
                else:
                    reference, et = elm.run(record, expected)
                    actual, rt = rust.run(record, expected)
                checked += 1
                times["elm"].append(et)
                times["rust"].append(rt)
                ok, worst, reason, kind = compare(
                    reference, actual, args.tolerance, args.decision_epsilon
                )
                if worst is not None:
                    worst_overall = max(worst_overall, worst)
                if kind == "tie":
                    ties.append({"case": label, "reason": reason})
                if not ok:
                    failures.append({"case": label, "reason": reason, "control_decision": kind == "decision"})
                    decision_failures += kind == "decision"
                    print(f"mismatch {label}: {reason}", file=sys.stderr, flush=True)

                # Replaying the record must give the same answer: graph state
                # belongs to a record and cannot leak into the next one.
                if expected and checked % 4 == 0:
                    replays += 1
                    again_elm, _ = elm.run(record, expected)
                    again_rust, _ = rust.run(record, expected)
                    for name, before, after in (("elm", reference, again_elm), ("rust", actual, again_rust)):
                        if before != after:
                            failures.append(
                                {"case": label, "reason": f"{name} answered the replayed record differently",
                                 "control_decision": False}
                            )
                            print(f"replay drift {label} in {name}", file=sys.stderr, flush=True)
                if checked % 50 == 0:
                    print(f"checked {checked}; mismatches {len(failures)}", file=sys.stderr, flush=True)
    finally:
        for worker in workers:
            worker.close()

    report = {
        "checked": checked,
        "mismatches": len(failures),
        "control_decision_mismatches": decision_failures,
        "control_boundary_ties": len(ties),
        "control_boundary_tie_cases": [tie["case"] for tie in ties][:20],
        "decision_epsilon": args.decision_epsilon,
        "records_replayed_for_reset": replays,
        "failures": failures[:40],
        "tolerance": args.tolerance,
        "largest_absolute_difference": worst_overall,
        "seed": args.seed,
        "elm_only": args.elm_only,
        "strict": args.decision_epsilon <= 0.0,
        "parity_claim": parity_claim(args.elm_only, failures, ties, args.decision_epsilon),
        "bundle_sha256": hashlib.sha256(args.bundle.read_bytes()).hexdigest(),
        "rust_sha256": None if args.elm_only else hashlib.sha256(args.rust.read_bytes()).hexdigest(),
        "timing": {name: timing(values) for name, values in times.items()},
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, allow_nan=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "failures"}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
