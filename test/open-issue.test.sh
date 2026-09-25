#!/bin/bash
# Cases for skills/objection/open-issue.sh with a fake gh.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OI="$ROOT/skills/objection/open-issue.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks [$2]"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$1 has [$2]"; }

# gh: "issue list" prints $FAKE/issues.json; "issue create" records its
# arguments and prints a URL; "pr view" prints a PR URL.
cat >"$T/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "issue list") cat "$FAKE/issues.json" ;;
  "issue create") printf '%s\n' "$@" >"$FAKE/created"; echo "https://github.com/o/r/issues/9" ;;
  "pr view") echo "https://github.com/o/r/pull/3" ;;
esac
STUB
chmod +x "$T/gh"
export OBJECTION_GH_BIN="$T/gh" FAKE="$T"
echo '[]' >"$T/issues.json"

R="$T/r"
git init -q "$R" && cd "$R" || exit 1
printf 'x\n' >a && git add . && gitc commit -q -m a && git checkout -q -b feat
sha=$(git rev-parse HEAD)
mkdir -p .git/objection
rec() { # rec <open section text>
  printf '<!-- objection: sha=%s base=origin/main -->\n# Debate: feat\n\n## Accusation\n\nx\n\n## Defense\n\nx\n\n## Judge\n\nx\n\n## Open\n\n%s\n\nOPEN: BLOCKER=0 HIGH=0\nVERDICT: APPROVED\n' "$sha" "$1" >".git/objection/$sha.md"
}

# No record: refused.
bash "$OI" >/dev/null 2>&1 && fail "ran without a stamped record"

# Nothing open: no issue, and gh is not asked to create one.
rec "nothing."
out=$(bash "$OI") || fail "nothing open failed"
printf '%s' "$out" | grep -q "nothing open" || fail "nothing open was not said ($out)"
[ -e "$T/created" ] && fail "an issue was created with nothing open"

# Open items: one issue with them, the branch, the commit, the PR, the marker.
rec "- 2 (MEDIUM): the retry is unbounded.
- 4 (LOW): a quoted cd target is missed."
out=$(bash "$OI") || fail "open items failed"
[ "$out" = "https://github.com/o/r/issues/9" ] || fail "the new issue's URL was not printed ($out)"
has "$T/created" "Open findings from feat @ ${sha:0:7}"
has "$T/created" "- 2 (MEDIUM): the retry is unbounded."
has "$T/created" "- 4 (LOW): a quoted cd target is missed."
has "$T/created" "PR https://github.com/o/r/pull/3"
has "$T/created" "<!-- objection-open: sha=$sha -->"
hasnt "$T/created" "OPEN: BLOCKER"

# Again on the same commit: the existing issue, not a second one.
rm -f "$T/created"
node -e 'console.log(JSON.stringify([{url:"https://github.com/o/r/issues/5",body:"x\n<!-- objection-open: sha="+process.argv[1]+" -->"}]))' "$sha" >"$T/issues.json"
out=$(bash "$OI") || fail "second run failed"
[ "$out" = "https://github.com/o/r/issues/5" ] || fail "the existing issue was not printed ($out)"
[ -e "$T/created" ] && fail "a second issue was created for the same commit"
# An issue for another commit does not count.
node -e 'console.log(JSON.stringify([{url:"https://github.com/o/r/issues/5",body:"<!-- objection-open: sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb -->"}]))' >"$T/issues.json"
bash "$OI" >/dev/null || fail "run with another commit's issue failed"
[ -e "$T/created" ] || fail "another commit's issue stopped this one"

# --dry-run prints and creates nothing.
rm -f "$T/created"
out=$(bash "$OI" --dry-run) || fail "--dry-run failed"
printf '%s' "$out" | grep -qF "Open findings from feat" || fail "--dry-run printed no title"
[ -e "$T/created" ] && fail "--dry-run created an issue"
bash "$OI" --dryrun >/dev/null 2>&1 && fail "an unknown flag was accepted"

if [ "$failures" = 0 ]; then echo "open-issue: all cases passed"; else echo "open-issue: $failures failure(s)"; exit 1; fi
