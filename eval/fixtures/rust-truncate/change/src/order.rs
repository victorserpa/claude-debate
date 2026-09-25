pub struct Line { pub sku: String, pub qty: u32, pub unit_cents: u64 }

// Quantities fit in a byte on the order line.
fn stored_qty(l: &Line) -> u8 { l.qty as u8 }

pub fn total_cents(lines: &[Line]) -> u64 {
    lines.iter().map(|l| l.unit_cents * stored_qty(l) as u64).sum()
}

pub fn ship(lines: &[Line]) -> Vec<(String, u32)> {
    lines.iter().map(|l| (l.sku.clone(), l.qty)).collect()
}
