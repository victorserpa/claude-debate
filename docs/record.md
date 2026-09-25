# The record

## What a record looks like

Every finding names its kind (BUG, REGRESSION, SCOPE, INVARIANT) and the
evidence it rests on, from `read` (someone read the code) up to
`reproduced` (someone ran it and saw it). The skill tells the judge to
settle disputes by raising the evidence and to keep an unsettled BLOCKER
or HIGH open. Those are rules for the judge: `stamp.sh` and the GitHub
check verify the stamp, the verdict and the `OPEN:` count, not the
content of each finding. The record is public in the PR so a person can check it.

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
