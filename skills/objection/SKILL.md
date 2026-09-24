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

The debate must cost less than the rework it prevents. Every run obeys
these, whatever the budget:

- **The review diff**, the only code a role gets up front, excludes noise
  and keeps little context. With `X` standing for
  `-- . ':!*.lock' ':!*lock.json' ':!*lock.yaml' ':!*.snap' ':!*.min.*' ':!dist/**' ':!build/**' ':!**/generated/**'`:
  - size first, never with `-U` (it would print the whole patch):
    `git diff --shortstat origin/<base>...HEAD X`
  - then the diff itself: `git diff -U5 origin/<base>...HEAD X`
- **Size decides the cast** (insertions plus deletions from `--shortstat`):

  | review diff | accusers | defender |
  |---|---|---|
  | docs only | none (step 0.4) | none |
  | up to 80 lines, no `reviewers` match | generic accuser only | only if a finding is BLOCKER or HIGH |
  | normal | generic + matching `reviewers` | once, if any finding is MEDIUM or above |
  | over 800 lines | same, but tell the user the size and suggest splitting the PR before spending | same |

- **`budget: lean`**: one accuser total (matching `reviewers`' `focus`
  lines are folded into the generic accuser's prompt), defender only for
  BLOCKER or HIGH. **`budget: thorough`**: every matching reviewer, and
  the defender sees LOW findings too.
- **No findings, no defense.** Zero MEDIUM-or-above findings skips step 2.
- **Roles report in their fixed table format** (see the role files) and
  read beyond the diff only to chase a specific suspicion.
- **Later rounds** debate only the fix diff, with only the accusers of
  the area touched, and the defender sees only the new findings.
- **Nothing else is loaded.** Do not paste whole files, prior rounds or
  your own reasoning into a role's prompt: diff, goal in one sentence,
  and for the defender the numbered findings.

## 1. Accusation

The cast comes from "Token budget" above. By default:

- the generic accuser (`roles/accuser.md`) on the review diff;
- each `reviewers` entry whose `paths` matches a changed file, with its
  `focus`.

**How to run a role**, in order of preference:

1. **Subagents, in parallel**, if your tool has them. In Claude Code, the
   plugin ships them as `objection:accuser` and `objection:defender`.
   Elsewhere, pass the role file's content as the subagent's instructions.
2. **Sequentially in a fresh context** if there are no subagents: a new
   chat or session per role, given the role file, the diff, and nothing
   of your own reasoning. The point is that the accuser has not seen why
   you wrote the code the way you did.
3. **Last resort, in this same session:** reread the role file and adopt
   it fully, then write the findings before looking at your own code
   again. Say in the record that the roles ran in one context; it is a
   weaker debate and the reader should know.

Give each accuser the review diff restricted to its files, the goal of
the change in one sentence and, when the task says what may change (an
issue's scope, "only the feedback layer"), that scope. Changes outside it
are findings of kind SCOPE, even when they are correct.

**Invariants.** Each `invariants` entry whose `paths` matches a changed
file goes into the accuser's prompt as a rule that must hold. A violation
is a BLOCKER of kind INVARIANT; the record lists which invariants were
checked.

**Precedents.** Unless `precedents` is `false`, run
`node <this skill's directory>/precedents.mjs match <changed files>` and
put its output (at most 10 lines) in the accuser's prompt as "Defects
this repository has already shipped: check these first." Nothing printed,
nothing added.

**Rules that go into every accuser's prompt:**

- Each finding has a severity (BLOCKER, HIGH, MEDIUM, LOW), a kind (BUG,
  REGRESSION, SCOPE, INVARIANT), `file:line`, **how to prove it** (the
  test that would fail or the execution path that reaches the defect),
  and the **evidence** it rests on, weakest to strongest: `read` (reading
  code), `static` (a checker or type error), `test` (an existing test
  fails), `new-test` (a test written for it fails), `reproduced` (run and
  observed).
- **No quota.** Never ask for "at least three problems": a quota makes
  the reviewer invent the third, and an invented finding is rework. Ask
  what it could not evaluate.
- Style and formatting are out.

## 2. Defense

The defender (`roles/defender.md`) receives the findings the budget
sends it (by default all BLOCKER, HIGH and MEDIUM), numbered, with the
proof each accuser gave, and not the diff. LOW goes straight to the
record, without defense. Same preference order for how to run it.

## 3. Judge: this session, never a smaller model

A wrong diagnosis returns a plausible explanation and nobody notices. So
the main session judges, with these rules, not with opinion:

| defense said | judge does |
|---|---|
| REFUTED | opens the citation and checks it covers **exactly** the accused case. It does not: UPHELD. |
| UPHELD | fixes it, or moves it to "Open" with a reason. |
| CANNOT VERIFY | BLOCKER or HIGH: treated as UPHELD. **Tie-break by test:** write the test the accuser said would fail. Fails: UPHELD. Passes: REFUTED, and the test stays in the repository. |

**The judge never refutes a finding alone.** Refuting requires the
defender's citation, checked. The judge wrote the code, and that is the
bias the debate exists to cut.

**Evidence decides disputes, not eloquence.** When accuser and defender
disagree on a BLOCKER or HIGH and neither side has more than `read`, the
finding is not settled: raise the evidence (write the test, run the
path) before deciding. Uncertainty never becomes approval: an unsettled
BLOCKER or HIGH stays UPHELD.

## 4. Rounds

Fixed something: commit (a `fix:` in the same branch, before the PR, is
the cheap fix) and redo steps 0 to 3 **only on the fix diff** (`git diff
<previous-round-sha>..HEAD`), with the accusers for that area. Tell the
accuser to hunt **regressions from the fix** first: in practice they are
the most common round-2 finding.

At most three rounds. What is still open after the third goes into
"Open" with its severity: MEDIUM and LOW can ship with the record
(tracked in an issue), BLOCKER and HIGH cannot, and the human decides
what happens to them.

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
bash <this skill's directory>/stamp.sh <record.md> origin/<base>
```

It refuses a record without the sections, with a dirty tree, with a base
outside `bases`, or APPROVED with a serious finding open. It stores the
record with a stamp (`<!-- objection: sha=... base=... -->`) on the first
line and prints where. Then push the debated commit and **paste the
stored record, stamp line included, into the PR body**: the GitHub check
reads it from there, and reviewers see what was rejected and what was
fixed because of it. A later push changes the SHA: debate the new
commits and replace the record in the body.

## Cost

Per PR, not per commit. A small PR gets one accuser and usually no
defender; a normal one gets one to three accusers and one defender; the
gate hook itself runs outside the model and costs no tokens. When a
round would be expensive (over 800 changed lines), say so before
spending, and prefer splitting the PR.
