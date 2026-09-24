#!/bin/bash
# Cases for skills/objection/ci-review.sh against a local "GitHub" (a bare
# repository with refs/pull/<n>/head) and a fake `claude`, so no model is
# called and nothing leaves the machine.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CI="$ROOT/skills/objection/ci-review.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks [$2]"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$1 has [$2]"; }

# The fake answers with the rows in $T/answer and records its model and stdin.
cat >"$T/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/args"
cat >"$FAKE_DIR/stdin"
[ -f "$FAKE_DIR/broken" ] && exit 1
node -e 'process.stdout.write(JSON.stringify({result: require("fs").readFileSync(process.argv[1], "utf8"), usage: {input_tokens: 5, output_tokens: 5}, total_cost_usd: 0.01}))' "$FAKE_DIR/answer"
STUB
chmod +x "$T/claude"
export OBJECTION_CLAUDE="$T/claude" FAKE_DIR="$T" ANTHROPIC_API_KEY=test
answer() {
  { printf '| severity | kind | file:line | defect | evidence | proof |\n|---|---|---|---|---|---|\n'
    for s in "$@"; do printf '| %s | BUG | src/a.ts:3 | defect %s | read | path |\n' "$s" "$s"; done
  } >"$T/answer"
}

# "GitHub": main, and a PR whose head adds a file that would run if executed.
B="$T/remote.git"
git init -q --bare "$B"
W="$T/w"
git init -q "$W" && cd "$W" || exit 1
printf '{"bases":["main"],"invariants":[{"paths":"^src/","rule":"RULE FROM BASE"}]}\n' >.objection.json
mkdir -p src && seq 1 10 >src/a.ts
git add . && gitc commit -q -m base && git branch -M main && git push -q "$B" main
printf 'x\n' >>src/a.ts
printf '{"bases":["main"],"invariants":[{"paths":"^src/","rule":"RULE FROM PR"}]}\n' >.objection.json
printf '#!/bin/sh\ntouch "%s/pwned"\n' "$T" >run-me.sh
git add . && gitc commit -q -m pr && git push -q "$B" HEAD:refs/pull/7/head
head=$(git rev-parse HEAD)
event() { printf '{"pull_request":{"number":7,"title":"%s","base":{"ref":"main"},"head":{"sha":"%s"}}}\n' "$1" "$2" >"$T/event.json"; }
export GITHUB_EVENT_PATH="$T/event.json" OBJECTION_CI_REMOTE="$B" GITHUB_STEP_SUMMARY="$T/summary"
cd "$T" || exit 1
run() { rm -f "$T/summary" "$T/stdin" "$T/args"; bash "$CI" >"$T/out" 2>"$T/err"; }

# No finding: passes, reviews the PR head against main, with the base's rules.
event "Add x" "$head"; answer
run || fail "a clean review failed ($(cat "$T/err"))"
has "$T/summary" "objection review: passed"
has "$T/stdin" "RULE FROM BASE (guards"
hasnt "$T/stdin" "RULE FROM PR (guards"
has "$T/stdin" "Goal: Add x"
has "$T/stdin" "+x"
grep -qx sonnet "$T/args" || fail "the default model is not sonnet"
[ -e "$T/pwned" ] && fail "the PR's code ran"

# A BLOCKER fails under the default; a HIGH only under fail-on high.
answer BLOCKER
run && fail "a BLOCKER passed"
has "$T/summary" "failed: 1 BLOCKER"
answer HIGH MEDIUM
run || fail "a HIGH failed under fail-on blocker"
has "$T/summary" "1 HIGH, 1 MEDIUM"
OBJECTION_FAIL_ON=high run && fail "a HIGH passed under fail-on high"
has "$T/summary" "failed: 0 BLOCKER, 1 HIGH"
answer BLOCKER
OBJECTION_FAIL_ON=none run || fail "fail-on none failed"
OBJECTION_FAIL_ON=bogus run && fail "an unknown fail-on was accepted"
# A word that only starts like a severity is not a finding.
{ printf '| severity | kind |\n|---|---|\n| Blockers noted: none | x |\n'; } >"$T/answer"
run || fail "a row starting with Blockers counted as a BLOCKER"

# Fails closed: the reviewer broken, no key, a head the event does not name.
answer; touch "$T/broken"
run && fail "a broken reviewer passed"
has "$T/summary" "the accuser did not run"
rm -f "$T/broken"
ANTHROPIC_API_KEY= run && fail "no API key passed"
event "Add x" "0000000000000000000000000000000000000000"
run && fail "a stale head passed"
has "$T/err" "pushed again?"
# An error the script did not foresee fails too (bash 3.2 would exit 0).
event "Add x" "$head"; answer
mkdir -p "$T/summary-dir"
GITHUB_STEP_SUMMARY="$T/summary-dir" bash "$CI" >/dev/null 2>&1 && fail "a failed summary write passed"
# An unset variable late in the script (bash 3.2 exits 0 on it under an
# EXIT trap): a copy with one injected before the end must still fail.
mkdir -p "$T/copy" && cp "$ROOT"/skills/objection/*.sh "$ROOT"/skills/objection/*.mjs "$T/copy/" && cp -R "$ROOT/skills/objection/roles" "$T/copy/"
sed 's/^finished=yes$/: "$objection_unset"; finished=yes/' "$CI" >"$T/copy/ci-review.sh"
grep -qF objection_unset "$T/copy/ci-review.sh" || fail "the injection did not apply"
bash "$T/copy/ci-review.sh" >/dev/null 2>&1 && fail "an unbound variable passed"
# A brief that cannot be built fails with the reason in the summary; a PR
# whose every file is excluded noise passes as nothing to review.
event "Add x" "$head"
cd "$W" && git checkout -q -b lock HEAD~1 && printf 'lock\n' >pnpm-lock.yaml && git add . && gitc commit -q -m lock &&
  git push -q -f "$B" HEAD:refs/pull/7/head && cd "$T" || exit 1
event "Lock" "$(git -C "$W" rev-parse HEAD)"
run || fail "a PR of excluded files failed ($(cat "$T/err"))"
has "$T/summary" "nothing to review"
[ -e "$T/stdin" ] && fail "the accuser ran on a PR of excluded files"
git -C "$B" update-ref -d refs/heads/main
run && fail "a missing base passed"
printf '{"push":{}}\n' >"$T/event.json"
run && fail "a non-PR event passed"

[ "$failures" -eq 0 ] && echo "ci-review: all cases passed" || { echo "ci-review: $failures failure(s)"; exit 1; }
