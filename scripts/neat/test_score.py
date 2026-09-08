#!/usr/bin/env python3
from score import cvar_mean, centered_ranks, is_our_win, pair_score, scenario_win, seat_score

win = {"outcome": "completed", "winner": "bottom", "own": 8, "enemy": 0, "ticks": 1149, "swap": False}
assert is_our_win(win, "bottom", 1800)
assert scenario_win(win, 1800)
assert seat_score({**win, "fitness": 998851}, "bottom") == 998851
assert not is_our_win({"outcome": "completed", "winner": "bottom", "own": 0, "enemy": 1, "ticks": 1322, "swap": True}, "top", 1800)
assert not scenario_win({"outcome": "completed", "winner": "bottom", "own": 0, "enemy": 1, "ticks": 1322, "swap": True}, 1800)
assert not is_our_win({"outcome": "completed", "winner": "draw", "own": 0, "enemy": 0, "ticks": 929}, "bottom", 1800)
assert pair_score(2, 998851, 998723) > pair_score(1, 998851, 200)

ranks = centered_ranks([1.0, 3.0, 2.0])
assert abs(ranks[0] + 0.5) < 1e-9
assert abs(ranks[1] - 0.5) < 1e-9
assert abs(ranks[2]) < 1e-9
assert centered_ranks([]) == []
assert centered_ranks([9]) == [0.0]

# [10, 20, 30, 40] worst quarter is 10; mean 25; mix 17.5
assert abs(cvar_mean([10, 20, 30, 40]) - 17.5) < 1e-9
# a single failure cannot be hidden: worst-quarter pulls the mix down
assert cvar_mean([1, 100, 100, 100]) < cvar_mean([50, 50, 50, 50])
print("score_ok")
