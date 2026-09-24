#!/bin/bash
# Cases for gate/hook.mjs (core.mjs) and stamp.sh, including every bypass the
# hook's own two debate rounds found. Run: bash test/gate.test.sh
#
# Uses temporary repositories and a fake `gh` on PATH (answers
# "$STUB_SHA $STUB_BASE" to `gh pr view`), so it never talks to GitHub.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/skills/objection/gate/hook.mjs"
STAMP="$ROOT/skills/objection/stamp.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

gitc() { git -c user.email=t@t -c user.name=t "$@"; }
optin() { mkdir -p "$1/.claude" && printf '{"bases":["develop","master"],"defaultBase":"master"}\n' >"$1/.claude/objection.json"; }

git init -q "$T/ok" && optin "$T/ok" && gitc -C "$T/ok" add . && gitc -C "$T/ok" commit -q -m a
git init -q "$T/no" && optin "$T/no" && gitc -C "$T/no" add . && gitc -C "$T/no" commit -q -m b
git init -q "$T/off" && gitc -C "$T/off" commit -q --allow-empty -m c
OK_SHA=$(git -C "$T/ok" rev-parse HEAD)
mkdir -p "$T/ok/.git/objection"
stamp="<!-- objection: sha=$OK_SHA base=origin/develop -->"
printf '%s\n# x\nVERDICT: APPROVED\n' "$stamp" >"$T/ok/.git/objection/$OK_SHA.md"

mkdir "$T/bin"
cat >"$T/bin/gh" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "pr view" ]; then
  [ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
  # With STUB_WANT set ("<target> [-R <repo>]"), answer the approved SHA only
  # when exactly those arguments arrive: a stub that answers the same SHA
  # for any target cannot tell a right parse from a wrong one.
  shift 2
  args="$*"
  args="${args%% --json*}"
  [ -n "${STUB_LOG:-}" ] && printf '%s\n' "$args" >>"$STUB_LOG"
  if [ -n "${STUB_WANT:-}" ] && [ "$args" != "$STUB_WANT" ]; then
    echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef ${STUB_BASE:-develop}"; exit 0
  fi
  echo "$STUB_SHA ${STUB_BASE:-develop}"; exit 0
fi
# The repository default branch, as `gh repo view` reports it.
if [ "$1 $2" = "repo view" ]; then
  [ -n "${STUB_NO_REPO:-}" ] && exit 1
  # With STUB_REPO_WANT set, answer only when that repository is asked for.
  if [ -n "${STUB_REPO_WANT:-}" ] && [ "$3" != "$STUB_REPO_WANT" ]; then exit 1; fi
  echo "${STUB_DEFAULT:-master}"; exit 0
fi
exit 1
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

failures=0
check() { # expected cwd tool command
  local expected=$1 cwd=$2 tool=$3 cmd=$4 json rc
  json=$(node -e 'console.log(JSON.stringify({cwd:process.argv[1],tool_name:process.argv[2],tool_input:{command:process.argv[3]}}))' "$cwd" "$tool" "$cmd")
  printf '%s' "$json" | node "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "$expected" ]; then
    echo "FAIL (expected $expected, got $rc): [$tool] $cmd"
    failures=$((failures + 1))
  fi
}
O="$T/ok"; N="$T/no"; F="$T/off"

# Repository without .objection.json (or .claude/objection.json): nothing is enforced.
check 0 $F Bash 'gh pr create --fill'
check 0 $F Bash 'gh pr merge 5 --auto'
check 0 $F mcp__github__create_pull_request ''

# Not about a PR: allowed.
check 0 $N Bash 'git status'
check 0 $N Bash 'gh pr list'
check 0 $N Bash 'gh pr view 12'
check 0 $N Bash 'grep -nE "gh pr create|gh pr merge" hooks/x'
check 0 $N Bash 'echo "step: git push; gh pr create"'
check 0 $N Bash 'git commit -m "docs: run cd x && gh pr merge later"'
check 0 $N Bash "git commit -F - <<'EOF'
fix: something

gh pr merge not now
EOF"
check 0 $N Bash 'gh api repos/o/r/pulls'
check 0 $N Bash 'gh api repos/o/r/pulls -F per_page=100 --method GET'
check 0 $N Bash 'gh api repos/o/r/pulls/12/comments -f body=hi'
check 0 $N Bash 'gh api repos/o/r/pulls --jq ".[].number" | jq -r . && echo -f x'
check 0 $N mcp__github__get_pull_request ''

# No record: blocked, however it is called.
check 2 $N Bash 'gh pr create --fill'
check 2 $N Bash 'gh pr new --fill'
check 2 $N Bash 'gh -R o/r pr create --fill'
check 2 $N Bash 'gh --repo=o/r pr create'
check 2 $N Bash 'x=$(gh pr create --fill)'
check 2 $N Bash 'x="$(gh pr create --fill)"'
check 2 $N Bash "(cd $N && gh pr create)"
check 2 $N Bash 'if true; then gh pr create; fi'
check 2 $N Bash 'time gh pr create'
check 2 $N Bash 'command gh pr create'
check 2 $N Bash '/opt/homebrew/bin/gh pr create'
check 2 $N Bash 'GH_REPO=o/r gh pr create'
check 2 $N Bash "bash -c 'gh pr create'"
check 2 $N Bash 'rtk gh pr ready'
check 2 $N Bash "gh pr create --body \"\$(cat <<'EOF'
body
EOF
)\""
check 2 $O Bash "git status; cd $N && gh pr create"
check 2 $O Bash "cd '$N' && gh pr create"
check 2 $N Bash 'gh api repos/o/r/pulls -f title=x -f head=a'
check 2 $N Bash "gh api 'repos/o/r/pulls' --method POST --input x.json"
check 2 $N Bash 'gh api -X PUT repos/o/r/pulls/12/merge'
check 2 $N Bash 'gh api graphql -f query="mutation{mergePullRequest(input:{}){clientMutationId}}"'
check 2 $N mcp__plugin_engineering_github__create_pull_request ''
check 2 $N mcp__plugin_engineering_github__merge_pull_request ''
check 2 $N mcp__plugin_engineering_github__update_pull_request ''
check 2 $N mcp__ccd_pr__set_auto_merge ''

# APPROVED record for the right SHA and base: allowed.
check 0 $O Bash 'gh pr create --fill --base develop'
check 0 $N Bash "cd $O && gh pr create --base develop"
check 0 $N Bash "cd '$O' && gh pr create -B develop"
# A record debated against develop does not release a PR to master
# (defaultBase in the config is master).
check 2 $O Bash 'gh pr create --fill'
check 2 $O Bash 'gh pr create --fill --base master'
export STUB_SHA=$OK_SHA
check 0 $O Bash 'gh pr merge 5 --squash'
check 0 $O Bash 'gh pr merge -R o/r 5 --squash'
check 0 $O Bash 'gh pr merge --subject "a b" 5'
check 0 $O Bash 'gh pr ready 12'
check 2 $O Bash 'gh pr merge 5 --auto --squash'
export STUB_SHA=deadbeef
check 2 $O Bash 'gh pr merge 5 --squash'
check 2 $O Bash 'gh pr ready 12'
export STUB_SHA=$OK_SHA STUB_BASE=master
check 2 $O Bash 'gh pr merge 5 --squash'
export STUB_BASE=develop

# --- Second debate round (accusation with defender) ----------------------
export STUB_SHA=deadbeef
# Multi-line GraphQL and queries read from a file.
check 2 $N Bash "gh api graphql -f query='
mutation {
  mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}
}'"
check 2 $N Bash 'gh api graphql -F query=@m.graphql'
check 0 $N Bash 'gh api graphql -f query="query{viewer{login}}"'
# Hung gh: the hook blocks before the harness limit (internal timeout).
export STUB_SLEEP=20
start=$(date +%s)
check 2 $O Bash 'gh pr merge 5 --squash'
[ $(( $(date +%s) - start )) -lt 25 ] || { echo "FAIL: hook took over 25 s with a hung gh"; failures=$((failures + 1)); }
unset STUB_SLEEP
# -R/--repo after `pr`.
check 2 $N Bash 'gh pr -R o/r create --fill'
check 2 $N Bash 'gh pr --repo o/r merge 5'
# A shell reading stdin.
check 2 $N Bash "bash <<'EOF'
gh pr create --fill
EOF"
check 2 $N Bash "echo 'gh pr create --fill' | bash"
# Disguised names and a path in gh api.
check 2 $N Bash '\gh pr create'
check 2 $N Bash 'g\h pr create'
check 2 $N Bash '"gh" pr create'
check 2 $N Bash '/opt/homebrew/bin/gh api -X PUT repos/o/r/pulls/12/merge'
# Ambiguous directory: blocked even when the cwd has a record.
check 2 $O Bash "(cd $N); gh pr create --base develop"
check 2 $O Bash "pushd $N; gh pr create --base develop"
check 2 $O Bash "env -C $N gh pr create --base develop"
check 2 $O Bash "echo \"a cd $O b\"; cd $N && gh pr create --base develop"
check 0 $N Bash "(cd $O && gh pr create --base develop)"
# Target from stdin.
export STUB_SHA=$OK_SHA
check 2 $O Bash 'echo 99 | xargs gh pr merge --squash'
# MCP: short names blocked, PR review allowed.
check 2 $N mcp__x__create_pr ''
check 2 $N mcp__x__merge_pr ''
check 2 $N mcp__x__mark_pr_ready_for_review ''
check 0 $N mcp__github__create_pull_request_review ''
check 0 $N mcp__github__create_pr_comment ''
# A record without the stamp from stamp.sh does not count.
printf '# x\nVERDICT: APPROVED\n' >"$T/ok/.git/objection/$OK_SHA.md"
check 2 $O Bash 'gh pr create --fill --base develop'
printf '<!-- objection: sha=%s base=origin/develop -->\n# x\nVERDICT: APPROVED\n' "$(printf 'a%.0s' $(seq 40))" >"$T/ok/.git/objection/$OK_SHA.md"
check 2 $O Bash 'gh pr create --fill --base develop'
printf '%s\n# x\nVERDICT: APPROVED\n' "$stamp" >"$T/ok/.git/objection/$OK_SHA.md"
# Help and disabling auto-merge touch no PR.
export STUB_SHA=deadbeef
check 0 $N Bash 'gh pr create --help'
check 0 $N Bash 'gh pr merge --help'
check 0 $N Bash 'gh pr merge --disable-auto 5'

# --- stamp.sh ------------------------------------------------------------
R="$T/stamp"
git init -q "$R" && optin "$R" && gitc -C "$R" add . && gitc -C "$R" commit -q -m base
git -C "$R" update-ref refs/remotes/origin/develop HEAD
printf 'x\n' >"$R/a.ts" && git -C "$R" add a.ts && gitc -C "$R" commit -q -m code
printf '# doc\n' >"$R/b.md" && git -C "$R" add b.md && gitc -C "$R" commit -q -m doc
printf 'VERDICT: APPROVED\n' >"$T/min.md"
full() { # open-list [open-count] [verdict]
  printf '# D\n\n## Accusation\nx\n\n## Defense\nx\n\n## Judge\nx\n\n## Open\n%s\n\n%s\nVERDICT: %s\n' "$1" "${2:-OPEN: BLOCKER=0 HIGH=0}" "${3:-APPROVED}" >"$T/rec.md"
}
stampcheck() { # expected base record
  (cd "$R" && bash "$STAMP" "$3" "$2" >/dev/null 2>&1); local rc=$?
  if { [ "$1" = 0 ] && [ $rc != 0 ]; } || { [ "$1" != 0 ] && [ $rc = 0 ]; }; then
    echo "FAIL stamp (expected $1, got $rc): base=$2 record=$3"; failures=$((failures + 1))
  fi
}
# Arbitrary base (HEAD~1) would fall into the docs exemption.
stampcheck 1 HEAD~1 "$T/min.md"
stampcheck 1 origin/develop "$T/min.md"
full '- MEDIUM: no test for case X yet'
stampcheck 0 origin/develop "$T/rec.md"
head -1 "$R/.git/objection/$(git -C "$R" rev-parse HEAD).md" | grep -q "^<!-- objection: sha=$(git -C "$R" rev-parse HEAD) base=origin/develop -->$" \
  || { echo "FAIL: stamp.sh did not write the stamp"; failures=$((failures + 1)); }
full 'HIGH: no list marker'
stampcheck 1 origin/develop "$T/rec.md"
full '1. **High** bold severity'
stampcheck 1 origin/develop "$T/rec.md"
full 'no HIGH finding is left'
stampcheck 0 origin/develop "$T/rec.md"
# The cross-check reads the template's own "#, severity" order.
full '1 HIGH race on retry' 'OPEN: BLOCKER=0 HIGH=0'
stampcheck 1 origin/develop "$T/rec.md"
full '4, HIGH, x.ts:3, race' 'OPEN: BLOCKER=0 HIGH=0'
stampcheck 1 origin/develop "$T/rec.md"
full '1 MEDIUM highlight color off' 'OPEN: BLOCKER=0 HIGH=0'
stampcheck 0 origin/develop "$T/rec.md"
# The structured count is required and must be zero to approve.
full 'nothing' 'no count line here'
stampcheck 1 origin/develop "$T/rec.md"
full '- MEDIUM: x' 'OPEN: BLOCKER=0 HIGH=1'
stampcheck 1 origin/develop "$T/rec.md"
full '- HIGH: race on retry' 'OPEN: BLOCKER=0 HIGH=0'
stampcheck 1 origin/develop "$T/rec.md"
full '- HIGH: race on retry' 'OPEN: BLOCKER=0 HIGH=1' REJECTED
stampcheck 0 origin/develop "$T/rec.md"
# The debate's own prompts (.claude/*.md) are not "documentation only".
mkdir -p "$R/.claude/agents" && printf 'x\n' >"$R/.claude/agents/c.md"
git -C "$R" add .claude && gitc -C "$R" commit -q -m prompt
git -C "$R" update-ref refs/remotes/origin/develop HEAD~1
stampcheck 1 origin/develop "$T/min.md"
# Issue #9: nor are agents/, skills/, AGENTS.md or the objection config.
for f in agents/defender.md skills/objection/roles/defender.md AGENTS.md .objection.json; do
  mkdir -p "$R/$(dirname "$f")"
  # The config must stay valid JSON (stamp.sh reads it); any change will do.
  if [ "$f" = .objection.json ]; then printf '{"bases":["develop","master"],"budget":"lean"}\n' >"$R/$f"; else printf 'x\n' >"$R/$f"; fi
  git -C "$R" add "$f" && gitc -C "$R" commit -q -m "prompt $f"
  git -C "$R" update-ref refs/remotes/origin/develop HEAD~1
  stampcheck 1 origin/develop "$T/min.md"
done
# ...while a README change alone still is.
printf 'y\n' >>"$R/b.md" && git -C "$R" add b.md && gitc -C "$R" commit -q -m doc2
git -C "$R" update-ref refs/remotes/origin/develop HEAD~1
stampcheck 0 origin/develop "$T/min.md"
# Repository not opted in: stamp.sh refuses.
(cd "$F" && bash "$STAMP" "$T/rec.md" origin/main >/dev/null 2>&1) && { echo "FAIL: stamp.sh ran without objection.json"; failures=$((failures + 1)); }

# --- Lessons from the first adopter's six-round debate ----------------------
# Each natural form failed on the version before this fix (negative
# control), and each sits next to the innocent look-alike that must pass.
# A quoted value glued to the flag is still the repo flag: blocked without a record.
check 2 $N Bash 'gh --repo="o/r" pr create --fill'
check 2 $N Bash "gh --repo='o/r' pr create"
check 2 $N Bash 'gh pr --repo="o/r" merge 5'
# ...and with a record, the right target and repo reach gh pr view.
export STUB_SHA=$OK_SHA
STUB_WANT="5 -R o/r" check 0 $O Bash 'gh -R"o/r" pr merge 5'
STUB_WANT="5 -R o/r" check 0 $O Bash 'gh --repo="o/r" pr merge 5 --squash'
# -m and -r are --merge and --rebase, not flags that take a value.
STUB_WANT="338" check 0 $O Bash 'gh pr merge -m 338'
STUB_WANT="338" check 0 $O Bash 'gh pr merge -r 338'
STUB_WANT="338" check 0 $O Bash 'gh pr merge --squash --delete-branch 338'
# The stub can say no: another target is not approved.
STUB_WANT="999" check 2 $O Bash 'gh pr merge -m 338'
export STUB_SHA=deadbeef
# Innocent look-alikes keep passing.
check 0 $N Bash 'gh pr view --repo="o/r" 5'
check 0 $N Bash 'git commit -m "fix: run gh pr merge -m 5 later"'
check 0 $N Bash 'grep -c "gh pr create" notes.md'
check 0 $N Bash "psql -c \"select 'gh pr create'\""
check 0 $N Bash 'tar -czf out.tgz "gh pr merge 5"'
# -c executes only after something that runs code.
check 2 $N Bash "sh -c 'gh pr create'"
check 2 $N Bash "/usr/bin/env bash -c 'gh pr merge 5'"

# --- Round 2 of that fix: its own regressions ----------------------------
# Every "allowed with a record" case has its twin "blocked without one":
# a case that only expects 0 also passes when the gate never saw the
# command. And the stub log proves gh got the right target and repo.
called() { # expected-args
  if ! grep -qxF "$1" "$T/gh.log" 2>/dev/null; then
    echo "FAIL: gh pr view was not called with [$1] (log: $(tr '\n' '|' <"$T/gh.log" 2>/dev/null))"
    failures=$((failures + 1))
  fi
  : >"$T/gh.log"
}
export STUB_LOG="$T/gh.log"
: >"$T/gh.log"
# Short flags with a glued value, quoted or not.
check 2 $N Bash 'gh -R"o/r" pr merge 5'
check 2 $N Bash "gh -R'o/r' pr create --fill"
check 2 $N Bash 'gh pr -R"o/r" merge 5'
check 2 $N Bash 'gh -Ro/r pr create --fill'
check 2 $N Bash 'gh pr merge -R"o/r" 5'
export STUB_SHA=$OK_SHA
: >"$T/gh.log"
STUB_WANT="5 -R o/r" check 0 $O Bash 'gh -R"o/r" pr merge 5'; called "5 -R o/r"
STUB_WANT="5 -R o/r" check 0 $O Bash 'gh pr merge -R"o/r" 5'; called "5 -R o/r"
STUB_WANT="5 -R o/r" check 0 $O Bash 'gh pr merge -Ro/r 5'; called "5 -R o/r"
# A glued value with ( or ; must not hide the PR number.
check 2 $N Bash 'gh pr merge -t"feat(ui)" 42 --squash'
STUB_WANT="42" check 0 $O Bash 'gh pr merge -t"feat(ui)" 42 --squash'; called "42"
STUB_WANT="5" check 0 $O Bash 'gh pr merge --subject="fix(gate):x" 5'; called "5"
STUB_WANT="42" check 0 $O Bash 'gh pr merge --body="a;b" 42'; called "42"
export STUB_SHA=deadbeef
# Glued base and head are read, not dropped (the record is for develop).
check 0 $O Bash 'gh pr create -B"develop" --fill'
check 2 $O Bash 'gh pr create -B"master" --fill'
check 2 $O Bash 'gh pr create -Bmaster --fill'
check 2 $O Bash 'gh pr create -H"nonexistent" --base develop'
# Natural ways to run a shell command string.
check 2 $N Bash "bash -lc 'gh pr merge 5'"
check 2 $N Bash "sh -xc 'gh pr create --fill'"
check 2 $N Bash '$SHELL -c "gh pr merge 5"'
check 2 $N Bash '${SHELL:-bash} -c "gh pr create --fill"'
check 2 $N Bash "pwsh -c 'gh pr merge 5'"
check 2 $N Bash "python3 -c 'gh pr merge 5'"

# --- Round 4: a command substitution that does not run gh ------------------
# `$(...)` or backticks before the PR number used to cut the command at `)`,
# so gh looked up the wrong target and an innocent merge was blocked. Code
# that does not mention gh cannot create or merge a PR (short of disguise,
# LOW), so it becomes a placeholder like inert text.
export STUB_LOG="$T/gh.log" STUB_SHA=$OK_SHA
: >"$T/gh.log"
STUB_WANT="42" check 0 $O Bash 'gh pr merge -t "$(git log -1 --format=%s)" 42 --squash'; called "42"
STUB_WANT="42" check 0 $O Bash 'gh pr merge --body="$(cat notes.md)" 42'; called "42"
STUB_WANT="42" check 0 $O Bash 'gh pr merge -t $(git log -1 --format=%s) 42'; called "42"
STUB_WANT="42" check 0 $O Bash 'gh pr merge -t `git log -1 --format=%s` 42'; called "42"
STUB_WANT="42" check 0 $O Bash 'gh pr merge --subject "$(printf "%s" "$(git log -1 --format=%s)")" 42'; called "42"
export STUB_SHA=deadbeef
unset STUB_LOG
# Their twins without a record stay blocked...
check 2 $N Bash 'gh pr merge -t "$(git log -1 --format=%s)" 42 --squash'
check 2 $N Bash 'gh pr merge -t $(git log -1 --format=%s) 42'
# ...and a substitution that does run gh is still code.
check 2 $N Bash 'x="$(gh pr create --fill)"'
check 2 $N Bash 'echo $(gh pr merge 5)'
check 2 $N Bash 'echo `gh pr merge 5`'
check 2 $N Bash "bash -c 'gh pr merge 5'"

# --- Round 5: what the round-4 accuser found in that fix -------------------
export STUB_SHA=$OK_SHA STUB_LOG="$T/gh.log"
: >"$T/gh.log"
# A PR number the gate cannot read is blocked, even when the current
# branch's PR has a record (it used to check that one instead).
check 2 $O Bash 'gh pr merge $(cat .pr-number) --squash'
check 2 $O Bash 'gh pr merge "$(jq -r .number pr.json)"'
check 2 $O Bash 'gh pr ready `cat .pr`'
check 2 $O Bash 'gh pr merge $((40+2))'
check 2 $O Bash 'gh pr merge "$PR" --squash'
check 2 $O Bash 'gh pr merge $PR'
# ...while a literal number with a substitution elsewhere still works.
STUB_WANT="7" check 0 $O Bash 'gh pr merge 7 -t "$(cd sub && git log -1 --format=%s)"'; called "7"
STUB_WANT="7" check 0 $O Bash 'gh pr merge 7 -t $(cd sub && git log -1 --format=%s)'; called "7"
unset STUB_LOG
export STUB_SHA=deadbeef
# Prose that names gh next to an innocent substitution is not a command.
check 0 $N Bash 'git commit -m "docs: explain gh pr merge ($(date +%F))"'
check 0 $N Bash 'echo "run gh pr create after $(date)"'
# ...but a substitution that runs gh inside a message still counts.
check 2 $N Bash 'echo "created: $(gh pr create --fill)"'
# Going back to the repository root with a substitution is resolved, not
# read as a literal path; its twin without a record stays blocked.
mkdir -p "$O/sub" "$N/sub"
STUB_SHA=$OK_SHA STUB_WANT="12" check 0 "$O/sub" Bash 'cd "$(git rev-parse --show-toplevel)" && gh pr merge 12'
STUB_SHA=$OK_SHA STUB_WANT="12" check 0 "$O/sub" Bash 'cd $(git rev-parse --show-toplevel) && gh pr merge 12'
check 2 "$N/sub" Bash 'cd "$(git rev-parse --show-toplevel)" && gh pr merge 12'
# Deep nesting does not crash the hook (a crash is a non-blocking error).
deep="gh pr merge 7 -t "$(printf '"$(echo %.0s' $(seq 5000))
check 2 $N Bash "$deep"
# (A quoted interpreter, "$SHELL" -c, is LOW by the threat model: treating
# any quoted word as an interpreter blocked the searches below.)
# ...and their innocent look-alikes, from the round-3 accuser.
check 0 $N Bash 'grep -rc "gh pr merge" docs'
check 0 $N Bash "node --check 'gh pr merge.js'"
check 0 $N Bash 'rg -g "*.md" -c "gh pr create"'
check 0 $N Bash 'grep --include "*.md" -rc "gh pr merge" .'
check 0 $N Bash "grep \"foo\" -c 'gh pr merge' f"
check 0 $N Bash "find docs -name \"*.md\" -exec grep -c 'gh pr merge' {} +"
check 0 $N Bash "perl -pe 's/gh pr create/x/' f"
check 0 $N Bash "perl -i -pe 's/gh pr merge 5/x/' docs.md"
check 0 $N Bash "perl -ne 'print if /gh pr merge/' f"
check 0 $N Bash "ruby -ne 'puts \$_ if /gh pr merge 5/' f"
check 0 $N Bash "python3 tool.py -vc 'gh pr merge 5'"
check 0 $N Bash "psql -c 'select 1' -c \"gh pr merge 5\""
unset STUB_LOG

# --- External review (issue #9) --------------------------------------------
# The base without --base is the one gh uses: the branch's gh-merge-base,
# else the repository default on GitHub, never .objection.json's
# defaultBase (master in this fixture; the record is for develop).
cur=$(git -C "$O" symbolic-ref --short HEAD)
STUB_DEFAULT=develop check 0 $O Bash 'gh pr create --fill'
STUB_DEFAULT=master check 2 $O Bash 'gh pr create --fill'
git -C "$O" config "branch.$cur.gh-merge-base" develop
STUB_DEFAULT=master check 0 $O Bash 'gh pr create --fill'
git -C "$O" config --unset "branch.$cur.gh-merge-base"
STUB_DEFAULT=develop STUB_NO_REPO=1 check 2 $O Bash 'gh pr create --fill'
# --head is checked against the branch on origin, not a local branch with
# the same name. Local feat is at the approved commit; origin/feat is not.
git init -q --bare "$T/remote.git"
git -C "$O" remote add origin "$T/remote.git"
git -C "$O" branch feat "$OK_SHA"
git -C "$O" push -q origin feat
check 0 $O Bash 'gh pr create --head feat --base develop'
git clone -q "$T/remote.git" "$T/other" 2>/dev/null
git -C "$T/other" checkout -q feat
gitc -C "$T/other" commit -q --allow-empty -m "someone else's commit"
git -C "$T/other" push -q origin feat
check 2 $O Bash 'gh pr create --head feat --base develop'
check 2 $O Bash 'gh pr create -H feat -B develop'
# A branch that is not on origin, and a fork's branch, cannot be checked.
git -C "$O" branch local-only "$OK_SHA"
check 2 $O Bash 'gh pr create --head local-only --base develop'
check 2 $O Bash 'gh pr create --head victorserpa:feat --base develop'
check 2 $O Bash 'gh pr create --head=someone:feat --base develop'
# Round 1 of that fix: the remote is found, not assumed to be origin.
git init -q "$T/named" && optin "$T/named" && gitc -C "$T/named" add . && gitc -C "$T/named" commit -q -m n
NAMED_SHA=$(git -C "$T/named" rev-parse HEAD)
mkdir -p "$T/named/.git/objection"
printf '<!-- objection: sha=%s base=origin/develop -->\n# x\nVERDICT: APPROVED\n' "$NAMED_SHA" >"$T/named/.git/objection/$NAMED_SHA.md"
git init -q --bare "$T/gh-remote.git"
git -C "$T/named" remote add github "$T/gh-remote.git"
git -C "$T/named" branch feat "$NAMED_SHA"
git -C "$T/named" push -q -u github feat
check 0 "$T/named" Bash 'gh pr create --head feat --base develop'
git -C "$T/named" branch unpushed "$NAMED_SHA"
check 2 "$T/named" Bash 'gh pr create --head unpushed --base develop'
# A fork's branch is read from the remote under that owner.
mkdir -p "$T/me" && git init -q --bare "$T/me/repo.git"
git -C "$T/named" remote add fork "$T/me/repo.git"
git -C "$T/named" push -q fork feat
check 0 "$T/named" Bash 'gh pr create --head me:feat --base develop -R up/repo'
check 2 "$T/named" Bash 'gh pr create --head stranger:feat --base develop -R up/repo'
gitc -C "$T/named" commit -q --allow-empty -m later
git -C "$T/named" push -q fork HEAD:feat
git -C "$T/named" reset -q --hard "$NAMED_SHA"
check 2 "$T/named" Bash 'gh pr create --head me:feat --base develop -R up/repo'
# -R picks the remote that matches it, and reaches gh repo view.
git init -q --bare "$T/up/repo.git" 2>/dev/null || { mkdir -p "$T/up" && git init -q --bare "$T/up/repo.git"; }
git -C "$T/named" remote add upstream "$T/up/repo.git"
git -C "$T/named" push -q upstream feat
STUB_DEFAULT=develop STUB_REPO_WANT=up/repo check 0 "$T/named" Bash 'gh pr create -R up/repo --head feat'
STUB_DEFAULT=develop STUB_REPO_WANT=other/repo check 2 "$T/named" Bash 'gh pr create -R up/repo --head feat'

# --- Other hosts' input shapes ----------------------------------------------
hostcheck() { # expected host json
  local rc
  printf '%s' "$3" | node "$HOOK" --host "$2" >"$T/out" 2>/dev/null
  rc=$?
  if [ "$rc" != "$1" ]; then echo "FAIL host $2 (expected $1, got $rc): $3"; failures=$((failures + 1)); fi
}
# JSON builders (inline JSON in bash gets brace-expanded).
cursor_shell() { node -e "console.log(JSON.stringify({command:process.argv[1],cwd:process.argv[2]}))" "$1" "$N"; }
cursor_mcp() { node -e "console.log(JSON.stringify({tool_name:process.argv[1],tool_input:{},mcp_server_name:\"github\",cwd:process.argv[2]}))" "$1" "$N"; }
tool_cmd() { node -e "console.log(JSON.stringify({tool_name:process.argv[1],tool_input:{command:process.argv[2]},cwd:process.argv[3]}))" "$1" "$2" "$N"; }
# Cursor beforeShellExecution: { command, cwd }; verdict JSON on stdout.
hostcheck 2 cursor "$(cursor_shell "gh pr create --fill")"
grep -q "\"permission\":\"deny\"" "$T/out" || { echo "FAIL: cursor deny JSON missing"; failures=$((failures + 1)); }
hostcheck 0 cursor "$(cursor_shell "git status")"
grep -q "\"permission\":\"allow\"" "$T/out" || { echo "FAIL: cursor allow JSON missing"; failures=$((failures + 1)); }
# Cursor beforeMCPExecution: { tool_name, tool_input, mcp_server_name }.
hostcheck 2 cursor "$(cursor_mcp create_pull_request)"
hostcheck 0 cursor "$(cursor_mcp get_pull_request)"
# Codex PreToolUse and Gemini BeforeTool: { tool_name, tool_input: { command }, cwd }.
hostcheck 2 codex "$(tool_cmd Bash "gh pr create")"
hostcheck 2 gemini "$(tool_cmd run_shell_command "gh pr merge 5")"
hostcheck 0 gemini "$(tool_cmd read_file "")"
# Tool-neutral opt-in file at the repository root.
git init -q "$T/neutral" && printf '{"bases":["main"]}\n' >"$T/neutral/.objection.json" && gitc -C "$T/neutral" add . && gitc -C "$T/neutral" commit -q -m n
check 2 "$T/neutral" Bash 'gh pr create --fill'

# A record quoting APPROVED but ending REJECTED: blocked.
printf '%s\n# x\nexample: VERDICT: APPROVED\nVERDICT: APPROVED\nVERDICT: REJECTED\n' "$stamp" >"$T/ok/.git/objection/$OK_SHA.md"
check 2 $O Bash 'gh pr create --fill --base develop'

if [ "$failures" = 0 ]; then echo "gate: all cases passed"; else echo "gate: $failures failure(s)"; exit 1; fi
