//! Which fights the population trains on this generation.
//!
//! One panel is drawn per generation and EVERY member is scored on that exact
//! panel, so the generation's numbers are mutually comparable. The panel mixes
//! three deterministic pressures:
//!
//!   * weakness, so cells the champion keeps losing get more attention,
//!   * novelty, so a cell the curriculum just unlocked is not ignored, and
//!   * a rehearsal floor, so a mastered cell keeps being revisited and a
//!     regression shows up instead of quietly rotting.
//!
//! Seats alternate by slot parity, so both orientations are always present.
//! Seeds come from the TRAIN stream only; audit and confirmation seeds live in
//! their own namespaces and can never be drawn here.

use crate::curriculum::Cell;
use crate::episode::Task;
use crate::rng::{episode_seed, Stream, StreamTag};
use serde_json::{json, Value};
use std::collections::BTreeMap;

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct SamplerConfig {
    /// Episodes each population member plays per generation.
    pub panel: usize,
    pub floor: f64,
    pub weakness: f64,
    pub novelty: f64,
    /// Generations a newly unlocked cell keeps its novelty bonus.
    pub novelty_span: u32,
    /// How fast older evidence fades out of the weakness estimate.
    pub decay: f64,
    /// Share of the panel drawn from frozen-model cells once the cyborg ladder
    /// is mastered. The rest stays on cyborgs, which is what detects a
    /// regression against the original opponents.
    pub model_share: f64,
    /// Extra weight given to a cell that an audit or a regression sweep just
    /// failed. This is how a failure turns into rehearsal rather than into a
    /// number on a dashboard.
    pub focus: f64,
}

impl Default for SamplerConfig {
    fn default() -> Self {
        SamplerConfig {
            panel: 8,
            floor: 1.0,
            weakness: 4.0,
            novelty: 6.0,
            novelty_span: 20,
            decay: 0.90,
            model_share: 0.5,
            focus: 8.0,
        }
    }
}

impl SamplerConfig {
    pub fn to_json(self) -> Value {
        json!({"panel": self.panel, "floor": self.floor, "weakness": self.weakness,
               "novelty": self.novelty, "novelty_span": self.novelty_span,
               "decay": self.decay, "model_share": self.model_share, "focus": self.focus})
    }

    pub fn from_json(value: &Value) -> Option<SamplerConfig> {
        let number = |key: &str| value.get(key)?.as_f64().filter(|n| n.is_finite());
        let panel = value.get("panel")?.as_u64()? as usize;
        if panel == 0 {
            return None;
        }
        Some(SamplerConfig {
            panel,
            floor: number("floor")?,
            weakness: number("weakness")?,
            novelty: number("novelty")?,
            novelty_span: value.get("novelty_span")?.as_u64()? as u32,
            decay: number("decay")?,
            model_share: number("model_share")?,
            // Older checkpoints predate focus; zero reproduces their behaviour.
            focus: match value.get("focus") {
                None => 0.0,
                Some(other) => other.as_f64().filter(|n| n.is_finite() && *n >= 0.0)?,
            },
        })
    }
}

/// Decayed training evidence for one cell. This is sampling state, never gate
/// evidence: the dashboard reports champion audits separately.
#[derive(Copy, Clone, PartialEq, Debug, Default)]
pub struct CellStat {
    pub wins: f64,
    pub games: f64,
    /// Generation the cell first became active.
    pub added: u32,
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
    /// Registers any cell that is active but not yet known, stamping the
    /// generation it appeared so novelty can be measured.
    pub fn admit(&mut self, active: &[Cell], generation: u32) {
        for cell in active {
            self.cells.entry(*cell).or_insert(CellStat {
                wins: 0.0,
                games: 0.0,
                added: generation,
            });
        }
    }

    pub fn record(&mut self, cell: Cell, won: bool, decay: f64) {
        let stat = self.cells.entry(cell).or_default();
        stat.wins = stat.wins * decay + won as u8 as f64;
        stat.games = stat.games * decay + 1.0;
    }

    pub fn to_json(&self) -> Value {
        let cells: Vec<Value> = self
            .cells
            .iter()
            .map(|(cell, stat)| json!([cell.encode(), stat.wins, stat.games, stat.added]))
            .collect();
        json!({"cells": cells, "issued": self.issued})
    }

    pub fn from_json(value: &Value) -> Option<SamplerStats> {
        let mut cells = BTreeMap::new();
        for raw in value.get("cells")?.as_array()? {
            let row = raw.as_array()?;
            if row.len() != 4 {
                return None;
            }
            let wins = row.get(1)?.as_f64().filter(|n| n.is_finite() && *n >= 0.0)?;
            let games = row.get(2)?.as_f64().filter(|n| n.is_finite() && *n >= 0.0)?;
            if wins > games + 1e-9 {
                return None;
            }
            cells.insert(
                Cell::decode(row.first()?)?,
                CellStat {
                    wins,
                    games,
                    added: row.get(3)?.as_u64()? as u32,
                },
            );
        }
        Some(SamplerStats {
            cells,
            issued: value.get("issued")?.as_u64()?,
        })
    }
}

/// How badly a cell wants attention this generation. `focused` marks a cell
/// that the most recent audit or regression sweep could not clear.
pub fn weight(config: &SamplerConfig, stat: &CellStat, generation: u32, focused: bool) -> f64 {
    let fresh = generation.saturating_sub(stat.added) < config.novelty_span;
    config.floor
        + config.weakness * (1.0 - stat.smoothed())
        + if fresh { config.novelty } else { 0.0 }
        + if focused { config.focus } else { 0.0 }
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

/// Draws the generation's panel. `cyborg` and `model` are the currently active
/// cells of each kind; `model` is empty until the cyborg ladder is mastered.
pub fn draw(
    config: &SamplerConfig,
    stats: &mut SamplerStats,
    rng: &mut Stream,
    salt: u64,
    generation: u32,
    ticks: i64,
    cyborg: &[Cell],
    model: &[Cell],
    focus: &[Cell],
) -> Panel {
    let mut tasks = Vec::with_capacity(config.panel);
    let model_slots = if model.is_empty() {
        0
    } else {
        (config.panel as f64 * config.model_share).round() as usize
    };
    for slot in 0..config.panel {
        // Cyborg cells come first so a short panel never loses its rehearsal.
        let pool = if slot >= config.panel - model_slots {
            model
        } else {
            cyborg
        };
        let pool = if pool.is_empty() { cyborg } else { pool };
        let Some(cell) = pick(config, stats, rng, generation, pool, focus) else {
            break;
        };
        let swap = slot % 2 == 1;
        stats.issued += 1;
        tasks.push(Task {
            cell,
            swap,
            seed: episode_seed(
                StreamTag::Train,
                salt,
                cell.key(),
                swap as u64,
                stats.issued,
            ),
            ticks,
        });
    }
    Panel::of(tasks)
}

fn pick(
    config: &SamplerConfig,
    stats: &SamplerStats,
    rng: &mut Stream,
    generation: u32,
    pool: &[Cell],
    focus: &[Cell],
) -> Option<Cell> {
    if pool.is_empty() {
        return None;
    }
    let weights: Vec<f64> = pool
        .iter()
        .map(|cell| {
            weight(
                config,
                stats.cells.get(cell).unwrap_or(&CellStat::default()),
                generation,
                focus.contains(cell),
            )
        })
        .collect();
    let total: f64 = weights.iter().sum();
    if total <= 0.0 {
        return Some(pool[rng.below(pool.len())]);
    }
    let mut target = rng.unit() * total;
    for (cell, weight) in pool.iter().zip(&weights) {
        target -= weight;
        if target <= 0.0 {
            return Some(*cell);
        }
    }
    Some(pool[pool.len() - 1])
}

/// A fixed probe used to decide whether a candidate is worth auditing. It uses
/// the READY stream, so it never consumes or reveals audit evidence.
pub fn readiness_probe(
    salt: u64,
    attempt: u64,
    games: usize,
    ticks: i64,
    cells: &[Cell],
) -> Vec<Task> {
    (0..games)
        .filter_map(|slot| {
            let cell = *cells.get(slot % cells.len().max(1))?;
            let swap = slot % 2 == 1;
            Some(Task {
                cell,
                swap,
                seed: episode_seed(
                    StreamTag::Ready,
                    salt,
                    cell.key(),
                    swap as u64,
                    attempt * games as u64 + slot as u64,
                ),
                ticks,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::curriculum::{cells, model_cells};
    use std::collections::BTreeSet;

    fn stats_for(active: &[Cell]) -> SamplerStats {
        let mut stats = SamplerStats::default();
        stats.admit(active, 0);
        stats
    }

    #[test]
    fn a_panel_covers_both_seats_and_never_repeats_a_seed() {
        let active = cells(6);
        let mut stats = stats_for(&active);
        let mut rng = Stream::seeded(3);
        let config = SamplerConfig {
            panel: 24,
            ..SamplerConfig::default()
        };
        let mut seen: BTreeSet<i64> = BTreeSet::new();
        for generation in 0..30 {
            let panel = draw(
                &config, &mut stats, &mut rng, 11, generation, 3600, &active, &[], &[],
            );
            assert_eq!(panel.tasks.len(), 24);
            assert!(panel.tasks.iter().any(|t| t.swap));
            assert!(panel.tasks.iter().any(|t| !t.swap));
            for task in &panel.tasks {
                assert!(seen.insert(task.seed), "seed reused: {}", task.seed);
                assert!(active.contains(&task.cell));
            }
        }
    }

    #[test]
    fn weak_and_new_cells_attract_more_of_the_panel_than_mastered_ones() {
        let active = cells(8);
        let mut stats = stats_for(&active);
        let weak = active[3];
        // Everything is old and mastered except the weak cell.
        for cell in &active {
            for _ in 0..60 {
                stats.record(*cell, *cell != weak, 1.0);
            }
        }
        let config = SamplerConfig::default();
        let generation = config.novelty_span + 5;
        let strong_weight = weight(&config, &stats.cells[&active[0]], generation, false);
        let weak_weight = weight(&config, &stats.cells[&weak], generation, false);
        assert!(weak_weight > strong_weight * 2.0);

        // But a mastered cell still keeps a rehearsal floor above zero.
        assert!(strong_weight >= config.floor);

        let mut rng = Stream::seeded(5);
        let panel = draw(
            &SamplerConfig {
                panel: 400,
                ..config
            },
            &mut stats,
            &mut rng,
            1,
            generation,
            3600,
            &active,
            &[],
            &[],
        );
        let drawn = panel.tasks.iter().filter(|t| t.cell == weak).count();
        let fair = panel.tasks.len() / active.len();
        assert!(drawn > fair, "weak cell drawn {drawn}, fair share {fair}");
        let covered: BTreeSet<Cell> = panel.tasks.iter().map(|t| t.cell).collect();
        assert_eq!(covered.len(), active.len(), "rehearsal floor lost a cell");
    }

    #[test]
    fn the_mixed_phase_keeps_sampling_cyborgs() {
        let cyborg = cells(crate::curriculum::FINAL_STAGE);
        let model = model_cells();
        let mut stats = stats_for(&cyborg);
        stats.admit(&model, 0);
        let mut rng = Stream::seeded(7);
        let config = SamplerConfig {
            panel: 64,
            ..SamplerConfig::default()
        };
        let panel = draw(
            &config, &mut stats, &mut rng, 2, 0, 3600, &cyborg, &model, &[],
        );
        let models = panel
            .tasks
            .iter()
            .filter(|t| t.cell.foe == crate::curriculum::Opponent::Model)
            .count();
        assert!(models > 0, "self play never happens");
        assert!(models < panel.tasks.len(), "cyborg rehearsal was dropped");
    }

    #[test]
    fn a_panel_only_restores_when_its_contents_still_match_its_identity() {
        let active = cells(4);
        let mut stats = stats_for(&active);
        let mut rng = Stream::seeded(9);
        let mut panel = draw(
            &SamplerConfig::default(),
            &mut stats,
            &mut rng,
            4,
            0,
            3600,
            &active,
            &[],
            &[],
        );
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
    fn a_failed_cell_is_rehearsed_harder_than_the_rest() {
        let active = cells(8);
        let mut stats = stats_for(&active);
        // Everything looks equally healthy, so only the focus can separate them.
        for cell in &active {
            for _ in 0..40 {
                stats.record(*cell, true, 1.0);
            }
        }
        let config = SamplerConfig {
            panel: 400,
            ..SamplerConfig::default()
        };
        let generation = config.novelty_span + 5;
        let failed = vec![active[5]];
        assert!(
            weight(&config, &stats.cells[&failed[0]], generation, true)
                > weight(&config, &stats.cells[&failed[0]], generation, false) * 3.0
        );
        let mut rng = Stream::seeded(17);
        let panel = draw(
            &config,
            &mut stats,
            &mut rng,
            3,
            generation,
            3600,
            &active,
            &[],
            &failed,
        );
        let focused = panel.tasks.iter().filter(|t| t.cell == failed[0]).count();
        let fair = panel.tasks.len() / active.len();
        assert!(
            focused > fair * 2,
            "failed cell drawn {focused}, fair share {fair}"
        );
    }

    #[test]
    fn sampler_stats_reject_impossible_evidence() {
        let good = stats_for(&cells(2));
        assert_eq!(
            SamplerStats::from_json(&good.to_json()).unwrap().to_json(),
            good.to_json()
        );
        let impossible = json!({"cells": [[["cyborg", 0, 0], 5.0, 2.0, 0]], "issued": 0});
        assert!(SamplerStats::from_json(&impossible).is_none());
        let foreign = json!({"cells": [[["cyborg", 99, 0], 1.0, 2.0, 0]], "issued": 0});
        assert!(SamplerStats::from_json(&foreign).is_none());
    }

    #[test]
    fn the_readiness_probe_lives_in_its_own_seed_namespace() {
        let active = cells(3);
        let probe = readiness_probe(6, 0, 16, 3600, &active);
        assert_eq!(probe.len(), 16);
        assert!(probe.iter().any(|t| t.swap));
        assert!(probe.iter().any(|t| !t.swap));
        let ready: BTreeSet<i64> = probe.iter().map(|t| t.seed).collect();

        let mut stats = stats_for(&active);
        let mut rng = Stream::seeded(13);
        let mut train: BTreeSet<i64> = BTreeSet::new();
        for generation in 0..200 {
            let panel = draw(
                &SamplerConfig {
                    panel: 16,
                    ..SamplerConfig::default()
                },
                &mut stats,
                &mut rng,
                6,
                generation,
                3600,
                &active,
                &[],
                &[],
            );
            train.extend(panel.tasks.iter().map(|t| t.seed));
        }
        assert!(ready.is_disjoint(&train), "readiness leaked into training");
    }
}
