#!/bin/bash
# Cases for skills/objection/init.sh: what it detects and writes, and that
# it never overwrites a file.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$ROOT/skills/objection/init.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
has() { grep -qF -- "$2" "$1" || fail "$1 lacks [$2]"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$1 has [$2]"; }
repo() { # repo <name> <origin url>
  R="$T/$1"
  git init -q "$R" && cd "$R" || exit 1
  git remote add origin "$2"
  printf 'x\n' >README && git add . && gitc commit -q -m init
  git update-ref refs/remotes/origin/main HEAD
}

# A pnpm project on GitHub with develop: develop is the default base, the
# package's own checks are verify, the workflow is written.
repo gh git@github.com:me/app.git
git update-ref refs/remotes/origin/develop HEAD
printf '{"scripts":{"typecheck":"tsc","lint":"eslint .","test":"vitest run","dev":"next"}}\n' >package.json
touch pnpm-lock.yaml
bash "$INIT" >"$T/out" 2>&1 || fail "init failed ($(cat "$T/out"))"
node -e '
const c = JSON.parse(require("fs").readFileSync(".objection.json", "utf8"));
const want = { $schema: "https://raw.githubusercontent.com/victorserpa/objection/v1/skills/objection/objection.schema.json", bases: ["develop", "main"], defaultBase: "develop", verify: ["pnpm typecheck", "pnpm lint", "pnpm test"], budget: "lean" };
if (JSON.stringify(c) !== JSON.stringify(want)) { console.log("FAIL: config " + JSON.stringify(c)); process.exit(1); }
' || failures=$((failures + 1))
has .github/workflows/objection.yml "victorserpa/objection@v1"
has "$T/out" 'make the "record" check required'
[ -e .claude/settings.json ] && fail "the plugin host wrote a hook"
# Twice: refuses, touches nothing.
bash "$INIT" >"$T/out" 2>&1 && fail "a second init did not refuse"
has "$T/out" "already exists"

# npm with the placeholder test script: not a check. GitLab: the CI job.
repo gl https://gitlab.com/me/app.git
printf '{"scripts":{"test":"echo \\"Error: no test specified\\" && exit 1","lint":"eslint ."}}\n' >package.json
bash "$INIT" >"$T/out" 2>&1 || fail "init failed on GitLab ($(cat "$T/out"))"
has .objection.json '"npm run lint"'
hasnt .objection.json '"npm test"'
has .gitlab/objection.gitlab-ci.yml "objection:"
[ -e .github ] && fail "GitLab got a GitHub workflow"

# Go, elsewhere, Cursor: the hook names the skill directory; no CI gate.
repo go ssh://git@git.example.com/me/app.git
printf 'module x\n' >go.mod
bash "$INIT" --host cursor >"$T/out" 2>&1 || fail "init failed for Cursor ($(cat "$T/out"))"
has .objection.json '"go test ./..."'
# hook.sh fails closed when node cannot run; Windows keeps node for Cursor,
# Codex and Gemini, which may lack a POSIX sh there.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) has .cursor/hooks.json "node \\\"$ROOT/skills/objection/gate/hook.mjs\\\" --host cursor" ;;
  *) has .cursor/hooks.json "sh \\\"$ROOT/skills/objection/gate/hook.sh\\\" --host cursor" ;;
esac
hasnt .cursor/hooks.json "<SKILL_DIR>"
has "$T/out" "there is no CI gate"

# Claude Code without the plugin, skill outside the repository: an
# absolute path, not one glued to $CLAUDE_PROJECT_DIR.
repo cc git@github.com:me/cc.git
bash "$INIT" --host claude >"$T/out" 2>&1 || fail "init failed for claude ($(cat "$T/out"))"
has .claude/settings.json 'sh \"'"$ROOT/skills/objection/gate/hook.sh"'\"'
hasnt .claude/settings.json 'CLAUDE_PROJECT_DIR'

# An existing hook file is never overwritten: the snippet is printed.
repo keep git@github.com:me/keep.git
mkdir -p .gemini && printf '{"theme":"mine"}\n' >.gemini/settings.json
bash "$INIT" --host gemini >"$T/out" 2>&1 || fail "init failed with an existing settings file"
has .gemini/settings.json '"theme":"mine"'
hasnt .gemini/settings.json "hook.mjs"
has "$T/out" "merge by hand: .gemini/settings.json"
has "$T/out" "--host gemini"

# Advisory: enforce false, no CI check.
repo adv git@github.com:me/adv.git
bash "$INIT" --advisory >"$T/out" 2>&1 || fail "advisory init failed ($(cat "$T/out"))"
has .objection.json '"enforce": false'
[ -e .github ] && fail "advisory init wrote a CI check"
has "$T/out" "advisory: nothing blocks"

# bun: `bun run test`, never `bun test` (bun's own runner).
repo bun git@github.com:me/bun.git
printf '{"scripts":{"test":"vitest run"}}\n' >package.json && touch bun.lockb
bash "$INIT" >"$T/out" 2>&1 || fail "bun init failed"
has .objection.json '"bun run test"'

# Nothing to verify: said so. Dry run: writes nothing.
repo dry git@github.com:me/dry.git
bash "$INIT" --dry-run >"$T/out" 2>&1 || fail "dry run failed"
[ -e .objection.json ] && fail "a dry run wrote the config"
has "$T/out" "would write: .objection.json"
has "$T/out" "verify: none found"
bash "$INIT" --host vscode >/dev/null 2>&1 && fail "an unknown host was accepted"

# On Windows (uname faked), Cursor gets node, even when the skill's path
# has a space.
mkdir -p "$T/fakeuname" "$T/sk dir" && printf '#!/bin/sh\necho MINGW64_NT-10.0\n' >"$T/fakeuname/uname" && chmod +x "$T/fakeuname/uname"
cp -R "$ROOT/skills/objection" "$T/sk dir/objection"
repo win ssh://git@git.example.com/me/win.git
PATH="$T/fakeuname:$PATH" bash "$T/sk dir/objection/init.sh" --host cursor >"$T/out" 2>&1 || fail "init failed on faked Windows ($(cat "$T/out"))"
grep -qF 'node \"' .cursor/hooks.json && grep -qF 'sk dir/objection/gate/hook.mjs\" --host cursor' .cursor/hooks.json || fail "Windows with a spaced skill path did not get node"
hasnt .cursor/hooks.json "hook.sh"

[ "$failures" -eq 0 ] && echo "init: all cases passed" || { echo "init: $failures failure(s)"; exit 1; }
