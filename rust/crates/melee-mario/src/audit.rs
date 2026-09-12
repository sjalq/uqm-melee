//! The arithmetic a held-out round is judged by, and the two rounds it takes.
//!
//! Two rules run through everything that uses this module:
//!
//!   * A round is opened against ONE frozen candidate (its genome fingerprint)
//!     and played to the end unless the result is already settled downward, so
//!     the Wilson bound below is never inflated by stopping when the numbers
//!     happen to look good.
//!   * Passing the audit panel is not a pass: a disjoint confirmation panel,
//!     drawn from its own seed partition, must clear the same bound as well.

/// Two-sided 95% normal quantile; the resulting one-sided bound is the number
/// the dashboard shows next to the target.
pub const Z: f64 = 1.959_963_984_540_054;

/// Wilson score interval, lower end. `None` when there is no evidence at all.
pub fn wilson_lower(wins: u32, games: u32) -> Option<f64> {
    if games == 0 {
        return None;
    }
    let n = games as f64;
    let p = wins as f64 / n;
    let z2 = Z * Z;
    let denominator = 1.0 + z2 / n;
    let center = p + z2 / (2.0 * n);
    let margin = Z * (p * (1.0 - p) / n + z2 / (4.0 * n * n)).sqrt();
    Some(((center - margin) / denominator).clamp(0.0, 1.0))
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub struct Tally {
    pub wins: u32,
    pub games: u32,
}

impl Tally {
    pub fn rate(self) -> Option<f64> {
        (self.games > 0).then(|| self.wins as f64 / self.games as f64)
    }

    pub fn lower_bound(self) -> Option<f64> {
        wilson_lower(self.wins, self.games)
    }
}

/// Which half of the gate a held-out round is. The two halves draw from
/// different [`crate::rng::StreamTag`] partitions, which is what makes the
/// confirmation genuinely disjoint evidence rather than a replay of the audit.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Round {
    /// The gate's first balanced panel.
    Audit,
    /// The disjoint panel that must also pass before the gate is cleared.
    Confirm,
}

impl Round {
    pub fn as_str(self) -> &'static str {
        match self {
            Round::Audit => "audit",
            Round::Confirm => "confirm",
        }
    }

    pub fn parse(raw: &str) -> Option<Round> {
        match raw {
            "audit" => Some(Round::Audit),
            "confirm" => Some(Round::Confirm),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wilson_needs_a_real_panel_before_it_can_clear_the_target() {
        assert_eq!(wilson_lower(0, 0), None);
        // A pooled-looking rate of 1.0 on one game proves nothing.
        assert!(wilson_lower(1, 1).unwrap() < 0.30);
        // Sixteen is the smallest perfect panel that clears the target at all.
        assert!(wilson_lower(15, 15).unwrap() < 0.80);
        assert!(wilson_lower(16, 16).unwrap() > 0.80);
        // Monotone in wins, and always below the observed rate.
        for games in 1..60u32 {
            for wins in 0..=games {
                let bound = wilson_lower(wins, games).unwrap();
                assert!((0.0..=1.0).contains(&bound));
                assert!(bound <= wins as f64 / games as f64 + 1e-12);
            }
        }
    }

    #[test]
    fn the_bound_demands_much_more_than_an_eighty_percent_observed_rate() {
        // An observed 80% never clears the bound at any practical panel size,
        // which is the whole cost of refusing lucky passes.
        for panel in [32u32, 64, 100, 400, 1000] {
            assert!(wilson_lower(panel * 8 / 10, panel).unwrap() <= 0.80);
        }
        // On a panel of sixty-four the margin is narrow: fifty-eight of
        // sixty-four clears the target and fifty-seven does not.
        assert!(wilson_lower(58, 64).unwrap() > 0.80);
        assert!(wilson_lower(57, 64).unwrap() <= 0.80);
    }

    #[test]
    fn a_round_name_round_trips_and_refuses_anything_else() {
        for round in [Round::Audit, Round::Confirm] {
            assert_eq!(Round::parse(round.as_str()), Some(round));
        }
        for bad in ["regression", "ready", "training", ""] {
            assert_eq!(Round::parse(bad), None);
        }
    }
}
