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
  "pr view")
    [ -f "$FAKE/body" ] || exit 1
    case "$*" in
      *"-q .headRefOid") cat "$FAKE/head" ;;
      *) cat "$FAKE/head"; cat "$FAKE/body" ;;
    esac
    # A push GitHub has not seen yet: the next view reports the new head.
    [ ! -f "$FAKE/head-next" ] || mv "$FAKE/head-next" "$FAKE/head" ;;
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
# Text the author put below the old record stays below the new one.
printf 'Adds coupons.\n\n<!-- objection: sha=0000000 base=origin/main -->\n# Debate: old\nOPEN: BLOCKER=0 HIGH=0\nVERDICT: APPROVED\n\n## Screenshots\n![after](x.png)\n\nCloses #12.\n' >"$T/body"
bash "$PB" --update >/dev/null || fail "--update with text below the record failed"
has "$edited" "## Screenshots"
has "$edited" "Closes #12."
hasnt "$edited" "# Debate: old"
awk '/Debate: new/ { n = NR } /Closes #12/ { c = NR } END { exit !(n && c > n) }' "$edited" || fail "the text below the record did not stay below it"

# An empty PR body takes the summary; a typo in the flag is refused; a
# subdirectory finds the same record.
: >"$T/body"
OBJECTION_SUMMARY="Adds coupons." bash "$PB" --update >/dev/null || fail "--update on an empty body failed"
has "$T/edited" "Adds coupons."
bash "$PB" --updat >/dev/null 2>&1 && fail "an unknown flag was accepted"
top_out=$(bash "$PB")
mkdir -p sub && sub_out=$(cd sub && bash "$PB") || fail "pr-body failed from a subdirectory"
[ "$sub_out" = "$top_out" ] || fail "a subdirectory wrote another body ($sub_out)"

# A full record: the accusation and the defense fold under <details>, the
# rulings stay in view, and the CI check still reads the body.
rm -f "$T/body"
printf '<!-- objection: sha=%s base=origin/main -->\n# Debate: full\n\n## Accusation\n\n| # | severity | kind | file:line | defect | evidence | proof |\n|---|---|---|---|---|---|---|\n| 1 | HIGH | BUG | a:1 | x | read | p |\n| 2 | LOW | BUG | a:2 | y | read | p |\n\n## Defense\n\n| # | verdict | evidence | kind | sentence |\n|---|---|---|---|---|\n| 1 | UPHELD | a:1 | read | s |\n\n## Judge\n\n1. fixed.\n2. open.\n\n## Open\n\n- 2 (LOW)\n\nOPEN: BLOCKER=0 HIGH=0\nVERDICT: APPROVED\n' "$(git rev-parse HEAD)" >".git/objection/$(git rev-parse HEAD).md"
out=$(OBJECTION_SUMMARY="Summary." bash "$PB") && [ -s "$out" ] || { fail "full-record body failed"; out=/dev/null; }
has "$out" "<summary>Accusation and defense (2 findings)</summary>"
awk '/^<details>$/{d=NR} /^## Accusation$/{a=NR} /^## Defense$/{f=NR} /^<\/details>$/{e=NR} /^## Judge$/{j=NR} END { exit !(d < a && a < f && f < e && e < j) }' "$out" ||
  fail "the fold is not around the accusation and the defense only"
node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({pull_request:{number:1,head:{sha:process.argv[2]},base:{ref:"main"},body:require("fs").readFileSync(process.argv[3],"utf8")},repository:{full_name:"o/r"}}))' "$T/event.json" "$(git rev-parse HEAD)" "$out"
GITHUB_EVENT_PATH="$T/event.json" OBJECTION_FILES="src/a.ts" node "$ROOT/skills/objection/gate/check-pr.mjs" >/dev/null 2>&1 || fail "the CI check refused a folded body"

# Right after a push, GitHub still reports the old head: when the pushed
# branch has the SHA, --update waits for it instead of refusing.
git init -q --bare "$T/remote.git" && git remote add origin "$T/remote.git" 2>/dev/null
git push -q -u origin HEAD:refs/heads/lag 2>/dev/null && git branch -q --set-upstream-to=origin/lag
printf 'Body.\n' >"$T/body"; echo 2222222222222222222222222222222222222222 >"$T/head"; git rev-parse HEAD >"$T/head-next"
OBJECTION_PR_WAIT=0 bash "$PB" --update >/dev/null 2>&1 || fail "--update did not wait for GitHub to see the push"
# An unpushed SHA is still refused at once.
echo 2222222222222222222222222222222222222222 >"$T/head"; rm -f "$T/head-next"
printf 'y\n' >>a && git add . && gitc commit -q -m unpushed
u=$(git rev-parse HEAD); printf '<!-- objection: sha=%s base=origin/main -->\n# Debate: u\nVERDICT: APPROVED\n' "$u" >".git/objection/$u.md"
err=$(OBJECTION_PR_WAIT=0 bash "$PB" --update 2>&1 >/dev/null) && fail "--update accepted an unpushed SHA"
case "$err" in *"push, then update"*) ;; *) fail "an unpushed SHA was refused for another reason ($err)" ;; esac

[ "$failures" -eq 0 ] && echo "pr-body: all cases passed" || { echo "pr-body: $failures failure(s)"; exit 1; }
