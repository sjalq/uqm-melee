#!/usr/bin/env python3
"""Real evaluator and checkpoint migration test. Build melee-worker first."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from experiment import atomic_json
from layout import FITNESS_VERSION, N_WEIGHTS

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


class RustMigrationTests(unittest.TestCase):
    def test_rust_continuation_matches_elm_search_and_champion(self):
        binary = ROOT / "rust/target/release/melee-worker"
        self.assertTrue(binary.is_file(), "build Rust melee-worker before running this integration test")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            hints = root / "hints.json"
            initial = root / "initial.json"
            atomic_json(hints, {"sigma": 0.12, "lr": 0.1, "pop": 8, "episode_ticks": 1800,
                               "seed": 20260908, "pause": False, "rating": "awesome",
                               "train_seeds": [1701, 2137], "hold_seeds": [42],
                               "pool": ["Pkunk", "Umgah", "Yehat"], "search": "block_es", "auto_expand": False})
            atomic_json(initial, {"fitness_version": FITNESS_VERSION, "weights": [0.0] * N_WEIGHTS})

            def run(directory, backend, generations, parent=None):
                command = [sys.executable, str(HERE / "train.py"), "--artifacts", str(directory),
                           "--hints", str(hints), "--initial", str(initial), "--generations", str(generations),
                           "--no-dashboard", "--evaluator", backend, "--rust-worker", str(binary)]
                if parent:
                    command += ["--resume-from", str(parent)]
                result = subprocess.run(command, capture_output=True, text=True, timeout=180,
                                        env={**os.environ, "NEAT_WORKERS": "2", "OPENBLAS_NUM_THREADS": "1"})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return json.loads((directory / "checkpoint.json").read_text())

            source = root / "elm"
            run(source, "elm", 1)
            migrated = run(root / "rust", "rust", 2, source)
            expected = run(source, "elm", 2)
            for key in ("generation", "weights", "rng"):
                self.assertEqual(migrated[key], expected[key], key)
            for key in ("weights", "generation", "seat_wins", "fitness", "scenarios"):
                self.assertEqual(migrated["champion"][key], expected["champion"][key], key)
            self.assertEqual(migrated["status"]["history"], expected["status"]["history"])
            self.assertEqual(migrated["status"]["evaluator"], "rust")


if __name__ == "__main__":
    unittest.main()
