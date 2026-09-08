use melee_sim::input::{BattleInput, Turn};

pub const N_OBS: usize = 43;
pub const N_FEEDBACK: usize = 13;
pub const N_IN: usize = 57;
pub const N_HIDDEN: usize = 16;
pub const N_OUT: usize = 13;
pub const N_WEIGHTS: usize = N_HIDDEN * N_IN + N_OUT * (N_HIDDEN + 1);

pub struct Net {
    weights: [f64; N_WEIGHTS],
}
pub struct Step {
    pub input: BattleInput,
    pub extra: [f64; 8],
}

impl Net {
    pub fn load(weights: &[f64]) -> Result<Self, String> {
        if weights.len() != N_WEIGHTS {
            return Err(format!("weight length {} != {}", weights.len(), N_WEIGHTS));
        }
        if !weights.iter().all(|x| x.is_finite()) {
            return Err("non-finite weights".into());
        }
        let mut w = [0.0; N_WEIGHTS];
        w.copy_from_slice(weights);
        Ok(Self { weights: w })
    }
    pub fn step(&self, obs: &[f64; N_OBS], previous: BattleInput, extra: &[f64; 8]) -> Step {
        let mut inputs = [0.0; N_IN];
        inputs[..N_OBS].copy_from_slice(obs);
        inputs[N_OBS..N_OBS + 5].copy_from_slice(&actions(previous));
        inputs[N_OBS + 5..N_IN - 1].copy_from_slice(extra);
        inputs[N_IN - 1] = 1.0;
        let mut hidden = [0.0; N_HIDDEN + 1];
        for (h, value) in hidden[..N_HIDDEN].iter_mut().enumerate() {
            let mut sum = 0.0;
            for i in 0..N_IN {
                sum += self.weights[h * N_IN + i] * inputs[i];
            }
            *value = tanh(sum);
        }
        hidden[N_HIDDEN] = 1.0;
        let mut outs = [0.0; N_OUT];
        for (o, value) in outs.iter_mut().enumerate() {
            let start = N_HIDDEN * N_IN + o * (N_HIDDEN + 1);
            for i in 0..=N_HIDDEN {
                *value += self.weights[start + i] * hidden[i];
            }
        }
        let input = BattleInput {
            turn: if outs[0] > 0.0 {
                Turn::TurnLeft
            } else if outs[1] > 0.0 {
                Turn::TurnRight
            } else {
                Turn::NoTurn
            },
            thrust: outs[2] > 0.0,
            weapon: outs[3] > 0.0,
            special: outs[4] > 0.0,
        };
        let mut next = [0.0; 8];
        for i in 0..8 {
            next[i] = tanh(outs[i + 5]);
        }
        Step { input, extra: next }
    }
}

pub fn actions(input: BattleInput) -> [f64; 5] {
    [
        (input.turn == Turn::TurnLeft) as u8 as f64,
        (input.turn == Turn::TurnRight) as u8 as f64,
        input.thrust as u8 as f64,
        input.weapon as u8 as f64,
        input.special as u8 as f64,
    ]
}

fn tanh(x: f64) -> f64 {
    if x >= 20.0 {
        1.0
    } else if x <= -20.0 {
        -1.0
    } else {
        let a = (2.0 * x).exp();
        (a - 1.0) / (a + 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::tanh;

    #[test]
    fn tanh_preserves_saturation_and_finite_values() {
        assert_eq!(tanh(f64::NEG_INFINITY), -1.0);
        assert_eq!(tanh(-20.0), -1.0);
        assert_eq!(tanh(0.0), 0.0);
        assert_eq!(tanh(20.0), 1.0);
        assert_eq!(tanh(f64::INFINITY), 1.0);

        for x in [-19.0_f64, -1.0, -0.125, -1e-12, 1e-12, 0.125, 1.0, 19.0] {
            assert!((tanh(x) - x.tanh()).abs() <= 1e-15);
        }
        assert!(tanh(f64::NAN).is_nan());
    }
}
