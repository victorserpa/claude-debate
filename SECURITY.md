# Security

## Reporting a vulnerability

Report privately through GitHub:
**Security → Report a vulnerability** on this repository. Please do not
open a public issue for a vulnerability.

You will get an answer within a week. Fixes ship as a new release and a
moved `v1` tag.

## What counts

- A way for an agent to **create, mark ready, or merge a PR without an
  APPROVED record** using a *natural* way of writing the command.
- A way to make the **GitHub check** accept a record bound to a different
  commit or base than the PR has.
- Anything in the action or the hook that runs code from a pull request,
  leaks a token, or writes outside the repository.

## What does not

The local hook protects against an agent *forgetting* the debate, not
against *deliberate disguise* (a command assembled from pieces, hidden in
an alias, a file, a variable, or another language). Disguise already
breaks the skill's rule, and the GitHub check with a required status
check is the gate that does not depend on reading the command. Reports of
new disguises are welcome as regular issues, labelled `gate`.

The GitHub check proves that the PR body carries an APPROVED record
**bound to its head commit and base**. It cannot prove that a debate
actually produced that record: anyone can type one by hand. That is by
design, and it is why the record is public in the PR and read by the
reviewer.

## How this repository is protected

- `main` changes only through pull requests: no direct push, no force
  push, no deletion, linear history.
- Required checks: `test`, `commits`, `issue-link`, `record`. The last
  three run from `main` through `pull_request_target`, so a PR cannot
  edit the checks that judge it.
- A check's name is not proof of where it came from: a PR could add a
  workflow with its own job named `record`. So pull requests from anyone
  but the maintainer need a code owner's approval, and workflows from
  outside contributors only run after a maintainer approves them. Read
  every change under `.github/` before approving either.

## Supply chain

- Workflows pin third-party actions to commit SHAs; Dependabot proposes
  updates.
- The `v*` tags are protected: only maintainers create or move them.
- The action and the hook have no dependencies and download nothing at
  runtime.
