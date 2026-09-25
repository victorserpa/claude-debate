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
# record stored by stamp.sh for HEAD, then whatever the PR had below the
# old record. Only the old record is replaced: from the first
# "<!-- objection: sha=" line to the last "VERDICT:" line after it, so the
# author's text on both sides stays (a "Closes #12" below the record used
# to be dropped, and the issue then stayed open). Refuses when HEAD has no
# stored record: stamp.sh comes first.
#
# Env: OBJECTION_GH_BIN (default gh), OBJECTION_SUMMARY.
set -eu

update=""
case "${1:-}" in
  "") ;;
  --update) update=yes ;;
  *) echo "usage: pr-body.sh [--update]" >&2; exit 2 ;;
esac
gh_bin="${OBJECTION_GH_BIN:-gh}"

sha=$(git rev-parse HEAD)
dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)/objection"
record="$dir/$sha.md"
[ -f "$record" ] || { echo "no stamped record for ${sha:0:7}: debate, judge and run stamp.sh first." >&2; exit 1; }

current=""
has_pr=""
pr_head=""
if command -v "$gh_bin" >/dev/null 2>&1 && view=$("$gh_bin" pr view --json body,headRefOid -q '.headRefOid + "\n" + .body' 2>/dev/null); then
  has_pr=yes
  pr_head=$(printf '%s\n' "$view" | head -n 1)
  current=$(printf '%s\n' "$view" | tail -n +2)
fi
# An empty body (or no PR yet) takes the summary.
[ -n "$(printf '%s' "$current" | tr -d '[:space:]')" ] || current="${OBJECTION_SUMMARY:-}"
if [ -n "$update" ]; then
  [ -n "$has_pr" ] || { echo "no open PR for this branch: create it with gh pr create --body-file <path>." >&2; exit 1; }
  # The CI check compares the record with the PR's head: push first.
  # Right after a push GitHub can still report the old head for a few
  # seconds; when the pushed branch already has this SHA, wait for it.
  if [ "$pr_head" != "$sha" ] && [ "$(git rev-parse '@{u}' 2>/dev/null)" = "$sha" ]; then
    for _ in 1 2 3 4 5 6; do
      sleep "${OBJECTION_PR_WAIT:-3}"
      pr_head=$("$gh_bin" pr view --json headRefOid -q .headRefOid 2>/dev/null || true)
      [ "$pr_head" != "$sha" ] || break
    done
  fi
  [ "$pr_head" = "$sha" ] || { echo "the PR's head is ${pr_head:0:7}, the record is for ${sha:0:7}: push, then update." >&2; exit 1; }
fi

body="$dir/body-$sha.md"
{
  # Everything above the old record, trailing blank lines dropped.
  printf '%s\n' "$current" | awk '/^<!-- objection: sha=/{exit} {print}' |
    awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }'
  [ -z "$(printf '%s' "$current" | awk '/^<!-- objection: sha=/{exit} NF{print; exit}')" ] || printf '\n'
  # The accusation and the defense fold under <details>: a reader of the
  # PR wants the rulings and what is open, and a long table pushed them
  # off the screen. The section lines stay whole lines, which is how the
  # CI check and the precedent parser find them.
  if grep -qx '## Accusation' "$record" && grep -qx '## Judge' "$record"; then
    n=$(awk '/^## Accusation$/ { a = 1; next } /^## / { a = 0 } a && /^[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*\|/ { c++ } END { print c + 0 }' "$record")
    awk -v n="$n" '
      /^## Accusation$/ && !open { printf "<details>\n<summary>Accusation and defense (%s finding%s)</summary>\n\n", n, (n == 1 ? "" : "s"); open = 1 }
      /^## Judge$/ && open == 1 { print "</details>\n"; open = 2 }
      { print }
    ' "$record"
  else
    cat "$record"
  fi
  # Below the old record: the lines after its last VERDICT line.
  after=$(printf '%s\n' "$current" | awk '
    /^<!-- objection: sha=/ && !seen { seen = 1 }
    { lines[NR] = $0 }
    seen && /^VERDICT: / { last = NR }
    END { if (last) for (i = last + 1; i <= NR; i++) print lines[i] }')
  if [ -n "$(printf '%s' "$after" | tr -d '[:space:]')" ]; then
    printf '\n%s\n' "$(printf '%s\n' "$after" | awk 'NF { p = 1 } p')"
  fi
} >"$body"

if [ -n "$update" ]; then
  "$gh_bin" pr edit --body-file "$body" >/dev/null
  echo "PR body updated with the record for ${sha:0:7}."
fi
echo "$body"
