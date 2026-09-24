#!/bin/bash
# Cases for skills/objection/review.sh with a fake `claude` that records its
# arguments and stdin, so no model is called.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$ROOT/skills/objection/review.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
failures=0
has() { grep -qF -- "$2" "$1" || { echo "FAIL: $1 lacks [$2]"; failures=$((failures + 1)); }; }
hasnt() { grep -qF -- "$2" "$1" && { echo "FAIL: $1 has [$2]"; failures=$((failures + 1)); }; }

cat >"$T/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/args"
pwd >"$FAKE_DIR/cwd"
cat >"$FAKE_DIR/stdin"
printf '{"result":"| severity | kind |","usage":{"input_tokens":2,"cache_creation_input_tokens":10000,"output_tokens":300},"total_cost_usd":0.1}\n'
EOF
chmod +x "$T/claude"
export OBJECTION_CLAUDE="$T/claude" FAKE_DIR="$T"

R="$T/repo"
git init -q "$R" && cd "$R" || exit 1
printf 'root rules\n' >CLAUDE.md
mkdir -p src && seq 1 200 | sed 's/^/code line /' >src/a.ts
git add . && gitc commit -q -m base
printf '# brief\nthe diff\n' >"$T/brief.md"

# Accuser: isolated flags, role as system prompt, brief on stdin, empty cwd.
out=$(bash "$REVIEW" accuser "$T/brief.md" 2>"$T/err")
[ "$out" = "| severity | kind |" ] || { echo "FAIL: result not printed ($out)"; failures=$((failures + 1)); }
has "$T/args" "--tools"
has "$T/args" "--strict-mcp-config"
has "$T/args" '{"mcpServers":{}}'
has "$T/args" "--disable-slash-commands"
has "$T/args" "--setting-sources"
has "$T/args" "--no-session-persistence"
has "$T/args" "$ROOT/skills/objection/roles/accuser.md"
has "$T/args" "You have NO tools"
has "$T/stdin" "the diff"
has "$T/err" "accuser used 10002 input + 300 output tokens"
# The empty tools value must reach claude as an empty argument.
awk 'prev=="--tools" && $0!="" {bad=1} {prev=$0} END{exit bad}' "$T/args" || { echo "FAIL: --tools was not empty"; failures=$((failures + 1)); }
# No CLAUDE.md where it runs.
[ ! -e "$(cat "$T/cwd")/CLAUDE.md" ] || { echo "FAIL: ran next to a CLAUDE.md"; failures=$((failures + 1)); }
[ "$(cat "$T/cwd")" != "$R" ] || { echo "FAIL: ran in the repository"; failures=$((failures + 1)); }

# Defender: findings plus excerpts of the cited lines, from HEAD.
printf '| 1 | HIGH | BUG | src/a.ts:100 | x | read | y |\n| 2 | LOW | BUG | missing/file.ts:3 | x | read | y |\n' >"$T/findings.md"
bash "$REVIEW" defender "$T/brief.md" "$T/findings.md" >/dev/null 2>&1
has "$T/args" "$ROOT/skills/objection/roles/defender.md"
has "$T/stdin" "# Findings to answer"
has "$T/stdin" "src/a.ts:100"
has "$T/stdin" "## src/a.ts (lines 60-140)"
has "$T/stdin" "  100  code line 100"
hasnt "$T/stdin" "code line 141"
hasnt "$T/stdin" "## missing/file.ts"
# A dirty working copy does not leak: excerpts come from HEAD. The recorded
# stdin is removed first, so the case cannot pass on the previous run.
printf 'UNCOMMITTED\n' >>src/a.ts
rm -f "$T/stdin"
bash "$REVIEW" defender "$T/brief.md" "$T/findings.md" >/dev/null 2>&1
has "$T/stdin" "## src/a.ts (lines 60-140)"
hasnt "$T/stdin" "UNCOMMITTED"
git checkout -q src/a.ts
# Cited code past the cap is cut with a notice.
rm -f "$T/stdin"
OBJECTION_EXCERPT_MAX=10 bash "$REVIEW" defender "$T/brief.md" "$T/findings.md" >/dev/null 2>&1
has "$T/stdin" "TRUNCATED: the cited code"
# The accuser runs outside a git repository (it needs none).
rm -f "$T/stdin"
(cd "$T" && bash "$REVIEW" accuser "$T/brief.md" >/dev/null 2>&1) || { echo "FAIL: accuser needs a git repository"; failures=$((failures + 1)); }
has "$T/stdin" "the diff"
# A failing or hung claude: exit 1, and whatever came back is shown.
cat >"$T/claude-fail" <<'EOF'
#!/bin/bash
cat >/dev/null
echo "PARTIAL ANSWER"
echo "auth error" >&2
exit 7
EOF
chmod +x "$T/claude-fail"
OBJECTION_CLAUDE="$T/claude-fail" bash "$REVIEW" accuser "$T/brief.md" >/dev/null 2>"$T/err"
[ $? = 1 ] || { echo "FAIL: a failing claude did not exit 1"; failures=$((failures + 1)); }
has "$T/err" "PARTIAL ANSWER"
has "$T/err" "auth error"
printf '#!/bin/bash\nsleep 30\n' >"$T/claude-hang" && chmod +x "$T/claude-hang"
start=$(date +%s)
OBJECTION_TIMEOUT=2 OBJECTION_CLAUDE="$T/claude-hang" bash "$REVIEW" accuser "$T/brief.md" >/dev/null 2>&1
rc=$?
[ "$rc" = 1 ] && [ $(( $(date +%s) - start )) -lt 15 ] || { echo "FAIL: a hung claude was not stopped (rc=$rc)"; failures=$((failures + 1)); }

# Refusals: unknown role, missing files, no claude CLI (exit 3).
bash "$REVIEW" judge "$T/brief.md" >/dev/null 2>&1 && { echo "FAIL: unknown role accepted"; failures=$((failures + 1)); }
bash "$REVIEW" defender "$T/brief.md" >/dev/null 2>&1 && { echo "FAIL: defender without findings accepted"; failures=$((failures + 1)); }
OBJECTION_CLAUDE=/nonexistent/claude bash "$REVIEW" accuser "$T/brief.md" >/dev/null 2>&1
[ $? = 3 ] || { echo "FAIL: missing claude did not exit 3"; failures=$((failures + 1)); }

if [ "$failures" = 0 ]; then echo "review: all cases passed"; else echo "review: $failures failure(s)"; exit 1; fi
