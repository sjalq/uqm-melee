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

    /// A SHARED claim on a run directory.
    ///
    /// Several readers may hold one at once, but none can be taken while a
    /// trainer holds the exclusive claim, so a copy made under it can never
    /// observe a half-written checkpoint. It writes NOTHING: the lock file's
    /// bytes, including whatever pid the last owner recorded, are left exactly
    /// as they were, which is what lets a source run be forked without being
    /// modified in any way.
    pub fn acquire_shared(dir: &Path) -> io::Result<RunLock> {
        let path = dir.join(LOCK);
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&path)?;
        // Safety: as in `acquire`; flock only associates a lock with a valid,
        // owned descriptor.
        let locked = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_SH | libc::LOCK_NB) };
        if locked != 0 {
            let error = io::Error::last_os_error();
            let owner = fs::read_to_string(&path).unwrap_or_default();
            let owner = owner.trim().to_string();
            return Err(io::Error::new(
                io::ErrorKind::AddrInUse,
                format!(
                    "run {} is being trained right now{}, so its state is still changing: {error}",
                    dir.display(),
                    if owner.is_empty() {
                        String::new()
                    } else {
                        format!(" by process {owner}")
                    }
                ),
            ));
        }
        Ok(RunLock { _file: file, owner: 0 })
    }

    /// The process id recorded in the lock file, or zero for a shared claim,
    /// which never writes one.
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
    fn a_shared_claim_reads_alongside_readers_but_never_beside_a_trainer() {
        let dir = scratch("shared");
        fs::write(dir.join(LOCK), "4242\n").unwrap();
        // Several readers at once is the point of it.
        let first = RunLock::acquire_shared(&dir).unwrap();
        let second = RunLock::acquire_shared(&dir).unwrap();
        assert_eq!(first.owner(), 0);
        // And the bytes the last trainer wrote are untouched, so forking a run
        // leaves the source exactly as it was found.
        assert_eq!(fs::read_to_string(dir.join(LOCK)).unwrap(), "4242\n");
        // A trainer cannot start while a copy is being read.
        assert!(RunLock::acquire(&dir).is_err());
        drop((first, second));

        // And a copy cannot be read while a trainer is writing.
        let trainer = RunLock::acquire(&dir).unwrap();
        assert!(RunLock::acquire_shared(&dir).is_err());
        drop(trainer);
        drop(RunLock::acquire_shared(&dir).expect("a stopped run must be readable"));
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
