#!/usr/bin/env python3

import importlib.util
import json
import random
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
FROZEN = ROOT / "artifacts/neat/releases/plateau-v1/scripts/neat"
SPEC = importlib.util.spec_from_file_location("plateau_train", FROZEN / "train.py")
train = importlib.util.module_from_spec(SPEC)
with patch.dict("sys.modules", {}):
    SPEC.loader.exec_module(train)

BASE = {
    "pool": ["Pkunk", "Umgah", "Yehat"],
    "train_seeds": [1701, 2137],
    "hold_seeds": [42, 99, 1234],
    "episode_ticks": 1800,
    "rating": "awesome",
}


class PlateauSamplingTests(unittest.TestCase):
    def load(self, updates):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hints.json"
            path.write_text(json.dumps(updates))
            with patch.object(train, "HINTS", path), patch.object(train, "CONTROL", None):
                return train.load_hints()

    def test_population_64_is_accepted_and_larger_is_rejected(self):
        self.assertEqual(self.load({"pop": 64})["pop"], 64)
        with self.assertRaisesRegex(ValueError, "at most 64"):
            self.load({"pop": 65})

    def test_default_training_scenarios_are_unchanged(self):
        scenarios = train.make_train_scenarios(BASE, 0)
        self.assertEqual(len(scenarios), 9)
        self.assertEqual(
            [(item["us"], item["them"]) for item in scenarios],
            train.pool_pairs(BASE["pool"]),
        )
        self.assertTrue(all(not item["group"].startswith(("practice:", "broad:")) for item in scenarios))

    def test_practice_and_broad_draws_balance_over_two_generations(self):
        hints = {**BASE, "practice_pairs": [["Pkunk", "Umgah"]]}
        generations = [train.make_train_scenarios(hints, gen) for gen in range(2)]
        self.assertEqual([len(batch) for batch in generations], [9, 9])
        self.assertEqual(
            [sum(item["group"].startswith("practice:") for item in batch) for batch in generations],
            [4, 5],
        )
        self.assertEqual(sum(item["group"].startswith("broad:") for batch in generations for item in batch), 9)
        self.assertEqual({item["swap"] for item in generations[0]}, {False})
        self.assertEqual({item["swap"] for item in generations[1]}, {True})

    def test_selection_is_deterministic_and_broad_cycle_covers_every_pair(self):
        hints = {**BASE, "practice_pairs": [["Pkunk", "Umgah"], ["Yehat", "Pkunk"]]}
        random.seed(9182)
        before = random.getstate()
        first = [train.make_train_scenarios(hints, gen) for gen in range(2)]
        self.assertEqual(first, [train.make_train_scenarios(hints, gen) for gen in range(2)])
        self.assertEqual(random.getstate(), before)
        broad_pairs = {
            (item["us"], item["them"])
            for batch in first
            for item in batch
            if item["group"].startswith("broad:")
        }
        self.assertEqual(broad_pairs, set(train.pool_pairs(BASE["pool"])))

    def test_invalid_practice_pairs_are_rejected(self):
        invalid = (
            {"practice_pairs": "Pkunk-Umgah"},
            {"practice_pairs": [["Pkunk"]]},
            {"practice_pairs": [["Pkunk", "Umgah"], ["Pkunk", "Umgah"]]},
            {"practice_pairs": [["Pkunk", "Androsynth"]]},
        )
        for hints in invalid:
            with self.subTest(hints=hints), self.assertRaises(ValueError):
                self.load(hints)

    def test_hold_scenarios_are_unchanged_by_practice_pairs(self):
        plain = train.make_hold_scenarios(BASE)
        practiced = train.make_hold_scenarios({**BASE, "practice_pairs": [["Pkunk", "Umgah"]]})
        self.assertEqual(practiced, plain)
        self.assertEqual(len(plain), 54)


if __name__ == "__main__":
    unittest.main()
