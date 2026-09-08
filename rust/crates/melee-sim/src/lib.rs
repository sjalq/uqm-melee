//! Bit-exact Rust mirror of the UQM Super Melee simulation in `src/Melee/`.

pub mod catalog;
#[rustfmt::skip]
pub mod catalog_generated;
pub mod element;
pub mod masks;
#[rustfmt::skip]
pub mod masks_generated;

pub use catalog::{ShipKind, MELEE_SHIP_COUNT};
