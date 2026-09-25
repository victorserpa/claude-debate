#!/bin/bash
# Cases for core/check-pr.mjs (the GitHub check). Synthetic pull_request
# events; OBJECTION_FILES stands in for the PR file list, so no network.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/skills/objection/gate/check-pr.mjs"
T=$(mktemp -d)
export SUITE_PID=$$
srv="" ghsrv=""
trap 'kill $srv $ghsrv 2>/dev/null; rm -rf "$T"' EXIT

HEAD=$(printf 'a%.0s' $(seq 40))
OLD=$(printf 'b%.0s' $(seq 40))
failures=0

run() { # expected files body
  local expected=$1 files=$2 body=$3 rc
  # CHANGED sets pull_request.changed_files (the real count), when a case needs it.
  node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({pull_request:{number:1,head:{sha:process.argv[2]},base:{ref:"main"},body:process.argv[3],changed_files:process.env.CHANGED?+process.env.CHANGED:undefined},repository:{full_name:"o/r"}}))' "$T/event.json" "$HEAD" "$body"
  GITHUB_EVENT_PATH="$T/event.json" OBJECTION_FILES="$files" node "$CHECK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "$expected" ]; then
    echo "FAIL (expected $expected, got $rc): files=[$files] body=$(printf '%s' "$body" | head -c 120 | tr '\n' '|')"
    failures=$((failures + 1))
  fi
}

record() { # sha base open verdicts...
  local sha=$1 base=$2 open=$3; shift 3
  printf '<!-- objection: sha=%s base=%s -->\n# Debate\n\n## Accusation\n1 HIGH x\n\n## Defense\n1 UPHELD\n\n## Judge\n1 fixed\n\n## Open\n%s\n\n%s\n' "$sha" "$base" "$open" "${OPENLINE-OPEN: BLOCKER=0 HIGH=0}"
  for v in "$@"; do printf 'VERDICT: %s\n' "$v"; done
}

CODE='src/a.ts'
run 0 "$CODE" "Summary above.

$(record $HEAD origin/main nothing APPROVED)"
run 1 "$CODE" "no record here"
# A body edited in the browser comes back with CRLF line ends.
run 0 "$CODE" "$(record $HEAD origin/main nothing APPROVED | sed 's/$/\r/')"
# Documentation is decided by extension: a file under docs/ can be code.
DOCREC="$(printf '<!-- objection: sha=%s base=origin/main -->\nVERDICT: APPROVED\n' "$HEAD")"
run 0 "docs/guide.md" "$DOCREC"
run 1 "docs/conf.py" "$DOCREC"
# requirements.txt and CMakeLists.txt change the build.
run 1 "requirements.txt" "$DOCREC"
run 1 "CMakeLists.txt" "$DOCREC"
run 1 "docs/.vitepress/config.mts" "$DOCREC"
run 1 "$CODE" "$(record $OLD origin/main nothing APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/develop nothing APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/main nothing APPROVED REJECTED)"
run 1 "$CODE" "$(record $HEAD origin/main '- HIGH: race on retry' APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/main '1. **Blocker** data loss' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '- MEDIUM: falta teste' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main 'no HIGH finding is left' APPROVED)"
# The last stamp wins: an old approved record below a new rejected one.
run 1 "$CODE" "$(record $OLD origin/main nothing APPROVED)
$(record $HEAD origin/main nothing REJECTED)"
run 0 "$CODE" "$(record $OLD origin/main nothing REJECTED)
$(record $HEAD origin/main nothing APPROVED)"
# The cross-check reads the template's own "#, severity" order.
run 1 "$CODE" "$(record $HEAD origin/main '1 HIGH race on retry' APPROVED)"
run 1 "$CODE" "$(record $HEAD origin/main '4, HIGH, x.ts:3, race' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '1 MEDIUM highlight color off' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '10, high-level note' APPROVED)"
run 0 "$CODE" "$(record $HEAD origin/main '- High-risk area untouched (MEDIUM)' APPROVED)"
# Every numbered finding needs a ruling: a list, a table row, a range.
ruled() { # accusation judge
  printf '<!-- objection: sha=%s base=origin/main -->\nobjection 0.13.0; config c; accuser a at effort e; defender d at effort e.\n## Accusation\n%s\n## Defense\nx\n## Judge\n%s\n## Open\nnothing\nOPEN: BLOCKER=0 HIGH=0\nVERDICT: APPROVED\n' "$HEAD" "$1" "$2"
}
run 0 "$CODE" "$(ruled '1. HIGH, BUG, a.ts:3: x
2. LOW: y' '1. UPHELD, fixed.
2. LOW, open.')"
run 1 "$CODE" "$(ruled '1. HIGH, BUG, a.ts:3: x
2. LOW: y' '1. UPHELD, fixed.')"
run 1 "$CODE" "$(ruled '| 1 | HIGH | BUG | a.ts:3 | x | read | p |
| 2 | LOW | BUG | a.ts:4 | y | read | p |' '2. REFUTED.')"
run 0 "$CODE" "$(ruled '| 1 | HIGH | BUG | a.ts:3 | x | read | p |
| 2 | LOW | BUG | a.ts:4 | y | read | p |
3. MEDIUM: z' '1-2. UPHELD, fixed in abc1234.
3) REFUTED by test.')"
run 0 "$CODE" "$(ruled '1. x
2. y
3. z
4. w' '1, 2 and 4: fixed.
3: kept LOW.')"
# A number inside the text is not a finding; the Defense does not rule.
run 0 "$CODE" "$(ruled 'Round 1 found 3 issues, see #20.' 'Nothing to rule on.')"
run 1 "$CODE" "$(ruled '1. HIGH: x' 'The defense said 1. UPHELD.')"
# A list finding with no severity word still needs its ruling.
run 1 "$CODE" "$(ruled '1. the cart total goes negative' 'Nothing to rule on.')"
# A Judge table rules too.
run 0 "$CODE" "$(ruled '| 1 | HIGH | BUG | a.ts:3 | x | read | p |' '| # | ruling |
|---|---|
| 1 | UPHELD, fixed |')"
# A record drafted before 0.13 (no version line) is not held to the rule.
run 0 "$CODE" "$(ruled '1. HIGH: x' 'All refuted.' | grep -v '^objection 0')"

# The structured count: required, and zero to approve.
OPENLINE="" run 1 "$CODE" "$(OPENLINE="" record $HEAD origin/main nothing APPROVED)"
run 1 "$CODE" "$(OPENLINE="OPEN: BLOCKER=0 HIGH=1" record $HEAD origin/main '- MEDIUM: x' APPROVED)"
run 1 "$CODE" "$(OPENLINE="OPEN: BLOCKER=1 HIGH=0" record $HEAD origin/main nothing APPROVED)"
# Missing sections on a code diff.
run 1 "$CODE" "<!-- objection: sha=$HEAD base=origin/main -->
VERDICT: APPROVED"
# Docs-only diff: sections not required, verdict still is.
run 0 "README.md
docs/x.md" "<!-- objection: sha=$HEAD base=origin/main -->
documentation only
VERDICT: APPROVED"
run 1 "README.md" "<!-- objection: sha=$HEAD base=origin/main -->
documentation only
VERDICT: REJECTED"
# Agent prompts are not documentation.
run 1 ".claude/agents/defender.md" "<!-- objection: sha=$HEAD base=origin/main -->
VERDICT: APPROVED"
run 1 ".cursor/rules/x.md" "<!-- objection: sha=$HEAD base=origin/main -->
VERDICT: APPROVED"
# Issue #9: the objection prompts, instructions and config are never
# "documentation only", wherever they live.
DOCREC="<!-- objection: sha=$HEAD base=origin/main -->
documentation only
VERDICT: APPROVED"
for f in agents/defender.md skills/objection/roles/defender.md skills/objection/SKILL.md \
  AGENTS.md CLAUDE.md GEMINI.md .objection.json .objection/precedents.md .agents/skills/x/SKILL.md; do
  run 1 "$f" "$DOCREC"
done
run 0 "docs/guide.md" "$DOCREC"
run 0 "README.md" "$DOCREC"
# ...at any depth for config dirs and instruction files; agents/ and
# skills/ only at the root (docs/agents/ is ordinary documentation).
for f in packages/web/CLAUDE.md sub/AGENTS.md pkg/.claude/agents/x.md apps/api/.cursor/rules/r.md; do
  run 1 "$f" "$DOCREC"
done
run 0 "docs/agents/overview.md" "$DOCREC"
run 0 "docs/skills/guide.md" "$DOCREC"
# Issue #9: a file list that hits the API limit, or is shorter than the
# PR's own count, proves nothing about the rest.
many=$(for i in $(seq 3000); do echo "docs/f$i.md"; done)
CHANGED=3001 run 1 "$many" "$DOCREC"
CHANGED=3 run 1 "$(printf 'docs/a.md\ndocs/b.md')" "$DOCREC"
CHANGED=2 run 0 "$(printf 'docs/a.md\ndocs/b.md')" "$DOCREC"

# --- GitLab CI (merge request pipelines) ------------------------------------
# The merge request comes from OBJECTION_MR_JSON (the API answer); the file
# list from git, against the MR's diff base, in a real repository.
G="$T/gl"
git init -q "$G" && cd "$G" || exit 1
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
printf 'a\n' >README.md && git add . && gitc commit -q -m base
GBASE=$(git rev-parse HEAD)
printf 'b\n' >>README.md && git add . && gitc commit -q -m docs
GDOCS=$(git rev-parse HEAD)
mkdir -p src && printf 'c\n' >src/x.ts && git add . && gitc commit -q -m code
GCODE=$(git rev-parse HEAD)
glrun() { # expected sha target body [iid]
  node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({sha:process.argv[2],target_branch:process.argv[3],description:process.argv[4]}))' "$T/mr.json" "$2" "$3" "$4"
  GITLAB_CI=true CI_MERGE_REQUEST_IID="${5-7}" CI_MERGE_REQUEST_DIFF_BASE_SHA="$GBASE" OBJECTION_MR_JSON="$T/mr.json" \
    node "$CHECK" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" != "$1" ]; then echo "FAIL gitlab (expected $1, got $rc): sha=${2:0:7} target=$3"; failures=$((failures + 1)); fi
}
full() { printf '<!-- objection: sha=%s base=origin/%s -->\n## Accusation\nx\n## Defense\nx\n## Judge\nx\n## Open\nnothing\nOPEN: BLOCKER=0 HIGH=0\nVERDICT: APPROVED\n' "$1" "$2"; }
short() { printf '<!-- objection: sha=%s base=origin/%s -->\ndocumentation only\nVERDICT: APPROVED\n' "$1" "$2"; }
glrun 0 "$GCODE" main "$(full "$GCODE" main)"
glrun 1 "$GCODE" main "$(full "$GDOCS" main)"
glrun 1 "$GCODE" develop "$(full "$GCODE" main)"
glrun 1 "$GCODE" main "no record here"
# The file list is read from git: code needs the sections, docs do not.
glrun 1 "$GCODE" main "$(short "$GCODE" main)"
glrun 0 "$GDOCS" main "$(short "$GDOCS" main)"
# An empty diff proves nothing: refused, not passed as documentation.
glrun 1 "$GBASE" main "$(short "$GBASE" main)"
# The API path: a local server stands in for GitLab. The job token is sent;
# a refused token falls back to the description variable when it is whole,
# and fails when it was cut.
node -e '
const http = require("http");
const fs = require("fs");
const s = http.createServer((q, r) => {
  fs.appendFileSync(process.argv[1], (q.headers["job-token"] || "-") + " " + q.url + "\n");
  if (q.headers["job-token"] !== "good") { r.statusCode = 403; return r.end("{}"); }
  r.setHeader("content-type", "application/json");
  r.end(fs.readFileSync(process.argv[2]));
}).listen(0, "127.0.0.1", () => fs.writeFileSync(process.argv[3], String(s.address().port)));
setTimeout(() => process.exit(0), 120000);
// Gone with the suite, even when it is killed: poll the shell that started it.
setInterval(() => { try { process.kill(+process.env.SUITE_PID, 0); } catch { process.exit(0); } }, 500).unref();
' "$T/api.log" "$T/mr.json" "$T/port" &
srv=$!
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
api="http://127.0.0.1:$(cat "$T/port")/api/v4"
node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({sha:process.argv[2],target_branch:"main",description:process.argv[3]}))' "$T/mr.json" "$GCODE" "$(full "$GCODE" main)"
apirun() { # expected token description truncated
  GITLAB_CI=true CI_MERGE_REQUEST_IID=7 CI_PROJECT_ID=42 CI_API_V4_URL="$api" CI_JOB_TOKEN="$2" \
    CI_MERGE_REQUEST_DIFF_BASE_SHA="$GBASE" CI_COMMIT_SHA="$GCODE" CI_MERGE_REQUEST_TARGET_BRANCH_NAME=main \
    CI_MERGE_REQUEST_DESCRIPTION="$3" CI_MERGE_REQUEST_DESCRIPTION_IS_TRUNCATED="$4" node "$CHECK" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "$1" ] || { echo "FAIL gitlab api (expected $1, got $rc): token=$2 truncated=$4"; failures=$((failures + 1)); }
}
apirun 0 good "" false
grep -q "^good /api/v4/projects/42/merge_requests/7$" "$T/api.log" || { echo "FAIL: the MR was not read with the job token"; failures=$((failures + 1)); }
apirun 0 bad "$(full "$GCODE" main)" false
apirun 1 bad "$(full "$GCODE" main)" true
apirun 1 bad "" false
# Older GitLab sets no truncation flag: a description of 2700 characters or
# more is taken as cut.
long="$(printf 'x%.0s' $(seq 2700))
$(full "$GCODE" main)"
apirun 1 bad "$long" ""
# An explicit "not truncated" is believed over the length guess.
apirun 0 bad "$long" false
# ...while the same record, short, passes on that fallback.
apirun 0 bad "$(full "$GCODE" main)" ""
kill $srv 2>/dev/null; wait $srv 2>/dev/null
# Outside a merge request pipeline: refuse.
glrun 1 "$GCODE" main "$(full "$GCODE" main)" ""
cd "$T" || exit 1

# --- The GitHub files API: a local server stands in for it. A rename is one
# entry (and one in changed_files) but counts under both names.
node -e '
const http = require("http");
const fs = require("fs");
const s = http.createServer((q, r) => {
  r.setHeader("content-type", "application/json");
  r.end(fs.readFileSync(process.argv[1]));
}).listen(0, "127.0.0.1", () => fs.writeFileSync(process.argv[2], String(s.address().port)));
setTimeout(() => process.exit(0), 120000);
// Gone with the suite, even when it is killed: poll the shell that started it.
setInterval(() => { try { process.kill(+process.env.SUITE_PID, 0); } catch { process.exit(0); } }, 500).unref();
' "$T/files.json" "$T/ghport" &
ghsrv=$!
for _ in $(seq 50); do [ -s "$T/ghport" ] && break; sleep 0.1; done
ghrun() { # expected files-json changed body
  printf '%s' "$2" >"$T/files.json"
  node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({pull_request:{number:1,head:{sha:process.argv[2]},base:{ref:"main"},body:process.argv[3],changed_files:+process.argv[4]},repository:{full_name:"o/r"}}))' "$T/event.json" "$HEAD" "$4" "$3"
  GITHUB_EVENT_PATH="$T/event.json" GITHUB_API_URL="http://127.0.0.1:$(cat "$T/ghport")" GITHUB_TOKEN=t node "$CHECK" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "$1" ] || { echo "FAIL github api (expected $1, got $rc): $2"; failures=$((failures + 1)); }
}
RENAMED='[{"filename":"src/b.ts","previous_filename":"src/a.ts"}]'
ghrun 0 "$RENAMED" 1 "$(record $HEAD origin/main nothing APPROVED)"
# Code renamed to .md is not documentation: the old name counts.
ghrun 1 '[{"filename":"docs/a.md","previous_filename":"src/a.ts"}]' 1 "$DOCREC"
ghrun 0 '[{"filename":"docs/b.md","previous_filename":"docs/a.md"}]' 1 "$DOCREC"
ghrun 1 "$RENAMED" 2 "$(record $HEAD origin/main nothing APPROVED)"
kill $ghsrv 2>/dev/null; wait $ghsrv 2>/dev/null

if [ "$failures" = 0 ]; then echo "check-pr: all cases passed"; else echo "check-pr: $failures failure(s)"; exit 1; fi
