#!/bin/bash
# Cases for skills/objection/pr-body.sh with a fake gh.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PB="$ROOT/skills/objection/pr-body.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks [$2]"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$1 has [$2]"; }

# gh: "pr view" prints $T/body when it exists (else fails: no PR);
# "pr edit --body-file f" copies f to $T/edited.
cat >"$T/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "pr view") [ -f "$FAKE/body" ] || exit 1; cat "$FAKE/head"; cat "$FAKE/body" ;;
  "pr edit") cp "$4" "$FAKE/edited" ;;
esac
STUB
chmod +x "$T/gh"
export OBJECTION_GH_BIN="$T/gh" FAKE="$T"

R="$T/r"
git init -q "$R" && cd "$R" || exit 1
printf 'x\n' >a && git add . && gitc commit -q -m a
sha=$(git rev-parse HEAD)

# No stamped record: refuses.
bash "$PB" >/dev/null 2>&1 && fail "wrote a body without a record"

mkdir -p .git/objection
printf '<!-- objection: sha=%s base=origin/main -->\n# Debate: new\nVERDICT: APPROVED\n' "$sha" >".git/objection/$sha.md"

# No PR yet: the summary, then the record.
out=$(OBJECTION_SUMMARY="Adds coupons." bash "$PB") || fail "no-PR body failed"
has "$out" "Adds coupons."
has "$out" "<!-- objection: sha=$sha"
[ "$(head -1 "$out")" = "Adds coupons." ] || fail "the summary is not first"
bash "$PB" --update >/dev/null 2>&1 && fail "--update without a PR succeeded"

# A PR with an old record: the description stays, the old record goes.
printf 'Adds coupons.\n\nCloses #3.\n\n<!-- objection: sha=0000000 base=origin/main -->\n# Debate: old\nVERDICT: APPROVED\n' >"$T/body"
git rev-parse HEAD~0 >/dev/null
echo 1111111111111111111111111111111111111111 >"$T/head"
bash "$PB" --update >/dev/null 2>&1 && fail "--update before the push succeeded"
git rev-parse HEAD >"$T/head"
out=$(bash "$PB" --update) || fail "--update failed"
edited="$T/edited"
has "$edited" "Closes #3."
has "$edited" "# Debate: new"
hasnt "$edited" "# Debate: old"
hasnt "$edited" "sha=0000000"
[ "$(grep -c 'objection: sha=' "$edited")" = 1 ] || fail "more than one record in the body"

# An empty PR body takes the summary; a typo in the flag is refused; a
# subdirectory finds the same record.
: >"$T/body"
OBJECTION_SUMMARY="Adds coupons." bash "$PB" --update >/dev/null || fail "--update on an empty body failed"
has "$T/edited" "Adds coupons."
bash "$PB" --updat >/dev/null 2>&1 && fail "an unknown flag was accepted"
mkdir -p sub && (cd sub && bash "$PB" >/dev/null) || fail "pr-body failed from a subdirectory"

[ "$failures" -eq 0 ] && echo "pr-body: all cases passed" || { echo "pr-body: $failures failure(s)"; exit 1; }
