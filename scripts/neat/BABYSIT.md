# Rust training is live (2026-09-08)

The live `uqm-neat.service` now runs two native Rust workers. `bash scripts/neat/start.sh` restores `artifacts/neat/runs/rust-v1/`. It forked the exact block-mutation checkpoint at generation 43, preserving weights, RNG, champion and chart history; the first Rust generation was 44. `artifacts/neat/active-run.json` identifies the live run. `python3 scripts/neat/inspect_run.py` follows it automatically. The dashboard shows the evaluator and active experiment.

Measured on Snowball over 14 generations per backend, with the same 360 fights per generation: Elm median 48.669 s, Rust median 1.224 s, a 39.78x speedup. Rust max/mean/median/min were 1.287/1.215/1.224/1.135 seconds. Evidence: `artifacts/neat/runs/rust-v1/speedup.json`. CPU affinity remains 6,7 with a 200% quota, 4 GiB memory limit and no swap.

The original two-arm pilot selected block mutations: validation improved from 5/54 to 11/54; fresh audit seeds improved from 3/54 to 7/54. The champion at the swap was 13/54. The fixed Pkunk/Umgah/Yehat pool, Awesome cyborg opponent, population 16, sigma 0.12, learning rate 0.1 and seed schedules are unchanged. `scripts/neat/hints.json` controls pause only; frozen run hints remain under the original block-mutations directory.

Validation before deployment included 1,296 full training-pool episodes locally, 216 on Snowball, full event traces, and an Elm-to-Rust checkpoint continuation test matching weights, RNG, champion and history. A broader 25-ship smoke matrix exposed an Ilwrath AI issue, which was fixed and its failing trace verified; that whole matrix was not rerun before deployment, per the request to stop expanding verification and take the validated training pool live.

Current source and worker snapshots are in `artifacts/neat/runs/rust-v1/source/`. Do not overwrite/rebuild the running worker binary or edit fingerprinted trainer files during a run. A changed evaluator/configuration requires a new run with recorded provenance. `--resume-from` explicitly forks a checkpoint into a new artifacts directory and requires identical scenario/search configuration. The original campaign remains preserved. Pre-swap scripts backup: `artifacts/neat-backups/before-rust-20260908-213256.tar.gz`.

There is no automatic LLM research daemon. Future models should inspect live results, check generalization on fresh seeds, and propose the next research/creative comparison. Do not expand the ship pool or raise resource limits without authorization.

# Earlier takeover notes (superseded runtime details)

# LLM babysit notes

## Takeover campaign

The campaign is live on snowball. Run commands from `/home/schalk/git/uqm-melee` with `ssh schalk@192.168.0.123 bash`. Use `bash scripts/neat/start.sh` for an intentional service restart; do not use a recorded PID.

`start.sh` runs the persistent user service `uqm-neat.service` on CPUs 6 and 7 with a 200% CPU quota, 4 GiB `MemoryMax`, and no swap. The dashboard is on port 8788 and output appends to `artifacts/neat/campaign.log`. At takeover it was active with zero restarts and the CPU, memory, and swap limits confirmed through systemd.

Check it with:

```bash
systemctl --user status uqm-neat.service
systemctl --user show uqm-neat.service -p AllowedCPUs -p CPUQuotaPerSecUSec -p MemoryMax -p MemorySwapMax -p MainPID
python3 scripts/neat/inspect_run.py
tail -f artifacts/neat/campaign.log
```

The campaign root is `artifacts/neat/campaigns/takeover-v1/`. `campaign.json` records the phase and `current_arm`. Each `runs/<id>/` owns its `best.json`, `status.json`, `metrics.jsonl`, `checkpoint.json`, and `manifest.json`. Checkpoints require exact configuration and code hashes. `artifacts/neat/best.json` is the frozen source for the campaign's immutable initial weights; it preserves the previous 3/18 champion. A restart uses the campaign's existing initial snapshot and must not replace it with a newer external `best.json`.

The current arm is `es-baseline`. Its initial validation at 20:43:20 SAST scored 5/54. This is the frozen initial baseline, not a measured improvement; its old 18-scenario subset remains 3/18. The pre-takeover backup is `artifacts/neat-backups/before-takeover-20260908-203543.tar.gz`. Main is `36e0f40`, and the deployed runtime records its configuration and code hashes in the run manifest.

The plan compares two pilot arms from the same initial weights and seed 20260908:

- `es-baseline`: research lane, standard ES, 14 generations.
- `block-mutations`: creative lane, block mutations, 14 generations.

Both use population 16, sigma 0.12, learning rate 0.1, 1800 ticks, and the fixed Pkunk/Umgah/Yehat pool against the Awesome cyborg. Training rotates seeds 1701, 2137, and 7; validation uses 42, 99, and 1234. All three ships and both seats produce 18 training scenarios for the current rotating seed and 54 validation scenarios. Sixteen population evaluations, one center evaluation, and validation total 360 fights per generation.

After both arms finish, fresh audit seeds 31013, 47017, and 59021 compare the selected champion with the immutable initial weights. The campaign then continues the exact winning arm. This is a pilot comparison with no guarantee of improvement and no claim of statistical significance.

## Operator rules

`scripts/neat/hints.json` is now only the global pause control and is currently set to false. Set only `pause` to true or false there. Do not change sigma, population, seeds, pool, or other experiment settings live; the plan and checkpoints are immutable. Create a new plan and campaign root for a changed experiment.

Do not expand the pool during this comparison. Do not raise the service above two CPU cores or 4 GiB RAM. Do not infer progress from an old PID; inspect the user service, campaign state, per-arm status, and log.

There is no automatic LLM research daemon. The persistent service executes the predeclared campaign. A future model reads the hypotheses and results, then nominates the next experiment for review.

## Historical state

The previous trainer reached generation 23. One unintended generation ran because of a missing-hints bug; its saved champion remained 3/18. The Rust port foundation exists but the port is not complete.
