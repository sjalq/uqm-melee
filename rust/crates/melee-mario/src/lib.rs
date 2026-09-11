//! MarI/O-style topology evolution for UQM Super Melee.
//!
//! The genome wire schema, the compiled graph runtime and the oracle are the
//! parts other languages depend on; everything else (evolution, curriculum,
//! sampling, auditing, checkpointing, the loopback dashboard server) sits on
//! top of them.

pub mod brain;
pub mod genome;
pub mod graph;
pub mod oracle;
