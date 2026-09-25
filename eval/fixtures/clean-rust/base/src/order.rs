pub struct Line { pub qty: u32, pub unit_cents: u64 }

pub fn total_cents(lines: &[Line]) -> u64 {
    lines.iter().map(|l| l.unit_cents * l.qty as u64).sum()
}
