# When the diff is a gate, check or validator

Read this when the change under debate blocks or allows something (this
skill's gate, a CI check, a permission rule, an input validator).

Changes to anything that blocks or allows (this skill's gate, a CI check,
a permission rule, an input validator) need a written threat model, or
the debate cannot converge: every new way of disguising the input looks
HIGH, and every fix opens the next hole. The first adopter debated this
skill's own gate for six rounds before writing this down.

1. **Write the threat model before the code**, in one sentence at the top
   of the file: what it stops, and what it does not. This skill's gate
   stops *forgetting* (the natural ways of writing a command), not
   *deliberate disguise* (a command assembled from pieces, hidden in an
   alias, a file, a variable or another language); disguise already breaks
   the rule, and the effect-based gate (a required check) covers it.
2. **Severity follows the threat model.** HIGH: a natural form passes, or
   an innocent command gets blocked. LOW: a form that only exists to evade.
3. **Negative control.** Every new test case must fail on the previous
   version (`git show <sha>:<file>` into a scratch directory, or `git stash`
   the fix). A case that passes on both versions guards against regression
   but proves nothing about the fix.
4. **Both sides, every round:** "the natural form is blocked" and "the
   similar innocent command still passes". Half of the regressions in that
   six-round debate were false blocks.
5. **Stubs must be able to say no.** A fake API that returns the same
   answer for every input cannot tell a right parse from a wrong one.
6. **Prefer allowlists** (what executes, what is permitted) over lists of
   what is harmless, and decide once which representation of the input
   each rule reads.
