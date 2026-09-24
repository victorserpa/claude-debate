# Working on objection

Instructions for any AI agent (and human) changing this repository.

## Workflow: mandatory

`main` only changes through pull requests (a ruleset blocks direct
pushes, force pushes and deletion). Every change:

1. has an issue; open it first if needed;
2. lives on a branch `<type>/<issue>-<slug>` from `main`;
3. goes through `/objection` on this repository itself (`.objection.json`),
   and the stored record is pasted into the PR body;
4. opens a PR whose body says `Closes #<issue>` and whose title follows
   the commit rules (squash merge uses it as the commit message);
5. merges by squash once `test`, `commits`, `issue-link` and `record`
   are green.

The `v*` tags are protected. Moving `v1` is a release decision for the
maintainer, never a side effect of a PR.

## Commits: mandatory

- **Conventional Commits, in English**: `type(scope)!: description`, with
  `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`, `perf`,
  `build`, `style` or `revert`. Subject in plain English, no accents.
- **Never add a `Co-Authored-By` trailer**, for any tool or person.
- Enforced locally by `.githooks/commit-msg` (run
  `git config core.hooksPath .githooks` once per clone) and in CI for
  every commit of a PR, both through `scripts/check-commit-msg.sh`.

## Layout

| path | what |
|---|---|
| `skills/objection/` | the skill, self-contained: `SKILL.md`, `roles/`, `stamp.sh`, `gate/`, `templates/` |
| `skills/objection/precedents.mjs` | keeps `.objection/precedents.md` (confirmed defects, capped) |
| `skills/objection/gate/core.mjs` | the gate logic, tool-neutral |
| `skills/objection/gate/hook.mjs` | pre-tool hook adapter (Claude Code, Codex, Gemini CLI, Cursor) |
| `skills/objection/gate/check-pr.mjs` | the GitHub check (`action.yml`) |
| `agents/` | Claude Code subagents; body must equal `skills/objection/roles/` |
| `.claude-plugin/`, `hooks/hooks.json` | Claude Code plugin and marketplace |
| `test/` | regression cases |

## Before committing

```bash
bash test/gate.test.sh
bash test/check-pr.test.sh
bash test/roles-in-sync.test.sh
bash test/precedents.test.sh
claude plugin validate .
```

- Changing the gate, a check or a validator? Follow "When the diff is a
  gate, check or validator" in `skills/objection/SKILL.md`: threat model
  first (the gate stops forgetting, not deliberate disguise), severity by
  that model, and every new test case with a **negative control** (it
  fails on the previous version) and its **innocent look-alike** (which
  must keep passing).
- Every gap found in the gate becomes a case in `test/gate.test.sh`
  before the fix.
- Changing a role? Change `skills/objection/roles/<role>.md` and the body
  of `agents/<role>.md` together.
- Host formats (hook input and output for Codex, Gemini CLI, Cursor,
  Copilot) come from the hosts' official docs. Do not describe a format
  in code or README that was not checked against them; say "unverified"
  instead.
- Do not make claims about other projects (Ruflo, etc.) that were not
  checked against their source.
