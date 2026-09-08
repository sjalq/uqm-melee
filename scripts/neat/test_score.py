#!/usr/bin/env python3

import itertools
import unittest

from score import cvar_mean, centered_ranks, is_our_win, pair_score, scenario_win, seat_score


class ScenarioScoreTests(unittest.TestCase):
    def test_only_strict_completed_kills_within_budget_are_wins(self):
        bottom_win = {
            "outcome": "completed",
            "winner": "bottom",
            "own": 8,
            "enemy": 0,
            "ticks": 1149,
            "swap": False,
        }
        top_win = {**bottom_win, "winner": "top", "swap": True}
        self.assertTrue(is_our_win(bottom_win, "bottom", 1800))
        self.assertTrue(scenario_win(bottom_win, 1800))
        self.assertTrue(scenario_win(top_win, 1800))

        invalid = [
            {**bottom_win, "error": "worker failed"},
            {**bottom_win, "outcome": "invalidated"},
            {**bottom_win, "winner": "draw"},
            {**bottom_win, "winner": "top"},
            {**bottom_win, "enemy": 1},
            {**bottom_win, "enemy": None},
            {**bottom_win, "ticks": 0},
            {**bottom_win, "ticks": 1800},
            {**bottom_win, "ticks": None},
        ]
        for record in invalid:
            with self.subTest(record=record):
                self.assertFalse(scenario_win(record, 1800))

    def test_combat_scoring_counts_a_resolved_last_tick_win(self):
        record = {"outcome": "completed", "winner": "bottom", "own": 1,
                  "enemy": 0, "ticks": 1800, "display_ticks": 2136,
                  "swap": False, "scoring_version": "combat-v1"}
        self.assertTrue(scenario_win(record, 1800))
        self.assertFalse(scenario_win({**record, "ticks": 1801}, 1800))
        self.assertFalse(scenario_win({**record, "outcome": "invalidated"}, 1800))
        self.assertFalse(scenario_win({**record, "scoring_version": "legacy"}, 1800))

    def test_seat_and_pair_scores_preserve_win_priority(self):
        win = {"outcome": "completed", "winner": "bottom", "fitness": 998851}
        self.assertEqual(seat_score(win, "bottom"), 998851)
        self.assertGreater(pair_score(2, 998851, 998723), pair_score(1, 998851, 200))


class AggregateScoreTests(unittest.TestCase):
    def test_centered_ranks_average_ties_neutrally(self):
        self.assertEqual(centered_ranks([]), [])
        self.assertEqual(centered_ranks([9]), [0.0])
        self.assertEqual(centered_ranks([7, 7, 7, 7]), [0.0, 0.0, 0.0, 0.0])

        ranks = centered_ranks([1.0, 1.0, 3.0, 3.0])
        self.assertAlmostEqual(ranks[0], ranks[1])
        self.assertAlmostEqual(ranks[2], ranks[3])
        self.assertAlmostEqual(sum(ranks), 0.0)

    def test_centered_ranks_are_permutation_invariant(self):
        values = [1.0, 3.0, 1.0, 2.0]
        expected_by_value = {}
        for value, rank in zip(values, centered_ranks(values)):
            expected_by_value[value] = rank

        for permuted in itertools.permutations(values):
            with self.subTest(permuted=permuted):
                actual = centered_ranks(list(permuted))
                self.assertEqual(actual, [expected_by_value[value] for value in permuted])

    def test_cvar_keeps_worst_results_visible(self):
        self.assertAlmostEqual(cvar_mean([10, 20, 30, 40]), 17.5)
        self.assertLess(cvar_mean([1, 100, 100, 100]), cvar_mean([50, 50, 50, 50]))


if __name__ == "__main__":
    unittest.main()
