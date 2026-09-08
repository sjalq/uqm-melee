import json
import random
import unittest
from layout import N_WEIGHTS
from population import PopulationSearch
from experiment import tuples


class PopulationTests(unittest.TestCase):
    def test_champion_is_retained_and_budget_is_exact(self):
        initial = [0.01] * N_WEIGHTS
        search = PopulationSearch(random.Random(42), initial)
        for stale in [0, 20]:
            search.stale = stale
            proposals = search.propose(17, 0)
            self.assertEqual(len(proposals), 17)
            self.assertEqual(proposals[0], initial)
            self.assertTrue(all(len(w) == N_WEIGHTS for w in proposals))
            self.assertTrue(any(w != initial for w in proposals[1:]))

    def test_restart_reproduces_the_same_candidates(self):
        rng = random.Random(42)
        original = PopulationSearch(rng, [0.0] * N_WEIGHTS)
        original.propose(17, 0)
        original.feedback(False, [0.0] * N_WEIGHTS)
        saved = json.loads(json.dumps(original.snapshot()))
        rng_state = json.loads(json.dumps(rng.getstate()))
        restored_rng = random.Random()
        restored_rng.setstate(tuples(rng_state))
        restored = PopulationSearch(restored_rng, [0.0] * N_WEIGHTS, saved=saved)
        self.assertEqual(original.propose(17, 1), restored.propose(17, 1))

    def test_islands_keep_lineages_and_resume(self):
        rng = random.Random(123)
        search = PopulationSearch(rng, [0.0] * N_WEIGHTS, revision=4)
        proposals = search.propose(17, 0)
        records = [{"weights": w, "seat_wins": i, "fitness": i} for i, w in enumerate(proposals)]
        search.observe(records)
        self.assertEqual(search.parents, [proposals[i] for i in [4, 8, 12, 16]])
        restored_rng = random.Random()
        restored_rng.setstate(tuples(json.loads(json.dumps(rng.getstate()))))
        restored = PopulationSearch(restored_rng, [0.0] * N_WEIGHTS, revision=4,
                                    saved=json.loads(json.dumps(search.snapshot())))
        self.assertEqual(search.propose(17, 1), restored.propose(17, 1))


if __name__ == "__main__":
    unittest.main()
