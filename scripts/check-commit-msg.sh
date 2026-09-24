#!/bin/bash
# Commit message rules for this repository, shared by .githooks/commit-msg
# (local) and CI (the PR title and every commit of a PR):
#   - no Co-Authored-By trailer, from anyone, ever
#   - Conventional Commits subject: type(scope)!: description
#   - English: the subject must be plain ASCII
# Usage: check-commit-msg.sh [--merge] <file-with-message>
#   --merge: the message belongs to a real merge commit (the local hook
#   passes it while a merge is in progress), so git's own "Merge ..."
#   subject is accepted. CI skips merge commits by parent count instead,
#   never by subject: a normal commit titled "Merge x" gets every rule.
set -u
merge=no
[ "${1:-}" = "--merge" ] && { merge=yes; shift; }
msg_file="${1:?usage: check-commit-msg.sh [--merge] <message-file>}"
subject=$(grep -v '^#' "$msg_file" | head -1)

fail() { echo "commit message rejected: $1" >&2; echo "  subject: $subject" >&2; exit 1; }

if grep -qi '^[[:space:]]*co-authored-by:' "$msg_file"; then
  fail "Co-Authored-By trailers are not allowed in this repository."
fi
if [ "$merge" = yes ]; then
  case "$subject" in "Merge "*) exit 0 ;; esac
fi
printf '%s' "$subject" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].*' ||
  fail "use Conventional Commits: type(scope)!: description (feat, fix, docs, refactor, test, ci, chore...)."
if printf '%s' "$subject" | LC_ALL=C grep -q '[^ -~]'; then
  fail "write the subject in English, plain ASCII (no accented characters)."
fi
exit 0
