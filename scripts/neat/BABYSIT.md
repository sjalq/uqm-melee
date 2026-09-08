# LLM babysit notes

Trainer reads `scripts/neat/hints.json` every generation.
Hall of fame is `artifacts/neat/hall/`.
Live status is `artifacts/neat/status.json` and dashboard `http://192.168.0.123:8788`.

Version: `v8-bits-hid`. Width 1133. 5-bit hull ids, 16 hidden tanh units. One net vs frozen Awesome cyborg.
Identity: two 25-wide one-hots (our hull, their hull) in Melee.Ship constructor order.

## What you may change in hints.json

- `sigma` (mutation scale, 0.03-0.3)
- `pop` (16-32 on this box)
- `episode_ticks` (600-1800)
- `pause` (true to freeze evolution, keep dashboard)
- `notes` (your hypothesis)
- `expand_at` (hold win rate to add the next catalog hull, default 0.8)

## Do not

- Raise CPU above 2 cores or RAM above 4G
- Add cloak / wait-timer inputs
- Change the Elm engine
- Treat leftover v5 12/12 or a million-minus-ticks WIN card as this run
- Expand the pool by editing it unless hold wins are actually at the gate

## Goal

Hold record is the number: completed, our seat, enemy crew 0, on the fixed hold set.
Start pool is Pkunk, Umgah, Yehat (all 3x3 pairs, both seats). Add the next catalog ship only after hold wins hit 80%. Keep going until 25 vs 25 is reliable.
