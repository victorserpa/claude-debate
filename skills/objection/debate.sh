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
defaulted=""
if [ $# -gt 0 ] && [ -n "$1" ] && git rev-parse --verify -q "refs/remotes/origin/$1" >/dev/null; then
  base="$1"
  shift
elif [ $# -gt 0 ]; then
  defaulted="$1"
fi
if [ -z "$base" ]; then
  for c in .objection.json .claude/objection.json; do
    [ -f "$c" ] || continue
    # A base the config lists but origin lacks is a missing fetch, not a
    # goal: running against defaultBase instead would review the wrong diff.
    if [ $# -gt 0 ] && node -e '
      try {
        const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        process.exit([...(c.bases || []), c.defaultBase].includes(process.argv[2]) ? 0 : 1);
      } catch { process.exit(1); }' "$c" "$1"; then
      echo "origin/$1 is not here: run git fetch origin $1, then debate again." >&2
      exit 1
    fi
    break
  done
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
base_note=""
if [ -n "$defaulted" ]; then
  base_note="base: $base (the default: \"$defaulted\" is not a branch on origin, so it was read as the goal)"
  # Said before anything is spent, and again in the summary.
  echo "objection: $base_note" >&2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# One form for both paths before comparing: on Windows git reports C:/...
# while Git Bash says /tmp/... or /c/... (pwd -W gives the C:/ form there).
canon() { (cd "$1" && { pwd -W 2>/dev/null || pwd -P; }); }
here_c=$(canon "$here")
top_c=$(canon "$top")
case "$here_c/" in
  "$top_c/"*)
    rel="${here_c#"$top_c/"}"
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
# Model and effort: the brief's tier (from the base config) unless the
# caller set OBJECTION_MODEL / OBJECTION_EFFORT.
tier=$(sed -n 's/^<!-- objection-model: \(.*\) -->$/\1/p' "$brief" | head -n 1)
set -- $tier
tier_model="${1:-sonnet}"
tier_effort="${2:-medium}"
tier_reason="${3:-default}"
brief_reason="$tier_reason"
if [ -n "${OBJECTION_MODEL:-}" ]; then tier_model="$OBJECTION_MODEL"; tier_reason="OBJECTION_MODEL"; fi
defender_effort="$tier_effort"
# A later round reviews only the fix: the accuser runs at the config's
# laterEffort (default low); the defender keeps the round's effort.
if [ -n "$since" ]; then
  later=$(sed -n 's/^<!-- objection-later-effort: \([A-Za-z]*\) -->$/\1/p' "$brief" | head -n 1)
  tier_effort="${later:-low}"
  tier_reason="$tier_reason, later round"
fi
if [ -n "${OBJECTION_EFFORT:-}" ]; then
  tier_effort="$OBJECTION_EFFORT"
  defender_effort="$OBJECTION_EFFORT"
  tier_reason="${tier_reason%, later round}, OBJECTION_EFFORT"
fi
# The defender's model: the config's models.defender (default sonnet),
# whatever the accuser runs on; OBJECTION_DEFENDER_MODEL overrides it.
defender_model=$(sed -n 's/^<!-- objection-defender: \([A-Za-z0-9._-]*\) -->$/\1/p' "$brief" | head -n 1)
defender_model="${OBJECTION_DEFENDER_MODEL:-${defender_model:-sonnet}}"
export OBJECTION_MODEL="$tier_model" OBJECTION_EFFORT="$tier_effort"
sha=$(git rev-parse HEAD)
dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)/objection"
accusation="$dir/accusation-$sha.md"
findings="$dir/findings-$sha.md"
defense="$dir/defense-$sha.md"
record="$dir/record-$sha.md"
rm -f "$findings" "$defense"

draft_head() {
  printf '# Debate: %s @ %s\n\n' "$(git rev-parse --abbrev-ref HEAD)" "${sha:0:7}"
}
draft_tail() {
  printf '\n## Judge\n\n'
  printf 'TODO(judge): rule on every finding with the rules of SKILL.md step 3.\n'
  printf '\n## Open\n\n'
  printf 'TODO(judge): what stays open, then OPEN: BLOCKER=<n> HIGH=<n>, then the VERDICT line.\n'
}

# A small lean diff that no invariant or strongPaths names is not worth a
# reviewer: the judge reads it and the verify step still runs. The
# threshold is the base config's smallDiff (default 20; 0 turns it off),
# or OBJECTION_SMALL_DIFF.
lines=$(sed -n 's/^<!-- objection-lines: \([0-9]*\) -->$/\1/p' "$brief" | head -n 1)
small=$(sed -n 's/^<!-- objection-small-diff: \([0-9]*\) -->$/\1/p' "$brief" | head -n 1)
[ -z "${OBJECTION_SMALL_DIFF:-}" ] || small="$OBJECTION_SMALL_DIFF"
case "$small" in '' | *[!0-9]*) small=20 ;; esac
if [ "$budget" = lean ] && [ "$brief_reason" = default ] && [ "$small" -gt 0 ] &&
  [ -n "$lines" ] && [ "$lines" -le "$small" ]; then
  skipped="skipped (small diff: $lines changed lines, at most $small)"
  {
    draft_head
    printf 'Budget: %s. Diff: %s...HEAD.\n\n' "$budget" "$diff_base"
    printf '## Accusation\n\nNo reviewers ran: small diff (%s changed lines, at most %s, and no invariant or strongPaths match). The judge reads the diff and rules on it alone.\n' "$lines" "$small"
    printf '\n## Defense\n\nnot run.\n'
    # Pre-filled for the common case: one TODO line stands between this
    # draft and a stamp, and removing it is the judge saying "I read it".
    printf '\n## Judge\n\n'
    printf 'TODO(judge): read the diff. If nothing is wrong, delete this line and stamp; otherwise write the findings here and in Open, and fix the counts and the verdict.\n'
    printf 'The judge read the %s changed lines and found nothing to rule on.\n' "$lines"
    printf '\n## Open\n\nNothing.\n\nOPEN: BLOCKER=0 HIGH=0\nVERDICT: APPROVED\n'
  } >"$record"
  echo "objection: $(git rev-parse --abbrev-ref HEAD) @ ${sha:0:7}, budget $budget, diff $diff_base...HEAD"
  [ -z "$defaulted" ] || echo "$base_note"
  echo "reviewers: $skipped"
  echo "draft record: $record"
  echo "next: read the diff (git diff $diff_base...HEAD); if nothing is wrong, delete the TODO(judge) line and run stamp.sh."
  exit 0
fi

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
      # An agent that names a Claude model runs on it; any other agent (a
      # different tool) is only a label here: this is review.sh's model.
      model="$OBJECTION_MODEL"
      case "$agent" in opus | sonnet | haiku | claude-*) model="$agent" ;; esac
      printf '\n### %s (focus: %s; run by review.sh%s)\n\n' "$agent" "$focus" "${model:+ on $model}" >>"$tmp/all"
      if OBJECTION_MODEL="$model" OBJECTION_FOCUS="$focus" bash "$here/review.sh" accuser "$brief" >"$tmp/one" </dev/null; then
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
# Every finding is numbered once, here, in a "#" column; the defender and
# the judge use the same numbers, so the draft never repeats the table.
sev() {
  awk -F'|' -v want="$1" -v col="$2" '
    /^[[:space:]]*\|/ {
      s = $col; sub(/^[[:space:]*_]+/, "", s)
      if (!match(s, /^[A-Za-z]+/)) next
      w = toupper(substr(s, 1, RLENGTH)); rest = substr(s, RLENGTH + 1)
      if (w ~ "^(" want ")$" && rest ~ /^([^A-Za-z-]|$)/) print
    }'
}
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
  { head = 0; print }' "$accusation" >"$tmp/numbered"
cp "$tmp/numbered" "$accusation"
rows() { sev "$1" 3 <"$accusation"; }
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
    rows "$sent"
  } >"$findings"
  # A failed defense must not lose the accusation already paid for: the
  # draft is written anyway and the exit code reports the failure.
  if OBJECTION_MODEL="$defender_model" OBJECTION_EFFORT="$defender_effort" \
    bash "$here/review.sh" defender "$brief" "$findings" >"$defense"; then
    n=$(rows "$sent" | wc -l | tr -d ' ')
    defended="answered $n finding(s) ($sent)"
  else
    rc=$?
    defended="defender FAILED (exit $rc): rerun review.sh defender, or treat its findings as undefended"
  fi
fi

{
  draft_head
  printf 'Budget: %s. Diff: %s...HEAD. Reviewers ran as isolated processes (review.sh, model %s).\n\n' \
    "$budget" "$diff_base" "$OBJECTION_MODEL, effort $OBJECTION_EFFORT"
  printf '## Accusation\n\n'
  cat "$accusation"
  printf '\n## Defense\n\n'
  if [ -s "$findings" ]; then
    printf 'Sent to the defender (numbers as in the Accusation): %s.\n\n' \
      "$(awk -F'|' 'NR > 2 { gsub(/ /, "", $2); printf "%s%s", (n++ ? ", " : ""), $2 }' "$findings")"
    if [ "$rc" != 0 ]; then printf '%s.\n\n' "$defended"; fi
    # Kept even on failure: an answer flagged as an error was still paid for.
    cat "$defense"
  else
    printf '%s.\n' "$defended"
  fi
  draft_tail
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
[ -z "$defaulted" ] || echo "$base_note"
echo "model: $tier_model, effort $tier_effort ($tier_reason); defender $defender_model, effort $defender_effort"
echo "accusers: $accusers"
echo "findings: $(count BLOCKER) BLOCKER, $(count HIGH) HIGH, $(count MEDIUM) MEDIUM, $(count LOW) LOW"
echo "defender: $defended"
echo "draft record: $record"
echo "next: judge each finding (SKILL.md step 3), replace the TODO(judge) lines, then stamp.sh."
exit "$rc"
