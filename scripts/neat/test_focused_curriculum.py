#!/usr/bin/env python3

import unittest

from focused_curriculum import broad_passes, lesson_passes, lesson_score, seeds


def audit(pair_wins, fights=20):
    scenarios = []
    flags = []
    for pair, wins in pair_wins:
        scenarios.extend({"us": pair[0], "them": pair[1]} for _ in range(fights))
        flags.extend([True] * wins + [False] * (fights - wins))
    return {"scenarios": scenarios, "flags": flags, "wins": sum(flags), "fights": len(flags)}


class LessonGateTests(unittest.TestCase):
    def test_rejects_truncated_outcomes(self):
        result = audit([(("Pkunk", "Umgah"), 12)])
        result["flags"].pop()
        with self.assertRaises(ValueError):
            lesson_score(result, [["Pkunk", "Umgah"]])

    def test_rejects_different_pair_denominators(self):
        pairs = [["Pkunk", "Umgah"], ["Umgah", "Pkunk"]]
        a = audit([(("Pkunk", "Umgah"), 20), (("Umgah", "Pkunk"), 20)])
        b = audit([(("Pkunk", "Umgah"), 20)], fights=30)
        tail = audit([(("Umgah", "Pkunk"), 8)], fights=10)
        b["scenarios"] += tail["scenarios"]
        b["flags"] += tail["flags"]
        self.assertFalse(lesson_passes(a, b, pairs))

    def test_score_requires_coverage_of_every_lesson(self):
        with self.assertRaisesRegex(ValueError, "cover every lesson"):
            lesson_score(audit([(("Pkunk", "Umgah"), 12)]), [["Pkunk", "Umgah"], ["Umgah", "Pkunk"]])

    def test_retention_requires_each_pair_at_least_forty_percent(self):
        pairs = [["Pkunk", "Umgah"], ["Umgah", "Pkunk"], ["Yehat", "Pkunk"]]
        candidate = audit([(("Pkunk", "Umgah"), 7), (("Umgah", "Pkunk"), 17), (("Yehat", "Pkunk"), 12)])
        reference = audit([(("Pkunk", "Umgah"), 7), (("Umgah", "Pkunk"), 17), (("Yehat", "Pkunk"), 10)])
        self.assertEqual(lesson_score(candidate, pairs)["wins"], 36)
        self.assertFalse(lesson_passes(candidate, reference, pairs))

    def test_newest_pair_needs_ten_point_gain_when_reference_is_below_sixty(self):
        pairs = [["Pkunk", "Umgah"], ["Umgah", "Pkunk"]]
        reference = audit([(("Pkunk", "Umgah"), 14), (("Umgah", "Pkunk"), 11)])
        insufficient = audit([(("Pkunk", "Umgah"), 14), (("Umgah", "Pkunk"), 12)])
        enough = audit([(("Pkunk", "Umgah"), 14), (("Umgah", "Pkunk"), 13)])
        self.assertFalse(lesson_passes(insufficient, reference, pairs))
        self.assertTrue(lesson_passes(enough, reference, pairs))

    def test_learned_newest_pair_may_hold_steady(self):
        pairs = [["Pkunk", "Umgah"], ["Umgah", "Pkunk"]]
        reference = audit([(("Pkunk", "Umgah"), 12), (("Umgah", "Pkunk"), 13)])
        candidate = audit([(("Pkunk", "Umgah"), 12), (("Umgah", "Pkunk"), 13)])
        self.assertTrue(lesson_passes(candidate, reference, pairs))


class BroadGateTests(unittest.TestCase):
    def results(self, candidate, original=10, live=10, fights=40):
        return {
            "candidate": {"wins": candidate, "fights": fights},
            "original": {"wins": original, "fights": fights},
            "live": {"wins": live, "fights": fights},
        }

    def test_first_audit_requires_eight_additional_wins_over_both_references(self):
        self.assertTrue(broad_passes(self.results(18)))
        self.assertFalse(broad_passes(self.results(17)))
        self.assertFalse(broad_passes(self.results(18, live=11)))

    def test_confirmation_requires_strict_wins_over_both_references(self):
        self.assertTrue(broad_passes(self.results(11), confirmation=True))
        self.assertFalse(broad_passes(self.results(10), confirmation=True))
        self.assertFalse(broad_passes(self.results(11, live=11), confirmation=True))

    def test_broad_gate_rejects_different_fight_counts(self):
        result = self.results(18)
        result["live"]["fights"] = 39
        self.assertFalse(broad_passes(result))


class SeedNamespaceTests(unittest.TestCase):
    def test_validation_audit_and_confirmation_namespaces_are_disjoint(self):
        validation = set(seeds("run:validation", 100))
        audit_seeds = set(seeds("run:audit", 100))
        confirmation = set(seeds("run:confirmation", 100))
        self.assertTrue(validation.isdisjoint(audit_seeds))
        self.assertTrue(validation.isdisjoint(confirmation))
        self.assertTrue(audit_seeds.isdisjoint(confirmation))
        self.assertTrue(all(1_000_000_000 <= seed < 1_100_000_000 for seed in validation))
        self.assertTrue(all(1_200_000_000 <= seed < 1_600_000_000 for seed in audit_seeds))
        self.assertTrue(all(1_700_000_000 <= seed < 2_100_000_000 for seed in confirmation))


if __name__ == "__main__":
    unittest.main()
