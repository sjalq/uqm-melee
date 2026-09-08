#!/usr/bin/env python3

import json
import math
import os
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from experiment import atomic_json, checked_weights, fork_checkpoint, mutation_indices, noise_vector, tuples
from layout import FITNESS_VERSION, N_WEIGHTS


HERE = Path(__file__).resolve().parent


class AtomicJsonTests(unittest.TestCase):
    def test_writes_strict_finite_json_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "nested" / "state.json"
            payload = {"fitness": 12.5, "weights": [0, -1.25]}
            atomic_json(target, payload)
            self.assertEqual(json.loads(target.read_text()), payload)
            self.assertTrue(target.read_text().endswith("\n"))
            self.assertFalse(target.with_name("state.json.tmp").exists())

    def test_rejects_non_finite_json_without_replacing_target(self):
        for invalid in (math.nan, math.inf, -math.inf):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "state.json"
                original = {"fitness": 4.0}
                atomic_json(target, original)
                with self.assertRaises(ValueError):
                    atomic_json(target, {"fitness": invalid})
                self.assertEqual(json.loads(target.read_text()), original)


class CheckpointTests(unittest.TestCase):
    def test_accepts_only_matching_finite_1133_weight_checkpoint(self):
        weights = [0.0] * N_WEIGHTS
        checkpoint = {"fitness_version": FITNESS_VERSION, "weights": weights}
        self.assertIs(checked_weights(checkpoint), weights)

        invalid_checkpoints = [
            {**checkpoint, "fitness_version": "old-version"},
            {**checkpoint, "weights": weights[:-1]},
            {**checkpoint, "weights": tuple(weights)},
            {**checkpoint, "weights": weights[:-1] + [math.nan]},
            {**checkpoint, "weights": weights[:-1] + [math.inf]},
            {**checkpoint, "weights": weights[:-1] + ["0"]},
            {**checkpoint, "weights": weights[:-1] + [True]},
        ]
        for invalid in invalid_checkpoints:
            with self.subTest(version=invalid.get("fitness_version"), length=len(invalid["weights"])):
                with self.assertRaises(ValueError):
                    checked_weights(invalid)

    def test_json_random_state_round_trip_reconstructs_tuples(self):
        source = random.Random(8675309)
        for _ in range(5):
            source.random()
        encoded_state = json.loads(json.dumps(source.getstate()))

        restored = random.Random()
        restored.setstate(tuples(encoded_state))
        self.assertEqual([source.random() for _ in range(20)], [restored.random() for _ in range(20)])


class NoiseScheduleTests(unittest.TestCase):
    def _expected_noise(self, seed):
        rng = random.Random(seed)
        return rng, [rng.gauss(0, 1) for _ in range(N_WEIGHTS)]

    def test_es_returns_every_draw_and_preserves_rng_consumption(self):
        seed = 12345
        expected_rng, expected = self._expected_noise(seed)
        actual_rng = random.Random(seed)
        self.assertEqual(noise_vector(actual_rng, "es", 4), expected)
        self.assertEqual(actual_rng.getstate(), expected_rng.getstate())

    def test_block_es_masks_only_inactive_weights_without_changing_draws(self):
        for generation in range(7):
            with self.subTest(generation=generation):
                seed = 9000 + generation
                expected_rng, expected = self._expected_noise(seed)
                actual_rng = random.Random(seed)
                actual = noise_vector(actual_rng, "block_es", generation)
                active = set(mutation_indices("block_es", generation))

                self.assertEqual(actual_rng.getstate(), expected_rng.getstate())
                self.assertEqual(len(actual), N_WEIGHTS)
                self.assertEqual(
                    actual,
                    [value if index in active else 0.0 for index, value in enumerate(expected)],
                )

    def test_block_schedule_partitions_weights_and_cycles_every_seven_generations(self):
        blocks = [set(mutation_indices("block_es", generation)) for generation in range(7)]
        self.assertEqual(set().union(*blocks), set(range(N_WEIGHTS)))
        self.assertEqual(sum(len(block) for block in blocks), N_WEIGHTS)
        for left in range(len(blocks)):
            for right in range(left + 1, len(blocks)):
                self.assertTrue(blocks[left].isdisjoint(blocks[right]))
        self.assertEqual(set(mutation_indices("block_es", 7)), blocks[0])
        self.assertEqual(set(mutation_indices("block_es", 13)), blocks[6])

    def test_unknown_mode_is_rejected(self):
        with self.assertRaises(ValueError):
            mutation_indices("not-a-mode", 0)


class RestartTests(unittest.TestCase):
    def _run(self, artifacts, hints, initial, generations, extra=()):
        environment = dict(os.environ)
        environment["NEAT_WORKERS"] = "2"
        subprocess.run(
            [
                sys.executable,
                str(HERE / "train.py"),
                "--artifacts",
                str(artifacts),
                "--hints",
                str(hints),
                "--initial",
                str(initial),
                "--generations",
                str(generations),
                "--no-dashboard",
                *extra,
            ],
            cwd=HERE,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
            timeout=120,
        )

    def test_restart_matches_two_uninterrupted_generations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hints = root / "hints.json"
            initial = root / "initial.json"
            atomic_json(
                hints,
                {
                    "sigma": 0.12,
                    "lr": 0.1,
                    "pop": 8,
                    "episode_ticks": 1800,
                    "seed": 1701,
                    "pause": False,
                    "rating": "awesome",
                    "train_seeds": [1701, 2137],
                    "hold_seeds": [42],
                    "pool": ["Pkunk"],
                    "search": "es",
                    "auto_expand": False,
                },
            )
            atomic_json(initial, {"fitness_version": FITNESS_VERSION, "weights": [0.0] * N_WEIGHTS})
            uninterrupted = root / "uninterrupted"
            restarted = root / "restarted"

            self._run(uninterrupted, hints, initial, 2)
            self._run(restarted, hints, initial, 1)
            forked = root / "forked"
            self._run(forked, hints, initial, 2, ["--resume-from", str(restarted)])
            self._run(restarted, hints, initial, 2)

            complete = json.loads((uninterrupted / "checkpoint.json").read_text())
            resumed = json.loads((restarted / "checkpoint.json").read_text())
            self.assertEqual(resumed["generation"], complete["generation"])
            self.assertEqual(resumed["weights"], complete["weights"])
            self.assertEqual(resumed["rng"], complete["rng"])
            carried = json.loads((forked / "checkpoint.json").read_text())
            for key in ("generation", "weights", "rng"):
                self.assertEqual(carried[key], complete[key])
            lineage = json.loads((forked / "manifest.json").read_text())["resumed_from"]
            self.assertEqual(lineage["generation"], 1)
            self.assertEqual(lineage["artifacts"], str(restarted.resolve()))
            bad_config = json.loads((restarted / "manifest.json").read_text())["provenance"]
            bad_config["config"]["seed"] += 1
            with self.assertRaisesRegex(ValueError, "identical"):
                fork_checkpoint(restarted, root / "bad-fork", bad_config)
            self.assertFalse((root / "bad-fork" / "checkpoint.json").exists())

            variable = {"eval_s"}
            complete_champion = {key: value for key, value in complete["champion"].items() if key not in variable}
            resumed_champion = {key: value for key, value in resumed["champion"].items() if key not in variable}
            self.assertEqual(resumed_champion, complete_champion)
            self.assertEqual(resumed_champion["scenarios"], complete_champion["scenarios"])

            complete_rows = [json.loads(line) for line in (uninterrupted / "metrics.jsonl").read_text().splitlines()]
            resumed_rows = [json.loads(line) for line in (restarted / "metrics.jsonl").read_text().splitlines()]
            self.assertEqual([row["train_seed"] for row in resumed_rows], [1701, 2137])
            self.assertEqual(
                [[scenario["seed"] for scenario in row["candidate_train"]["scenarios"]] for row in resumed_rows],
                [[scenario["seed"] for scenario in row["candidate_train"]["scenarios"]] for row in complete_rows],
            )


if __name__ == "__main__":
    unittest.main()
