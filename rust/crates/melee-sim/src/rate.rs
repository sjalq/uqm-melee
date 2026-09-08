//! `src/Melee/Rate.elm`. The 60 Hz display-clock to 24 Hz battle-clock pump.

pub const C_BATTLE_FRAMES_PER_SECOND: i64 = 24;
pub const DISPLAY_HZ: i64 = 60;

#[inline]
pub fn advance_pump(acc: i64) -> (i64, i64) {
    let mut remaining = acc + C_BATTLE_FRAMES_PER_SECOND;
    let mut frames = 0;
    while remaining >= DISPLAY_HZ {
        remaining -= DISPLAY_HZ;
        frames += 1;
    }
    (frames, remaining)
}

pub fn repeat<T>(count: i64, mut step: impl FnMut(T) -> T, mut value: T) -> T {
    for _ in 0..count.max(0) {
        value = step(value);
    }
    value
}
