# Running the roles without debate.sh

Read this when `debate.sh` exits 3 (no `claude` CLI) or you run the
roles one by one on purpose.

## Build the brief

`bash <this skill's directory>/brief.sh origin/<base> "<goal in one
sentence>" "<scope, if the task states one>"` writes one file and prints
its path: the review diff (noise filtered, 3 lines of context, each line
numbered by the new file), the changed files, the invariants, reviewer
focus and precedents that cover them, the definitions the added lines
call, and the reading rule. For a later round, the previous round's
commit is the diff base and the PR's base the config base:
`brief.sh <previous-round-sha> "<goal>" "<scope>" origin/<base>`.

Give each accuser that path and its role file; the defender gets that
path, its role file and the numbered findings. Nothing else: no pasted
files, no prior rounds, no reasoning of yours.

## How to run a role, in order of preference

1. **Isolated process, when the `claude` CLI is available** (any tool can
   call it): `bash <this skill's directory>/review.sh accuser <brief>`
   and, for the defense, `review.sh defender <brief> <findings.md>` (the
   findings the budget sends it, as the accuser's table, numbered). Each
   runs with no tools, no MCP servers, no skills and no project
   CLAUDE.md, only its role and the brief (the defender also gets the
   code its findings cite): 2-12k input tokens per reviewer, against
   87-134k for a subagent. Without the `claude` CLI it runs the roles
   through `codex` when that is installed (`OBJECTION_RUNNER=gemini` for
   the Gemini CLI). Exit 3 (no CLI) or 2 (no `node` or `perl`): go to the
   next option.
2. **Subagents**, if your tool has them and not the CLI. In Claude Code,
   the plugin ships them as `objection:accuser` and `objection:defender`;
   elsewhere, pass the role file's content as the subagent's
   instructions. They inherit your session's prompt, tools and project
   instructions, so they cost several times more.
3. **Sequentially in a fresh context** if there are neither: a new chat or
   session per role, given the role file, the brief, and nothing of your
   own reasoning. The point is that the accuser has not seen why you wrote
   the code the way you did.
4. **Last resort, in this same session:** reread the role file and adopt
   it fully, then write the findings before looking at your own code
   again. Say in the record that the roles ran in one context; it is a
   weaker debate and the reader should know.

## Rules that go into every accuser's prompt

The plugin's accuser has them in its role file; say them to any other
reviewer:

- The finding format: severity (BLOCKER, HIGH, MEDIUM, LOW) | kind (BUG,
  REGRESSION, SCOPE, INVARIANT) | file:line | defect | evidence (read,
  static, test, new-test, reproduced) | proof path.
- **No quota.** Never ask for "at least three problems": a quota makes
  the reviewer invent the third, and an invented finding is rework. Ask
  what it could not evaluate.
- Style and formatting are out.
- Changes outside the stated scope are findings of kind SCOPE, even when
  correct; an invariant violation is a BLOCKER of kind INVARIANT.

## The defense

The defender (`roles/defender.md`) receives the findings the budget sends
it (`lean`: BLOCKER and HIGH; `standard`: MEDIUM too; `thorough`: all),
numbered, with the proof each accuser gave and the brief's path. The rest
goes straight to the record, without defense.

## The record, written by hand

Number the findings once, in the Accusation; the defender and the rulings
use the same numbers. The sections, exactly:

```markdown
# Debate: <branch> @ <sha7>

## Accusation
<one finding per line: #, severity, kind, accuser, file:line, evidence, sentence>
<invariants checked, if any: one line each>

## Defense
<#, defender verdict, evidence>

## Judge
<#, final decision, and what was fixed (commit) or why not>

## Open
<what was left out, with severity and reason; "nothing" if nothing>

OPEN: BLOCKER=0 HIGH=0
VERDICT: APPROVED
```
