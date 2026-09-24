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
has "$out" "the base has none yet"

# A long diff is truncated and says so.
cd "$R" && for i in $(seq 1 50); do printf 'line %s\n' "$i" >>src/ui/x.ts; done
git add . && gitc commit -q -m long
out=$(OBJECTION_BRIEF_MAX_LINES=20 bash "$BRIEF" origin/main)
has "$out" "TRUNCATED:"

# Nothing to review, or an unknown base: refuse.
(cd "$T/fresh" && git update-ref refs/remotes/origin/main HEAD && bash "$BRIEF" origin/main >/dev/null 2>&1) && { echo "FAIL: empty diff accepted"; failures=$((failures + 1)); }
(cd "$R" && bash "$BRIEF" origin/nope >/dev/null 2>&1) && { echo "FAIL: unknown base accepted"; failures=$((failures + 1)); }

if [ "$failures" = 0 ]; then echo "brief: all cases passed"; else echo "brief: $failures failure(s)"; exit 1; fi
