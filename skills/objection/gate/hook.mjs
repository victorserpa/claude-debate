#!/usr/bin/env node
// Pre-tool hook adapter for the objection gate. One script, several hosts:
//
//   node hook.mjs                  Claude Code  (PreToolUse, matcher Bash|mcp__.*)
//   node hook.mjs --host codex     Codex CLI    (PreToolUse, .codex/hooks.json)
//   node hook.mjs --host gemini    Gemini CLI   (BeforeTool, .gemini/settings.json)
//   node hook.mjs --host cursor    Cursor       (beforeShellExecution and beforeMCPExecution)
//
// All four accept "exit 2 + reason on stderr" as a block. Cursor also gets
// its JSON verdict on stdout ({"permission":"deny", ...}) so the reason
// reaches both the user and the agent.
//
// Input shapes this reads (from each host's docs):
//   Claude / Codex / Gemini: { tool_name, tool_input: { command }, cwd }
//   Cursor shell:            { command, cwd }
//   Cursor MCP:              { tool_name, tool_input, mcp_server_name }
// Anything carrying a command string is a shell call; anything else with a
// tool name is checked by name (tools that create or merge PRs).
//
// The logic lives in core.mjs, shared with check-pr.mjs (the GitHub check
// that covers hosts without hooks).

import { readFileSync } from "node:fs";
import { gate, HINT } from "./core.mjs";

const hostArg = process.argv.indexOf("--host");
const host = hostArg > -1 ? process.argv[hostArg + 1] : "claude";

function deny(reason, withHint) {
  const text = `[objection] Blocked: ${reason}${withHint ? `\n[objection] ${HINT}` : ""}`;
  if (host === "cursor")
    process.stdout.write(
      JSON.stringify({ continue: true, permission: "deny", userMessage: text, agentMessage: text }),
    );
  process.stderr.write(`${text}\n`);
  process.exit(2);
}

let raw = "";
try {
  raw = readFileSync(0, "utf8");
} catch {
  process.exit(0);
}

let input;
try {
  input = JSON.parse(raw);
} catch {
  // Unreadable input: only block if it looks PR-related, so a change in a
  // host's input format does not stop every command.
  if (/\bgh\b|pull_request|auto_merge/.test(raw))
    deny("could not parse the hook input to check the debate record.", true);
  process.exit(0);
}

const command =
  (typeof input.command === "string" && input.command) ||
  (input.tool_input && typeof input.tool_input.command === "string" && input.tool_input.command) ||
  "";
const cwd =
  input.cwd ||
  process.env.CLAUDE_PROJECT_DIR ||
  process.env.CURSOR_PROJECT_DIR ||
  process.env.GEMINI_PROJECT_DIR ||
  process.cwd();

const call = command
  ? { kind: "shell", command, cwd }
  : { kind: "tool", tool: input.tool_name || "", cwd };

const result = gate(call);
if (result.blocked) deny(result.reason, result.hint);
// Advisory mode: allowed, and both the agent (stderr) and the user hear why
// it would have been blocked.
const note = result.warning ? `[objection] Advisory (enforce is false), would block: ${result.warning}` : "";
if (note) process.stderr.write(`${note}\n`);
if (host === "cursor")
  process.stdout.write(JSON.stringify({ continue: true, permission: "allow", ...(note && { userMessage: note, agentMessage: note }) }));
else if (note && host === "claude") process.stdout.write(JSON.stringify({ systemMessage: note }));
process.exit(0);
