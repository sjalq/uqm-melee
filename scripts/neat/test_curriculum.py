import unittest
from curriculum import expansion_gate, finish_stage, next_opponents
from layout import ALL_SHIPS, START_POOL


def result(wins_by_opponent):
    flags = []
    scenarios = []
    for opponent, wins in wins_by_opponent.items():
        flags += [True] * wins + [False] * (100 - wins)
        scenarios += [{'them': opponent}] * 100
    return {'wins': sum(flags), 'fights': len(flags), 'flags': flags, 'scenarios': scenarios}


class CurriculumTests(unittest.TestCase):
    def test_gate_needs_competence_gain_and_no_weak_opponent(self):
        reference = result({'Pkunk': 50, 'Umgah': 50, 'Yehat': 50})
        self.assertTrue(expansion_gate(reference, result({'Pkunk': 60, 'Umgah': 60, 'Yehat': 60})))
        self.assertFalse(expansion_gate(reference, result({'Pkunk': 59, 'Umgah': 60, 'Yehat': 60})))
        self.assertFalse(expansion_gate(reference, result({'Pkunk': 100, 'Umgah': 100, 'Yehat': 39})))
        self.assertFalse(expansion_gate(result({'Pkunk': 60}), result({'Pkunk': 69})))
        self.assertFalse(expansion_gate(result({'Pkunk': 0}), result({'Pkunk': 59})))

    def test_expansion_only_appends_one_ship_without_repeats(self):
        roster = list(START_POOL)
        self.assertEqual(next_opponents(roster), roster + ['Earthling'])
        while len(roster) < len(ALL_SHIPS):
            expanded = next_opponents(roster)
            self.assertEqual(expanded[:-1], roster)
            self.assertEqual(len(set(expanded)), len(roster) + 1)
            roster = expanded
        self.assertEqual(next_opponents(roster), roster)

    def test_completed_stage_moves_reference_and_clears_pending(self):
        state = {'stage': 0, 'opponents': list(START_POOL), 'reference': 'old'}
        pending = {'opponents': next_opponents(state['opponents']), 'reference': 'new'}
        new = finish_stage(state, pending)
        self.assertEqual(new['stage'], 1)
        self.assertEqual(new['reference'], 'new')
        self.assertIsNone(new['pending'])
        self.assertEqual(state['stage'], 0)
