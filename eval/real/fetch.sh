#!/bin/bash
# Builds eval fixtures from real bugs: commits in public repositories that
# introduced a defect a later commit fixed, naming the culprit. The code
# is not stored here (licenses vary): this downloads, for each case in
# cases.jsonl, the touched files at the culprit's parent (base/) and at
# the culprit (change/), into a cache directory, and writes the
# expect.json and config.json eval/run.sh reads.
#
#   bash eval/real/fetch.sh [dir]          default: $TMPDIR/objection-real
#   EVAL_FIXTURES=<dir> bash eval/run.sh   runs them
#
# Needs curl, node and network; `gh` when present (higher rate limit).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-${TMPDIR:-/tmp}/objection-real}"
mkdir -p "$out"

api() { # api <path>: the GitHub REST API, through gh when it is logged in
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh api "$1"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
  fi
}

while IFS= read -r line; do
  [ -n "$line" ] || continue
  name=$(printf '%s' "$line" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).name))')
  if [ -f "$out/$name/expect.json" ]; then echo "cached: $name"; continue; fi
  repo=$(printf '%s' "$line" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).repo))')
  sha=$(printf '%s' "$line" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).introducing))')
  meta=$(api "repos/$repo/commits/$sha")
  parent=$(printf '%s' "$meta" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).parents[0].sha))')
  goal=$(printf '%s' "$meta" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).commit.message.split("\n")[0]))')
  rm -rf "$out/$name.tmp" && mkdir -p "$out/$name.tmp"
  for f in $(printf '%s' "$line" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).files.join("\n")))'); do
    for side in base change; do
      rev=$parent; [ "$side" = change ] && rev=$sha
      mkdir -p "$out/$name.tmp/$side/$(dirname "$f")"
      # A file the culprit created has no base side.
      curl -fsSL "https://raw.githubusercontent.com/$repo/$rev/$f" -o "$out/$name.tmp/$side/$f" || rm -f "$out/$name.tmp/$side/$f"
    done
  done
  printf '{"bases":["main"]}\n' >"$out/$name.tmp/config.json"
  GOAL="$goal" LINE="$line" node -e '
    const c = JSON.parse(process.env.LINE);
    process.stdout.write(JSON.stringify({ goal: process.env.GOAL, severity: c.severity, match: c.match, file: c.file, lines: c.lines, source: `https://github.com/${c.repo}/commit/${c.introducing}`, fixedBy: c.fix }) + "\n");
  ' >"$out/$name.tmp/expect.json"
  rm -rf "$out/$name" && mv "$out/$name.tmp" "$out/$name"
  echo "fetched: $name ($repo@${sha:0:7}, parent ${parent:0:7})"
done <"$here/cases.jsonl"
echo "$out"
