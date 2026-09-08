#!/usr/bin/env python3
"""Regression coverage for the fixed v8 training and hold scenario sets."""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from layout import (  # noqa: E402
    FITNESS_VERSION,
    N_HIDDEN,
    N_IN,
    N_KIND,
    N_OUT,
    N_SHIPS,
    N_W1,
    N_W2,
    N_WEIGHTS,
    START_POOL,
)
from train import make_hold_scenarios, make_train_scenarios, pool_pairs  # noqa: E402


HINTS = {
    "pool": list(START_POOL),
    "train_seeds": [1701, 2137],
    "hold_seeds": [42, 99],
    "episode_ticks": 1800,
    "rating": "awesome",
}


class LayoutTests(unittest.TestCase):
    def test_v8_layout_is_stable(self):
        self.assertEqual(FITNESS_VERSION, "v8-bits-hid")
        self.assertEqual(N_KIND, 10)
        self.assertEqual(N_HIDDEN, 16)
        self.assertEqual(N_IN, 33 + 10 + 13 + 1)
        self.assertEqual(N_W1, N_HIDDEN * N_IN)
        self.assertEqual(N_W2, N_OUT * (N_HIDDEN + 1))
        self.assertEqual(N_WEIGHTS, N_W1 + N_W2)
        self.assertEqual(N_WEIGHTS, 1133)
        self.assertEqual(N_SHIPS, 25)
        self.assertEqual(START_POOL, ["Pkunk", "Umgah", "Yehat"])

    def test_pool_pairs_are_the_complete_ordered_matrix(self):
        expected = [(a, b) for a in START_POOL for b in START_POOL]
        self.assertEqual(pool_pairs(START_POOL), expected)
        self.assertEqual(len(expected), 9)


class ScenarioTests(unittest.TestCase):
    def test_training_rotates_one_seed_and_covers_cycle(self):
        generations = [make_train_scenarios(HINTS, gen) for gen in range(4)]
        self.assertEqual(
            [{scenario["seed"] for scenario in batch} for batch in generations],
            [{1701}, {2137}, {1701}, {2137}],
        )
        self.assertTrue(all(len(batch) == 9 for batch in generations))
        self.assertEqual(
            [{scenario["swap"] for scenario in batch} for batch in generations],
            [{False}, {True}, {False}, {True}],
        )
        expected_pairs = set(pool_pairs(START_POOL))
        for batch in generations:
            self.assertEqual({(scenario["us"], scenario["them"]) for scenario in batch}, expected_pairs)
        self.assertEqual({scenario["seed"] for batch in generations[:2] for scenario in batch}, {1701, 2137})

    def test_training_scenarios_are_fixed_for_every_candidate(self):
        first_candidate = make_train_scenarios(HINTS, 1)
        second_candidate = make_train_scenarios(HINTS, 1)
        self.assertEqual(first_candidate, second_candidate)
        self.assertIsNot(first_candidate, second_candidate)

    def test_hold_uses_every_seed_and_both_seats(self):
        hold = make_hold_scenarios(HINTS)
        self.assertEqual(len(hold), 36)
        self.assertEqual({scenario["seed"] for scenario in hold}, {42, 99})
        self.assertEqual(sum(scenario["swap"] for scenario in hold), 18)
        self.assertEqual({scenario["us"] for scenario in hold}, set(START_POOL))
        self.assertEqual({scenario["them"] for scenario in hold}, set(START_POOL))

    def test_all_scenarios_use_the_frozen_cyborg(self):
        scenarios = make_hold_scenarios(HINTS) + make_train_scenarios(HINTS, 0)
        self.assertTrue(all(scenario["foe"] == "cyborg" for scenario in scenarios))
        self.assertTrue(all("weights" not in scenario for scenario in scenarios))


if __name__ == "__main__":
    unittest.main()
