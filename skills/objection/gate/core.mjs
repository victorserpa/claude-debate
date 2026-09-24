// Tool-neutral core of the objection gate. Adapters (Claude Code, Cursor,
// Codex, Gemini CLI...) translate their hook input into
//   { kind: "shell", command, cwd }   or   { kind: "tool", tool, cwd }
// and translate the result back: { blocked: false } or
// { blocked: true, reason, hint }.
//
// It blocks creating, marking ready, and merging a pull request unless an
// APPROVED /objection record exists for the exact commit going into the PR,
// plus the shortcuts that would skip the record: `gh api` writing to
// /pulls, GraphQL PR mutations, auto-merge, and tools that create or merge
// PRs. Opt-in per repository: nothing is enforced without `.objection.json`
// (or `.claude/objection.json`) at the repository root.
//
// The record is per commit, not per branch. It lives at
// `<git-common-dir>/objection/<sha>.md` and is only valid for that SHA: a
// new commit after the debate invalidates it. `ready` and `merge` check the
// PR head SHA on GitHub, not the local copy.
//
// This code went through two rounds of its own debate before release. The
// first round broke the original bash version with 12 bypasses (a record
// ending in REJECTED that quoted "APPROVED" passed; `gh -R x pr create`,
// `gh pr new`, `x=$(gh pr create)`, auto-merge...). The second round, with
// the defender, found 10 more (multi-line GraphQL, a hung `gh`, `gh pr -R`,
// a shell reading stdin, disguised command names, ambiguous directories,
// xargs, tool names, arbitrary stamp base, hand-written records). Every one
// of them is a case in test/gate.test.sh.
//
// Threat model, in one sentence: this gate stops an agent that FORGETS the
// debate (the natural ways of writing the command), not one that DISGUISES
// the command on purpose (assembled from pieces, hidden in an alias, a
// file, a variable or another language). Disguise already breaks the
// skill's rule, and the GitHub check with a required status check is the
// gate that does not read commands. So a natural form that passes, or an
// innocent command that gets blocked, is HIGH; a form that only exists to
// evade is LOW. The first adopter debated this gate for six rounds before
// that sentence existed, mostly chasing regressions of its own fixes.
//
// Which text each rule reads (decided here, once):
//   command   raw input, with disguised `gh` names normalized. GraphQL
//             mutations are looked for here, heredocs included, because a
//             multi-line query is the normal way to write one.
//   noDocs    command without heredoc bodies (unless a shell reads stdin).
//             `gh api` REST writes and `cd` paths are read here.
//   active    noDocs with inert quoted text replaced by ''. Quoted values
//             glued to -R/-B/-H (or --repo=/--base=/--head=) become plain
//             values; any other glued value becomes a glued ''. Arguments
//             of -c/-lc (shells, python, su...), -e (node, perl, ruby) and
//             eval are kept as code (allowlist).
//             `gh pr <action>` detection and positions are measured here.
//
// Fails closed when the command is about a PR: if it cannot verify (gh
// offline, PR not found), it blocks and says why. A human bypasses it by
// running the command in their own terminal; the gate only binds the agent.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";

export const HINT =
  "Run /objection until the record says APPROVED for this commit. A human can bypass this by running the command in their own terminal.";

class Blocked extends Error {
  constructor(reason, withHint) {
    super(reason);
    this.reason = reason;
    this.withHint = withHint;
  }
}

function block(reason, withHint = true) {
  throw new Blocked(reason, withHint);
}

const ALLOW = { blocked: false };

export function gate(input) {
  try {
    function git(dir, ...args) {
      // Timeout: without it a hung git/gh pushes the hook past the harness
      // limit, which treats the overrun as a non-blocking error (fail-open).
      // Callers turn the throw into a block.
      return execFileSync("git", ["-C", dir, ...args], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 10000,
      }).trim();
    }

    // --- Opt-in ------------------------------------------------------------------
    const sessionDir =
      input.cwd && existsSync(input.cwd) ? input.cwd : process.cwd();

    function loadConfig(dir) {
      let top;
      try {
        top = git(dir, "rev-parse", "--show-toplevel");
      } catch {
        return null;
      }
      // Tool-neutral location first; .claude/ kept for Claude Code users.
      const file = [join(top, ".objection.json"), join(top, ".claude", "objection.json")].find(existsSync);
      if (!file) return null;
      try {
        return JSON.parse(readFileSync(file, "utf8"));
      } catch {
        block(`${file} is not valid JSON.`, false);
      }
    }

    const config = loadConfig(sessionDir);
    if (!config) return ALLOW;

    function defaultBase(dir) {
      if (config.defaultBase) return config.defaultBase;
      try {
        return git(dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD").replace(/^origin\//, "");
      } catch {
        return "main";
      }
    }

    const tool = input.tool || "";

    // --- MCP PR tools ------------------------------------------------------------
    // They do not go through `gh`, so there is no SHA to check: send them to the
    // path that checks.
    if (input.kind === "tool") {
      if (
        /(create|merge|update)_pull_request(?!_review)|pull_request_branch|auto_merge|mark.*ready|(create|merge|ready)_pr(?![a-z0-9])(?!_comment|_review)/i.test(
          tool,
        )
      )
        block(
          `${tool} creates, changes or merges a PR without a debate record. Use gh pr create / gh pr ready / gh pr merge after /objection.`,
          false,
        );
      return ALLOW;
    }

    const rawCommand = input.command || "";
    // Disguised command name (`\gh`, `g\h`, `"gh"`, `'gh'`): to the shell it is
    // the same `gh`.
    const command = rawCommand.replace(/\\([A-Za-z])/g, "$1").replace(/(["'])gh\1(?=\s)/g, "gh");
    if (!/\bgh\b/.test(command)) return ALLOW;

    // --- Text that is not a command --------------------------------------------
    // Heredoc bodies and quoted strings (commit messages, grep patterns, echo)
    // do not run `gh`. But `bash -c '...'`, `eval "..."` and strings with
    // `$(`/backticks do, so those stay.
    function stripHeredocs(s) {
      return s.replace(
        /<<-?[ \t]*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n[\s\S]*?\n[ \t]*\2[ \t]*(?=\n|$|\))/g,
        "<<HEREDOC",
      );
    }

    // Index just past the `)` that closes the `(` at index k (the one right
    // after `$`), skipping quoted text and nested substitutions inside it.
    function substEnd(s, k) {
      let depth = 1;
      for (let p = k + 1; p < s.length; p++) {
        const ch = s[p];
        if (ch === "\\") { p++; continue; }
        if (ch === "'") { const q = s.indexOf("'", p + 1); p = q === -1 ? s.length : q; continue; }
        if (ch === '"') {
          let q = p + 1;
          while (q < s.length && s[q] !== '"') {
            if (s[q] === "\\") q++;
            else if (s[q] === "$" && s[q + 1] === "(") q = substEnd(s, q + 1) - 1;
            q++;
          }
          p = q;
          continue;
        }
        if (ch === "(") depth++;
        if (ch === ")" && --depth === 0) return p + 1;
      }
      return s.length;
    }

    function stripInertText(s) {
      let out = "";
      let i = 0;
      while (i < s.length) {
        const c = s[i];
        if (c === "\\" && i + 1 < s.length) {
          out += s.slice(i, i + 2);
          i += 2;
          continue;
        }
        // Unquoted command substitution. Code that never mentions gh cannot
        // create or merge a PR (short of disguise, LOW), so it becomes a
        // placeholder; otherwise its `)` cut the command short and hid the
        // PR number after it (round 4: `gh pr merge -t $(git log ...) 42`).
        if ((c === "$" && s[i + 1] === "(") || c === "`") {
          const end = c === "`" ? s.indexOf("`", i + 1) + 1 || s.length : substEnd(s, i + 1);
          const code = s.slice(c === "`" ? i + 1 : i + 2, c === "`" ? end - 1 : end - 1);
          out += /\bgh\b/.test(code) ? ` ${code} ` : " '' ";
          i = end;
          continue;
        }
        if (c === "'" || c === '"') {
          let j = i + 1;
          while (j < s.length && s[j] !== c) {
            if (c === '"' && s[j] === "\\") j++;
            else if (c === '"' && s[j] === "$" && s[j + 1] === "(") j = substEnd(s, j + 1) - 1;
            j++;
          }
          const inside = s.slice(i + 1, j);
          const before = out.slice(-80);
          // A quoted value glued to a flag is part of that word for the
          // shell (`--repo="o/r"` is `--repo=o/r`, `-R"o/r"` is `-Ro/r`).
          // The gate needs three of those values (repo, base, head), so
          // they come out as plain `-R o/r` / `--repo=o/r`. Any other glued
          // value (`-t"feat(ui)"`, `--body="a;b"`) becomes a glued '' so
          // its characters cannot cut the command short, and the flag keeps
          // its shape. A round-2 accuser found both: keeping every glued
          // value raw broke `-R"o/r"` and let `(`/`;` inside a subject hide
          // the PR number.
          const glued = i > 0 && !/[\s;&|()`]/.test(s[i - 1]);
          if (glued && !/\s/.test(inside) && !/\$\(|`/.test(inside)) {
            const plain = !/[;&|()`<>]/.test(inside);
            if (plain && /(^|\s)-[RBH]$/.test(out)) out += ` ${inside}`;
            else if (plain && /(^|\s)--(repo|base|head)=$/.test(out)) out += inside;
            else out += "''";
            i = j + 1;
            continue;
          }
          // Allowlist of what executes its argument as code, with only
          // options between the program and the flag (never a script name):
          //   a shell (or $SHELL) then -c, alone or combined (`bash -lc`);
          //   python, su, runuser, script, flock then exactly -c;
          //   node, perl, ruby then exactly -e (`perl -pe`/`-ne` take a
          //   regex, not a command);
          //   eval.
          // Any other -c (grep -c, rg -c, psql -c, tar -czf) is a flag. The
          // round-3 accuser showed the cost of a wider list: counting any
          // quoted word as an interpreter blocked `rg -g "*.md" -c "gh pr
          // create"`. A quoted interpreter (`"$SHELL" -c`) is LOW, not listed.
          const opts = String.raw`(?:\s+-[^\s;&|]*)*`;
          const shell = String.raw`(?:\S*\/)?(?:bash|sh|zsh|dash|ksh|fish|pwsh|powershell|\$\{?SHELL(?::-[^}\s]*)?\}?)`;
          const runsC = String.raw`(?:\S*\/)?(?:python[0-9.]*|su|runuser|script|flock)`;
          const runsE = String.raw`(?:\S*\/)?(?:node|perl|ruby)`;
          const executes =
            new RegExp(String.raw`(^|[\s;&|(\`])${shell}${opts}\s+-[A-Za-z]*c\s*$`).test(before) ||
            new RegExp(String.raw`(^|[\s;&|(\`])${runsC}${opts}\s+-c\s*$`).test(before) ||
            new RegExp(String.raw`(^|[\s;&|(\`])${runsE}${opts}\s+-e\s*$`).test(before) ||
            /(^|[\s;&|(`])eval\s*$/.test(before) ||
            (c === '"' && /\$\(|`/.test(inside));
          // Code is kept only when it mentions gh (see the unquoted case
          // above); an innocent `"$(git log -1 --format=%s)"` becomes ''.
          out += executes && /\bgh\b/.test(inside) ? ` ${stripInertText(inside)} ` : " '' ";
          i = j + 1;
          continue;
        }
        out += c;
        i++;
      }
      return out;
    }

    // When a shell reads its own stdin (`bash <<EOF`, `... | sh`, `sh -s`),
    // heredoc bodies and quoted text ARE commands: nothing is stripped.
    const shellReadsStdin =
      /(^|[\s;&|(`])(?:\S*\/)?(bash|sh|zsh|dash|ksh)\b[^;&|\n]*(<<|<\s*<\(|\s-s\b)/.test(command) ||
      /\|\s*(?:sudo\s+)?(?:\S*\/)?(bash|sh|zsh|dash|ksh)\b/.test(command);
    const noDocs = shellReadsStdin ? command : stripHeredocs(command);
    // In stdin mode quotes become spaces: `echo 'gh pr create' | bash` runs what
    // is inside them, and a quote glued to `gh` would prevent the match.
    const active = shellReadsStdin ? command.replace(/["']/g, " ") : stripInertText(noDocs);

    // --- gh api ------------------------------------------------------------------
    // GraphQL: checked on the WHOLE command, heredoc included (multi-line
    // queries put the mutation on the next line). Queries read from a file
    // (`-F query=@x`, `--input`) cannot be read: always blocked. REST: writing
    // to /pulls (create) or /pulls/<n>/merge, checked per segment (between `;`,
    // `&&`, `|`) so a `-f` from another command in the chain does not count.
    const reGhApi = /(^|[\s;&|(`])(?:\S*\/)?gh\s+api\b/;
    if (reGhApi.test(command) && /\bgraphql\b/.test(command)) {
      if (
        /createPullRequest|mergePullRequest|markPullRequestReadyForReview|enablePullRequestAutoMerge|updatePullRequest/.test(
          command,
        ) ||
        /\s(-F|--field)[\s=]+query=@|\s--input[\s=]/.test(command)
      )
        block("a GraphQL PR mutation (or a query read from a file) skips the debate record. Use gh pr create / gh pr merge after /objection.", false);
    }
    for (const segment of noDocs.split(/\n|;|&&|\|\|?/)) {
      if (!reGhApi.test(segment)) continue;
      const pullsTarget = /\/pulls(?![\w/])|\/pulls\/\d+\/merge/.test(segment);
      const read = /(-X|--method)\s*=?\s*GET\b/i.test(segment);
      const write =
        /(-X|--method)\s*=?\s*(POST|PUT)\b/i.test(segment) ||
        /\s(-f|-F|--field|--raw-field|--input)[\s=]/.test(segment);
      if (pullsTarget && write && !read)
        block("gh api writing to /pulls skips the debate record. Use gh pr create / gh pr merge after /objection.", false);
    }

    // --- gh pr <action> ----------------------------------------------------------
    // `gh` in any command position (start, after ; & | ( $( backtick, `time`,
    // `command`, VAR=x, absolute path), with -R/--repo before or after `pr`.
    const reGh =
      /(?:^|[\s;&|(`])(?:\S*\/)?gh((?:\s+(?:-R\s*=?|--repo(?:\s+|=))\S+)*)\s+pr((?:\s+(?:-R\s*=?|--repo(?:\s+|=))\S+)*)\s+(create|new|ready|merge)\b([^;&|\n)]*)/g;

    const matches = [...active.matchAll(reGh)];
    if (matches.length === 0) return ALLOW;

    function tokens(s) {
      return s.trim().split(/\s+/).filter(Boolean);
    }

    // `gh pr merge|ready` flags that consume the next token.
    const TAKES_VALUE = new Set([
      "-R", "--repo", "-t", "--subject", "-b", "--body", "-F", "--body-file",
      "-A", "--author-email", "--match-head-commit",
    ]);

    function repoOf(globals, rest) {
      const toks = [...tokens(globals), ...tokens(rest)];
      for (let k = 0; k < toks.length; k++) {
        const t = toks[k];
        if (t === "-R" || t === "--repo") return toks[k + 1];
        if (t.startsWith("--repo=")) return t.slice(7);
        // Short flag with its value attached, as gh accepts: -Ro/r, -R=o/r.
        if (/^-R./.test(t)) return t.slice(2).replace(/^=/, "");
      }
      return null;
    }

    function targetOf(rest) {
      const toks = tokens(rest);
      for (let k = 0; k < toks.length; k++) {
        const t = toks[k];
        if (TAKES_VALUE.has(t)) {
          k++;
          continue;
        }
        if (t.startsWith("-")) continue;
        if (t === "''") continue;
        return t;
      }
      return null;
    }

    function valueOf(rest, ...names) {
      const toks = tokens(rest);
      for (let k = 0; k < toks.length; k++) {
        for (const n of names) {
          if (toks[k] === n) return toks[k + 1];
          if (toks[k].startsWith(`${n}=`)) return toks[k].slice(n.length + 1);
          // Short flag with its value attached: -Bmain, -Hfeat/x.
          if (/^-[A-Za-z]$/.test(n) && toks[k].length > 2 && toks[k].startsWith(n))
            return toks[k].slice(2).replace(/^=/, "");
        }
      }
      return null;
    }

    // Directory `gh` will run in: the last `cd` before it.
    function dirBefore(pos) {
      const before = active.slice(0, pos);
      // Cases where gh's directory is not the last visible `cd`: a subshell
      // whose `cd` closed before it, `pushd`, `env -C`, or a `cd` inside quoted
      // text shifting the count. Without certainty about the directory, the
      // record checked could belong to another repository.
      const nActive = [...active.matchAll(/(?:^|[\s;&|(])cd\s/g)].length;
      const nOriginal = [...noDocs.matchAll(/(?:^|[\s;&|(])cd\s/g)].length;
      if (
        /\(\s*cd\b[^)]*\)/.test(before) ||
        /(^|[\s;&|(])(pushd|popd)\b/.test(before) ||
        /(^|[\s;&|(])env\b[^;&|\n]*\s(-C|--chdir)\b/.test(before) ||
        nActive !== nOriginal
      )
        block("cannot tell which directory gh will run in. Run gh on its own, after a plain cd (or from the right directory).");
      let dir = sessionDir;
      // Searched in the active text, where `pos` was measured. Quoted paths
      // became '' there, so the path is read from the original, in the same
      // order.
      const reCdActive = /(?:^|[\s;&|(])cd\s+('')?([^\s;&|)]*)/g;
      const reCdOriginal = /(?:^|[\s;&|(])cd\s+("([^"]+)"|'([^']+)'|([^\s;&|)]+))/g;
      const n = [...active.slice(0, pos).matchAll(reCdActive)].length;
      if (n > 0) {
        const m = [...noDocs.matchAll(reCdOriginal)][n - 1];
        if (m) {
          let p = m[2] || m[3] || m[4];
          if (p.startsWith("~")) p = join(process.env.HOME || "", p.slice(1));
          dir = isAbsolute(p) ? p : resolve(dir, p);
        }
      }
      return dir;
    }

    /** PR head SHA and base branch, from GitHub. */
    function fromPr(dir, repo, target) {
      const args = ["pr", "view"];
      if (target) args.push(target);
      if (repo) args.push("-R", repo);
      args.push("--json", "headRefOid,baseRefName", "-q", '.headRefOid + " " + .baseRefName');
      const [sha, base] = execFileSync("gh", args, {
        cwd: dir,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 15000,
      })
        .trim()
        .split(/\s+/);
      if (!sha || !base) throw new Error("gh answered without sha/base");
      return { sha, base };
    }

    // The record counts by its LAST verdict line, the same one stamp.sh reads.
    // It also needs the stamp that only stamp.sh writes on the first line, with
    // the SHA and the base the diff was debated against: a file written by hand
    // into `.git/objection/` does not count, and a record debated against one base
    // does not release a PR to another base (different diff, different accusers).
    function approved(common, sha, prBase) {
      const file = join(common, "objection", `${sha}.md`);
      if (!existsSync(file)) return `no /objection record for commit ${sha.slice(0, 7)}.`;
      const text = readFileSync(file, "utf8");
      const stamp = /^<!-- objection: sha=([0-9a-f]{40}) base=(\S+) -->$/m.exec(text.split("\n")[0] || "");
      if (!stamp || stamp[1] !== sha)
        return `the record for ${sha.slice(0, 7)} was not written by stamp.sh (${file}).`;
      if (prBase && stamp[2] !== `origin/${prBase}`)
        return `the record for ${sha.slice(0, 7)} was debated against ${stamp[2]}, but the PR targets ${prBase}. Run /objection against origin/${prBase}.`;
      const verdicts = text.split("\n").filter((l) => /^VERDICT: /.test(l));
      if (verdicts.at(-1) !== "VERDICT: APPROVED")
        return `the record for ${sha.slice(0, 7)} is not APPROVED (${file}).`;
      return null;
    }

    for (const m of matches) {
      const [, ghGlobals, prGlobals, rawAction, rest] = m;
      const globals = `${ghGlobals} ${prGlobals}`;
      const action = rawAction === "new" ? "create" : rawAction;
      // Help and disabling auto-merge touch no PR.
      if (/(^|\s)(--help|-h)\b/.test(rest)) continue;
      if (action === "merge" && /(^|\s)--disable-auto\b/.test(rest)) continue;
      // Target from stdin (`... | xargs gh pr merge`): the hook would check the
      // current branch's PR while another one gets merged.
      if (/\bxargs\b[^;&|\n]*$/.test(active.slice(0, m.index + 1)))
        block("gh pr merge/ready through xargs hides which PR it is. Put the PR number in the command itself.", false);
      const dir = dirBefore(m.index);
      const repo = repoOf(globals, rest);

      if (action === "merge" && /(^|\s)--auto\b/.test(rest))
        block("gh pr merge --auto lets in commits pushed after the debate. Merge without --auto, with the record for the current SHA.", false);

      let common;
      try {
        common = git(dir, "rev-parse", "--path-format=absolute", "--git-common-dir");
      } catch {
        block(`could not find a git repository at ${dir}.`);
      }

      let sha;
      let prBase;
      try {
        if (action === "create") {
          const head = valueOf(rest, "-H", "--head");
          // `--head owner:branch` points at a fork: no local copy, no record.
          sha = git(dir, "rev-parse", head ? head.replace(/^[^:]+:/, "") : "HEAD");
          // Without --base, gh uses the repository default branch.
          prBase = valueOf(rest, "-B", "--base") || defaultBase(dir);
          // The PR is born from what is on the remote, not the local HEAD.
          if (!head) {
            let remote = null;
            try {
              remote = git(dir, "rev-parse", "@{u}");
            } catch {
              remote = null;
            }
            if (remote && remote !== sha)
              block(`the branch remote is at ${remote.slice(0, 7)} but the debate was about ${sha.slice(0, 7)}. Push the debated commit before opening the PR.`, false);
          }
        } else {
          ({ sha, base: prBase } = fromPr(dir, repo, targetOf(rest)));
        }
      } catch (e) {
        if (e instanceof Blocked) throw e;
        block(
          action === "create"
            ? `could not read the commit going into the PR at ${dir}.`
            : `could not read the head SHA of PR ${targetOf(rest) || "for the current branch"}${repo ? ` in ${repo}` : ""}.`,
        );
      }

      const problem = approved(common, sha, prBase);
      if (problem) block(problem);
    }

    return ALLOW;
  } catch (e) {
    if (e instanceof Blocked) return { blocked: true, reason: e.reason, hint: e.withHint };
    throw e;
  }
}
