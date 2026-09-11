//! Binding between the 57 network inputs, the 13 network outputs and the
//! simulation's controls. This layout is part of the cross-language contract.
//!
//! INPUTS, in order:
//!   `0..=42`  the 43 observations from `melee_neat::encode::vector`, which
//!             are 33 sensors (the last of which is the constant 1.0), then
//!             our hull as 5 bits low bit first, then theirs as 5 bits.
//!   `43..=47` the five ACTUAL controls the seat used on the previous tick:
//!             turn-left, turn-right, thrust, weapon, special.
//!   `48..=55` the eight memory channels this policy emitted last tick.
//!   `56`      bias, always 1.0.
//!
//! OUTPUTS, in order:
//!   `0..=4`   controls; a value strictly greater than zero asserts the
//!             control. Left and right both asserted cancel to NO turn.
//!   `5..=12`  the eight memory channels for the next tick, already bounded to
//!             (-1, 1) by the activation function.

use crate::genome::{Genome, N_CONTROL, N_INPUT, N_MEMORY, N_OBS};
use crate::graph::{Activations, Network};
use melee_neat::eval::Controller;
use melee_sim::input::{BattleInput, Turn};
use melee_core::units::Side;

pub const CONTROL_BASE: usize = N_OBS;
pub const MEMORY_BASE: usize = N_OBS + N_CONTROL;
pub const BIAS_SLOT: usize = N_OBS + N_CONTROL + N_MEMORY;

/// The five control bits as the network sees them on the next tick.
pub fn control_bits(input: BattleInput) -> [f64; N_CONTROL] {
    [
        (input.turn == Turn::TurnLeft) as u8 as f64,
        (input.turn == Turn::TurnRight) as u8 as f64,
        input.thrust as u8 as f64,
        input.weapon as u8 as f64,
        input.special as u8 as f64,
    ]
}

/// Output activations to controls. Asserting both turns cancels to no turn,
/// which differs deliberately from the human key layout where left wins.
pub fn controls_of(outputs: &[f64; 13]) -> BattleInput {
    let left = outputs[0] > 0.0;
    let right = outputs[1] > 0.0;
    BattleInput {
        turn: match (left, right) {
            (true, false) => Turn::TurnLeft,
            (false, true) => Turn::TurnRight,
            _ => Turn::NoTurn,
        },
        thrust: outputs[2] > 0.0,
        weapon: outputs[3] > 0.0,
        special: outputs[4] > 0.0,
    }
}

pub fn memory_of(outputs: &[f64; 13]) -> [f64; N_MEMORY] {
    let mut memory = [0.0; N_MEMORY];
    memory.copy_from_slice(&outputs[N_CONTROL..]);
    memory
}

/// Assembles the full input vector. Callers that already hold prior controls
/// and memory explicitly (the oracle, cross-language checks) use this directly.
pub fn assemble(
    observation: &[f64; N_OBS],
    previous: &[f64; N_CONTROL],
    memory: &[f64; N_MEMORY],
) -> [f64; N_INPUT as usize] {
    let mut inputs = [0.0; N_INPUT as usize];
    inputs[..N_OBS].copy_from_slice(observation);
    inputs[CONTROL_BASE..MEMORY_BASE].copy_from_slice(previous);
    inputs[MEMORY_BASE..BIAS_SLOT].copy_from_slice(memory);
    inputs[BIAS_SLOT] = 1.0;
    inputs
}

/// A compiled policy plus the state of one seat. Recurrent graph activations
/// and the eight explicit memory channels are distinct: the first belongs to
/// the graph, the second is fed back through inputs `48..=55`.
pub struct Brain {
    pub network: Network,
    state: Activations,
    memory: [f64; N_MEMORY],
    ship: &'static str,
}

impl Brain {
    pub fn compile(genome: &Genome) -> Brain {
        let network = Network::compile(genome);
        let state = Activations::new(&network);
        Brain {
            network,
            state,
            memory: [0.0; N_MEMORY],
            ship: "",
        }
    }

    /// Everything a new episode, round or hull must forget.
    pub fn reset(&mut self) {
        self.state.reset();
        self.memory = [0.0; N_MEMORY];
        self.ship = "";
    }

    pub fn step(
        &mut self,
        observation: &[f64; N_OBS],
        previous: &[f64; N_CONTROL],
    ) -> [f64; 13] {
        let inputs = assemble(observation, previous, &self.memory);
        let outputs = self.network.activate(&mut self.state, &inputs);
        self.memory = memory_of(&outputs);
        outputs
    }
}

/// Drives exactly one seat; the other seat is an Awesome cyborg or a frozen
/// opponent brain, never this one.
pub struct SeatPilot {
    pub seat: Side,
    pub brain: Brain,
}

impl SeatPilot {
    pub fn new(seat: Side, genome: &Genome) -> SeatPilot {
        SeatPilot {
            seat,
            brain: Brain::compile(genome),
        }
    }
}

impl Controller for SeatPilot {
    /// Evaluating the seat this policy does not pilot cannot influence the
    /// simulation, so the genome path skips that discarded work.
    fn evaluates_idle_seat(&self) -> bool {
        false
    }

    fn decide(
        &mut self,
        _side: Side,
        ship: &'static str,
        observation: &[f64; N_OBS],
        previous: BattleInput,
    ) -> BattleInput {
        if self.brain.ship != ship {
            self.brain.reset();
            self.brain.ship = ship;
        }
        let outputs = self.brain.step(observation, &control_bits(previous));
        controls_of(&outputs)
    }
}

/// Drives both seats from two independent brains: ours and a frozen opponent
/// snapshot. Each seat keeps its own graph state and memory.
pub struct DuelPilot {
    pub ours: Brain,
    pub theirs: Brain,
    pub our_seat: Side,
}

impl DuelPilot {
    pub fn new(our_seat: Side, ours: &Genome, theirs: &Genome) -> DuelPilot {
        DuelPilot {
            ours: Brain::compile(ours),
            theirs: Brain::compile(theirs),
            our_seat,
        }
    }
}

impl Controller for DuelPilot {
    fn decide(
        &mut self,
        side: Side,
        ship: &'static str,
        observation: &[f64; N_OBS],
        previous: BattleInput,
    ) -> BattleInput {
        let brain = if side == self.our_seat {
            &mut self.ours
        } else {
            &mut self.theirs
        };
        if brain.ship != ship {
            brain.reset();
            brain.ship = ship;
        }
        controls_of(&brain.step(observation, &control_bits(previous)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_turns_asserted_cancel_to_no_turn() {
        let mut outputs = [0.0; 13];
        outputs[0] = 0.5;
        outputs[1] = 0.5;
        assert_eq!(controls_of(&outputs).turn, Turn::NoTurn);
        outputs[1] = -0.5;
        assert_eq!(controls_of(&outputs).turn, Turn::TurnLeft);
        outputs[0] = -0.5;
        outputs[1] = 0.5;
        assert_eq!(controls_of(&outputs).turn, Turn::TurnRight);
        // Exactly zero is not "greater than zero".
        assert_eq!(controls_of(&[0.0; 13]).turn, Turn::NoTurn);
        assert!(!controls_of(&[0.0; 13]).thrust);
    }

    #[test]
    fn control_bits_round_trip_through_the_input_vector() {
        let input = BattleInput {
            turn: Turn::TurnRight,
            thrust: true,
            weapon: false,
            special: true,
        };
        let bits = control_bits(input);
        assert_eq!(bits, [0.0, 1.0, 1.0, 0.0, 1.0]);
        let inputs = assemble(&[0.25; N_OBS], &bits, &[-0.5; N_MEMORY]);
        assert_eq!(inputs[N_OBS - 1], 0.25);
        assert_eq!(&inputs[CONTROL_BASE..MEMORY_BASE], &bits);
        assert_eq!(inputs[MEMORY_BASE], -0.5);
        assert_eq!(inputs[BIAS_SLOT], 1.0);
        assert_eq!(BIAS_SLOT, 56);
    }

    #[test]
    fn memory_feeds_back_into_the_next_step() {
        use crate::genome::{Gene, Node, NodeKind};
        // memory channel 0 (output 62) is driven by the bias, and output 57
        // reads memory input slot 48 back.
        let mut g = Genome::minimal();
        g.genes = vec![
            Gene {
                innovation: 1,
                from: 56,
                to: 62,
                weight: 1.0,
                enabled: true,
            },
            Gene {
                innovation: 2,
                from: 48,
                to: 57,
                weight: 1.0,
                enabled: true,
            },
        ];
        let _ = Node {
            id: 70,
            kind: NodeKind::Hidden,
        };
        let genome = g.validate().unwrap();
        let mut brain = Brain::compile(&genome);
        let first = brain.step(&[0.0; N_OBS], &[0.0; N_CONTROL]);
        assert_eq!(first[0], 0.0);
        assert!(first[5] > 0.0);
        let second = brain.step(&[0.0; N_OBS], &[0.0; N_CONTROL]);
        assert!((second[0] - crate::graph::sigmoid(first[5])).abs() < 1e-15);
        brain.reset();
        assert_eq!(brain.step(&[0.0; N_OBS], &[0.0; N_CONTROL])[0], 0.0);
    }
}
