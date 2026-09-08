"""Small elitist population with behavior diversity and stalled-search restarts."""
from experiment import result_key
from layout import N_HIDDEN, N_IN, N_WEIGHTS, N_W1


class PopulationSearch:
    def __init__(self, rng, initial, revision=1, saved=None):
        self.rng = rng
        self.revision = revision
        self.parents = [list(initial)]
        self.champion = list(initial)
        self.stale = 0
        if saved is not None:
            self.parents = saved["parents"]
            self.champion = saved["champion"]
            self.stale = saved["stale"]

    def snapshot(self):
        return {"parents": self.parents, "champion": self.champion, "stale": self.stale}

    def propose(self, count, generation):
        candidates = [list(self.champion)]
        for parent in self.parents:
            if parent not in candidates and len(candidates) < min(4, count):
                candidates.append(list(parent))
        while len(candidates) < count:
            index = len(candidates)
            parent = self.rng.choice(self.parents)
            sigma = (0.03, 0.12, 0.35, 0.8)[index % 4]
            weights = list(parent)
            if self.stale >= 15 and index >= count - 3:
                weights = list(self.champion) if index % 2 else [0.0] * N_WEIGHTS
                indices = range(N_WEIGHTS)
                sigma = 0.4 if index % 2 == 0 else 0.8
            elif index % 3 == 0:
                indices = range(N_WEIGHTS)
            elif index % 3 == 1:
                indices = self.rng.sample(range(N_WEIGHTS), 64)
            else:
                output = self.rng.randrange(13)
                indices = range(N_W1 + output * (N_HIDDEN + 1), N_W1 + (output + 1) * (N_HIDDEN + 1))
            if self.revision >= 2:
                sigma = (0.05, 0.15, 0.4, 1.0)[index % 4]
                if index % 4 == 0:
                    hidden = self.rng.randrange(N_HIDDEN)
                    indices = list(range(hidden * N_IN, (hidden + 1) * N_IN))
                    indices += [N_W1 + output * (N_HIDDEN + 1) + hidden for output in range(13)]
                elif index % 4 == 1:
                    indices = range(N_W1, N_W1 + 5 * (N_HIDDEN + 1))
                elif index % 4 == 2 and len(self.parents) > 1:
                    donor = self.rng.choice(self.parents)
                    for hidden in self.rng.sample(range(N_HIDDEN), N_HIDDEN // 2):
                        weights[hidden * N_IN:(hidden + 1) * N_IN] = donor[hidden * N_IN:(hidden + 1) * N_IN]
                        for output in range(13):
                            offset = N_W1 + output * (N_HIDDEN + 1) + hidden
                            weights[offset] = donor[offset]
                    indices = self.rng.sample(range(N_WEIGHTS), 32)
                    sigma = 0.05
                elif self.stale >= 8 or generation == 0:
                    weights = [self.rng.gauss(0, 0.5) if self.rng.random() < 0.2 else 0.0 for _ in range(N_WEIGHTS)]
                    indices = []
            for i in indices:
                weights[i] += self.rng.gauss(0.0, sigma)
            candidates.append(weights)
        return candidates

    @staticmethod
    def behavior(record):
        return tuple((s["winner"], int(s["own"]) // 2, int(s["enemy"]) // 2,
                      int(s["ticks"]) // 120) for s in record["scenarios"])

    def observe(self, records):
        ranked = sorted(records, key=result_key, reverse=True)
        selected = [ranked[0]]
        signatures = {self.behavior(ranked[0])}
        for record in ranked[1:12]:
            signature = self.behavior(record)
            if signature not in signatures:
                selected.append(record)
                signatures.add(signature)
            if len(selected) == 4:
                break
        self.parents = [list(record["weights"]) for record in selected]
        return ranked[0]

    def feedback(self, promoted, champion):
        self.stale = 0 if promoted else self.stale + 1
        if promoted:
            self.champion = list(champion)
