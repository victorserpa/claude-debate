#!/bin/bash
# Cases for skills/objection/debate.sh and usage.sh, with a fake `claude`
# that answers per role from prepared files, so no model is called.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEBATE="$ROOT/skills/objection/debate.sh"
USAGE="$ROOT/skills/objection/usage.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks [$2]"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$1 has [$2]"; }

# The fake answers with $FAKE_DIR/<role>.txt and records the defender's stdin.
cat >"$T/claude" <<'EOF'
#!/bin/bash
role=accuser
prev=""
for a in "$@"; do
  [ "$prev" = --system-prompt-file ] && case "$a" in *defender.md) role=defender ;; esac
  prev="$a"
done
cat >"$FAKE_DIR/stdin-$role"
touch "$FAKE_DIR/ran-$role"
node -e 'process.stdout.write(JSON.stringify({result: require("fs").readFileSync(process.argv[1], "utf8"),
  usage: {input_tokens: 1000, output_tokens: 200}, total_cost_usd: 0.05}))' "$FAKE_DIR/$role.txt"
EOF
chmod +x "$T/claude"
export OBJECTION_CLAUDE="$T/claude" FAKE_DIR="$T"
printf '| # | verdict | evidence | kind | why |\n|---|---|---|---|---|\n| 1 | UPHELD | src/a.ts:3 | read | yes |\n' >"$T/defender.txt"
accuse() {
  {
    printf '| severity | kind | file:line | defect | evidence | proof |\n|---|---|---|---|---|---|\n'
    for s in "$@"; do printf '| %s | BUG | src/a.ts:3 | defect %s | read | path |\n' "$s" "$s"; done
    printf '\nCould not evaluate: nothing.\n'
  } >"$T/accuser.txt"
}
reset() { rm -f "$T"/ran-* "$T"/stdin-*; }

R="$T/r"
git init -q "$R" && cd "$R" || exit 1
printf '{"bases":["main"]}\n' >.objection.json
mkdir -p src && seq 1 10 >src/a.ts
git add . && gitc commit -q -m base
git update-ref refs/remotes/origin/main HEAD
printf 'x\n' >>src/a.ts && git add . && gitc commit -q -m change

# Lean (no budget in the config): only BLOCKER and HIGH reach the defender.
accuse HIGH MEDIUM "**LOW**"
reset
out=$(bash "$DEBATE" main "the goal" 2>"$T/err") || fail "debate exited $? ($(cat "$T/err"))"
printf '%s\n' "$out" >"$T/out"
has "$T/out" "budget lean"
has "$T/out" "accuser: 0 BLOCKER, 1 HIGH, 1 MEDIUM, 1 LOW"
has "$T/out" "defender: answered 1 finding(s)"
has "$T/stdin-defender" "| 1 | HIGH | BUG | src/a.ts:3 | defect HIGH"
hasnt "$T/stdin-defender" "defect MEDIUM"
record=$(sed -n 's/^draft record: //p' "$T/out")
[ -f "$record" ] || fail "no draft record ($record)"
has "$record" "## Accusation"
has "$record" "## Defense"
has "$record" "UPHELD"
has "$record" "## Judge"
has "$record" "## Open"
has "$record" "TODO(judge)"
# The draft cannot be stamped as is: it has no OPEN line.
grep -qE '^OPEN:' "$record" && fail "the draft already carries an OPEN line"
has "$T/err" "accuser used 1000 input + 200 output tokens"

# No BLOCKER or HIGH under lean: the defender never runs.
accuse MEDIUM LOW
reset
out=$(bash "$DEBATE" main 2>/dev/null)
[ -e "$T/ran-defender" ] && fail "lean ran the defender for MEDIUM and LOW"
printf '%s\n' "$out" | grep -qF "defender: not run" || fail "summary does not say the defender did not run"

# Standard, from the base branch: MEDIUM goes to the defender too.
git checkout -q -b cfg origin/main
printf '{"bases":["main"],"budget":"standard"}\n' >.objection.json
git add . && gitc commit -q -m standard
git update-ref refs/remotes/origin/main HEAD
git checkout -q - && gitc rebase -q origin/main
reset
out=$(bash "$DEBATE" main 2>/dev/null)
printf '%s\n' "$out" | grep -qF "budget standard" || fail "standard budget not read from the base"
has "$T/stdin-defender" "defect MEDIUM"
hasnt "$T/stdin-defender" "defect LOW"
printf '%s\n' "$out" | grep -qF "reviewers entry" || fail "standard does not mention the other reviewers"

# The branch cannot lower its own budget: the base's config wins.
printf '{"bases":["main"],"budget":"lean"}\n' >.objection.json
git add . && gitc commit -q -m "try lean on the branch"
reset
bash "$DEBATE" main 2>/dev/null | grep -qF "budget standard" || fail "the branch lowered its own budget"

# Later round: the diff starts at the previous commit and says so.
prev=$(git rev-parse HEAD)
printf 'y\n' >>src/a.ts && git add . && gitc commit -q -m fix
reset
out=$(bash "$DEBATE" --since "$prev" main 2>/dev/null)
printf '%s\n' "$out" | grep -qF "diff $prev...HEAD" || fail "--since did not set the diff base"
has "$T/stdin-accuser" "hunt regressions from the fix first"

# No claude CLI: exit 3 reaches the caller, so it can fall back to subagents.
OBJECTION_CLAUDE=/nonexistent/claude bash "$DEBATE" main >/dev/null 2>&1
[ $? = 3 ] || fail "a missing claude CLI did not exit 3"

# usage.sh sums the log review.sh wrote, per branch.
bash "$USAGE" >"$T/usage"
has "$T/usage" "$(git rev-parse --abbrev-ref HEAD)"
runs=$(awk -v b="$(git rev-parse --abbrev-ref HEAD)" '$1 == b {print $2}' "$T/usage")
[ "$runs" -ge 7 ] 2>/dev/null || fail "usage counted $runs runs, expected at least 7"
bash "$USAGE" "$(git rev-parse --abbrev-ref HEAD)" | grep -qE '^total: [0-9]+ runs, [0-9]+ input' || fail "usage.sh <branch> has no total"
bash "$USAGE" no-such-branch | grep -qF "no runs logged" || fail "an unknown branch is not reported"

if [ "$failures" = 0 ]; then echo "debate: all cases passed"; else echo "debate: $failures failure(s)"; exit 1; fi
