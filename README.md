# objection

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Objection%20PR%20Trial-red?logo=github)](https://github.com/marketplace/actions/objection-pr-trial)
[![Release](https://img.shields.io/github/v/release/victorserpa/objection)](https://github.com/victorserpa/objection/releases)
[![Tests](https://github.com/victorserpa/objection/actions/workflows/test.yml/badge.svg)](https://github.com/victorserpa/objection/actions/workflows/test.yml)

> **OBJECTION!** Your PR goes on trial before it ships.

**A skill and plugin for AI coding agents** (Claude Code, Codex, Cursor,
Gemini CLI, GitHub Copilot, anything that reads
[Agent Skills](https://agentskills.io)). Before your agent opens a pull
request, a second model attacks the diff, a third tries to refute every
accusation with `file:line`, your agent's session judges what is left,
and a gate keeps the PR closed until the verdict is APPROVED.

It is not an app, a hosted service or a bot account: it is instructions
and a few scripts your agent runs, on your own `claude` or `codex` CLI.

![A real debate on a toy cart: the accuser finds a negative total and a NaN, the gate blocks gh pr create, round 2 finds one more NaN, then the record is APPROVED and the PR opens](docs/demo.svg)

That run is real (sonnet, `debate.sh`, a planted bug in a
[toy cart](docs/make-demo.mjs)): 3 bugs, 2 rounds, **$0.041** of
reviewers.

## What you get

- **Bugs caught before the PR exists**, not after a human reviewer or a
  user finds them. The agent that wrote the code does not grade it: an
  isolated reviewer with no stake in the diff does.
- **Few false alarms.** Every finding has to survive a defender that
  looks for the line of code proving it wrong. What cannot be refuted
  stands; what can is dropped, with the evidence in the record.
- **A step that cannot be skipped.** The local hook blocks `gh pr create`
  and `gh pr merge` without an APPROVED record for that exact commit,
  and the optional GitHub Action (or GitLab job) checks the same in CI.
  Or run it in advisory mode first: it warns instead of blocking.
- **Cents per PR.** Reviewers run as isolated `claude -p` processes on
  sonnet: $0.02 to $0.15 for a typical PR, opus only where you mark the
  code as critical. With a Claude subscription it is plan usage, not
  dollars.
- **A record reviewers can read.** What was accused, refuted, fixed and
  left open goes into the PR body, stamped to the commit.
- **It learns the repository.** Confirmed defects become precedents the
  next accuser checks first.

## Quick start

```
/plugin marketplace add victorserpa/objection
/plugin install objection@objection
```

To see what it finds before setting anything up, ask for `/objection try`
on a branch: one review of that branch against the default one, judged in
your session, and nothing written outside `.git/`.

To make it a step, in a repository ask your agent for `/objection init` (other agents:
[Install](docs/install.md)). It reads what it can (bases, your test and type
checks, your forge) and asks nothing else. To try it without blocking
anyone, say `/objection init --advisory`. Run it on the default branch
and merge its files there first: from a feature branch, the config
becomes part of the first diff the accuser reviews. From then on, when the agent is
about to open a PR, it runs the debate first; you get the record in the
PR body. Something seems off? `/objection doctor` checks the tools, the
config, the hooks (and the trust Codex and Gemini need), the CI workflow
and whether the check is required, one line each, with the fix.

## Known bugs, caught

[`eval/`](eval) plants twenty-three bugs in small repositories
(JavaScript, TypeScript, Python, Go, Rust, Java, Ruby, PHP, shell, SQL
migrations and Terraform) and adds eight changes with no bug at all: a SQL query
built by concatenation, a session cookie read with `pickle.loads`, an
authorization check turned into a deny-list, a DELETE route without the
owner check its GET has, a Go `err` shadowed by `:=` that marks a failed
charge paid, a ban check on a user fetched without `await`, and more,
including a comment telling the reviewer the change is approved.

All 40 cases, five runs each, on two model families, measured on 0.20.0 ([raw output](eval/results/2026-09-25.md)):

| | planted bugs (23 × 5) | false alarms (8 clean × 5) | real bugs (9 × 5) | caught, planted and real |
|---|---|---|---|---|
| **objection**, Claude sonnet | 114 of 115 | 2 (5%) | 71% at the right severity, 87% found | **91%** |
| **objection**, Gemini CLI default | 115 of 115 | 5 (12.5%) | 76% at the right severity | **93%** |
| same model, plain "review this diff" prompt (earlier, 19 cases, 9 real × 4) | 14 of 15 | 0 of 4 | 61% at the right severity, 81% found | |

Sonnet meets both of the v1.0 bars (90% caught, at most 10% false
alarms); Gemini catches more and alarms more, over the 10% bar. One
"clean" case was not clean: Gemini found that a new optional parameter
turned `dates.map(isoDay)` into passing the array index as the separator.
Sonnet missed it five times; the case was fixed and re-run clean on both.

The real bugs are regressions from CPython, Redis, Rails, Django, Go,
Vue, ESLint and curl, each reviewed as the PR that introduced it: the
harder test, and where the brief and the roles earn their cost ($0.23 for
the nineteen planted cases on sonnet, against $0.13 for the plain prompt).

Nine real bugs are still a small sample, and a reviewer still misses
some: no number here says it catches everything. How it is scored, every case, how the numbers
moved between versions, and the false-alarm rate across repeated runs:
[docs/eval.md](docs/eval.md). Run it yourself: `bash eval/run.sh`.

## How it differs from a review command

A review command (`/code-review`, a review bot) finds issues and hands
you a list. objection adds three things a list does not do:

- **A defender.** A second model tries to refute each finding with
  `file:line`. Fewer false positives reach you, and none is dismissed
  without evidence.
- **A gate.** The PR cannot be opened or merged until a judged record
  says APPROVED for that commit. A review that can be skipped gets
  skipped when the agent is in a hurry.
- **Memory.** Precedents (`.objection/precedents.md`) carry what this
  repository already got wrong into the next review.

They combine: keep your review command, and let objection be the step
that cannot be skipped.

## When it is worth it, and when it is not

Worth it where a bug is expensive: money, auth, data, anything with a
rule that must never break (write it as an `invariant` and it becomes a
BLOCKER when violated), and wherever an agent opens PRs faster than
people can read them.

Less so for a prototype, a repository where every PR already gets a
careful human review, or PRs that are mostly docs and config (docs-only
PRs need no reviewers, and small diffs skip them: the judge reads the
diff, writes one sentence on why it is safe, and stamps).

What it costs you in friction: one command per round (`debate.sh`), a
record the agent puts into the PR body (`pr-body.sh`), and a cheaper
round after each push that reviews only the new commits.

## How it works

When you ask an AI to build something, it plans, writes, checks, and
approves its own work: the same mind grading its own exam. objection
splits that into roles that argue:

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
                 └──────┬───────┘  put into the PR body (pr-body.sh)
                        ▼
  PR create / ready / merge  ── blocked until the record says APPROVED
```

Only what survives the defense becomes a fix.

**No finding quotas.** Prompts like "find at least three problems" make
the model invent the third one. The accusers are asked what they could
*not* evaluate instead.

It started in two projects where `fix:` commits outnumbered `feat:`
commits almost two to one over 300 commits, and review was a rule in the
agent's instructions that nothing enforced. Your ratio may be healthier;
the question objection answers is different: did anyone other than the
author look at this diff before it became a PR?

## Install

**Claude Code**: the two `/plugin` lines above (skill, subagents and the
gate hook). **Any agent that reads [Agent Skills](https://agentskills.io)**
(Codex, Cursor, Copilot, Gemini CLI, Cline, OpenCode...):
`npx skills add victorserpa/objection`, or copy
[`skills/objection/`](skills/objection) into its skills directory.

Then `/objection init` in each repository you want to protect. **Nothing
is enforced in a repository without its `.objection.json`**, so
installing the skill never blocks work anywhere else. Needs `node`,
`git`, `bash`, `perl`, and the `claude` or `codex` CLI for the reviewers.

Every config key (bases, verify, invariants, reviewers, budget, models),
running without GitHub, and uninstalling: [docs/install.md](docs/install.md).

## Gates

1. **Local hook** (Claude Code, Codex, Cursor, Gemini CLI): blocks the
   agent's `gh pr create`, `ready` and `merge` without an APPROVED record
   for that exact commit.
2. **GitHub check** (or GitLab job): fails the PR unless its body carries
   that record, whoever opened it.
3. **Independent review in CI** (optional): an accuser runs on GitHub's
   runner with a key the agent never sees, on Claude or a free-tier
   Gemini key, and can post its findings on the PR.

Setup, the threat model, and every command form the hook catches:
[docs/gates.md](docs/gates.md).

## Honest limits

- A **process guard, not a security boundary**: an agent set on cheating
  can write a fake record locally. The CI review, with a key the agent
  cannot reach, is the answer to that.
- The hook reads commands with patterns, not a shell parser: it stops an
  agent that forgets the debate, not one that disguises the command. The
  CI check covers those.
- It costs money: about **$0.05 to $0.15 of reviewers** for a typical
  `lean` PR on sonnet, plus your session judging. `usage.sh` shows yours.
- Small eval cases are not large PRs. A diff over 800 lines is reported
  before anything is spent, with a suggestion to split it.

Everything else, with the measurements: [docs/limits.md](docs/limits.md).

## Versions and stability

The hook runs before your agent's `gh` commands, so changes to it are
deliberate: every release is in the [CHANGELOG](CHANGELOG.md), and the
gate itself is reviewed on the strong model with its own rules
([reference/gate-changes.md](skills/objection/reference/gate-changes.md)).
To stay on a version: use the Action as `victorserpa/objection@v0.12.1`
(or a commit SHA) instead of `@v1`, and copy the skill folder from a
[release](https://github.com/victorserpa/objection/releases) instead of
following `main`.

## Docs

| | |
|---|---|
| [docs/install.md](docs/install.md) | install, every config key, without GitHub, uninstall |
| [docs/gates.md](docs/gates.md) | the local hook, the GitHub/GitLab check, the CI review |
| [docs/record.md](docs/record.md) | what a record looks like, precedents |
| [docs/eval.md](docs/eval.md) | the eval: cases, scoring, results |
| [docs/limits.md](docs/limits.md) | honest limits, costs, how it compares |
| [docs/layout.md](docs/layout.md) | where everything lives in this repository |
| [CHANGELOG.md](CHANGELOG.md) | every release |

## License

MIT
