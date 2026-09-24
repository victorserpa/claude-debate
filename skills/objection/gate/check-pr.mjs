#!/usr/bin/env node
// The tool-neutral gate: a GitHub check that fails a pull request unless
// its body carries an APPROVED /objection record for the PR's current head
// SHA and base. It does not care which agent (or human) opened the PR, so
// it covers every tool that has no local hook. Make it a required status
// check in branch protection and nothing merges without a debate.
//
// A new push changes the head SHA, so the check fails again until the
// debate runs on the new commit and the body is updated with the new
// record. Same rules as stamp.sh: last VERDICT line counts, required
// sections unless the diff is documentation only, nothing BLOCKER/HIGH
// under "## Open".
//
// Inputs (GitHub Actions): GITHUB_EVENT_PATH, GITHUB_TOKEN, GITHUB_API_URL.
// Test hook: OBJECTION_FILES (newline-separated changed files) skips the
// API call.

import { readFileSync } from "node:fs";

function fail(msg) {
  console.log(`::error title=objection::${msg}`);
  console.error(`objection: ${msg}`);
  process.exit(1);
}

const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, "utf8"));
const pr = event.pull_request;
if (!pr) fail("this check only runs on pull_request events.");

const head = pr.head.sha;
const base = pr.base.ref;
const body = pr.body || "";

// The LAST stamp in the body wins: an older record left above a newer one
// must not count.
const stamps = [...body.matchAll(/^<!-- objection: sha=([0-9a-f]{40}) base=(\S+) -->$/gm)];
if (stamps.length === 0)
  fail(`no /objection record in the PR body. Run /objection on ${head.slice(0, 7)} and paste the stored record (including its first line) into the body.`);
const stamp = stamps.at(-1);
if (stamp[1] !== head)
  fail(`the record in the body is for ${stamp[1].slice(0, 7)}, but the PR head is ${head.slice(0, 7)}. Debate the new commits and update the body.`);
if (stamp[2] !== `origin/${base}`)
  fail(`the record was debated against ${stamp[2]}, but the PR targets ${base}.`);

const record = body.slice(stamp.index);

async function changedFiles() {
  if (process.env.OBJECTION_FILES !== undefined)
    return process.env.OBJECTION_FILES.split("\n").filter(Boolean);
  const api = process.env.GITHUB_API_URL || "https://api.github.com";
  const repo = event.repository.full_name;
  const files = [];
  for (let page = 1; page <= 30; page++) {
    const res = await fetch(`${api}/repos/${repo}/pulls/${pr.number}/files?per_page=100&page=${page}`, {
      headers: {
        authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
        accept: "application/vnd.github+json",
      },
    });
    if (!res.ok) fail(`could not list the PR files (HTTP ${res.status}).`);
    const batch = await res.json();
    files.push(...batch.map((f) => f.filename));
    if (batch.length < 100) break;
  }
  return files;
}

const files = await changedFiles();
// The files API stops at 3000 files. A list that hits the limit, or that
// is shorter than the PR says it is, proves nothing about the rest: a PR of
// 3000 docs and one source file must not pass as documentation only.
if (files.length >= 3000 || (Number.isInteger(pr.changed_files) && files.length !== pr.changed_files))
  fail(`cannot prove the full list of changed files (listed ${files.length}, PR has ${pr.changed_files}). Split the PR.`);
// Agent prompts, skills, instructions and the objection config are how the
// debate itself behaves: weakening the defender must not ship without a
// debate, wherever those files live. Same list as stamp.sh (NEVER_DOCS).
const NEVER_DOCS =
  /^(\.(claude|cursor|codex|gemini|github|agents|objection)\/|agents\/|skills\/|(AGENTS|CLAUDE|GEMINI)\.md$|\.objection\.json$)/;
const docsOnly =
  files.length > 0 &&
  files.every((f) => !NEVER_DOCS.test(f) && (/\.md$/.test(f) || /^docs\//.test(f)));

const lines = record.split("\n");
if (!docsOnly) {
  for (const section of ["## Accusation", "## Defense", "## Judge", "## Open"])
    if (!lines.includes(section)) fail(`the record is missing the section "${section}".`);
}

const verdicts = lines.filter((l) => /^VERDICT: /.test(l));
if (verdicts.at(-1) !== "VERDICT: APPROVED") fail("the record's last verdict is not APPROVED.");

if (!docsOnly) {
  // The judge's structured count is the authority (same rule as stamp.sh);
  // the word scan below only cross-checks it against its own list.
  const counts = lines.filter((l) => /^OPEN: BLOCKER=\d+ HIGH=\d+$/.test(l)).at(-1);
  if (!counts) fail("the record is missing the line 'OPEN: BLOCKER=<n> HIGH=<n>'.");
  if (counts !== "OPEN: BLOCKER=0 HIGH=0") fail(`the record is APPROVED with ${counts}.`);
  const start = lines.indexOf("## Open");
  const open = [];
  for (let i = start + 1; i < lines.length && !/^## /.test(lines[i]); i++) open.push(lines[i]);
  if (open.some((l) => /^\s*([-*]|\d+[.),]?)?\s*,?\s*[*_]*(blocker|high)([^a-z-]|$)/i.test(l)))
    fail("the record is APPROVED but lists a BLOCKER/HIGH finding under Open.");
}

console.log(`objection: APPROVED record for ${head.slice(0, 7)} against ${base}.`);
