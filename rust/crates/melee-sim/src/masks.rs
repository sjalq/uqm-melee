//! `src/Melee/Masks.elm`. Original sprite collision masks, run-length encoded
//! per row. The mask bodies live in `masks_generated.rs`; this module holds the
//! literal port of `opaque` and `overlap`.

use crate::masks_generated::{MASK_ROWS, MASK_SPANS};

/// One sprite mask. `rows` are stored out of line in `MASK_ROWS`/`MASK_SPANS`
/// so the whole table is a handful of flat, cache-friendly arrays.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub struct Mask {
    pub width: i64,
    pub height: i64,
    pub x: i64,
    pub y: i64,
    pub row_start: u32,
    pub row_count: u32,
}

impl Mask {
    /// Inclusive opaque spans of row `y`. Out-of-range rows are empty, matching
    /// Elm's `Array.get ... |> Maybe.withDefault []`.
    #[inline]
    pub fn row(&self, y: i64) -> &'static [(i16, i16)] {
        if y < 0 || y >= self.row_count as i64 {
            return &[];
        }
        let (start, len) = MASK_ROWS[self.row_start as usize + y as usize];
        &MASK_SPANS[start as usize..start as usize + len as usize]
    }

    /// `Melee.Masks.opaque`.
    pub fn opaque(&self, x: i64, y: i64) -> bool {
        let px = x + self.x;
        self.row(y + self.y)
            .iter()
            .any(|&(a, b)| px >= a as i64 && px <= b as i64)
    }
}

/// `Melee.Masks.overlap`. Literal transcription: the span test is
/// `x0 <= z1 + left && x1 >= z0 + left`, walked row by row from `first` to
/// `last`.
pub fn overlap(a: &Mask, b: &Mask, dx: i64, dy: i64) -> bool {
    let left = dx + a.x - b.x;
    let top = dy + a.y - b.y;
    let first = top.max(0);
    let last = (a.height - 1).min(top + b.height - 1);

    if !(left < a.width && left + b.width > 0 && first <= last) {
        return false;
    }

    for y in first..=last {
        let ar = a.row(y);
        if ar.is_empty() {
            continue;
        }
        let br = b.row(y - top);
        if br.is_empty() {
            continue;
        }
        for &(x0, x1) in ar {
            let (x0, x1) = (x0 as i64, x1 as i64);
            for &(z0, z1) in br {
                if x0 <= z1 as i64 + left && x1 >= z0 as i64 + left {
                    return true;
                }
            }
        }
    }
    false
}
