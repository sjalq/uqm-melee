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

/// One node's turn in the evaluation order, carrying the half-open range of
/// the edge arrays that feeds it. Fusing the node with its span lets a decision
/// walk `steps` and the edge arrays as three sequential streams.
#[derive(Copy, Clone, Debug)]
struct Step {
    node: u32,
    start: u32,
    end: u32,
}

/// Immutable compiled form of a genome. Shared by every episode that runs the
/// same policy; all mutable per-episode data lives in [`Activations`].
///
/// An activation buffer is two halves of one allocation. The first `width`
/// slots hold the decision being computed, one per node index. The rest are the
/// SHADOW half: one slot per node that some recurrent edge reads, frozen at the
/// top of a decision. Rule 3's choice between the previous and the current
/// decision is therefore made once, at compile time, and survives as nothing
/// but the slot number an edge carries, so the inner loop has no branch and the
/// per-decision carry-over costs one slot per recurrent SOURCE rather than a
/// copy of every node.
#[derive(Clone, Debug)]
pub struct Network {
    width: usize,
    /// Non-input nodes in evaluation order, each with its edge span.
    steps: Vec<Step>,
    /// Activation-buffer slot each incoming edge reads, in evaluation order and
    /// within a node in ascending innovation order (rule 4).
    edge_slot: Vec<u32>,
    /// Weights parallel to `edge_slot`.
    edge_weight: Vec<f64>,
    /// Node indices frozen into the shadow half before a decision; the node at
    /// position `i` lives in slot `width + i`.
    recurrent_sources: Vec<u32>,
    input_slot: [Option<u32>; N_INPUT as usize],
    /// Every input node is declared, so the input vector lands on slots
    /// `0..N_INPUT` unchanged and can be written in one copy.
    inputs_contiguous: bool,
    output_slot: [Option<u32>; N_OUTPUT as usize],
    node_count: usize,
    link_count: usize,
}

/// Mutable per-episode activation state. Separate from [`Network`] so a single
/// compiled policy can be evaluated in many independent episodes.
#[derive(Clone, Debug)]
pub struct Activations {
    /// The current decision, then the shadow half; see [`Network`].
    values: Vec<f64>,
}

impl Activations {
    pub fn new(net: &Network) -> Activations {
        Activations {
            values: vec![0.0; net.width + net.recurrent_sources.len()],
        }
    }

    /// Back to the start-of-episode state: every activation zero.
    pub fn reset(&mut self) {
        self.values.fill(0.0);
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

        // Edges are laid out in evaluation order so a decision streams through
        // them once, front to back. Within a node the genome's innovation order
        // is untouched (rule 4), which is the only order the sums depend on.
        let mut steps = Vec::with_capacity(order.len());
        let mut edge_slot: Vec<u32> = Vec::with_capacity(link_count);
        let mut edge_weight: Vec<f64> = Vec::with_capacity(link_count);
        let mut shadow_of = vec![u32::MAX; width];
        let mut recurrent_sources: Vec<u32> = Vec::new();
        for &index in order.iter() {
            let start = edge_slot.len() as u32;
            for &(source, weight) in incoming[index as usize].iter() {
                let recurrent = component[source as usize] == component[index as usize]
                    && cyclic[component[index as usize] as usize];
                let slot = if !recurrent {
                    source
                } else if shadow_of[source as usize] != u32::MAX {
                    shadow_of[source as usize]
                } else {
                    let slot = (width + recurrent_sources.len()) as u32;
                    shadow_of[source as usize] = slot;
                    recurrent_sources.push(source);
                    slot
                };
                edge_slot.push(slot);
                edge_weight.push(weight);
            }
            steps.push(Step {
                node: index,
                start,
                end: edge_slot.len() as u32,
            });
        }

        let inputs_contiguous = input_slot
            .iter()
            .enumerate()
            .all(|(id, slot)| *slot == Some(id as u32));

        Network {
            width,
            steps,
            edge_slot,
            edge_weight,
            recurrent_sources,
            input_slot,
            inputs_contiguous,
            output_slot,
            node_count: width,
            link_count,
        }
    }

    /// One decision. `inputs` is the assembled 57-slot input vector; the
    /// returned 13 values are the raw output activations.
    pub fn activate(&self, state: &mut Activations, inputs: &[f64; N_INPUT as usize]) -> [f64; N_OUTPUT as usize] {
        let values = &mut state.values;
        // Rule 3. This has to happen before anything overwrites the current
        // half: it freezes the PREVIOUS decision's value of every node a
        // recurrent edge reads. Only those nodes are carried over, so a
        // feed-forward genome copies nothing at all.
        for (offset, &source) in self.recurrent_sources.iter().enumerate() {
            values[self.width + offset] = values[source as usize];
        }
        if self.inputs_contiguous {
            values[..N_INPUT as usize].copy_from_slice(inputs);
        } else {
            for (slot, value) in self.input_slot.iter().zip(inputs.iter()) {
                if let Some(index) = slot {
                    values[*index as usize] = *value;
                }
            }
        }
        for step in self.steps.iter() {
            let (start, end) = (step.start as usize, step.end as usize);
            let slots = &self.edge_slot[start..end];
            let weights = &self.edge_weight[start..end];
            let mut sum = 0.0;
            for (&slot, &weight) in slots.iter().zip(weights.iter()) {
                sum += weight * values[slot as usize];
            }
            values[step.node as usize] = sigmoid(sum);
        }
        let mut outputs = [0.0; N_OUTPUT as usize];
        for (out, slot) in outputs.iter_mut().zip(self.output_slot.iter()) {
            // An output slot the genome never declared reads as zero.
            *out = slot.map_or(0.0, |index| values[index as usize]);
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
    use crate::genome::{Gene, Node, HIDDEN_BASE, OUTPUT_BASE};

    /// Named landmarks rather than literals: these tests are about the graph's
    /// evaluation rules, not about how wide the observation vector happens to
    /// be, so widening that vector must not make them lie.
    const BIAS: u32 = N_INPUT - 1;
    const OUT0: u32 = OUTPUT_BASE;
    const OUT1: u32 = OUTPUT_BASE + 1;
    const OUT_LAST: u32 = HIDDEN_BASE - 1;
    const H0: u32 = HIDDEN_BASE;
    const H1: u32 = HIDDEN_BASE + 1;
    const H2: u32 = HIDDEN_BASE + 2;
    const H3: u32 = HIDDEN_BASE + 3;

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
        assert_eq!(net.node_count(), HIDDEN_BASE as usize);
    }

    #[test]
    fn feed_forward_chain_resolves_within_one_activation() {
        // input 0 -> hidden H0 -> output OUT0, both weights 1.
        let net = Network::compile(&genome(&[H0], &[(1, 0, H0, 1.0), (2, H0, OUT0, 1.0)]));
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
        // input 0 -> hidden H0, and hidden H0 -> hidden H0 (recurrent).
        let net = Network::compile(&genome(
            &[H0],
            &[(1, 0, H0, 1.0), (2, H0, H0, 1.0), (3, H0, OUT0, 1.0)],
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
        // H0 <-> H1 form one cyclic component; 0 -> H0 is a normal edge.
        let net = Network::compile(&genome(
            &[H0, H1],
            &[
                (1, 0, H0, 1.0),
                (2, H0, H1, 1.0),
                (3, H1, H0, 1.0),
                (4, H1, OUT0, 1.0),
            ],
        ));
        let mut state = Activations::new(&net);
        let mut inputs = [0.0; N_INPUT as usize];
        inputs[0] = 1.0;
        let first = net.activate(&mut state, &inputs);
        assert_eq!(first[0], sigmoid(0.0));
        let second = net.activate(&mut state, &inputs);
        // H0 was sigmoid(1 + 0) on step one, so H1 now sees it.
        assert!((second[0] - sigmoid(sigmoid(sigmoid(1.0)))).abs() < 1e-15);
    }

    #[test]
    fn disabled_genes_are_absent_from_the_runtime() {
        let mut g = genome(&[H0], &[(1, 0, H0, 1.0), (2, H0, OUT0, 1.0)]);
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
        // A ten-node hidden chain into the first output, declared out of
        // topological order.
        let hidden: Vec<u32> = (HIDDEN_BASE..HIDDEN_BASE + 10).collect();
        let mut genes = vec![(1u32, HIDDEN_BASE + 9, OUT0, 1.0f64)];
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

    // ---------------------------------------------------------------------
    // Reference equivalence.
    //
    // `reference` below is a second, deliberately naive evaluator written
    // straight from the rules at the top of this module. It shares no code with
    // `Network`: components come from a transitive-reachability closure instead
    // of Tarjan, the condensation is ordered by repeated peeling instead of
    // relying on Tarjan's emission order, and each decision keeps explicit
    // current/previous maps keyed by node IDENTIFIER, copying the whole of
    // current into previous the way the kernel did before the slot-compiled
    // buffer replaced it. The compiled kernel has to agree with it BIT for bit,
    // because a single last-bit difference can flip a control and therefore a
    // whole fight.
    // ---------------------------------------------------------------------

    use std::collections::BTreeMap;

    fn reference(
        genome: &Genome,
        steps: &[[f64; N_INPUT as usize]],
    ) -> Vec<[f64; N_OUTPUT as usize]> {
        let present = |id: u32| genome.nodes.iter().any(|n| n.id == id);
        // Rule 1: disabled genes, and genes with an undeclared endpoint, are
        // not part of the graph at all.
        let links: Vec<&Gene> = genome
            .genes
            .iter()
            .filter(|g| g.enabled && present(g.from) && present(g.to))
            .collect();

        // Only nodes touched by a link can ever be anything but zero: a node
        // with no incoming link sums to zero and sigmoid(0) is zero, which is
        // what it already held. So the condensation only needs the endpoints.
        let mut active: Vec<u32> = Vec::new();
        for link in links.iter() {
            for end in [link.from, link.to] {
                if !active.contains(&end) {
                    active.push(end);
                }
            }
        }
        active.sort_unstable();
        let position = |id: u32| active.iter().position(|&a| a == id).unwrap();
        let n = active.len();

        // Reachability closure, the long way round.
        let mut reach = vec![vec![false; n]; n];
        for link in links.iter() {
            reach[position(link.from)][position(link.to)] = true;
        }
        for k in 0..n {
            for i in 0..n {
                for j in 0..n {
                    if reach[i][k] && reach[k][j] {
                        reach[i][j] = true;
                    }
                }
            }
        }

        // Rule 2: mutual reachability is the component relation.
        let mut component = vec![usize::MAX; n];
        let mut groups: Vec<Vec<u32>> = Vec::new();
        for i in 0..n {
            if component[i] != usize::MAX {
                continue;
            }
            let id = groups.len();
            let mut group = Vec::new();
            for j in 0..n {
                if component[j] == usize::MAX && (i == j || (reach[i][j] && reach[j][i])) {
                    component[j] = id;
                    group.push(active[j]);
                }
            }
            groups.push(group);
        }
        // Rule 3: a component is cyclic when it holds more than one node, or
        // one node that links to itself.
        let mut cyclic: Vec<bool> = groups.iter().map(|g| g.len() > 1).collect();
        for link in links.iter() {
            if link.from == link.to {
                cyclic[component[position(link.from)]] = true;
            }
        }

        // Peel the condensation: emit a component once nothing unemitted feeds
        // it. Rule 3 makes the answer independent of which valid order that is,
        // so the smallest remaining identifier is a fine tie-break.
        let mut emitted = vec![false; groups.len()];
        let mut order: Vec<u32> = Vec::new();
        for _ in 0..groups.len() {
            let mut choice: Option<usize> = None;
            for (c, group) in groups.iter().enumerate() {
                if emitted[c] {
                    continue;
                }
                let fed = links.iter().any(|l| {
                    let (from, to) = (component[position(l.from)], component[position(l.to)]);
                    to == c && from != c && !emitted[from]
                });
                if fed {
                    continue;
                }
                let better = match choice {
                    None => true,
                    Some(best) => group[0] < groups[best][0],
                };
                if better {
                    choice = Some(c);
                }
            }
            let c = choice.expect("the condensation is a DAG, so something is always ready");
            emitted[c] = true;
            for &id in groups[c].iter() {
                // Rule 5: inputs are driven, never computed.
                if NodeKind::of_id(id) != NodeKind::Input {
                    order.push(id);
                }
            }
        }

        let mut current: BTreeMap<u32, f64> = genome.nodes.iter().map(|n| (n.id, 0.0)).collect();
        let mut outputs = Vec::with_capacity(steps.len());
        for inputs in steps.iter() {
            let previous = current.clone();
            for (id, value) in inputs.iter().enumerate() {
                let id = id as u32;
                if present(id) {
                    current.insert(id, *value);
                }
            }
            for &id in order.iter() {
                let mut sum = 0.0;
                // Rule 4: ascending innovation order, and `genes` is sorted by
                // innovation, so this is the genome's own order.
                for link in links.iter().filter(|l| l.to == id) {
                    let same = component[position(link.from)] == component[position(link.to)];
                    let source = if same && cyclic[component[position(id)]] {
                        previous[&link.from]
                    } else {
                        current[&link.from]
                    };
                    sum += link.weight * source;
                }
                current.insert(id, sigmoid(sum));
            }
            let mut out = [0.0; N_OUTPUT as usize];
            for (k, slot) in out.iter_mut().enumerate() {
                let id = N_INPUT + k as u32;
                *slot = current.get(&id).copied().unwrap_or(0.0);
            }
            outputs.push(out);
        }
        outputs
    }

    fn assert_matches_reference(genome: &Genome, steps: &[[f64; N_INPUT as usize]], what: &str) {
        let expected = reference(genome, steps);
        let net = Network::compile(genome);
        let mut state = Activations::new(&net);
        for (step, inputs) in steps.iter().enumerate() {
            let got = net.activate(&mut state, inputs);
            for (k, (a, b)) in got.iter().zip(expected[step].iter()).enumerate() {
                assert_eq!(
                    a.to_bits(),
                    b.to_bits(),
                    "{what}: output {k} differs from the reference at step {step}: {a} vs {b}"
                );
            }
        }
        // Rule 7: a reset returns the episode to its opening state exactly.
        state.reset();
        let reopened = net.activate(&mut state, &steps[0]);
        for (k, (a, b)) in reopened.iter().zip(expected[0].iter()).enumerate() {
            assert_eq!(a.to_bits(), b.to_bits(), "{what}: output {k} differs after a reset");
        }
    }

    /// Deterministic so a failure is always the same failure.
    struct Lcg(u64);

    impl Lcg {
        fn next(&mut self) -> u64 {
            self.0 = self
                .0
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            self.0 >> 33
        }

        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }

        fn weight(&mut self) -> f64 {
            self.below(4001) as f64 / 1000.0 - 2.0
        }
    }

    fn input_steps(rng: &mut Lcg, count: usize) -> Vec<[f64; N_INPUT as usize]> {
        (0..count)
            .map(|_| {
                let mut inputs = [0.0; N_INPUT as usize];
                for slot in inputs.iter_mut() {
                    *slot = rng.below(2001) as f64 / 1000.0 - 1.0;
                }
                inputs[(N_INPUT - 1) as usize] = 1.0;
                inputs
            })
            .collect()
    }

    #[test]
    fn hand_built_graphs_match_the_reference_evaluator() {
        let mut rng = Lcg(0x5eed);
        let steps = input_steps(&mut rng, 6);
        let cases: Vec<(&str, Genome)> = vec![
            ("no genes at all", Genome::minimal()),
            (
                "feed-forward chain",
                genome(&[H0], &[(1, 0, H0, 0.7), (2, H0, OUT0, -1.3)]),
            ),
            (
                "self-loop",
                genome(
                    &[H0],
                    &[(1, 0, H0, 0.9), (2, H0, H0, 0.6), (3, H0, OUT0, 1.1)],
                ),
            ),
            (
                "two-cycle with an entry and an exit",
                genome(
                    &[H0, H1],
                    &[
                        (1, 0, H0, 1.2),
                        (2, H0, H1, -0.4),
                        (3, H1, H0, 0.8),
                        (4, H1, OUT0, 1.0),
                    ],
                ),
            ),
            (
                "three-cycle behind a feed-forward front",
                genome(
                    &[H0, H1, H2, H3],
                    &[
                        (1, 0, H3, 0.5),
                        (2, H3, H0, 1.4),
                        (3, H0, H1, 0.3),
                        (4, H1, H2, -0.9),
                        (5, H2, H0, 0.7),
                        (6, H2, OUT0, 1.0),
                        (7, 1, OUT1, -0.6),
                    ],
                ),
            ),
            (
                "an output feeding a hidden node back",
                genome(
                    &[H0],
                    &[
                        (1, 0, OUT0, 0.8),
                        (2, OUT0, H0, 1.1),
                        (3, H0, OUT0, -0.5),
                        (4, BIAS, H0, 0.2),
                    ],
                ),
            ),
            (
                "output straight to output",
                genome(
                    &[],
                    &[
                        (1, 2, OUT0, 1.7),
                        (2, OUT0, OUT1, -1.2),
                        (3, OUT1, OUT0, 0.4),
                    ],
                ),
            ),
        ];
        for (what, g) in cases {
            assert_matches_reference(&g, &steps, what);
        }

        // Rule 1: the disabled variants of the same graphs, including one that
        // disables an edge inside a cycle and so breaks the recurrence.
        let mut disabled = genome(
            &[H0, H1],
            &[
                (1, 0, H0, 1.2),
                (2, H0, H1, -0.4),
                (3, H1, H0, 0.8),
                (4, H1, OUT0, 1.0),
            ],
        );
        disabled.genes[2].enabled = false;
        assert_matches_reference(&disabled, &steps, "cycle broken by a disabled gene");
        disabled.genes[0].enabled = false;
        assert_matches_reference(&disabled, &steps, "two disabled genes");
    }

    #[test]
    fn partial_node_sets_match_the_reference_evaluator() {
        let mut rng = Lcg(0xfa11);
        let steps = input_steps(&mut rng, 5);
        // A genome that declares only some inputs and some outputs, so the
        // input vector no longer lands on every input slot and several outputs
        // are undeclared.
        let ids: [u32; 6] = [0, 3, BIAS, OUT1, OUT_LAST, H0];
        let nodes: Vec<Node> = ids
            .iter()
            .map(|&id| Node {
                id,
                kind: NodeKind::of_id(id),
            })
            .collect();
        let genes = [
            (1u32, 0u32, H0, 0.9f64),
            (2, H0, H0, 0.5),
            (3, BIAS, OUT1, -1.1),
            (4, H0, OUT_LAST, 0.3),
            (5, OUT_LAST, H0, 0.6),
            (6, 3, OUT1, 1.4),
        ];
        let g = Genome {
            nodes,
            genes: genes
                .iter()
                .map(|&(innovation, from, to, weight)| Gene {
                    innovation,
                    from,
                    to,
                    weight,
                    enabled: true,
                })
                .collect(),
        }
        .validate()
        .unwrap();
        assert_matches_reference(&g, &steps, "partial node set");
    }

    #[test]
    fn random_graphs_match_the_reference_evaluator_bit_for_bit() {
        let mut rng = Lcg(0xc0ffee);
        for case in 0..200u32 {
            // Half the cases declare every input, which is what an evolved
            // genome looks like; the other half declare a sparse subset.
            let full = case % 2 == 0;
            let mut nodes: Vec<Node> = if full {
                Genome::minimal().nodes
            } else {
                [0u32, 1, 2, BIAS, OUT0, OUT1, OUT_LAST]
                    .iter()
                    .filter(|_| rng.below(4) != 0)
                    .map(|&id| Node {
                        id,
                        kind: NodeKind::of_id(id),
                    })
                    .collect()
            };
            let hidden: Vec<u32> = (HIDDEN_BASE..HIDDEN_BASE + rng.below(5) as u32).collect();
            for &id in hidden.iter() {
                nodes.push(Node {
                    id,
                    kind: NodeKind::Hidden,
                });
            }
            nodes.sort_by_key(|n| n.id);
            if nodes.is_empty() {
                continue;
            }

            let ids: Vec<u32> = nodes.iter().map(|n| n.id).collect();
            let sinks: Vec<u32> = ids
                .iter()
                .copied()
                .filter(|&id| NodeKind::of_id(id) != NodeKind::Input)
                .collect();
            if sinks.is_empty() {
                continue;
            }
            let mut genes: Vec<Gene> = Vec::new();
            let mut seen: Vec<(u32, u32)> = Vec::new();
            for _ in 0..rng.below(14) {
                let from = ids[rng.below(ids.len() as u64) as usize];
                let to = sinks[rng.below(sinks.len() as u64) as usize];
                if seen.contains(&(from, to)) {
                    continue;
                }
                seen.push((from, to));
                genes.push(Gene {
                    innovation: genes.len() as u32 + 1,
                    from,
                    to,
                    weight: rng.weight(),
                    // Rule 1: disabled genes have to drop out of the ordering
                    // as well as out of the sums.
                    enabled: rng.below(5) != 0,
                });
            }
            let g = Genome { nodes, genes }.validate().unwrap();
            let steps = input_steps(&mut rng, 4);
            assert_matches_reference(&g, &steps, &format!("random case {case}"));
        }
    }

    #[test]
    fn only_the_sources_a_recurrent_edge_reads_are_carried_between_decisions() {
        // The carry-over is the compiled recurrence, not a copy of the whole
        // graph: a feed-forward genome carries nothing, and a cycle carries one
        // slot per distinct recurrent SOURCE however many edges read it.
        let forward = Network::compile(&genome(&[H0], &[(1, 0, H0, 1.0), (2, H0, OUT0, 1.0)]));
        assert_eq!(forward.recurrent_sources.len(), 0);
        assert_eq!(Activations::new(&forward).values.len(), forward.width);

        let cyclic = Network::compile(&genome(
            &[H0, H1],
            &[
                (1, 0, H0, 1.0),
                (2, H0, H1, 1.0),
                (3, H1, H0, 1.0),
                // A second reader of the same recurrent source.
                (4, H1, H1, 1.0),
                (5, H1, OUT0, 1.0),
            ],
        ));
        // H0 and H1 are each read from the previous decision; H1 by two edges.
        assert_eq!(cyclic.recurrent_sources.len(), 2);
        assert_eq!(
            Activations::new(&cyclic).values.len(),
            cyclic.width + 2,
            "the shadow half is one slot per recurrent source"
        );
    }
}
