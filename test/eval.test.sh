#!/bin/bash
# Cases for eval/run.sh's scoring, with a fake `claude` that answers a
# fixed row: no model is called.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
cat >"$T/claude" <<'STUB'
#!/bin/bash
cat >/dev/null
node -e 'process.stdout.write(JSON.stringify({result: process.env.FAKE_ROW, usage: {input_tokens: 1, output_tokens: 1}, total_cost_usd: 0}))'
STUB
chmod +x "$T/claude"
export OBJECTION_CLAUDE="$T/claude"
score() { # fixture row -> the result column
  FAKE_ROW="$2" bash "$ROOT/eval/run.sh" "$1" 2>/dev/null | awk -v n="$1" '$1 == n' | grep -oE 'CAUGHT|LOW-RATED|MISSED|PASS|FALSE-ALARM|ERROR' | head -n 1
}
row='| HIGH | BUG | src/export.js:%s | %s | read | %s |'
# A cited bug line, or the bug said in the defect cell: caught.
[ "$(score missing-cleanup "$(printf "$row" 11 'x' 'p')")" = CAUGHT ] || fail "a cited bug line was not caught"
[ "$(score missing-cleanup "$(printf "$row" 40 'the temp dir leaks on retry' 'p')")" = CAUGHT ] || fail "the bug in words was not caught"
# An unrelated finding in the same file is not a catch, even when a
# keyword appears elsewhere in the row.
[ "$(score missing-cleanup "$(printf "$row" 40 'unrelated: the code is not clean' 'p')")" = MISSED ] || fail "an unrelated finding was caught"
[ "$(score missing-cleanup "$(printf "$row" 40 'style nit' 'leaks the temp dir')")" = MISSED ] || fail "a keyword in the proof cell was caught"
# The clean change: a HIGH is a false alarm, a LOW is not.
[ "$(score clean "| HIGH | BUG | src/format.js:1 | x | read | p |")" = FALSE-ALARM ] || fail "a HIGH on the clean change passed"
[ "$(score clean "| LOW | BUG | src/format.js:1 | x | read | p |")" = PASS ] || fail "a LOW on the clean change failed"
# No fixture ran: not a pass.
bash "$ROOT/eval/run.sh" nosuch >/dev/null 2>&1
[ $? = 2 ] || fail "an empty run did not exit 2"
[ "$failures" = 0 ] && echo "eval: all cases passed" || { echo "eval: $failures failure(s)"; exit 1; }
