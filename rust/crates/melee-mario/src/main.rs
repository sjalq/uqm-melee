use std::io::{self, BufWriter};

fn main() -> io::Result<()> {
    let mut out = BufWriter::new(io::stdout().lock());
    melee_mario::oracle::run(io::stdin().lock(), &mut out)
}
