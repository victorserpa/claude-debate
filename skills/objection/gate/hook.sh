#!/bin/sh
# Runs the gate (hook.mjs) and fails closed when it cannot run.
#
#   sh hook.sh [--host <name>]    the same arguments as hook.mjs
#
# A host reads exit 2 as a block and any other failure as "go ahead". So a
# `node` that does not start (not installed: 127; a version manager's shim
# refusing because .tool-versions or .nvmrc pins a version that is not
# installed: 126) or crashes (1) let `gh pr merge` through. On such a
# failure this blocks what hook.mjs would have checked (the same test it
# uses for input it cannot parse), and only where the repository opted in.
# It does not stop a host that cannot start sh itself, nor a PR command
# written so that the test above misses it (the required check covers both).
here=$(cd "$(dirname "$0")" && pwd)
in=$(cat)
printf '%s' "$in" | node "$here/hook.mjs" "$@"
rc=$?
case "$rc" in 0 | 2) exit "$rc" ;; esac
printf '%s' "$in" | grep -qE '(^|[^A-Za-z0-9_])gh([^A-Za-z0-9_]|$)|pull_request|auto_merge' || exit 0
# Opted in: any place the host may mean. hook.mjs reads the payload's cwd
# first, since a host can start the hook elsewhere; without node the cwd
# comes out of the JSON with sed (Windows backslashes turned to /).
cwd=$(printf '%s' "$in" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | sed 's#\\\\#/#g')
# `cd <dir> && gh ...`: the directories the command changes to count too.
cds=$(printf '%s' "$in" | grep -oE '(^|[^A-Za-z0-9_])cd +[^;&|" ]+' | sed 's/.*cd *//')
optin=""
IFS_old=$IFS
IFS='
'
for d in $cds "$cwd" "${CLAUDE_PROJECT_DIR:-}" "${CURSOR_PROJECT_DIR:-}" "${GEMINI_PROJECT_DIR:-}" "$PWD"; do
  [ -n "$d" ] && [ -d "$d" ] || continue
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || continue
  { [ -f "$top/.objection.json" ] || [ -f "$top/.claude/objection.json" ]; } && { optin=yes; break; }
done
IFS=$IFS_old
[ -n "$optin" ] || exit 0
msg="[objection] Blocked: the gate did not run (node exited $rc), so it cannot check this command. Make node run in this repository (a .tool-versions or .nvmrc may pin a version that is not installed), then retry."
case " $* " in
  *" cursor "*) printf '{"continue":true,"permission":"deny","userMessage":"%s","agentMessage":"%s"}' "$msg" "$msg" ;;
esac
printf '%s\n' "$msg" >&2
exit 2
