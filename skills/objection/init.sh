#!/bin/bash
# Opts a repository in without asking anything it can read for itself.
#
#   init.sh [--host plugin|claude|cursor|codex|gemini] [--advisory] [--dry-run]
#
# --advisory: try it without blocking anyone. The config gets
# "enforce": false (the local hook reports what it would block and lets
# it through) and no CI check is written. Remove the line to enforce.
#
# Writes .objection.json from what the repository shows:
#   bases       origin's default branch, plus develop when origin has it
#               (then develop is defaultBase)
#   verify      the project's own checks: package.json scripts (typecheck,
#               lint, test) run with the package manager its lockfile
#               names; Cargo, Go, a Makefile `test` target, pytest
#   budget      lean
# Then the gates:
#   --host      the local hook for that agent (default: plugin, which is
#               Claude Code with the plugin installed: nothing to write)
#   CI          .github/workflows/objection.yml on GitHub,
#               .gitlab/objection.gitlab-ci.yml on GitLab, nothing elsewhere
# A file that already exists is never overwritten: the snippet is printed
# to merge by hand. Nothing is committed; the agent shows the user the
# result and commits it. Invariants and reviewers are left for the user:
# they are the project's rules, and inventing them would be worse than none.
set -eu

host=plugin
dry=""
advisory=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="${2:?--host needs plugin, claude, cursor, codex or gemini}"; shift 2 ;;
    --dry-run) dry=yes; shift ;;
    --advisory) advisory=yes; shift ;;
    -h|--help) echo "usage: init.sh [--host plugin|claude|cursor|codex|gemini] [--advisory] [--dry-run]"; exit 0 ;;
    *) echo "init.sh: unknown option $1" >&2; echo "usage: init.sh [--host plugin|claude|cursor|codex|gemini] [--advisory] [--dry-run]" >&2; exit 2 ;;
  esac
done
case "$host" in plugin | claude | cursor | codex | gemini) ;; *) echo "unknown host: $host" >&2; exit 2 ;; esac

here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "run it inside the repository to opt in." >&2; exit 1; }
cd "$top"
for c in .objection.json .claude/objection.json; do
  [ -f "$c" ] && { echo "$c already exists: this repository is opted in. Edit it instead." >&2; exit 1; }
done

# Bases: origin's default branch (origin/HEAD, else main/master on origin).
default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || default=""
if [ -z "$default" ]; then
  for b in main master; do
    git rev-parse --verify -q "refs/remotes/origin/$b" >/dev/null && { default="$b"; break; }
  done
fi
[ -n "$default" ] || default=$(git symbolic-ref --short HEAD 2>/dev/null || echo main)
bases="$default"
base_default="$default"
if [ "$default" != develop ] && git rev-parse --verify -q refs/remotes/origin/develop >/dev/null; then
  bases="develop $default"
  base_default=develop
fi

# Forge, from origin's URL.
url=$(git remote get-url origin 2>/dev/null || echo "")
forge=none
case "$url" in
  *github.com[:/]* | *github.com/*) forge=github ;;
  *gitlab*) forge=gitlab ;;
esac

config=$(node -e '
const fs = require("fs");
const [bases, def, advisory] = [process.argv[1].split(" "), process.argv[2], process.argv[3] === "yes"];
const has = (f) => fs.existsSync(f);
const verify = [];
if (has("package.json")) {
  let scripts = {};
  try { scripts = JSON.parse(fs.readFileSync("package.json", "utf8")).scripts || {}; } catch {}
  const pm = has("pnpm-lock.yaml") ? "pnpm" : has("yarn.lock") ? "yarn"
    : has("bun.lockb") || has("bun.lock") ? "bun" : "npm";
  // `bun test` is the runner built into bun, not the script: bun gets `run`.
  const run = (s) => (pm === "bun" || (pm === "npm" && s !== "test") ? `${pm} run ${s}` : `${pm} ${s}`);
  for (const s of ["typecheck", "type-check", "lint", "test"]) {
    // npm init writes a test script that only fails: not a check.
    if (scripts[s] && !/no test specified/.test(scripts[s])) verify.push(run(s));
  }
}
if (has("Cargo.toml")) verify.push("cargo check", "cargo test");
if (has("go.mod")) verify.push("go vet ./...", "go test ./...");
if (!verify.length && has("Makefile") && /^test:/m.test(fs.readFileSync("Makefile", "utf8"))) verify.push("make test");
if (!verify.length && (has("pytest.ini") || (has("pyproject.toml") && /pytest/.test(fs.readFileSync("pyproject.toml", "utf8"))))) verify.push("python -m pytest");
// $schema: editors complete and check the keys (objection.schema.json).
const c = { $schema: "https://raw.githubusercontent.com/victorserpa/objection/v1/skills/objection/objection.schema.json",
  bases, defaultBase: def, verify, budget: "lean", ...(advisory && { enforce: false }) };
process.stdout.write(JSON.stringify(c, null, 2) + "\n");
' "$bases" "$base_default" "$advisory")

# The skill directory as the hook should name it: relative to the
# repository when the skill lives inside it, absolute otherwise.
top_p=$(pwd -P)
case "$here/" in
  "$top_p/"*) skill_dir="${here#"$top_p/"}" ;;
  *) skill_dir="$here" ;;
esac

wrote=()
manual=()
put() { # put <path> <content>
  if [ -e "$1" ]; then
    manual+=("$1")
    printf '\n%s exists; merge this into it:\n%s\n' "$1" "$2"
    return
  fi
  wrote+=("$1")
  [ -n "$dry" ] && { printf '\nwould write %s:\n%s\n' "$1" "$2"; return; }
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}
template() {
  # An absolute skill directory replaces the project-relative prefix too.
  case "$skill_dir" in
    /*) sed -e "s#\\\$CLAUDE_PROJECT_DIR/<SKILL_DIR>#$skill_dir#g" -e "s#<SKILL_DIR>#$skill_dir#g" "$here/templates/$1" ;;
    *) sed "s#<SKILL_DIR>#$skill_dir#g" "$here/templates/$1" ;;
  esac | {
    # hook.sh fails closed when node cannot run; on Windows, where Cursor,
    # Codex and Gemini may run hooks without a POSIX sh, they call node.
    case "$(uname -s)/$1" in
      MINGW*/claude/* | MSYS*/claude/* | CYGWIN*/claude/*) cat ;;
      MINGW* | MSYS* | CYGWIN*) sed 's#sh \(.*\)/gate/hook\.sh#node \1/gate/hook.mjs#' ;;
      *) cat ;;
    esac
  }
}

put .objection.json "$config"
case "$host" in
  claude) put .claude/settings.json "$(template claude/settings.json)" ;;
  cursor) put .cursor/hooks.json "$(template cursor/hooks.json)" ;;
  codex) put .codex/hooks.json "$(template codex/hooks.json)" ;;
  gemini) put .gemini/settings.json "$(template gemini/settings.json)" ;;
esac
[ -z "$advisory" ] || forge_gate=none
case "${forge_gate:-$forge}" in
  github) put .github/workflows/objection.yml "$(cat "$here/templates/github/objection.yml")" ;;
  gitlab) put .gitlab/objection.gitlab-ci.yml "$(cat "$here/templates/gitlab/objection.gitlab-ci.yml")" ;;
esac

echo
echo "objection init: bases $bases (default $base_default), forge $forge, host $host"
label=wrote
[ -z "$dry" ] || label="would write"
[ ${#wrote[@]} -eq 0 ] || echo "$label: ${wrote[*]:-}"
[ ${#manual[@]} -eq 0 ] || echo "merge by hand: ${manual[*]:-}"
printf '%s\n' "$config" | grep -q '"verify": \[\]' &&
  echo "verify: none found; add the project's cheapest checks (types, tests) to .objection.json."
echo "next:"
[ "$host" = gemini ] && echo "- Gemini: trust this folder in Gemini once; it skips project hooks in an untrusted folder, silently."
[ "$host" = plugin ] && echo "- local gate: the Claude Code plugin's hook (nothing written); other agents: init.sh --host cursor|codex|gemini"
[ "$host" = codex ] && echo "- Codex: open codex in this repository once and trust the objection hook; until then Codex skips it silently."
[ -z "$advisory" ] || echo "- advisory: nothing blocks; the hook says what it would block. Remove \"enforce\": false to enforce; for the CI check copy templates/github/objection.yml (or the GitLab one)."
[ -n "$advisory" ] || case "$forge" in
  github) echo "- GitHub: make the \"record\" check required in a ruleset on $default (Settings > Rules)."
    echo "- optional: an accuser in CI with its own key, templates/github/objection-review.yml (Claude or a free-tier Gemini key)." ;;
  gitlab) echo "- GitLab: include .gitlab/objection.gitlab-ci.yml from .gitlab-ci.yml and turn on \"Pipelines must succeed\"."
    echo "- optional: an accuser in CI with its own key, templates/gitlab/objection-review.gitlab-ci.yml (Claude or a free-tier Gemini key)." ;;
  *) echo "- no GitHub or GitLab origin: there is no CI gate, the debate is advice there." ;;
esac
echo "- invariants (optional): the few rules that must never break, each with the paths it guards."
echo "- doctor.sh: checks the setup (config, hooks, CI, required check) whenever something seems off."
echo "- commit these files; from then on a PR needs an APPROVED record."
