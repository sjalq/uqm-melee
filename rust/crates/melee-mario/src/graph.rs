//! Compiled sparse network and its episode state.
//!
//! EXACT GRAPH SEMANTICS. `tests/Mario/Genome.elm` implements the same rules
//! and `melee-mario oracle` exists so the two can be compared step for step.
//! Nothing here may be "simplified"; the ordering rules are the definition of
//! the policy, not an implementation detail.
//!
//!  1. Only enabled genes take part. A disabled gene contributes nothing and
//!     does not affect ordering.
//!  2. The enabled-gene digraph is decomposed into strongly connected
//!     components; the components are visited in a topological order of the
//!     condensation, and within a component the member nodes are visited in
//!     ascending node-identifier order.
//!  3. An edge whose endpoints lie in the same CYCLIC component (a component
//!     of two or more nodes, or a single node carrying a self-loop) reads the
//!     source's value from the PREVIOUS decision. Every other edge reads the
//!     value computed during the CURRENT decision. Because a non-recurrent
//!     edge can only run from an earlier component to a later one, the result
//!     does not depend on which valid topological order was chosen.
//!  4. A node's incoming edges are summed in ascending innovation order, so
//!     floating-point addition is associative-order stable across languages
//!     and across mutations that reorder storage.
//!  5. Input nodes are driven directly and never have incoming edges. A
//!     non-input node with no enabled incoming edge sums to zero and therefore
//!     outputs zero, which is also what `sigmoid(0)` returns.
//!  6. `sigmoid(x) = 2 / (1 + exp(-4.9 * x)) - 1`, which is exactly
//!     `tanh(2.45 * x)`, with a non-finite accumulator saturating:
//!     `+inf -> 1`, `-inf -> -1`, `NaN -> 0`. Near zero the exponential form
//!     is evaluated through a cancellation: `exp(-4.9x)` rounds to a
//!     neighbour of 1, `2 / (1 + that)` rounds to a neighbour of 1, and the
//!     final subtraction keeps only the rounding noise, which two runtimes
//!     need not agree on. Since a control is asserted when its output is
//!     strictly greater than zero, that noise can flip a control. So for
//!     `|x| < 1e-5` the odd Taylor series of `tanh` is used instead; see
//!     [`sigmoid`] for the exact expression both languages must write.
//!  7. All activations are zero when an episode begins and whenever the state
//!     is reset (a new round, or a different ship in the seat).

use crate::genome::{Genome, NodeKind, N_INPUT, N_OUTPUT};

/// Cutoff below which the series form is used. At `|x| = 1e-5` the next
/// series term is `2 u^5 / 15` with `u = 2.45e-5`, which is about `5e-20`
/// relative to `u` and therefore far below the last bit of the result, so two
/// terms are exact here. Above the cutoff the exponential form has no
/// cancellation left to worry about.
pub const SERIES_CUTOFF: f64 = 1.0e-5;

/// `2 / (1 + exp(-4.9 x)) - 1`, the activation the original MarI/O used,
/// written so that both runtimes agree on the SIGN as well as the value.
///
/// Every language implementing this genome must write these two expressions
/// exactly as they stand, including the association:
///
/// ```text
///   u = 2.45 * x
///   |x| <  1e-5  ->  u - u * u * u / 3.0
///   |x| >= 1e-5  ->  2.0 / (1.0 + exp(-4.9 * x)) - 1.0
/// ```
///
/// The series branch is an odd polynomial, so its sign is the sign of `x` with
/// no rounding involved at all, and it is composed only of correctly rounded
/// multiplications, a division by an exact power of two's neighbour and one
/// subtraction, which IEEE-754 makes bit-identical everywhere. The branch
/// above the cutoff never approaches zero closely enough for rounding to
/// decide a control.
#[inline]
pub fn sigmoid(x: f64) -> f64 {
    if x.is_nan() {
        return 0.0;
    }
    let u = 2.45 * x;
    if x.abs() < SERIES_CUTOFF {
        u - u * u * u / 3.0
    } else {
        2.0 / (1.0 + (-4.9 * x).exp()) - 1.0
    }
}

#[derive(Copy, Clone, Debug)]
struct Edge {
    source: u32,
    weight: f64,
    /// Reads the previous decision's activation instead of this one's.
    recurrent: bool,
}

/// Immutable compiled form of a genome. Shared by every episode that runs the
/// same policy; all mutable per-episode data lives in [`Activations`].
#[derive(Clone, Debug)]
pub struct Network {
    width: usize,
    /// Non-input node indices, in evaluation order.
    order: Vec<u32>,
    edges: Vec<Edge>,
    /// `spans[i]` is the half-open range of `edges` feeding node index `i`.
    spans: Vec<(u32, u32)>,
    input_slot: [Option<u32>; N_INPUT as usize],
    output_slot: [Option<u32>; N_OUTPUT as usize],
    node_count: usize,
    link_count: usize,
}

/// Mutable per-episode activation state. Separate from [`Network`] so a single
/// compiled policy can be evaluated in many independent episodes.
#[derive(Clone, Debug)]
pub struct Activations {
    current: Vec<f64>,
    previous: Vec<f64>,
}

impl Activations {
    pub fn new(net: &Network) -> Activations {
        Activations {
            current: vec![0.0; net.width],
            previous: vec![0.0; net.width],
        }
    }

    /// Back to the start-of-episode state: every activation zero.
    pub fn reset(&mut self) {
        self.current.fill(0.0);
        self.previous.fill(0.0);
    }
}

impl Network {
    /// Declared nodes, including inputs and outputs that carry no edges.
    pub fn node_count(&self) -> usize {
        self.node_count
    }

    /// Enabled genes; the disabled ones are not part of the runtime.
    pub fn link_count(&self) -> usize {
        self.link_count
    }

    pub fn compile(genome: &Genome) -> Network {
        let width = genome.nodes.len();
        let index_of = |id: u32| -> Option<u32> {
            genome
                .nodes
                .binary_search_by_key(&id, |n| n.id)
                .ok()
                .map(|i| i as u32)
        };

        let mut input_slot = [None; N_INPUT as usize];
        let mut output_slot = [None; N_OUTPUT as usize];
        for (i, node) in genome.nodes.iter().enumerate() {
            match node.kind {
                NodeKind::Input => input_slot[node.id as usize] = Some(i as u32),
                NodeKind::Output => output_slot[(node.id - N_INPUT) as usize] = Some(i as u32),
                NodeKind::Hidden => {}
            }
        }

        // Incoming lists keep the genome's innovation order (rule 4); outgoing
        // lists are sorted by target index so the traversal is deterministic.
        let mut incoming: Vec<Vec<(u32, f64)>> = vec![Vec::new(); width];
        let mut outgoing: Vec<Vec<u32>> = vec![Vec::new(); width];
        let mut link_count = 0;
        for gene in genome.genes.iter().filter(|g| g.enabled) {
            let (Some(from), Some(to)) = (index_of(gene.from), index_of(gene.to)) else {
                continue;
            };
            incoming[to as usize].push((from, gene.weight));
            outgoing[from as usize].push(to);
            link_count += 1;
        }
        for list in outgoing.iter_mut() {
            list.sort_unstable();
        }

        let (component, components) = strongly_connected(&outgoing);
        let cyclic = cyclic_components(&outgoing, &component, components);

        // Tarjan emits a component only after everything it can reach, so the
        // emission order is a reverse topological order of the condensation.
        let mut members: Vec<Vec<u32>> = vec![Vec::new(); components];
        for (index, &c) in component.iter().enumerate() {
            members[c as usize].push(index as u32);
        }
        let mut order = Vec::with_capacity(width);
        for group in members.iter().rev() {
            // Node indices ascend with node identifiers, so index order is
            // identifier order (rule 2).
            for &index in group.iter() {
                if genome.nodes[index as usize].kind != NodeKind::Input {
                    order.push(index);
                }
            }
        }

        let mut edges = Vec::with_capacity(link_count);
        let mut spans = vec![(0u32, 0u32); width];
        for (index, list) in incoming.iter().enumerate() {
            let start = edges.len() as u32;
            for &(source, weight) in list {
                edges.push(Edge {
                    source,
                    weight,
                    recurrent: component[source as usize] == component[index]
                        && cyclic[component[index] as usize],
                });
            }
            spans[index] = (start, edges.len() as u32);
        }

        Network {
            width,
            order,
            edges,
            spans,
            input_slot,
            output_slot,
            node_count: width,
            link_count,
        }
    }

    /// One decision. `inputs` is the assembled 57-slot input vector; the
    /// returned 13 values are the raw output activations.
    pub fn activate(&self, state: &mut Activations, inputs: &[f64; N_INPUT as usize]) -> [f64; N_OUTPUT as usize] {
        state.previous.copy_from_slice(&state.current);
        for (slot, value) in self.input_slot.iter().zip(inputs.iter()) {
            if let Some(index) = slot {
                state.current[*index as usize] = *value;
            }
        }
        for &index in &self.order {
            let (start, end) = self.spans[index as usize];
            let mut sum = 0.0;
            for edge in &self.edges[start as usize..end as usize] {
                let source = edge.source as usize;
                let value = if edge.recurrent {
                    state.previous[source]
                } else {
                    state.current[source]
                };
                sum += edge.weight * value;
            }
            state.current[index as usize] = sigmoid(sum);
        }
        let mut outputs = [0.0; N_OUTPUT as usize];
        for (out, slot) in outputs.iter_mut().zip(self.output_slot.iter()) {
            // An output slot the genome never declared reads as zero.
            *out = slot.map_or(0.0, |index| state.current[index as usize]);
        }
        outputs
    }
}

/// Iterative Tarjan. Returns each node's component identifier plus the number
/// of components. Components are numbered in emission order, which is a
/// reverse topological order of the condensation.
fn strongly_connected(outgoing: &[Vec<u32>]) -> (Vec<u32>, usize) {
    let width = outgoing.len();
    const UNVISITED: u32 = u32::MAX;
    let mut index = vec![UNVISITED; width];
    let mut low = vec![0u32; width];
    let mut on_stack = vec![false; width];
    let mut component = vec![UNVISITED; width];
    let mut stack: Vec<u32> = Vec::new();
    let mut counter: u32 = 0;
    let mut components = 0usize;
    // (node, next outgoing edge to explore)
    let mut work: Vec<(u32, usize)> = Vec::new();

    for root in 0..width as u32 {
        if index[root as usize] != UNVISITED {
            continue;
        }
        work.push((root, 0));
        while let Some((node, edge)) = work.pop() {
            let n = node as usize;
            if edge == 0 {
                index[n] = counter;
                low[n] = counter;
                counter += 1;
                stack.push(node);
                on_stack[n] = true;
            }
            let mut descended = false;
            for (offset, &next) in outgoing[n].iter().enumerate().skip(edge) {
                let m = next as usize;
                if index[m] == UNVISITED {
                    work.push((node, offset + 1));
                    work.push((next, 0));
                    descended = true;
                    break;
                } else if on_stack[m] {
                    low[n] = low[n].min(index[m]);
                }
            }
            if descended {
                continue;
            }
            if low[n] == index[n] {
                while let Some(popped) = stack.pop() {
                    on_stack[popped as usize] = false;
                    component[popped as usize] = components as u32;
                    if popped == node {
                        break;
                    }
                }
                components += 1;
            }
            if let Some(&(parent, _)) = work.last() {
                let p = parent as usize;
                low[p] = low[p].min(low[n]);
            }
        }
    }
    (component, components)
}

/// A component is cyclic when it holds more than one node, or one node that
/// links to itself. Only edges inside a cyclic component are recurrent.
fn cyclic_components(outgoing: &[Vec<u32>], component: &[u32], components: usize) -> Vec<bool> {
    let mut size = vec![0usize; components];
    for &c in component {
        size[c as usize] += 1;
    }
    let mut cyclic: Vec<bool> = size.iter().map(|&n| n > 1).collect();
    for (node, targets) in outgoing.iter().enumerate() {
        if targets.contains(&(node as u32)) {
            cyclic[component[node] as usize] = true;
        }
    }
    cyclic
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::genome::{Gene, Node};

    fn genome(hidden: &[u32], genes: &[(u32, u32, u32, f64)]) -> Genome {
        let mut g = Genome::minimal();
        for &id in hidden {
            g.nodes.push(Node {
                id,
                kind: NodeKind::Hidden,
            });
        }
        g.genes = genes
            .iter()
            .map(|&(innovation, from, to, weight)| Gene {
                innovation,
                from,
                to,
                weight,
                enabled: true,
            })
            .collect();
        g.validate().unwrap()
    }

    #[test]
    fn sigmoid_matches_the_declared_formula_and_saturates() {
        assert_eq!(sigmoid(0.0), 0.0);
        assert!((sigmoid(1.0) - (2.0 / (1.0 + (-4.9f64).exp()) - 1.0)).abs() < 1e-15);
        assert_eq!(sigmoid(f64::INFINITY), 1.0);
        assert_eq!(sigmoid(f64::NEG_INFINITY), -1.0);
        assert_eq!(sigmoid(f64::NAN), 0.0);
        assert!(sigmoid(-1000.0) > -1.0000001 && sigmoid(-1000.0) <= -1.0 + 1e-12);
    }

    #[test]
    fn sigmoid_never_lets_rounding_decide_a_control_near_zero() {
        // A control is asserted on `> 0`, so the sign has to be the sign of the
        // input for every input, including the ones where the exponential form
        // cancels down to nothing but rounding noise.
        assert_eq!(sigmoid(0.0), 0.0);
        assert_eq!(sigmoid(-0.0), 0.0);
        let mut x = 1.0e-3;
        while x > 0.0 {
            assert!(sigmoid(x) > 0.0, "sigmoid({x:e}) was not positive");
            assert!(sigmoid(-x) < 0.0, "sigmoid({:e}) was not negative", -x);
            if x < SERIES_CUTOFF {
                // Below the cutoff the polynomial is exactly odd, so the two
                // seats of a mirrored fight cannot disagree by a rounding step.
                assert_eq!(sigmoid(-x), -sigmoid(x), "series stopped being odd at {x:e}");
            }
            x /= 2.0;
        }
        // The exponential form collapses exactly where the series takes over.
        let naive = |x: f64| 2.0 / (1.0 + (-4.9 * x).exp()) - 1.0;
        assert_eq!(naive(1.0e-17), 0.0, "the defect this branch exists for");
        assert!(sigmoid(1.0e-17) > 0.0);
    }

    #[test]
    fn the_two_sigmoid_branches_join_smoothly_at_the_cutoff() {
        let naive = |x: f64| 2.0 / (1.0 + (-4.9 * x).exp()) - 1.0;
        // Just ABOVE the cutoff the exponential form is still the one in use,
        // and the series it replaced would have given the same answer to well
        // within the value's own precision. Its residual error there is the
        // cancellation, about one part in 1e11, which is nowhere near enough to
        // change a sign.
        for step in 1..=1000 {
            let x = SERIES_CUTOFF * (1.0 + step as f64 / 100.0);
            let series = 2.45 * x - (2.45 * x) * (2.45 * x) * (2.45 * x) / 3.0;
            let relative = ((naive(x) - series) / series).abs();
            assert!(relative < 1e-9, "branches disagree at {x:e} by {relative:e}");
        }
        // Below the cutoff the series is the true tanh to full precision.
        for x in [1e-6_f64, 1e-7, 5e-6, -3e-6, 9.9e-6] {
            assert!(
                (sigmoid(x) - (2.45 * x).tanh()).abs() <= 1e-21,
                "series is not tanh at {x:e}"
            );
        }
        // The old formula collapses entirely well before the cutoff, which is
        // exactly the region the series now covers.
        assert_eq!(naive(1e-17), 0.0);
        assert!(naive(1e-16) != 2.45e-16, "the cancellation is real");
    }

    #[test]
    fn isolated_non_input_nodes_output_zero() {
        let net = Network::compile(&Genome::minimal());
        let mut state = Activations::new(&net);
        let outputs = net.activate(&mut state, &[1.0; N_INPUT as usize]);
        assert_eq!(outputs, [0.0; N_OUTPUT as usize]);
        assert_eq!(net.link_count(), 0);
        assert_eq!(net.node_count(), 70);
    }

    #[test]
    fn feed_forward_chain_resolves_within_one_activation() {
        // input 0 -> hidden 70 -> output 57, both weights 1.
        let net = Network::compile(&genome(&[70], &[(1, 0, 70, 1.0), (2, 70, 57, 1.0)]));
        let mut state = Activations::new(&net);
        let mut inputs = [0.0; N_INPUT as usize];
        inputs[0] = 1.0;
        let outputs = net.activate(&mut state, &inputs);
        assert!((outputs[0] - sigmoid(sigmoid(1.0))).abs() < 1e-15);
        // A feed-forward graph is memoryless: repeating the input repeats it.
        let again = net.activate(&mut state, &inputs);
        assert_eq!(again[0], outputs[0]);
    }

    #[test]
    fn self_loop_reads_the_previous_decision() {
        // input 0 -> hidden 70, and hidden 70 -> hidden 70 (recurrent).
        let net = Network::compile(&genome(
            &[70],
            &[(1, 0, 70, 1.0), (2, 70, 70, 1.0), (3, 70, 57, 1.0)],
        ));
        let mut state = Activations::new(&net);
        let mut inputs = [0.0; N_INPUT as usize];
        inputs[0] = 1.0;
        let first = net.activate(&mut state, &inputs);
        let second = net.activate(&mut state, &inputs);
        // Step one sees a zero self-input; step two sees step one's value.
        let h1 = sigmoid(1.0);
        let h2 = sigmoid(1.0 + h1);
        assert!((first[0] - sigmoid(h1)).abs() < 1e-15);
        assert!((second[0] - sigmoid(h2)).abs() < 1e-15);
        state.reset();
        let after_reset = net.activate(&mut state, &inputs);
        assert_eq!(after_reset[0], first[0]);
    }

    #[test]
    fn two_cycle_reads_previous_on_both_intra_component_edges() {
        // 70 <-> 71 form one cyclic component; 0 -> 70 is a normal edge.
        let net = Network::compile(&genome(
            &[70, 71],
            &[
                (1, 0, 70, 1.0),
                (2, 70, 71, 1.0),
                (3, 71, 70, 1.0),
                (4, 71, 57, 1.0),
            ],
        ));
        let mut state = Activations::new(&net);
        let mut inputs = [0.0; N_INPUT as usize];
        inputs[0] = 1.0;
        let first = net.activate(&mut state, &inputs);
        assert_eq!(first[0], sigmoid(0.0));
        let second = net.activate(&mut state, &inputs);
        // 70 was sigmoid(1 + 0) on step one, so 71 now sees it.
        assert!((second[0] - sigmoid(sigmoid(sigmoid(1.0)))).abs() < 1e-15);
    }

    #[test]
    fn disabled_genes_are_absent_from_the_runtime() {
        let mut g = genome(&[70], &[(1, 0, 70, 1.0), (2, 70, 57, 1.0)]);
        g.genes[0].enabled = false;
        let net = Network::compile(&g);
        assert_eq!(net.link_count(), 1);
        let mut state = Activations::new(&net);
        let mut inputs = [0.0; N_INPUT as usize];
        inputs[0] = 1.0;
        assert_eq!(net.activate(&mut state, &inputs)[0], 0.0);
    }

    #[test]
    fn long_feed_forward_chain_resolves_in_one_pass() {
        // 0 -> 70 -> 71 -> ... -> 79 -> 57, declared out of topological order.
        let hidden: Vec<u32> = (70..80).collect();
        let mut genes = vec![(1u32, 79u32, 57u32, 1.0f64)];
        for (i, id) in hidden.iter().enumerate() {
            let from = if i == 0 { 0 } else { hidden[i - 1] };
            genes.push((2 + i as u32, from, *id, 1.0));
        }
        let net = Network::compile(&genome(&hidden, &genes));
        let mut state = Activations::new(&net);
        let mut inputs = [0.0; N_INPUT as usize];
        inputs[0] = 1.0;
        let mut expected = 1.0;
        for _ in 0..11 {
            expected = sigmoid(expected);
        }
        assert!((net.activate(&mut state, &inputs)[0] - expected).abs() < 1e-14);
    }
}
