#!/usr/bin/env python3
"""Focused curriculum adapter around an immutable copy of the existing trainer.

Package as train.py beside base_train.py and focused_sampling.py in a release.
The ES update, policy, game worker, checkpoint format and pause handling are reused.
"""
import hashlib
from pathlib import Path


def main():
    import base_train as trainer
    import focused_sampling as sampling

    old_load = trainer.load_hints
    old_train = trainer.make_train_scenarios
    old_hold = trainer.make_hold_scenarios
    old_hashes = trainer.source_hashes

    def load():
        hints = old_load()
        if "training_pairs" in hints:
            sampling.validate_config(hints)
        return hints

    def hashes(root, evaluator="elm", rust_worker=None):
        result = old_hashes(root, evaluator, rust_worker)
        for name in ["base_train.py", "focused_sampling.py"]:
            result[name] = hashlib.sha256((Path(root) / name).read_bytes()).hexdigest()
        return result

    trainer.load_hints = load
    trainer.source_hashes = hashes
    trainer.make_train_scenarios = lambda hints, gen: (
        sampling.training_scenarios(hints, gen) if "training_pairs" in hints else old_train(hints, gen)
    )
    trainer.make_hold_scenarios = lambda hints: (
        sampling.validation_scenarios(hints)
        if "training_pairs" in hints and not hints.get("focused_full_validation") else old_hold(hints)
    )
    trainer.main()


if __name__ == "__main__":
    main()
