#!/bin/bash
# The accuser, run by CI on a pull request, outside the agent's reach.
#
#   ci-review.sh     (inside a GitHub Actions job, see action.yml; or a
#                     GitLab merge request job, see
#                     templates/gitlab/objection-review.gitlab-ci.yml)
#
# Why: the record in the PR body is written on the agent's machine, with
# the user's credentials, so an agent can forge one. This run happens on
# GitHub's runner with a key the agent never sees, on the head SHA GitHub
# reports, and fails the check when the accuser finds a BLOCKER (or a
# HIGH, with OBJECTION_FAIL_ON=high). It is a barrier only if the agent's
# token cannot bypass the ruleset or edit the workflow on the base branch.
#
# The PR's code is data here: nothing from it is checked out or run. The
# base branch and the PR head are fetched into an empty repository, HEAD
# is pointed at the head commit without writing its files, and brief.sh
# and review.sh (from this action, not from the PR) read the commits.
# The rules (config, precedents) come from the base branch, as always.
#
# Env: OBJECTION_RUNNER (claude or gemini; default claude),
#      ANTHROPIC_API_KEY (required for claude), GEMINI_API_KEY (for gemini),
#      OBJECTION_GEMINI_MODEL (default: the Gemini CLI's own),
#      GITHUB_EVENT_PATH, GITHUB_REPOSITORY,
#      GITHUB_SERVER_URL, GITHUB_TOKEN (to fetch), GITHUB_STEP_SUMMARY,
#      OBJECTION_FAIL_ON (blocker, high or none; default blocker),
#      OBJECTION_MODEL / OBJECTION_EFFORT (default sonnet, medium),
#      OBJECTION_DEFENSE (true: a defender answers each BLOCKER, HIGH and
#      MEDIUM, as advice shown with them; OBJECTION_DEFENDER_MODEL,
#      default the accuser's),
#      OBJECTION_COMMENT (true: the summary as one PR comment, kept up
#      to date), OBJECTION_GH_BIN (default gh),
#      OBJECTION_CI_REMOTE (the URL to fetch from; tests use a local one).
# On GitLab (GITLAB_CI set), the merge request comes from the predefined
# variables instead of an event file: CI_MERGE_REQUEST_IID, _TITLE,
# _TARGET_BRANCH_NAME, _SOURCE_BRANCH_SHA (else CI_COMMIT_SHA),
# _SOURCE_PROJECT_ID and _PROJECT_ID, _PROJECT_URL, CI_JOB_TOKEN (to
# fetch), CI_API_V4_URL; the comment is a merge request note posted with
# OBJECTION_GITLAB_TOKEN (a project access token with the api scope: the
# job token cannot write notes).
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
fail_on="${OBJECTION_FAIL_ON:-blocker}"
case "$fail_on" in blocker | high | none) ;; *) echo "fail-on must be blocker, high or none (got $fail_on)." >&2; exit 2 ;; esac
runner="${OBJECTION_RUNNER:-claude}"
case "$runner" in
  claude) [ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "objection review: ANTHROPIC_API_KEY is not set (the anthropic-api-key input)." >&2; exit 1; } ;;
  gemini) [ -n "${GEMINI_API_KEY:-}" ] || { echo "objection review: GEMINI_API_KEY is not set (the gemini-api-key input)." >&2; exit 1; } ;;
  *) echo "objection review: runner must be claude or gemini (got $runner)." >&2; exit 2 ;;
esac
export OBJECTION_RUNNER="$runner"
gitlab=""
[ -n "${GITLAB_CI:-}" ] && gitlab=yes
if [ -n "$gitlab" ]; then
  [ -n "${CI_MERGE_REQUEST_IID:-}" ] || { echo "objection review: this job only runs in merge request pipelines (rules: if: \$CI_PIPELINE_SOURCE == \"merge_request_event\")." >&2; exit 1; }
  number="$CI_MERGE_REQUEST_IID"
  base="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
  # In a merged-results pipeline CI_COMMIT_SHA is a merge commit, not the
  # merge request's head.
  head="${CI_MERGE_REQUEST_SOURCE_BRANCH_SHA:-${CI_COMMIT_SHA:-}}"
  [ -n "$base" ] && [ -n "$head" ] || { echo "objection review: CI_MERGE_REQUEST_TARGET_BRANCH_NAME or the head SHA is not set." >&2; exit 1; }
  title=$(printf '%s' "${CI_MERGE_REQUEST_TITLE:-not stated}" | tr '\n\r\t' '   ' | tr -s ' ')
  # From a fork unless both projects are named and the same one.
  origin_kind=fork
  [ -n "${CI_MERGE_REQUEST_SOURCE_PROJECT_ID:-}" ] &&
    [ "${CI_MERGE_REQUEST_SOURCE_PROJECT_ID}" = "${CI_MERGE_REQUEST_PROJECT_ID:-}" ] && origin_kind=same
  what="MR !$number"
  pr_ref="refs/merge-requests/$number/head"
else
[ -f "${GITHUB_EVENT_PATH:-}" ] || { echo "objection review: no pull request event (GITHUB_EVENT_PATH)." >&2; exit 1; }

# number, base branch, head SHA and title, one per line.
event=$(node -e '
  const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const p = e.pull_request || {};
  if (!p.number || !p.base || !p.head) process.exit(1);
  // A fork: the head repository is not the base repository. A deleted
  // fork has no head repository, and its diff is still an outsider one.
  const fork = !p.head.repo || !p.base.repo || p.head.repo.full_name !== p.base.repo.full_name;
  console.log([p.number, p.base.ref, p.head.sha, String(p.title || "not stated").replace(/\s+/g, " "), fork ? "fork" : "same"].join("\n"));
' "$GITHUB_EVENT_PATH") || { echo "objection review: the event is not a pull request." >&2; exit 1; }
number=$(printf '%s\n' "$event" | sed -n 1p)
base=$(printf '%s\n' "$event" | sed -n 2p)
head=$(printf '%s\n' "$event" | sed -n 3p)
title=$(printf '%s\n' "$event" | sed -n 4p)
origin_kind=$(printf '%s\n' "$event" | sed -n 5p)
what="PR #$number"
pr_ref="refs/pull/$number/head"
fi

# A fork's PR is reviewed only when the repository asks for it
# (review-forks: true): pull_request_target would hand every stranger's
# push this repository's key. It fails rather than passes, since nothing
# reviewed the code: a maintainer reviews it by hand, or turns it on.
if [ "$origin_kind" = fork ] && [ "${OBJECTION_REVIEW_FORKS:-false}" != true ]; then
  msg="## objection review: failed: not run on a fork's PR

$what comes from a fork. The review runs on forks only with review-forks: true (OBJECTION_REVIEW_FORKS=true on GitLab), since every push would spend this repository's key. Review the change by hand, or turn it on."
  printf '%s\n' "$msg"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$msg" >>"$GITHUB_STEP_SUMMARY"
  exit 1
fi

auth=()
if [ -n "$gitlab" ]; then
  # The merge request's refs live in the target project.
  remote="${OBJECTION_CI_REMOTE:-${CI_MERGE_REQUEST_PROJECT_URL:-${CI_SERVER_URL:?}/${CI_PROJECT_PATH:?}}.git}"
  if [ -n "${CI_JOB_TOKEN:-}" ] && [ -z "${OBJECTION_CI_REMOTE:-}" ]; then
    auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'gitlab-ci-token:%s' "$CI_JOB_TOKEN" | base64 | tr -d '\n')")
  fi
else
  remote="${OBJECTION_CI_REMOTE:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:?}.git}"
  if [ -n "${GITHUB_TOKEN:-}" ] && [ -z "${OBJECTION_CI_REMOTE:-}" ]; then
    auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')")
  fi
fi

work=$(mktemp -d)
# Fails closed: bash 3.2 exits 0 from a `set -u` error when an EXIT trap
# is set, so only the last line of this script may exit with its own code.
trap 'st=$?; rm -rf "$work"; [ "${finished:-}" = yes ] && exit "$st"; exit 1' EXIT
cd "$work"
git init -q repo && cd repo
git remote add origin "$remote"
# A fork's head lives in the base repository as refs/pull/<n>/head
# (refs/merge-requests/<iid>/head on GitLab).
git ${auth[@]+"${auth[@]}"} fetch -q --no-tags origin \
  "+refs/heads/$base:refs/remotes/origin/$base" "+$pr_ref:refs/objection/pr" ||
  { echo "objection review: could not fetch $base and $pr_ref from $remote." >&2; exit 1; }
got=$(git rev-parse refs/objection/pr)
[ "$got" = "$head" ] || { echo "objection review: $pr_ref is at ${got:0:7}, the event says ${head:0:7} (pushed again?); the next run reviews it." >&2; exit 1; }
# Detached HEAD on the head commit, with no files written to disk.
git update-ref --no-deref HEAD "$head"

export OBJECTION_MODEL="${OBJECTION_MODEL:-sonnet}" OBJECTION_EFFORT="${OBJECTION_EFFORT:-medium}"
# With OBJECTION_COMMENT=true, the summary also goes to the PR as one
# comment, edited in place on every push instead of piling up. It needs
# pull-requests: write. A comment that cannot be posted is a warning, not
# a failed check: the verdict is the check's, the comment only shows it.
comment() {
  [ "${OBJECTION_COMMENT:-false}" = true ] || return 0
  [ -z "$gitlab" ] || { gitlab_note "$1"; return 0; }
  local gh_bin="${OBJECTION_GH_BIN:-gh}" marker="<!-- objection-review -->" repo="${GITHUB_REPOSITORY:-}" ids id
  # Only this job's own comments are edited: a token with write access can
  # edit anyone's, and a marker is easy to copy. OBJECTION_COMMENT_AUTHOR
  # names the account when the token is not GitHub's (a PAT, an app).
  local author="${OBJECTION_COMMENT_AUTHOR:-github-actions[bot]}"
  printf '%s' "$author" | grep -qE '^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$' || { echo "::warning::objection review: comment author $author is not a GitHub login" >&2; return 0; }
  [ -n "$repo" ] && [ -n "${number:-}" ] || { echo "::warning::objection review: no repository or PR number, so no PR comment" >&2; return 0; }
  printf '%s\n%s\n\n<sub>objection %s, in CI. Updated on every push.</sub>\n' "$marker" "$1" "$(cat "$here/VERSION" 2>/dev/null || echo "")" |
    node -e 'let s = ""; process.stdin.setEncoding("utf8").on("data", (d) => (s += d)).on("end", () => {
      // An @name in model output would ping that user: a zero-width space
      // after the @ keeps the text and drops the ping.
      s = s.replace(/@(?=[A-Za-z0-9_-])/g, "@\u200b");
      // GitHub takes 65536 characters; the cut says so.
      if (s.length > 60000) s = s.slice(0, 60000) + "\n\n(cut: the full findings are in the job summary)";
      process.stdout.write(JSON.stringify({ body: s }));
    });' >"$work/comment.json" || { echo "::warning::objection review: the PR comment could not be written" >&2; return 0; }
  # A listing that fails posts nothing: a blind POST would stack a second
  # comment. A marked comment this token cannot edit is skipped for the
  # next one, then a new one is posted.
  ids=$(GH_TOKEN="${GITHUB_TOKEN:-}" "$gh_bin" api --paginate "repos/$repo/issues/$number/comments" \
    -q "[.[] | select((.body | startswith(\"$marker\")) and .user.login == \"$author\")] | .[].id" 2>/dev/null) ||
    { echo "::warning::objection review: the PR's comments could not be listed, so no comment was posted or edited" >&2; return 0; }
  for id in $ids; do
    GH_TOKEN="${GITHUB_TOKEN:-}" "$gh_bin" api -X PATCH "repos/$repo/issues/comments/$id" --input "$work/comment.json" >/dev/null 2>&1 && return 0
  done
  GH_TOKEN="${GITHUB_TOKEN:-}" "$gh_bin" api -X POST "repos/$repo/issues/$number/comments" --input "$work/comment.json" >/dev/null 2>&1 ||
    echo "::warning::objection review: the PR comment could not be posted (does the job have pull-requests: write?)" >&2
}
# The GitLab form: one merge request note, found by the marker among the
# notes of the token's own user (GET /user) and edited in place. The job
# token cannot write notes: OBJECTION_GITLAB_TOKEN (api scope) does it.
gitlab_note() {
  local marker="<!-- objection-review -->"
  [ -n "${OBJECTION_GITLAB_TOKEN:-}" ] || { echo "WARNING: objection review: OBJECTION_GITLAB_TOKEN is not set (a project access token with the api scope), so no merge request note" >&2; return 0; }
  printf '%s\n%s\n\n<sub>objection %s, in CI. Updated on every push.</sub>\n' "$marker" "$1" "$(cat "$here/VERSION" 2>/dev/null || echo "")" |
    MARKER="$marker" node -e '
let s = "";
process.stdin.setEncoding("utf8").on("data", (d) => (s += d)).on("end", async () => {
  // An @name in model output would ping that user: a zero-width space
  // after the @ keeps the text and drops the ping.
  s = s.replace(/@(?=[A-Za-z0-9_.-])/g, "@\u200b");
  if (s.length > 60000) s = s.slice(0, 60000) + "\n\n(cut: the full findings are in the job log)";
  const api = process.env.CI_API_V4_URL;
  const project = encodeURIComponent(process.env.CI_MERGE_REQUEST_PROJECT_ID || process.env.CI_PROJECT_ID || "");
  const notes = `${api}/projects/${project}/merge_requests/${encodeURIComponent(process.env.CI_MERGE_REQUEST_IID)}/notes`;
  const headers = { "PRIVATE-TOKEN": process.env.OBJECTION_GITLAB_TOKEN, "content-type": "application/json" };
  const warn = (m) => { console.error(`WARNING: objection review: ${m}`); process.exit(0); };
  const call = async (method, url, body) => {
    const r = await fetch(url, { method, headers, body: body && JSON.stringify(body), signal: AbortSignal.timeout(30000) });
    return { ok: r.ok, status: r.status, json: r.ok && method === "GET" ? await r.json() : null };
  };
  try {
    if (!api || !project) warn("CI_API_V4_URL or the project is not set, so no merge request note");
    const me = await call("GET", `${api}/user`);
    if (!me.ok || !me.json || !me.json.username) warn(`the token owner could not be read (HTTP ${me.status}), so no note was posted or edited`);
    // Only this token user'"'"'s own notes are edited: a marker is easy to copy.
    const mine = [];
    for (let page = 1; page <= 50; page++) {
      const r = await call("GET", `${notes}?per_page=100&page=${page}`);
      if (!r.ok || !Array.isArray(r.json)) warn(`the merge request notes could not be listed (HTTP ${r.status}), so no note was posted or edited`);
      for (const n of r.json) if (!n.system && n.author && n.author.username === me.json.username && String(n.body || "").startsWith(process.env.MARKER)) mine.push(n.id);
      if (r.json.length < 100) break;
    }
    for (const id of mine) if ((await call("PUT", `${notes}/${id}`, { body: s })).ok) return;
    const r = await call("POST", notes, { body: s });
    if (!r.ok) warn(`the merge request note could not be posted (HTTP ${r.status}; does the token have the api scope and Reporter access?)`);
  } catch (e) { warn(`the merge request note failed (${e.message})`); }
});' || echo "WARNING: objection review: the merge request note failed" >&2
}
summarise() {
  printf '%s\n' "$1"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"
}
accusation="$work/accusation.md"
rc=0
if ! brief=$(OBJECTION_BRIEF_STRICT=1 bash "$here/brief.sh" "origin/$base" "$title" "not stated" "origin/$base" 2>"$work/brief.err"); then
  cat "$work/brief.err" >&2
  # Every changed file is noise the config excludes: nothing to accuse.
  if grep -q '^nothing to review' "$work/brief.err"; then
    summarise "## objection review: passed

$what @ ${head:0:7}: nothing to review ($(head -n 1 "$work/brief.err"))."
    finished=yes
    exit 0
  fi
  summarise "## objection review: failed: the brief could not be built

$(head -n 5 "$work/brief.err")"
  finished=yes
  exit 1
fi
# The reviewer gets only its own runner's key: not the other runner's
# key, and no credential of the job. Named by pattern, since each CI adds
# its own: GitHub's token and OIDC request token, GitLab's job token,
# job JWTs, registry and deploy passwords, and CI_REPOSITORY_URL, which
# carries the job token inside the URL.
other_key=GEMINI_API_KEY
[ "$runner" = gemini ] && other_key=ANTHROPIC_API_KEY
strip=(-u "$other_key")
while IFS= read -r v; do
  case "$v" in
    *TOKEN* | *PASSWORD* | *JWT* | *SECRET* | CI_REPOSITORY_URL) strip+=(-u "$v") ;;
  esac
done < <(compgen -e)
env "${strip[@]}" bash "$here/review.sh" accuser "$brief" >"$accusation" || rc=$?

# Same row rule as debate.sh: a table row whose first cell starts with the word.
count() {
  awk -F'|' -v want="$1" '
    /^[[:space:]]*\|/ {
      s = $2; sub(/^[[:space:]*_]+/, "", s)
      if (!match(s, /^[A-Za-z]+/)) next
      w = toupper(substr(s, 1, RLENGTH)); rest = substr(s, RLENGTH + 1)
      if (w == want && rest ~ /^([^A-Za-z-]|$)/) n++
    }
    END { print n + 0 }' "$accusation"
}
blocker=$(count BLOCKER)
high=$(count HIGH)
medium=$(count MEDIUM)
low=$(count LOW)

# An answer with no findings table and no "NO FINDINGS" line (empty, a
# refusal, prose) is not a review: counting its rows gave "passed". A
# header row, a full finding row without one (severity, kind, file,
# defect, evidence, proof), or the NO FINDINGS line counts.
# It fails even under fail-on: none, like an accuser that did not run.
answered=yes
grep -qiE '^[[:space:]]*\|[[:space:]]*(#[[:space:]]*\|[[:space:]]*)?severity[[:space:]]*\|' "$accusation" ||
  grep -qE '^[[:space:]]*\|([^|]*\|)?[[:space:]]*(BLOCKER|HIGH|MEDIUM|LOW)[[:space:]]*\|([^|]*\|){4,}' "$accusation" ||
  grep -qiE '^[[:space:]]*NO FINDINGS\.?[[:space:]]*$' "$accusation" || answered=""

# The defense (OBJECTION_DEFENSE=true), as advice: every BLOCKER, HIGH
# and MEDIUM goes to the defender in one call, and its answer is shown
# under the findings. It never changes the check. Measured on 70 findings
# a Gemini accuser made on the eval (sonnet defending): of 5 false alarms
# it refuted none, proposed a lower severity for 2 and could not verify 2;
# of 65 real ones it refuted one, the main row of caller-units, with a
# refutation that cited a real line and said itself "not confirmed", and
# proposed LOW for the other row of that bug. Honored, it would have
# passed a real bug through the barrier, which costs more than a false
# alarm. Without a judge, its answer is for the person reading.
defense=""
defense_line="No defense (defense: true adds one, as advice)."
if [ "${OBJECTION_DEFENSE:-false}" = true ] && [ "$rc" = 0 ] && [ -n "$answered" ]; then
  # Numbered like debate.sh: "| n | SEVERITY | ...", in the accusation too.
  awk -F'|' '
    function finding(s, w) {
      sub(/^[[:space:]*_]+/, "", s)
      if (!match(s, /^[A-Za-z]+/)) return 0
      w = toupper(substr(s, 1, RLENGTH))
      return w ~ /^(BLOCKER|HIGH|MEDIUM|LOW)$/ && substr(s, RLENGTH + 1) ~ /^([^A-Za-z-]|$)/
    }
    /^[[:space:]]*\|/ {
      h = $2; gsub(/[[:space:]*_]/, "", h)
      if (tolower(h) == "severity") { sub(/^[[:space:]]*\|/, "| # |"); print; head = 1; next }
      if (head && $0 ~ /^[[:space:]]*\|[[:space:]:-]*\|/) { sub(/^[[:space:]]*\|/, "|---|"); print; head = 0; next }
      head = 0
      if (finding($2)) { sub(/^[[:space:]]*\|/, "| " ++n " |"); print; next }
    }
    { head = 0; print }' "$accusation" >"$work/numbered" && cp "$work/numbered" "$accusation"
  {
    printf '| # | severity | kind | file:line | defect | evidence | proof path |\n|---|---|---|---|---|---|---|\n'
    awk -F'|' '
      /^[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
        s = $3; sub(/^[[:space:]*_]+/, "", s)
        if (match(s, /^[A-Za-z]+/) && toupper(substr(s, 1, RLENGTH)) ~ /^(BLOCKER|HIGH|MEDIUM)$/) print
      }' "$accusation"
  } >"$work/findings"
  total=$(($(wc -l <"$work/findings" | tr -d ' ') - 2))
  if [ "$total" -gt 0 ]; then
    defense="$work/defense.md"
    drc=0
    OBJECTION_MODEL="${OBJECTION_DEFENDER_MODEL:-$OBJECTION_MODEL}" \
      env "${strip[@]}" bash "$here/review.sh" defender "$brief" "$work/findings" >"$defense" || drc=$?
    if [ "$drc" != 0 ]; then
      defense_line="Defense: the defender did not run (exit $drc)."
      : >"$defense"
    else
      tally=$(awk -F'|' '
        /^[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
          v = toupper($3)
          if (v ~ /REFUTED/) r++
          else if (v ~ /CANNOT/) c++
          else if (v ~ /UPHELD/ && v ~ /PROPOSE/) l++
          else if (v ~ /UPHELD/) u++
        }
        END { printf "%d refuted, %d upheld with a lower severity proposed, %d upheld, %d cannot verify", r, l, u, c }' "$defense")
      defense_line="Defense, as advice (it does not change the check): $total finding(s) answered: $tally. It refuted one real bug on the eval, so read each refutation before you trust it."
    fi
  else
    defense_line="Defense: no BLOCKER, HIGH or MEDIUM to defend."
  fi
fi
verdict="passed"
status=0
if [ "$rc" != 0 ]; then
  verdict="failed: the accuser did not run (exit $rc)"
  status=1
elif [ -z "$answered" ]; then
  verdict="failed: the accuser's answer has no findings table"
  status=1
elif [ "$fail_on" != none ] && grep -q '^TRUNCATED: the diff has' "$brief"; then
  verdict="failed: the diff is too large for one review, so part of it was not read (split the PR, or fail-on: none)"
  status=1
elif [ "$fail_on" = blocker ] && [ "$blocker" -gt 0 ]; then
  verdict="failed: $blocker BLOCKER"
  status=1
elif [ "$fail_on" = high ] && [ $((blocker + high)) -gt 0 ]; then
  verdict="failed: $blocker BLOCKER, $high HIGH"
  status=1
fi

summary=$(
  printf '## objection review: %s\n\n' "$verdict"
  accuser="$OBJECTION_MODEL, effort $OBJECTION_EFFORT"
  [ "$runner" = gemini ] && accuser="gemini ${OBJECTION_GEMINI_MODEL:-(the CLI default model)}"
  printf '%s @ %s against %s. Accuser: %s, isolated. Fails on: %s.\n\n' \
    "$what" "${head:0:7}" "$base" "$accuser" "$fail_on"
  printf 'Findings: %s BLOCKER, %s HIGH, %s MEDIUM, %s LOW. No judge: a finding here is a claim to check, not a verdict.\n\n%s\n\n' \
    "$blocker" "$high" "$medium" "$low" "$defense_line"
  # Model text, shown to people: an unclosed "<!--" would hide the rest of
  # the comment, and an image would make GitHub fetch a URL of its choice.
  sed 's/<!--/\&lt;!--/g; s/!\[/!\\[/g' "$accusation"
  if [ -n "$defense" ] && [ -s "$defense" ]; then
    printf '\n### Defense\n\n'
    sed 's/<!--/\&lt;!--/g; s/!\[/!\\[/g' "$defense"
  fi
)
summarise "$summary"
# Never the verdict: whatever fails in comment() is a warning.
comment "$summary" || echo "::warning::objection review: the PR comment failed" >&2
finished=yes
exit "$status"
