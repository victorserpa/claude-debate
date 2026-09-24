#!/bin/bash
# The accuser, run by CI on a pull request, outside the agent's reach.
#
#   ci-review.sh     (inside a GitHub Actions job; see action.yml)
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
# Env: ANTHROPIC_API_KEY (required), GITHUB_EVENT_PATH, GITHUB_REPOSITORY,
#      GITHUB_SERVER_URL, GITHUB_TOKEN (to fetch), GITHUB_STEP_SUMMARY,
#      OBJECTION_FAIL_ON (blocker, high or none; default blocker),
#      OBJECTION_MODEL / OBJECTION_EFFORT (default sonnet, medium),
#      OBJECTION_CI_REMOTE (the URL to fetch from; tests use a local one).
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
fail_on="${OBJECTION_FAIL_ON:-blocker}"
case "$fail_on" in blocker | high | none) ;; *) echo "fail-on must be blocker, high or none (got $fail_on)." >&2; exit 2 ;; esac
[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "objection review: ANTHROPIC_API_KEY is not set (the anthropic-api-key input)." >&2; exit 1; }
[ -f "${GITHUB_EVENT_PATH:-}" ] || { echo "objection review: no pull request event (GITHUB_EVENT_PATH)." >&2; exit 1; }

# number, base branch, head SHA and title, one per line.
event=$(node -e '
  const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const p = e.pull_request || {};
  if (!p.number || !p.base || !p.head) process.exit(1);
  console.log([p.number, p.base.ref, p.head.sha, String(p.title || "not stated").replace(/\s+/g, " ")].join("\n"));
' "$GITHUB_EVENT_PATH") || { echo "objection review: the event is not a pull request." >&2; exit 1; }
number=$(printf '%s\n' "$event" | sed -n 1p)
base=$(printf '%s\n' "$event" | sed -n 2p)
head=$(printf '%s\n' "$event" | sed -n 3p)
title=$(printf '%s\n' "$event" | sed -n 4p)

remote="${OBJECTION_CI_REMOTE:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:?}.git}"
auth=()
if [ -n "${GITHUB_TOKEN:-}" ] && [ -z "${OBJECTION_CI_REMOTE:-}" ]; then
  auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')")
fi

work=$(mktemp -d)
# Fails closed: bash 3.2 exits 0 from a `set -u` error when an EXIT trap
# is set, so only the last line of this script may exit with its own code.
trap 'st=$?; rm -rf "$work"; [ "${finished:-}" = yes ] && exit "$st"; exit 1' EXIT
cd "$work"
git init -q repo && cd repo
git remote add origin "$remote"
# A fork's head lives in the base repository as refs/pull/<n>/head.
git ${auth[@]+"${auth[@]}"} fetch -q --no-tags origin \
  "+refs/heads/$base:refs/remotes/origin/$base" "+refs/pull/$number/head:refs/objection/pr" ||
  { echo "objection review: could not fetch $base and pull/$number from $remote." >&2; exit 1; }
got=$(git rev-parse refs/objection/pr)
[ "$got" = "$head" ] || { echo "objection review: pull/$number is at ${got:0:7}, the event says ${head:0:7} (pushed again?); the next run reviews it." >&2; exit 1; }
# Detached HEAD on the head commit, with no files written to disk.
git update-ref --no-deref HEAD "$head"

export OBJECTION_MODEL="${OBJECTION_MODEL:-sonnet}" OBJECTION_EFFORT="${OBJECTION_EFFORT:-medium}"
brief=$(bash "$here/brief.sh" "origin/$base" "$title" "not stated" "origin/$base")
accusation="$work/accusation.md"
rc=0
bash "$here/review.sh" accuser "$brief" >"$accusation" || rc=$?

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

verdict="passed"
status=0
if [ "$rc" != 0 ]; then
  verdict="failed: the accuser did not run (exit $rc)"
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
  printf 'PR #%s @ %s against %s. Accuser: %s, effort %s, isolated. Fails on: %s.\n\n' \
    "$number" "${head:0:7}" "$base" "$OBJECTION_MODEL" "$OBJECTION_EFFORT" "$fail_on"
  printf 'Findings: %s BLOCKER, %s HIGH, %s MEDIUM, %s LOW. One reviewer, no defense and no judge: a finding here is a claim to check, not a verdict.\n\n' \
    "$blocker" "$high" "$medium" "$low"
  cat "$accusation"
)
printf '%s\n' "$summary"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$summary" >>"$GITHUB_STEP_SUMMARY"
finished=yes
exit "$status"
