# NEAT melee trainer handoff

Paused for handoff. Unpause only by setting `scripts/neat/hints.json` `"pause": false` on snowball. Do not expand the ship pool. Do not treat leftover v5 12/12 or v7 3/18 as this run.

## Goal

One weight vector. One net vs frozen original Awesome cyborg. Strategies emit only `BattleInput`. Real Elm engine via `LongGame.runFold`. Caps: 2 CPU cores, 4 GB RAM on snowball.

Curriculum: start at 3 ships, add the next catalog ship only when saved hold kills hit 80% (15/18). Target is eventually reliable 25 vs 25. Never two of our ships in one fight. Never NN vs NN on this run.

## Live box

```
host       schalk@192.168.0.123
repo       /home/schalk/git/uqm-melee
shell      always /bin/bash  (login shell is fish; fish eats python -c and heredocs)
dashboard  http://192.168.0.123:8788
pid        1403794   (train.py, taskset cores 6,7, prlimit 4GiB)
start      bash scripts/neat/start.sh
```

Clients must use `http://localhost:8000` for Lamdera live, but this trainer is the 8788 dashboard, not the game server.

## Snapshot when paused (2026-09-08 ~19:54 SAST)

```
version     v8-bits-hid
weights     1133
pool        Pkunk, Umgah, Yehat
train/hold  18 / 18   all pairs, both seats, foe=cyborg, rating=awesome
gen         21
hold        3/18
hold score  +81186
mean        +12057
champ gen   0 in best.json (first v8 save; log called it gen 1)
kills       Pkunk vs Umgah bottom  1774t  8-0
            Yehat vs Umgah bottom  1374t  20-0
            Yehat vs Umgah top     1384t  18-0
```

Zeros baseline was 0/18 at -2544. Gen 1 already got those 3 kills. Gens 2-21 did not beat 3 kills, so the champion gate held.

`hints.json` on snowball has `"pause": true`. The loop reloads hints every generation (~40s), so it should sit in the pause sleep after the current gen finishes.

## Architecture (v8)

Not a linear 97->13 net anymore.

```
obs 43 = 33 combat + 5-bit our hull + 5-bit their hull
input 57 = obs + 13 feedback + bias
hidden 16 tanh
output 13 = 5 controls (sign>0) + 8 extra tanh memory
W1 16 x 57 = 912
W2 13 x 17 = 221
total 1133
```

Hull bits are constructor-order index in `Encode.roster` / `layout.ALL_SHIPS`, LSB first. 4 bits cannot name 25 ships. 5 bits can. One-hots were dropped; unused-hull weight masking from v7 does not apply.

Identity is read from `State.kind` of the actual combatants inside `Encode.vector`, not stuffed in as a job-only parameter.

Controls: turn L, turn R, thrust, fire, special. Feedback is previous action bits plus the 8 extras. Extras are deterministic, not RNG.

## Score (do not confuse with Hold record)

Per fight in `tests/Neat/Eval.elm`:

```
kill (completed, our seat, enemy crew 0):  1_000_000 - ticks
enemy 0 but not our completed win:         100_000 - ticks + dense
completed loss:                            dense - 3000
timeout / invalidated:                     dense

dense = 1000*damage - 500*hurt + 50*engage - 0.01*ticks
```

18 fight scores -> `cvar_mean` in `scripts/neat/score.py`: 0.5 * mean(worst 25%) + 0.5 * mean(all). That is Hold score / this-gen mean. It is not a win count.

Hold record / seat_wins: completed, winner is our seat, enemy == 0, ticks in (0, budget). **Never use `x or -1` on enemy.** Float 0 is a kill.

Champion save is lexicographic: `(hold_wins, hold_fitness) > (best_wins, best_f)`. More kills always beat fewer. Score only breaks ties. This stopped 2/18 being replaced by 1/18 because timeouts looked nicer.

## Engine / speed

Git HEAD is `d672f84` `Speed authoritative melee simulations`, same as `origin/main`. That is the fast 60 Hz skip to the next 24 Hz physics pump (`LongGame.nextEvent`, plus Step/Local/Masks).

On top of that, uncommitted `tests/Helpers/LongGame.elm` adds `runFold` so the net can rebuild pilots between events without storing strategy functions or NN state in Lamdera models / Seed.

Gens are ~40s (37-49s). Fight sim is >99% of that. The 16-unit matmul is <1%. Do not "speed up training" by adding CPU or cutting the 1800-tick hold budget (current kills are 1374-1774t).

## Rust engine port (in progress, 2026-09-08)

Goal: an input/output identical Rust implementation of the training game loop,
built for maximum speed, with the same interface the trainer already uses, and
ultimately evaluated on the GPU so transport is not the bottleneck.

The Elm kernel is >99% of a generation. Nothing about the trainer, the fitness
function, the hold set or the network changes; only who runs the fight.

### Non-negotiable: identity is proven, not asserted

The port is verified against the Elm by differential oracles that must diff
clean. Compilation proves nothing here.

```
bash scripts/oracle/check.sh      # elm <-> rust differential, must be silent-ok
bash scripts/oracle/gen.sh        # regenerate the derived Rust tables
```

Current state of that check:

```
  ok   primitives (2659 rows)    RNG chains, sine/cosine, arctan, isqrt,
                                 wrap/wrapDelta, full velocity accumulators
  ok   maskchecks (4355 rows)    opaque bitmaps + 361-offset overlap sweeps for
                                 every ship hull and weapon sprite
```

### Why port from the Elm and not from the C

The Elm is what training runs, and it is not identical to the C. Two examples
already found and reproduced deliberately:

- `Melee.Rng.next` has no `if (seed < 0) seed += M` branch, so the battle RNG
  emits negative values where `random.c` never would. The Rust reproduces the
  Elm, negatives included.
- `Melee.Arsenal.launchState` uses `floor (toFloat v / 32)`, a float floor, not
  Elm's truncating `//`. A hand-port that "tidied" this would drift.

Also note `Melee.Step.circlesHit` is f64, not integer. That is exact in Rust,
but it is the one thing that blocks a naive f32 WGSL kernel; the GPU stage has
to keep that path in f64 or restructure it.

### Layout

```
rust/crates/melee-core     units, trig, rng, velocity          verified
rust/crates/melee-sim      catalog, element, masks             tables verified
rust/crates/melee-neat     encode, policy, fitness             not started
rust/crates/melee-worker   stdin/stdout job protocol           not started
tests/Oracle/*.elm         the Elm half of each differential oracle
scripts/oracle/gen.sh      regenerates *_generated.rs from the Elm
scripts/oracle/check.sh    runs every differential sweep
```

`catalog_generated.rs` and `masks_generated.rs` are produced from the Elm by
`scripts/oracle/gen.sh`. Do not hand-edit them: 25 ship stocks, 29 missile
specs, 799 collision masks and 24 317 spans are derived from `Melee.Ship`,
`Melee.Arsenal`, `Melee.Catalog`, `Melee.Art` and `Melee.Masks`, so a change
there is picked up by regenerating rather than by re-typing.

### Design decisions already fixed

- Element iteration is always ascending id order. `arena.queue` is append-only
  plus filter over monotonic ids, and `Dict.values` is ascending key, so both
  orders coincide. The Rust uses a compact 150-slot array in id order.
- All state is fixed-capacity POD (no `Vec`, no `HashMap`) so the same shape
  can move to a compute shader later.
- `i64` everywhere, because Elm Ints are JS doubles: `/` reproduces `//`
  (truncation toward zero) and `rem_euclid` reproduces `modBy`.

### Remaining, in order

1. `Melee.Step` (3302 lines): physics, weapons, collision, gravity.
2. `Melee.Cyborg` (2118 lines): the frozen opponent. Must match exactly or the
   whole training signal changes.
3. `Melee.Local` (845) + `Melee.Init` (380): phases, rounds, victory.
4. `Neat.Encode` / `Neat.Policy` / `Helpers.LongGame` + the fitness record.
5. `melee-worker`: two modes. `--mode line` is a drop-in for `node worker.js`
   (same NDJSON job in, same record out, so `train.py` changes one path). Then
   `--mode batch` takes a whole generation in one call and fans out with rayon,
   which removes the per-fight process round trip.
6. Frame-level trace oracle before 2 lands: per-C-frame digests of both ships,
   the RNG seed and the element queue. Debugging an 1800-tick divergence
   without it is not realistic.
7. GPU (wgpu/WGSL, portable Metal + Vulkan): one fight per invocation, masks
   and weights resident in storage buffers, only the fitness records read back.
   Population weights are ~18k floats per generation, so with the sim on the
   GPU transport is negligible. Blocked on the f64 note above.

### Do not

- Do not "simplify" the arithmetic. The accumulators, the rounding and the
  divergences from C are the simulation.
- Do not claim parity from a clean build. Only `scripts/oracle/check.sh`
  diffing clean counts.
- Do not change the Elm engine to make the Rust agree.


## Files

```
tests/Neat/Encode.elm      combat vector + 5-bit kinds
tests/Neat/Policy.elm      two-layer net, load/step
tests/Neat/Eval.elm        worker: LongGame.runFold, fitness
tests/Neat/Dashboard.elm   dashboard + fish-style net drawing + (i) explainers
tests/Neat/PolicyTests.elm
tests/Helpers/LongGame.elm uncommitted runFold on top of main speed commit
scripts/neat/layout.py     N_* and FITNESS_VERSION
scripts/neat/train.py      OpenAI-ES, hold, expand, /api/status /api/best /api/net
scripts/neat/score.py      cvar_mean, scenario_win, centered_ranks
scripts/neat/hints.json    live knobs, reloaded every gen
scripts/neat/kernel.js     compiled Eval (must rebuild after Elm changes)
scripts/neat/dashboard.js  compiled Dashboard
scripts/neat/start.sh      kill old, taskset 6,7, 4GiB, nohup
scripts/neat/worker.js
scripts/neat/test_pool.py
scripts/neat/BABYSIT.md
```

Compile:

```
lamdera make tests/Neat/Eval.elm --output=scripts/neat/kernel.js
lamdera make tests/Neat/Dashboard.elm --output=scripts/neat/dashboard.js
elm-test-rs --compiler lamdera tests/Neat/PolicyTests.elm
python3 scripts/neat/test_pool.py
```

Deploy to snowball with rsync of those files, then `bash scripts/neat/start.sh`. SSH always `bash -lc`. Never fish.

`/api/best` strips weights. `/api/net` returns weights for the brain drawing (`n_in`, `n_hidden`, `n_out`, `weights`).

## What already failed and was fixed

- Dashboard "WIN 509t" was a fake jackpot from treating CVaR >= 1e5 as 1e6-ticks. Do not bring that back.
- `enemy 0 or -1` false-negatives on hold. Use `e is not None and int(e)==0`.
- `pool, grew = maybe_expand_pool(...)` overwrote `KernelPool`. Workers are `kernels`. Ship list is `ship_pool`.
- v5/v6 metrics.jsonl restored gen 5500+ into a new run. Restore only rows with matching `fitness_version`. Width mismatch starts fresh.
- Completed loss was -100000 vs timeout ~0, so ES learned to kite. Now dense-3000.
- Watcher `watch_neat_v6.sh` used to die on empty SSH. It retries 3 times. Trainer death is not the same as a probe blip.
- Fable 5.1 was out of credits. The architecture review was Claude Sonnet on the same brief.

## Do not

- Raise CPU above 2 cores or RAM above 4G
- Add cloak / wait-timer inputs
- Cut `episode_ticks` below current kill times
- Hand-edit `pool` to add a 4th ship
- NN vs NN / self-play
- Fake damage, forced unstick, or production timeouts to make sims pass
- Store strategy functions in Lamdera models or messages
- Restart `start.sh` just because an old babysit said pid 3848025 / 1082459 is dead
- Call hold score +81k a win. Watch **3/18**
- Use Chrome 9222 unless the user actually has remote debugging up (it was down)

## Next work (ranked, already agreed)

1. Leave it paused until a human unpauses. Then watch whether hold kills rise above 3 under v8. Gen 1 hitting 3/18 from zeros is interesting; gens 2-21 did not add a 4th.
2. If hold is stuck: do not add ships. Look at whether train-set kills exist on seed 1701 that fail on hold seed 42 (overfit).
3. Cap hold work before pool grows. Train already samples 12 pairs after 4 ships. Hold still enumerates every pair every generation. At 25 ships that is 1250 fights/gen. Full hold only on improvement, or every N gens. Not urgent at 3 ships.
4. Sigma decay only after hold kills are actually climbing. 0.12 is still right at 3/18. `hints.json` can change sigma live with no restart.
5. Do not go back to 25+25 one-hots unless 5-bit+hidden is clearly stuck. The hidden layer exists so 5 bits can mix into ship-specific behaviour.

Unpause: on snowball, set `pause` to false in `scripts/neat/hints.json`. No restart required.

Resume after a crash: `best.json` is 1133 weights, `v8-bits-hid`. `bash scripts/neat/start.sh` reloads them and re-scores hold.

## Git

```
local and snowball: d672f84 on main / snowball-es, tracking origin/main
uncommitted: tests/Helpers/LongGame.elm (runFold)
untracked:   scripts/neat/  tests/Neat/
```

Nothing here is committed. The game speed work is already on main. The trainer is not.
