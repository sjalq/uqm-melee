## Focused curriculum is running (2026-09-09)

User authorized replacing broad fixed-seed practice after the foundation diagnostic. `uqm-focused.service` now runs `artifacts/neat/releases/focused-v1/scripts/neat/focused_curriculum.py` persistently on CPUs4,5, quota200%, MemoryMax4GiB, swap0. `uqm-review.timer` is disabled; its previous state is in `artifacts/neat/focused/previous-schedule.json`. The existing live trainer/champion and 20-minute health timer remain active. The monitor's `/api/review` shows focused stage/generation and readable fresh results, while live service indicators retain their original meanings.

Training begins with Pkunk vs Umgah, then Umgah vs Pkunk, then the other seven ordered pairings within the original three-ship pool. Each generation uses four newly drawn deterministic seeds, both seats, eight fights and32 candidates. Training seeds occupy1..999999999; fixed lesson validation, fresh audits and confirmations have disjoint higher namespaces. The original54 production hold fights are excluded from training. The immutable base trainer, ES update and Rust scoring-v1 worker are reused; no game or NN activation change. `focused_train.py` is packaged as release/train.py beside the frozen base_train.py. Both adapter and sampler are fingerprinted for exact resume.

Every200generations the current best is checked on20freshseeds across both seats/all nine matchups. Expansion requires60% overall lesson wins, at least40% for each retained matchup, and60% on the new matchup plus a10-point gain over its stage reference (or maintaining an already competent reference), on BOTH the audit and a separate confirmation panel. Retained matchups remain in later training and validation. Unchanged policies are not repeatedly audited within an attempt. Every1000generations an unfinished lesson restarts from its saved best with a new validation panel and mutation scale cycling .04/.08/.12. This is programmed iteration, not an autonomous research agent.

A broad improvement may be promoted independently of lesson expansion: at least8 extra wins over both the original and current live champions in360freshfights, strictly more wins in another360freshfights, and no regression on the separately re-scored54original hold fights. Current live weights and roster are rechecked before switching. A promoted live trainer uses all nine pairs with varied seeds and the original54hold panel. Launcher failure rolls deployment back. No policy has been promoted by the initial preflight. Full-model comparisons are operational gates, not statistical significance claims.

Evidence: `artifacts/neat/focused/state.json`, checks.jsonl, stage-NN/attempt-NNN/{hints,manifest,checkpoint,best}.json and check-NNNNNN audits/results. Local source: scripts/neat/focused_{train,sampling,curriculum}.py and uqm-focused.service. Sixteen pure tests and the monitor test passed. Real Rust smoke tests proved exact checkpoint resume vs an uninterrupted run and the unchanged25/54broad baseline; the two-generation controller preflight completed its real audit (17/40 lesson wins,107/360broad versus114/360live), without promotion.

To stop this experiment use `systemctl --user disable --now uqm-focused.service`; mark focused/state.json enabled=false to restore the legacy monitor view, and enable uqm-review.timer if resuming old recipe trials is desired. Do not start both experiment schedulers. Global scripts/neat/hints.json pause is respected.

## Conditional opponent expansion armed (2026-09-09)

The network keeps flying Pkunk/Umgah/Yehat. The opponent roster expands by exactly one ship after it wins at least 60% overall, at least 40% against each current opponent type, and improves at least 10 percentage points over the last expansion reference on EACH of two independent fresh 20-seed sets. All seats and current matchups are audited. These are operational progress thresholds, not a statistical-significance claim. Earthling is first, followed by Shofixti, Spathi, Arilou and the remaining catalog ships without repeats. Every opponent remains the original Awesome cyborg.

artifacts/neat/curriculum/state.json is enabled at stage 0 with the original three opponents; no live roster expansion has occurred. Each stage freezes its reference weights. The 20-minute health process checks eligibility, but takes the same lock as review trials, so expansion never races a running experiment. At the current 22/54 validation result the cheap competence check refuses expansion before spending additional audit compute. A passed candidate gets an isolated expanded-roster pilot, a newly scored run and recorded provenance, then a guarded switch with rollback. Old scores/checkpoints are not relabelled as scores on a larger roster.

The future trainer release is artifacts/neat/releases/opponents-v1. It adds opponent_pool separately from our pool. It retains every old fight and includes all new pairings every generation; the former 12-pair training subsample does not apply to explicit opponent rosters. The game worker remains the frozen scoring-v1 Rust binary. Review audits, screening gates, confirmation gates and dashboard matchup details support rectangular rosters and scale with the fight count. The current scoring-v1 trainer source, checkpoint and PID remain unchanged.

Validation: an isolated Earthling pilot produced 72 validation fights; all 54 pre-existing fights matched the old saved champion's scenario records exactly. The pilot then resumed from generation 1 to 2 successfully. Unit coverage checks the competence/gain gates, weak-opponent rejection, exactly-one-ship growth, all old matchups and Awesome opponents, and expanded audit thresholds. Elm compiled. No artificial wins were used to trigger a live expansion.

Check-ins use a persistent calendar timer at minutes 00/20/40; experiments use an hourly calendar timer. This avoids re-triggering experiments when unit configuration is reloaded. Health has a 1 GiB ceiling for the future larger audits/pilot; experiment and live trainer limits remain 4 GiB each on separate physical cores. Curriculum details are inside the existing expanded details panel; main progress charts and metrics remain intact.

## Extra experiment capacity (2026-09-09)

The user authorized more resources locally and on Snowball. Experiment, monitor and health services now use CPUs 4,5, separate physical cores from live training on 6,7. Experiments retain two evaluator workers, now at CPUWeight 100 and a 4 GiB memory ceiling. Live training stays on CPUs 6,7 with 4 GiB. Both running processes were moved/configured without restart. Snowball reported about 16 GiB available memory and lightly used CPUs 4,5 before the change. No extra local compute was necessary.

Runtime properties are effective immediately, and persistent unit files plus install_monitor.py match. Do not rerun the older CPU-sharing setup. The 20-minute check-ins, hourly trials, early screening and independent promotion gates remain unchanged. Timing evidence is artifacts/neat/reviews/resource-change.json.

## Check-ins and CPU priority (2026-09-09)

Check-ins now run every 20 minutes via uqm-health.timer. Hourly experiments remain enabled. Every check appends to artifacts/neat/reviews/checkins.jsonl; direct research, bottleneck and design findings are journaled in scripts/neat/review-findings.jsonl on codex/training-monitor and in the monitor-v1 release. This side conversation cannot launch sub-agents; these findings were reviewed directly. There is still no automatic LLM research or debate process.

Observed generation medians during the creative trial were 1.019 seconds (329 generations), versus 0.602 seconds afterward (282 generations). Live training now has CPUWeight 100; trial and health units have CPUWeight 10 on the same CPUs 6,7. This prioritizes the live trainer but cannot guarantee zero contention. Trial per-arm timeout is now 3600 seconds and service timeout 10800 seconds to allow lower-priority work to finish. Post-change throughput benefit has not yet been measured. No trainer restart was needed for this update.

Identical policies now share a single Rust audit within each same-seed comparison. Cycle 0 was confirmed to have identical baseline and challenger weights. Audit labels and selection gates are unchanged. Keep the conservative 40-generation screening stage, informed by adaptive allocation literature, without claiming to implement Hyperband. The live dashboard layout and progress charts are unchanged.

## Hourly experiments, faster feedback (2026-09-09)

Supersedes the 15-minute experiment cadence below: uqm-review.timer now starts new experiments hourly; uqm-health.timer checks progress every 15 minutes. Health checks audit changed champion weights against the previous checked policy (or the run initial policy for the first check), using 360 new paired fights. These checks are diagnostic and do not promote policies. A failed trainer is restarted from checkpoint; an intentionally stopped or paused trainer is not restarted. The dashboard remains on port 8788.

Each trial now runs both arms for 40 generations and reports a 90-fight screening comparison. A challenger at least 8 wins behind, with no fixed-validation advantage, is rejected early. Otherwise both exact checkpoints continue to 160 generations before the unchanged independent deployment gates. This can save 75% of training evaluations for clearly poor candidates, but may miss methods that only improve with longer training. Screening seeds are disjoint from final audits. Plans record a concise case for, case against, previous same-lane result and rejection rule. These are explicit programmed arguments, not an autonomous LLM debate or new paper discovery.

The main dashboard removes duplicate generation/scoring cards and the mixed-crew chart, and folds the network explorer behind an expandable section. Hovers remain. It shows early screening and periodic fresh-seed results. During this update the live champion reached 22/54 validation wins; the first health audit measured 107/360 fresh wins versus 102/360 for the run's starting policy. This is one diagnostic sample, not a confirmed deployment improvement. The creative hidden-unit-reset experiment is running under the new screening rule.

## Live monitoring and continuous recipe trials (2026-09-09)

Dashboard remains http://192.168.0.123:8788. It is now served independently by uqm-monitor.service from artifacts/neat/releases/monitor-v1/scripts/neat, so a trainer restart does not take away the monitoring page. The actual trainer listens on 8789, uses the unchanged scoring-v1 release and Rust worker, and follows its existing checkpoint. Canonical scripts/neat/start.sh now reads artifacts/neat/deployment.json when present to restore a successfully promoted experiment; absence restores scoring-v1. The previous launcher is artifacts/neat/monitor-before-start.sh.

The dashboard prioritizes saved validation wins, generations since promotion, generation duration, approximate fights/second, scoring version, actual service/file freshness, review phase and results, and per-matchup wins. Detailed validation fights are expandable. Existing network and chart hover explanations remain. Practice mean and saved validation score are no longer plotted as comparable lines. Fixed validation wins are explicitly distinguished from fresh audit results.

uqm-review.timer invokes uqm-review.service every 15 minutes, one process at a time. The lanes rotate research, creative, radical, exactly one turn each. These are programmed recipes, NOT an autonomous LLM and NOT recurring new literature research. Research uses mirrored ES parameter sweeps inspired by https://arxiv.org/abs/1703.03864. Creative trials reset a hidden unit and evolve blocks. Radical trials erase low-magnitude weights or memory output weights and allow regrowth; pruning inspiration https://arxiv.org/abs/1803.03635, not a claim of reproducing the lottery-ticket method or speeding up the dense kernel. New seeds and current champion weights feed each cycle. Rejects do not stop the timer.

Each cycle freezes the live starting policy and runs baseline/challenger for 160 generations, population 16, identical training seeds and equal fight budgets (33,174 per arm for this pool). Keep requires at least 8 extra wins in 360 fresh audit fights with no fixed-validation regression, then strictly more wins than baseline, starting policy and current live champion on another 360 fresh fights. A changed live champion during confirmation prevents replacement. Winners continue their tested checkpoint/configuration via deployment.json; failures preserve the live run. A failed launch rolls the selection back and restarts the previous run. These are operational selection gates, not statistical significance claims.

The existing 3-ship pool, Awesome opponent, combat-v1 scoring and game engine are unchanged. Live trainer retains CPUs 6,7, 200% CPU quota, 4 GiB memory and zero swap. Review unit shares CPUs 6,7 with a 2 GiB maximum; monitor has 256 MiB maximum. A real 2-generation smoke trial consumed about 83 MiB and rejected its tied 107/360 result. No worker compilation or GPU changes were made. Global pause prevents new reviews and pauses trial trainers too.

Evidence lives in artifacts/neat/reviews/state.json and cycle-NNNNNN/{plan,result,audit,confirmation}.json plus immutable per-arm configs, initial weights, checkpoints and metrics. The timer and monitor are enabled user units and login linger is enabled. Check systemctl --user status uqm-neat uqm-monitor uqm-review.timer and journalctl --user -u uqm-review.service. Stop uqm-review.timer to stop future recipes; stop uqm-review.service as well to interrupt a running trial. Source is on codex/training-monitor in the uqm-melee-monitor worktree; do not silently replace it with the older main-tree dashboard or launcher.

Validation: Elm dashboard compiled; desktop/mobile browser inspection found no horizontal overflow; hover explanations, expandable fights and network diagram worked; pure recipe/gating tests passed; actual Rust smoke trial preserved the live trainer. The UI restart resumed the same live checkpoint. The first full timer-driven cycle completed: both arms used 33,174 training fights and tied 107/360 fresh wins; the challenger was rejected. The next creative review was confirmed scheduled for 00:23:37 SAST, exactly 15 minutes after the first activation.


# Corrected scoring is live (2026-09-08)

`uqm-neat.service` now runs `artifacts/neat/runs/scoring-v1` using the isolated `artifacts/neat/releases/scoring-v1` source and binary from commit `92ddb86`. `bash scripts/neat/start.sh` restores this run. The scoring version is `combat-v1`: the 1800-tick budget covers combat only; countdown and death/victory transitions do not consume it. Existing authoritative post-death simulation still resolves projectiles and resurrection before deciding the winner. The CPU optimizations remain present. The usual CPUs 6,7, 200% quota, 4 GiB memory and no-swap limits remain.

The new run starts from frozen rust-v2 champion weights (champion generation 4432), with validation re-scored and fresh search RNG/history. It does not inherit old scores or the drifting search centre. On the identical 54 validation fights, this champion changes from 20 wins / 183850.15746 to 21 wins / 192233.83718. The extra win was already a kill, but the old 1800-display-tick deadline expired four ticks before the victory transition completed. This is corrected credit, not learned improvement. Evidence and frozen inputs: `artifacts/neat/releases/scoring-v1/comparison-current/`. All 54 legacy-mode outputs of the new binary matched the prior live binary exactly. Focused Rust and Python tests passed, and the live dashboard and advancing checkpoints were verified. Early generation median was about 0.54 seconds.

The prior rust-v1 and rust-v2 runs and executables remain intact. `artifacts/neat/active-run.json` and the dashboard now follow scoring-v1. Do not restart an older run with the new scoring version; use `--initial` into a freshly scored run. The sections below describe earlier deployments.

# Optimized Rust training is live (2026-09-08)

`uqm-neat.service` now runs `artifacts/neat/runs/rust-v2/source/melee-worker`, the verified copying plus single-exp activation build. It forks the final `rust-v1` checkpoint with weights, RNG, champion and chart history preserved. `bash scripts/neat/start.sh` restores rust-v2. Both workers are active, new generations are completing, and the dashboard follows rust-v2 through `active-run.json`. CPU affinity remains 6,7, quota 200%, memory 4 GiB and no swap. The prior run and executable remain available. New source snapshots and live before/after timing are under `rust-v2/source/` and `rust-v2/speedup.json`.

The earlier "not deployed" optimization notes below describe the pre-deployment verification and are superseded by this section.

# Rust training is live (2026-09-08)

The live `uqm-neat.service` now runs two native Rust workers. `bash scripts/neat/start.sh` restores `artifacts/neat/runs/rust-v1/`. It forked the exact block-mutation checkpoint at generation 43, preserving weights, RNG, champion and chart history; the first Rust generation was 44. `artifacts/neat/active-run.json` identifies the live run. `python3 scripts/neat/inspect_run.py` follows it automatically. The dashboard shows the evaluator and active experiment.

Measured on Snowball over 14 generations per backend, with the same 360 fights per generation: Elm median 48.669 s, Rust median 1.224 s, a 39.78x speedup. Rust max/mean/median/min were 1.287/1.215/1.224/1.135 seconds. Evidence: `artifacts/neat/runs/rust-v1/speedup.json`. CPU affinity remains 6,7 with a 200% quota, 4 GiB memory limit and no swap.

The original two-arm pilot selected block mutations: validation improved from 5/54 to 11/54; fresh audit seeds improved from 3/54 to 7/54. The champion at the swap was 13/54. The fixed Pkunk/Umgah/Yehat pool, Awesome cyborg opponent, population 16, sigma 0.12, learning rate 0.1 and seed schedules are unchanged. `scripts/neat/hints.json` controls pause only; frozen run hints remain under the original block-mutations directory.

Validation before deployment included 1,296 full training-pool episodes locally, 216 on Snowball, full event traces, and an Elm-to-Rust checkpoint continuation test matching weights, RNG, champion and history. A broader 25-ship smoke matrix exposed an Ilwrath AI issue, which was fixed and its failing trace verified; that whole matrix was not rerun before deployment, per the request to stop expanding verification and take the validated training pool live.

Current source and worker snapshots are in `artifacts/neat/runs/rust-v1/source/`. Do not overwrite/rebuild the running worker binary or edit fingerprinted trainer files during a run. A changed evaluator/configuration requires a new run with recorded provenance. `--resume-from` explicitly forks a checkpoint into a new artifacts directory and requires identical scenario/search configuration. The original campaign remains preserved. Pre-swap scripts backup: `artifacts/neat-backups/before-rust-20260908-213256.tar.gz`.

There is no automatic LLM research daemon. Future models should inspect live results, check generalization on fresh seeds, and propose the next research/creative comparison. Do not expand the ship pool or raise resource limits without authorization.

## Implemented top-two CPU optimizations (2026-09-08)

Implemented locally and in Snowball source; **not deployed to the running trainer**. The ready optimized worker is `artifacts/optimization-top2/combined-worker`, SHA256 `96d9935e9c855ae4bef476a49f14ee756ff9a6f8e0be5bcfa35468dce8393313`. The live worker still has SHA256 `c89b66d4b69ea36bcd115c4f445feeb9bc28facb4f41c3d97050539073e9e8f4`. Do not overwrite a running executable or silently restart into changed source; use a recorded checkpoint fork to activate it.

State copying: `step::collide_all` now retains ordered snapshots in stable optional slots instead of removing the first vector element and rebuilding the tail on every pass. Disappeared second elements leave empty slots, and loss of the first element still ends that pass immediately. Collision order and snapshots are preserved. Input updates mutate core fields directly. Cyborg decisions return only the characteristics that pilot needs instead of copying a full combatant.

NN activation: retain exact +/-20 saturation, replace the two E.powf calls with `(exp(2*x)-1)/(exp(2*x)+1)`. This is mathematically tanh with different last-bit rounding, allowed for the NN. Native `f64::tanh` was tested first but regressed performance on Snowball, so it was rejected. The focused activation test covers boundaries, infinities, NaN and interior agreement with native tanh within 1e-15.

Matched 360-fight batch, five alternating measured runs per binary after one warmup each: CPU medians baseline 1.668232 s, copying only 1.402464 s, combined 1.292556 s. That is 19.0% more evaluator throughput from copying, 29.1% combined (22.5% less CPU time). All 360 complete fight reports match for both variants. Exact NDJSON trace comparison of baseline versus copying-only passed all 11,558 records across 18 full training-pool episodes, including complete Arena/RNG state and both seats. Keeping the original NN for this trace isolates game-update equivalence.

Full two-worker trainer comparison, five generations each from the same frozen champion: median generation time 1.810188 s baseline versus 1.506273 s optimized, **20.2% more throughput**. Both ended with exactly matching search weights, RNG and champion scenarios. These isolated runs shared CPUs 6,7 with the live trainer; their absolute timings are not standalone production latency. Normal live resource limits are restored and training remains active.

Evidence: `artifacts/optimization-top2/benchmark.json`, `benchmark-native-tanh.json`, `trace-parity.json`, `trainer-benchmark.json`. Copies are available locally. Baseline source/binary, candidate source, frozen weights and exact jobs remain in that directory on Snowball. `scripts/temp/benchmark_top2.py` reproduces the three-way evaluator benchmark. No JSON batching or intercept optimization was included in this change.

## Measured CPU profile (2026-09-08)

The actual live workers were sampled for 20 seconds at 199 Hz with `perf cpu-clock:u`: 5,891 samples, zero lost. Non-overlapping leaf CPU shares: memcpy/memmove 23.765%; game tick 22.322%; NN arithmetic 9.404% plus its pow-based activation 8.810%; observation intercept 7.673%; cyborg intercept 6.315%; observation vector 3.938%. These are Rust worker CPU percentages, not generation wall-time percentages. Game-tick self time includes inlined helpers. The binary already has release line-table debug symbols, so no evaluator rebuild or restart was needed.

Copy attribution: 889 of 1,400 memcpy/memmove samples came from the tick and 254 from cyborg pilot. Existing state types are 296 bytes per Combatant, 192 per CombatantCore, and 320 per Element. Candidates include whole-state copies and collision Vec front removals; preserve operation order and validate byte parity for any changes. Intercept routines repeatedly project velocities/wrapped positions; optimize only equivalent arithmetic. NN tanh currently makes two E.powf calls per activation, a separate measured target that can affect NN decisions if changed.

Python's isolated five-generation probe used explicit per-call thread CPU clocks: 1,854 eval jobs consumed 0.950326 CPU seconds, with json.dumps taking 0.743197 CPU seconds (~78% of dispatch CPU). Main-thread CPU was 0.288485 seconds. The job protocol repeatedly serializes 1,133 weights per fight, so caching or batching weight encoding is justified. Timed categories overlap; do not sum them. This probe shared the two cores with live training and started fresh chart history, so its wall time is not a production speed measurement.

Evidence on Snowball: `artifacts/profiling/summary.json`, `live-rust.data`, `rust-self-all.txt`, `classified-samples.json`, `python-timings.json`, and copies of the profiled worker/libc/libm with SHA256 fingerprints. Summary and parsed results are also copied locally. Native stack unwinding had invalid tail frames, so perf's inclusive Children column is not used. cProfile with a thread CPU timer produced invalid cross-thread timings on Python 3.14; those pstats files are diagnostic failures, not evidence. The explicit timing probe in `scripts/temp/profile_neat_coordinator.py` replaced it.

Profiler tools are isolated under `artifacts/profiling/tools/`; no system library upgrade was performed. Repeat native collection with the current worker PIDs (read them from the service, never reuse old PIDs blindly):

```sh
LD_LIBRARY_PATH=artifacts/profiling/tools/usr/lib artifacts/profiling/tools/usr/bin/perf record -e cpu-clock:u -F 199 --call-graph dwarf,16384 -p PID1,PID2 -o artifacts/profiling/live-rust.data -- sleep 20
LD_LIBRARY_PATH=artifacts/profiling/tools/usr/lib artifacts/profiling/tools/usr/bin/perf report -i artifacts/profiling/live-rust.data --stdio --no-inline --no-children --sort dso,symbol -g none
```

Training remains on the original live Rust executable; no optimization was deployed during profiling. Normal CPU affinity 6,7 and 4 GiB memory limit are restored.

## GPU update-loop prototype (2026-09-08)

`rust/gpu/` is a separate workspace compiling the same `melee_sim::step::tick_authoritative` to NVPTX. `scripts/neat/gpu_probe.py` loads its CUDA binary through ctypes, with no Python CUDA dependency. Each GPU thread runs a complete fixed-input episode without per-tick host transfers. This is a game-loop prototype, not the live NN/cyborg evaluator. Live training remains on the CPU Rust workers.

On Snowball, `artifacts/gpu/game.cubin` runs on the RTX 5060 Ti. Exact canonical state-byte comparison passed 9 Pkunk/Umgah/Yehat pairings × 120 physics ticks (1,080 complete state snapshots), plus the initial 48-snapshot smoke. These compare every serialized Arena field, excluding object padding/pointers; this is not a claim of exhaustive parity across all gameplay. The trace report is `artifacts/gpu/trace.json`. Trace timing includes state serialization and first-launch costs and is not an evaluator speedup.

The NVIDIA optimized compiler crashed. The working binary uses `ptxas -O0`; building it took 187 seconds and peaked at 6.6 GiB. The human temporarily authorized a 20 GiB compiler cap. Runtime training limits remain 2 CPU cores and 4 GiB. Keep compiler limits temporary. GPU-only no-inline annotations keep large functions separate; no game rules changed.

Build from the repository root on Snowball (under the resource-limited temporary build unit):

```sh
RUSTFLAGS="-C target-cpu=sm_89 -C target-feature=+ptx80 -C llvm-args=--inline-threshold=0" cargo +nightly build --manifest-path rust/gpu/Cargo.toml --release --lib --target nvptx64-nvidia-cuda -Zbuild-std=core,alloc --target-dir artifacts/gpu/build -j1
/opt/cuda/bin/ptxas -arch=sm_120 -O0 artifacts/gpu/build/nvptx64-nvidia-cuda/release/melee_gpu.ptx -o artifacts/gpu/game.cubin
cargo +nightly build --manifest-path rust/gpu/Cargo.toml --release --bin gpu-reference --target-dir artifacts/gpu/host -j1
python3 scripts/neat/gpu_probe.py --ptx artifacts/gpu/game.cubin --cpu artifacts/gpu/host/release/gpu-reference --jobs 9 --ticks 120 --stride 65536
python3 scripts/neat/gpu_probe.py --ptx artifacts/gpu/game.cubin --cpu artifacts/gpu/host/release/gpu-reference --benchmark
```

The full 288 × 720-tick benchmark was stopped after 142 seconds without a result. A bounded 288 × 24-tick benchmark passed all final-state hashes: one CPU core 0.105511188 s, warmed GPU kernel 6.388323552 s, GPU copy 0.000046857 s. This unoptimized GPU build is **60.55× slower** than one CPU core, not a training acceleration. Evidence: `artifacts/gpu/benchmark-short.json`. The temporary compiler service has exited; live training is active with its normal 4 GiB cap.

The benchmark excludes a warmup launch, defaults to 288 episodes × 720 physics ticks (use `--ticks 24` for the bounded measurement), and compares final state hashes. Its baseline is one CPU core, not the two-worker live trainer. Do not switch training to this prototype or claim a GPU speedup without a measured faster complete evaluator.

# Earlier takeover notes (superseded runtime details)

# NEAT takeover campaign

The takeover campaign is live on snowball. Run repository commands from `/home/schalk/git/uqm-melee` with `ssh schalk@192.168.0.123 bash`. Use `bash scripts/neat/start.sh` for an intentional service restart; do not use a recorded PID.

The persistent user service `uqm-neat.service` is restricted to CPUs 6 and 7, `CPUQuota=200%`, `MemoryMax=4G`, and `MemorySwapMax=0`. At takeover it was active with zero restarts and all limits confirmed through systemd. It serves the dashboard on port 8788 and appends output to `artifacts/neat/campaign.log`. Inspect it with `systemctl --user status uqm-neat.service` and `systemctl --user show uqm-neat.service -p AllowedCPUs -p CPUQuotaPerSecUSec -p MemoryMax -p MemorySwapMax -p MainPID`.

The campaign root is `artifacts/neat/campaigns/takeover-v1/`. Its `campaign.json` records the phase and `current_arm`; each `runs/<id>/` contains its own `best.json`, `status.json`, `metrics.jsonl`, `checkpoint.json`, and `manifest.json`. Trainer resume requires exact configuration and code hashes. The campaign freezes `artifacts/neat/best.json`, the previous 3/18 champion, as its immutable initial snapshot. Restarts use that snapshot even if the external `best.json` later changes.

The current arm is `es-baseline`. Its initial validation at 20:43:20 SAST scored 5/54. This is the frozen initial baseline, not an improvement; the old 18-scenario subset remains 3/18. The pre-takeover backup is `artifacts/neat-backups/before-takeover-20260908-203543.tar.gz`. Main is `36e0f40`, and the deployed runtime records its configuration and code hashes in the run manifest.

The fixed three-ship comparison runs two arms from the same initial weights and seed 20260908: `es-baseline` is the 14-generation research lane using standard ES, and `block-mutations` is the 14-generation creative lane using block mutations. Both use population 16, sigma 0.12, learning rate 0.1, 1800 ticks, and Pkunk/Umgah/Yehat against the Awesome cyborg. Training rotates seeds 1701, 2137, and 7; validation uses 42, 99, and 1234. All ships and both seats yield 18 training scenarios for the current seed and 54 validation scenarios. Sixteen population evaluations, one center evaluation, and validation total 360 fights per generation. The pool does not expand during this comparison.

After both arms, fresh seeds 31013, 47017, and 59021 audit the chosen champion against the immutable initial weights. The campaign then continues the exact winning arm. This pilot offers no guarantee of improvement and does not establish statistical significance.

`scripts/neat/hints.json` now controls only global pause and is currently set to false. Do not change sigma, population, seeds, pool, or other experiment settings live. Any such change requires a new experiment plan and campaign root. There is no automatic LLM research daemon: the service executes the predeclared plan, and a future model reads its hypotheses and results before nominating another experiment.

The prior trainer reached generation 23; one unintended generation ran because of a missing-hints bug, and its champion remained 3/18. The Rust port has its foundation in place but is incomplete.

# Historical handoff

Everything below records the superseded trainer and remains for historical context.

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
bash scripts/oracle/check.sh      # elm <-> rust differential, must be all-ok
bash scripts/oracle/gen.sh        # regenerate the derived Rust tables
```

`check.sh` compares by sha256, not by `diff`. This is deliberate: in this
environment `diff` returned exit 0 for two files that genuinely differed, so a
diff-based gate can pass while the port is wrong. Keep the hash comparison.

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

### Measured speed so far

There is no end-to-end speedup yet, because the loop itself is not ported. What
is measured is like-for-like throughput on the two hottest inner components,
identical workload, checksums verified equal on both sides:

```
python3 scripts/oracle/bench.py

process floor: node 43.4 ms, rust 2.1 ms (subtracted)
component     elm ms   rust ms   speedup  checksums
velocity       333.2      2.48      134x  match     500 launches x 40 frames
mask            61.6      0.79       78x  match     4 hull pairs x 19x19 offsets
both           361.1      3.48      104x  match
```

Single core, no parallelism. The trainer's measured Elm baseline on snowball is
`bench 11619 scenario-ticks/s` over 18 scenarios on 2 cores, which is the ~40s
generation.

Treat 104x as an indication, not a promise. The real loop adds branchy per-ship
logic where the gap is narrower, and removes Elm Dict/record allocation where
the gap is wider. Two further multipliers are orthogonal to it: rayon across the
18 scenarios (only 2x on snowball's core cap) and dropping the per-fight JSON
round trip through node's stdin/stdout. The GPU matters mostly because the 2
core / 4 GB cap does not apply to VRAM.


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

Focused first 200-generation audit: candidate 22/40 lesson wins versus stage reference 19/40, and 115/360 across all matchups versus live 112/360 on the same fresh seeds. Below both advancement and promotion gates; champion protected. Controller automatically resumed toward generation 400, observed at generation 226 with zero restarts.
