#!/bin/bash
# Runs one round of the debate up to the judge, so the main session does
# not spend its own (expensive) context driving it.
#
#   debate.sh [base] [goal] [scope]                    round 1
#   debate.sh --since <commit> [base] [goal] [scope]   later rounds: the fix only
#
# base: the branch the PR targets. Omitted (or not a branch on origin), it
# is the config's defaultBase, and the first argument is the goal.
#
# Steps: the brief (brief.sh), the accuser (review.sh, isolated), the
# defender only for the findings the budget sends it, and a draft record
# with the Judge and Open sections left to the main session. Prints a
# short summary and the draft's path; the session then reads that one
# file instead of every step.
#
# The budget is the base branch's (brief.sh reads it from there). Under
# `standard` and `thorough`, each matching `reviewers` entry also runs as
# its own isolated accuser, with its focus.
#
# When the skill under review is in the repository itself (objection's own
# repository), the roles come from the base branch: a branch must not
# review itself with prompts it rewrote.
#
# Old artifacts in <git-common-dir>/objection are pruned to the newest
# OBJECTION_KEEP (default 10) of each kind; stamped records are kept.
#
# Exit codes are review.sh's: 3 means no claude CLI (run the roles as
# subagents, SKILL.md step 1), 2 a missing tool, 1 a failed run. When
# the defender fails, the draft is still written and summarised, and the
# exit code is the defender's: rerun only the defense, not the round.
set -eu

# Git Bash (Windows) rewrites an argument like "origin/main:file" as a
# path list ("origin\\main;file"); these calls must reach git untouched.
gitref() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' git "$@"; }

since=""
if [ "${1:-}" = --since ]; then
  since="${2:?--since needs the commit of the previous round}"
  shift 2
fi
# Physical paths: git reports the toplevel resolved (/private/var on macOS).
here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git rev-parse --show-toplevel)"
cd "$top"

base=""
if [ $# -gt 0 ] && [ -n "$1" ] && git rev-parse --verify -q "refs/remotes/origin/$1" >/dev/null; then
  base="$1"
  shift
fi
if [ -z "$base" ]; then
  for c in .objection.json .claude/objection.json; do
    [ -f "$c" ] || continue
    base=$(node -e '
      try {
        const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        console.log(c.defaultBase || (c.bases || [])[0] || "");
      } catch { console.log(""); }' "$c")
    break
  done
fi
if [ -z "$base" ]; then
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
  base="${base#origin/}"
fi
goal="${1:-not stated}"
scope="${2:-not stated}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
case "$here/" in
  "$top/"*)
    rel="${here#"$top/"}"
    mkdir -p "$tmp/roles"
    for r in accuser defender; do
      # New at the base (the PR that adds the skill): the working copy.
      gitref show "origin/$base:$rel/roles/$r.md" >"$tmp/roles/$r.md" 2>/dev/null ||
        cp "$here/roles/$r.md" "$tmp/roles/$r.md"
    done
    export OBJECTION_ROLES_DIR="$tmp/roles"
    ;;
esac

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
rc=0

# Standard and thorough: one more accuser per matching reviewers entry
# (brief.sh lists them as "agent<TAB>focus"). A failed one is noted, and
# the answers already paid for are kept.
accusers="generic"
if [ "$budget" != lean ]; then
  sed -n 's/^<!-- objection-reviewer: \(.*\) -->$/\1/p' "$brief" >"$tmp/reviewers"
  if [ -s "$tmp/reviewers" ]; then
    { printf '### generic\n\n'; cat "$accusation"; } >"$tmp/all"
    while IFS="$(printf '\t')" read -r agent focus; do
      [ -n "$agent" ] || continue
      accusers="$accusers + $agent"
      printf '\n### %s (focus: %s)\n\n' "$agent" "$focus" >>"$tmp/all"
      if OBJECTION_FOCUS="$focus" bash "$here/review.sh" accuser "$brief" >"$tmp/one" </dev/null; then
        cat "$tmp/one" >>"$tmp/all"
      else
        rc=$?
        printf 'accuser %s FAILED (exit %s).\n' "$agent" "$rc" >>"$tmp/all"
        cat "$tmp/one" >>"$tmp/all"
      fi
    done <"$tmp/reviewers"
    cp "$tmp/all" "$accusation"
  fi
fi

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

# Prune: the newest OBJECTION_KEEP of each kind stay (this run's among
# them). Stamped records (<sha>.md) match none of these names.
keep="${OBJECTION_KEEP:-10}"
case "$keep" in '' | *[!0-9]* | 0) keep=10 ;; esac
for kind in brief accusation findings defense record; do
  ls -t "$dir/$kind"-*.md 2>/dev/null | tail -n +"$((keep + 1))" | while IFS= read -r old; do
    rm -f "$old"
  done
done

echo "objection: $(git rev-parse --abbrev-ref HEAD) @ ${sha:0:7}, budget $budget, diff $diff_base...HEAD"
echo "accusers: $accusers"
echo "findings: $(count BLOCKER) BLOCKER, $(count HIGH) HIGH, $(count MEDIUM) MEDIUM, $(count LOW) LOW"
echo "defender: $defended"
echo "draft record: $record"
echo "next: judge each finding (SKILL.md step 3), replace the TODO(judge) lines, then stamp.sh."
exit "$rc"
