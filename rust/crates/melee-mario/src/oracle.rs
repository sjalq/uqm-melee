//! Cross-language oracle for `tests/Oracle/MarioPolicy.elm`.
//!
//! Reads NDJSON on stdin, one record per line:
//!
//! ```json
//! {"genome": <genome schema 1>,
//!  "steps": [{"observations":[103 numbers],"previous":[5],"memory":[8]}]}
//! ```
//!
//! Writes NDJSON on stdout, ONE LINE PER STEP, in order:
//!
//! ```json
//! {"outputs":[13 numbers]}
//! ```
//!
//! A malformed record emits a single `{"error":"..."}` line instead of that
//! record's step lines, and reading continues with the next record.
//!
//! Prior controls and prior memory are supplied explicitly by the caller, so
//! the oracle never invents them. The graph's own recurrent activations DO
//! persist from step to step within a record and are reset at the start of
//! every record, which is exactly what one episode does.

use crate::brain::assemble;
use crate::genome::{Genome, N_CONTROL, N_MEMORY, N_OBS};
use crate::graph::{Activations, Network};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn numbers<const N: usize>(value: Option<&Value>, field: &str) -> Result<[f64; N], String> {
    let list = value
        .ok_or_else(|| format!("missing {field}"))?
        .as_array()
        .ok_or_else(|| format!("{field} must be an array"))?;
    if list.len() != N {
        return Err(format!("{field} must hold {N} numbers, found {}", list.len()));
    }
    let mut out = [0.0; N];
    for (slot, raw) in out.iter_mut().zip(list) {
        let n = raw
            .as_f64()
            .ok_or_else(|| format!("{field} must hold numbers"))?;
        if !n.is_finite() {
            return Err(format!("{field} must hold finite numbers"));
        }
        *slot = n;
    }
    Ok(out)
}

fn record(raw: &str, out: &mut impl Write) -> Result<(), String> {
    let value: Value = serde_json::from_str(raw).map_err(|e| e.to_string())?;
    let genome = Genome::from_json(
        value
            .get("genome")
            .ok_or_else(|| "missing genome".to_string())?,
    )
    .map_err(|e| e.to_string())?;
    let steps = value
        .get("steps")
        .ok_or_else(|| "missing steps".to_string())?
        .as_array()
        .ok_or_else(|| "steps must be an array".to_string())?;

    let network = Network::compile(&genome);
    let mut state = Activations::new(&network);
    let mut lines: Vec<Value> = Vec::with_capacity(steps.len());
    for step in steps {
        let observation = numbers::<N_OBS>(step.get("observations"), "observations")?;
        let previous = numbers::<N_CONTROL>(step.get("previous"), "previous")?;
        let memory = numbers::<N_MEMORY>(step.get("memory"), "memory")?;
        let outputs = network.activate(&mut state, &assemble(&observation, &previous, &memory));
        lines.push(json!({ "outputs": outputs.to_vec() }));
    }
    // Only emitted once the whole record parsed, so a late failure cannot
    // leave a half-written answer interleaved with an error line.
    for line in lines {
        serde_json::to_writer(&mut *out, &line).map_err(|e| e.to_string())?;
        writeln!(out).map_err(|e| e.to_string())?;
    }
    out.flush().map_err(|e| e.to_string())
}

pub fn run(input: impl BufRead, out: &mut impl Write) -> io::Result<()> {
    for line in input.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        if let Err(error) = record(&line, out) {
            serde_json::to_writer(&mut *out, &json!({ "error": error }))?;
            writeln!(out)?;
            out.flush()?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::genome::{Gene, Node, NodeKind, HIDDEN_BASE, N_INPUT, OUTPUT_BASE};

    fn drive(input: &str) -> String {
        let mut out: Vec<u8> = Vec::new();
        run(io::Cursor::new(input), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn emits_one_line_per_step_and_keeps_graph_state() {
        let mut g = Genome::minimal();
        g.nodes.push(Node {
            id: HIDDEN_BASE,
            kind: NodeKind::Hidden,
        });
        g.genes = vec![
            Gene {
                innovation: 1,
                from: N_INPUT - 1,
                to: HIDDEN_BASE,
                weight: 1.0,
                enabled: true,
            },
            Gene {
                innovation: 2,
                from: HIDDEN_BASE,
                to: HIDDEN_BASE,
                weight: 1.0,
                enabled: true,
            },
            Gene {
                innovation: 3,
                from: HIDDEN_BASE,
                to: OUTPUT_BASE,
                weight: 1.0,
                enabled: true,
            },
        ];
        let genome = g.validate().unwrap();
        let step = json!({
            "observations": vec![0.0; N_OBS],
            "previous": vec![0.0; N_CONTROL],
            "memory": vec![0.0; N_MEMORY],
        });
        let line = json!({"genome": genome.to_json(), "steps": [step.clone(), step]});
        let output = drive(&format!("{line}\n"));
        let emitted: Vec<Value> = output
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect();
        assert_eq!(emitted.len(), 2);
        let first = emitted[0]["outputs"].as_array().unwrap();
        let second = emitted[1]["outputs"].as_array().unwrap();
        assert_eq!(first.len(), 13);
        // The self-loop means step two sees step one, so the answers differ.
        assert_ne!(first[0], second[0]);
    }

    #[test]
    fn reports_bad_records_without_stopping() {
        let genome = Genome::minimal();
        let good = json!({"genome": genome.to_json(), "steps": []});
        let bad = json!({"genome": genome.to_json(), "steps": [{"observations": [1.0]}]});
        let output = drive(&format!("{bad}\n{good}\nnot json\n"));
        let lines: Vec<&str> = output.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains(&format!("observations must hold {N_OBS} numbers")));
        assert!(lines[1].contains("error"));
    }
}
