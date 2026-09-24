# objection

> **OBJECTION!** Your PR goes on trial before it ships.

Adversarial review for AI coding agents: accusers attack the diff, a
defender refutes them with evidence, a judge rules, and a gate keeps the
PR from being created or merged until the verdict is APPROVED. Works with
Claude Code, Codex, Cursor, Gemini CLI, GitHub Copilot, and anything else
that reads [Agent Skills](https://agentskills.io) or opens pull requests
on GitHub.

When you ask an AI to build something, it plans, writes, checks, and
approves its own work. It is the same mind grading its own exam. This
skill splits that into roles that argue:

```
                 ┌──────────────┐
  your diff ───▶ │  ACCUSATION  │  generic accuser + your specialist reviewers
                 └──────┬───────┘  every finding needs file:line and a proof path
                        ▼
                 ┌──────────────┐
                 │   DEFENSE    │  defender tries to REFUTE each finding with code;
                 └──────┬───────┘  when in doubt, the finding stands
                        ▼
                 ┌──────────────┐
                 │    JUDGE     │  the main session: checks every refutation,
                 └──────┬───────┘  cannot dismiss anything alone, ties go to a test
                        ▼
                 ┌──────────────┐
                 │    RECORD    │  stamped to the exact commit SHA and base,
                 └──────┬───────┘  pasted into the PR body
                        ▼
  PR create / ready / merge  ── blocked until the record says APPROVED
```

Only what survives the defense becomes a fix. The record goes into the PR
body, so reviewers see what was rejected and what was fixed because of it.

## Why

It came from two real projects where, over the last 300 commits, `fix:`
commits outnumbered `feat:` commits almost two to one. The defect shipped
and came back as a fix. Review existed as a rule written in the agent's
instructions, and a written rule stops nothing.

Two design decisions carry most of the value:

- **A defender, not just more reviewers.** Reviewers are rewarded for
  finding things, so they also find things that are not there, and a false
  finding sends someone to "fix" correct code. The defender refutes with
  `file:line` or not at all. The burden of proof is on the defense.
- **A gate, not a suggestion.** The debate is the condition for the PR to
  exist. A new commit after the debate invalidates the record.

**No finding quotas.** Prompts like "find at least three problems" make
the model invent the third one. The accusers are asked what they could
*not* evaluate instead.

## Install

**Claude Code** (skill, subagents and the gate hook in one step):

```
/plugin marketplace add victorserpa/objection
/plugin install objection@objection
```

**Any other agent that reads Agent Skills** (Codex, Cursor, Copilot,
Gemini CLI, Cline, OpenCode, ...), with the
[`skills` CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add victorserpa/objection
```

or copy [`skills/objection/`](skills/objection) into your agent's skills
directory (`.agents/skills/`, `.github/skills/`, `.claude/skills/`...).
The folder is self-contained: instructions, role prompts, stamp script,
gate and templates.

Then, in each repository you want to protect, ask your agent:

```
/objection init
```

It creates `.objection.json` and installs a gate. **Nothing is enforced
in a repository without that file**, so installing the skill never blocks
work anywhere you did not opt in.

```json
{
  "bases": ["develop", "main"],
  "defaultBase": "develop",
  "verify": ["pnpm typecheck", "pnpm test"],
  "reviewers": [
    { "paths": "^apps/api/src/(auth|billing)/", "agent": "security-reviewer", "focus": "the project's security checklist" }
  ]
}
```

| key | meaning |
|---|---|
| `bases` | every branch a PR may target; a record is only valid against the base it was debated on |
| `defaultBase` | the base to debate against by default; gh does not read it, so pass `--base` (the gate checks the base gh will really use) |
| `verify` | cheap proof (types, tests) that must pass before any reviewer runs |
| `reviewers` | your own reviewers, added as accusers when the diff touches `paths`; `agent` can be another tool or model for a second opinion on risky paths |
| `invariants` | rules that must never break, each with the `paths` it guards; a violation is a BLOCKER |
| `budget` | `lean`, `standard` or `thorough`: how many reviewers run per round |

Requirements: `node`, `git`, and the `gh` CLI.

## Gates

Two layers. Use both where you can.

**1. Local hook**: blocks the agent's PR command before it runs.
One script, [`gate/hook.mjs`](skills/objection/gate/hook.mjs), speaks
each host's hook format; templates live in
[`skills/objection/templates/`](skills/objection/templates).

| host | hook | status |
|---|---|---|
| Claude Code | `PreToolUse` (ships with the plugin) | used daily |
| Cursor | `beforeShellExecution` + `beforeMCPExecution` | built from Cursor's docs; input shapes covered by tests, not yet run in Cursor |
| Codex CLI | `PreToolUse` (experimental in Codex, must be enabled) | built from Codex's docs; not yet run in Codex |
| Gemini CLI | `BeforeTool` | built from Gemini CLI's docs; not yet run in Gemini |
| GitHub Copilot | hook format not confirmed | use the GitHub check |

Reports from people running it in those tools are welcome.

**2. GitHub check**: fails the PR unless its body has an APPROVED record
for the current head SHA and base. It does not care which tool (or
person) opened the PR, so it covers every agent, including those without
hooks. Copy [`templates/github/objection.yml`](skills/objection/templates/github/objection.yml)
to `.github/workflows/` and make `record` a required status check in a
ruleset on your default branch:

```yaml
on:
  pull_request_target: # runs from the base branch: a PR cannot edit its own judge
    types: [opened, edited, synchronize, reopened, ready_for_review]
jobs:
  record:
    runs-on: ubuntu-latest
    steps:
      - uses: victorserpa/objection@v1
```

A push changes the head SHA, so the check fails again until the new
commits are debated and the body is updated.

## What the local gate blocks

Without an APPROVED, stamped record for the exact SHA and base:

- `gh pr create` / `new` / `ready` / `merge`, however they are invoked:
  `gh -R x pr …`, `$(…)`, `bash -c`, `xargs`, piped into a shell,
  `\gh`, absolute paths
- `gh pr merge --auto` (it would let in commits pushed after the debate)
- `gh api` writes to `/pulls` or `/pulls/<n>/merge`, and GraphQL PR
  mutations (including multi-line queries and queries read from a file)
- MCP tools that create, update, mark ready, or merge a PR

It does not block reading PRs, commenting, reviewing, or any command that
merely *mentions* those commands (commit messages, `grep`, `echo`,
heredoc bodies).

**Threat model:** the local gate stops an agent that *forgets* the debate,
not one that *disguises* the command on purpose (built from pieces, hidden
in an alias, a file or another language). Disguise already breaks the
rule; the GitHub check with a required status check is the gate that does
not depend on reading commands. See [SECURITY.md](SECURITY.md).

**The gate went through its own debate before release.** Round one found
12 ways around the first (bash) version, including a record ending in
`REJECTED` that quoted `APPROVED` and still passed. Round two, with the
defender, found 10 more. The first adopter then debated its copy for six
rounds, and most findings from round two on were regressions of the
previous fix; what that taught is now part of the skill (threat model
first, negative controls, both sides every round). Every case is in
[`test/gate.test.sh`](test/gate.test.sh).

## What a record looks like

Every finding names its kind (BUG, REGRESSION, SCOPE, INVARIANT) and the
evidence it rests on, from `read` (someone read the code) up to
`reproduced` (someone ran it and saw it). The skill tells the judge to
settle disputes by raising the evidence and to keep an unsettled BLOCKER
or HIGH open. Those are rules for the judge: `stamp.sh` and the GitHub
check verify the stamp, the verdict and the `OPEN:` count, not the
content of each finding. The record is public in the PR so a person can.

```markdown
<!-- objection: sha=4dc01af... base=origin/main -->
# Debate: fix/9-external-review @ 4dc01af

## Accusation
1, HIGH, BUG, accuser, gate/core.mjs:568, reproduced, --head checked a remote hardcoded as origin
2, MEDIUM, BUG, accuser, check-pr.mjs:74, reproduced, nested CLAUDE.md files counted as docs
Invariants checked: none configured

## Defense
1, UPHELD, core.mjs:568 (ls-remote origin), new-test
2, UPHELD, check-pr.mjs:74 (anchored at ^), reproduced

## Judge
1: fixed in 3f72169 (the remote is found, not assumed); the new case fails on the previous commit
2: fixed in 3f72169 (instruction files count at any depth)

## Open
nothing

OPEN: BLOCKER=0 HIGH=0
VERDICT: APPROVED
```

Real ones are in the body of every merged PR in this repository.

## Precedents

After each debate, the defects that survived the defense are distilled
into `.objection/precedents.md`, one line each, with how many times the
repository has made that kind of mistake:

```
- [3x, 2026-09-23, a1b2c3d] apps/worker/: temp dir not cleaned when the job fails before finally
- [2x, 2026-09-20, 9f8e7d6] *: constant measured on a small case reused on a large one
```

The next accuser gets the lines that cover the files being changed (at
most 10), so the mistake that already came back as a `fix:` twice is
the first thing it looks for. A small script does the bookkeeping
(counting, dating, capping at 30 lines) instead of a model rewriting the
file, and refuted findings never become precedent. No vector database,
no server: a text file in the repository, reviewed in the PR like any
other change.

## Without subagents

The debate works best when each role runs in its own context, so the
accuser never sees why you wrote the code the way you did. Where the
agent has no subagents, the skill runs each role in a fresh session with
the role prompt from [`roles/`](skills/objection/roles). As a last resort
it runs them in one session and says so in the record.

## Honest limits

- It is a **process guard, not a security boundary.** An agent determined
  to cheat could write a fake record. The skill forbids it in writing, and
  the record is public in the PR body.
- `curl` against the GitHub API with a token from `gh auth token` is not
  blocked by the local hook (the GitHub check still catches the PR).
- It is not free. It is built to stay cheap:
  - a small diff (up to 80 changed lines) gets **one** accuser, and the
    defender only runs if something serious was found;
  - roles get a trimmed diff (no lockfiles, snapshots, build output, 5
    lines of context), read beyond it only to chase a suspicion, and
    answer in a fixed table capped at 15 rows;
  - later rounds see only the fix diff;
  - `"budget": "lean"` in `.objection.json` cuts it to one accuser per
    round; the gate hook runs outside the model and costs no tokens.

## How it compares to Ruflo

[Ruflo](https://github.com/ruvnet/ruflo) (formerly claude-flow) is a large
multi-agent orchestration platform. If you want swarms, vector memory, and
100+ agents, look there. objection does one thing: make sure no PR ships
unless someone other than its author tried to break it.

| | objection | Ruflo (`ruflo-core` plugin, checked 2026-09-23) |
|---|---|---|
| Focus | a debate record per commit before any PR | multi-agent orchestration platform |
| MCP server | none | registers one with 300+ tools |
| Runtime downloads | none | hooks and MCP fall back to `npx …@latest` |
| Hooks | one pre-tool hook, inert without `.objection.json` | on every Bash, Edit, compaction and stop |
| Agents | 2 (accuser, defender) + yours | 100+ |
| Memory | precedents: a capped text file in the repo, reviewed in PRs | vector memory (AgentDB) |

## Layout

```
skills/objection/            the skill, self-contained
  SKILL.md                   the procedure
  roles/accuser.md           prosecution
  roles/defender.md          defense
  reference/                 init and gate-change rules, read only when needed
  stamp.sh                   validates and stores the record
  precedents.mjs             keeps .objection/precedents.md
  gate/core.mjs              gate logic, tool-neutral
  gate/hook.mjs              local hook for Claude Code, Codex, Gemini CLI, Cursor
  gate/check-pr.mjs          GitHub check
  templates/                 hook configs per tool + the GitHub workflow
agents/                      Claude Code subagents (same prompts as roles/)
.claude-plugin/, hooks/      Claude Code plugin and marketplace
action.yml                   the GitHub Action
test/                        regression cases
```

Contributing: see [AGENTS.md](AGENTS.md).

## License

MIT
