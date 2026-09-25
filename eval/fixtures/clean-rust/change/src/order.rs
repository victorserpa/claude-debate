pub struct Line { pub qty: u32, pub unit_cents: u64 }

fn line_cents(l: &Line) -> u64 {
    l.unit_cents * l.qty as u64
}

pub fn total_cents(lines: &[Line]) -> u64 {
    lines.iter().map(line_cents).sum()
}
