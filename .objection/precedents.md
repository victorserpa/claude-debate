# Precedents

Defects confirmed by /objection debates in this repository, one per line:
`- [<times seen>x, <last seen>, <record sha>] <area>: <pattern>`.
Maintained by precedents.mjs; edit by hand only to delete a line.

- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a pipe into grep -q under pipefail can fail on SIGPIPE and read as not found; use here-strings
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a shell step without pipefail lets an API failure produce an empty loop that passes
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: a required check is matched by name only; a PR can add a job with the same name
- [1x, 2026-09-24, 4bf9f11] .github/workflows/: skipping a check based on the event sender makes the result flip on the same commit
- [1x, 2026-09-24, 4bf9f11] scripts/: an exemption keyed on subject text (Merge ...) lets ordinary commits skip every rule
- [1x, 2026-09-24, 4bf9f11] *: a document promises protection the code does not enforce
