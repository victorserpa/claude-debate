#!/bin/bash
# Live check of review.sh against the real claude CLI (needs a logged-in
# claude; costs a few cents with the default haiku). Not run in CI.
#
#   bash test/review.live.sh
#
# The unit test (review.test.sh) only proves which flags review.sh passes.
# This proves they work: an isolated run must stay far below what a
# subagent costs (87-134k input tokens measured), which it cannot if the
# tools, MCP servers, skills or a project CLAUDE.md leaked in.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
LIMIT="${OBJECTION_LIVE_LIMIT:-20000}"

printf '# objection brief: test\n\nGoal: add two numbers\n\n## Diff\n\n```diff\n+export const add = (a, b) => a - b;\n```\n' >"$T/brief.md"
OBJECTION_MODEL="${OBJECTION_MODEL:-haiku}" bash "$ROOT/skills/objection/review.sh" accuser "$T/brief.md" >"$T/out" 2>"$T/err"
rc=$?
cat "$T/err"
[ "$rc" = 0 ] || { echo "live: review.sh failed (rc=$rc)"; exit 1; }
used=$(grep -oE 'used [0-9]+ input' "$T/err" | grep -oE '[0-9]+')
[ -n "$used" ] || { echo "live: no token count reported"; exit 1; }
[ "$used" -lt "$LIMIT" ] || { echo "live: $used input tokens, above $LIMIT: something leaked into the isolated run"; exit 1; }
grep -qi 'add\|subtract\|minus\|a - b' "$T/out" || { echo "live: the answer does not mention the defect:"; cat "$T/out"; exit 1; }
echo "live: isolated accuser used $used input tokens (limit $LIMIT) and found the defect"
