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
# A quoted target reaches this as \"dir with space\" inside the JSON.
cds=$(printf '%s' "$in" | grep -oE '(^|[^A-Za-z0-9_])cd +(\\"[^"\\]+\\"|[^;&|" ]+)' | sed -e 's/^.*cd *//' -e 's/^\\"//' -e 's/\\"$//')
optin=""
# Split on newlines only, and no globbing: a target is tested as written.
set -f
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
case "$rc" in
  127) why="node is not on the hook's PATH (install Node.js 18 or later, or put it where the host's hooks look)" ;;
  126) why="node was found but could not start (a version manager's shim, such as asdf, mise, volta, nvm or fnm, with no version for this directory, or a file without exec permission)" ;;
  *) why="node exited $rc while checking (a Node.js older than 18, or a crash; \`node -v\` and \`bash <skill>/doctor.sh\` show which)" ;;
esac
msg="[objection] Blocked: the gate could not check this command: $why. Fix node, then retry."
case " $* " in
  *" cursor "*) printf '{"continue":true,"permission":"deny","userMessage":"%s","agentMessage":"%s"}' "$msg" "$msg" ;;
esac
printf '%s\n' "$msg" >&2
exit 2
