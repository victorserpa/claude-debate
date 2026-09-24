# Precedents

Defects confirmed by /objection debates in this repository, one per line:
`- [<times seen>x, <last seen>, <record sha>] <area>: <pattern>`.
Maintained by precedents.mjs; edit by hand only to delete a line.

- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a pipe into grep -q under pipefail can fail on SIGPIPE and read as not found; use here-strings
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a shell step without pipefail lets an API failure produce an empty loop that passes
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a required check is matched by name only; a PR can add a job with the same name
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: skipping a check based on the event sender makes the result flip on the same commit
- [1x, 2026-09-24, 4bf9f11] scripts/: an exemption keyed on subject text (Merge ...) lets ordinary commits skip every rule
- [3x, 2026-09-24, 7cff2bf] *: a document promises protection the code does not enforce
- [3x, 2026-09-24, f68452f] skills/objection/gate/: widening an allowlist to close one bypass starts blocking innocent commands nearby
- [2x, 2026-09-24, db4fe2e] skills/objection/gate/: a normalization shared by several rules fixes one form and breaks a neighboring one
- [1x, 2026-09-24, 0d888b5] test/: a case that only expects pass also passes when the gate never saw the command; pair it with a blocked twin
- [1x, 2026-09-24, 0d888b5] test/: a stub that answers the same for any input cannot tell a right parse from a wrong one
- [2x, 2026-09-24, ab823c2] skills/objection/gate/: a value the gate cannot read was skipped silently instead of failing closed
- [1x, 2026-09-24, 291590a] .github/workflows/: trusting the commit author alone: whoever writes a commit sets its author; check committer and signature too
- [1x, 2026-09-24, 4dc01af] skills/objection/gate/: a hardcoded or first-found name (origin, first matching remote) stands in for the one gh really uses
- [2x, 2026-09-24, 80722b1] skills/objection/: two instructions an agent reads together contradict each other (write a test, never change files)
- [1x, 2026-09-24, ffa9cd5] skills/objection/: a rule moved or trimmed stops reaching an agent that never reads the file it moved to
- [1x, 2026-09-24, 80722b1] skills/objection/: rules read from the branch under review instead of its base let a change rewrite its own rules
- [2x, 2026-09-24, 471e520] skills/objection/: a paid external call whose failure or odd output discards the answer instead of showing it
- [1x, 2026-09-24, dc942c5] test/: a live check that passes on a word the prompt already contains cannot report a miss
- [1x, 2026-09-24, 1952d54] skills/objection/: a parser of model output that silently drops rows written in a format it did not expect
- [1x, 2026-09-24, 471e520] test/: an assertion behind a guard or only a negative grep passes when nothing was checked
- [1x, 2026-09-24, 7cff2bf] skills/objection/: a marker matched anywhere in free text refuses content that only quotes it
- [1x, 2026-09-24, 7cff2bf] skills/objection/: an argument that does not parse as one thing is silently reused as another
- [1x, 2026-09-24, 7cff2bf] skills/objection/gate/: a helper process spawned per item inside the hook, uncached, spends the hook's time budget
- [1x, 2026-09-24, a9d6f78] skills/objection/gate/: a gate that covers one spelling of an action misses its other spellings (another flag, another value form)
- [1x, 2026-09-24, 102d9d2] skills/objection/gate/: a flag whose value the parser does not know is read as the target
- [1x, 2026-09-24, a9d6f78] skills/objection/gate/: an input the platform may truncate is trusted as whole
- [1x, 2026-09-24, a9d6f78] skills/objection/: a new automatic fallback turns a documented fall-back exit into a hard failure
- [1x, 2026-09-24, 5fe2c5d] skills/objection/: bash 3.2 exits 0 from a set -u error when an EXIT trap is set, so a script meant to fail closed passes
- [1x, 2026-09-24, 5fe2c5d] skills/objection/: a size or count heuristic reads what it cannot measure (a binary file, a rename) as zero and takes the cheap path
- [1x, 2026-09-24, 5fe2c5d] skills/objection/: a CI step treats every failure of a helper as one opaque exit, so a benign case (nothing to review) fails the check without saying why
