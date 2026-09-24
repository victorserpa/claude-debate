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
  # CHANGED sets pull_request.changed_files (the real count), when a case needs it.
  node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({pull_request:{number:1,head:{sha:process.argv[2]},base:{ref:"main"},body:process.argv[3],changed_files:process.env.CHANGED?+process.env.CHANGED:undefined},repository:{full_name:"o/r"}}))' "$T/event.json" "$HEAD" "$body"
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
# The cross-check reads the template's own "#, severity" order.
run 1 "$CODE" "$(record $HEAD origin/main '1 HIGH race on retry' APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/main '4, HIGH, x.ts:3, race' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '1 MEDIUM highlight color off' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '10, high-level note' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '- High-risk area untouched (MEDIUM)' APPROVED)"
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
# Issue #9: the objection prompts, instructions and config are never
# "documentation only", wherever they live.
DOCREC="<!-- objection: sha=$HEAD base=origin/main -->
documentation only
VERDICT: APPROVED"
for f in agents/defender.md skills/objection/roles/defender.md skills/objection/SKILL.md \
  AGENTS.md CLAUDE.md GEMINI.md .objection.json .objection/precedents.md .agents/skills/x/SKILL.md; do
  run 1 "$f" "$DOCREC"
done
run 0 "docs/guide.md" "$DOCREC"
run 0 "README.md" "$DOCREC"
# ...at any depth for config dirs and instruction files; agents/ and
# skills/ only at the root (docs/agents/ is ordinary documentation).
for f in packages/web/CLAUDE.md sub/AGENTS.md pkg/.claude/agents/x.md apps/api/.cursor/rules/r.md; do
  run 1 "$f" "$DOCREC"
done
run 0 "docs/agents/overview.md" "$DOCREC"
run 0 "docs/skills/guide.md" "$DOCREC"
# Issue #9: a file list that hits the API limit, or is shorter than the
# PR's own count, proves nothing about the rest.
many=$(for i in $(seq 3000); do echo "docs/f$i.md"; done)
CHANGED=3001 run 1 "$many" "$DOCREC"
CHANGED=3 run 1 "$(printf 'docs/a.md\ndocs/b.md')" "$DOCREC"
CHANGED=2 run 0 "$(printf 'docs/a.md\ndocs/b.md')" "$DOCREC"

if [ "$failures" = 0 ]; then echo "check-pr: all cases passed"; else echo "check-pr: $failures failure(s)"; exit 1; fi
