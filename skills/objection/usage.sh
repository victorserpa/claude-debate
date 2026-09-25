#!/bin/bash
# What the debate's reviewers cost, from the log review.sh keeps.
#
#   usage.sh            totals per branch
#   usage.sh <branch>   every run on that branch, then its total
#   usage.sh --summary  cost per month, and the median and mean per branch
#                       (a branch is one PR: every round and reviewer)
#
# Only runs made through review.sh are logged: a reviewer run as a
# subagent, or in another session, is not in these numbers.
set -eu

# Outside a repository git prints nothing, and `cd ""` would succeed.
g=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$g" ] && common=$(cd "$g" && pwd) ||
  { echo "run it inside the repository whose debates you want to see."; exit 1; }
log="$common/objection/usage.log"
[ -s "$log" ] || { echo "no reviewer runs logged yet ($log)."; exit 0; }

if [ "${1:-}" = --summary ]; then
  awk -F'\t' '{ m = substr($1, 1, 7); runs[m]++; cost[m] += $8; if (!((m, $2) in seen)) { seen[m, $2] = 1; br[m]++ } }
    END {
      printf "%-8s %9s %5s %9s\n", "month", "branches", "runs", "cost"
      for (m in runs) printf "%-8s %9d %5d %9.3f\n", m, br[m], runs[m], cost[m]
    }' "$log" | { IFS= read -r h; printf '%s\n' "$h"; sort; }
  # Sorted per-branch totals, so the median needs no array sort (BSD awk).
  awk -F'\t' '{ c[$2] += $8 } END { for (b in c) printf "%.6f\n", c[b] }' "$log" | sort -n |
    awk '{ v[NR] = $1; t += $1 }
      END {
        med = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
        printf "per branch: %d branches, median $%.3f, mean $%.3f, max $%.3f\n", NR, med, t / NR, v[NR]
      }'
elif [ $# -eq 0 ]; then
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
