# Precedents

Defects confirmed by /objection debates in this repository, one per line:
`- [<times seen>x, <last seen>, <record sha>] <area>: <pattern>`.
Maintained by precedents.mjs; edit by hand only to delete a line.

- [3x, 2026-09-24, 7cff2bf] *: a document promises protection the code does not enforce
- [3x, 2026-09-24, f68452f] skills/objection/gate/: widening an allowlist to close one bypass starts blocking innocent commands nearby
- [2x, 2026-09-24, db4fe2e] skills/objection/gate/: a normalization shared by several rules fixes one form and breaks a neighboring one
- [2x, 2026-09-24, ab823c2] skills/objection/gate/: a value the gate cannot read was skipped silently instead of failing closed
- [2x, 2026-09-24, 80722b1] skills/objection/: two instructions an agent reads together contradict each other (write a test, never change files)
- [2x, 2026-09-24, 471e520] skills/objection/: a paid external call whose failure or odd output discards the answer instead of showing it
- [1x, 2026-09-24, 7cff2bf] skills/objection/gate/: a helper process spawned per item inside the hook, uncached, spends the hook's time budget
- [1x, 2026-09-24, a9d6f78] skills/objection/gate/: a gate that covers one spelling of an action misses its other spellings (another flag, another value form)
- [1x, 2026-09-24, 102d9d2] skills/objection/gate/: a flag whose value the parser does not know is read as the target
- [1x, 2026-09-24, a9d6f78] skills/objection/gate/: an input the platform may truncate is trusted as whole
- [1x, 2026-09-24, a9d6f78] skills/objection/: a new automatic fallback turns a documented fall-back exit into a hard failure
- [1x, 2026-09-24, 5fe2c5d] skills/objection/: bash 3.2 exits 0 from a set -u error when an EXIT trap is set, so a script meant to fail closed passes
- [1x, 2026-09-24, 5fe2c5d] skills/objection/: a size or count heuristic reads what it cannot measure (a binary file, a rename) as zero and takes the cheap path
- [1x, 2026-09-24, 5fe2c5d] skills/objection/: a CI step treats every failure of a helper as one opaque exit, so a benign case (nothing to review) fails the check without saying why
- [1x, 2026-09-24, 41a39ee] test/: a test reruns a command without capturing its output and asserts on the previous run's output
- [1x, 2026-09-24, c4467fd] skills/objection/: a summary label set for one case stays when an override later changes the value it describes
- [1x, 2026-09-24, fcd5724] skills/objection/: a package manager's shorthand runs its own tool instead of the project's script (bun test)
- [1x, 2026-09-24, fcd5724] skills/objection/: a helper writes to a PR for a commit that is not the PR's head yet
- [1x, 2026-09-24, da13e89] skills/objection/: a template pre-writes a statement that only the judge can make, so removing a marker turns it into a claim nobody made
- [1x, 2026-09-24, 8e6ef56] skills/objection/: a command run inside a while-read loop inherits the loop's stdin and eats the lines still to come
- [1x, 2026-09-24, 8e6ef56] skills/objection/gate/: a new rule in a moving tag is applied to records made before it existed
- [1x, 2026-09-24, 8e6ef56] eval/: a harness that matched nothing reports 0 of 0 as a pass
- [1x, 2026-09-24, 119f23a] skills/objection/: a parser that only counts rows in one exact shape reads a model's other valid shape as zero findings and passes it
- [1x, 2026-09-24, 119f23a] skills/objection/gate/: narrowing what counts as a finding, to stop asking for one ruling too many, lets a real finding ship unruled
- [1x, 2026-09-24, 354347c] skills/objection/: a checker validates the working copy when the tool it checks for reads the base branch's copy
- [1x, 2026-09-24, 354347c] skills/objection/: a name search across the repository picks up unrelated locals and test helpers with the same name
- [2x, 2026-09-25, f0ac915] skills/objection/: a pipeline's status is its last command's, so a failed lookup reads as found nothing and the fallback runs
- [1x, 2026-09-25, 862bef3] skills/objection/: stdin read as string chunks splits a multibyte character at a 64 KiB boundary
- [1x, 2026-09-25, 1474094] test/: a regression test only fails on one platform's tool behavior, so CI on another platform passes it with the fix removed
- [1x, 2026-09-25, 18e6144] skills/objection/gate/: a fallback for when the checker cannot run resolves the target from the process directory instead of the input the checker reads
