#![cfg_attr(target_arch = "nvptx64", no_std)]

//! Bit-exact Rust mirror of the UQM Super Melee simulation in `src/Melee/`.

extern crate alloc;

pub mod arsenal;
pub mod art;
pub mod catalog;
#[rustfmt::skip]
pub mod catalog_generated;
pub mod battle;
pub mod cyborg;
pub mod element;
pub mod energy;
pub mod init;
pub mod input;
pub mod masks;
#[rustfmt::skip]
pub mod masks_generated;
pub mod motion;
pub mod rate;
pub mod ship_state;
pub mod step;

pub use catalog::{ShipKind, MELEE_SHIP_COUNT};
