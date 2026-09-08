#!/usr/bin/env python3
"""Persistent, recipe-based trials. No LLM or automatic paper discovery is implied."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from experiment import atomic_json, checked_weights, digest
from layout import N_HIDDEN, N_IN, N_WEIGHTS, N_W1
from review_audit import audit

HERE = Path(__file__).resolve().parent
ROOT = Path('/home/schalk/git/uqm-melee')
ART = ROOT / 'artifacts/neat'
REVIEWS = ART / 'reviews'
RELEASE = ART / 'releases/scoring-v1'
WORKER = RELEASE / 'rust/target/release/melee-worker'
LANES = ['research', 'creative', 'radical']


def read(path):
    return json.loads(Path(path).read_text())


def active_run():
    return Path(read(ART / 'active-run.json')['run'])


def summary():
    state = read(REVIEWS / 'state.json') if (REVIEWS / 'state.json').exists() else {'phase': 'waiting', 'history': []}
    run = active_run()
    status = read(run / 'status.json')
    state = {**state, 'server_time': time.time(), 'status_age_s': max(0, time.time() - (run / 'status.json').stat().st_mtime),
             'mode': 'recipe-based experiments; no autonomous LLM research', 'interval_s': 3600,
             'live_run': str(run), 'scoring_version': status.get('scoring_version'),
             'trainer_active': subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'uqm-neat.service']).returncode == 0}
    if state.get('phase') == 'waiting':
        state['lane'] = LANES[state.get('cycle', 0) % 3]
        state['hypothesis'] = 'Next lane: ' + state['lane'] + '. The last comparison and its outcome are recorded below.'
    if subprocess.run(['systemctl', '--user', 'is-failed', '--quiet', 'uqm-review.service']).returncode == 0:
        state['error'] = state.get('error') or 'Review service failed; inspect its journal. The next timer activation will retry.'
    if subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'uqm-review.timer']).returncode != 0:
        state['phase'] = 'schedule disabled'
    trial = REVIEWS / f"cycle-{state.get('cycle', 0):06d}" / state.get('phase', '') / 'status.json'
    if trial.is_file():
        progress = read(trial)
        state['trial_generation'] = progress.get('generation', 0)
    health = REVIEWS / 'health.json'
    state['health_check'] = read(health) if health.exists() else None
    return state


def health_check():
    REVIEWS.mkdir(parents=True, exist_ok=True)
    run = active_run()
    status = read(run / 'status.json')
    previous_path = REVIEWS / 'health.json'
    previous = read(previous_path) if previous_path.exists() else {}
    same_run = previous.get('run') == str(run)
    check = {'checked_at': time.time(), 'run': str(run), 'generation': status['generation'],
             'champion_wins': status.get('champion_wins'),
             'generations_since_check': status['generation'] - previous.get('generation', status['generation']) if same_run else None,
             'status_age_s': time.time() - (run / 'status.json').stat().st_mtime,
             'paused': read(ROOT / 'scripts/neat/hints.json').get('pause', True), 'error': status.get('error', '')}
    failed = subprocess.run(['systemctl', '--user', 'is-failed', '--quiet', 'uqm-neat.service']).returncode == 0
    check['action'] = 'observe'
    if failed and not check['paused']:
        subprocess.run(['bash', str(HERE / 'start.sh')], check=True, timeout=100, stdout=subprocess.DEVNULL)
        check['action'] = 'restarted failed trainer from checkpoint'
    champion = read(run / 'best.json')
    saved_policy = REVIEWS / 'health-champion.json'
    prior = read(saved_policy) if saved_policy.exists() else read(read(run / 'manifest.json')['initial'])
    config = read(run / 'manifest.json')['provenance']['config']
    if config['pool'] == ['Pkunk', 'Umgah', 'Yehat'] and digest(champion['weights']) != digest(prior['weights']):
        seeds = random.Random(int(check['checked_at'])).sample(range(400000001, 500000000), 20)
        before = audit(WORKER, prior['weights'], config['pool'], seeds)
        after = audit(WORKER, champion['weights'], config['pool'], seeds)
        evidence = {'checked_at': check['checked_at'], 'seeds': seeds, 'before': before, 'after': after}
        atomic_json(REVIEWS / f"health-audit-{int(check['checked_at'])}.json", evidence)
        check['fresh_check'] = {'before_wins': before['wins'], 'after_wins': after['wins'], 'fights': after['fights'],
                                'checked_at': check['checked_at'], 'champion_hash': digest(champion['weights'])}
    elif same_run and previous.get('fresh_check'):
        check['fresh_check'] = previous['fresh_check']
    atomic_json(saved_policy, champion)
    atomic_json(previous_path, check)


def trial_arguments(lane, history):
    cases = {
        'research': ('Broader coordinated weight changes could escape the current local optimum.', 'Whole-network noise may destroy useful behavior; the first trial tied the baseline.'),
        'creative': ('Replacing one feature may open a new behavior while retaining most of the policy.', 'That feature may be essential; resetting it can lose existing wins.'),
        'radical': ('Erasing weights or memory may remove dependence on unhelpful behavior and permit regrowth.', 'Ablation can destroy useful behavior; fewer nonzero weights alone do not speed up this dense evaluator.')}
    pro, con = cases[lane]
    previous = next((r for r in reversed(history) if r.get('lane') == lane), None)
    return {'case_for': pro, 'case_against': con,
            'previous_result': {k: previous.get(k) for k in ['cycle','decision','baseline_wins','challenger_wins']} if previous else None,
            'early_stop': 'After 40 generations, stop only if the challenger trails by at least 8 wins on 90 screening fights and has no validation advantage.',
            'keep': 'Full independent audit and confirmation gates must still pass.'}


def screen_rejects(results, candidate, baseline):
    return results['challenger']['wins'] + 8 <= results['baseline']['wins'] and candidate['seat_wins'] <= baseline['seat_wins']


def recipe(cycle, weights, config):
    lane = LANES[cycle % 3]
    rng = random.Random(87000000 + cycle)
    hints = dict(config)
    initial = list(weights)
    if lane == 'research':
        hints.update(search='es', sigma=[0.04, 0.08, 0.16, 0.3][(cycle // 3) % 4], lr=[0.03, 0.1][(cycle // 12) % 2])
        idea = 'Whole-network mirrored evolution strategies; sweep mutation scale and learning rate.'
        source = 'https://arxiv.org/abs/1703.03864'
    elif lane == 'creative':
        hidden = rng.randrange(N_HIDDEN)
        for i in range(hidden * N_IN, (hidden + 1) * N_IN):
            initial[i] = rng.gauss(0, 0.2)
        hints.update(search='block_es', sigma=[0.06, 0.18, 0.35][(cycle // 3) % 3])
        idea = f'Reseed hidden unit {hidden} to introduce a new feature, then evolve coherent blocks.'
        source = None
    else:
        fraction = [0.25, 0.5, 0.75][(cycle // 3) % 3]
        if (cycle // 9) % 2:
            indices = range(N_W1 + 5 * (N_HIDDEN + 1), N_WEIGHTS)
            idea = 'Erase recurrent output weights, then allow them to regrow during training.'
        else:
            indices = sorted(range(N_WEIGHTS), key=lambda i: abs(initial[i]))[:round(N_WEIGHTS * fraction)]
            idea = f'Erase the smallest {fraction:.0%} of weights, then allow regrowth. This is an ablation, not a sparse-kernel speedup.'
        for i in indices:
            initial[i] = 0.0
        hints.update(search='block_es', sigma=0.12)
        source = 'https://arxiv.org/abs/1803.03635'
    return lane, idea, source, initial, hints


def train_arm(path, initial, hints, generations):
    path.mkdir(parents=True, exist_ok=True)
    atomic_json(path / 'initial.json', initial)
    atomic_json(path / 'hints.json', hints)
    cmd = [sys.executable, str(RELEASE / 'scripts/neat/train.py'), '--artifacts', str(path), '--hints', str(path / 'hints.json'),
           '--initial', str(path / 'initial.json'), '--evaluator', 'rust', '--rust-worker', str(WORKER),
           '--scoring-version', 'combat-v1', '--control', str(ROOT / 'scripts/neat/hints.json'), '--no-dashboard', '--generations', str(generations)]
    with (path / 'run.log').open('a') as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600,
                       env={**os.environ, 'NEAT_WORKERS': '2', 'OPENBLAS_NUM_THREADS': '1', 'OMP_NUM_THREADS': '1'})
    rows = [json.loads(line) for line in (path / 'metrics.jsonl').read_text().splitlines()]
    budget = len(read(path / 'baseline.json')['scenarios']) + sum(17 * r['n_train'] + r['n_hold'] for r in rows)
    return read(path / 'best.json'), budget


def audit_passes(results, candidate, original, baseline):
    return (results['challenger']['wins'] >= results['baseline']['wins'] + 8
            and candidate['seat_wins'] >= max(original['seat_wins'], baseline['seat_wins']))


def confirmation_passes(results, candidate, current):
    return (all(results['challenger']['wins'] > results[name]['wins'] for name in ['baseline', 'starting', 'live'])
            and candidate['seat_wins'] >= current['seat_wins'])


def review(generations=160, deploy=True):
    REVIEWS.mkdir(parents=True, exist_ok=True)
    with (REVIEWS / 'review.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if read(ROOT / 'scripts/neat/hints.json').get('pause', True):
            return
        if subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'uqm-search-trial.service']).returncode == 0:
            return
        state = read(REVIEWS / 'state.json') if (REVIEWS / 'state.json').exists() else {'cycle': 0, 'history': []}
        cycle = state['cycle']
        if state.get('phase') in ['baseline', 'challenger', 'screen', 'audit', 'confirmation', 'deploying']:
            state.setdefault('history', []).append({'cycle': cycle, 'lane': LANES[cycle % 3], 'decision': 'interrupted', 'finished': time.time()})
            cycle += 1
        while (REVIEWS / f'cycle-{cycle:06d}').exists():
            cycle += 1
        path = REVIEWS / f'cycle-{cycle:06d}'
        path.mkdir(exist_ok=False)
        run = active_run()
        original = read(run / 'best.json')
        provenance = read(run / 'manifest.json')['provenance']
        if provenance.get('scoring_version') != 'combat-v1' or provenance['config']['pool'] != ['Pkunk', 'Umgah', 'Yehat']:
            raise ValueError('Live scoring or pool changed; review recipe needs revision')
        config = provenance['config']
        rng = random.Random(500000000 + cycle)
        config.update(pop=16, seed=600000000 + cycle, train_seeds=rng.sample(range(1000000, 100000000), 3), pause=False, auto_expand=False)
        lane, idea, source, weights, hints = recipe(cycle, checked_weights(original), config)
        changed = {**original, 'weights': weights}
        arguments = trial_arguments(lane, state.get('history', []))
        state.update(cycle=cycle, lane=lane, hypothesis=idea, source=source, started=time.time(), phase='baseline', screen=None, next_review_at=time.time()+3600, error='')
        evidence = {'cycle': cycle, 'lane': lane, 'hypothesis': idea, 'source': source, 'starting_run': str(run), 'started': state['started'], 'generations': generations, 'arguments': arguments}
        atomic_json(path / 'plan.json', {**evidence, 'baseline_config': config, 'challenger_config': hints,
                                      'starting_weight_hash': digest(original['weights']), 'minimum_extra_wins': 8,
                                      'confirmation_rule': 'Beat baseline, starting champion and current live champion on independent 360 fights; no fixed-validation regression.'})
        def phase(name):
            state['phase'] = name
            atomic_json(REVIEWS / 'state.json', state)
        try:
            state['target_generations'] = min(40, generations)
            phase('baseline')
            baseline, base_budget = train_arm(path / 'baseline', original, config, min(40, generations))
            phase('challenger')
            candidate, budget = train_arm(path / 'challenger', changed, hints, min(40, generations))
            if budget != base_budget:
                raise ValueError('Unequal screening fight budgets')
            phase('screen')
            screening_seeds = rng.sample(range(300000001, 400000000), 5)
            screening = {name: audit(WORKER, policy['weights'], config['pool'], screening_seeds)
                         for name, policy in [('baseline', baseline), ('challenger', candidate)]}
            atomic_json(path / 'screen.json', {'seeds': screening_seeds, **screening})
            state['screen'] = {name: result['wins'] for name, result in screening.items()}
            evidence['screen'] = state['screen']
            if screen_rejects(screening, candidate, baseline):
                evidence.update(decision='screen rejected', baseline_wins=screening['baseline']['wins'],
                                challenger_wins=screening['challenger']['wins'], audit_fights=screening['baseline']['fights'],
                                fights_per_arm=budget, finished=time.time())
                atomic_json(path / 'result.json', evidence)
                state['history'] = (state.get('history', []) + [evidence])[-60:]
                state.update(cycle=cycle+1, phase='waiting', next_review_at=state['started']+3600)
                atomic_json(REVIEWS / 'state.json', state)
                return
            if generations > 40:
                state['target_generations'] = generations
                phase('baseline')
                baseline, base_budget = train_arm(path / 'baseline', original, config, generations)
                phase('challenger')
                candidate, budget = train_arm(path / 'challenger', changed, hints, generations)
            if budget != base_budget:
                raise ValueError('Unequal fight budgets')
            evidence['fights_per_arm'] = budget
            phase('audit')
            seeds = rng.sample(range(100000001, 200000000), 20)
            results = {name: audit(WORKER, policy['weights'], config['pool'], seeds) for name, policy in [('baseline', baseline), ('challenger', candidate)]}
            atomic_json(path / 'audit.json', {'seeds': seeds, **results})
            evidence.update(baseline_wins=results['baseline']['wins'], challenger_wins=results['challenger']['wins'], audit_fights=results['baseline']['fights'])
            passed = audit_passes(results, candidate, original, baseline)
            evidence['decision'] = 'rejected'
            if passed:
                phase('confirmation')
                current_run = active_run()
                current = read(current_run / 'best.json')
                seeds = rng.sample(range(200000001, 300000000), 20)
                confirm = {name: audit(WORKER, policy['weights'], config['pool'], seeds) for name, policy in [('baseline', baseline), ('challenger', candidate), ('starting', original), ('live', current)]}
                atomic_json(path / 'confirmation.json', {'seeds': seeds, **confirm})
                passed = confirmation_passes(confirm, candidate, current)
                evidence['confirmation_wins'] = {name: value['wins'] for name, value in confirm.items()}
                if passed:
                    evidence['decision'] = 'qualified'
                    if deploy:
                        phase('deploying')
                        if active_run() != current_run or digest(read(current_run / 'best.json')['weights']) != digest(current['weights']):
                            raise RuntimeError('Live champion changed during confirmation; leaving it running')
                        deployment = ART / 'deployment.json'
                        previous = read(deployment) if deployment.exists() else None
                        atomic_json(path / 'previous-deployment.json', previous)
                        atomic_json(deployment, {'release': str(RELEASE), 'worker': str(WORKER), 'run': str(path / 'challenger'),
                                                 'hints': str(path / 'challenger/hints.json'), 'initial': str(path / 'challenger/initial.json')})
                        try:
                            subprocess.run(['bash', str(HERE / 'start.sh')], check=True, timeout=100, stdout=subprocess.DEVNULL)
                            time.sleep(3)
                            if active_run() != path / 'challenger' or subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'uqm-neat.service']).returncode:
                                raise RuntimeError('Deployment did not become live')
                            evidence['decision'] = 'deployed'
                        except Exception:
                            if previous is None:
                                deployment.unlink(missing_ok=True)
                            else:
                                atomic_json(deployment, previous)
                            subprocess.run(['bash', str(HERE / 'start.sh')], check=True, timeout=100, stdout=subprocess.DEVNULL)
                            raise
            evidence['finished'] = time.time()
        except Exception as error:
            evidence.update(decision='error', error=str(error), finished=time.time())
            state['error'] = str(error)
        atomic_json(path / 'result.json', evidence)
        state['history'] = (state.get('history', []) + [evidence])[-60:]
        state.update(cycle=cycle+1, phase='waiting', next_review_at=max(state['started']+3600, time.time()))
        atomic_json(REVIEWS / 'state.json', state)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        try:
            route = self.path.split('?')[0]
            if route == '/api/review':
                data, mime = json.dumps(summary()).encode(), 'application/json'
            elif route in ['/api/status', '/api/best', '/api/net']:
                path = active_run() / ('status.json' if route == '/api/status' else 'best.json')
                obj = read(path)
                if route == '/api/net':
                    obj = {'generation': obj['generation'], 'n_in': N_IN, 'n_hidden': N_HIDDEN, 'n_out': 13, 'weights': obj['weights']}
                elif route == '/api/best':
                    obj.pop('weights', None)
                data, mime = json.dumps(obj).encode(), 'application/json'
            elif route in ['/', '/index.html', '/dashboard.js']:
                filename = 'dashboard.js' if route == '/dashboard.js' else 'index.html'
                data = (HERE / filename).read_bytes()
                mime = 'application/javascript' if filename.endswith('.js') else 'text/html'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as error:
            self.send_error(503, str(error))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['serve', 'review', 'health'])
    p.add_argument('--generations', type=int, default=160)
    p.add_argument('--no-deploy', action='store_true')
    p.add_argument('--port', type=int, default=8788)
    p.add_argument('--review-root', type=Path, default=REVIEWS)
    args = p.parse_args()
    REVIEWS = args.review_root.resolve()
    if args.action == 'serve':
        ThreadingHTTPServer(('0.0.0.0', args.port), Handler).serve_forever()
    elif args.action == 'health':
        health_check()
    else:
        review(args.generations, not args.no_deploy)
