# Changelog

## Unreleased

- pr-body.sh folds the accusation and the defense under `<details>`
  ("Accusation and defense (N findings)"), so the PR shows the rulings,
  what is open and the verdict first. The section lines stay whole, and
  the CI check reads a folded body (test/pr-body.test.sh runs it).
- **A rebase no longer costs a round.** When the branch's diff is
  byte-for-byte one an APPROVED record already judged (same `git
  patch-id`, same base) and the commits the base gained touch none of the
  changed files, `debate.sh` runs no reviewer: the draft carries the old
  record, with one line for the judge to confirm after `verify`. A base
  commit in a changed file, a failed invariant check, `--since` or
  `--force` run the full round.
- SKILL.md is 1,600 words instead of 3,000: it loads into the session
  that judges, the most expensive context of the debate. Running the
  roles by hand (no `claude` CLI) moved to `reference/manual-roles.md`.
- The brief drops diff header lines that repeat the file name (`index`
  hashes, and the `---`/`+++` pair unless a side is `/dev/null`).
- Each record says which round it was ("Round 2 of 3."), and a round run
  with `--extra-round` says it ran past the cap, so the human reading the
  PR sees it. debate.sh prints the same line.
- The CI review counts a finding row without a header as an answer only
  when it has the whole row (severity, kind, file, defect, evidence,
  proof): a refusal that quotes a short row no longer passes.
- The first PR after init, while the base has no config yet, gets a
  record that names the working copy's config instead of "config none",
  as the brief already did.
- brief.sh, stamp.sh and review.sh print a clean usage line when called
  without arguments; `init.sh --help` prints its usage and exits 0.
- README: run init on the default branch, so the config is not part of
  the first reviewed diff.
- The eval has three more cases: path traversal through an unanchored
  regex, a DELETE route without the owner check, and a clean SQL change.
  claude sonnet and the Gemini CLI default each caught 12 of 12 bugs with
  no false alarm on the three clean changes, with every reviewer tool
  off.
- The brief numbers each line of the diff by the new file (blank for a
  removed line), so a finding cites the line the code is on instead of
  one counted from the `@@` header: sonnet had cited the line above the
  bug in the prompt-injection case. The eval now says whether each catch
  cited a bug line or only named the bug; with the numbered diff, all
  twelve catches cited the line, on sonnet and on the Gemini default.
- The accuser and the defender now rate what the change does, not what
  the code already did: a defect the removed lines show the base code
  had, which the change neither causes nor spreads, is at most LOW
  ("pre-existing"). Measured on a new clean case (slugs that drop
  accents): sonnet's false alarm went from 6 of 9 runs to 3 of 10.
- The eval has Python and Go cases: a session cookie read with
  `pickle.loads` (remote code execution) and an `err` shadowed by `:=`
  that marks a failed charge as paid, plus a clean Python change.
- `EVAL_DEFENSE=1 bash eval/run.sh` also runs the defender on each false
  alarm and each catch, and reports what it ruled.

## 0.17.0 (2026-09-24)

**A security pass, and a round cap the script enforces.** Upgrade from
0.16: it let a diff plant brief markers (below).

- **Fixed, critical (0.16):** the definitions section put code from the
  repository into the brief, and debate.sh read its markers (budget,
  model, invariant checks) from anywhere in the brief, so a planted line
  could turn an invariant check off or change the model. brief.sh now
  ends its header with `<!-- objection-header-end -->` and debate.sh
  reads markers only above it.
- Gemini reviewers run under an admin policy that denies every tool and
  MCP server; the run fails if the policy does not load or a tool call
  succeeds. Before, a bad policy was ignored without a word.
- Codex reviewers run ephemeral, with the user's config, rules, shell,
  web search, plugins, apps and hooks off, and fail if the stream shows
  a command, a file change or a web search.
- CI review: a fork's PR fails unless `review-forks: "true"`, so strangers
  cannot spend the key; the reviewer runs without `GITHUB_TOKEN`; a reply
  with no findings table and no `NO FINDINGS` fails; a truncated brief
  fails (unless `fail-on: none`); the PR comment neutralizes `<!--`,
  images and mentions, and only edits the bot's own comment.
- The review has its own workflow template,
  `templates/github/objection-review.yml`, without `edited`: a skipped run
  in the record workflow counted as the latest result and hid a failure.
- The local gate reads the opt-in from the directory each command runs
  in (`cd repo && gh pr create` from a session started elsewhere is
  checked against that repository), treats `GH_REPO` like `-R`,
  and lets `gh pr ready --undo` through.
- **Round cap:** debate.sh refuses a round past `maxRounds` (2 under
  lean, 3 otherwise; new config key) and exits 4, telling the agent to
  close the record and ask the human. `--extra-round` runs one more when
  the human asks; `--force` re-debates a commit already judged. SKILL.md
  now says MEDIUM and LOW findings may stay Open: fix them only when
  small and in scope. An agent had saved "every finding becomes a fix"
  and ran a PR through 8 rounds, each one reviewing the previous fix.
- Docs-only is decided by extension (md, mdx, rst, adoc; not txt, since
  requirements.txt changes the build), and a
  rename counts under both names, so renaming code to `.md` is not
  docs-only.
- PR bodies with CRLF line endings are read correctly by the check and
  the precedent parser.
- pr-body.sh keeps text written below the old record.
- File names with non-ASCII characters reach invariant regexes as they
  are (git quoted them before).
- git grep in the definitions step has a timeout.
- README: an Uninstall section, and the isolation of each runner as it
  is now.

## 0.16.0 (2026-09-24)

**Easier to set up, sees past the diff, speaks up on the PR.**

- The Action's review takes `comment: true`: the findings go on the PR as
  one comment, found by a marker and edited on every push, instead of
  only in the job summary nobody opens. A comment that cannot be posted
  (no `pull-requests: write`) is a warning, never a changed verdict.
  This repository's `review (gemini)` job uses it.

- The brief carries the definitions the added lines call, read from the
  commit (at most 8, 12 lines each, 80 in all; a name defined in more
  than 3 places is left out). A reviewer that saw only the diff could not
  tell that a helper in an untouched file is async. On the new
  cross-file-async eval case (a ban check on a user fetched without
  `await`), sonnet went from HIGH, HIGH and a hedged MEDIUM to BLOCKER
  three times, at the same cost. The eval now has twelve cases: sonnet
  caught 10 of 10 bugs for $0.11, and gemini-3.1-pro-preview and
  gemini-3-flash-preview caught the new one as BLOCKER.

- `/objection doctor` (doctor.sh): one line per item, ok, warn or FAIL,
  with the fix. It checks the tools and the reviewer CLIs, and the
  config: valid JSON, unknown keys (a typo like "invariant" used to be
  ignored in silence), types, regexes that do not compile, and a
  defaultBase that is not among bases. It says when the base branch's
  config differs from the working copy, which one debates use until the
  merge. It checks the hook files and the trust step Codex and Gemini
  need, the CI workflow, and, through gh, whether "record" is a required
  check. It only reads.
- `objection.schema.json`: the config's keys and values for editors.
  `init` writes `"$schema"`, so VS Code and others complete and check
  `.objection.json`. A test keeps the schema and doctor.sh on the same
  keys.

- Every node step that reads stdin decodes it as UTF-8 (setEncoding).
  Chunks concatenated as strings split a multibyte character at a
  64 KiB boundary. This repository's review (gemini) job found it on
  its own PR.

## 0.15.0 (2026-09-24)

**One real fail-open closed, and a bigger eval.**

- review.sh adds the outer pipes to a findings table written without
  them ("BLOCKER | BUG | a.ts:6 | ..."). debate.sh, ci-review.sh and the
  eval count only rows that start with "|", so such a BLOCKER counted as
  none, and the CI check would have passed it. Found by the eval:
  gemini-3-flash-preview wrote its SQL-injection BLOCKER that way.
- eval: four new cases (a SQL query built by concatenation, the
  Authorization header written to the log, writes from a
  `forEach(async ...)` never awaited, and a second clean change), eleven
  in all. Claude Sonnet caught 9 of 9 bugs for $0.10, gemini-3.1-pro-preview
  9 of 9, and gemini-3-flash-preview 9 of 9 once its table was read.
  None raised a false alarm on the clean changes.
- The eval's scoring is tighter: a keyword counts only in the defect
  cell next to the file, so an unrelated finding in the same file is no
  longer a catch. test/eval.test.sh checks the scoring against a fake
  reviewer and runs in CI.
- The Gemini CI review runs on a GitHub runner: this repository's
  `review (gemini)` job reviews every same-repository PR with it. First
  live run: PR #42, authenticated by `GEMINI_API_KEY` alone, 4433 input +
  1694 output tokens.

## 0.14.0 (2026-09-24)

- The Action's review step runs through the Gemini CLI with
  `runner: gemini` and `gemini-api-key`, so a repository without an
  Anthropic account can still have an independent accuser in CI (Gemini
  has a free tier). The CLI is pinned (`gemini-version`, default 0.61.0),
  and `gemini-model` picks the model. Run live through `ci-review.sh` on
  the negative-total fixture: caught as BLOCKER, the check failed. Not
  yet run on a GitHub runner.
- README: Marketplace, release and test badges.

## 0.13.0 (2026-09-24)

**Evidence over opinion, and a second model family.**

- Gemini CLI: the hook was run live (0.61, with an API key): it blocks
  `gh pr create` without a record and allows it with one, once the folder
  is trusted (an untrusted folder skips project hooks silently). With
  Codex (0.12.1), every host with hooks is now verified live.
- Reviewers through the Gemini CLI: a `reviewers` entry with
  `"agent": "gemini"` (or `gemini-<model>`, or `codex`) runs that accuser
  through that CLI, isolated (the role as `GEMINI_SYSTEM_MD`, read-only
  plan mode, no extensions, no project config). `OBJECTION_RUNNER=gemini`
  forces it for any role. Never picked on its own.
- `eval/`: seven known bugs (prompt injection and a clean change
  included) and `eval/run.sh` to run any reviewer against them. Claude
  sonnet caught 7 of 7 for $0.06; Gemini caught 7 of 7; neither raised a
  false alarm on the clean change.
- Invariants take `"verify": "<command>"`: run by `debate.sh` before the
  reviewers when the diff touches the invariant's paths; a failure is a
  numbered BLOCKER, a pass is listed in the record.
- Every draft record names the objection version (`skills/objection/VERSION`),
  the base config's hash, and the accuser's and defender's model and
  effort.
- `stamp.sh` and the CI check require a Judge ruling ("N.", "N-M.",
  "1, 2 and 5:") for every finding the Accusation numbers.
- The Action's Marketplace name is "Objection PR Trial" ("objection" is
  taken there); `uses: victorserpa/objection@v1` is unchanged.

## 0.12.1 (2026-09-24)

- README leads with what you get, a two-command quick start, when
  objection is worth it and when it is not, the friction it adds, and how
  to pin a version. The fix-to-feat ratio is now the origin story, not
  the argument.
- A small diff's draft record comes pre-filled as APPROVED with one
  `TODO(judge)` line: read the diff, replace the line with one sentence
  on why it is safe, stamp. The script never writes that sentence.
- Codex: the hook was run live (`codex exec` 0.156): it blocks
  `gh pr create` without a record and allows it with one. Codex runs a new
  hook only after the user trusts it, and skips it silently until then;
  init and the docs now say so (they called Codex hooks experimental).

## 0.12.0 (2026-09-24)

**Easier to try, easier to live with.**

- `init.sh`: `/objection init` asks nothing it can read. Bases from
  origin (develop becomes the default when origin has it), `verify` from
  the project's own scripts (package.json with its package manager,
  Cargo, Go, Make, pytest), the hook for your agent (`--host`), the CI
  check for GitHub or GitLab. Never overwrites a file.
- Advisory mode: `"enforce": false` (or `init.sh --advisory`) keeps the
  debate and turns the gate into a warning: the hook lets the PR through
  and says what it would have blocked. Only a literal `false` counts; an
  invalid config still blocks.
- `pr-body.sh`: puts the stamped record into the PR body (`--update`
  replaces it in an open PR, keeping the description), so nobody pastes
  records after every push.
- README: an animated demo of a real debate ($0.041, 3 bugs), the track
  record from this repository's own PRs, a section on trying it without
  blocking anyone, and how it differs from a review command.

## 0.11.0 (2026-09-24)

**Less per PR, the same reviews.** Every cut was measured on real
briefs before it became a default; none of them drops a reviewer.

- Reviewer runs no longer write the prompt cache (`DISABLE_PROMPT_CACHING`
  for the isolated `claude -p`): each run is one-shot, never read back,
  and the CLI wrote the whole input to a 1-hour cache at a premium.
  Accuser $0.104 -> $0.071, defender $0.100 -> $0.067 on the same brief.
  `OBJECTION_PROMPT_CACHE=1` keeps it.
- The defender runs on `models.defender` (default sonnet) whatever the
  accuser runs on: on a real round it gave opus's verdicts on five
  findings and the judge's on the sixth, for $0.09 instead of $0.40.
  `OBJECTION_DEFENDER_MODEL` overrides it.
- Later rounds (`--since`, the fix only) run the accuser at
  `models.laterEffort` (default low).
- The brief carries three lines of diff context instead of five; the
  known HIGH (ab823c2) was still found in 2 of 2 runs.
- Tried and dropped: a prompt prefix shared by accuser and defender, so
  the defender would read the brief from cache; the cache never hit.

## 0.10.0 (2026-09-24)

**Say what it is, spend less, and a reviewer the agent cannot reach.**

- README opens with what objection is: a skill and plugin installed into
  AI coding agents, not an app or a hosted service, and what it is not.
- Under `lean`, a diff of at most `smallDiff` changed lines (default 20,
  `0` turns it off) that no invariant or `strongPaths` touches runs no
  reviewer: the draft says so and the judge reads the diff alone.
- `models.strongEffort` sets the strong tier's effort apart (opus at low
  found the same HIGH as at its default effort for $0.13, not $0.33).
- The draft record numbers each finding once, in the Accusation; the
  defender gets the same numbers and the table is not repeated.
- The Action takes `review: true` (with `anthropic-api-key`, `model`,
  `effort`, `fail-on`): `ci-review.sh` runs the accuser on the PR head in
  CI, never checking out or running the PR's code, and fails on a BLOCKER
  (or HIGH). It fails closed, including on bash 3.2, which exits 0 from a
  `set -u` error under an EXIT trap.
- Cursor: the hook was run live with the `cursor-agent` CLI (blocks
  without a record, allows with one); its environment does not inherit
  the agent's shell `PATH`.
- Honest limits say why a signature would not stop a forged record, and
  that the local hook catches forgetting, not disguise.

## 0.9.0 (2026-09-24)

**Cheap enough for several projects at once, and not only GitHub.**

- Reviewers run on **sonnet at effort medium** by default. Measured on
  one brief with a known HIGH: sonnet at medium found it for $0.05
  (2.5k output tokens), opus at its default effort for $0.33 (10.5k),
  opus at medium for $0.20, haiku misjudged it. Opus is kept for what
  an invariant or the new `strongPaths` names, and for `thorough`
  (`models` in the config sets both and the effort). `debate.sh` prints
  the model and why; `OBJECTION_MODEL` and `OBJECTION_EFFORT` override.
- `review.sh` runs the roles through the **Codex CLI** (`codex exec`,
  read-only sandbox, the role as instructions, no AGENTS.md) when the
  claude CLI is missing, or with `OBJECTION_RUNNER=codex`; a Codex
  picked that way that fails exits 3 (fall back to subagents). Flags
  from Codex's docs; not yet run live.
- **GitLab**: the local gate covers `glab mr create` (needs
  `--target-branch` and the debated commit pushed), `glab mr merge`
  (only with `--auto-merge=false`: auto-merge is glab's default),
  `glab mr update --ready` and `glab api` writes to `merge_requests`. `check-pr.mjs` runs as a GitLab
  CI job (`templates/gitlab/`), reading the merge request with the job
  token (or `OBJECTION_GITLAB_TOKEN`; the description variable when the
  API refuses and it was not cut) and the files with git. Not yet run on
  gitlab.com.
- README: what works without GitHub or `gh` (the debate everywhere, the
  gate only where there is one), and what a PR costs.
- No script needs git 2.31 any more (`--path-format=absolute` is gone).

## 0.8.0 (2026-09-24)

**Windows, and the gaps left after 0.7.0.**

- Windows: CI now runs every test on Linux, macOS and Windows (Git
  Bash). The gate reads Git Bash paths (`/c/...`, `/tmp/...`) in `cd`
  targets and the hook's `cwd` through `cygpath`; `.gitattributes` keeps
  the scripts LF on Windows checkouts.
- `debate.sh` and `stamp.sh` default to the config's `defaultBase`
  (adopters whose base is `develop` no longer need to say so).
- `stamp.sh` refuses a record that still has `TODO(judge)` lines.
- Under `standard` and `thorough`, `debate.sh` runs each matching
  `reviewers` entry as its own isolated accuser with its focus
  (`OBJECTION_FOCUS` in `review.sh`); an `agent` that names a Claude
  model runs on it. A base the config lists but origin lacks stops the
  round with a fetch hint instead of falling back to `defaultBase`.
- `debate.sh` keeps the newest `OBJECTION_KEEP` (10) artifacts of each
  kind in `<git-common-dir>/objection`; stamped records are never pruned.
- `review.sh`'s timeout ends the reviewer's whole process group, and an
  interrupt is passed on to it.
- Precedents come from the base branch, like the rules; and when the
  skill under review is in the repository itself, `debate.sh` gives the
  reviewers the base branch's roles.
- The gate's `--head <owner>:<branch>` only matches remotes on GitHub's
  host (or `GH_HOST`) or an SSH alias for it: a mirror elsewhere no
  longer blocks.

## 0.7.0 (2026-09-24)

**One command per round, and the cost of each PR on record.**

- `debate.sh <base> [goal] [scope]` runs a round up to the judge: the
  brief, the isolated accuser, the defender only for the findings the
  budget sends (`lean`: BLOCKER and HIGH), and a draft record with the
  Judge and Open sections marked `TODO(judge)`. It prints a four-line
  summary; the main session reads the draft and judges, instead of
  spending its own context on every step. `--since <commit>` runs a later
  round on the fix only. The budget comes from the base branch.
- `review.sh` appends every run (date, branch, commit, role, model,
  tokens, cost) to `<git-common-dir>/objection/usage.log`; `usage.sh`
  sums it per branch, `usage.sh <branch>` lists each run.
- `brief.sh` writes the base branch's budget into the brief.
- The reviewer model stays `opus`. On the same brief, opus found 3 HIGH
  and 6 MEDIUM ($0.31); sonnet 1 HIGH and 4 MEDIUM ($0.08); haiku 1 HIGH
  and 1 MEDIUM ($0.09). `OBJECTION_MODEL=sonnet` is the knob for a
  cheaper, shallower run.

## 0.6.0 (2026-09-24)

**Reviewers run isolated: 2-12k input tokens each instead of 87-134k.**

- `review.sh accuser <brief>` / `review.sh defender <brief> <findings>`
  run a role as a `claude -p` process with no tools, no MCP servers, no
  skills, no user or project settings and no project CLAUDE.md: the role
  is the whole system prompt and the brief is the only input. Measured in
  this repository: 6,843 (accuser) and 11,634 (defender) input tokens,
  against 87-134k for the same roles run as subagents. The defender also
  gets the code around every file:line its findings cite. A timeout stops
  a hung call, and a failed call shows what came back.
- SKILL.md: isolated runs first; subagents only when the `claude` CLI is
  not available.
- `test/review.live.sh` proves the isolation against the real CLI (1,678
  input tokens for a small diff).

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
