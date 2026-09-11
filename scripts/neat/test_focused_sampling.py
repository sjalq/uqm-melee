#!/usr/bin/env python3

import math
import random
import unittest

from focused_sampling import training_scenarios, validate_config, validation_scenarios


HINTS = {
    "pool": ["Pkunk", "Umgah", "Yehat"],
    "training_pairs": [
        ["Pkunk", "Umgah"],
        ["Umgah", "Pkunk"],
        ["Pkunk", "Yehat"],
        ["Yehat", "Pkunk"],
        ["Umgah", "Yehat"],
    ],
    "hold_seeds": [42, 99, 1234],
    "validation_seeds": [1_000_005_001, 1_000_005_002],
    "fresh_seed_base": 918273,
    "episode_ticks": 1800,
    "rating": "awesome",
}


class FocusedSamplingTests(unittest.TestCase):
    def test_missing_training_pairs_is_inert(self):
        hints = {key: value for key, value in HINTS.items() if key != "training_pairs"}
        self.assertIsNone(validate_config(hints))

    def test_training_is_deterministic_resumable_and_does_not_touch_random(self):
        random.seed(81)
        state = random.getstate()
        first = training_scenarios(HINTS, 17)
        self.assertEqual(first, training_scenarios(HINTS, 17))
        self.assertEqual(random.getstate(), state)
        current_seeds = {item["seed"] for item in first}
        next_seeds = {item["seed"] for item in training_scenarios(HINTS, 18)}
        self.assertTrue(current_seeds.isdisjoint(next_seeds))

    def test_training_has_four_fresh_seeds_and_both_seats(self):
        scenarios = training_scenarios(HINTS, 0)
        seeds = {item["seed"] for item in scenarios}
        self.assertEqual(len(scenarios), 8)
        self.assertEqual(len(seeds), 4)
        self.assertTrue(all(0 < seed <= 999_999_999 for seed in seeds))
        self.assertTrue(seeds.isdisjoint(HINTS["hold_seeds"] + HINTS["validation_seeds"]))
        for seed in seeds:
            self.assertEqual({item["swap"] for item in scenarios if item["seed"] == seed}, {False, True})
        self.assertTrue(all(item["foe"] == "cyborg" and item["ticks"] == 1800 for item in scenarios))

    def test_pair_rotation_covers_all_active_pairs_on_schedule(self):
        generations = math.ceil(len(HINTS["training_pairs"]) / 4)
        covered = {
            (item["us"], item["them"])
            for gen in range(generations)
            for item in training_scenarios(HINTS, gen)
        }
        self.assertEqual(covered, {tuple(pair) for pair in HINTS["training_pairs"]})

    def test_validation_enumerates_pairs_seeds_and_seats(self):
        scenarios = validation_scenarios(HINTS)
        self.assertEqual(len(scenarios), len(HINTS["training_pairs"]) * len(HINTS["validation_seeds"]) * 2)
        expected = {
            (tuple(pair), seed, swap)
            for pair in HINTS["training_pairs"]
            for seed in HINTS["validation_seeds"]
            for swap in (False, True)
        }
        actual = {((item["us"], item["them"]), item["seed"], item["swap"]) for item in scenarios}
        self.assertEqual(actual, expected)

    def test_invalid_configuration_is_rejected(self):
        invalid = [
            {"training_pairs": []},
            {"training_pairs": [["Pkunk", "Umgah"], ["Pkunk", "Umgah"]]},
            {"training_pairs": [["Pkunk", "Androsynth"]]},
            {"validation_seeds": [1_000_005_001, 1_000_005_001]},
            {"validation_seeds": [42]},
            {"validation_seeds": [2_147_483_647]},
            {"hold_seeds": [42, 1_000_005_001]},
            {"hold_seeds": [0]},
            {"fresh_seed_base": 0},
        ]
        for update in invalid:
            with self.subTest(update=update), self.assertRaises(ValueError):
                validate_config({**HINTS, **update})


if __name__ == "__main__":
    unittest.main()
