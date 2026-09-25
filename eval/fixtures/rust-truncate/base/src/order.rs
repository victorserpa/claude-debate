pub struct Line { pub sku: String, pub qty: u32, pub unit_cents: u64 }

pub fn total_cents(lines: &[Line]) -> u64 {
    lines.iter().map(|l| l.unit_cents * l.qty as u64).sum()
}

pub fn ship(lines: &[Line]) -> Vec<(String, u32)> {
    lines.iter().map(|l| (l.sku.clone(), l.qty)).collect()
}
