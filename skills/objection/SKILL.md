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

If `.objection.json` does not exist at the repository root and the user
asked for `init` (or this is the first debate), create it. Ask the user
only what you cannot read from the repository:

```json
{
  "bases": ["main"],
  "defaultBase": "main",
  "verify": ["npm run typecheck", "npm test"],
  "reviewers": [
    { "paths": "^src/(auth|billing)/", "agent": "security-reviewer", "focus": "the project's security checklist" }
  ]
}
```

- `bases`: every branch a PR may target (e.g. `["develop", "main"]`).
- `defaultBase`: what `gh pr create` uses without `--base`.
- `verify`: the cheap proof that runs before any accuser (step 0).
- `reviewers`: extra accusers by path regex. `agent` names a reviewer the
  project already defines for your tool (subagent, custom agent, or a
  prompt file path); `focus` goes into its prompt. The generic accuser
  always runs on code, so this list can start empty.
- `budget` (optional): `lean`, `standard` (default) or `thorough`. See
  "Token budget".
- `precedents` (optional, default `true`): keep and use the repository's
  precedents (step 1 and step 5). `false` turns them off.

Then install a gate, and tell the user which one you installed:

1. **Local gate for your tool**, so the PR command itself is blocked.
   Copy the matching file from `templates/` next to this file
   (or write it from the snippet below), replacing `<SKILL_DIR>` with this
   skill's directory, relative to the repository root when the skill is
   inside the repository:
   - Claude Code: nothing to do if installed as the plugin (the hook ships
     with it). Otherwise a `PreToolUse` hook on `Bash|mcp__.*` running
     `node <SKILL_DIR>/gate/hook.mjs`.
   - Cursor: `.cursor/hooks.json`, `beforeShellExecution` and
     `beforeMCPExecution` running `node <SKILL_DIR>/gate/hook.mjs --host cursor`.
   - Codex CLI: `.codex/hooks.json`, `PreToolUse` running
     `node <SKILL_DIR>/gate/hook.mjs --host codex` (Codex hooks are
     experimental and must be enabled).
   - Gemini CLI: `.gemini/settings.json`, `BeforeTool` running
     `node <SKILL_DIR>/gate/hook.mjs --host gemini`.
2. **GitHub check**, which works whatever tool (or person) opens the PR:
   `.github/workflows/objection.yml` from `templates/github/objection.yml`
   (it uses `victorserpa/objection@v1`),
   then ask the user to make it a required status check. Recommend it
   always; it is the only gate for tools without hooks.

Commit the files. From then on the debate is enforced in this repository.

## 0. Before the debate: the cheap proof

A debate is argument; a test is proof. Do not spend review effort on
code that does not pass.

1. Everything committed. The record is for one SHA, and anything outside
   the commit was not debated.
2. Base: the branch the PR targets, from `bases`. `git fetch origin <base>`.
3. Run every command in `verify`. Red: fix it first.
4. **Diff touching only `*.md` or `docs/`** (outside agent configuration
   directories like `.claude/`, `.cursor/`, `.codex/`, `.gemini/`, `.github/`):
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

Give each accuser the review diff restricted to its files and the goal
of the change in one sentence.

**Precedents.** Unless `precedents` is `false`, run
`node <this skill's directory>/precedents.mjs match <changed files>` and
put its output (at most 10 lines) in the accuser's prompt as "Defects
this repository has already shipped: check these first." Nothing printed,
nothing added.

**Rules that go into every accuser's prompt:**

- Each finding has a severity (BLOCKER, HIGH, MEDIUM, LOW), `file:line`,
  and **how to prove it**: the test that would fail or the execution path
  that reaches the defect.
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

Changes to anything that blocks or allows (this skill's gate, a CI check,
a permission rule, an input validator) need a written threat model, or
the debate cannot converge: every new way of disguising the input looks
HIGH, and every fix opens the next hole. The first adopter debated this
skill's own gate for six rounds before writing this down.

1. **Write the threat model before the code**, in one sentence at the top
   of the file: what it stops, and what it does not. This skill's gate
   stops *forgetting* (the natural ways of writing a command), not
   *deliberate disguise* (a command assembled from pieces, hidden in an
   alias, a file, a variable or another language); disguise already breaks
   the rule, and the effect-based gate (a required check) covers it.
2. **Severity follows the threat model.** HIGH: a natural form passes, or
   an innocent command gets blocked. LOW: a form that only exists to evade.
3. **Negative control.** Every new test case must fail on the previous
   version (`git show <sha>:<file>` into a scratch directory, or `git stash`
   the fix). A case that passes on both versions guards against regression
   but proves nothing about the fix.
4. **Both sides, every round:** "the natural form is blocked" and "the
   similar innocent command still passes". Half of the regressions in that
   six-round debate were false blocks.
5. **Stubs must be able to say no.** A fake API that returns the same
   answer for every input cannot tell a right parse from a wrong one.
6. **Prefer allowlists** (what executes, what is permitted) over lists of
   what is harmless, and decide once which representation of the input
   each rule reads.

## 5. Record and stamp

Write the record to a scratch file, with these exact sections:

```markdown
# Debate: <branch> @ <sha7>

## Accusation
<one finding per line: #, severity, accuser, file:line, sentence>

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
