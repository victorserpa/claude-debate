#!/bin/bash
# Cases for skills/objection/doctor.sh: one throwaway repository per
# config, no network (gh points nowhere).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR="$ROOT/skills/objection/doctor.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
export OBJECTION_GH_BIN=/nonexistent/gh
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
n=0
repo() { # config-text -> a fresh repository with it committed on origin/main
  n=$((n + 1)); R="$T/r$n"
  git init -q -b main "$R" && cd "$R" || exit 1
  [ -z "$1" ] || printf '%s\n' "$1" >.objection.json
  echo x >a && git add -A && gitc commit -q -m base && git update-ref refs/remotes/origin/main HEAD
}
doc() { bash "$DOCTOR" >"$T/out" 2>&1; }
has() { grep -qF -- "$1" "$T/out" || fail "doctor output lacks [$1]: $(cat "$T/out")"; }
hasnt() { grep -qF -- "$1" "$T/out" && fail "doctor output has [$1]"; }

repo ""
doc && fail "no config passed"
has "FAIL  no .objection.json"

repo '{"bases":["main"],"defaultBase":"main","verify":["true"]}'
doc || fail "a valid config failed: $(cat "$T/out")"
has "ok    config: .objection.json, the same on origin/main"
hasnt "FAIL"

repo '{"bases":["main"],"verify":["true"],"invariant":[{"rule":"x","paths":"^a"}]}'
doc || fail "an unknown key failed the run"
has 'unknown key "invariant"'

repo '{"bases":["main"],"verify":["true"],"invariants":[{"rule":"x","paths":"(["}]}'
doc && fail "an invalid regex passed"
has 'invariants[0].paths: invalid regex'

repo '{"bases":["main"],'
doc && fail "invalid JSON passed"
has "not valid JSON"

repo '{"bases":["main"],"defaultBase":"develop","verify":["true"]}'
doc && fail "a defaultBase outside bases passed"
has 'defaultBase "develop" is not one of bases'

repo '{"bases":["main"],"verify":["true"],"budget":"cheap","smallDiff":-1,"models":{"default":"so net"}}'
doc && fail "bad values passed"
has 'budget "cheap"'
has "smallDiff must be a whole number"
has "models.default"

# The working copy ahead of the base: the debate uses the base's.
repo '{"bases":["main"],"verify":["true"]}'
printf '{"bases":["main"],"verify":["true","false"]}\n' >.objection.json
doc
has "origin/main has a different .objection.json"

# Hooks and the trust they need; a workflow with the check.
repo '{"bases":["main"],"verify":["true"]}'
mkdir -p .codex .github/workflows
echo '{"hooks":"node skills/objection/gate/hook.mjs --host codex"}' >.codex/hooks.json
printf 'jobs:\n  record:\n    steps:\n      - uses: victorserpa/objection@v1\n' >.github/workflows/objection.yml
doc || fail "hooks and CI failed the run: $(cat "$T/out")"
has "ok    local gate hooks: codex"
has "codex: the hook runs only once trusted"
has "ok    CI: a GitHub workflow runs the record check"
has "could not read the rules"

# The schema and the doctor know the same keys.
schema=$(node -e 'console.log(Object.keys(require(process.argv[1]).properties).sort().join(" "))' "$ROOT/skills/objection/objection.schema.json")
doctor=$(node -e 'const m = require("fs").readFileSync(process.argv[1], "utf8").match(/const known = \[(.*)\];/); console.log(JSON.parse("[" + m[1] + "]").sort().join(" "))' "$DOCTOR")
[ "$schema" = "$doctor" ] || fail "schema keys ($schema) differ from doctor.sh's ($doctor)"

[ "$failures" = 0 ] && echo "doctor: all cases passed" || { echo "doctor: $failures failure(s)"; exit 1; }
