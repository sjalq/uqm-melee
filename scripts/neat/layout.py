"""Must match tests/Neat/Policy.elm and Neat.Encode."""

N_COMBAT = 33
N_KIND_BITS = 5
N_KIND = N_KIND_BITS * 2
N_OBS = N_COMBAT + N_KIND
N_CONTROLS = 5
N_EXTRA = 8
N_FEEDBACK = N_CONTROLS + N_EXTRA
N_HIDDEN = 16
N_IN = N_OBS + N_FEEDBACK + 1
N_OUT = N_CONTROLS + N_EXTRA
N_W1 = N_HIDDEN * N_IN
N_W2 = N_OUT * (N_HIDDEN + 1)
N_WEIGHTS = N_W1 + N_W2
FITNESS_VERSION = "v8-bits-hid"
ALL_SHIPS = [
    "Androsynth",
    "Arilou",
    "Chenjesu",
    "Chmmr",
    "Druuge",
    "Earthling",
    "Ilwrath",
    "KohrAh",
    "Melnorme",
    "Mmrnmhrm",
    "Mycon",
    "Orz",
    "Pkunk",
    "Shofixti",
    "Slylandro",
    "Spathi",
    "Supox",
    "Syreen",
    "Thraddash",
    "Umgah",
    "UrQuan",
    "Utwig",
    "Vux",
    "Yehat",
    "ZoqFotPik",
]
START_POOL = ["Pkunk", "Umgah", "Yehat"]
N_SHIPS = len(ALL_SHIPS)
