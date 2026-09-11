//! Exact singleton-fleet evaluation path through Local and Helpers.LongGame.
//! Display ticks, the physics pump, post-death simulation and recurrent policy
//! calls deliberately follow the Elm evaluator's event boundaries.
use crate::{
    encode,
    policy::{Net, N_OBS},
};
use melee_core::{
    rng::Seed,
    units::{Side, Sided},
};
use melee_sim::{
    battle::Arena,
    catalog::ShipKind,
    cyborg, init,
    input::{idle, BattleInput, CyborgRating},
    rate, step,
};

#[derive(Clone, Copy)]
pub struct Job {
    pub seed: i64,
    pub ticks: i64,
    pub swap: bool,
    pub rating: CyborgRating,
    pub us: ShipKind,
    pub them: ShipKind,
    pub self_play: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Countdown(i64),
    Combat,
    RoundOver(i64),
    Selecting,
    Victory(Option<Side>),
}

/// The policy driving a seat. Implementing this is the only thing a new brain
/// has to do; the round, phase and pump bookkeeping below stays shared, so the
/// original dense path and any evolved topology see identical event stepping.
pub trait Controller {
    /// The dense path mirrors Elm and evaluates BOTH seats every decision tick,
    /// discarding the seat the cyborg actually pilots. That discarded call
    /// cannot influence the simulation, so a controller that would rather not
    /// pay for it may return false.
    fn evaluates_idle_seat(&self) -> bool {
        true
    }

    /// `ship` is the live hull in that seat; a controller resets any per-ship
    /// state when it changes. `previous` is the seat's actual last input.
    fn decide(
        &mut self,
        side: Side,
        ship: &'static str,
        observation: &[f64; N_OBS],
        previous: BattleInput,
    ) -> BattleInput;
}

/// The original fixed-topology policy, including its memory reset rule: the
/// eight feedback channels zero whenever the hull in a seat changes.
pub struct DensePilot<'a> {
    pub net: &'a Net,
    pub memory: Sided<[f64; 8]>,
    pub memory_round: i64,
    pub memory_names: Sided<&'static str>,
}

impl<'a> DensePilot<'a> {
    pub fn new(net: &'a Net) -> Self {
        Self {
            net,
            memory: Sided::both([0.0; 8]),
            memory_round: -1,
            memory_names: Sided::both(""),
        }
    }
}

impl Controller for DensePilot<'_> {
    fn decide(
        &mut self,
        side: Side,
        ship: &'static str,
        observation: &[f64; N_OBS],
        previous: BattleInput,
    ) -> BattleInput {
        let extra = if *self.memory_names.get(side) == ship {
            *self.memory.get(side)
        } else {
            [0.0; 8]
        };
        let next = self.net.step(observation, previous, &extra);
        self.memory.set(side, next.extra);
        self.memory_names.set(side, ship);
        self.memory_round = 1;
        next.input
    }
}

pub struct State<C> {
    pub phase: Phase,
    /// In Selecting/Victory this is Local.survivor, otherwise phaseArena.
    pub arena: Arena,
    pub game_seed: Seed,
    pub ticks: i64,
    pub quiet: i64,
    pub longest: i64,
    pub pilot: C,
}

pub struct Report {
    pub ticks: i64,
    pub longest_quiet_ticks: i64,
    pub completed: bool,
    pub winner: &'static str,
    pub crew: Sided<i64>,
}

pub fn crew(arena: &Arena, side: Side) -> i64 {
    arena
        .elements
        .get(&arena.combatants.get(side).core().element.0)
        .map_or(0, |el| el.points)
}

const DITTY: [i64; 25] = [
    261, 179, 119, 250, 215, 168, 276, 316, 180, 204, 222, 244, 194, 227, 216, 189, 149, 222, 126,
    194, 285, 336, 230, 136, 287,
];

impl<C: Controller> State<C> {
    pub fn start(job: &Job, pilot: C) -> Self {
        // Demo autoPick consumes a roll for each fleet, including singletons.
        let (_, s) = Seed(job.seed).next();
        let (_, s) = s.next();
        let (bottom, top) = if job.swap {
            (job.them, job.us)
        } else {
            (job.us, job.them)
        };
        Self {
            phase: Phase::Countdown(60),
            arena: init::arena(bottom, top, s),
            game_seed: s,
            ticks: 0,
            quiet: 0,
            longest: 0,
            pilot,
        }
    }

    fn think(&mut self, job: &Job) -> Sided<BattleInput> {
        let mut desired = Sided::both(idle());
        // Both policies are evaluated before either pilot runs, including the
        // unused opposing policy. Feedback contains actual previous controls.
        let ours = if job.swap { Side::Top } else { Side::Bottom };
        let all = self.pilot.evaluates_idle_seat();
        for side in [Side::Bottom, Side::Top] {
            if !(all || job.self_play || side == ours) {
                continue;
            }
            let combatant = self.arena.combatants.get(side);
            let name = combatant.kind().name();
            let previous = combatant.core().old_input;
            let observation = encode::vector(side, &self.arena);
            let next = self.pilot.decide(side, name, &observation, previous);
            desired.set(side, next);
        }
        desired
    }

    pub fn advance(&mut self, job: &Job) {
        let before = (
            crew(&self.arena, Side::Bottom),
            crew(&self.arena, Side::Top),
        );
        let mut elapsed = 1;
        match self.phase {
            Phase::Countdown(n) => {
                self.phase = if n <= 1 {
                    Phase::Combat
                } else {
                    Phase::Countdown(n - 1)
                }
            }
            Phase::Combat => {
                let desired = self.think(job);
                let display_ticks = ((60 - self.arena.pump_acc + 23) / 24).max(1);
                if display_ticks <= job.ticks - self.ticks {
                    elapsed = display_ticks;
                    self.arena.pump_acc += (display_ticks - 1) * 24;
                }
                let (frames, acc) = rate::advance_pump(self.arena.pump_acc);
                self.arena.pump_acc = acc;
                let us = if job.swap { Side::Top } else { Side::Bottom };
                for _ in 0..frames {
                    let mut inputs = Sided::both(idle());
                    for side in [Side::Bottom, Side::Top] {
                        inputs.set(
                            side,
                            if job.self_play || side == us {
                                *desired.get(side)
                            } else {
                                cyborg::pilot(job.rating, side, &mut self.arena)
                            },
                        );
                    }
                    step::tick_authoritative(inputs, &mut self.arena);
                }
                let bottom = crew(&self.arena, Side::Bottom);
                let top = crew(&self.arena, Side::Top);
                if bottom == 0 || top == 0 {
                    let duration = if bottom > 0 {
                        DITTY[self.arena.combatants.bottom.kind().index()]
                    } else if top > 0 {
                        DITTY[self.arena.combatants.top.kind().index()]
                    } else {
                        0
                    };
                    self.phase = Phase::RoundOver(90 + duration);
                    self.game_seed = self.arena.seed;
                }
            }
            Phase::RoundOver(n) => {
                if n > 1 {
                    step::pump_authoritative(Sided::both(idle()), &mut self.arena);
                    self.phase = Phase::RoundOver(n - 1);
                } else {
                    let bottom = crew(&self.arena, Side::Bottom) > 0;
                    let top = crew(&self.arena, Side::Top) > 0;
                    self.phase = match (bottom, top) {
                        (false, false) => Phase::Victory(None),
                        (true, false) => Phase::Victory(Some(Side::Bottom)),
                        (false, true) => Phase::Victory(Some(Side::Top)),
                        // A resurrected survivor can leave both singleton slots
                        // selected. Local stays in Selecting in this case.
                        (true, true) => {
                            let (_, s) = self.game_seed.next();
                            let (_, s) = s.next();
                            self.game_seed = s;
                            Phase::Selecting
                        }
                    };
                }
            }
            Phase::Selecting | Phase::Victory(_) => {}
        }
        let after = (
            crew(&self.arena, Side::Bottom),
            crew(&self.arena, Side::Top),
        );
        let changed = after != before;
        let dry = if changed { 0 } else { self.quiet + elapsed };
        self.longest = self.longest.max(if changed {
            self.quiet + elapsed - 1
        } else {
            dry
        });
        self.quiet = dry;
        self.ticks += elapsed;
    }

    pub fn report(&self) -> Report {
        Report {
            ticks: self.ticks,
            longest_quiet_ticks: self.longest,
            completed: matches!(self.phase, Phase::Victory(_)),
            winner: match self.phase {
                Phase::Victory(Some(Side::Bottom)) => "bottom",
                Phase::Victory(Some(Side::Top)) => "top",
                Phase::Victory(None) => "draw",
                _ => "pending",
            },
            crew: Sided {
                bottom: crew(&self.arena, Side::Bottom),
                top: crew(&self.arena, Side::Top),
            },
        }
    }
}

pub fn run(job: &Job, net: &Net) -> Report {
    run_with(job, DensePilot::new(net))
}

pub fn run_with<C: Controller>(job: &Job, pilot: C) -> Report {
    run_observed(job, pilot, |_| {})
}

pub fn run_observed<C: Controller>(
    job: &Job,
    pilot: C,
    mut observe: impl FnMut(&State<C>),
) -> Report {
    let mut state = State::start(job, pilot);
    observe(&state);
    while !matches!(state.phase, Phase::Victory(_)) && state.ticks < job.ticks {
        state.advance(job);
        observe(&state);
    }
    state.report()
}
