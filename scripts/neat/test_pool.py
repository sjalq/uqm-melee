#!/usr/bin/env python3
"""v8 pool: 5-bit hull ids, hidden layer, 3x3 cyborg only."""

import sys
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

assert FITNESS_VERSION == "v8-bits-hid"
assert N_KIND == 10
assert N_HIDDEN == 16
assert N_IN == 33 + 10 + 13 + 1 == 57
assert N_W1 == N_HIDDEN * N_IN
assert N_W2 == N_OUT * (N_HIDDEN + 1)
assert N_WEIGHTS == N_W1 + N_W2 == 1133
assert N_SHIPS == 25
assert START_POOL == ["Pkunk", "Umgah", "Yehat"]
assert pool_pairs(START_POOL) == [(a, b) for a in START_POOL for b in START_POOL]
assert len(pool_pairs(START_POOL)) == 9

hints = {
    "pool": list(START_POOL),
    "train_seeds": [1701, 2137],
    "hold_seeds": [42, 99],
    "episode_ticks": 1800,
    "rating": "awesome",
}
hold = make_hold_scenarios(hints)
train = make_train_scenarios(hints, 0)
assert len(hold) == 18
assert len(train) == 18
assert all(s["foe"] == "cyborg" for s in hold + train)
assert {s["us"] for s in hold} == set(START_POOL)
assert {s["them"] for s in hold} == set(START_POOL)
assert sum(1 for s in hold if s["swap"]) == 9
print("pool_ok")
