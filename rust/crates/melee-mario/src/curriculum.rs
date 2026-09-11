//! Frozen roster expansion order and the ordered matchup cells of a stage.
//!
//! Both expansion orders are fixed for the life of the project so that a stage
//! number always means the same set of fights, in every run and after every
//! resume. Ours starts at Pkunk, theirs at Umgah, and the rest follow catalog
//! order with the already-placed hull skipped.
//!
//! Stage 0 is the single ordered pair Pkunk against Umgah. Each step adds one
//! hull, the opponent side first, then ours, alternating to the full 25 by 25
//! board at stage 48.

use melee_sim::catalog::{ShipKind, ALL_SHIPS, MELEE_SHIP_COUNT};
use serde_json::{json, Value};

pub const STAGES: usize = 2 * MELEE_SHIP_COUNT - 1;
pub const FINAL_STAGE: usize = STAGES - 1;

fn expansion(first: ShipKind) -> [ShipKind; MELEE_SHIP_COUNT] {
    let mut order = [first; MELEE_SHIP_COUNT];
    let mut at = 1;
    let mut i = 0;
    while i < MELEE_SHIP_COUNT {
        let kind = ALL_SHIPS[i];
        if kind as u8 != first as u8 {
            order[at] = kind;
            at += 1;
        }
        i += 1;
    }
    order
}

/// Our hulls, in the order the curriculum unlocks them.
pub fn ours() -> [ShipKind; MELEE_SHIP_COUNT] {
    expansion(ShipKind::Pkunk)
}

/// Their hulls, in the order the curriculum unlocks them.
pub fn theirs() -> [ShipKind; MELEE_SHIP_COUNT] {
    expansion(ShipKind::Umgah)
}

/// How many hulls each side has at a stage, as `(ours, theirs)`. Moving from
/// stage `s` to `s + 1` widens THEIR roster when `s` is even and OURS when `s`
/// is odd, which is what "add opponent, then add ours, repeat" means:
/// `(1,1) -> (1,2) -> (2,2) -> (2,3) -> (3,3)`.
///
/// Panics above [`FINAL_STAGE`]; callers decode a stage through
/// [`valid_stage`] before it ever reaches here.
pub fn counts(stage: usize) -> (usize, usize) {
    assert!(stage <= FINAL_STAGE, "stage {stage} is outside the curriculum");
    (1 + stage / 2, 1 + (stage + 1) / 2)
}

/// Accepts only stages the curriculum actually defines. Used when decoding a
/// checkpoint so a corrupt or foreign file cannot resume a nonexistent board.
pub fn valid_stage(raw: u64) -> Option<usize> {
    (raw < STAGES as u64).then_some(raw as usize)
}

/// The side whose roster the next promotion widens, and the hull it adds.
pub fn next_addition(stage: usize) -> (&'static str, Option<ShipKind>) {
    if stage >= FINAL_STAGE {
        return ("model", None);
    }
    let (mine, yours) = counts(stage + 1);
    if stage % 2 == 0 {
        ("opponent", Some(theirs()[yours - 1]))
    } else {
        ("ours", Some(ours()[mine - 1]))
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub enum Opponent {
    /// The original Awesome cyborg, which is what the curriculum is graded on.
    Cyborg,
    /// A frozen champion snapshot. Never gates a stage.
    Model,
}

impl Opponent {
    pub fn as_str(self) -> &'static str {
        match self {
            Opponent::Cyborg => "cyborg",
            Opponent::Model => "model",
        }
    }

    pub fn parse(raw: &str) -> Option<Opponent> {
        match raw {
            "cyborg" => Some(Opponent::Cyborg),
            "model" => Some(Opponent::Model),
            _ => None,
        }
    }
}

/// One ordered matchup. `us` and `them` index the expansion orders above, so a
/// cell keeps its identity as the rosters grow.
#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub struct Cell {
    pub foe: Opponent,
    pub us: u8,
    pub them: u8,
}

impl Cell {
    pub fn our_ship(self) -> ShipKind {
        ours()[self.us as usize]
    }

    pub fn their_ship(self) -> ShipKind {
        theirs()[self.them as usize]
    }

    /// Stable identity used to derive episode seeds.
    pub fn key(self) -> u64 {
        (self.foe as u64) * 1_000_000 + self.us as u64 * 100 + self.them as u64
    }

    pub fn to_json(self) -> Value {
        json!({"us": self.our_ship().name(), "them": self.their_ship().name(),
               "opponent_type": self.foe.as_str()})
    }

    pub fn encode(self) -> Value {
        json!([self.foe.as_str(), self.us, self.them])
    }

    /// Strict inverse of [`Cell::encode`]. The shape must be exactly a triple
    /// and both indices must name a hull that exists, so a malformed or
    /// foreign checkpoint is rejected instead of narrowing into a wrong
    /// matchup or panicking later on a roster lookup.
    pub fn decode(value: &Value) -> Option<Cell> {
        let triple = value.as_array()?;
        if triple.len() != 3 {
            return None;
        }
        let index = |at: usize| -> Option<u8> {
            let raw = triple.get(at)?.as_u64()?;
            (raw < MELEE_SHIP_COUNT as u64).then_some(raw as u8)
        };
        Some(Cell {
            foe: Opponent::parse(triple.first()?.as_str()?)?,
            us: index(1)?,
            them: index(2)?,
        })
    }
}

/// Every ordered cyborg matchup active at a stage, in a fixed order.
pub fn cells(stage: usize) -> Vec<Cell> {
    let (mine, yours) = counts(stage);
    let mut out = Vec::with_capacity(mine * yours);
    for us in 0..mine as u8 {
        for them in 0..yours as u8 {
            out.push(Cell {
                foe: Opponent::Cyborg,
                us,
                them,
            });
        }
    }
    out
}

/// The frozen-model mirror of the full board, added once the cyborg ladder is
/// mastered. These are never part of a mastery gate.
pub fn model_cells() -> Vec<Cell> {
    let mut out = Vec::with_capacity(MELEE_SHIP_COUNT * MELEE_SHIP_COUNT);
    for us in 0..MELEE_SHIP_COUNT as u8 {
        for them in 0..MELEE_SHIP_COUNT as u8 {
            out.push(Cell {
                foe: Opponent::Model,
                us,
                them,
            });
        }
    }
    out
}

pub fn roster_names(order: &[ShipKind; MELEE_SHIP_COUNT], count: usize) -> Vec<&'static str> {
    order[..count].iter().map(|k| k.name()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    #[test]
    fn expansion_orders_are_unique_permutations_with_the_declared_heads() {
        for order in [ours(), theirs()] {
            let unique: BTreeSet<u8> = order.iter().map(|k| *k as u8).collect();
            assert_eq!(unique.len(), MELEE_SHIP_COUNT);
        }
        assert_eq!(ours()[0], ShipKind::Pkunk);
        assert_eq!(theirs()[0], ShipKind::Umgah);
        assert_eq!(ours()[1], ShipKind::Androsynth);
        assert_eq!(theirs()[1], ShipKind::Androsynth);
    }

    #[test]
    fn stage_zero_is_one_fight_and_the_last_stage_is_the_full_board() {
        assert_eq!(counts(0), (1, 1));
        assert_eq!(cells(0).len(), 1);
        assert_eq!(cells(0)[0].our_ship(), ShipKind::Pkunk);
        assert_eq!(cells(0)[0].their_ship(), ShipKind::Umgah);
        assert_eq!(counts(1), (1, 2));
        assert_eq!(counts(2), (2, 2));
        assert_eq!(counts(FINAL_STAGE), (25, 25));
        assert_eq!(cells(FINAL_STAGE).len(), 625);
        assert_eq!(FINAL_STAGE, 48);
    }

    #[test]
    fn every_stage_grows_by_exactly_one_hull_on_the_declared_side() {
        for stage in 0..FINAL_STAGE {
            let (mine, yours) = counts(stage);
            let (next_mine, next_yours) = counts(stage + 1);
            let (side, added) = next_addition(stage);
            if stage % 2 == 0 {
                assert_eq!((next_mine, next_yours), (mine, yours + 1));
                assert_eq!(side, "opponent");
                assert_eq!(added, Some(theirs()[next_yours - 1]));
            } else {
                assert_eq!((next_mine, next_yours), (mine + 1, yours));
                assert_eq!(side, "ours");
                assert_eq!(added, Some(ours()[next_mine - 1]));
            }
        }
        assert_eq!(next_addition(FINAL_STAGE), ("model", None));
    }

    #[test]
    fn cells_only_ever_grow_so_evidence_keeps_its_identity() {
        for stage in 0..FINAL_STAGE {
            let before: BTreeSet<Cell> = cells(stage).into_iter().collect();
            let after: BTreeSet<Cell> = cells(stage + 1).into_iter().collect();
            assert!(before.is_subset(&after), "stage {stage} dropped a cell");
            assert!(after.len() > before.len());
        }
    }

    #[test]
    fn decoding_rejects_shapes_that_could_resume_the_wrong_matchup() {
        assert_eq!(Cell::decode(&json!(["cyborg", 0, 0])), Some(cells(0)[0]));
        // Out of range, so `ours()[index]` can never be reached with it.
        assert_eq!(Cell::decode(&json!(["cyborg", 25, 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", 0, 25])), None);
        // 256 must not wrap to hull zero.
        assert_eq!(Cell::decode(&json!(["cyborg", 256, 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", -1, 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", 0])), None);
        assert_eq!(Cell::decode(&json!(["cyborg", 0, 0, 0])), None);
        assert_eq!(Cell::decode(&json!(["human", 0, 0])), None);
        assert_eq!(Cell::decode(&json!({"us": 0})), None);
    }

    #[test]
    fn stage_decoding_rejects_stages_outside_the_curriculum() {
        assert_eq!(valid_stage(0), Some(0));
        assert_eq!(valid_stage(FINAL_STAGE as u64), Some(FINAL_STAGE));
        assert_eq!(valid_stage(STAGES as u64), None);
        assert_eq!(valid_stage(u64::MAX), None);
    }

    #[test]
    fn cell_keys_and_encodings_are_injective() {
        let mut keys = BTreeSet::new();
        for cell in cells(FINAL_STAGE).into_iter().chain(model_cells()) {
            assert!(keys.insert(cell.key()), "key collision at {cell:?}");
            assert_eq!(Cell::decode(&cell.encode()), Some(cell));
        }
        assert_eq!(keys.len(), 1250);
    }
}
