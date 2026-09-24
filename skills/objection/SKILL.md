---
name: objection
description: Adversarial review before opening or merging a pull request. Accusers review the diff, a defender tries to refute each finding with evidence from the code, and the main session judges and stores a record for the exact commit. With a gate installed, PR create, ready and merge are blocked until the record is APPROVED. Use when a branch is ready for a PR, when the gate blocks, or with "init" to opt a repository in.
license: MIT
---

# /objection

Whoever wrote the code does not approve the code. The debate puts
different roles in opposition: the accusation looks for defects, the
defense tries to refute each accusation with evidence, and the judge
decides. Only what survives the defense becomes a fix.

**Every PR, whatever its size.** Do not route around the gate (`gh api`,
a GitHub MCP tool, `curl` with a token, asking the human to run it for
you without saying the debate did not run). If it blocked, run the
debate.

Everything this skill needs sits next to this file:

| file | what |
|---|---|
| `roles/accuser.md` | the prosecution's instructions |
| `roles/defender.md` | the defense's instructions |
| `stamp.sh` | validates a record and stores it for the current commit |
| `pr-body.sh` | puts the stored record into the PR body (`--update` for an open PR) |
| `init.sh` | opts a repository in without questions (`--advisory` to try it without blocking) |
| `brief.sh` | builds the one context file every reviewer of a round reads |
| `review.sh` | runs a reviewer as an isolated `claude -p` process (2-12k tokens) |
| `gate/hook.mjs` | local gate for Claude Code, Codex, Gemini CLI and Cursor |
| `gate/check-pr.mjs` | the same gate as a GitHub check, for any tool or human |

Below, "this skill's directory" means the directory containing this file.

## init: opting a repository in

No `.objection.json` (or `.claude/objection.json`) at the repository root,
or the user asked for `init`: read `reference/init.md` next to this file
and follow it. It creates the config (bases, verify, reviewers,
invariants, budget) and installs a gate. Nothing else in this file is
needed until then.

## 0. Before the debate: the cheap proof

A debate is argument; a test is proof. Do not spend review effort on
code that does not pass.

1. Everything committed. The record is for one SHA, and anything outside
   the commit was not debated.
2. Base: the branch the PR targets, from `bases`. `git fetch origin <base>`.
3. Run every command in `verify`, **as defined on the base branch**, not
   on the branch under review: a change can rewrite its own `verify` into
   anything. Read it with `git show origin/<base>:.objection.json` (or
   `:.claude/objection.json`, whichever the repository uses). If the base
   has no config yet (the opt-in PR itself), or the branch changes
   `verify`, show the commands to the human and run them only with their
   go-ahead. Red: fix it first.
4. **Diff touching only `*.md` or `docs/`** (never agent prompts, skills
   or instructions: `agents/`, `skills/`, `.claude/`, `.cursor/`,
   `.codex/`, `.gemini/`, `.github/`, `.agents/`, `AGENTS.md`, `CLAUDE.md`,
   `GEMINI.md`, `.objection.json`, `.objection/`):
   skip steps 1 to 3. The record says "documentation only", without the
   debate sections, and goes straight to the stamp.

## Token budget

The debate must cost less than the rework it prevents. A reviewer costs
its start-up plus what it reads. `review.sh` makes the start-up small
(no tools, no project instructions); a subagent pays your whole session's
prompt, tools and CLAUDE.md again. Either way, the number of reviewers
multiplies the cost, and the brief keeps the reading small.

**Models.** The reviewers run on sonnet at effort medium; opus where an
invariant or `strongPaths` matches, or under `thorough` (`models` and
`strongPaths` in the config; `models.strongEffort` sets the strong tier's
effort apart; the defender runs on `models.defender`, default sonnet;
later rounds run the accuser at `models.laterEffort`, default low).
`debate.sh` applies this; `OBJECTION_MODEL` overrides the accusers'
model, `OBJECTION_DEFENDER_MODEL` the defender's, and `OBJECTION_EFFORT`
every effort. A `reviewers` entry whose `agent` is `gemini` or `codex`
runs through that CLI instead: a second model family. Without the `claude` CLI, `review.sh`
runs the roles through the `codex` CLI when that is installed.

**One brief per round.** Run `bash <this skill's directory>/brief.sh
origin/<base> "<goal in one sentence>" "<scope, if the task states one>"`.
It writes one file with the review diff (noise filtered, 5 lines of
context), the changed files, the invariants, reviewer focus and
precedents that cover them, and the reading rule, and prints its path.
Give each accuser that path, its role file and the rules of step 1; the
defender gets that path, its role file and the numbered findings (step
2). Nothing else: no pasted files, no prior rounds, no reasoning of yours. Roles open at most 5 other files, each for a
named suspicion. For the size, `brief.sh` prints the diff's
`--shortstat` in the brief.

**The budget** (`budget` in `.objection.json`; **`lean` when absent**):

| | lean (default) | standard | thorough |
|---|---|---|---|
| accusers per round | one: the generic accuser, with every matching `reviewers` focus and invariant folded into its prompt | generic + each matching `reviewers` entry | same as standard |
| defender | only for BLOCKER or HIGH findings | once, if any finding is MEDIUM or above | sees LOW too |
| later rounds | only when the fix touches a gate, check or validator, or exceeds 40 changed lines; otherwise the judge runs `verify`, and a fix for a BLOCKER or HIGH comes with a test that fails before the fix and passes after (negative control) | on every fix, fix diff only | on every fix |
| max rounds | 2 | 3 | 3 |

Whatever the budget: docs-only diffs get no reviewers (step 0.4); no
MEDIUM-or-above finding means no defense; roles answer in their fixed
table; a diff over 800 lines is reported to the user with a suggestion
to split the PR before anything is spent.

## 1. Accusation

The cast comes from the budget above. With `lean` (the default) it is one
generic accuser (`roles/accuser.md`) whose prompt also carries the
`focus` of every `reviewers` entry whose `paths` match; `standard` and
`thorough` run those reviewers as accusers of their own.

**The whole round in one command, when the `claude` CLI is available:**
`bash <this skill's directory>/debate.sh "<goal>" "<scope>"` (the base
is the config's `defaultBase`; name another first: `debate.sh <base>
"<goal>"`; later rounds: `debate.sh --since <previous-round-sha> "<goal>"`).
It builds the brief, runs the accusers (under `standard` and `thorough`,
each matching `reviewers` entry too, with its focus) and, for the
findings the budget sends, the defender, all isolated (option 1 below),
and writes a draft record whose Judge and Open sections say
`TODO(judge)`. It prints a short summary and the draft's path: read the
draft, judge (step 3), replace every TODO line (`stamp.sh` refuses a
record that still has one), stamp. Findings are numbered once, in the
Accusation; the defender and your rulings use the same numbers, and
every number needs a ruling line in Judge that starts with it ("3.",
"1, 2 and 5:", "4-6." or a "| 3 |" table row): stamp.sh and the CI check
refuse a record that leaves one out. Under
`lean`, a diff of at most `smallDiff` changed lines (default 20) that no
invariant or `strongPaths` touches runs no reviewer: the draft comes
pre-filled as APPROVED with one `TODO(judge)` line; read the diff and
replace that line with one sentence of your own on what it does and why
it is safe (otherwise write the findings and fix the counts and verdict);
verify still runs. Exit 3 means no `claude` CLI: run the
roles one by one as below. `usage.sh` shows what each branch's
reviewers cost.

**How to run a role**, in order of preference:

1. **Isolated process, when the `claude` CLI is available** (any tool can
   call it):
   `bash <this skill's directory>/review.sh accuser <brief>` and, for the
   defense, `review.sh defender <brief> <findings.md>` (the findings the
   budget sends it, as the accuser's table). Each runs with no tools, no
   MCP servers, no skills and no project CLAUDE.md, only its role and the
   brief (the defender also gets the code its findings cite): measured at
   2-12k input tokens per reviewer, against 87-134k for a subagent. Save
   each answer to a file; it prints the tokens used. Exit 3 (no `claude`
   CLI) or 2 (no `node` or `perl`): go to the next option. Your user-level
   `~/.claude/CLAUDE.md` still loads, so keep it short.
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

Give each accuser the brief's path (see "Token budget"). The brief
already holds the goal and, when the task says what may change (an
issue's scope, "only the feedback layer"), that scope: changes outside it
are findings of kind SCOPE, even when they are correct. It also holds
the matching **invariants** (a violation is a BLOCKER of kind INVARIANT;
the record lists which invariants were checked), the **reviewer focus**
of every matching `reviewers` entry (under `lean` the one accuser covers
them all) and the **precedents**, the defects this repository already
shipped in those files. An invariant whose `paths` is not a valid regex
is flagged in the brief: fix the config, it was not checked.

**Rules that go into every accuser's prompt:**

- The finding format: severity (BLOCKER, HIGH, MEDIUM, LOW) | kind (BUG,
  REGRESSION, SCOPE, INVARIANT) | file:line | defect | evidence (read,
  static, test, new-test, reproduced) | proof path. The plugin's accuser has
  it in its role file; say it to every other reviewer.
- **No quota.** Never ask for "at least three problems": a quota makes
  the reviewer invent the third, and an invented finding is rework. Ask
  what it could not evaluate.
- Style and formatting are out.

## 2. Defense

The defender (`roles/defender.md`) receives the findings the budget
sends it (`lean`: BLOCKER and HIGH; `standard`: MEDIUM too; `thorough`:
all), numbered, with the proof each accuser gave and the brief's path.
The rest goes straight to the record, without defense. Same preference
order for how to run it.

## 3. Judge: this session, never a smaller model

A wrong diagnosis returns a plausible explanation and nobody notices. So
the main session judges, with these rules, not with opinion:

| defense said | judge does |
|---|---|
| REFUTED | opens the citation and checks it covers **exactly** the accused case. It does not: UPHELD. |
| UPHELD | fixes it, or moves it to "Open" with a reason. |
| CANNOT VERIFY | BLOCKER or HIGH: treated as UPHELD. **Tie-break by test:** write the test the accuser said would fail. Fails: UPHELD. Passes: REFUTED only with a negative control (below), and the test stays in the repository. |

**The judge never refutes a finding alone.** Refuting requires the
defender's citation, checked, or a tie-break test with a **negative
control**: the test is shown able to fail on the accused path: it fails
when the defect is put back (revert the fix, or inject it in a scratch
copy) or, for missing behavior, when the path it claims to cover is
broken on purpose. A test never shown able to fail proves nothing, and
the finding stays UPHELD. The judge wrote the code: that is the bias the
debate exists to cut.

**Evidence decides disputes, not eloquence.** When accuser and defender
disagree on a BLOCKER or HIGH and neither side has more than `read`, the
finding is not settled: raise the evidence (a test with a negative
control, or run the path) before deciding. Uncertainty never becomes
approval: an unsettled BLOCKER or HIGH stays UPHELD.

## 4. Rounds

Fixed something: commit (a `fix:` in the same branch, before the PR, is
the cheap fix). The budget decides whether another round runs (`lean`:
only when the fix touches a gate, check or validator, or exceeds 40
changed lines; otherwise run `verify`, and a fix for a BLOCKER or HIGH
comes with a test that fails before the fix and passes after; record
both). When it runs, it covers **only the fix diff**: build
the brief with the previous round's commit as the diff base and the PR's
base as the config base (`brief.sh <previous-round-sha> "<goal>" "<scope>"
origin/<base>`), so the rules still come from the base branch, and tell
the accuser to hunt
**regressions from the fix** first: in practice they are the most common
round-2 finding.

After the last round the budget allows (2 for `lean`, 3 otherwise),
what is still open goes into "Open" with its severity: MEDIUM and LOW can
ship with the record (tracked in an issue), BLOCKER and HIGH cannot, and
the human decides what happens to them.

## When the diff is a gate, check or validator

If the change blocks or allows something (this skill's gate, a CI check,
a permission rule, an input validator), read `reference/gate-changes.md`
before the accusation: threat model first, negative controls, both sides
every round. Without it, that kind of debate does not converge.

## 5. Record and stamp

Write the record to a scratch file, with these exact sections:

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

`OPEN:` is the judge's count of BLOCKER and HIGH findings left in "Open".
It is the authority: nothing parses the free text for severities except
as a cross-check against a count that contradicts its own list. APPROVED
only with `OPEN: BLOCKER=0 HIGH=0`.

**Update the precedents** (unless `precedents` is `false`), before
stamping. Only findings the judge kept (UPHELD, fixed or left open) of
severity MEDIUM or above; refuted findings never become precedent.

1. `node <this skill's directory>/precedents.mjs list`
2. For each kept finding: if a listed line describes the same kind of
   defect, `precedents.mjs bump <n> --sha <sha7>`. Otherwise
   `precedents.mjs add --area <prefix> --pattern "<sentence>" --sha <sha7>`,
   where `<prefix>` is the narrowest directory covering where it happened
   (`*` if it is not about a place) and `<sentence>` names the **kind** of
   defect, not the instance: "temp dir not cleaned when the job fails
   before finally", not "line 42 of ingest.ts". No code, no secrets, no
   names of people.
3. Commit `.objection/precedents.md` on the branch
   (`chore(objection): update precedents`). The script caps the file at 30
   lines, so it stays cheap to read.

Then stamp the resulting HEAD:

```bash
bash <this skill's directory>/stamp.sh <record.md> [origin/<base>]
```

The base defaults to `origin/<defaultBase>`. It refuses a record without
the sections, with a `TODO(judge)` line left, with a dirty tree, with a
base outside `bases`, or APPROVED with a serious finding open. It stores the
record with a stamp (`<!-- objection: sha=... base=... -->`) on the first
line and prints where. Then push the debated commit and put the stored
record, stamp line included, into the PR body: `bash <this skill's
directory>/pr-body.sh` writes the body and prints its path (`gh pr create
--body-file <path>`; `OBJECTION_SUMMARY` sets the text above the record),
and `pr-body.sh --update` replaces the record in an open PR's body,
keeping the description. The GitHub check reads it from there, and
reviewers see what was rejected and what was fixed because of it. A
later push changes the SHA: debate the new commits (`debate.sh --since`)
and run `pr-body.sh --update`.

With `"enforce": false` in the config (advisory mode), the hook lets the
PR through and says what it would have blocked: run the debate anyway,
it is the point.

## Cost

Per PR, not per commit. A small PR gets one accuser and usually no
defender; a normal one gets one to three accusers and one defender; the
gate hook itself runs outside the model and costs no tokens. When a
round would be expensive (over 800 changed lines), say so before
spending, and prefer splitting the PR.
