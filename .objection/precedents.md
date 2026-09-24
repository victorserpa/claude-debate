# Precedents

Defects confirmed by /objection debates in this repository, one per line:
`- [<times seen>x, <last seen>, <record sha>] <area>: <pattern>`.
Maintained by precedents.mjs; edit by hand only to delete a line.

- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a pipe into grep -q under pipefail can fail on SIGPIPE and read as not found; use here-strings
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a shell step without pipefail lets an API failure produce an empty loop that passes
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a required check is matched by name only; a PR can add a job with the same name
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: skipping a check based on the event sender makes the result flip on the same commit
- [1x, 2026-09-24, 4bf9f11] scripts/: an exemption keyed on subject text (Merge ...) lets ordinary commits skip every rule
- [2x, 2026-09-24, 291590a] *: a document promises protection the code does not enforce
- [2x, 2026-09-24, 4dc01af] skills/objection/gate/: widening an allowlist to close one bypass starts blocking innocent commands nearby
- [2x, 2026-09-24, db4fe2e] skills/objection/gate/: a normalization shared by several rules fixes one form and breaks a neighboring one
- [1x, 2026-09-24, 0d888b5] test/: a case that only expects pass also passes when the gate never saw the command; pair it with a blocked twin
- [1x, 2026-09-24, 0d888b5] test/: a stub that answers the same for any input cannot tell a right parse from a wrong one
- [1x, 2026-09-24, db4fe2e] skills/objection/gate/: a value the gate cannot read was skipped silently instead of failing closed
- [1x, 2026-09-24, 291590a] .github/workflows/: trusting the commit author alone: whoever writes a commit sets its author; check committer and signature too
- [1x, 2026-09-24, 4dc01af] skills/objection/gate/: a hardcoded or first-found name (origin, first matching remote) stands in for the one gh really uses
