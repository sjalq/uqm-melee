"""Deterministic scenarios for opt-in focused matchup training."""

from __future__ import annotations

import hashlib

from layout import ALL_SHIPS


MAX_SEED = 2**31 - 1
TRAINING_SEED_MAX = 999_999_999
VALIDATION_SEED_MIN = 1_000_000_000
VALIDATION_SEED_MAX = MAX_SEED - 1


def _seeds(value, name, minimum=1, maximum=MAX_SEED):
    if not isinstance(value, list) or not value:
        raise ValueError(f"{name} must be a non-empty list")
    if any(isinstance(seed, bool) or not isinstance(seed, int) or not minimum <= seed <= maximum for seed in value):
        raise ValueError(f"{name} seeds must be between {minimum} and {maximum}")
    if len(set(value)) != len(value):
        raise ValueError(f"{name} must not contain duplicates")
    return list(value)


def validate_config(hints):
    if "training_pairs" not in hints:
        return None
    pool = hints.get("pool")
    if not isinstance(pool, list) or not pool or len(set(pool)) != len(pool) or any(ship not in ALL_SHIPS for ship in pool):
        raise ValueError("pool must contain unique, known ships")
    pairs = hints["training_pairs"]
    if not isinstance(pairs, list) or not pairs:
        raise ValueError("training_pairs must be a non-empty list")
    normalized = []
    for pair in pairs:
        if not isinstance(pair, list) or len(pair) != 2 or any(not isinstance(ship, str) for ship in pair):
            raise ValueError("training_pairs entries must be [us, them]")
        item = tuple(pair)
        if item[0] not in pool or item[1] not in pool:
            raise ValueError("training_pairs ships must belong to pool")
        normalized.append(item)
    if len(set(normalized)) != len(normalized):
        raise ValueError("training_pairs must not contain duplicates")
    validation_seeds = _seeds(
        hints.get("validation_seeds"), "validation_seeds", VALIDATION_SEED_MIN, VALIDATION_SEED_MAX
    )
    hold_seeds = _seeds(hints.get("hold_seeds"), "hold_seeds")
    if set(validation_seeds) & set(hold_seeds):
        raise ValueError("validation_seeds and hold_seeds must be disjoint")
    base = hints.get("fresh_seed_base")
    if isinstance(base, bool) or not isinstance(base, int) or not 0 < base <= MAX_SEED:
        raise ValueError("fresh_seed_base must be a positive 31-bit integer")
    return {
        "pairs": normalized,
        "validation_seeds": validation_seeds,
        "excluded_seeds": set(validation_seeds) | set(hold_seeds),
        "fresh_seed_base": base,
    }


def _fresh_seed(base, gen, index, excluded, used):
    nonce = 0
    while True:
        payload = f"focused-v1:{base}:{gen}:{index}:{nonce}".encode()
        # Training owns the low namespace; validation and audit seeds own the high namespace.
        seed = int.from_bytes(hashlib.sha256(payload).digest()[:4], "big") % TRAINING_SEED_MAX + 1
        if seed not in excluded and seed not in used:
            return seed
        nonce += 1


def _scenario(hints, pair, seed, swap, group):
    return {
        "us": pair[0],
        "them": pair[1],
        "foe": "cyborg",
        "rating": str(hints.get("rating") or "awesome"),
        "seed": seed,
        "swap": swap,
        "ticks": int(hints["episode_ticks"]),
        "group": group,
    }


def training_scenarios(hints, gen):
    config = validate_config(hints)
    if config is None:
        raise ValueError("training_pairs must be explicitly configured")
    if isinstance(gen, bool) or not isinstance(gen, int) or gen < 0:
        raise ValueError("generation must be a non-negative integer")
    used = set()
    out = []
    for index in range(4):
        pair = config["pairs"][(gen * 4 + index) % len(config["pairs"])]
        seed = _fresh_seed(config["fresh_seed_base"], gen, index, config["excluded_seeds"], used)
        used.add(seed)
        group = f"focused:{pair[0]}-{pair[1]}"
        out.extend(_scenario(hints, pair, seed, swap, group) for swap in (False, True))
    return out


def validation_scenarios(hints):
    config = validate_config(hints)
    if config is None:
        raise ValueError("training_pairs must be explicitly configured")
    return [
        _scenario(hints, pair, seed, swap, f"focused-validation:{pair[0]}-{pair[1]}")
        for pair in config["pairs"]
        for seed in config["validation_seeds"]
        for swap in (False, True)
    ]
