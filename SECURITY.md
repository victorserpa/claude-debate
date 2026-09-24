# Security

## Reporting a vulnerability

Report privately through GitHub:
**Security → Report a vulnerability** on this repository. Please do not
open a public issue for a vulnerability.

You will get an answer within a week. Fixes ship as a new release and a
moved `v1` tag.

## What counts

- A way for an agent to **create, mark ready, or merge a PR without an
  APPROVED record** using a *natural* way of writing the command, or a way
  for a pull request to make the **GitHub check** pass without a valid
  record.
- Anything in the action or the hook that runs code from a pull request,
  leaks a token, or writes outside the repository.

## What does not

The local hook protects against an agent *forgetting* the debate, not
against *deliberate disguise* (a command assembled from pieces, hidden in
an alias, a file, a variable, or another language). Disguise already
breaks the skill's rule, and the GitHub check with a required status
check is the gate that does not depend on reading the command. Reports of
new disguises are welcome as regular issues, labelled `gate`.

## Supply chain

- Workflows pin third-party actions to commit SHAs; Dependabot proposes
  updates.
- The `v*` tags are protected: only maintainers create or move them.
- The action and the hook have no dependencies and download nothing at
  runtime.
