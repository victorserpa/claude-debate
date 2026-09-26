# Gates


Two layers. Use both where you can.

**1. Local hook**: blocks the agent's PR command before it runs.
One script, [`gate/hook.mjs`](../skills/objection/gate/hook.mjs), speaks
each host's hook format, and the hosts run it through
[`gate/hook.sh`](../skills/objection/gate/hook.sh): every host reads a
hook that fails to run as "go ahead", so a `node` that does not start (a
version manager's shim exits 126 when `.tool-versions` pins a version
that is not installed) or crashes let `gh pr merge` through. `hook.sh`
blocks a PR command then, in a repository that opted in. Templates live in
[`skills/objection/templates/`](../skills/objection/templates).

| host | hook | status |
|---|---|---|
| Claude Code | `PreToolUse` (ships with the plugin) | used daily; `hook.sh` run live with `claude -p`: blocked `gh pr create` without a record, allowed it with one |
| Cursor | `beforeShellExecution` + `beforeMCPExecution` | run live with the `cursor-agent` CLI, through `hook.sh` too: blocked `gh pr create` without a record (gh never ran), allowed it with one. The hook does not inherit the agent's shell `PATH`: put `node` where the hook's environment finds it |
| Codex CLI | `PreToolUse` in `.codex/hooks.json` | run live with `codex exec` (0.156), through `hook.sh` too: blocked `gh pr create` without a record, allowed it with one. After a change to the hook command, Codex asks to trust it again ("Hooks need review"). Codex runs a new hook only after you trust it (it asks in its interactive UI); until then it skips it without a word, so open Codex in the repository once after `init` |
| Gemini CLI | `BeforeTool` in `.gemini/settings.json` | run live with `gemini -p` (0.61, API key), through `hook.sh` too: blocked `gh pr create` without a record (Gemini counts the block as a failed hook in its stats, and the command does not run), allowed it with one. Gemini loads project hooks only in a trusted folder; untrusted, it skips them without a word, so trust the repository once after `init` |
| GitHub Copilot | hook format not confirmed | use the GitHub check |

Reports from people running it in those tools are welcome.

**2. GitHub check**: fails the PR unless its body has an APPROVED record
for the current head SHA and base. It does not care which tool (or
person) opened the PR, so it covers every agent, including those without
hooks. Copy [`templates/github/objection.yml`](../skills/objection/templates/github/objection.yml)
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
commits are debated and the body is updated. GitHub's *Update branch*
button is a push too, and so is a rebase: the SHA changes. When the diff
itself did not (same patch-id) and the base gained nothing in the
changed files, `debate.sh` carries the APPROVED record over without
running a reviewer, and the judge confirms it; otherwise it is a new
round.

**3. Independent review in CI (optional).** The record is written on the
agent's machine, with your credentials, so an agent that sets out to
cheat can forge one. `review: true` runs the
accuser itself, on GitHub's runner, with a key the agent never sees, on
the head SHA GitHub reports, and fails when it finds a BLOCKER
(`fail-on: high` for HIGH too, `none` to only report; a review that did not run or did not answer still fails). The findings go
to the job summary. The PR's code is never checked out or run: the base
and the PR head are fetched as commits, and the scripts come from the
action. About $0.05 per push on sonnet. It lives in its own workflow,
[`templates/github/objection-review.yml`](../skills/objection/templates/github/objection-review.yml),
which does not run on `edited`: a body edit changes no code, and a
skipped run in the record workflow would count as the latest result
and hide a failed review. Keep its `pull_request_target`: it runs from
the base branch, so a PR cannot edit its own reviewer. A PR from a fork
fails the review unless `review-forks: "true"`, so a stranger's pushes
do not spend your key; review those by hand, or turn it on. A reply
that is neither a findings table nor `NO FINDINGS` fails the check, as
does a diff too large to fit the brief (unless `fail-on: none`). The
reviewer runs without `GITHUB_TOKEN` in its environment. The `claude` CLI is
installed at a pinned version (`claude-version`), since a new one can
change the flags the reviewer is run with.

```yaml
      - uses: victorserpa/objection@v1
        with:
          record: "false"
          review: true
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
```

`defense: true` sends every BLOCKER, HIGH and MEDIUM to a defender in
one call, the same role the local debate uses, on the same runner, and
shows its answer under the findings. **It is advice: the check stays the
accuser's.** Measured on 70 findings a Gemini accuser made on the eval,
with sonnet defending: of 5 false alarms it refuted none, proposed a
lower severity for 2 and could not verify 2; of 65 real findings it
refuted one, the main row of a real bug (caller-units), citing a real
line, and proposed LOW for that bug's other row. Letting it decide would
have passed that bug through the barrier. With no judge in CI, its
answer is for the person reading the comment. One more call, only when
there is a BLOCKER, HIGH or MEDIUM. `defender-model` picks its Claude
model (default: `model`).

`comment: true` also puts the findings on the PR as one comment, edited
in place on every push rather than piling up (the job needs
`pull-requests: write`). A comment that cannot be posted is a warning;
the check's verdict does not change.

No Anthropic account? `runner: gemini` runs the same accuser through the
Gemini CLI (pinned with `gemini-version`), with a Gemini API key, which
has a free tier. `gemini-model` picks the model; empty uses the CLI's
default. It was run live through `ci-review.sh` on a planted bug (caught
as BLOCKER, check failed), and it reviews every same-repository PR here
(`.github/workflows/review.yml`). Like the claude runner, it gets no
tools: an admin policy denies every tool and MCP server, and the run
fails if the policy does not load or if any tool call succeeds anyway.
`runner: codex` (local only) disables the shell, web search, plugins
and hooks, ignores the user's config, and fails if the output shows a
command, a file change or a web search.

```yaml
      - uses: victorserpa/objection@v1
        with:
          record: "false"
          review: true
          runner: gemini
          gemini-api-key: ${{ secrets.GEMINI_API_KEY }}
```

It is a barrier only when the agent cannot get around it: the token the
agent uses must not be able to bypass the ruleset or push to the base
branch (where this workflow lives). For a solo admin whose agent uses
the admin's own `gh` login, GitHub cannot tell the two apart; use a
fine-grained token without admin rights for the agent. One reviewer can
be wrong (the defense is only advice), and the diff it reads is written
by the agent: text in the diff can try to talk it out of a finding. It has no tools,
so the worst case is a missed finding, not an action.

**GitLab CI.** Copy [`templates/gitlab/objection.gitlab-ci.yml`](../skills/objection/templates/gitlab/objection.gitlab-ci.yml),
include it from `.gitlab-ci.yml`, and turn on *Pipelines must succeed*
(Settings > Merge requests). The same script reads the merge request
through the API with the job token (the description variable GitLab
provides is cut at 2700 characters) and lists the changed files with
git. A merge request pipeline runs the source branch's CI file, so a
merge request can drop the job from its own pipeline; keep the CI file
in another project, or use a pipeline execution policy, where that
matters. If your instance does not let the job token read merge
requests, set `OBJECTION_GITLAB_TOKEN` (a project access token with
`read_api`) as a masked CI variable. Not yet run on gitlab.com: covered
by tests only.

**GitLab review.** The same accuser as the GitHub review, as a merge
request job: copy
[`templates/gitlab/objection-review.gitlab-ci.yml`](../skills/objection/templates/gitlab/objection-review.gitlab-ci.yml)
to `.gitlab/`, include it, and set `ANTHROPIC_API_KEY` (or
`GEMINI_API_KEY` with `OBJECTION_RUNNER: gemini`) as a masked variable.
It fetches the target branch and `refs/merge-requests/<iid>/head` into an
empty repository with the job token, runs nothing from the merge
request, and fails on a BLOCKER (`OBJECTION_FAIL_ON` sets the bar). With
`OBJECTION_COMMENT: "true"` and `OBJECTION_GITLAB_TOKEN` (a project
access token with the `api` scope), the findings go into one merge
request note, edited in place on every push; only that token user's own
note is edited. The reviewer never sees the job token or the note token.
It is weaker than the GitHub review: a merge request pipeline runs the
source branch's CI file, and a masked variable reaches it, so a branch
can drop the job or print the key. Keep the CI file and the variables in
another project, or use a pipeline execution policy, where that matters.
Not yet run on gitlab.com: covered by tests against a local stand-in for
the API.

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
not depend on reading commands. See [SECURITY.md](../SECURITY.md).

**The gate went through its own debate before release.** Round one found
12 ways around the first (bash) version, including a record ending in
`REJECTED` that quoted `APPROVED` and still passed. Round two, with the
defender, found 10 more. The first adopter then debated its copy for six
rounds, and most findings from round two on were regressions of the
previous fix; what that taught is now part of the skill (threat model
first, negative controls, both sides every round). Every case is in
[`test/gate.test.sh`](../test/gate.test.sh).
