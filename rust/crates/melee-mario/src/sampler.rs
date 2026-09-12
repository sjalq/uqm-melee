//! Decayed training evidence, and the identity of one generation's panel.
//!
//! One panel is drawn per generation and EVERY member is scored on that exact
//! panel, so the generation's numbers are mutually comparable. [`Panel`] is
//! what stamps that comparability: two fitness numbers may be read against each
//! other only when they were measured under the same panel id.
//!
//! [`SamplerStats`] is the memory the adaptive half of a panel is drawn from.
//! It is SAMPLING state, never gate evidence: the dashboard reports the
//! champion's held-out balanced rounds separately. Which cells a panel actually
//! contains is decided in [`crate::broad`].

use crate::broad::Cell;
use crate::episode::Task;
use serde_json::{json, Value};
use std::collections::BTreeMap;

/// Decayed training evidence for one cell.
#[derive(Copy, Clone, PartialEq, Debug, Default)]
pub struct CellStat {
    pub wins: f64,
    pub games: f64,
}

impl CellStat {
    /// Laplace-smoothed win rate, so a cell with no evidence reads as a coin
    /// flip rather than as a certainty in either direction.
    pub fn smoothed(&self) -> f64 {
        (self.wins + 1.0) / (self.games + 2.0)
    }
}

#[derive(Clone, Debug, Default)]
pub struct SamplerStats {
    pub cells: BTreeMap<Cell, CellStat>,
    /// Monotonic episode counter; feeds the seed namespace so no training seed
    /// is ever reused, across resumes included.
    pub issued: u64,
}

impl SamplerStats {
    pub fn record(&mut self, cell: Cell, won: bool, decay: f64) {
        let stat = self.cells.entry(cell).or_default();
        stat.wins = stat.wins * decay + won as u8 as f64;
        stat.games = stat.games * decay + 1.0;
    }

    pub fn to_json(&self) -> Value {
        let cells: Vec<Value> = self
            .cells
            .iter()
            .map(|(cell, stat)| json!([cell.encode(), stat.wins, stat.games]))
            .collect();
        json!({"cells": cells, "issued": self.issued})
    }

    pub fn from_json(value: &Value) -> Option<SamplerStats> {
        let mut cells = BTreeMap::new();
        for raw in value.get("cells")?.as_array()? {
            let row = raw.as_array()?;
            if row.len() != 3 {
                return None;
            }
            let wins = row.get(1)?.as_f64().filter(|n| n.is_finite() && *n >= 0.0)?;
            let games = row.get(2)?.as_f64().filter(|n| n.is_finite() && *n >= 0.0)?;
            if wins > games + 1e-9 {
                return None;
            }
            cells.insert(Cell::decode(row.first()?)?, CellStat { wins, games });
        }
        Some(SamplerStats {
            cells,
            issued: value.get("issued")?.as_u64()?,
        })
    }
}

/// The panel every member of the generation is scored on.
#[derive(Clone, Debug)]
pub struct Panel {
    pub tasks: Vec<Task>,
    /// Identity of the panel. Two fitness numbers may be compared only when
    /// they were measured under the same id.
    pub id: String,
    /// Index of the next member still owed a score.
    pub cursor: usize,
}

impl Panel {
    /// Seals a task list into a panel, stamping the identity that makes two
    /// fitness numbers comparable. Every panel, however it was drawn, goes
    /// through here so the identity rule is one rule.
    pub fn of(tasks: Vec<Task>) -> Panel {
        Panel {
            id: Panel::identify(&tasks),
            tasks,
            cursor: 0,
        }
    }

    fn identify(tasks: &[Task]) -> String {
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        let mut absorb = |word: u64| {
            hash ^= word;
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        };
        for task in tasks {
            absorb(task.cell.key());
            absorb(task.swap as u64);
            absorb(task.seed as u64);
            absorb(task.ticks as u64);
        }
        format!("p{hash:016x}")
    }

    pub fn to_json(&self) -> Value {
        let tasks: Vec<Value> = self
            .tasks
            .iter()
            .map(|t| json!([t.cell.encode(), t.swap, t.seed, t.ticks]))
            .collect();
        json!({"tasks": tasks, "id": self.id, "cursor": self.cursor})
    }

    pub fn from_json(value: &Value) -> Option<Panel> {
        let mut tasks = Vec::new();
        for raw in value.get("tasks")?.as_array()? {
            let row = raw.as_array()?;
            if row.len() != 4 {
                return None;
            }
            tasks.push(Task {
                cell: Cell::decode(row.first()?)?,
                swap: row.get(1)?.as_bool()?,
                seed: row.get(2)?.as_i64().filter(|s| (1..=2_147_483_646).contains(s))?,
                ticks: row.get(3)?.as_i64().filter(|t| *t > 0)?,
            });
        }
        let panel = Panel {
            id: value.get("id")?.as_str()?.to_string(),
            cursor: value.get("cursor")?.as_u64()? as usize,
            tasks,
        };
        // A panel whose contents no longer hash to its recorded identity could
        // let scores from two different panels be compared. Refuse it.
        (panel.id == Panel::identify(&panel.tasks)).then_some(panel)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::broad::{self, BroadConfig};
    use crate::rng::Stream;

    fn drawn() -> Panel {
        let mut stats = SamplerStats::default();
        let mut rng = Stream::seeded(9);
        let mut cursor = 0u64;
        Panel::of(broad::draw(
            &BroadConfig::default(),
            &mut stats,
            &mut rng,
            4,
            3600,
            &mut cursor,
        ))
    }

    #[test]
    fn a_panel_only_restores_when_its_contents_still_match_its_identity() {
        let mut panel = drawn();
        panel.cursor = 17;
        let saved = panel.to_json();
        let restored = Panel::from_json(&saved).expect("round trip");
        assert_eq!(restored.to_json(), saved);
        assert_eq!(restored.cursor, 17);

        let mut tampered = saved.clone();
        tampered["tasks"][0][2] = json!(1234);
        assert!(
            Panel::from_json(&tampered).is_none(),
            "an edited panel must not keep its identity"
        );
    }

    #[test]
    fn decayed_evidence_forgets_at_the_configured_rate() {
        let cell = broad::board()[0];
        let mut stats = SamplerStats::default();
        // With no decay the statistics are a plain count.
        for _ in 0..10 {
            stats.record(cell, true, 1.0);
        }
        assert_eq!(stats.cells[&cell].games, 10.0);
        assert_eq!(stats.cells[&cell].wins, 10.0);
        // A loss under decay moves the smoothed rate down without erasing the
        // history that came before it.
        stats.record(cell, false, 0.5);
        let stat = stats.cells[&cell];
        assert_eq!(stat.games, 6.0);
        assert_eq!(stat.wins, 5.0);
        assert!(stat.smoothed() < 1.0 && stat.smoothed() > 0.5);
        // And a cell nobody has played reads as a coin flip, not a certainty.
        assert_eq!(CellStat::default().smoothed(), 0.5);
    }

    #[test]
    fn sampler_stats_reject_impossible_evidence() {
        let mut good = SamplerStats::default();
        good.record(broad::board()[0], true, 1.0);
        assert_eq!(
            SamplerStats::from_json(&good.to_json()).unwrap().to_json(),
            good.to_json()
        );
        let impossible = json!({"cells": [[["cyborg", 0, 0], 5.0, 2.0]], "issued": 0});
        assert!(SamplerStats::from_json(&impossible).is_none());
        let foreign = json!({"cells": [[["cyborg", 99, 0], 1.0, 2.0]], "issued": 0});
        assert!(SamplerStats::from_json(&foreign).is_none());
    }
}
