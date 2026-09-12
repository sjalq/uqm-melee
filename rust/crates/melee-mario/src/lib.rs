//! MarI/O-style topology evolution for UQM Super Melee.
//!
//! The genome wire schema, the compiled graph runtime and the oracle are the
//! parts other languages depend on; everything else (evolution, the board and
//! its sampling, the balanced gate, checkpointing, the loopback dashboard
//! server) sits on top of them.

pub mod brain;
pub mod audit;
pub mod benchmark;
pub mod broad;
pub mod checkpoint;
pub mod cli;
pub mod episode;
pub mod genome;
pub mod graph;
pub mod neat;
pub mod oracle;
pub mod phases;
pub mod pool;
pub mod rng;
pub mod sampler;
pub mod server;
pub mod status;
pub mod store;
pub mod trainer;
