//! Training accounting around the unchanged authoritative game transitions.
//! Only combat consumes the evaluation budget. Finish a started round transition
//! to resolve surviving projectiles/resurrection; its presentation time is free.
use crate::{
    eval::{Job, Phase, Report, State},
    policy::Net,
};

pub const VERSION: &str = "combat-v1";

pub struct Evaluation {
    pub report: Report,
    pub display_ticks: i64,
}

pub fn run(job: &Job, net: &Net) -> Evaluation {
    evaluate(State::start(job), job, net)
}

fn evaluate(mut state: State, job: &Job, net: &Net) -> Evaluation {
    while matches!(state.phase, Phase::Countdown(_)) {
        state.advance(job, net);
    }
    state.quiet = 0;
    state.longest = 0;
    let mut combat_ticks = 0;
    while state.phase == Phase::Combat && combat_ticks < job.ticks {
        let before = state.ticks;
        // advance's batching uses an absolute display deadline. Translate the
        // remaining combat budget without changing any physics or policy call.
        let remaining = Job {
            ticks: state.ticks + job.ticks - combat_ticks,
            ..*job
        };
        state.advance(&remaining, net);
        combat_ticks += state.ticks - before;
    }
    let longest_quiet_ticks = state.longest;
    // This is the existing game transition, not an early zero-crew win guess.
    // Selecting with two survivors remains unresolved, never a fabricated win.
    while matches!(state.phase, Phase::RoundOver(_)) {
        state.advance(job, net);
    }
    let mut report = state.report();
    report.ticks = combat_ticks;
    report.longest_quiet_ticks = longest_quiet_ticks;
    Evaluation {
        report,
        display_ticks: state.ticks,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{eval, policy::N_WEIGHTS};
    use melee_sim::{catalog::ShipKind, input::CyborgRating};

    fn job(seed: i64) -> Job {
        Job {
            seed,
            ticks: 1800,
            swap: false,
            rating: CyborgRating::AwesomeCyborg,
            us: ShipKind::Umgah,
            them: ShipKind::Yehat,
            self_play: false,
        }
    }

    #[test]
    fn countdown_does_not_consume_combat_budget_or_affect_score_inputs() {
        let net = Net::load(&[0.0; N_WEIGHTS]).unwrap();
        let job = Job {
            ticks: 24,
            ..job(42)
        };
        let normal = run(&job, &net);
        let mut state = State::start(&job);
        state.phase = Phase::Countdown(600);
        let longer = evaluate(state, &job, &net);
        assert_eq!(normal.report.ticks, 24);
        assert_eq!(longer.report.ticks, 24);
        assert_eq!(normal.report.crew, longer.report.crew);
        assert_eq!(
            normal.report.longest_quiet_ticks,
            longer.report.longest_quiet_ticks
        );
        assert_eq!(longer.display_ticks - normal.display_ticks, 540);
    }

    #[test]
    fn deaths_on_the_last_combat_tick_are_resolved_outside_the_budget() {
        let net = Net::load(&[0.0; N_WEIGHTS]).unwrap();
        let mut found = 0;
        for seed in [42, 99, 1234, 1701] {
            let full = run(&job(seed), &net);
            if !full.report.completed {
                continue;
            }
            found += 1;
            let boundary = run(
                &Job {
                    ticks: full.report.ticks,
                    ..job(seed)
                },
                &net,
            );
            assert!(boundary.report.completed);
            assert_eq!(boundary.report.winner, full.report.winner);
            assert_eq!(boundary.report.crew, full.report.crew);
            assert!(boundary.display_ticks > boundary.report.ticks + 60);
        }
        assert!(found > 0, "fixture must naturally reach a combat death");
    }

    #[test]
    fn resolved_results_match_the_original_game_including_pkunk_resurrection() {
        let net = Net::load(&[0.0; N_WEIGHTS]).unwrap();
        for seed in [42, 99, 1234, 1701, 2137, 7] {
            for us in [ShipKind::Pkunk, ShipKind::Umgah, ShipKind::Yehat] {
                let job = Job { us, ..job(seed) };
                let actual = run(&job, &net);
                // Replay identical controls and seed through the unchanged full
                // game, using the actual elapsed deadline rather than combat time.
                let expected = eval::run(
                    &Job {
                        ticks: actual.display_ticks,
                        ..job
                    },
                    &net,
                );
                assert_eq!(actual.report.crew, expected.crew);
                assert_eq!(actual.report.winner, expected.winner);
                assert_eq!(actual.report.completed, expected.completed);
                assert!(actual.report.ticks <= job.ticks);
            }
        }
    }
}
