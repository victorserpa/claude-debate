#!/bin/bash
# Cases for core/check-pr.mjs (the GitHub check). Synthetic pull_request
# events; OBJECTION_FILES stands in for the PR file list, so no network.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/objection/gate/check-pr.mjs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

HEAD=$(printf 'a%.0s' $(seq 40))
OLD=$(printf 'b%.0s' $(seq 40))
failures=0

run() { # expected files body
  local expected=$1 files=$2 body=$3 rc
  node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({pull_request:{number:1,head:{sha:process.argv[2]},base:{ref:"main"},body:process.argv[3]},repository:{full_name:"o/r"}}))' "$T/event.json" "$HEAD" "$body"
  GITHUB_EVENT_PATH="$T/event.json" OBJECTION_FILES="$files" node "$CHECK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "$expected" ]; then
    echo "FAIL (expected $expected, got $rc): files=[$files] body=$(printf '%s' "$body" | head -c 120 | tr '\n' '|')"
    failures=$((failures + 1))
  fi
}

record() { # sha base open verdicts...
  local sha=$1 base=$2 open=$3; shift 3
  printf '<!-- objection: sha=%s base=%s -->\n# Debate\n\n## Accusation\n1 HIGH x\n\n## Defense\n1 UPHELD\n\n## Judge\n1 fixed\n\n## Open\n%s\n\n%s\n' "$sha" "$base" "$open" "${OPENLINE-OPEN: BLOCKER=0 HIGH=0}"
  for v in "$@"; do printf 'VERDICT: %s\n' "$v"; done
}

CODE='src/a.ts'
run 0 "$CODE" "Summary above.

$(record $HEAD origin/main nothing APPROVED)"
run 1 "$CODE" "no record here"
run 1 "$CODE" "$(record $OLD origin/main nothing APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/develop nothing APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/main nothing APPROVED REJECTED)"
run 1 "$CODE" "$(record $HEAD origin/main '- HIGH: race on retry' APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/main '1. **Blocker** data loss' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '- MEDIUM: falta teste' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main 'no HIGH finding is left' APPROVED)"
# The last stamp wins: an old approved record below a new rejected one.
run 1 "$CODE" "$(record $OLD origin/main nothing APPROVED)
$(record $HEAD origin/main nothing REJECTED)"
run 0 "$CODE" "$(record $OLD origin/main nothing REJECTED)
$(record $HEAD origin/main nothing APPROVED)"
# The structured count: required, and zero to approve.
OPENLINE="" run 1 "$CODE" "$(OPENLINE="" record $HEAD origin/main nothing APPROVED)"
run 1 "$CODE" "$(OPENLINE="OPEN: BLOCKER=0 HIGH=1" record $HEAD origin/main '- MEDIUM: x' APPROVED)"
run 1 "$CODE" "$(OPENLINE="OPEN: BLOCKER=1 HIGH=0" record $HEAD origin/main nothing APPROVED)"
# Missing sections on a code diff.
run 1 "$CODE" "<!-- objection: sha=$HEAD base=origin/main -->
VERDICT: APPROVED"
# Docs-only diff: sections not required, verdict still is.
run 0 "README.md
docs/x.md" "<!-- objection: sha=$HEAD base=origin/main -->
documentation only
VERDICT: APPROVED"
run 1 "README.md" "<!-- objection: sha=$HEAD base=origin/main -->
documentation only
VERDICT: REJECTED"
# Agent prompts are not documentation.
run 1 ".claude/agents/defender.md" "<!-- objection: sha=$HEAD base=origin/main -->
VERDICT: APPROVED"
run 1 ".cursor/rules/x.md" "<!-- objection: sha=$HEAD base=origin/main -->
VERDICT: APPROVED"

if [ "$failures" = 0 ]; then echo "check-pr: all cases passed"; else echo "check-pr: $failures failure(s)"; exit 1; fi
