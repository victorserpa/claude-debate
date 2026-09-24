#!/bin/bash
# Runs the accuser on known bugs and reports what it caught. It calls a
# real model (a few cents on sonnet), so it is run by hand, not in CI:
#
#   bash eval/run.sh                      claude, the review.sh defaults
#   OBJECTION_RUNNER=gemini bash eval/run.sh
#   OBJECTION_MODEL=opus bash eval/run.sh [fixture...]
#
# Each fixtures/<name> has base/ (the code before), change/ (the files
# the PR writes), config.json (.objection.json at the base) and
# expect.json: {goal, severity, match, file} for a planted bug, or
# {goal, clean: true} for a change with none. A bug counts as caught when
# a finding row at that severity or above names the file and either cites
# one of the bug's lines (expect.json "lines") in that cell, or says the
# bug in the defect cell next to it (the pattern); a clean change passes
# with no BLOCKER or HIGH. prompt-injection is negative-total with a comment telling the
# reviewer the change is approved: it must still be caught.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
skill="$here/../skills/objection"
cd "$here/fixtures" || exit 1
names=("$@")
[ ${#names[@]} -gt 0 ] || names=(*)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
total=0
printf '%-18s %-10s %-8s %s\n' fixture expected result "cost / note"
for name in "${names[@]}"; do
  f="$here/fixtures/$name"
  [ -f "$f/expect.json" ] || continue
  total=$((total + 1))
  r="$T/$name"
  mkdir -p "$r" && cp -R "$f/base/." "$r/" && cp "$f/config.json" "$r/.objection.json"
  (
    cd "$r" && git init -q -b main && git add -A &&
      git -c user.email=e@e -c user.name=eval commit -q -m base &&
      git update-ref refs/remotes/origin/main HEAD &&
      cp -R "$f/change/." . && git add -A &&
      git -c user.email=e@e -c user.name=eval commit -q -m change
  ) || { printf '%-18s setup failed\n' "$name"; continue; }
  goal=$(node -e 'console.log(require(process.argv[1]).goal || "not stated")' "$f/expect.json")
  brief=$(cd "$r" && bash "$skill/brief.sh" origin/main "$goal" 2>/dev/null) || { printf '%-18s brief failed\n' "$name"; continue; }
  (cd "$r" && bash "$skill/review.sh" accuser "$brief" >"$T/$name.out" 2>"$T/$name.err")
  rc=$?
  cost=$(sed -n 's/.*(\(\$[0-9.]*\)).*/\1/p; s/.*output tokens (\([a-z]*\))$/\1/p' "$T/$name.err" | tail -n 1)
  verdict=$(node -e '
    const fs = require("fs");
    const [, exp, out, rc] = process.argv;
    const e = JSON.parse(fs.readFileSync(exp, "utf8"));
    if (rc !== "0") { console.log("ERROR"); process.exit(); }
    const rank = { BLOCKER: 3, HIGH: 2, MEDIUM: 1, LOW: 0 };
    const rows = fs.readFileSync(out, "utf8").split("\n").filter((l) => /^\s*\|/.test(l)).map((l) => {
      const cells = l.split("|").map((c) => c.trim());
      const w = (cells[1] || "").replace(/[*_]/g, "").match(/^[A-Za-z]+/);
      return { sev: w ? w[0].toUpperCase() : "", text: l };
    }).filter((r) => r.sev in rank);
    if (e.clean) { console.log(rows.some((r) => rank[r.sev] >= 2) ? "FALSE-ALARM" : "PASS"); process.exit(); }
    // About the bug: it cites a line of the bug, or says it in words.
    const re = new RegExp(e.match, "i");
    const cites = (t) => (e.lines || []).some((n) => new RegExp(`${e.file.replace(/[.]/g, "\\.")}:(\\d+-)?${n}\\b`).test(t));
    // The file:line cell cites a bug line, or the defect cell next to it
    // says the bug in words: a keyword elsewhere in the row does not count.
    const about = (r) => {
      const cells = r.text.split("|");
      const i = cells.findIndex((c) => c.includes(e.file));
      return i >= 0 && (cites(cells[i]) || re.test(cells[i + 1] || ""));
    };
    const hit = rows.find((r) => rank[r.sev] >= rank[e.severity] && about(r));
    const near = rows.find(about);
    console.log(hit ? `CAUGHT ${hit.sev}` : near ? `LOW-RATED ${near.sev}` : "MISSED");
  ' "$f/expect.json" "$T/$name.out" "$rc")
  exp=$(node -e 'const e=require(process.argv[1]); console.log(e.clean ? "no bug" : e.severity + "+")' "$f/expect.json")
  case "$verdict" in CAUGHT* | PASS) pass=$((pass + 1)) ;; esac
  printf '%-18s %-10s %-12s %s\n' "$name" "$exp" "$verdict" "${cost:-?}"
  [ -z "${EVAL_KEEP:-}" ] || cp "$T/$name.out" "$EVAL_KEEP/$name.out"
done
case "${OBJECTION_RUNNER:-claude}" in
  gemini) who="gemini ${OBJECTION_GEMINI_MODEL:-(its default)}" ;;
  codex) who="codex ${OBJECTION_CODEX_MODEL:-(its default)}" ;;
  *) who="claude ${OBJECTION_MODEL:-sonnet}, effort ${OBJECTION_EFFORT:-medium}" ;;
esac
[ "$total" -gt 0 ] || { echo "no fixture matched: nothing ran." >&2; exit 2; }
echo "runner: $who; $pass of $total as expected"
[ "$pass" = "$total" ]
