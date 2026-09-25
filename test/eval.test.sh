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
# The defender runs with defender.md as its system prompt file.
out=$FAKE_ROW
case " $* " in *defender.md*) out=${FAKE_DEFENSE:-} ;; esac
FAKE_OUT=$out node -e 'process.stdout.write(JSON.stringify({result: process.env.FAKE_OUT, usage: {input_tokens: 1, output_tokens: 1}, total_cost_usd: 0}))'
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
# Which evidence counted: the line when cited, else the words.
how() { FAKE_ROW="$2" bash "$ROOT/eval/run.sh" "$1" 2>/dev/null | awk -v n="$1" '$1 == n' | grep -oE '\((line|words)\)'; }
[ "$(how missing-cleanup "$(printf "$row" 11 'x' 'p')")" = "(line)" ] || fail "a cited line was not reported as (line)"
[ "$(how missing-cleanup "$(printf "$row" 40 'the temp dir leaks on retry' 'p')")" = "(words)" ] || fail "a catch in words was not reported as (words)"
# The file named in the defect cell too: the file:line cell still counts.
[ "$(score missing-cleanup '| HIGH | BUG | the temp dir in src/export.js leaks | src/export.js:11 | read | p |')" = CAUGHT ] || fail "a file named twice was not caught"
# An unrelated finding in the same file is not a catch, even when a
# keyword appears elsewhere in the row.
[ "$(score missing-cleanup "$(printf "$row" 40 'unrelated: the code is not clean' 'p')")" = MISSED ] || fail "an unrelated finding was caught"
[ "$(score missing-cleanup "$(printf "$row" 40 'style nit' 'leaks the temp dir')")" = MISSED ] || fail "a keyword in the proof cell was caught"
# The clean change: a HIGH is a false alarm, a LOW is not.
[ "$(score clean "| HIGH | BUG | src/format.js:1 | x | read | p |")" = FALSE-ALARM ] || fail "a HIGH on the clean change passed"
[ "$(score clean "| LOW | BUG | src/format.js:1 | x | read | p |")" = PASS ] || fail "a LOW on the clean change failed"
# EVAL_DEFENSE=1: a false alarm and a catch go to the defender, and the
# line says what it ruled; a clean pass does not call it.
def='| # | verdict | evidence | kind | sentence |
|---|---|---|---|---|
| 1 | REFUTED | src/format.js:1 | read | the old code did the same |'
line=$(EVAL_DEFENSE=1 FAKE_DEFENSE="$def" FAKE_ROW="| HIGH | BUG | src/format.js:1 | x | read | p |" bash "$ROOT/eval/run.sh" clean 2>/dev/null | awk '$1 == "clean"')
case "$line" in *"defense: 1 refuted, 0 upheld, 0 cannot verify"*) ;; *) fail "the defense on a false alarm was not reported ($line)" ;; esac
# A catch goes to the defender too (review.sh passes the role with
# --system-prompt-file, which is what the stub keys on).
up='| # | verdict | evidence | kind | sentence |
|---|---|---|---|---|
| 1 | UPHELD | src/export.js:11 | read | nothing cleans it up |'
line=$(EVAL_DEFENSE=1 FAKE_DEFENSE="$up" FAKE_ROW="$(printf "$row" 11 'x' 'p')" bash "$ROOT/eval/run.sh" missing-cleanup 2>/dev/null | awk '$1 == "missing-cleanup"')
case "$line" in *"defense: 0 refuted, 1 upheld, 0 cannot verify"*) ;; *) fail "the defense on a catch was not reported ($line)" ;; esac
line=$(EVAL_DEFENSE=1 FAKE_DEFENSE="$def" FAKE_ROW="NO FINDINGS" bash "$ROOT/eval/run.sh" clean 2>/dev/null | awk '$1 == "clean"')
case "$line" in *defense:*) fail "the defender ran on a clean pass ($line)" ;; esac
# No fixture ran: not a pass.
bash "$ROOT/eval/run.sh" nosuch >/dev/null 2>&1
[ $? = 2 ] || fail "an empty run did not exit 2"
[ "$failures" = 0 ] && echo "eval: all cases passed" || { echo "eval: $failures failure(s)"; exit 1; }
