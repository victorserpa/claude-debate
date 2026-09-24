#!/usr/bin/env node
// Precedents: the defects this repository's debates have confirmed, kept
// as one line each in <repo>/.objection/precedents.md, so the next accuser
// starts by looking for the mistakes that already happened here.
//
//   node precedents.mjs list
//   node precedents.mjs add  --area <path-prefix|*> --pattern "<one sentence>" --sha <sha7>
//   node precedents.mjs bump <n> --sha <sha7>
//   node precedents.mjs match <changed-file>...
//
// Deterministic on purpose: counting, dating and capping are done here,
// not by a model rewriting a file. The model only decides whether a
// confirmed finding is a new pattern (add) or a repeat of line n (bump).
//
// Token budget: the file is capped at MAX lines (when full, the least
// repeated and oldest line goes), and `match` prints at most SHOW lines,
// the ones whose area covers a changed file, most repeated first.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const MAX = 30;
const SHOW = 10;
const HEADER = `# Precedents

Defects confirmed by /objection debates in this repository, one per line:
\`- [<times seen>x, <last seen>, <record sha>] <area>: <pattern>\`.
Maintained by precedents.mjs; edit by hand only to delete a line.
`;
const LINE = /^- \[(\d+)x, (\d{4}-\d{2}-\d{2}), ([0-9a-f]{7,40})\] (\S+): (.+)$/;

function fail(msg) {
  process.stderr.write(`precedents: ${msg}\n`);
  process.exit(1);
}

let top;
try {
  top = execFileSync("git", ["rev-parse", "--show-toplevel"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
} catch {
  fail("not inside a git repository.");
}
// OBJECTION_PRECEDENTS_FILE: brief.sh passes the base branch copy, so a
// branch cannot drop its own precedents from its review.
const file = process.env.OBJECTION_PRECEDENTS_FILE || join(top, ".objection", "precedents.md");

function load() {
  if (!existsSync(file)) return [];
  return readFileSync(file, "utf8")
    .split("\n")
    .map((l) => LINE.exec(l))
    .filter(Boolean)
    .map((m) => ({ seen: Number(m[1]), last: m[2], sha: m[3], area: m[4], pattern: m[5] }));
}

function save(items) {
  mkdirSync(dirname(file), { recursive: true });
  const body = items.map((p) => `- [${p.seen}x, ${p.last}, ${p.sha}] ${p.area}: ${p.pattern}`).join("\n");
  writeFileSync(file, `${HEADER}\n${body}\n`);
}

function opt(name) {
  const i = process.argv.indexOf(name);
  return i > -1 ? process.argv[i + 1] : undefined;
}

const today = new Date().toISOString().slice(0, 10);
const [cmd, ...rest] = process.argv.slice(2);
const items = load();

if (cmd === "list") {
  items.forEach((p, i) => console.log(`${i + 1}. [${p.seen}x, ${p.last}] ${p.area}: ${p.pattern}`));
  if (items.length === 0) console.log("(no precedents yet)");
} else if (cmd === "add") {
  const area = opt("--area");
  const pattern = opt("--pattern");
  const sha = opt("--sha");
  if (!area || !pattern || !sha) fail("add needs --area, --pattern and --sha.");
  if (/\s/.test(area)) fail("--area is a path prefix (or *), without spaces.");
  if (!/^[0-9a-f]{7,40}$/.test(sha)) fail("--sha must be a commit hash.");
  const clean = pattern.replace(/\s+/g, " ").trim();
  if (clean.length > 160) fail("--pattern must be one sentence of at most 160 characters.");
  if (items.some((p) => p.area === area && p.pattern.toLowerCase() === clean.toLowerCase()))
    fail("this exact precedent exists; use bump <n>.");
  items.push({ seen: 1, last: today, sha: sha.slice(0, 7), area, pattern: clean });
  while (items.length > MAX) {
    // Evict the least repeated; among those, the oldest.
    let victim = 0;
    items.forEach((p, i) => {
      const v = items[victim];
      if (p.seen < v.seen || (p.seen === v.seen && p.last < v.last)) victim = i;
    });
    items.splice(victim, 1);
  }
  save(items);
  console.log(`added: ${area}: ${clean}`);
} else if (cmd === "bump") {
  const n = Number(rest[0]);
  const sha = opt("--sha");
  if (!Number.isInteger(n) || n < 1 || n > items.length) fail(`bump needs a line number from list (1-${items.length}).`);
  if (!sha || !/^[0-9a-f]{7,40}$/.test(sha)) fail("bump needs --sha <commit hash>.");
  const p = items[n - 1];
  p.seen += 1;
  p.last = today;
  p.sha = sha.slice(0, 7);
  save(items);
  console.log(`bumped to ${p.seen}x: ${p.area}: ${p.pattern}`);
} else if (cmd === "match") {
  const files = rest.filter((f) => !f.startsWith("-"));
  const relevant = items
    .filter((p) => p.area === "*" || files.some((f) => f.startsWith(p.area)))
    .sort((a, b) => b.seen - a.seen || b.last.localeCompare(a.last))
    .slice(0, SHOW);
  for (const p of relevant) console.log(`- [${p.seen}x] ${p.area}: ${p.pattern}`);
} else {
  fail("usage: list | add --area <prefix> --pattern <sentence> --sha <sha> | bump <n> --sha <sha> | match <files...>");
}
