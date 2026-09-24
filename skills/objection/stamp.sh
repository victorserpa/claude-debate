#!/bin/bash
# Registers a /objection record for the current HEAD, where the
# objection gate (gate/core.mjs) looks for it.
#
# Usage: stamp.sh <record.md> <base>     (base: origin/<branch the PR targets>)
#
# Refuses the record when:
# - there are uncommitted tracked changes: the record describes HEAD, and
#   code outside the commit was not debated;
# - the base is not one of the PR targets in .objection.json;
# - a required section or the verdict line is missing;
# - the verdict is APPROVED but "## Open" still lists a BLOCKER or HIGH
#   finding.
#
# The first line it writes is a stamp with the SHA and the base. The hook
# only accepts stamped records, so a file dropped into .git/objection/ by hand
# does not count. Nothing stops someone from stamping a made-up record: the
# rule that the record comes out of the debate, not out of whoever wrote the
# code, lives in SKILL.md. This is a process guard, not a security boundary.
set -eu

record="${1:?usage: stamp.sh <record.md> <base>}"
base="${2:?usage: stamp.sh <record.md> <base>}"

[ -f "$record" ] || { echo "record not found: $record" >&2; exit 1; }

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "uncommitted changes; commit, then debate the commit." >&2
  exit 1
fi

top=$(git rev-parse --show-toplevel)
# Tool-neutral location first; .claude/ kept for Claude Code users.
config="$top/.objection.json"
[ -f "$config" ] || config="$top/.claude/objection.json"
[ -f "$config" ] || { echo "no .objection.json at $top: this repository has not opted in to /objection." >&2; exit 1; }

# Only real PR targets. An arbitrary base (HEAD~1) would let a docs-only
# commit on top of undebated code fall into the documentation exemption.
allowed=$(node -e '
const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const b = c.bases || (c.defaultBase ? [c.defaultBase] : []);
console.log(b.map((x) => "origin/" + x).join(" "));
' "$config")
if [ -z "$allowed" ]; then
  allowed=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
fi
case " $allowed " in
  *" $base "*) ;;
  *) echo "base must be one of: $allowed (got: $base)." >&2; exit 1 ;;
esac
git rev-parse --verify -q "$base" >/dev/null ||
  { echo "unknown base: $base (run git fetch origin)." >&2; exit 1; }

files=$(git diff --name-only "$base"...HEAD)
[ -n "$files" ] || { echo "nothing to debate between $base and HEAD." >&2; exit 1; }

# A docs-only diff skips accusation and defense (see SKILL.md) but still
# needs a record saying so.
docs_only=yes
while IFS= read -r f; do
  case "$f" in
    # .md under agent configuration dirs are the debate's own prompts
    # (agents, skills, rules): weakening the defender must not ship
    # without a debate. Same list as gate/check-pr.mjs.
    .claude/* | .cursor/* | .codex/* | .gemini/* | .github/*) docs_only=no ;;
    *.md | docs/*) ;;
    *) docs_only=no ;;
  esac
done <<<"$files"

if [ "$docs_only" = no ]; then
  for section in '## Accusation' '## Defense' '## Judge' '## Open'; do
    grep -qx "$section" "$record" || { echo "missing section '$section' in the record." >&2; exit 1; }
  done
fi

verdict=$(grep -E '^VERDICT: ' "$record" | tail -1)
case "$verdict" in
  'VERDICT: APPROVED' | 'VERDICT: REJECTED') ;;
  *) echo "missing a 'VERDICT: APPROVED' or 'VERDICT: REJECTED' line." >&2; exit 1 ;;
esac

if [ "$docs_only" = no ]; then
  # The judge's structured count is the authority: free text is not parsed
  # for it. The word scan below is only a cross-check against a count that
  # contradicts its own list.
  counts=$(grep -E '^OPEN: BLOCKER=[0-9]+ HIGH=[0-9]+$' "$record" | tail -1)
  [ -n "$counts" ] || { echo "missing the line 'OPEN: BLOCKER=<n> HIGH=<n>' (the judge's count of what is left open)." >&2; exit 1; }
  if [ "$verdict" = 'VERDICT: APPROVED' ] && [ "$counts" != 'OPEN: BLOCKER=0 HIGH=0' ]; then
    echo "APPROVED with $counts: fix them or reject." >&2
    exit 1
  fi
fi

if [ "$verdict" = 'VERDICT: APPROVED' ] && [ "$docs_only" = no ]; then
  # A line that STARTS with the severity (list marker and bold optional):
  # "- HIGH: x", "HIGH: x", "1. **High** x", "1 HIGH x", "4, HIGH, x" (the
  # template's "#, severity" order). Whole word, so "no HIGH finding is
  # left" (does not start with it) and "high-level note" (hyphenated) do
  # not count.
  open=$(awk '/^## Open$/{f=1;next} /^## /{f=0} f' "$record")
  if printf '%s\n' "$open" | grep -qiE '^[[:space:]]*([-*]|[0-9]+[.),]?)?[[:space:]]*,?[[:space:]]*[*_]*(blocker|high)([^[:alpha:]-]|$)'; then
    echo "APPROVED with a BLOCKER/HIGH finding still open: fix it or reject." >&2
    exit 1
  fi
fi

sha=$(git rev-parse HEAD)
dest="$(git rev-parse --path-format=absolute --git-common-dir)/objection"
mkdir -p "$dest"
{ printf '<!-- objection: sha=%s base=%s -->\n' "$sha" "$base"; cat "$record"; } >"$dest/$sha.md"
echo "record stored for ${sha:0:7}: $dest/$sha.md"
echo "$verdict"
