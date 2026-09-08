#!/usr/bin/env python3
"""Hand linear prior: face, close, fire only on a hit solution. Must match Policy.elm."""

from __future__ import annotations

from layout import N_CONTROLS, N_IN, N_OBS, N_OUT, N_WEIGHTS

# Encode.vector indices
ENERGY, CREW, FACE_C, FACE_S, SPEED, TRAVEL_C, TRAVEL_S = range(7)
WREADY, SREADY, TREADY, THREADY = 7, 8, 9, 10
DX, DY, DIST, CLOSING = 11, 12, 13, 14
REL_C, REL_S, FOE_ENERGY, FOE_CREW, FOE_SPEED, CLOAKED = 15, 16, 17, 18, 19, 20
MYHIT, MYHIT2, TURN_ERR, THEIRHIT, THEIRHIT2 = 21, 22, 23, 24, 25
PDX, PDY, PHIT, IN_HIT, IN_C, IN_S, OBS_ONE = 26, 27, 28, 29, 30, 31, 32

LEFT, RIGHT, THRUST, WEAPON, SPECIAL = range(5)


def _set(w, out_i, in_i, val):
    w[out_i * N_IN + in_i] = float(val)


def _bias(w, out_i, val):
    w[out_i * N_IN + (N_IN - 1)] = float(val)


def fb(k: int) -> int:
    return N_OBS + k


def pursuit_prior():
    w = [0.0] * N_WEIGHTS
    # Face the foe. turnErr>0 means turn right (DirectPursuit / shortestFacing).
    _set(w, LEFT, TURN_ERR, -8.0)
    _set(w, RIGHT, TURN_ERR, 8.0)
    # Close when far and not sitting in the cone.
    _bias(w, THRUST, 0.15)
    _set(w, THRUST, DIST, 2.5)
    _set(w, THRUST, THEIRHIT, -4.0)
    _set(w, THRUST, THEIRHIT2, -2.0)
    _set(w, THRUST, IN_HIT, -2.0)
    _set(w, THRUST, CLOSING, 0.8)
    # Pkunk has 12 shots and no regen: fire only on a real intercept.
    _set(w, WEAPON, MYHIT, 10.0)
    _set(w, WEAPON, MYHIT2, 6.0)
    _set(w, WEAPON, WREADY, 1.5)
    _set(w, WEAPON, ENERGY, 3.0)
    _bias(w, WEAPON, -2.0)
    _bias(w, SPECIAL, -3.0)
    # Extra 0: leaky lined-up memory, keeps a short fury burst.
    _set(w, N_CONTROLS, MYHIT, 1.2)
    _set(w, N_CONTROLS, fb(5), 0.55)
    _bias(w, N_CONTROLS, -0.2)
    _set(w, WEAPON, fb(5), 2.0)
    # Extra 1: cone memory, cuts thrust.
    _set(w, N_CONTROLS + 1, THEIRHIT, 1.4)
    _set(w, N_CONTROLS + 1, fb(6), 0.5)
    _set(w, THRUST, fb(6), -2.5)
    assert len(w) == N_WEIGHTS
    return w


if __name__ == "__main__":
    print(N_WEIGHTS, N_OUT, N_IN, sum(abs(x) for x in pursuit_prior()))
