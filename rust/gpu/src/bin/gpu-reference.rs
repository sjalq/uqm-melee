use std::{env, fs, time::Instant};
fn main() {
    let args: Vec<String> = env::args().collect();
    let arg = |name: &str| args.windows(2).find(|p| p[0] == name).expect(name)[1].clone();
    let jobs: u32 = arg("--jobs").parse().unwrap();
    let ticks: u32 = arg("--ticks").parse().unwrap();
    let stride: u32 = arg("--stride").parse().unwrap();
    let out = arg("--out");
    if args.iter().any(|a| a == "--bench") {
        let start = Instant::now();
        let values: Vec<u64> = (0..jobs).map(|job| melee_gpu::bench(job, ticks)).collect();
        eprintln!("cpu_seconds={:.9}", start.elapsed().as_secs_f64());
        fs::write(
            out,
            values
                .iter()
                .flat_map(|n| n.to_le_bytes())
                .collect::<Vec<_>>(),
        )
        .unwrap();
        return;
    }
    let mut bytes = vec![0u8; jobs as usize * ticks as usize * stride as usize];
    let mut lengths = vec![0u64; jobs as usize * ticks as usize];
    let start = Instant::now();
    for job in 0..jobs {
        unsafe {
            melee_gpu::replay(bytes.as_mut_ptr(), lengths.as_mut_ptr(), job, ticks, stride);
        }
    }
    eprintln!("cpu_seconds={:.9}", start.elapsed().as_secs_f64());
    assert!(
        lengths.iter().all(|&n| n <= stride as u64),
        "state exceeds stride"
    );
    fs::write(&out, bytes).unwrap();
    fs::write(
        format!("{}.lengths", out),
        lengths
            .iter()
            .flat_map(|n| n.to_le_bytes())
            .collect::<Vec<_>>(),
    )
    .unwrap();
}
