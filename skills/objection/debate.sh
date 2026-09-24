#!/bin/bash
# Runs one round of the debate up to the judge, so the main session does
# not spend its own (expensive) context driving it.
#
#   debate.sh <base> [goal] [scope]                    round 1
#   debate.sh --since <commit> <base> [goal] [scope]   later rounds: the fix only
#
# Steps: the brief (brief.sh), the accuser (review.sh, isolated), the
# defender only for the findings the budget sends it, and a draft record
# with the Judge and Open sections left to the main session. Prints a
# short summary and the draft's path; the session then reads that one
# file instead of every step.
#
# The budget is the base branch's (brief.sh reads it from there). Under
# `standard` and `thorough` it runs the generic accuser only: the summary
# says to run each matching `reviewers` entry as well (SKILL.md step 1).
#
# Exit codes are review.sh's: 3 means no claude CLI (run the roles as
# subagents, SKILL.md step 1), 2 a missing tool, 1 a failed run. When
# the defender fails, the draft is still written and summarised, and the
# exit code is the defender's: rerun only the defense, not the round.
set -eu

since=""
if [ "${1:-}" = --since ]; then
  since="${2:?--since needs the commit of the previous round}"
  shift 2
fi
base="${1:?usage: debate.sh [--since <commit>] <base> [goal] [scope]}"
goal="${2:-not stated}"
scope="${3:-not stated}"
here="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"

diff_base="origin/$base"
if [ -n "$since" ]; then
  diff_base="$since"
  goal="Round after a fix: hunt regressions from the fix first. Goal of the PR: $goal"
fi
brief=$(bash "$here/brief.sh" "$diff_base" "$goal" "$scope" "origin/$base")

budget=$(sed -n 's/^<!-- objection-budget: \([a-z]*\) -->$/\1/p' "$brief" | head -n 1)
[ -n "$budget" ] || budget=lean
sha=$(git rev-parse HEAD)
dir="$(git rev-parse --path-format=absolute --git-common-dir)/objection"
accusation="$dir/accusation-$sha.md"
findings="$dir/findings-$sha.md"
defense="$dir/defense-$sha.md"
record="$dir/record-$sha.md"
rm -f "$findings" "$defense"

# An exit 3 (no claude CLI) must reach the caller as 3, so no `|| exit 1`.
bash "$here/review.sh" accuser "$brief" >"$accusation"

# Finding rows: a table row whose first cell starts with a severity word.
# Bold, underscores and a note after it ("HIGH (regression)") are
# tolerated; a longer word ("Low-level", "Lowest") and the header are not.
rows() {
  awk -F'|' -v want="$1" '
    /^[[:space:]]*\|/ {
      s = $2; sub(/^[[:space:]*_]+/, "", s)
      if (!match(s, /^[A-Za-z]+/)) next
      w = toupper(substr(s, 1, RLENGTH)); rest = substr(s, RLENGTH + 1)
      if (w ~ "^(" want ")$" && rest ~ /^([^A-Za-z-]|$)/) print
    }' "$accusation"
}
count() { rows "$1" | wc -l | tr -d ' '; }
case "$budget" in
  thorough) sent="BLOCKER|HIGH|MEDIUM|LOW" ;;
  standard) sent="BLOCKER|HIGH|MEDIUM" ;;
  *) sent="BLOCKER|HIGH" ;;
esac

defended="not run: no finding the $budget budget sends to the defense"
rc=0
if [ -n "$(rows "$sent")" ]; then
  {
    printf '| # | severity | kind | file:line | defect | evidence | proof path |\n'
    printf '|---|---|---|---|---|---|---|\n'
    rows "$sent" | awk '{ sub(/^[[:space:]]*\|/, ""); printf "| %d |%s\n", NR, $0 }'
  } >"$findings"
  # A failed defense must not lose the accusation already paid for: the
  # draft is written anyway and the exit code reports the failure.
  if bash "$here/review.sh" defender "$brief" "$findings" >"$defense"; then
    n=$(rows "$sent" | wc -l | tr -d ' ')
    defended="answered $n finding(s) ($sent)"
  else
    rc=$?
    defended="defender FAILED (exit $rc): rerun review.sh defender, or treat its findings as undefended"
  fi
fi

{
  printf '# Debate: %s @ %s\n\n' "$(git rev-parse --abbrev-ref HEAD)" "${sha:0:7}"
  printf 'Budget: %s. Diff: %s...HEAD. Reviewers ran as isolated processes (review.sh, model %s).\n\n' \
    "$budget" "$diff_base" "${OBJECTION_MODEL:-opus}"
  printf '## Accusation\n\n'
  cat "$accusation"
  printf '\n## Defense\n\n'
  if [ -s "$findings" ]; then
    printf 'Findings as numbered for the defender:\n\n'
    cat "$findings"
    printf '\n'
    if [ "$rc" != 0 ]; then printf '%s.\n\n' "$defended"; fi
    # Kept even on failure: an answer flagged as an error was still paid for.
    cat "$defense"
  else
    printf '%s.\n' "$defended"
  fi
  printf '\n## Judge\n\n'
  printf 'TODO(judge): rule on every finding with the rules of SKILL.md step 3.\n'
  printf '\n## Open\n\n'
  printf 'TODO(judge): what stays open, then OPEN: BLOCKER=<n> HIGH=<n>, then the VERDICT line.\n'
} >"$record"

echo "objection: $(git rev-parse --abbrev-ref HEAD) @ ${sha:0:7}, budget $budget, diff $diff_base...HEAD"
echo "accuser: $(count BLOCKER) BLOCKER, $(count HIGH) HIGH, $(count MEDIUM) MEDIUM, $(count LOW) LOW"
echo "defender: $defended"
echo "draft record: $record"
if [ "$budget" != lean ]; then
  echo "note: $budget also runs each matching reviewers entry as an accuser (SKILL.md step 1); this script ran the generic one."
fi
echo "next: judge each finding (SKILL.md step 3), replace the TODO(judge) lines, then stamp.sh."
exit "$rc"
