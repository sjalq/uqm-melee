//! Genome wire schema (`schema_version: 1`) and its validation rules.
//!
//! The genome is the only thing that crosses a language boundary, so the shape
//! below is normative for `tests/Mario/Genome.elm` as well:
//!
//! ```json
//! {"schema_version":1,
//!  "nodes":[{"id":0,"kind":"input"}],
//!  "genes":[{"innovation":1,"from":0,"to":141,"weight":0.5,"enabled":true}]}
//! ```
//!
//! Node identifier ranges are fixed, never negotiated:
//!   * `0..=140`   inputs  (127 observations, 5 prior controls, 8 prior memory, bias)
//!   * `141..=153` outputs (5 controls, 8 memory channels)
//!   * `>=154`     hidden
//!
//! A node identifier's range and its declared `kind` must agree, which makes a
//! mislabelled node unrepresentable after `Genome::validate`.

use serde_json::{json, Map, Value};
use std::collections::BTreeSet;
use std::fmt;

/// Observation slots. Taken straight from the encoder rather than restated, so
/// the two cannot drift; the layout those slots carry is documented on
/// `melee_neat::encode::vector`, and changing it changes this number and every
/// stored genome with it.
pub const N_OBS: usize = melee_neat::policy::N_OBS;
pub const N_CONTROL: usize = 5;
pub const N_MEMORY: usize = 8;
/// 127 observations + 5 prior controls + 8 prior memory + 1 bias.
pub const N_INPUT: u32 = (N_OBS + N_CONTROL + N_MEMORY + 1) as u32;
/// 5 control bits + 8 memory channels.
pub const N_OUTPUT: u32 = (N_CONTROL + N_MEMORY) as u32;

/// First identifier of each range. Inputs start at zero.
pub const OUTPUT_BASE: u32 = N_INPUT; // 141
pub const HIDDEN_BASE: u32 = N_INPUT + N_OUTPUT; // 154
pub const SCHEMA_VERSION: i64 = 1;

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub enum NodeKind {
    Input,
    Output,
    Hidden,
}

impl NodeKind {
    pub fn as_str(self) -> &'static str {
        match self {
            NodeKind::Input => "input",
            NodeKind::Output => "output",
            NodeKind::Hidden => "hidden",
        }
    }

    /// The only kind an identifier is allowed to carry.
    pub fn of_id(id: u32) -> NodeKind {
        if id < OUTPUT_BASE {
            NodeKind::Input
        } else if id < HIDDEN_BASE {
            NodeKind::Output
        } else {
            NodeKind::Hidden
        }
    }

    fn parse(raw: &str) -> Option<NodeKind> {
        match raw {
            "input" => Some(NodeKind::Input),
            "output" => Some(NodeKind::Output),
            "hidden" => Some(NodeKind::Hidden),
            _ => None,
        }
    }
}

#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Node {
    pub id: u32,
    pub kind: NodeKind,
}

#[derive(Copy, Clone, PartialEq, Debug)]
pub struct Gene {
    pub innovation: u32,
    pub from: u32,
    pub to: u32,
    pub weight: f64,
    pub enabled: bool,
}

#[derive(Clone, PartialEq, Debug, Default)]
pub struct Genome {
    /// Ascending by `id`, no duplicates.
    pub nodes: Vec<Node>,
    /// Ascending by `innovation`, no duplicates. Summation order follows this
    /// vector so that arithmetic is stable across languages and mutations.
    pub genes: Vec<Gene>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum GenomeError {
    SchemaVersion(i64),
    NotAnObject,
    MissingField(&'static str),
    BadField(&'static str),
    UnknownKind(String),
    KindMismatch { id: u32, declared: String },
    DuplicateNode(u32),
    DuplicateInnovation(u32),
    DuplicateEdge { from: u32, to: u32 },
    UnknownEndpoint { innovation: u32, node: u32 },
    InputDestination { innovation: u32, node: u32 },
    NonFiniteWeight(u32),
}

impl fmt::Display for GenomeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GenomeError::SchemaVersion(v) => write!(f, "unsupported schema_version {v}"),
            GenomeError::NotAnObject => write!(f, "genome must be a JSON object"),
            GenomeError::MissingField(n) => write!(f, "missing field {n}"),
            GenomeError::BadField(n) => write!(f, "malformed field {n}"),
            GenomeError::UnknownKind(k) => write!(f, "unknown node kind {k:?}"),
            GenomeError::KindMismatch { id, declared } => {
                write!(
                    f,
                    "node {id} declared {declared:?} but its identifier range is {:?}",
                    NodeKind::of_id(*id).as_str()
                )
            }
            GenomeError::DuplicateNode(id) => write!(f, "duplicate node {id}"),
            GenomeError::DuplicateInnovation(i) => write!(f, "duplicate innovation {i}"),
            GenomeError::DuplicateEdge { from, to } => {
                write!(f, "duplicate edge {from} -> {to}")
            }
            GenomeError::UnknownEndpoint { innovation, node } => {
                write!(f, "gene {innovation} references undeclared node {node}")
            }
            GenomeError::InputDestination { innovation, node } => {
                write!(f, "gene {innovation} targets input node {node}")
            }
            GenomeError::NonFiniteWeight(i) => write!(f, "gene {i} has a non-finite weight"),
        }
    }
}

fn as_u32(value: Option<&Value>, field: &'static str) -> Result<u32, GenomeError> {
    let n = value
        .ok_or(GenomeError::MissingField(field))?
        .as_i64()
        .ok_or(GenomeError::BadField(field))?;
    u32::try_from(n).map_err(|_| GenomeError::BadField(field))
}

impl Genome {
    /// The canonical seed: every input and output slot present, no genes. All
    /// evolved genomes descend from this, so identifier ranges stay meaningful.
    pub fn minimal() -> Genome {
        let mut nodes = Vec::with_capacity((N_INPUT + N_OUTPUT) as usize);
        for id in 0..N_INPUT + N_OUTPUT {
            nodes.push(Node {
                id,
                kind: NodeKind::of_id(id),
            });
        }
        Genome {
            nodes,
            genes: Vec::new(),
        }
    }

    pub fn has_node(&self, id: u32) -> bool {
        self.nodes.binary_search_by_key(&id, |n| n.id).is_ok()
    }

    pub fn hidden_count(&self) -> usize {
        self.nodes
            .iter()
            .filter(|n| n.kind == NodeKind::Hidden)
            .count()
    }

    pub fn enabled_count(&self) -> usize {
        self.genes.iter().filter(|g| g.enabled).count()
    }

    /// Sorts nodes and genes into canonical order, then enforces every rule in
    /// the module documentation. Called by both the decoder and the evolution
    /// loop so that no invalid genome can reach the runtime.
    pub fn validate(mut self) -> Result<Genome, GenomeError> {
        self.nodes.sort_by_key(|n| n.id);
        self.genes.sort_by_key(|g| g.innovation);

        let mut previous: Option<u32> = None;
        for node in &self.nodes {
            if previous == Some(node.id) {
                return Err(GenomeError::DuplicateNode(node.id));
            }
            if NodeKind::of_id(node.id) != node.kind {
                return Err(GenomeError::KindMismatch {
                    id: node.id,
                    declared: node.kind.as_str().to_string(),
                });
            }
            previous = Some(node.id);
        }

        let mut innovation: Option<u32> = None;
        let mut edges: BTreeSet<(u32, u32)> = BTreeSet::new();
        for gene in &self.genes {
            if innovation == Some(gene.innovation) {
                return Err(GenomeError::DuplicateInnovation(gene.innovation));
            }
            innovation = Some(gene.innovation);
            if !gene.weight.is_finite() {
                return Err(GenomeError::NonFiniteWeight(gene.innovation));
            }
            for end in [gene.from, gene.to] {
                if !self.has_node(end) {
                    return Err(GenomeError::UnknownEndpoint {
                        innovation: gene.innovation,
                        node: end,
                    });
                }
            }
            if NodeKind::of_id(gene.to) == NodeKind::Input {
                return Err(GenomeError::InputDestination {
                    innovation: gene.innovation,
                    node: gene.to,
                });
            }
            if !edges.insert((gene.from, gene.to)) {
                return Err(GenomeError::DuplicateEdge {
                    from: gene.from,
                    to: gene.to,
                });
            }
        }
        Ok(self)
    }

    pub fn from_json(value: &Value) -> Result<Genome, GenomeError> {
        let object = value.as_object().ok_or(GenomeError::NotAnObject)?;
        match object.get("schema_version").and_then(Value::as_i64) {
            Some(SCHEMA_VERSION) => {}
            Some(other) => return Err(GenomeError::SchemaVersion(other)),
            None => return Err(GenomeError::MissingField("schema_version")),
        }
        let raw_nodes = object
            .get("nodes")
            .ok_or(GenomeError::MissingField("nodes"))?
            .as_array()
            .ok_or(GenomeError::BadField("nodes"))?;
        let mut nodes = Vec::with_capacity(raw_nodes.len());
        for raw in raw_nodes {
            let entry = raw.as_object().ok_or(GenomeError::BadField("nodes"))?;
            let id = as_u32(entry.get("id"), "id")?;
            let raw_kind = entry
                .get("kind")
                .ok_or(GenomeError::MissingField("kind"))?
                .as_str()
                .ok_or(GenomeError::BadField("kind"))?;
            let kind =
                NodeKind::parse(raw_kind).ok_or_else(|| GenomeError::UnknownKind(raw_kind.into()))?;
            nodes.push(Node { id, kind });
        }
        let raw_genes = object
            .get("genes")
            .ok_or(GenomeError::MissingField("genes"))?
            .as_array()
            .ok_or(GenomeError::BadField("genes"))?;
        let mut genes = Vec::with_capacity(raw_genes.len());
        for raw in raw_genes {
            let entry = raw.as_object().ok_or(GenomeError::BadField("genes"))?;
            genes.push(Gene {
                innovation: as_u32(entry.get("innovation"), "innovation")?,
                from: as_u32(entry.get("from"), "from")?,
                to: as_u32(entry.get("to"), "to")?,
                weight: entry
                    .get("weight")
                    .ok_or(GenomeError::MissingField("weight"))?
                    .as_f64()
                    .ok_or(GenomeError::BadField("weight"))?,
                enabled: entry
                    .get("enabled")
                    .ok_or(GenomeError::MissingField("enabled"))?
                    .as_bool()
                    .ok_or(GenomeError::BadField("enabled"))?,
            });
        }
        Genome { nodes, genes }.validate()
    }

    pub fn parse(raw: &str) -> Result<Genome, String> {
        let value: Value = serde_json::from_str(raw).map_err(|e| e.to_string())?;
        Genome::from_json(&value).map_err(|e| e.to_string())
    }

    pub fn to_json(&self) -> Value {
        let nodes: Vec<Value> = self
            .nodes
            .iter()
            .map(|n| json!({"id": n.id, "kind": n.kind.as_str()}))
            .collect();
        let genes: Vec<Value> = self
            .genes
            .iter()
            .map(|g| {
                let mut entry = Map::new();
                entry.insert("innovation".into(), json!(g.innovation));
                entry.insert("from".into(), json!(g.from));
                entry.insert("to".into(), json!(g.to));
                entry.insert("weight".into(), json!(g.weight));
                entry.insert("enabled".into(), json!(g.enabled));
                Value::Object(entry)
            })
            .collect();
        json!({"schema_version": SCHEMA_VERSION, "nodes": nodes, "genes": genes})
    }

    /// Identity of a candidate policy. Gate evidence is keyed by this, so any
    /// weight or structure change invalidates the evidence that preceded it.
    /// Weights enter through their exact IEEE-754 bits: two genomes with the
    /// same fingerprint behave identically.
    pub fn fingerprint(&self) -> String {
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        let mut absorb = |word: u64| {
            hash ^= word;
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        };
        absorb(SCHEMA_VERSION as u64);
        for node in &self.nodes {
            absorb(node.id as u64);
            absorb(node.kind as u64 + 1);
        }
        for gene in &self.genes {
            absorb(gene.innovation as u64);
            absorb(gene.from as u64);
            absorb(gene.to as u64);
            absorb(gene.weight.to_bits());
            absorb(gene.enabled as u64);
        }
        format!("g{hash:016x}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn minimal_seed_is_valid_and_covers_every_fixed_slot() {
        let genome = Genome::minimal().validate().expect("minimal is valid");
        assert_eq!(genome.nodes.len(), HIDDEN_BASE as usize);
        assert_eq!(genome.nodes[0].kind, NodeKind::Input);
        assert_eq!(genome.nodes[(N_INPUT - 1) as usize].kind, NodeKind::Input);
        assert_eq!(genome.nodes[OUTPUT_BASE as usize].kind, NodeKind::Output);
        assert_eq!(
            genome.nodes[(HIDDEN_BASE - 1) as usize].kind,
            NodeKind::Output
        );
        assert!(genome.genes.is_empty());
    }

    fn seeded(genes: Vec<Gene>) -> Genome {
        let mut genome = Genome::minimal();
        genome.nodes.push(Node {
            id: HIDDEN_BASE,
            kind: NodeKind::Hidden,
        });
        genome.genes = genes;
        genome
    }

    #[test]
    fn round_trips_through_json_in_canonical_order() {
        let genome = seeded(vec![
            Gene {
                innovation: 7,
                from: N_INPUT - 1,
                to: HIDDEN_BASE,
                weight: -0.25,
                enabled: true,
            },
            Gene {
                innovation: 3,
                from: 0,
                to: OUTPUT_BASE,
                weight: 1.5,
                enabled: false,
            },
        ])
        .validate()
        .unwrap();
        assert_eq!(genome.genes[0].innovation, 3);
        let back = Genome::from_json(&genome.to_json()).unwrap();
        assert_eq!(back, genome);
        assert_eq!(back.fingerprint(), genome.fingerprint());
    }

    #[test]
    fn rejects_every_invalid_shape() {
        let mismatch = Genome {
            nodes: vec![Node {
                id: 0,
                kind: NodeKind::Hidden,
            }],
            genes: vec![],
        };
        assert!(matches!(
            mismatch.validate(),
            Err(GenomeError::KindMismatch { id: 0, .. })
        ));

        let duplicate_node = Genome {
            nodes: vec![
                Node {
                    id: 0,
                    kind: NodeKind::Input,
                },
                Node {
                    id: 0,
                    kind: NodeKind::Input,
                },
            ],
            genes: vec![],
        };
        assert_eq!(
            duplicate_node.validate(),
            Err(GenomeError::DuplicateNode(0))
        );

        let to_input = seeded(vec![Gene {
            innovation: 1,
            from: HIDDEN_BASE,
            to: 3,
            weight: 0.0,
            enabled: true,
        }]);
        assert!(matches!(
            to_input.validate(),
            Err(GenomeError::InputDestination { node: 3, .. })
        ));

        let unknown = seeded(vec![Gene {
            innovation: 1,
            from: 999,
            to: OUTPUT_BASE,
            weight: 0.0,
            enabled: true,
        }]);
        assert!(matches!(
            unknown.validate(),
            Err(GenomeError::UnknownEndpoint { node: 999, .. })
        ));

        let nan = seeded(vec![Gene {
            innovation: 1,
            from: 0,
            to: OUTPUT_BASE,
            weight: f64::NAN,
            enabled: true,
        }]);
        assert_eq!(nan.validate(), Err(GenomeError::NonFiniteWeight(1)));

        let twice = seeded(vec![
            Gene {
                innovation: 1,
                from: 0,
                to: OUTPUT_BASE,
                weight: 0.0,
                enabled: true,
            },
            Gene {
                innovation: 2,
                from: 0,
                to: OUTPUT_BASE,
                weight: 1.0,
                enabled: false,
            },
        ]);
        assert_eq!(
            twice.validate(),
            Err(GenomeError::DuplicateEdge {
                from: 0,
                to: OUTPUT_BASE
            })
        );

        let same_innovation = seeded(vec![
            Gene {
                innovation: 1,
                from: 0,
                to: OUTPUT_BASE,
                weight: 0.0,
                enabled: true,
            },
            Gene {
                innovation: 1,
                from: 1,
                to: OUTPUT_BASE,
                weight: 0.0,
                enabled: true,
            },
        ]);
        assert_eq!(
            same_innovation.validate(),
            Err(GenomeError::DuplicateInnovation(1))
        );
    }

    #[test]
    fn rejects_foreign_schema_versions() {
        let value = json!({"schema_version": 2, "nodes": [], "genes": []});
        assert_eq!(
            Genome::from_json(&value),
            Err(GenomeError::SchemaVersion(2))
        );
    }

    #[test]
    fn every_evolved_weight_survives_a_checkpoint_round_trip_bit_for_bit() {
        // A weight that needs seventeen significant digits only round trips if
        // the JSON parser is correctly rounded. Without that, decoding a
        // checkpoint can move a weight by one unit in the last place, which
        // changes the fingerprint, which throws away the gate evidence that
        // fingerprint is keyed to and makes a resume a different run.
        use crate::rng::Stream;
        let mut rng = Stream::seeded(0xfeed);
        let mut genome = Genome::minimal();
        genome.nodes.push(Node {
            id: HIDDEN_BASE,
            kind: NodeKind::Hidden,
        });
        for innovation in 1..500u32 {
            // Distinct (from, to) for every innovation: the input walks fastest
            // so that no two genes claim the same edge.
            let from = innovation % N_INPUT;
            genome.genes.push(Gene {
                innovation,
                from,
                to: OUTPUT_BASE + (innovation / N_INPUT) % N_OUTPUT,
                weight: rng.signed() * 2.0,
                enabled: innovation % 7 != 0,
            });
        }
        // Include the exact values that expose a fast, incorrectly rounded
        // parser, each one a different neighbour of minus one.
        for (at, awkward) in [-0.9999999999999999_f64, 0.1, 1e-300, 2.2250738585072014e-308]
            .into_iter()
            .enumerate()
        {
            genome.genes[at].weight = awkward;
        }
        let genome = genome.validate().unwrap();

        let text = serde_json::to_string(&genome.to_json()).unwrap();
        let back = Genome::parse(&text).expect("a genome must survive JSON");
        assert_eq!(back.genes.len(), genome.genes.len());
        for (before, after) in genome.genes.iter().zip(&back.genes) {
            assert_eq!(
                before.weight.to_bits(),
                after.weight.to_bits(),
                "weight {} came back as {} ({} vs {} bits)",
                before.weight,
                after.weight,
                before.weight.to_bits(),
                after.weight.to_bits()
            );
        }
        assert_eq!(back.fingerprint(), genome.fingerprint());
        assert_eq!(back, genome);
    }

    #[test]
    fn fingerprint_separates_weight_changes_but_ignores_storage_order() {
        let a = seeded(vec![
            Gene {
                innovation: 1,
                from: 0,
                to: OUTPUT_BASE,
                weight: 0.5,
                enabled: true,
            },
            Gene {
                innovation: 2,
                from: 1,
                to: OUTPUT_BASE,
                weight: 0.5,
                enabled: true,
            },
        ])
        .validate()
        .unwrap();
        let mut shuffled = a.clone();
        shuffled.genes.reverse();
        assert_eq!(shuffled.validate().unwrap().fingerprint(), a.fingerprint());

        let mut nudged = a.clone();
        nudged.genes[0].weight = 0.5000000001;
        assert_ne!(nudged.fingerprint(), a.fingerprint());
    }
}
