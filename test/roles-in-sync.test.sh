#!/bin/bash
# The Claude Code subagents (agents/*.md) and the tool-neutral role prompts
# (skills/objection/roles/*.md) must say the same thing. Body only: the
# agents add Claude Code frontmatter.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
for r in accuser defender; do
  body=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$ROOT/agents/$r.md" | sed '1{/^$/d;}')
  if [ "$body" != "$(cat "$ROOT/skills/objection/roles/$r.md")" ]; then
    echo "FAIL: agents/$r.md and skills/objection/roles/$r.md differ"
    failures=$((failures + 1))
  fi
done
# The version the records carry is the plugin's.
v=$(cat "$ROOT/skills/objection/VERSION")
p=$(node -e 'console.log(require(process.argv[1]).version)' "$ROOT/.claude-plugin/plugin.json")
[ "$v" = "$p" ] || { echo "FAIL: skills/objection/VERSION ($v) and plugin.json ($p) differ"; failures=$((failures + 1)); }
if [ "$failures" = 0 ]; then echo "roles: in sync"; else exit 1; fi
