#!/bin/bash
# Cases for skills/objection/brief.sh.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIEF="$ROOT/skills/objection/brief.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
has() { grep -qF -- "$2" "$1" || { echo "FAIL: brief lacks [$2]"; failures=$((failures + 1)); }; }
hasnt() { grep -qF -- "$2" "$1" && { echo "FAIL: brief has [$2]"; failures=$((failures + 1)); }; }

R="$T/r"
git init -q "$R" && cd "$R" || exit 1
printf '{"bases":["main"],"invariants":[{"paths":"^src/game/","rule":"undo never restores a spent life"},{"paths":"^src/auth/","rule":"no private data in responses"}]}\n' >.objection.json
mkdir -p src/game src/ui && printf 'a\n' >src/game/undo.ts && printf 'a\n' >src/ui/x.ts && printf 'lock\n' >pnpm-lock.yaml
git add . && gitc commit -q -m base
git update-ref refs/remotes/origin/main HEAD
printf 'b\n' >>src/game/undo.ts && printf 'b\n' >>src/ui/x.ts && printf 'changed\n' >>pnpm-lock.yaml
git add . && gitc commit -q -m change

out=$(bash "$BRIEF" origin/main "undo keeps lives" "src/game only")
[ -f "$out" ] || { echo "FAIL: no brief written ($out)"; exit 1; }
has "$out" "Goal: undo keeps lives"
has "$out" "Scope: src/game only"
has "$out" "- src/game/undo.ts"
has "$out" "undo never restores a spent life"
hasnt "$out" "no private data in responses"
hasnt "$out" "pnpm-lock.yaml"
has "$out" "Open at most 5 other files"
has "$out" "(from origin/main)"

# Invariants come from the base, not from the branch under review.
printf '{"bases":["main"],"invariants":[]}\n' >.objection.json
git add . && gitc commit -q -m "drop invariants on the branch"
out=$(bash "$BRIEF" origin/main)
has "$out" "undo never restores a spent life"

# A base without config (the opt-in PR) falls back to the working copy.
git init -q "$T/fresh" && cd "$T/fresh" && gitc commit -q --allow-empty -m base
git update-ref refs/remotes/origin/main HEAD
printf '{"invariants":[{"paths":".","rule":"everything is guarded"}]}\n' >.objection.json
git add . && gitc commit -q -m optin
out=$(bash "$BRIEF" origin/main)
has "$out" "everything is guarded"
has "$out" "has none yet"

# A long diff is truncated and says so.
cd "$R" && for i in $(seq 1 50); do printf 'line %s\n' "$i" >>src/ui/x.ts; done
git add . && gitc commit -q -m long
out=$(OBJECTION_BRIEF_MAX_LINES=20 bash "$BRIEF" origin/main)
has "$out" "TRUNCATED:"

# --- Round 1 of the brief's own debate -------------------------------------
# Later rounds diff against the previous round's commit, but the rules still
# come from the PR's base (the branch dropped the invariant above).
cd "$R"
prev=$(git rev-parse HEAD)
printf 'c\n' >>src/game/undo.ts && git add . && gitc commit -q -m fix
out=$(bash "$BRIEF" "$prev" "the fix" "" origin/main)
has "$out" "undo never restores a spent life"
has "$out" "- src/game/undo.ts"
hasnt "$out" "- src/ui/x.ts"
# Run from a subdirectory: nothing elsewhere is dropped.
out=$(cd src/ui && bash "$BRIEF" origin/main)
has "$out" "- src/game/undo.ts"
# An invalid regex is reported, not dropped; reviewer focus is in the brief.
git init -q "$T/rx" && cd "$T/rx" && gitc commit -q --allow-empty -m base
git update-ref refs/remotes/origin/main HEAD
cat >.objection.json <<'EOF'
{"invariants":[{"paths":"^src/(bad","rule":"RULE-BAD"}],
 "reviewers":[{"paths":"^src/","agent":"security-reviewer","focus":"FOCUS-SEC"},{"paths":"^docs/","agent":"x","focus":"FOCUS-DOCS"}]}
EOF
git add . && gitc commit -q -m cfg
git update-ref refs/remotes/origin/main HEAD
mkdir -p "src/a dir" && printf 'x\n' >"src/a dir/f.ts" && git add . && gitc commit -q -m spaced
out=$(bash "$BRIEF" origin/main)
has "$out" "INVALID paths regex"
has "$out" "RULE-BAD"
has "$out" "FOCUS-SEC"
hasnt "$out" "FOCUS-DOCS"
has "$out" "- src/a dir/f.ts"
# precedents: false in the config turns them off, and says so.
printf '{"precedents":false}\n' >.objection.json && git add . && gitc commit -q -m off
git update-ref refs/remotes/origin/main HEAD~0
printf 'y\n' >>"src/a dir/f.ts" && git add . && gitc commit -q -m more
out=$(bash "$BRIEF" origin/main)
has "$out" "turned off"

# Precedents come from the base, like the rules: a branch that deletes
# them still gets them. Matching reviewers are listed for debate.sh.
P="$T/prec"
git init -q "$P" && cd "$P" || exit 1
printf '{"bases":["main"],"reviewers":[{"paths":"^src/","focus":"money math","agent":"money"},{"paths":"^docs/","focus":"prose","agent":"docs"}]}\n' >.objection.json
mkdir -p src && printf 'a\n' >src/pay.ts
node "$ROOT/skills/objection/precedents.mjs" add --area src/ --pattern "rounding lost a cent" --sha abc1234 >/dev/null
git add . && gitc commit -q -m base
git update-ref refs/remotes/origin/main HEAD
git rm -q .objection/precedents.md && printf 'b\n' >>src/pay.ts && git add . && gitc commit -q -m "drop precedents"
out=$(bash "$BRIEF" origin/main)
# Checked in its section: the deletion itself shows the line in the diff.
awk '/^## Defects/{f=1;next} /^## /{f=0} f' "$out" | grep -qF "rounding lost a cent" || { echo "FAIL: precedents read from the branch"; failures=$((failures + 1)); }
has "$out" "<!-- objection-reviewer: money	money math -->"
hasnt "$out" "objection-reviewer: docs"

# Model tier, from the base config: the cheap model unless an invariant
# matches, strongPaths matches, or the budget is thorough.
M="$T/model"
git init -q "$M" && cd "$M" || exit 1
printf '{"bases":["main"],"invariants":[{"paths":"^src/pay","rule":"money exact"}],"strongPaths":"^src/gate/"}\n' >.objection.json
mkdir -p src/gate && printf 'a\n' >src/ui.ts && printf 'a\n' >src/pay.ts && printf 'a\n' >src/gate/x.ts
git add . && gitc commit -q -m base && git update-ref refs/remotes/origin/main HEAD
printf 'b\n' >>src/ui.ts && git add . && gitc commit -q -m ui
out=$(bash "$BRIEF" origin/main)
has "$out" "<!-- objection-model: sonnet medium default -->"
git reset -q --hard origin/main && printf 'b\n' >>src/pay.ts && git add . && gitc commit -q -m pay
out=$(bash "$BRIEF" origin/main)
has "$out" "<!-- objection-model: opus medium invariant -->"
git reset -q --hard origin/main && printf 'b\n' >>src/gate/x.ts && git add . && gitc commit -q -m gate
out=$(bash "$BRIEF" origin/main)
has "$out" "<!-- objection-model: opus medium strongPaths -->"
# Configured models and effort, and thorough.
git reset -q --hard origin/main
printf '{"bases":["main"],"budget":"thorough","models":{"default":"haiku","strong":"sonnet","effort":"low"}}\n' >.objection.json
git add . && gitc commit -q -m cfg && git update-ref refs/remotes/origin/main HEAD
printf 'c\n' >>src/ui.ts && git add . && gitc commit -q -m ui2
out=$(bash "$BRIEF" origin/main)
has "$out" "<!-- objection-model: sonnet low thorough -->"

# Nothing to review, or an unknown base: refuse.
(cd "$T/fresh" && git update-ref refs/remotes/origin/main HEAD && bash "$BRIEF" origin/main >/dev/null 2>&1) && { echo "FAIL: empty diff accepted"; failures=$((failures + 1)); }
(cd "$R" && bash "$BRIEF" origin/nope >/dev/null 2>&1) && { echo "FAIL: unknown base accepted"; failures=$((failures + 1)); }

if [ "$failures" = 0 ]; then echo "brief: all cases passed"; else echo "brief: $failures failure(s)"; exit 1; fi
