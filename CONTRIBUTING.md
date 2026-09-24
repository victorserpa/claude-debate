# Contributing

1. **Open an issue first**, or pick one. Every pull request closes an
   issue (`Closes #n` in the body); CI checks it.
2. **Branch from `main`**: `<type>/<issue>-<slug>`, e.g. `fix/12-glued-repo-flag`.
   `main` only changes through pull requests.
3. **Commits and PR title**: Conventional Commits, in English, no
   `Co-Authored-By` trailer. Enable the local hook once:
   `git config core.hooksPath .githooks`. The PR title becomes the squash
   commit, so it follows the same rules.
4. **Run the tests** listed in [AGENTS.md](AGENTS.md).
5. **Debate your change**: this repository uses objection on itself. Run
   `/objection` and paste the stored record into the PR body; the
   `record` check reads it.

Changing the gate (`skills/objection/gate/`)? Read the threat model in
[SECURITY.md](SECURITY.md) and the rules for gate changes in
[AGENTS.md](AGENTS.md) first.
