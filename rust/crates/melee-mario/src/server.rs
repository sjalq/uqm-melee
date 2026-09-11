//! A loopback-only dashboard server.
//!
//! Three properties are deliberate:
//!
//!   * It binds 127.0.0.1 and nothing else. There is no flag that turns this
//!     into a public listener.
//!   * It never joins a caller-supplied path onto the filesystem. Static
//!     routes are a fixed table of exactly two entries, matched on the whole
//!     request target, so directory traversal is not merely blocked, it is
//!     unrepresentable.
//!   * It never computes anything. The trainer thread publishes rendered
//!     documents and the server hands out the latest one, so requests stay
//!     fast while a fight is being simulated and keep working while paused.

use serde_json::Value;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const DEFAULT_PORT: u16 = 8788;
pub const LOOPBACK: Ipv4Addr = Ipv4Addr::LOCALHOST;

/// The only files served, and the only place they may come from.
const STATIC_ROUTES: [(&str, &str, &str); 3] = [
    ("/", "index.html", "text/html; charset=utf-8"),
    ("/index.html", "index.html", "text/html; charset=utf-8"),
    (
        "/dashboard.js",
        "dashboard.js",
        "text/javascript; charset=utf-8",
    ),
];

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum Control {
    Run = 0,
    Pause = 1,
    Stop = 2,
}

impl Control {
    fn from_u8(raw: u8) -> Control {
        match raw {
            1 => Control::Pause,
            2 => Control::Stop,
            _ => Control::Run,
        }
    }
}

/// Rendered documents plus the control flag. Cloning a handle is cheap; the
/// lock is held only long enough to swap or read an `Arc<String>`.
#[derive(Clone)]
pub struct Shared {
    documents: Arc<Mutex<Documents>>,
    control: Arc<AtomicU8>,
    assets: Arc<PathBuf>,
}

struct Documents {
    status: Arc<String>,
    network: Arc<String>,
}

impl Shared {
    pub fn new(assets: PathBuf) -> Shared {
        Shared {
            documents: Arc::new(Mutex::new(Documents {
                status: Arc::new("{}".into()),
                network: Arc::new("{}".into()),
            })),
            control: Arc::new(AtomicU8::new(Control::Run as u8)),
            assets: Arc::new(assets),
        }
    }

    pub fn publish(&self, status: &Value, network: &Value) {
        let status = Arc::new(status.to_string());
        let network = Arc::new(network.to_string());
        if let Ok(mut held) = self.documents.lock() {
            held.status = status;
            held.network = network;
        }
    }

    pub fn control(&self) -> Control {
        Control::from_u8(self.control.load(Ordering::SeqCst))
    }

    pub fn set_control(&self, control: Control) {
        self.control.store(control as u8, Ordering::SeqCst);
    }

    fn documents(&self) -> (Arc<String>, Arc<String>) {
        match self.documents.lock() {
            Ok(held) => (held.status.clone(), held.network.clone()),
            Err(poisoned) => {
                let held = poisoned.into_inner();
                (held.status.clone(), held.network.clone())
            }
        }
    }
}

pub fn bind(port: u16) -> std::io::Result<TcpListener> {
    TcpListener::bind(SocketAddr::from((LOOPBACK, port)))
}

/// Serves until the process ends. Each connection is handled on its own
/// short-lived thread with timeouts, so one stalled client cannot delay
/// another request or the trainer.
pub fn serve(listener: TcpListener, shared: Shared) {
    for stream in listener.incoming() {
        let Ok(stream) = stream else { continue };
        let shared = shared.clone();
        std::thread::spawn(move || {
            let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
            let _ = stream.set_write_timeout(Some(Duration::from_secs(5)));
            let _ = handle(stream, &shared);
        });
    }
}

fn handle(mut stream: TcpStream, shared: &Shared) -> std::io::Result<()> {
    let peer = stream.peer_addr()?;
    // Belt and braces: the socket is bound to loopback, and anything that
    // somehow arrives from elsewhere is refused rather than answered.
    if !peer.ip().is_loopback() {
        return respond(&mut stream, 403, "text/plain", b"loopback only");
    }
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut request = String::new();
    if reader.read_line(&mut request)? == 0 {
        return Ok(());
    }
    let mut parts = request.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let target = parts.next().unwrap_or("").to_string();

    let mut length = 0usize;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some(raw) = line
            .strip_prefix("Content-Length:")
            .or_else(|| line.strip_prefix("content-length:"))
        {
            length = raw.trim().parse().unwrap_or(0);
        }
    }
    // A body larger than this is not a control message.
    let length = length.min(4096);
    let mut body = vec![0u8; length];
    if length > 0 {
        reader.read_exact(&mut body)?;
    }

    // The query string is ignored entirely; routing is on the path alone.
    let path = target.split('?').next().unwrap_or("/").to_string();
    match (method.as_str(), path.as_str()) {
        ("GET", "/api/status") => {
            let (status, _) = shared.documents();
            respond(&mut stream, 200, "application/json", status.as_bytes())
        }
        ("GET", "/api/network") => {
            let (_, network) = shared.documents();
            respond(&mut stream, 200, "application/json", network.as_bytes())
        }
        ("POST", "/api/control") => {
            let answer = control(shared, &body);
            respond(&mut stream, 200, "application/json", answer.as_bytes())
        }
        ("GET", _) | ("HEAD", _) => match STATIC_ROUTES.iter().find(|(route, _, _)| *route == path) {
            None => respond(&mut stream, 404, "text/plain", b"not found"),
            Some((_, file, kind)) => match std::fs::read(shared.assets.join(file)) {
                Ok(bytes) => respond(&mut stream, 200, kind, &bytes),
                Err(_) => respond(
                    &mut stream,
                    404,
                    "text/plain",
                    format!(
                        "{file} is not built yet; run scripts/mario/build.sh to produce it"
                    )
                    .as_bytes(),
                ),
            },
        },
        _ => respond(&mut stream, 405, "text/plain", b"method not allowed"),
    }
}

/// Accepts exactly three actions and nothing else, so a malformed or hostile
/// body can only ever be rejected.
fn control(shared: &Shared, body: &[u8]) -> String {
    let parsed: Option<Value> = serde_json::from_slice(body).ok();
    let action = parsed
        .as_ref()
        .and_then(|v| v.get("action"))
        .and_then(Value::as_str)
        .unwrap_or("");
    let accepted = match action {
        "pause" => Some(Control::Pause),
        "resume" => Some(Control::Run),
        "stop" => Some(Control::Stop),
        _ => None,
    };
    match accepted {
        None => {
            "{\"ok\":false,\"error\":\"action must be pause, resume or stop\"}".to_string()
        }
        Some(control) => {
            shared.set_control(control);
            format!("{{\"ok\":true,\"action\":\"{action}\"}}")
        }
    }
}

fn respond(stream: &mut TcpStream, code: u16, kind: &str, body: &[u8]) -> std::io::Result<()> {
    let reason = match code {
        200 => "OK",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        _ => "Error",
    };
    write!(
        stream,
        "HTTP/1.1 {code} {reason}\r\nContent-Type: {kind}\r\nContent-Length: {}\r\n\
         Cache-Control: no-store\r\nConnection: close\r\n\r\n",
        body.len()
    )?;
    stream.write_all(body)?;
    stream.flush()
}

/// Minimal loopback client used by the `pause`, `resume` and `stop` commands.
pub fn post_control(port: u16, action: &str) -> std::io::Result<String> {
    let body = format!("{{\"action\":\"{action}\"}}");
    let mut stream = TcpStream::connect(SocketAddr::from((LOOPBACK, port)))?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    write!(
        stream,
        "POST /api/control HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n\
         Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )?;
    stream.flush()?;
    let mut answer = String::new();
    stream.read_to_string(&mut answer)?;
    Ok(answer.rsplit("\r\n\r\n").next().unwrap_or("").to_string())
}

pub fn get(port: u16, path: &str) -> std::io::Result<String> {
    let mut stream = TcpStream::connect(SocketAddr::from((LOOPBACK, port)))?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    write!(
        stream,
        "GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
    )?;
    stream.flush()?;
    let mut answer = String::new();
    stream.read_to_string(&mut answer)?;
    Ok(answer.rsplit("\r\n\r\n").next().unwrap_or("").to_string())
}

pub fn asset_dir(root: &Path) -> PathBuf {
    root.join("scripts").join("mario")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn started() -> (u16, Shared) {
        let dir = std::env::temp_dir().join(format!("mario-assets-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("index.html"), b"<h1>mission control</h1>").unwrap();
        std::fs::write(dir.join("dashboard.js"), b"// built elm").unwrap();
        let shared = Shared::new(dir);
        shared.publish(
            &json!({"schema_version": 1, "phase": "training"}),
            &json!({"schema_version": 1, "champion_id": "g1"}),
        );
        let listener = bind(0).unwrap();
        let port = listener.local_addr().unwrap().port();
        let clone = shared.clone();
        std::thread::spawn(move || serve(listener, clone));
        (port, shared)
    }

    #[test]
    fn it_serves_the_api_the_allowed_assets_and_nothing_else() {
        let (port, shared) = started();
        assert!(get(port, "/api/status").unwrap().contains("\"training\""));
        assert!(get(port, "/api/network").unwrap().contains("g1"));
        assert!(get(port, "/").unwrap().contains("mission control"));
        assert!(get(port, "/dashboard.js").unwrap().contains("built elm"));
        // A query string must not change routing.
        assert!(get(port, "/api/status?t=1").unwrap().contains("training"));

        // Nothing outside the two-entry table is reachable, traversal included.
        for attempt in [
            "/../../../etc/passwd",
            "/..%2f..%2fetc/passwd",
            "/index.html/../dashboard.js",
            "/checkpoint.json",
            "/scripts/mario/index.html",
            "//etc/passwd",
            "/.env",
        ] {
            let answer = get(port, attempt).unwrap();
            assert_eq!(answer, "not found", "route {attempt} was served");
        }
        drop(shared);
    }

    #[test]
    fn control_accepts_only_the_three_declared_actions() {
        let (port, shared) = started();
        assert!(post_control(port, "pause").unwrap().contains("\"ok\":true"));
        assert_eq!(shared.control(), Control::Pause);
        assert!(post_control(port, "resume").unwrap().contains("\"ok\":true"));
        assert_eq!(shared.control(), Control::Run);
        assert!(post_control(port, "stop").unwrap().contains("\"ok\":true"));
        assert_eq!(shared.control(), Control::Stop);

        shared.set_control(Control::Run);
        for bogus in ["delete", "", "PAUSE", "stop; rm -rf /"] {
            let answer = post_control(port, bogus).unwrap();
            assert!(answer.contains("\"ok\":false"), "accepted {bogus:?}");
        }
        assert_eq!(shared.control(), Control::Run);
    }

    #[test]
    fn published_documents_are_served_without_blocking_on_the_trainer() {
        let (port, shared) = started();
        // Simulate the trainer republishing while requests are in flight.
        let writer = shared.clone();
        let pump = std::thread::spawn(move || {
            for generation in 0..200 {
                writer.publish(
                    &json!({"schema_version": 1, "generation": generation}),
                    &json!({"schema_version": 1}),
                );
            }
        });
        for _ in 0..20 {
            assert!(get(port, "/api/status").unwrap().contains("generation"));
        }
        pump.join().unwrap();
    }
}
