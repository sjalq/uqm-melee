use melee_core::units::Side;
use melee_neat::{
    eval,
    policy::{Net, N_WEIGHTS},
};
use melee_sim::{catalog::ShipKind, input::CyborgRating};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn emit(out: &mut impl Write, value: &Value) -> io::Result<()> {
    serde_json::to_writer(&mut *out, value)?;
    writeln!(out)?;
    out.flush()
}

fn evaluate(raw: &str, out: &mut impl Write) -> Result<(), String> {
    let v: Value = serde_json::from_str(raw).map_err(|e| e.to_string())?;
    let weights = v
        .get("weights")
        .and_then(Value::as_array)
        .ok_or("missing weights array")?
        .iter()
        .map(|x| {
            x.as_f64()
                .ok_or_else(|| "weights must be numbers".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let net = Net::load(&weights)?;
    let seed = v
        .get("seed")
        .and_then(Value::as_i64)
        .ok_or("missing integer seed")?;
    let ticks = v
        .get("ticks")
        .and_then(Value::as_i64)
        .ok_or("missing integer ticks")?;
    let swap = v.get("swap").and_then(Value::as_bool).unwrap_or(false);
    let string = |key: &str, default: &str| {
        v.get(key)
            .and_then(Value::as_str)
            .unwrap_or(default)
            .to_string()
    };
    let rating = string("rating", "awesome");
    let us = string("us", "Pkunk");
    let them = string("them", "Umgah");
    let foe = string("foe", "cyborg");
    let job = eval::Job {
        seed,
        ticks,
        swap,
        rating: match rating.as_str() {
            "standard" => CyborgRating::StandardCyborg,
            "good" => CyborgRating::GoodCyborg,
            _ => CyborgRating::AwesomeCyborg,
        },
        us: ShipKind::from_str_lossy(&us),
        them: ShipKind::from_str_lossy(&them),
        self_play: foe == "self",
    };
    if v.get("trace").and_then(Value::as_bool).unwrap_or(false) {
        let metadata = melee_neat::trace::Metadata {
            rating: &rating,
            us: &us,
            them: &them,
            foe: &foe,
        };
        let mut error = None;
        melee_neat::trace::run_with_metadata(&job, &net, metadata, |value| {
            if error.is_none() {
                error = emit(out, &value).err();
            }
        });
        return error.map_or(Ok(()), |e| Err(e.to_string()));
    }
    let report = eval::run(&job, &net);
    let side = if swap { Side::Top } else { Side::Bottom };
    let seat = if swap { "top" } else { "bottom" };
    let own = *report.crew.get(side);
    let enemy = *report.crew.get(side.other());
    let own_start = job.us.stock().starting_crew;
    let enemy_start = job.them.stock().starting_crew;
    let damage = (enemy_start - enemy).max(0) as f64 / enemy_start.max(1) as f64;
    let hurt = (own_start - own).max(0) as f64 / own_start.max(1) as f64;
    let engage = 1.0 - report.longest_quiet_ticks as f64 / report.ticks.max(1) as f64;
    let dense = 1000.0 * damage - 500.0 * hurt + 50.0 * engage - 0.01 * report.ticks as f64;
    let won = report.winner == seat && report.completed;
    let lost = report.completed && report.winner != seat && report.winner != "pending";
    let fitness = if won {
        1_000_000.0 - report.ticks as f64
    } else if enemy == 0 {
        100_000.0 - report.ticks as f64 + dense
    } else if lost {
        dense - 3000.0
    } else {
        dense
    };
    emit(out,
        &json!({"fitness":fitness,"ticks":report.ticks,"winner":report.winner,"own":own,"enemy":enemy,
        "own_start":own_start,"enemy_start":enemy_start,"damage":damage,"hurt":hurt,"engage":engage,"dense":dense,
        "swap":swap,"outcome":if report.completed{"completed"}else{"invalidated"},"seed":seed,"us":us,"them":them,
        "rating":rating,"foe":foe,"n_weights":N_WEIGHTS}),
    ).map_err(|e| e.to_string())
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut stdout = io::BufWriter::new(io::stdout().lock());
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        if let Err(error) = evaluate(&line, &mut stdout) {
            emit(&mut stdout, &json!({"error":error}))?;
        }
    }
    Ok(())
}
