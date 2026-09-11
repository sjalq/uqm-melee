#![cfg_attr(target_arch = "nvptx64", no_std)]
#![cfg_attr(
    target_arch = "nvptx64",
    feature(abi_ptx, stdarch_nvptx, asm_experimental_arch, alloc_error_handler)
)]

use core::hash::{Hash, Hasher};
use melee_core::{rng::Seed, units::Sided};
use melee_sim::{
    catalog::ShipKind,
    init,
    input::{BattleInput, Turn},
    step,
};

#[cfg(target_arch = "nvptx64")]
mod device {
    use core::alloc::{GlobalAlloc, Layout};
    struct DeviceAllocator;
    unsafe impl GlobalAlloc for DeviceAllocator {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            if layout.align() > 16 {
                return core::ptr::null_mut();
            }
            core::arch::nvptx::malloc(layout.size()) as *mut u8
        }
        unsafe fn dealloc(&self, ptr: *mut u8, _: Layout) {
            core::arch::nvptx::free(ptr.cast());
        }
    }
    #[global_allocator]
    static ALLOCATOR: DeviceAllocator = DeviceAllocator;
    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo) -> ! {
        unsafe {
            core::arch::asm!("trap;", options(noreturn));
        }
    }
    #[alloc_error_handler]
    fn oom(_: Layout) -> ! {
        unsafe {
            core::arch::asm!("trap;", options(noreturn));
        }
    }
}

/// Canonical state bytes emitted by derived Hash implementations; never copies
/// struct padding or process-specific pointers. Host and device are little-endian
/// 64-bit targets and share these exact field traversal implementations.
struct StateBytes {
    output: *mut u8,
    capacity: usize,
    written: usize,
}
impl Hasher for StateBytes {
    fn finish(&self) -> u64 {
        0
    }
    #[inline(never)]
    fn write(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            if self.written < self.capacity {
                unsafe {
                    self.output.add(self.written).write(byte);
                }
            }
            self.written += 1;
        }
    }
}

pub fn controls(job: u32, tick: u32, top: bool) -> BattleInput {
    let t = tick + if top { 37 } else { job * 13 };
    BattleInput {
        turn: match (t / 17) % 3 {
            0 => Turn::TurnLeft,
            1 => Turn::TurnRight,
            _ => Turn::NoTurn,
        },
        thrust: t % 31 < 24,
        weapon: t % 19 < 16,
        special: t % 47 < 7,
    }
}

/// One independent full simulation per GPU thread. There are no host transfers
/// between game ticks. The first probe uses the live training ship pool.
pub unsafe fn replay(output: *mut u8, lengths: *mut u64, job: u32, ticks: u32, stride: u32) {
    let ships = [ShipKind::Pkunk, ShipKind::Umgah, ShipKind::Yehat];
    let mut arena = init::arena(
        ships[(job as usize / 3) % 3],
        ships[job as usize % 3],
        Seed(42 + job as i64 * 1701),
    );
    for tick in 0..ticks {
        step::tick_authoritative(
            Sided {
                bottom: controls(job, tick, false),
                top: controls(job, tick, true),
            },
            &mut arena,
        );
        let index = job as usize * ticks as usize + tick as usize;
        let mut sink = StateBytes {
            output: output.add(index * stride as usize),
            capacity: stride as usize,
            written: 0,
        };
        arena.hash(&mut sink);
        lengths.add(index).write(sink.written as u64);
    }
}

#[cfg(target_arch = "nvptx64")]
#[no_mangle]
pub unsafe extern "ptx-kernel" fn game_replay(
    output: *mut u8,
    lengths: *mut u64,
    jobs: u32,
    ticks: u32,
    stride: u32,
) {
    use core::arch::nvptx::{_block_dim_x, _block_idx_x, _thread_idx_x};
    let job = (_block_idx_x() * _block_dim_x() + _thread_idx_x()) as u32;
    if job < jobs {
        replay(output, lengths, job, ticks, stride);
    }
}

struct Digest(u64);
impl Hasher for Digest {
    fn finish(&self) -> u64 {
        self.0
    }
    #[inline(never)]
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0 ^ b as u64).wrapping_mul(1099511628211);
        }
    }
}
pub fn bench(job: u32, ticks: u32) -> u64 {
    let ships = [ShipKind::Pkunk, ShipKind::Umgah, ShipKind::Yehat];
    let mut arena = init::arena(
        ships[(job as usize / 3) % 3],
        ships[job as usize % 3],
        Seed(42 + job as i64 * 1701),
    );
    for tick in 0..ticks {
        step::tick_authoritative(
            Sided {
                bottom: controls(job, tick, false),
                top: controls(job, tick, true),
            },
            &mut arena,
        );
    }
    let mut hash = Digest(14695981039346656037);
    arena.hash(&mut hash);
    hash.finish()
}
#[cfg(target_arch = "nvptx64")]
#[no_mangle]
pub unsafe extern "ptx-kernel" fn game_bench(output: *mut u64, jobs: u32, ticks: u32) {
    use core::arch::nvptx::{_block_dim_x, _block_idx_x, _thread_idx_x};
    let job = (_block_idx_x() * _block_dim_x() + _thread_idx_x()) as u32;
    if job < jobs {
        output.add(job as usize).write(bench(job, ticks));
    }
}
