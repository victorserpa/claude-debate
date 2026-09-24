#!/bin/bash
# What the debate's reviewers cost, from the log review.sh keeps.
#
#   usage.sh            totals per branch
#   usage.sh <branch>   every run on that branch, then its total
#
# Only runs made through review.sh are logged: a reviewer run as a
# subagent, or in another session, is not in these numbers.
set -eu

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  { echo "run it inside the repository whose debates you want to see."; exit 1; }
log="$common/objection/usage.log"
[ -s "$log" ] || { echo "no reviewer runs logged yet ($log)."; exit 0; }

if [ $# -eq 0 ]; then
  awk -F'\t' '
    { runs[$2]++; inp[$2] += $6; outp[$2] += $7; cost[$2] += $8; last[$2] = $1 }
    END {
      printf "%-40s %5s %10s %10s %9s  %s\n", "branch", "runs", "input", "output", "cost", "last run"
      for (b in runs) printf "%-40s %5d %10d %10d %9.3f  %s\n", b, runs[b], inp[b], outp[b], cost[b], last[b]
    }' "$log"
else
  awk -F'\t' -v b="$1" '
    $2 == b { n++; i += $6; o += $7; c += $8
              printf "%s  %s  %-8s %-7s %8d in %7d out  $%.3f  %s\n", $1, $3, $4, $5, $6, $7, $8, $9 }
    END {
      if (!n) { print "no runs logged for " b; exit }
      printf "total: %d runs, %d input + %d output tokens, $%.3f\n", n, i, o, c
    }' "$log"
fi
