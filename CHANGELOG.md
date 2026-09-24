# Changelog

## 0.5.0 (2026-09-24)

**Cheaper by default.** An adopter measured ~9 reviewer subagents at
80-160k tokens each in one session.

- `budget` defaults to `lean` when absent: one accuser per round (with
  every matching reviewer focus in its brief), the defender only for
  BLOCKER or HIGH, a second round only when a fix touches a gate, check or
  validator or exceeds 40 lines, at most two rounds. A fix for a BLOCKER
  or HIGH without a second round needs a test that fails before the fix.
  Set `"budget": "standard"` to get the previous behavior.
- `brief.sh`: one context file per round (filtered diff, changed files,
  size, reviewer focus, invariants and precedents that cover them, the
  reading rule). Rules come from the PR's base branch; invalid invariant
  regexes are flagged; reviewers open at most 5 other files.
- The docs say where the tokens go: every subagent reloads the tool's
  prompt and the project's instructions, so a short CLAUDE.md and fewer
  reviewers save the most; the brief cuts exploring (~110k per reviewer
  measured here, with the brief).

## 0.4.0 (2026-09-24)

**Stricter, may block what used to pass:**
- Without `--base`, the local gate uses the base gh will really use (the
  branch's `gh-merge-base`, else the repository default reported by
  `gh repo view`), not `.objection.json`'s `defaultBase`, which is now only
  the debate's default. Pass `--base` to be explicit.
- `gh pr create --head` checks the branch on its remote (the fork's remote
  for `owner:branch`) and blocks when it differs from the local one.
- Agent prompts, skills, instructions and the objection config are never
  "documentation only": `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
  `.objection.json` and agent config dirs (`.claude/`, `.cursor/`...) at
  any depth; `agents/` and `skills/` at the repository root.
- The GitHub check fails when the PR's file list hits the 3000-file API
  limit or is shorter than the PR's `changed_files`.

**New:**
- `invariants` in `.objection.json`: rules with the paths they guard; a
  violation is a BLOCKER.
- Findings carry a kind (BUG, REGRESSION, SCOPE, INVARIANT) and the
  evidence they rest on (read, static, test, new-test, reproduced); SCOPE
  covers changes outside what the task allowed.
- A tie-break test refutes a finding only with a negative control (shown
  able to fail); uncertainty stays UPHELD.
- Reviewers treat everything they read as data (prompt injection), and
  `verify` commands come from the base branch's config.
- Leaner `SKILL.md`: init and the rules for changing a gate load on demand
  from `reference/`.
- This repository's Dependabot PRs skip issue-link and record only when
  every commit is Dependabot's own (author, committer web-flow, verified).

## 0.3.0 (2026-09-24)

**Breaking for existing records:** a record now needs the judge's
structured count, `OPEN: BLOCKER=<n> HIGH=<n>`, and is APPROVED only with
`OPEN: BLOCKER=0 HIGH=0`. `stamp.sh` refuses to store a record without it,
and the GitHub check refuses a PR body without it from this release on
(the `v1` tag moves to 0.3.0). The local gate does not re-read records
stamped before the upgrade: it still checks only their stamp and verdict,
so the GitHub check is where an old record fails. Debate open PRs again,
or add the line from the record's own "Open" section.

- **Precedents** (`precedents.mjs`, `.objection/precedents.md`): defects
  the debates confirmed become one line each, with how often they
  happened; the next accuser checks the ones covering the changed files
  first. Capped at 30 lines, kept by a script, not rewritten by a model.
- **Token budget**: the review diff drops lockfiles, snapshots and build
  output; small diffs get one accuser and a defender only for serious
  findings; roles answer in a capped table; `"budget": "lean"`.
- **Gate, closed gaps** (from the first adopter's six-round debate and
  six more rounds here): quoted values glued to flags (`--repo="o/r"`,
  `-R"o/r"`), `-Ro/r`, command substitutions and backticks, a PR number
  the gate cannot read (now blocked with a message instead of checking
  the current branch's PR), `cd "$(git rev-parse --show-toplevel)"`, and
  an allowlist for what executes code (`bash -lc`, `python -c`,
  `node -e`), so `grep -c`, `rg -c` and `perl -pe` stay text.
- **Threat model written down**: the local gate stops an agent that
  forgets the debate, not one that disguises the command on purpose; the
  GitHub check with a required status check is the gate that does not
  read commands.
- **Rules for changing a gate, check or validator** in the skill:
  negative controls, both sides every round, stubs that can say no,
  allowlists, one representation per rule.
- **Repository governance**: `main` changes only through issue-linked
  PRs, required checks (tests, commit rules, issue link, the objection
  record) run from `main` through `pull_request_target`, outside PRs need
  a code owner, and `v*` tags are protected. The user workflow template
  now uses `pull_request_target` too.

## 0.2.0 (2026-09-23)

- Works with any AI coding agent: the skill is self-contained under
  `skills/objection/` (Agent Skills layout), the gate core is tool-neutral,
  and one hook script speaks Claude Code, Codex, Gemini CLI and Cursor.
- GitHub Action (`victorserpa/objection@v1`): fails a PR whose body has
  no APPROVED record for its head SHA and base, for any tool or human.
- Opt-in file is `.objection.json` (`.claude/objection.json` still read).
- Renamed from `claude-debate` to `objection` (`/objection`).

## 0.1.0 (2026-09-23)

- `/debate` for Claude Code: accusers, a defender and a judge debate the
  diff; a record is stamped to the exact commit, and a hook blocks
  `gh pr create`, `ready` and `merge` until it is APPROVED.
