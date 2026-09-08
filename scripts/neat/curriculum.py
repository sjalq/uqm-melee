"""Add one Awesome-cyborg opponent only after independently confirmed progress."""
import fcntl
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import time
from experiment import atomic_json, checked_weights, digest
from layout import ALL_SHIPS
from review_audit import audit

ORDER = ['Earthling', 'Shofixti', 'Spathi', 'Arilou'] + [s for s in ALL_SHIPS if s not in ['Earthling', 'Shofixti', 'Spathi', 'Arilou']]
THRESHOLDS = {'overall_win_rate': 0.60, 'each_opponent_win_rate': 0.40, 'gain_percentage_points': 10, 'fresh_sets': 2, 'seeds_per_set': 20}


def read(path):
    return json.loads(Path(path).read_text())


def next_opponents(opponents):
    next_ship = next((s for s in ORDER if s not in opponents), None)
    return opponents + [next_ship] if next_ship else list(opponents)


def expansion_gate(before, after):
    n = after['fights']
    if not n or before['fights'] != n:
        return False
    if after['wins'] * 100 < 60 * n or (after['wins'] - before['wins']) * 100 < 10 * n:
        return False
    groups = {}
    for scenario, won in zip(after['scenarios'], after['flags']):
        groups.setdefault(scenario['them'], []).append(won)
    return bool(groups) and all(sum(wins) * 100 >= 40 * len(wins) for wins in groups.values())


def finish_stage(state, pending):
    return {**state, 'stage': state['stage'] + 1, 'opponents': pending['opponents'],
            'reference': pending['reference'], 'pending': None, 'last_expansion': pending,
            'last_checked_hash': None, 'error': '', 'updated_at': time.time()}


def consider(root, release, worker, launcher):
    art = Path(root) / 'artifacts/neat'
    directory = art / 'curriculum'
    directory.mkdir(exist_ok=True)
    with (art / 'reviews/review.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if read(Path(root) / 'scripts/neat/hints.json').get('pause', True):
            return
        run = Path(read(art / 'active-run.json')['run'])
        manifest = read(run / 'manifest.json')
        config = manifest['provenance']['config']
        if manifest['provenance'].get('scoring_version') != 'combat-v1' or config['rating'] != 'awesome':
            raise ValueError('Curriculum requires combat-v1 scoring and the Awesome cyborg')
        champion = read(run / 'best.json')
        checked_weights(champion)
        opponents = config.get('opponent_pool', config['pool'])
        state_path = directory / 'state.json'
        if state_path.exists():
            state = read(state_path)
        else:
            reference = directory / 'initial-reference.json'
            atomic_json(reference, champion)
            state = {'enabled': True, 'stage': 0, 'our_ships': config['pool'], 'opponents': opponents,
                     'reference': str(reference), 'thresholds': THRESHOLDS, 'pending': None, 'error': '', 'updated_at': time.time()}
            atomic_json(state_path, state)
        if not state.get('enabled', False):
            return
        pending = state.get('pending')
        if pending:
            if str(run) == pending['run'] and opponents == pending['opponents']:
                state = finish_stage(state, pending)
                atomic_json(state_path, state)
                return
            elif opponents == state['opponents']:
                state['pending'] = None
                atomic_json(state_path, state)
            else:
                raise ValueError('Curriculum deployment state differs from live run; refusing a second expansion')
        if opponents != state['opponents'] or config['pool'] != state['our_ships']:
            raise ValueError('Live roster differs from the curriculum record')
        expanded = next_opponents(opponents)
        if expanded == opponents:
            return
        # Cheap validation prefilter avoids auditing the still-incompetent policy.
        if champion['seat_wins'] * 100 < 60 * len(champion['scenarios']):
            return
        champion_hash = digest(champion['weights'])
        if state.get('last_checked_hash') == champion_hash:
            return
        stamp = time.time_ns()
        attempt = directory / f'check-{stamp}'
        attempt.mkdir()
        evidence = {'at': time.time(), 'stage': state['stage'], 'our_ships': config['pool'], 'opponents': opponents,
                    'candidate_hash': champion_hash, 'reference': state['reference'], 'thresholds': THRESHOLDS,
                    'next_opponent': expanded[-1], 'decision': 'checking'}
        atomic_json(attempt / 'plan.json', evidence)
        reference = read(state['reference'])
        rng = random.Random(stamp)
        try:
            for index in range(2):
                seeds = rng.sample(range(700000001, 900000000), 20)
                before = audit(worker, reference['weights'], config['pool'], seeds, opponents)
                after = audit(worker, champion['weights'], config['pool'], seeds, opponents)
                passed = expansion_gate(before, after)
                atomic_json(attempt / f'audit-{index}.json', {'seeds': seeds, 'before': before, 'after': after, 'passed': passed})
                if not passed:
                    evidence['decision'] = 'not ready'
                    break
            else:
                # Prepare and exercise the expanded game matrix while live training continues.
                candidate_run = attempt / 'expanded-run'
                candidate_run.mkdir()
                hints = {**config, 'opponent_pool': expanded, 'rating': 'awesome', 'auto_expand': False, 'pause': False}
                atomic_json(candidate_run / 'hints.json', hints)
                atomic_json(candidate_run / 'initial.json', champion)
                command = [sys.executable, str(Path(release) / 'scripts/neat/train.py'), '--artifacts', str(candidate_run),
                           '--hints', str(candidate_run / 'hints.json'), '--initial', str(candidate_run / 'initial.json'),
                           '--evaluator', 'rust', '--rust-worker', str(worker), '--scoring-version', 'combat-v1',
                           '--no-dashboard', '--generations', '1']
                with (candidate_run / 'pilot.log').open('w') as log:
                    subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=3600,
                                   env={**os.environ, 'NEAT_WORKERS': '2', 'OPENBLAS_NUM_THREADS': '1', 'OMP_NUM_THREADS': '1'})
                pilot = read(candidate_run / 'best.json')
                expected = {(us, them, seed, swap) for us in config['pool'] for them in expanded for seed in config['hold_seeds'] for swap in [False, True]}
                actual = {(f['us'], f['them'], f['seed'], f['swap']) for f in pilot['scenarios']}
                if actual != expected or any(f['foe'] != 'cyborg' or f['rating'] != 'awesome' for f in pilot['scenarios']):
                    raise ValueError('Expanded pilot did not cover the required Awesome-cyborg fights')
                if Path(read(art / 'active-run.json')['run']) != run or digest(read(run / 'best.json')['weights']) != champion_hash:
                    evidence['decision'] = 'deferred: live champion changed'
                else:
                    pending = {'run': str(candidate_run), 'opponents': expanded, 'added': expanded[-1],
                               'reference': str(candidate_run / 'initial.json'), 'evidence': str(attempt), 'at': time.time()}
                    state['pending'] = pending
                    atomic_json(state_path, state)
                    deployment = art / 'deployment.json'
                    previous = read(deployment) if deployment.exists() else None
                    atomic_json(attempt / 'previous-deployment.json', previous)
                    atomic_json(deployment, {'release': str(release), 'worker': str(worker), 'run': str(candidate_run),
                                             'hints': str(candidate_run / 'hints.json'), 'initial': str(candidate_run / 'initial.json')})
                    try:
                        subprocess.run(['bash', str(launcher)], check=True, timeout=100, stdout=subprocess.DEVNULL)
                        if Path(read(art / 'active-run.json')['run']) != candidate_run or subprocess.run(['systemctl', '--user', 'is-active', '--quiet', 'uqm-neat.service']).returncode:
                            raise RuntimeError('Expanded run failed to become live')
                    except Exception:
                        if previous is None:
                            deployment.unlink(missing_ok=True)
                        else:
                            atomic_json(deployment, previous)
                        subprocess.run(['bash', str(launcher)], check=True, timeout=100, stdout=subprocess.DEVNULL)
                        state['pending'] = None
                        raise
                    state = finish_stage(state, pending)
                    evidence['decision'] = 'expanded'
        except Exception as error:
            state['error'] = str(error)
            evidence.update(decision='error', error=str(error))
        if evidence['decision'] == 'not ready':
            state['last_checked_hash'] = champion_hash
        state['updated_at'] = time.time()
        atomic_json(attempt / 'result.json', evidence)
        atomic_json(state_path, state)
