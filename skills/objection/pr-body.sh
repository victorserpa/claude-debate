#!/bin/bash
# Puts the stamped record for HEAD into the PR body, so nobody pastes it.
#
#   pr-body.sh            writes the body to <git-common-dir>/objection/body-<sha>.md
#                         and prints its path: gh pr create --body-file <path>
#   pr-body.sh --update   also replaces the body of the branch's open PR
#                         (gh pr edit), after a new debate for a new push
#
# The body is the text the PR already has above its old record (or,
# without a PR, the given summary: OBJECTION_SUMMARY or nothing), then the
# record stored by stamp.sh for HEAD. Only the part from the first
# "<!-- objection: sha=" line on is replaced, so the author's description
# stays. Refuses when HEAD has no stored record: stamp.sh comes first.
#
# Env: OBJECTION_GH_BIN (default gh), OBJECTION_SUMMARY.
set -eu

update=""
[ "${1:-}" = --update ] && update=yes
gh_bin="${OBJECTION_GH_BIN:-gh}"

sha=$(git rev-parse HEAD)
dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)/objection"
record="$dir/$sha.md"
[ -f "$record" ] || { echo "no stamped record for ${sha:0:7}: debate, judge and run stamp.sh first." >&2; exit 1; }

current=""
has_pr=""
if command -v "$gh_bin" >/dev/null 2>&1 && current=$("$gh_bin" pr view --json body -q .body 2>/dev/null); then
  has_pr=yes
else
  current="${OBJECTION_SUMMARY:-}"
fi
[ -n "$update" ] && [ -z "$has_pr" ] && { echo "no open PR for this branch: create it with gh pr create --body-file <path>." >&2; exit 1; }

body="$dir/body-$sha.md"
{
  # Everything above the old record, trailing blank lines dropped.
  printf '%s\n' "$current" | awk '/^<!-- objection: sha=/{exit} {print}' |
    awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'
  [ -z "$(printf '%s' "$current" | awk '/^<!-- objection: sha=/{exit} NF{print; exit}')" ] || printf '\n'
  cat "$record"
} >"$body"

if [ -n "$update" ]; then
  "$gh_bin" pr edit --body-file "$body" >/dev/null
  echo "PR body updated with the record for ${sha:0:7}."
fi
echo "$body"
