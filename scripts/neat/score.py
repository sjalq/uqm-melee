"""Scenario scores, robust aggregate, centered ranks, win gate."""


def seat_of(rec) -> str:
    return "top" if rec.get("swap") else "bottom"


def is_our_win(rec, us: str, budget: int) -> bool:
    if rec.get("error"):
        return False
    if rec.get("outcome") != "completed" or rec.get("winner") != us:
        return False
    enemy = rec.get("enemy")
    ticks = rec.get("ticks")
    if enemy is None or ticks is None:
        return False
    try:
        enemy_i = int(enemy)
        ticks_i = int(ticks)
    except (TypeError, ValueError):
        return False
    return enemy_i == 0 and 0 < ticks_i < budget


def scenario_win(rec, budget: int) -> bool:
    return is_our_win(rec, seat_of(rec), budget)


def cvar_mean(xs, worst_frac: float = 0.25) -> float:
    vals = [float(x) for x in xs]
    if not vals:
        return 0.0
    vals.sort()
    k = max(1, int(len(vals) * worst_frac))
    cvar = sum(vals[:k]) / k
    mean = sum(vals) / len(vals)
    return 0.5 * cvar + 0.5 * mean


def centered_ranks(fits):
    n = len(fits)
    if n == 0:
        return []
    order = sorted(range(n), key=lambda i: fits[i])
    ranks = [0.0] * n
    if n == 1:
        return ranks
    for r, i in enumerate(order):
        ranks[i] = r / (n - 1) - 0.5
    return ranks


def pair_score(wins: int, fa: float, fb: float) -> float:
    if wins == 2:
        return (fa + fb) / 2.0
    raw = (0.0 if fa >= 100000 else fa) + (0.0 if fb >= 100000 else fb)
    return 100000.0 * wins + raw


def seat_score(rec, us: str) -> float:
    if rec.get("error"):
        return 0.0
    if "fitness" in rec:
        return float(rec.get("fitness") or 0)
    own = int(rec.get("own") or 0)
    enemy = int(rec.get("enemy") or 0)
    ticks = int(rec.get("ticks") or 0)
    if rec.get("outcome") == "completed" and rec.get("winner") == us:
        return 1000000.0 - ticks
    if enemy == 0:
        return 100000.0 - ticks
    start = int(rec.get("enemy_start") or 10)
    own_start = int(rec.get("own_start") or 8)
    damage = max(0, start - enemy) / max(1, start)
    hurt = max(0, own_start - own) / max(1, own_start)
    return 1000.0 * damage - 500.0 * hurt - 0.01 * ticks
