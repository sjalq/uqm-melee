import unittest
from review_loop import recipe, audit_passes, confirmation_passes
from layout import N_WEIGHTS

class ReviewTests(unittest.TestCase):
    def test_balanced_reproducible_lanes_without_mutating_incumbent(self):
        weights = [0.25] * N_WEIGHTS
        hints = {'search': 'block_es', 'sigma': .12, 'lr': .1}
        lanes = []
        for cycle in range(36):
            result = recipe(cycle, weights, hints)
            self.assertEqual(result, recipe(cycle, weights, hints))
            lanes.append(result[0])
            self.assertEqual(len(result[3]), N_WEIGHTS)
        self.assertEqual([lanes.count(lane) for lane in ['research','creative','radical']], [12,12,12])
        self.assertEqual(weights, [0.25] * N_WEIGHTS)
        self.assertEqual(hints, {'search': 'block_es', 'sigma': .12, 'lr': .1})

    def test_validation_or_fresh_seed_regression_blocks_promotion(self):
        current = {'seat_wins': 22}
        results = {'baseline': {'wins': 90}, 'challenger': {'wins': 97}}
        self.assertFalse(audit_passes(results, current, current, current))
        results['challenger']['wins'] = 98
        self.assertTrue(audit_passes(results, current, current, current))
        self.assertFalse(audit_passes(results, {'seat_wins': 21}, current, current))
        confirmation = {name: {'wins': 100} for name in ['baseline','starting','live','challenger']}
        self.assertFalse(confirmation_passes(confirmation, current, current))
        confirmation['challenger']['wins'] = 101
        self.assertTrue(confirmation_passes(confirmation, current, current))
        self.assertFalse(confirmation_passes(confirmation, {'seat_wins': 21}, current))
