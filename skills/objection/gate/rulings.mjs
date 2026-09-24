// Every finding the accusation numbers must get a ruling from the judge.
// Shared by stamp.sh (node rulings.mjs <record>) and check-pr.mjs.
//
// A numbered finding is a line of the Accusation section that starts with
// "N." (a list) or "| N |" (the table debate.sh numbers). A numbered step
// in prose counts too: asking for one ruling too many fails closed, and
// requiring a severity word on the line would let a finding through. A ruling is a
// line of the Judge section that starts with "N." / "N)" / "N:", a range
// "N-M.", or a list "1, 2 and 5:" covering it, or a table row "| N |".
// Anything else in the text
// is free-form.

export function missingRulings(text) {
  const lines = text.split("\n");
  const section = (name) => {
    const out = [];
    let inside = false;
    for (const l of lines) {
      if (/^## /.test(l)) inside = l.trim() === name;
      else if (inside) out.push(l);
    }
    return out;
  };
  const accused = new Set();
  for (const l of section("## Accusation")) {
    const m = /^\s*(\d+)\.\s/.exec(l) || /^\s*\|\s*(\d+)\s*\|/.exec(l);
    if (m) accused.add(Number(m[1]));
  }
  const ruled = new Set();
  for (const l of section("## Judge")) {
    const item = String.raw`\d+(?:\s*[-–]\s*\d+)?`;
    const list = String.raw`(${item}(?:\s*(?:,|and|&)\s*${item})*)`;
    const m = new RegExp(String.raw`^\s*${list}\s*[.):]`).exec(l) || new RegExp(String.raw`^\s*\|\s*${list}\s*\|`).exec(l);
    if (!m) continue;
    for (const part of m[1].split(/\s*(?:,|and|&)\s*/)) {
      const [a, b = a] = part.split(/\s*[-–]\s*/).map(Number);
      for (let n = a; n <= b && n - a < 1000; n++) ruled.add(n);
    }
  }
  return [...accused].filter((n) => !ruled.has(n)).sort((x, y) => x - y);
}

if (process.argv[1]?.endsWith("rulings.mjs")) {
  const { readFileSync } = await import("node:fs");
  const missing = missingRulings(readFileSync(process.argv[2], "utf8"));
  if (missing.length) {
    console.error(`no ruling in the Judge section for finding(s) ${missing.join(", ")}: rule on every numbered finding.`);
    process.exit(1);
  }
}
