//! Run directory, single-instance lock and atomic checkpoints.
//!
//! Every run owns `artifacts/mario/<run id>/`, which is immutable in the sense
//! that a second run never writes into it. A checkpoint is written to a
//! temporary file in the same directory and then renamed over the live one, so
//! a crash mid-write leaves either the previous complete checkpoint or the new
//! complete one, never a truncated file.

use serde_json::Value;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

pub const CHECKPOINT: &str = "checkpoint.json";
pub const CONFIG: &str = "config.json";
pub const EVENTS: &str = "events.ndjson";
pub const LOCK: &str = "run.lock";

pub fn run_dir(root: &Path, run_id: &str) -> PathBuf {
    root.join("artifacts").join("mario").join(run_id)
}

/// Holds the run directory for one process. Dropping it releases the claim.
#[derive(Debug)]
pub struct RunLock {
    path: PathBuf,
}

impl RunLock {
    /// Fails when another live process already owns this run. A lock left
    /// behind by a killed process is reclaimed, because the run directory is
    /// still consistent: the checkpoint is whole and the unfinished batch is
    /// deterministic and simply replays.
    pub fn acquire(dir: &Path) -> io::Result<RunLock> {
        fs::create_dir_all(dir)?;
        let path = dir.join(LOCK);
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(mut file) => {
                writeln!(file, "{}", std::process::id())?;
                Ok(RunLock { path })
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                let owner = fs::read_to_string(&path).unwrap_or_default();
                let pid: u32 = owner.trim().parse().unwrap_or(0);
                if pid != 0 && alive(pid) {
                    return Err(io::Error::new(
                        io::ErrorKind::AddrInUse,
                        format!(
                            "run {} is already being trained by process {pid}",
                            dir.display()
                        ),
                    ));
                }
                let mut file = File::create(&path)?;
                writeln!(file, "{}", std::process::id())?;
                Ok(RunLock { path })
            }
            Err(error) => Err(error),
        }
    }
}

impl Drop for RunLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

#[cfg(unix)]
fn alive(pid: u32) -> bool {
    // `kill -0` reports whether the process exists without disturbing it.
    std::process::Command::new("kill")
        .args(["-0", &pid.to_string()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn alive(_pid: u32) -> bool {
    true
}

/// Writes `value` so that readers only ever observe a complete document.
pub fn write_atomic(path: &Path, value: &Value) -> io::Result<()> {
    let parent = path.parent().unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        "{}.tmp",
        path.file_name().and_then(|n| n.to_str()).unwrap_or("out")
    ));
    {
        let mut file = File::create(&temporary)?;
        serde_json::to_writer(&mut file, value)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
    }
    fs::rename(&temporary, path)
}

pub fn read_json(path: &Path) -> io::Result<Value> {
    let mut raw = String::new();
    File::open(path)?.read_to_string(&mut raw)?;
    serde_json::from_str(&raw).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

pub fn append_line(path: &Path, value: &Value) -> io::Result<()> {
    let parent = path.parent().unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let mut file = OpenOptions::new().append(true).create(true).open(path)?;
    serde_json::to_writer(&mut file, value)?;
    file.write_all(b"\n")
}

/// Lists the run identifiers under a root, newest checkpoint first.
pub fn runs(root: &Path) -> Vec<String> {
    let base = root.join("artifacts").join("mario");
    let mut found: Vec<(std::time::SystemTime, String)> = Vec::new();
    let Ok(entries) = fs::read_dir(&base) else {
        return Vec::new();
    };
    for entry in entries.flatten() {
        let Some(name) = entry.file_name().to_str().map(str::to_string) else {
            continue;
        };
        let checkpoint = entry.path().join(CHECKPOINT);
        let stamp = fs::metadata(&checkpoint)
            .and_then(|m| m.modified())
            .unwrap_or(std::time::UNIX_EPOCH);
        if checkpoint.exists() {
            found.push((stamp, name));
        }
    }
    found.sort_by(|a, b| b.0.cmp(&a.0));
    found.into_iter().map(|(_, name)| name).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("melee-mario-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn an_atomic_write_replaces_the_previous_document_whole() {
        let dir = scratch("atomic");
        let path = dir.join("checkpoint.json");
        write_atomic(&path, &json!({"generation": 1})).unwrap();
        assert_eq!(read_json(&path).unwrap(), json!({"generation": 1}));
        write_atomic(&path, &json!({"generation": 2})).unwrap();
        assert_eq!(read_json(&path).unwrap(), json!({"generation": 2}));
        assert!(!dir.join("checkpoint.json.tmp").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_second_live_instance_cannot_claim_the_same_run() {
        let dir = scratch("lock");
        let first = RunLock::acquire(&dir).unwrap();
        let second = RunLock::acquire(&dir);
        assert!(second.is_err(), "two trainers claimed one run");
        drop(first);
        // Released, so the run can be resumed.
        let third = RunLock::acquire(&dir).unwrap();
        drop(third);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_stale_lock_from_a_dead_process_is_reclaimed() {
        let dir = scratch("stale");
        fs::write(dir.join(LOCK), "999999999\n").unwrap();
        let lock = RunLock::acquire(&dir).expect("stale lock must not block a resume");
        drop(lock);
        fs::remove_dir_all(&dir).unwrap();
    }
}
