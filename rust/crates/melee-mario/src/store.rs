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
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};

pub const CHECKPOINT: &str = "checkpoint.json";
pub const CONFIG: &str = "config.json";
pub const EVENTS: &str = "events.ndjson";
pub const LOCK: &str = "run.lock";

pub fn run_dir(root: &Path, run_id: &str) -> PathBuf {
    root.join("artifacts").join("mario").join(run_id)
}

/// An exclusive claim on one run directory, held by the KERNEL rather than by
/// a written process id.
///
/// A file containing a pid can only ever be advisory: two resumes that both
/// read a dead owner's pid would both decide the lock was stale and both
/// proceed, and then two processes would be writing the same checkpoint. So
/// the claim is an `flock(LOCK_EX | LOCK_NB)` on the lock file's inode, held
/// open for the life of the [`RunLock`]. The kernel releases it when the file
/// descriptor closes, which includes a crash or a kill, so a dead owner never
/// blocks a resume and a live one always does.
///
/// The lock file is never unlinked while held: removing it would let a second
/// process create a NEW inode at the same path and lock that instead. It stays
/// in the run directory as a permanent, empty marker.
#[derive(Debug)]
pub struct RunLock {
    /// Kept open purely to hold the kernel lock. Dropping it releases.
    _file: File,
    owner: u32,
}

impl RunLock {
    /// Fails while another live process owns this run. Acquire it BEFORE
    /// reading or writing anything else in the directory.
    pub fn acquire(dir: &Path) -> io::Result<RunLock> {
        fs::create_dir_all(dir)?;
        let path = dir.join(LOCK);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&path)?;
        // Safety: the descriptor is valid and owned for the duration of the
        // call, and flock only associates a lock with it.
        let locked = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if locked != 0 {
            let error = io::Error::last_os_error();
            let owner = fs::read_to_string(&path).unwrap_or_default();
            let owner = owner.trim();
            return Err(io::Error::new(
                io::ErrorKind::AddrInUse,
                format!(
                    "run {} is already being trained{}: {error}",
                    dir.display(),
                    if owner.is_empty() {
                        String::new()
                    } else {
                        format!(" by process {owner}")
                    }
                ),
            ));
        }
        // Recorded for the operator's benefit only; nothing depends on it.
        let owner = std::process::id();
        let mut file = file;
        file.set_len(0)?;
        writeln!(file, "{owner}")?;
        file.flush()?;
        Ok(RunLock { _file: file, owner })
    }

    /// The process id recorded in the lock file.
    pub fn owner(&self) -> u32 {
        self.owner
    }
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
        // `serde_json::to_writer` emits a document as a stream of very small
        // writes, one per token and per separator. Handed a `File` those are
        // syscalls, so a twenty megabyte checkpoint costs millions of them and
        // the trainer's main thread spends a whole generation in the kernel
        // while its workers sit idle. A modest fixed buffer turns them into
        // whole-block writes without changing a single byte of the output.
        let mut writer = io::BufWriter::with_capacity(1 << 16, File::create(&temporary)?);
        serde_json::to_writer(&mut writer, value)?;
        writer.write_all(b"\n")?;
        // Flushed EXPLICITLY, never by `Drop`: a dropped `BufWriter` discards
        // the error from its final write, which would turn a full disk into a
        // checkpoint that looks written and then gets renamed over the last
        // good one. Only once every byte is in the file does durability, and
        // then the atomic replacement, mean anything.
        writer.flush()?;
        let file = writer.into_inner().map_err(|e| e.into_error())?;
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

    /// A checkpoint-sized document, big enough that the difference between a
    /// syscall per token and a syscall per block is the difference between a
    /// stalled generation and an unnoticed one.
    fn bulky() -> Value {
        let genomes: Vec<Value> = (0..4000)
            .map(|g| {
                json!({
                    "id": g,
                    "fitness": g as f64 * 1.5,
                    "species": g % 37,
                    "name": format!("genome-{g}"),
                    "connections": (0..40)
                        .map(|c| json!({
                            "from": c,
                            "to": c + 1,
                            "weight": (g * c) as f64 / 7.0,
                            "enabled": c % 3 != 0,
                        }))
                        .collect::<Vec<_>>(),
                })
            })
            .collect();
        json!({"generation": 12345, "population": genomes})
    }

    #[test]
    fn a_large_checkpoint_lands_byte_for_byte() {
        // Buffering may not alter one byte of the document: a checkpoint has
        // to read back as the same run it was saved from.
        let dir = scratch("bytes");
        let path = dir.join("checkpoint.json");
        let value = bulky();
        write_atomic(&path, &value).unwrap();

        let mut expected = serde_json::to_vec(&value).unwrap();
        expected.push(b'\n');
        let written = fs::read(&path).unwrap();
        assert!(
            written.len() > 1_000_000,
            "the case is only interesting at checkpoint scale, got {} bytes",
            written.len()
        );
        assert_eq!(written, expected, "the written bytes differ from the document");
        assert_eq!(read_json(&path).unwrap(), value);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn repeated_large_writes_replace_the_whole_document() {
        // The real cadence: the same path overwritten generation after
        // generation, never leaving a temporary behind or a shortened tail
        // from a previous, longer save.
        let dir = scratch("repeat");
        let path = dir.join("checkpoint.json");
        for generation in 0..3 {
            let mut value = bulky();
            value["generation"] = json!(generation);
            // Shrinking, so a stale tail from the previous write would show.
            value["population"] = json!(value["population"]
                .as_array()
                .unwrap()
                .iter()
                .take(4000 - generation * 1200)
                .cloned()
                .collect::<Vec<_>>());
            write_atomic(&path, &value).unwrap();

            let mut expected = serde_json::to_vec(&value).unwrap();
            expected.push(b'\n');
            assert_eq!(fs::read(&path).unwrap(), expected);
            assert_eq!(read_json(&path).unwrap(), value);
            assert!(!dir.join("checkpoint.json.tmp").exists());
        }
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_failed_write_leaves_the_last_good_checkpoint_in_place() {
        use std::os::unix::fs::PermissionsExt;

        let dir = scratch("failed");
        let path = dir.join("checkpoint.json");
        let good = json!({"generation": 7, "population": ["kept"]});
        write_atomic(&path, &good).unwrap();

        // A directory that cannot be written to is the honest version of a
        // failing save: no mock, the real syscall refuses.
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o555)).unwrap();
        let outcome = write_atomic(&path, &json!({"generation": 8}));
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).unwrap();

        assert!(outcome.is_err(), "a save that cannot be written must say so");
        assert_eq!(
            read_json(&path).unwrap(),
            good,
            "a failed save destroyed the checkpoint it was replacing"
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_second_live_instance_cannot_claim_the_same_run() {
        let dir = scratch("lock");
        let first = RunLock::acquire(&dir).unwrap();
        assert_eq!(first.owner(), std::process::id());
        for _ in 0..5 {
            assert!(
                RunLock::acquire(&dir).is_err(),
                "two trainers claimed one run"
            );
        }
        drop(first);
        // Released, so the run can be resumed.
        let third = RunLock::acquire(&dir).unwrap();
        drop(third);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn two_simultaneous_resumes_cannot_both_win() {
        // The old pid-file scheme lost exactly here: both racers read the same
        // dead owner and both decided the lock was stale.
        let dir = scratch("race");
        fs::write(dir.join(LOCK), "999999999\n").unwrap();
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
        let winners = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let held = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let mut racers = Vec::new();
        for _ in 0..8 {
            let (dir, barrier, winners, held) = (
                dir.clone(),
                barrier.clone(),
                winners.clone(),
                held.clone(),
            );
            racers.push(std::thread::spawn(move || {
                barrier.wait();
                if let Ok(lock) = RunLock::acquire(&dir) {
                    winners.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    // Hold it, so a later winner would overlap with this one.
                    held.lock().unwrap().push(lock);
                }
            }));
        }
        for racer in racers {
            racer.join().unwrap();
        }
        assert_eq!(
            winners.load(std::sync::atomic::Ordering::SeqCst),
            1,
            "more than one process would have written this checkpoint"
        );
        held.lock().unwrap().clear();
        // And once the winner is gone the run is resumable again.
        drop(RunLock::acquire(&dir).expect("a released run must be resumable"));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_lock_left_by_a_dead_process_does_not_block_a_resume() {
        let dir = scratch("stale");
        // A crash closes the descriptor, which is what releasing looks like.
        drop(RunLock::acquire(&dir).unwrap());
        assert!(dir.join(LOCK).exists(), "the lock file must persist");
        let lock = RunLock::acquire(&dir).expect("a dead owner must not block a resume");
        drop(lock);
        fs::remove_dir_all(&dir).unwrap();
    }
}
