# Honest limits


- It is a **process guard, not a security boundary.** An agent determined
  to cheat could write a fake record. The skill forbids it in writing, and
  the record is public in the PR body. No signature fixes that: the key
  would sit on the same machine as the agent. What does is a reviewer the
  agent cannot reach (the CI review above) plus a token for the agent
  that cannot bypass the ruleset.
- The local hook reads commands with patterns, not a shell parser. It
  catches an agent that forgets the debate, including the spellings the
  tests list, not one that disguises the command (an alias, a script that
  calls `gh`, `curl` to the API). The CI check covers those.
- `curl` against the GitHub API with a token from `gh auth token` is not
  blocked by the local hook (the GitHub check still catches the PR).
- **What a PR costs.** Measured with `usage.sh` on one brief with a known
  HIGH: sonnet at effort medium found it for **$0.05**, opus at its
  default effort for $0.33 (haiku misjudged it). So the reviewers run on
  sonnet at effort medium, and opus only where an invariant or
  `strongPaths` applies, or under `thorough`. A `lean` PR (one accuser,
  the defender only for BLOCKER or HIGH) is about $0.05 to $0.15 of
  reviewers, plus your session reading the draft and judging. With a
  Claude subscription, `claude -p` spends plan usage, not dollars; the
  dollars are the API price. Run `usage.sh --summary` after a few PRs to
  see yours. objection's own 26 PRs (standard budget, gate and validator
  changes that pull in opus, up to three rounds): median $0.15, mean
  $0.46, max $2.52 of reviewers.
- It is not free, and it is built to cost little. **Each reviewer runs as
  an isolated `claude -p` process** (`review.sh`): no tools, no MCP
  servers, no skills, no project CLAUDE.md, only its role and the brief.
  Measured in this repository: **2-12k input tokens per reviewer** (plus
  your user-level `~/.claude/CLAUDE.md`, which still loads),
  against 87-134k when the same role ran as a subagent, which inherits the
  session's prompt, every tool and your project's instructions (a
  37k-token CLAUDE.md in one adopter's repository). Without the `claude`
  CLI, the skill falls back to subagents. On top of that, objection keeps
  the count and the reading low:
  - `lean` is the default: one accuser per round, the defender only for
    BLOCKER or HIGH findings, a second round only when a fix touches a
    gate or exceeds 40 lines (otherwise the tests verify it), at most two
    rounds; `standard` and `thorough` spend more for more coverage;
  - every reviewer of a round reads one brief (`brief.sh`): the trimmed
    diff, changed files, invariants, reviewer focus, precedents and the
    definitions the added lines call (capped at 80 lines), and
    opens at most 5 other files, each for a named suspicion (in an isolated
    run it has no tools at all and judges from the brief);
  - `debate.sh` runs a whole round up to the judge (brief, accuser,
    defender for what the budget sends, a draft record), so your session
    reads one file instead of driving every step;
  - reviewer runs do not write the prompt cache: a run is one-shot and
    never reads it back, and the write costs more than plain input
    (measured: -32% per run);
  - the defender runs on sonnet even when the accuser runs on opus: it
    checks evidence already cited (same verdicts as opus on a real
    round, $0.09 instead of $0.40); later rounds review only the fix, at
    effort low; the brief carries three lines of context, not five;
  - under `lean`, a small diff (`smallDiff`, 20 changed lines) that no
    invariant or `strongPaths` touches runs no reviewer at all;
  - each finding is numbered once and the draft record does not repeat
    the table, so the judging session reads less;
  - `usage.sh` shows what each branch's reviewers cost, from a log
    `review.sh` keeps in `.git/objection/usage.log`;
  - answers come in a fixed table capped at 15 rows, and the gate hook
    runs outside the model and costs no tokens.

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

**Why it exists.** It started in two projects where `fix:` commits
outnumbered `feat:` commits almost two to one over 300 commits, and
review was a rule in the agent's instructions that nothing enforced. The
question it answers: did anyone other than the author look at this diff
before it became a PR?
