//! Rust half of the collision-mask differential oracle. Emits byte-for-byte the
//! same dump as `tests/Oracle/MaskChecks.elm`.

use melee_sim::catalog::{MissileKind, ShipKind, ALL_SHIPS};
use melee_sim::element::Body;
use melee_sim::masks::{overlap, Mask};
use melee_sim::masks_generated::{projectile_mask, ship_mask};

fn main() {
    let probes = probes();
    let mut lines: Vec<String> = probes.iter().map(opaque_row).collect();
    lines.extend(overlap_rows(&probes));
    println!("{}", lines.join("\n"));
}

type Probe = (String, Option<&'static Mask>);

fn probes() -> Vec<Probe> {
    let mut out: Vec<Probe> = Vec::new();
    for kind in ALL_SHIPS {
        for facing in [0i64, 3, 7, 11] {
            out.push((
                format!("ship:{}:{}", ship_tag(kind), facing),
                ship_mask(kind, false, facing),
            ));
        }
    }
    for (name, body) in projectile_probes() {
        for frame in [0i64, 1, 5] {
            out.push((format!("proj:{name}:{frame}"), projectile_mask(body, frame)));
        }
    }
    out
}

/// Matches the `projectileProbes` list in the Elm oracle, including its ordering.
fn projectile_probes() -> Vec<(&'static str, Body)> {
    vec![
        ("PkunkSpread", Body::PkunkSpread),
        ("UmgahCone", Body::UmgahCone),
        ("YehatMissile", Body::YehatMissile),
        ("ChenjesuDogi", Body::ChenjesuDogi),
        ("KohrAhSaw", Body::KohrAhSaw),
        ("MyconPlasma", Body::MyconPlasma),
        ("EarthlingNuke", Body::EarthlingNuke),
        ("VuxLimpet", Body::VuxLimpet),
        ("ChmmrSatellite", Body::ChmmrSatellite { orbit_facing: 0 }),
        ("WeaponImpact:Bug", Body::WeaponImpact(MissileKind::Bug)),
    ]
}

fn offsets() -> Vec<i64> {
    (0..=18).map(|i| i * 7 - 63).collect()
}

fn opaque_row((name, mask): &Probe) -> String {
    match mask {
        None => format!("opaque {name} none"),
        Some(m) => {
            let mut values = Vec::with_capacity(41 * 41);
            for y in -20..=20i64 {
                for x in -20..=20i64 {
                    values.push(m.opaque(x, y));
                }
            }
            format!("opaque {name} {}x{}@{},{} {}", m.width, m.height, m.x, m.y, bits(&values))
        }
    }
}

fn overlap_rows(probes: &[Probe]) -> Vec<String> {
    let offsets = offsets();
    let mut out = Vec::new();
    for (i, (name_a, a)) in probes.iter().enumerate() {
        for (j, (name_b, b)) in probes.iter().enumerate() {
            if (i + j) % 4 != 0 {
                continue;
            }
            let body = match (a, b) {
                (Some(ma), Some(mb)) => {
                    let mut values = Vec::with_capacity(offsets.len() * offsets.len());
                    for &dy in &offsets {
                        for &dx in &offsets {
                            values.push(overlap(ma, mb, dx, dy));
                        }
                    }
                    bits(&values)
                }
                _ => "none".to_string(),
            };
            out.push(format!("overlap {name_a} {name_b} {body}"));
        }
    }
    out
}

/// Packs booleans into hex nibbles, padding the final nibble the way the Elm
/// oracle does (shift the pending bits up to the high end of the nibble).
fn bits(values: &[bool]) -> String {
    let mut out = String::with_capacity(values.len() / 4 + 1);
    let mut pending = 0u32;
    let mut count = 0u32;
    for &v in values {
        pending = pending * 2 + v as u32;
        if count == 3 {
            out.push(char::from_digit(pending, 16).unwrap());
            pending = 0;
            count = 0;
        } else {
            count += 1;
        }
    }
    if count != 0 {
        out.push(char::from_digit(pending << (4 - count), 16).unwrap());
    }
    out
}

fn ship_tag(kind: ShipKind) -> &'static str {
    use ShipKind::*;
    match kind {
        Androsynth => "Androsynth",
        Arilou => "Arilou",
        Chenjesu => "Chenjesu",
        Chmmr => "Chmmr",
        Druuge => "Druuge",
        Earthling => "Earthling",
        Ilwrath => "Ilwrath",
        KohrAh => "KohrAh",
        Melnorme => "Melnorme",
        Mmrnmhrm => "Mmrnmhrm",
        Mycon => "Mycon",
        Orz => "Orz",
        Pkunk => "Pkunk",
        Shofixti => "Shofixti",
        Slylandro => "Slylandro",
        Spathi => "Spathi",
        Supox => "Supox",
        Syreen => "Syreen",
        Thraddash => "Thraddash",
        Umgah => "Umgah",
        UrQuan => "UrQuan",
        Utwig => "Utwig",
        Vux => "Vux",
        Yehat => "Yehat",
        ZoqFotPik => "ZoqFotPik",
    }
}
