# /objection init

Read this only when opting a repository in (no `.objection.json` yet, or the
user asked for `init`). Paths below are relative to the skill directory.

If `.objection.json` does not exist at the repository root and the user
asked for `init` (or this is the first debate), create it. Ask the user
only what you cannot read from the repository:

```json
{
  "bases": ["main"],
  "defaultBase": "main",
  "verify": ["npm run typecheck", "npm test"],
  "reviewers": [
    { "paths": "^src/(auth|billing)/", "agent": "security-reviewer", "focus": "the project's security checklist" }
  ],
  "invariants": [
    { "paths": "^src/game/", "rule": "undo never restores a life that was spent" },
    { "paths": "^src/(auth|api)/", "rule": "a response never includes another user's private data" }
  ]
}
```

- `bases`: every branch a PR may target (e.g. `["develop", "main"]`).
- `defaultBase`: the base to debate against when the task does not say.
  gh never reads it: pass `--base` to `gh pr create` (the gate checks the
  base gh will really use: `--base`, else the branch's `gh-merge-base`,
  else the repository default on GitHub).
- `verify`: the cheap proof that runs before any accuser (step 0 of SKILL.md).
- `reviewers`: extra accusers by path regex. `agent` names a reviewer the
  project already defines for your tool (subagent, custom agent, or a
  prompt file path); `focus` goes into its prompt. The generic accuser
  always runs on code, so this list can start empty. `agent` may also
  be another tool (`codex exec`, a different model): a second opinion from
  a different model is the cheapest way to avoid everyone repeating the
  same mistake, and it is worth it on the riskiest paths only.
- `invariants` (optional): rules the project must never break, each with
  the paths it guards. When the diff touches those paths, the accuser gets
  the rule and a violation is a BLOCKER. Ask the user for the few that
  matter most; do not invent them.
- `budget` (optional): `lean` (default), `standard` or `thorough`. See
  "Token budget" in SKILL.md.
- `precedents` (optional, default `true`): keep and use the repository's
  precedents (steps 1 and 5 of SKILL.md). `false` turns them off.

Then install a gate, and tell the user which one you installed:

1. **Local gate for your tool**, so the PR command itself is blocked.
   Copy the matching file from `templates/` in the skill directory
   (or write it from the snippet below), replacing `<SKILL_DIR>` with this
   skill's directory, relative to the repository root when the skill is
   inside the repository:
   - Claude Code: nothing to do if installed as the plugin (the hook ships
     with it). Otherwise a `PreToolUse` hook on `Bash|mcp__.*` running
     `node <SKILL_DIR>/gate/hook.mjs`.
   - Cursor: `.cursor/hooks.json`, `beforeShellExecution` and
     `beforeMCPExecution` running `node <SKILL_DIR>/gate/hook.mjs --host cursor`.
   - Codex CLI: `.codex/hooks.json`, `PreToolUse` running
     `node <SKILL_DIR>/gate/hook.mjs --host codex` (Codex hooks are
     experimental and must be enabled).
   - Gemini CLI: `.gemini/settings.json`, `BeforeTool` running
     `node <SKILL_DIR>/gate/hook.mjs --host gemini`.
2. **GitHub check**, which works whatever tool (or person) opens the PR:
   `.github/workflows/objection.yml` from `templates/github/objection.yml`
   (it uses `victorserpa/objection@v1`),
   then ask the user to make it a required status check. Recommend it
   always; it is the only gate for tools without hooks.
   On GitLab instead: `.gitlab/objection.gitlab-ci.yml` from
   `templates/gitlab/objection.gitlab-ci.yml`, included from
   `.gitlab-ci.yml`, and ask the user to turn on "Pipelines must succeed".
   Elsewhere (Bitbucket, Gitea, no forge): say there is no gate, the
   debate is advice.

Commit the files. From then on the debate is enforced in this repository.
