//! Topology evolution: speciation, rank allocation, crossover and structural
//! mutation. Independently implemented from the published description of the
//! MarI/O algorithm; no protected source is reproduced here.
//!
//! Two rules matter more than the parameters and are enforced by the types:
//!
//!   * A fitness number is meaningful only next to other numbers from the SAME
//!     sampled panel. [`Individual::fitness`] is `None` until that panel has
//!     been evaluated, and a new panel clears every score, elites included.
//!   * Species staleness is measured against a SAVED GENOME, not a saved
//!     number. Each species keeps its historical best genome; that genome is
//!     re-entered into the population every generation and rescored on the
//!     current panel, and staleness resets only when today's best member beats
//!     that incumbent ON THAT SAME PANEL. No margin, rank or score is ever
//!     carried across panels.
//!
//! Innovation numbering follows the original MarI/O behaviour: every
//! structural mutation draws a FRESH innovation number, and crossover inherits
//! whatever numbers the parents carry. There is no global (from, to) registry
//! that would retroactively identify independently discovered edges.

use crate::genome::{Gene, Genome, Node, NodeKind, HIDDEN_BASE, N_INPUT};
use crate::rng::Stream;
use serde_json::{json, Value};


/// Per-genome mutation rates. They drift with the genome, so the population
/// searches over its own search intensity as well as over topology.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct MutationRates {
    pub weight: f64,
    pub link: f64,
    pub bias: f64,
    pub node: f64,
    pub enable: f64,
    pub disable: f64,
    pub step: f64,
}

impl Default for MutationRates {
    fn default() -> Self {
        MutationRates {
            weight: 0.25,
            link: 2.0,
            bias: 0.40,
            node: 0.50,
            enable: 0.20,
            disable: 0.40,
            step: 0.10,
        }
    }
}

impl MutationRates {
    const DRIFT: f64 = 0.95;

    fn drift(&mut self, rng: &mut Stream) {
        for rate in [
            &mut self.weight,
            &mut self.link,
            &mut self.bias,
            &mut self.node,
            &mut self.enable,
            &mut self.disable,
            &mut self.step,
        ] {
            *rate *= if rng.chance(0.5) {
                Self::DRIFT
            } else {
                1.0 / Self::DRIFT
            };
        }
    }

    pub fn to_json(self) -> Value {
        json!({"weight": self.weight, "link": self.link, "bias": self.bias, "node": self.node,
               "enable": self.enable, "disable": self.disable, "step": self.step})
    }

    pub fn from_json(value: &Value) -> Option<MutationRates> {
        let number = |key: &str| value.get(key)?.as_f64().filter(|n| n.is_finite());
        Some(MutationRates {
            weight: number("weight")?,
            link: number("link")?,
            bias: number("bias")?,
            node: number("node")?,
            enable: number("enable")?,
            disable: number("disable")?,
            step: number("step")?,
        })
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct NeatConfig {
    pub population: usize,
    pub crossover: f64,
    pub perturb: f64,
    pub delta_disjoint: f64,
    pub delta_weights: f64,
    pub delta_threshold: f64,
    pub stale_species: u32,
    pub seed_rates: MutationRates,
}

impl Default for NeatConfig {
    fn default() -> Self {
        NeatConfig {
            population: 300,
            crossover: 0.75,
            perturb: 0.90,
            delta_disjoint: 2.0,
            delta_weights: 0.40,
            delta_threshold: 1.0,
            stale_species: 15,
            seed_rates: MutationRates::default(),
        }
    }
}

impl NeatConfig {
    pub fn to_json(self) -> Value {
        json!({"population": self.population, "crossover": self.crossover, "perturb": self.perturb,
               "delta_disjoint": self.delta_disjoint, "delta_weights": self.delta_weights,
               "delta_threshold": self.delta_threshold, "stale_species": self.stale_species,
               "seed_rates": self.seed_rates.to_json()})
    }

    pub fn from_json(value: &Value) -> Option<NeatConfig> {
        Some(NeatConfig {
            population: value.get("population")?.as_u64()? as usize,
            crossover: value.get("crossover")?.as_f64()?,
            perturb: value.get("perturb")?.as_f64()?,
            delta_disjoint: value.get("delta_disjoint")?.as_f64()?,
            delta_weights: value.get("delta_weights")?.as_f64()?,
            delta_threshold: value.get("delta_threshold")?.as_f64()?,
            stale_species: value.get("stale_species")?.as_u64()? as u32,
            seed_rates: MutationRates::from_json(value.get("seed_rates")?)?,
        })
    }
}

#[derive(Clone, Debug)]
pub struct Individual {
    pub genome: Genome,
    pub rates: MutationRates,
    /// `None` means "not measured on the current panel". Never a stale number
    /// carried over from a different panel.
    pub fitness: Option<f64>,
}

impl Individual {
    pub fn seed(
        rng: &mut Stream,
        rates: MutationRates,
        book: &mut Innovations,
        perturb: f64,
    ) -> Individual {
        let mut individual = Individual {
            genome: Genome::minimal(),
            rates,
            fitness: None,
        };
        individual.mutate(rng, book, perturb);
        individual
    }

    pub fn score(&self) -> f64 {
        self.fitness.unwrap_or(f64::NEG_INFINITY)
    }

    fn to_json(&self) -> Value {
        json!({"genome": self.genome.to_json(), "rates": self.rates.to_json(),
               "fitness": self.fitness})
    }

    fn from_json(value: &Value) -> Option<Individual> {
        Some(Individual {
            genome: Genome::from_json(value.get("genome")?).ok()?,
            rates: MutationRates::from_json(value.get("rates")?)?,
            fitness: match value.get("fitness") {
                None | Some(Value::Null) => None,
                Some(other) => Some(other.as_f64().filter(|n| n.is_finite())?),
            },
        })
    }
}

/// Global structural bookkeeping: two monotonic counters, exactly as the
/// original algorithm keeps them.
///
/// A structural mutation draws a fresh innovation number every time, so two
/// genomes that independently discover the same edge carry DIFFERENT numbers
/// and count as disjoint. That is the published behaviour and it is what the
/// compatibility distance was tuned against; a (from, to) registry would
/// quietly merge those discoveries and change speciation.
///
/// Hidden node identifiers come from a global counter rather than a per-genome
/// high-water mark. That is a determinism safeguard, not a behavioural change:
/// crossover takes its whole node set from one parent, and the graph runtime's
/// result is invariant under node identifier renaming, so only the numbers
/// printed on a diagram differ.
#[derive(Clone, Copy, Debug)]
pub struct Innovations {
    next_innovation: u32,
    next_node: u32,
}

impl Default for Innovations {
    fn default() -> Self {
        Innovations::new()
    }
}

impl Innovations {
    pub fn new() -> Innovations {
        Innovations {
            next_innovation: 1,
            next_node: HIDDEN_BASE,
        }
    }

    /// A fresh innovation number for one newly created gene.
    pub fn innovation(&mut self) -> u32 {
        let assigned = self.next_innovation;
        self.next_innovation += 1;
        assigned
    }

    pub fn node(&mut self) -> u32 {
        let assigned = self.next_node;
        self.next_node += 1;
        assigned
    }

    pub fn to_json(&self) -> Value {
        json!({"next_innovation": self.next_innovation, "next_node": self.next_node})
    }

    pub fn from_json(value: &Value) -> Option<Innovations> {
        let next_innovation = value.get("next_innovation")?.as_u64()?;
        let next_node = value.get("next_node")?.as_u64()?;
        if next_innovation < 1 || next_node < HIDDEN_BASE as u64 {
            return None;
        }
        Some(Innovations {
            next_innovation: u32::try_from(next_innovation).ok()?,
            next_node: u32::try_from(next_node).ok()?,
        })
    }
}

impl Individual {
    /// Drifts this genome's rates, then applies the structural and weight
    /// mutations they call for.
    pub fn mutate(&mut self, rng: &mut Stream, book: &mut Innovations, perturb: f64) {
        self.rates.drift(rng);
        if rng.chance(self.rates.weight) {
            self.perturb_weights(rng, perturb);
        }
        let mut budget = self.rates.link;
        while budget > 0.0 {
            if rng.chance(budget) {
                self.add_link(rng, book, false);
            }
            budget -= 1.0;
        }
        let mut budget = self.rates.bias;
        while budget > 0.0 {
            if rng.chance(budget) {
                self.add_link(rng, book, true);
            }
            budget -= 1.0;
        }
        let mut budget = self.rates.node;
        while budget > 0.0 {
            if rng.chance(budget) {
                self.split_link(rng, book);
            }
            budget -= 1.0;
        }
        let mut budget = self.rates.enable;
        while budget > 0.0 {
            if rng.chance(budget) {
                self.flip_enabled(rng, true);
            }
            budget -= 1.0;
        }
        let mut budget = self.rates.disable;
        while budget > 0.0 {
            if rng.chance(budget) {
                self.flip_enabled(rng, false);
            }
            budget -= 1.0;
        }
    }

    fn perturb_weights(&mut self, rng: &mut Stream, perturb: f64) {
        let step = self.rates.step;
        for gene in self.genome.genes.iter_mut() {
            gene.weight = if rng.chance(perturb) {
                gene.weight + rng.signed() * step
            } else {
                rng.signed() * 2.0
            };
        }
    }

    fn add_link(&mut self, rng: &mut Stream, book: &mut Innovations, force_bias: bool) {
        let sinks: Vec<u32> = self
            .genome
            .nodes
            .iter()
            .filter(|n| n.kind != NodeKind::Input)
            .map(|n| n.id)
            .collect();
        if sinks.is_empty() {
            return;
        }
        let to = sinks[rng.below(sinks.len())];
        let from = if force_bias {
            N_INPUT - 1
        } else {
            self.genome.nodes[rng.below(self.genome.nodes.len())].id
        };
        if self
            .genome
            .genes
            .iter()
            .any(|g| g.from == from && g.to == to)
        {
            return;
        }
        let innovation = book.innovation();
        self.insert(Gene {
            innovation,
            from,
            to,
            weight: rng.signed() * 2.0,
            enabled: true,
        });
    }

    fn split_link(&mut self, rng: &mut Stream, book: &mut Innovations) {
        let enabled: Vec<usize> = self
            .genome
            .genes
            .iter()
            .enumerate()
            .filter(|(_, g)| g.enabled)
            .map(|(i, _)| i)
            .collect();
        if enabled.is_empty() {
            return;
        }
        let chosen = enabled[rng.below(enabled.len())];
        let old = self.genome.genes[chosen];
        self.genome.genes[chosen].enabled = false;
        let middle = book.node();
        self.genome.nodes.push(Node {
            id: middle,
            kind: NodeKind::Hidden,
        });
        self.genome.nodes.sort_by_key(|n| n.id);
        let into = book.innovation();
        let out = book.innovation();
        // The incoming half carries unit weight and the outgoing half the old
        // weight, so the split starts out behaving like the gene it replaced.
        self.insert(Gene {
            innovation: into,
            from: old.from,
            to: middle,
            weight: 1.0,
            enabled: true,
        });
        self.insert(Gene {
            innovation: out,
            from: middle,
            to: old.to,
            weight: old.weight,
            enabled: true,
        });
    }

    fn flip_enabled(&mut self, rng: &mut Stream, into: bool) {
        let candidates: Vec<usize> = self
            .genome
            .genes
            .iter()
            .enumerate()
            .filter(|(_, g)| g.enabled != into)
            .map(|(i, _)| i)
            .collect();
        if candidates.is_empty() {
            return;
        }
        let chosen = candidates[rng.below(candidates.len())];
        self.genome.genes[chosen].enabled = into;
    }

    fn insert(&mut self, gene: Gene) {
        match self
            .genome
            .genes
            .binary_search_by_key(&gene.innovation, |g| g.innovation)
        {
            // Re-deriving an innovation this genome already carries is a no-op,
            // which keeps innovation numbers unique within a genome.
            Ok(_) => {}
            Err(at) => self.genome.genes.insert(at, gene),
        }
    }
}

/// Genes the fitter parent contributes outright; matching innovations are
/// inherited from either parent with even odds.
pub fn crossover(better: &Individual, other: &Individual, rng: &mut Stream) -> Individual {
    let mut genes = better.genome.genes.clone();
    for gene in genes.iter_mut() {
        if let Ok(found) = other
            .genome
            .genes
            .binary_search_by_key(&gene.innovation, |g| g.innovation)
        {
            let alternative = other.genome.genes[found];
            if alternative.enabled && rng.chance(0.5) {
                gene.weight = alternative.weight;
            }
        }
    }
    let mut nodes = better.genome.nodes.clone();
    // Inherited weights never introduce endpoints, so the fitter parent's node
    // set is already complete; the sort keeps the canonical order explicit.
    nodes.sort_by_key(|n| n.id);
    Individual {
        genome: Genome { nodes, genes },
        rates: better.rates,
        fitness: None,
    }
}

fn disjoint_fraction(a: &Genome, b: &Genome) -> f64 {
    if a.genes.is_empty() && b.genes.is_empty() {
        return 0.0;
    }
    let missing = |from: &Genome, into: &Genome| {
        from.genes
            .iter()
            .filter(|g| {
                into.genes
                    .binary_search_by_key(&g.innovation, |o| o.innovation)
                    .is_err()
            })
            .count()
    };
    (missing(a, b) + missing(b, a)) as f64 / a.genes.len().max(b.genes.len()) as f64
}

fn weight_difference(a: &Genome, b: &Genome) -> f64 {
    let mut total = 0.0;
    let mut matched = 0usize;
    for gene in &a.genes {
        if let Ok(found) = b
            .genes
            .binary_search_by_key(&gene.innovation, |o| o.innovation)
        {
            total += (gene.weight - b.genes[found].weight).abs();
            matched += 1;
        }
    }
    if matched == 0 {
        0.0
    } else {
        total / matched as f64
    }
}

pub fn same_species(config: &NeatConfig, a: &Genome, b: &Genome) -> bool {
    config.delta_disjoint * disjoint_fraction(a, b)
        + config.delta_weights * weight_difference(a, b)
        < config.delta_threshold
}

#[derive(Clone, Debug)]
pub struct Species {
    pub members: Vec<Individual>,
    /// The historical best member of this species, kept as STRUCTURE rather
    /// than as a number: its genome and the mutation rates that genome had
    /// drifted to. It is re-entered into the species and rescored on whatever
    /// panel is current, which is what makes the staleness test a paired
    /// same-panel comparison instead of a cross-panel one. Its own fitness is
    /// never carried across a panel.
    pub incumbent: Option<Individual>,
    pub staleness: u32,
    /// Filled in during each generation turnover; purely derived.
    pub average_rank: f64,
}

impl Species {
    fn new(first: Individual) -> Species {
        Species {
            incumbent: Some(Individual {
                fitness: None,
                ..first.clone()
            }),
            members: vec![first],
            staleness: 0,
            average_rank: 0.0,
        }
    }

    pub fn best(&self) -> Option<&Individual> {
        self.members
            .iter()
            .filter(|m| m.fitness.is_some())
            .max_by(|a, b| a.score().total_cmp(&b.score()))
    }

    /// This species' score on the CURRENT panel, or `None` if nothing in it has
    /// been measured yet.
    pub fn best_score(&self) -> Option<f64> {
        self.best().and_then(|m| m.fitness)
    }

    /// Puts the saved incumbent back into the species so the next panel scores
    /// it alongside everyone else. Cheap: usually it is already there. Its
    /// drifted mutation rates come back with it, because those rates are part
    /// of what the search found and reseeding them would quietly undo the
    /// per-genome rate adaptation the algorithm depends on.
    fn restore_incumbent(&mut self) {
        let Some(incumbent) = self.incumbent.clone() else {
            return;
        };
        let fingerprint = incumbent.genome.fingerprint();
        if self
            .members
            .iter()
            .any(|m| m.genome.fingerprint() == fingerprint)
        {
            return;
        }
        self.members.push(Individual {
            fitness: None,
            ..incumbent
        });
    }

    /// The incumbent's score on the current panel, if it was measured.
    fn incumbent_score(&self) -> Option<f64> {
        let fingerprint = self.incumbent.as_ref()?.genome.fingerprint();
        self.members
            .iter()
            .find(|m| m.genome.fingerprint() == fingerprint)?
            .fitness
    }

    fn to_json(&self) -> Value {
        json!({"members": self.members.iter().map(Individual::to_json).collect::<Vec<_>>(),
               "incumbent": self.incumbent.as_ref().map(Individual::to_json),
               "staleness": self.staleness})
    }

    fn from_json(value: &Value) -> Option<Species> {
        let members = value
            .get("members")?
            .as_array()?
            .iter()
            .map(Individual::from_json)
            .collect::<Option<Vec<_>>>()?;
        if members.is_empty() {
            return None;
        }
        Some(Species {
            members,
            incumbent: match value.get("incumbent") {
                None | Some(Value::Null) => None,
                Some(other) => Some(Individual::from_json(other)?),
            },
            staleness: value.get("staleness")?.as_u64()? as u32,
            average_rank: 0.0,
        })
    }
}

#[derive(Clone, Debug)]
pub struct Population {
    pub config: NeatConfig,
    pub species: Vec<Species>,
    pub innovations: Innovations,
    pub generation: u32,
}

impl Population {
    pub fn seed(config: NeatConfig, rng: &mut Stream) -> Population {
        let mut population = Population {
            config,
            species: Vec::new(),
            innovations: Innovations::new(),
            generation: 0,
        };
        for _ in 0..config.population {
            let individual = Individual::seed(
                rng,
                config.seed_rates,
                &mut population.innovations,
                config.perturb,
            );
            population.place(individual);
        }
        population
    }

    pub fn members(&self) -> impl Iterator<Item = &Individual> {
        self.species.iter().flat_map(|s| s.members.iter())
    }

    pub fn members_mut(&mut self) -> impl Iterator<Item = &mut Individual> {
        self.species.iter_mut().flat_map(|s| s.members.iter_mut())
    }

    pub fn size(&self) -> usize {
        self.species.iter().map(|s| s.members.len()).sum()
    }

    pub fn best(&self) -> Option<&Individual> {
        self.members()
            .filter(|m| m.fitness.is_some())
            .max_by(|a, b| a.score().total_cmp(&b.score()))
    }

    fn place(&mut self, individual: Individual) {
        let config = self.config;
        for species in self.species.iter_mut() {
            let representative = &species.members[0].genome;
            if same_species(&config, &individual.genome, representative) {
                species.members.push(individual);
                return;
            }
        }
        self.species.push(Species::new(individual));
    }

    /// Re-enters every species' saved incumbent genome and clears all scores.
    /// Call this immediately before evaluating a new panel: afterwards every
    /// number in the population comes from that one panel, which is what makes
    /// two of them comparable at all.
    pub fn open_panel(&mut self) {
        for species in self.species.iter_mut() {
            species.restore_incumbent();
            for member in species.members.iter_mut() {
                member.fitness = None;
            }
        }
    }

    /// Produces the next generation from scores that were all measured on one
    /// panel. Staleness is decided by comparing each species' best member with
    /// that species' own saved incumbent genome, rescored on this same panel;
    /// nothing is compared with a number from an earlier panel.
    pub fn advance(&mut self, rng: &mut Stream) {
        for species in self.species.iter_mut() {
            let Some(best) = species.best().map(|m| (m.clone(), m.score())) else {
                // Nothing measurable this panel: neither progress nor decay.
                continue;
            };
            // The new baseline keeps the winner's drifted rates, not the seed.
            let adopt = Individual {
                fitness: None,
                ..best.0
            };
            match species.incumbent_score() {
                None => {
                    // No comparable baseline on this panel, so adopt today's
                    // best as the baseline rather than inventing a comparison.
                    species.incumbent = Some(adopt);
                    species.staleness = 0;
                }
                Some(baseline) if best.1 > baseline => {
                    species.incumbent = Some(adopt);
                    species.staleness = 0;
                }
                Some(_) => species.staleness += 1,
            }
        }

        self.cull(false);
        self.drop_stale();
        self.allocate_ranks();
        self.drop_weak();

        let total: f64 = self.species.iter().map(|s| s.average_rank).sum();
        let mut children: Vec<Individual> = Vec::with_capacity(self.config.population);
        if total > 0.0 {
            for index in 0..self.species.len() {
                let share = self.species[index].average_rank / total
                    * self.config.population as f64;
                // Minus one: the species champion survives untouched below.
                let breed = (share.floor() as i64 - 1).max(0) as usize;
                for _ in 0..breed {
                    children.push(self.breed(index, rng));
                }
            }
        }
        // Only the single best member of each species survives as an elite.
        self.cull(true);
        while children.len() + self.species.len() < self.config.population {
            let index = rng.below(self.species.len());
            children.push(self.breed(index, rng));
        }
        for child in children {
            self.place(child);
        }
        self.generation += 1;
    }

    /// `to_one` keeps only each species' best member, otherwise the top half.
    fn cull(&mut self, to_one: bool) {
        for species in self.species.iter_mut() {
            species
                .members
                .sort_by(|a, b| b.score().total_cmp(&a.score()));
            let keep = if to_one {
                1
            } else {
                species.members.len().div_ceil(2)
            };
            species.members.truncate(keep.max(1));
        }
        self.species.retain(|s| !s.members.is_empty());
    }

    fn drop_stale(&mut self) {
        if self.species.len() <= 1 {
            return;
        }
        // The species to protect is the strongest on TODAY's panel, which is a
        // paired comparison; there is no historical score to appeal to.
        let freshest = self
            .species
            .iter()
            .enumerate()
            .max_by(|a, b| {
                a.1.best_score()
                    .unwrap_or(f64::NEG_INFINITY)
                    .total_cmp(&b.1.best_score().unwrap_or(f64::NEG_INFINITY))
            })
            .map(|(i, _)| i)
            .unwrap_or(0);
        let limit = self.config.stale_species;
        let mut index = 0;
        self.species.retain(|species| {
            let keep = index == freshest || species.staleness < limit;
            index += 1;
            keep
        });
    }

    /// Global rank sharing: a species' breeding share is the mean global rank
    /// of its surviving members, so consistently strong species breed more.
    fn allocate_ranks(&mut self) {
        let mut ordered: Vec<(usize, usize, f64)> = Vec::new();
        for (s, species) in self.species.iter().enumerate() {
            for (m, member) in species.members.iter().enumerate() {
                ordered.push((s, m, member.score()));
            }
        }
        ordered.sort_by(|a, b| a.2.total_cmp(&b.2));
        let mut rank = vec![vec![0.0f64; 0]; self.species.len()];
        for (s, species) in self.species.iter().enumerate() {
            rank[s] = vec![0.0; species.members.len()];
        }
        for (position, &(s, m, _)) in ordered.iter().enumerate() {
            rank[s][m] = (position + 1) as f64;
        }
        for (s, species) in self.species.iter_mut().enumerate() {
            species.average_rank = rank[s].iter().sum::<f64>() / rank[s].len().max(1) as f64;
        }
    }

    fn drop_weak(&mut self) {
        if self.species.len() <= 1 {
            return;
        }
        let total: f64 = self.species.iter().map(|s| s.average_rank).sum();
        if total <= 0.0 {
            return;
        }
        let population = self.config.population as f64;
        let strongest = self
            .species
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.average_rank.total_cmp(&b.1.average_rank))
            .map(|(i, _)| i)
            .unwrap_or(0);
        let mut index = 0;
        self.species.retain(|species| {
            let keep = index == strongest
                || (species.average_rank / total * population).floor() >= 1.0;
            index += 1;
            keep
        });
    }

    fn breed(&mut self, species: usize, rng: &mut Stream) -> Individual {
        let (chance, perturb) = (self.config.crossover, self.config.perturb);
        let mut child = {
            let members = &self.species[species].members;
            if members.len() > 1 && rng.chance(chance) {
                let a = &members[rng.below(members.len())];
                let b = &members[rng.below(members.len())];
                if a.score() >= b.score() {
                    crossover(a, b, rng)
                } else {
                    crossover(b, a, rng)
                }
            } else {
                let mut copy = members[rng.below(members.len())].clone();
                copy.fitness = None;
                copy
            }
        };
        child.mutate(rng, &mut self.innovations, perturb);
        child
    }

    /// Guarantees the incumbent champion is present, so the next generation can
    /// rescore it on the new panel and the comparison stays paired. Its drifted
    /// mutation rates come with it; reseeding them would throw away the search
    /// intensity the champion arrived at.
    pub fn ensure_elite(&mut self, champion: &Genome, rates: MutationRates) {
        let fingerprint = champion.fingerprint();
        if self
            .members()
            .any(|m| m.genome.fingerprint() == fingerprint)
        {
            return;
        }
        self.place(Individual {
            genome: champion.clone(),
            rates,
            fitness: None,
        });
    }

    pub fn to_json(&self) -> Value {
        json!({"config": self.config.to_json(), "generation": self.generation,
               "innovations": self.innovations.to_json(),
               "species": self.species.iter().map(Species::to_json).collect::<Vec<_>>()})
    }

    pub fn from_json(value: &Value) -> Option<Population> {
        Some(Population {
            config: NeatConfig::from_json(value.get("config")?)?,
            generation: value.get("generation")?.as_u64()? as u32,
            innovations: Innovations::from_json(value.get("innovations")?)?,
            species: value
                .get("species")?
                .as_array()?
                .iter()
                .map(Species::from_json)
                .collect::<Option<Vec<_>>>()?,
        })
    }

    pub fn mean_nodes(&self) -> f64 {
        let count = self.size().max(1) as f64;
        self.members().map(|m| m.genome.nodes.len() as f64).sum::<f64>() / count
    }

    pub fn mean_connections(&self) -> f64 {
        let count = self.size().max(1) as f64;
        self.members()
            .map(|m| m.genome.enabled_count() as f64)
            .sum::<f64>()
            / count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn book() -> Innovations {
        Innovations::new()
    }

    #[test]
    fn every_structural_mutation_draws_a_fresh_innovation_number() {
        let mut b = book();
        let first = b.innovation();
        assert_eq!(b.innovation(), first + 1);
        assert_eq!(b.innovation(), first + 2);
        assert_eq!(b.node(), HIDDEN_BASE);
        assert_eq!(b.node(), HIDDEN_BASE + 1);
        let saved = b.to_json();
        assert_eq!(Innovations::from_json(&saved).unwrap().to_json(), saved);
        assert!(
            Innovations::from_json(&json!({"next_innovation": 0, "next_node": HIDDEN_BASE}))
                .is_none()
        );
        assert!(Innovations::from_json(&json!({"next_innovation": 1, "next_node": 3})).is_none());
    }

    #[test]
    fn mutation_never_produces_an_invalid_genome() {
        let mut rng = Stream::seeded(4);
        let mut b = book();
        let mut individual = Individual::seed(&mut rng, MutationRates::default(), &mut b, 0.9);
        for _ in 0..400 {
            individual.mutate(&mut rng, &mut b, 0.9);
            individual
                .genome
                .clone()
                .validate()
                .expect("mutation keeps the genome valid");
        }
        assert!(individual.genome.hidden_count() > 0, "topology must grow");
        assert!(individual.genome.genes.len() > 10);
    }

    #[test]
    fn topology_actually_evolves_rather_than_only_weights() {
        let mut rng = Stream::seeded(11);
        let mut b = book();
        let mut individual = Individual::seed(&mut rng, MutationRates::default(), &mut b, 0.9);
        let start = (individual.genome.nodes.len(), individual.genome.genes.len());
        for _ in 0..200 {
            individual.mutate(&mut rng, &mut b, 0.9);
        }
        let end = (individual.genome.nodes.len(), individual.genome.genes.len());
        assert!(end.0 > start.0, "hidden nodes must appear");
        assert!(end.1 > start.1, "links must appear");
        assert_eq!(individual.genome.nodes[0].id, 0);
    }

    #[test]
    fn crossover_yields_a_valid_child_of_both_parents() {
        let mut rng = Stream::seeded(19);
        let mut b = book();
        let mut a = Individual::seed(&mut rng, MutationRates::default(), &mut b, 0.9);
        let mut c = Individual::seed(&mut rng, MutationRates::default(), &mut b, 0.9);
        for _ in 0..40 {
            a.mutate(&mut rng, &mut b, 0.9);
            c.mutate(&mut rng, &mut b, 0.9);
        }
        a.fitness = Some(1.0);
        c.fitness = Some(0.5);
        let child = crossover(&a, &c, &mut rng);
        assert!(child.fitness.is_none(), "a child starts unmeasured");
        child.genome.validate().expect("valid child");
    }

    #[test]
    fn a_genome_is_always_its_own_species() {
        let mut rng = Stream::seeded(23);
        let mut b = book();
        let mut individual = Individual::seed(&mut rng, MutationRates::default(), &mut b, 0.9);
        for _ in 0..30 {
            individual.mutate(&mut rng, &mut b, 0.9);
        }
        let config = NeatConfig::default();
        assert!(same_species(
            &config,
            &individual.genome,
            &individual.genome
        ));
    }

    #[test]
    fn a_generation_keeps_the_population_size_and_clears_every_score() {
        let mut rng = Stream::seeded(31);
        let config = NeatConfig {
            population: 60,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        assert_eq!(population.size(), 60);
        for generation in 0..8 {
            population.open_panel();
            let mut value = 0.0;
            for member in population.members_mut() {
                value += 1.0;
                member.fitness = Some(value + generation as f64);
            }
            population.advance(&mut rng);
            assert!(population.size() >= 60, "generation {generation}");
            population.open_panel();
            assert!(
                population.members().all(|m| m.fitness.is_none()),
                "scores from a spent panel must not survive"
            );
            assert!(!population.species.is_empty());
        }
        assert_eq!(population.generation, 8);
    }

    #[test]
    fn inflating_every_score_does_not_hide_a_stale_species() {
        // The population is scored on a different "panel" each generation and
        // every number grows, but no member ever beats its species incumbent on
        // the panel they share. Staleness must still accrue.
        let mut rng = Stream::seeded(53);
        let config = NeatConfig {
            population: 30,
            stale_species: 4,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        let mut inflation = 0.0;
        for _ in 0..4 {
            population.open_panel();
            inflation += 1000.0;
            let mut species_index = 0.0;
            for species in population.species.iter_mut() {
                let incumbent = species
                    .incumbent
                    .as_ref()
                    .map(|i| i.genome.fingerprint());
                species_index += 1.0;
                for member in species.members.iter_mut() {
                    // The incumbent is the best thing on this panel, always.
                    let bonus = if Some(member.genome.fingerprint()) == incumbent {
                        1.0
                    } else {
                        0.0
                    };
                    member.fitness = Some(inflation + species_index + bonus);
                }
            }
            population.advance(&mut rng);
        }
        assert!(
            population.species.iter().any(|s| s.staleness > 0),
            "a species that never improved on a shared panel must go stale"
        );
    }

    /// Scores a whole population from a per-member function, so the same
    /// ORDERING can be replayed under two different number lines.
    fn score_every_member(population: &mut Population, of: impl Fn(usize) -> f64) {
        for (at, member) in population.members_mut().enumerate() {
            member.fitness = Some(of(at));
        }
    }

    /// A compact description of everything selection produced: how the species
    /// came out, how big each is, and which genomes survived in which.
    fn shape(population: &Population) -> Vec<Vec<String>> {
        population
            .species
            .iter()
            .map(|s| s.members.iter().map(|m| m.genome.fingerprint()).collect())
            .collect()
    }

    #[test]
    fn an_all_negative_panel_selects_exactly_as_the_same_order_of_positives_does() {
        // The no-damage penalty can make EVERY member of a panel score -1000,
        // and a run can sit there for generations. Offspring allocation is
        // share-of-global-RANK, not share-of-fitness, so it must be invariant
        // under any strictly increasing transform of the scores: shifting a
        // panel far below zero may not change who breeds, who survives as an
        // elite, or how the species come out.
        let config = NeatConfig {
            population: 40,
            stale_species: 4,
            ..NeatConfig::default()
        };
        // Same seed for both, so the only difference is the number line.
        let mut positive = Population::seed(config, &mut Stream::seeded(97));
        let mut negative = Population::seed(config, &mut Stream::seeded(97));
        assert_eq!(shape(&positive), shape(&negative), "same seed, same start");

        for generation in 0..6 {
            positive.open_panel();
            negative.open_panel();
            // A strictly increasing map of the other: every score negative,
            // every score well below the worst positive one, and the gap
            // between neighbours wildly different. Only the ORDER is shared.
            let base = |at: usize| (at % 7) as f64 + generation as f64;
            score_every_member(&mut positive, base);
            score_every_member(&mut negative, |at| base(at) * 3.0 - 1000.0);

            assert!(
                negative.members().all(|m| m.score() < 0.0),
                "the whole panel is meant to be negative"
            );
            assert_eq!(
                positive.best().map(|m| m.genome.fingerprint()),
                negative.best().map(|m| m.genome.fingerprint()),
                "the best member must not depend on the number line"
            );

            let mut evolving = Stream::seeded(31);
            positive.advance(&mut evolving);
            let mut evolving = Stream::seeded(31);
            negative.advance(&mut evolving);

            assert_eq!(
                shape(&positive),
                shape(&negative),
                "an all-negative panel selected differently at generation {generation}"
            );
            assert_eq!(positive.size(), negative.size());
            // The population must actually refill rather than collapsing to
            // the elites, which is what a fitness-proportional share would do
            // when every share is negative.
            assert_eq!(negative.size(), config.population);
        }
    }

    #[test]
    fn a_measured_negative_member_still_outranks_an_unmeasured_one() {
        // `score()` stands in NEG_INFINITY for a member this panel has not
        // reached yet. A real -1000 has to beat that, or a penalised member
        // would be culled as though it had never been evaluated.
        let mut rng = Stream::seeded(101);
        let config = NeatConfig {
            population: 6,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        population.open_panel();
        let measured = population
            .members()
            .next()
            .map(|m| m.genome.fingerprint())
            .expect("a seeded population has members");
        for member in population.members_mut() {
            if member.genome.fingerprint() == measured {
                member.fitness = Some(-1000.0);
            }
        }
        assert_eq!(
            population.best().map(|m| m.genome.fingerprint()),
            Some(measured),
            "the only measured member must be the best, however negative"
        );
        assert!(population.best().unwrap().score() < 0.0);
    }

    #[test]
    fn a_champion_is_promotable_out_of_an_entirely_negative_panel() {
        // Champion replacement is a paired comparison of two scores on one
        // panel. Nothing in it may assume a positive number, or a run under
        // the penalty could never promote anybody at all.
        let mut rng = Stream::seeded(103);
        let config = NeatConfig {
            population: 10,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        population.open_panel();
        score_every_member(&mut population, |at| -1000.0 + at as f64);
        let best = population.best().expect("a scored panel has a best member");
        assert!(best.score() < 0.0);
        // The strongest member of an all-negative panel is still strictly
        // better than the rest of it, which is all a promotion needs.
        let others: Vec<f64> = population
            .members()
            .map(|m| m.score())
            .filter(|s| *s != best.score())
            .collect();
        assert!(!others.is_empty());
        assert!(others.iter().all(|s| *s < best.score()));
    }

    #[test]
    fn an_incumbent_keeps_the_mutation_rates_it_drifted_to() {
        // Per-genome rate drift is part of what the search finds. Re-entering a
        // saved incumbent with the seed rates would silently undo it every
        // generation, which is not the published algorithm.
        let mut rng = Stream::seeded(67);
        let config = NeatConfig {
            population: 12,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        // Drive the rates well away from the seed values.
        for member in population.members_mut() {
            for _ in 0..30 {
                member.rates.drift(&mut rng);
            }
        }
        let seeded = config.seed_rates;
        assert!(population.members().all(|m| m.rates != seeded));

        for _ in 0..6 {
            population.open_panel();
            let mut score = 0.0;
            for member in population.members_mut() {
                score += 1.0;
                member.fitness = Some(score);
            }
            population.advance(&mut rng);
            population.open_panel();
            for species in &population.species {
                let incumbent = species.incumbent.as_ref().expect("a baseline exists");
                assert_ne!(
                    incumbent.rates, seeded,
                    "the incumbent was reseeded to the default rates"
                );
                // Its genome is back in the species to be rescored, which is
                // what makes the staleness comparison a paired one.
                assert!(
                    species
                        .members
                        .iter()
                        .any(|m| m.genome.fingerprint() == incumbent.genome.fingerprint()),
                    "the incumbent was not re-entered for rescoring"
                );
            }
        }

        // And when it genuinely has to be re-inserted, it arrives with its own
        // rates rather than with the seed defaults.
        let species = &mut population.species[0];
        let incumbent = species.incumbent.clone().unwrap();
        species.members.clear();
        species.members.push(Individual {
            genome: Genome::minimal(),
            rates: seeded,
            fitness: None,
        });
        species.restore_incumbent();
        let back = species
            .members
            .iter()
            .find(|m| m.genome.fingerprint() == incumbent.genome.fingerprint())
            .expect("the incumbent was re-inserted");
        assert_eq!(back.rates, incumbent.rates);
        assert!(back.fitness.is_none(), "a restored baseline is unmeasured");
    }

    #[test]
    fn the_population_stays_bounded_across_many_generations() {
        let mut rng = Stream::seeded(59);
        let config = NeatConfig {
            population: 40,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        for _ in 0..25 {
            population.open_panel();
            for member in population.members_mut() {
                member.fitness = Some(rng_score(&mut rng));
            }
            let species = population.species.len();
            population.advance(&mut rng);
            assert!(
                population.size() <= 40 + species,
                "size {} exceeded {} + {species}",
                population.size(),
                40
            );
            assert!(population.size() >= 1);
        }
    }

    fn rng_score(rng: &mut Stream) -> f64 {
        rng.unit()
    }

    #[test]
    fn population_survives_a_checkpoint_round_trip() {
        let mut rng = Stream::seeded(37);
        let config = NeatConfig {
            population: 24,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        for (index, member) in population.members_mut().enumerate() {
            if index % 3 != 0 {
                member.fitness = Some(index as f64);
            }
        }
        let saved = population.to_json();
        let restored = Population::from_json(&saved).expect("round trip");
        assert_eq!(restored.size(), population.size());
        assert_eq!(restored.to_json(), saved);
        let unmeasured = restored.members().filter(|m| m.fitness.is_none()).count();
        assert_eq!(unmeasured, population.members().filter(|m| m.fitness.is_none()).count());
    }

    #[test]
    fn the_incumbent_champion_is_carried_forward_for_paired_rescoring() {
        let mut rng = Stream::seeded(41);
        let config = NeatConfig {
            population: 20,
            ..NeatConfig::default()
        };
        let mut population = Population::seed(config, &mut rng);
        let first = population.members().next().unwrap().clone();
        population.species.clear();
        population.ensure_elite(&first.genome, first.rates);
        assert_eq!(population.size(), 1);
        population.ensure_elite(&first.genome, first.rates);
        assert_eq!(population.size(), 1, "no duplicate elite");
        // The rates that came back are the champion's, not the seed defaults.
        assert_eq!(population.members().next().unwrap().rates, first.rates);
    }
}
