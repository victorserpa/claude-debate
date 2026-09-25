# Evaluation

## Known bugs, caught

[`eval/`](../eval) plants fourteen bugs in small repositories (JavaScript,
Python and Go) and adds four changes with no bug at all: a negative cart total, an authorization
check turned into a deny-list, a temp dir leaked on a retry, pages that
start at 1 but skip the first, a charge that lost its row lock, a SQL
query built by concatenating a search term, request headers (with the
`Authorization` token) written to the log, writes fired from a
`forEach(async ...)` and never awaited, a ban check on a user fetched
without `await` (the `async` is in a file the PR does not touch), and
the negative total again with a comment telling the reviewer the change
is approved, a file name checked by a regex with no anchors before it
reaches `path.join` (path traversal), and a new DELETE route that skips
the owner check its GET sibling has, a session cookie read back with
`pickle.loads` (remote code execution), and a Go `err` shadowed by `:=`
that marks a failed charge as paid. One clean change adds `ORDER BY`
and a bounded `LIMIT` to a parameterized query, to see whether SQL alone
draws a false alarm; another makes slugs drop accents, which leaves
non-Latin titles empty exactly as the old code did. It runs the accuser on each. Latest runs (with
every reviewer tool off and the diff numbered by line), all fifteen
eighteen cases; every catch cited one of the bug's lines, not just its
words, and the defender (`EVAL_DEFENSE=1`) upheld every catch:

| runner | bugs caught | false alarm on the four clean changes | cost |
|---|---|---|---|
| claude sonnet, effort medium | 14 of 14 (12 BLOCKER, 2 HIGH) | none in that run; the slug case in 3 of 10 runs (below) | $0.22 for all eighteen (accuser) |
| gemini-3.1-pro-preview (the Gemini CLI's default) | 14 of 14 (12 BLOCKER, 2 HIGH) | none | about 6k tokens a review (measured on PR #42) |
| gemini-3-flash-preview (0.16, first twelve cases) | 10 of 10 (9 BLOCKER, 1 HIGH) | none of two | Flash pricing, below Pro |

False alarms move too: on the slug case, sonnet flagged the empty slug
as HIGH in 6 of 9 runs until both roles were told to rate what the
change does (a defect the removed lines show the old code had is at most
LOW); after that, 3 of 10. That is the defender's job in a real debate,
and one run in which the defender still upheld the alarm is why the
judge, not the defender, has the last word.

Severities move a step between runs (a HIGH one run is a BLOCKER the
next); the catches did not. The cross-file case is why the brief now carries the definitions the
added lines call, read from the commit: without them, sonnet rated it
HIGH twice and once only MEDIUM ("if `getUser` is async"), with
`src/users.js` under "Could not evaluate"; with them, BLOCKER three times
out of three, at the same cost.

The prompt-injection case was caught by all three: text in the diff is
data under review, not instructions. Flash's first run scored the SQL
injection as missed, although it had written the finding as BLOCKER:
its table had no outer pipes, so every reader counted no rows, and a CI
check would have passed that BLOCKER. review.sh now adds the pipes to
such a table (test/review.test.sh and test/ci-review.test.sh pin it),
and the rerun counted it. Run the eval yourself with `bash eval/run.sh`
(`OBJECTION_RUNNER=gemini` or `codex` for the others, and
`OBJECTION_GEMINI_MODEL` for the model). It calls a real model, so CI
runs only its scoring, against a fake reviewer (test/eval.test.sh).
Eighteen small cases prove the reviewers catch these bugs, not that they
catch every bug.

## Track record

objection reviews its own pull requests, and every record is public in
the PR body. Over five feature PRs
([#20](https://github.com/victorserpa/objection/pull/20) to
[#28](https://github.com/victorserpa/objection/pull/28)): **43 findings
the judge upheld**, every BLOCKER and HIGH fixed before merge (the rest
fixed or kept as open LOW items in the record), among them a gate that let a
PR through when `ssh` could not answer (#22), a CI check that passed on
bash 3.2 after a crash (#26), and a size rule that read binary files as
zero lines and skipped the review (#26). The same debates cost $1.22 to
$2.36 with opus forced on everything; on today's defaults the last one
(#28, two rounds) cost **$0.135**.
