#!/bin/bash
# Opens one issue for what the stamped record of HEAD left open, so a
# MEDIUM or LOW that shipped is tracked instead of forgotten.
#
#   open-issue.sh              the record of HEAD; prints the issue's URL
#   open-issue.sh --dry-run    prints the title and body, creates nothing
#
# The Open section is the body, with the branch, the commit and the PR (if
# any). Nothing open ("nothing", or no list item): no issue. Run again on
# the same commit: the existing issue is printed, not a second one (its
# body carries a marker with the SHA). Needs `gh`, logged in.
#
# Env: OBJECTION_GH_BIN (default gh).
set -eu

dry=""
case "${1:-}" in
  "") ;;
  --dry-run) dry=yes ;;
  *) echo "usage: open-issue.sh [--dry-run]" >&2; exit 2 ;;
esac
gh_bin="${OBJECTION_GH_BIN:-gh}"

sha=$(git rev-parse HEAD)
dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)/objection"
record="$dir/$sha.md"
[ -f "$record" ] || { echo "no stamped record for ${sha:0:7}: debate, judge and run stamp.sh first." >&2; exit 1; }
# What stamp.sh writes: its line for this SHA first, APPROVED last.
{ head -n 1 "$record" | grep -q "^<!-- objection: sha=$sha " &&
  [ "$(grep -E '^VERDICT:' "$record" | tail -n 1)" = "VERDICT: APPROVED" ]; } ||
  { echo "the record for ${sha:0:7} is not stamped APPROVED: run stamp.sh on it first." >&2; exit 1; }

# The items of the Open section: its lines up to the OPEN: count.
open=$(awk '/^## Open[[:space:]]*$/ { f = 1; next } /^## / { f = 0 } /^OPEN:/ { f = 0 } f' "$record" |
  awk '{ l[NR] = $0 } END { a = 1; while (a <= NR && l[a] ~ /^[[:space:]]*$/) a++; b = NR; while (b >= a && l[b] ~ /^[[:space:]]*$/) b--; for (i = a; i <= b; i++) print l[i] }')
# Empty, or only "nothing": nothing to track. Anything else is, list or prose.
if [ -z "$open" ] || printf '%s\n' "$open" | grep -qixE '[[:space:]]*(nothing|none)[.]?[[:space:]]*'; then
  echo "nothing open in the record for ${sha:0:7}: no issue."
  exit 0
fi

branch=$(git rev-parse --abbrev-ref HEAD)
# A detached HEAD (a CI checkout) has no branch name to show.
[ "$branch" != HEAD ] || branch="commit ${sha:0:7}"
marker="<!-- objection-open: sha=$sha -->"
pr_url=""
command -v "$gh_bin" >/dev/null 2>&1 && pr_url=$("$gh_bin" pr view --json url -q .url 2>/dev/null || true)
title="Open findings from $branch @ ${sha:0:7}"
[ "$branch" != "commit ${sha:0:7}" ] || title="Open findings from commit ${sha:0:7}"
body="Findings the debate left open when this was approved (MEDIUM and LOW ship with the record; each one still deserves a decision).

$open

Branch: $branch; commit \`${sha:0:7}\`${pr_url:+, PR $pr_url}.

$marker"

if [ -n "$dry" ]; then
  printf '%s\n\n%s\n' "$title" "$body"
  exit 0
fi
command -v "$gh_bin" >/dev/null 2>&1 || { echo "gh not found: install it and log in, or open the issue by hand (--dry-run prints it)." >&2; exit 1; }

# Once per commit: an issue already carrying the marker is the answer. The
# short SHA is in every title, which search indexes (not HTML comments). A
# failed lookup stops here: creating anyway could open a duplicate.
list=$("$gh_bin" issue list --state all --search "${sha:0:7} in:title" --json url,body) ||
  { echo "could not list the issues (gh issue list failed): nothing created. Log in with gh, or open it by hand (--dry-run prints it)." >&2; exit 1; }
existing=$(printf '%s' "$list" | MARK="$marker" node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let a;try{a=JSON.parse(s)}catch{process.exit(3)}const i=a.find(x=>(x.body||"").includes(process.env.MARK));if(i)console.log(i.url)})') ||
  { echo "could not read the issue list: nothing created." >&2; exit 1; }
if [ -n "$existing" ]; then
  echo "$existing"
  exit 0
fi
"$gh_bin" issue create --title "$title" --body "$body"
