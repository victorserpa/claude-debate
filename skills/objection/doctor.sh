#!/bin/bash
# Says what is set up and what is missing, before a debate finds out.
#
#   doctor.sh            run inside the repository
#
# Checks, one line each (ok, warn or FAIL):
#   tools      git, node, perl; which reviewer CLIs exist (claude, codex,
#              gemini), since none means the subagent path
#   config     the file the rules come from (the base branch, as brief.sh
#              reads it), valid JSON, known keys, the types and regexes
#              objection.schema.json describes, defaultBase among bases
#   local gate the hook files per agent, and the trust step Codex and
#              Gemini need before they run a project hook at all
#   CI         a workflow that runs the check, and (with gh) whether the
#              "record" check is required on the default base
#   records    whether HEAD already has a stamped record
# Reads only: nothing is written, nothing is sent except the gh API read.
# Exit 1 when any line is FAIL.
set -u

fails=0
ok() { printf 'ok    %s\n' "$*"; }
warn() { printf 'warn  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

here="$(cd "$(dirname "$0")" && pwd)"
gh_bin="${OBJECTION_GH_BIN:-gh}"
# "origin/main:.objection.json" must reach git whole: Git Bash on Windows
# would rewrite it as a path list (same wrapper as brief.sh).
gitref() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' git "$@"; }

# tools
for t in git node perl; do
  command -v "$t" >/dev/null 2>&1 && ok "$t: $(command -v "$t")" || bad "$t not found: objection needs it"
done
command -v node >/dev/null 2>&1 || { echo "cannot go on without node."; exit 1; }
clis=""
for c in claude codex gemini; do
  v="OBJECTION_$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')"
  bin="${!v:-$c}"
  command -v "$bin" >/dev/null 2>&1 && clis="$clis $c"
done
case "$clis" in
  *claude* | *codex*) ok "reviewer CLIs:$clis" ;;
  *gemini*) warn "reviewer CLIs:$clis (gemini runs only when a reviewers entry or OBJECTION_RUNNER asks for it: without claude or codex, the debate falls back to subagents)" ;;
  *) warn "no reviewer CLI (claude, codex, gemini): the debate runs the roles as subagents, not as isolated processes" ;;
esac

top=$(git rev-parse --show-toplevel 2>/dev/null) || { bad "not inside a git repository"; echo; echo "doctor: $fails problem(s)."; exit 1; }
cd "$top" || exit 1

# config: validated as the debates read it. brief.sh takes the rules from
# origin/<defaultBase> and falls back to the working copy only when the
# base has none, so that is the copy checked first; a working copy that
# differs is checked too, as what applies after its merge.
validate() { # text label -> prints its lines, counts FAILs; sets v_base
  local report problems
  report=$(printf '%s' "$1" | node -e '
let raw = "";
process.stdin.on("data", (d) => (raw += d)).on("end", () => {
  const out = [];
  const fail = (m) => out.push("FAIL\t" + m);
  const warn = (m) => out.push("warn\t" + m);
  let c;
  try { c = JSON.parse(raw); } catch (e) { fail(`not valid JSON (${e.message}): brief.sh reads no rules from it`); console.log(out.join("\n")); return; }
  if (!c || typeof c !== "object" || Array.isArray(c)) { fail("not a JSON object"); console.log(out.join("\n")); return; }
  const known = ["$schema", "bases", "defaultBase", "verify", "budget", "invariants", "reviewers", "models", "strongPaths", "smallDiff", "enforce", "precedents"];
  for (const k of Object.keys(c)) if (!known.includes(k)) warn(`unknown key "${k}": ignored (a typo? known: ${known.slice(1).join(", ")})`);
  const regex = (where, v) => { try { new RegExp(v); } catch (e) { fail(`${where}: invalid regex ${JSON.stringify(v)}: that rule is never checked`); } };
  const strs = (v) => Array.isArray(v) && v.every((x) => typeof x === "string" && x.length);
  if (!strs(c.bases) || !c.bases.length) fail("bases must be a list of branch names");
  if (c.defaultBase !== undefined && (typeof c.defaultBase !== "string" || (strs(c.bases) && !c.bases.includes(c.defaultBase))))
    fail(`defaultBase ${JSON.stringify(c.defaultBase)} is not one of bases`);
  if (c.verify !== undefined && !strs(c.verify)) fail("verify must be a list of commands");
  if (strs(c.verify) && !c.verify.length) warn("verify is empty: add the cheapest checks (types, tests)");
  if (c.verify === undefined) warn("no verify: add the cheapest checks (types, tests)");
  if (c.budget !== undefined && !["lean", "standard", "thorough"].includes(c.budget)) fail(`budget ${JSON.stringify(c.budget)} is not lean, standard or thorough: lean is used`);
  for (const [key, need] of [["invariants", ["rule", "paths"]], ["reviewers", ["paths"]]]) {
    const extra = key === "invariants" ? ["verify"] : ["agent", "focus"];
    if (c[key] === undefined) continue;
    if (!Array.isArray(c[key])) { fail(`${key} must be a list`); continue; }
    c[key].forEach((x, n) => {
      const at = `${key}[${n}]`;
      if (!x || typeof x !== "object") return fail(`${at} must be an object`);
      for (const r of need) if (typeof x[r] !== "string" || !x[r]) fail(`${at} needs "${r}"`);
      for (const k of Object.keys(x)) if (!need.includes(k) && !extra.includes(k)) warn(`${at}: unknown key "${k}": ignored`);
      if (typeof x.paths === "string") regex(`${at}.paths`, x.paths);
    });
  }
  if (c.strongPaths !== undefined) typeof c.strongPaths === "string" ? regex("strongPaths", c.strongPaths) : fail("strongPaths must be a regex string");
  if (c.models !== undefined) {
    const mk = ["default", "strong", "effort", "strongEffort", "defender", "laterEffort"];
    if (!c.models || typeof c.models !== "object") fail("models must be an object");
    else for (const [k, v] of Object.entries(c.models)) {
      if (!mk.includes(k)) warn(`models: unknown key "${k}": ignored`);
      else if (typeof v !== "string" || !/^[A-Za-z0-9._-]+$/.test(v)) fail(`models.${k} ${JSON.stringify(v)} is not a model or effort name: the default is used`);
    }
  }
  if (c.smallDiff !== undefined && !(Number.isInteger(c.smallDiff) && c.smallDiff >= 0)) fail("smallDiff must be a whole number, 0 or more: 20 is used");
  if (c.enforce !== undefined && typeof c.enforce !== "boolean") fail("enforce must be true or false");
  if (c.enforce === false) warn("enforce is false: advisory mode, the local hook blocks nothing");
  if (c.precedents !== undefined && typeof c.precedents !== "boolean") fail("precedents must be true or false");
  out.push(`base\t${c.defaultBase || (strs(c.bases) && c.bases[0]) || ""}`);
  console.log(out.join("\n"));
});')
  if [ -z "$report" ]; then bad "config ($2): the validator did not run"; return; fi
  v_base=$(printf '%s\n' "$report" | sed -n 's/^base	//p')
  problems=$(printf '%s\n' "$report" | grep -v '^base	' | grep -c . || true)
  while IFS="$(printf '\t')" read -r level msg; do
    [ -n "$level" ] || continue
    if [ "$level" = FAIL ]; then bad "config ($2): $msg"; else warn "config ($2): $msg"; fi
  done <<EOF_REPORT
$(printf '%s\n' "$report" | grep -v '^base	')
EOF_REPORT
  [ "$problems" = 0 ] && ok "config ($2): valid"
}
cfg_text=""
cfg_file=""
for c in .objection.json .claude/objection.json; do
  [ -f "$c" ] && { cfg_text=$(cat "$c"); cfg_file="$c"; break; }
done
# The base is named by the config itself: the working copy's, else main.
base=$(printf '%s' "$cfg_text" | node -e 'let r="";process.stdin.on("data",(d)=>(r+=d)).on("end",()=>{try{const c=JSON.parse(r);console.log(c.defaultBase||(c.bases||[])[0]||"")}catch{console.log("")}})')
[ -n "$base" ] || base=main
on_base=""
base_file=""
if git rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null; then
  for c in .objection.json .claude/objection.json; do
    on_base=$(gitref show "origin/$base:$c" 2>/dev/null) && [ -n "$on_base" ] && { base_file="$c"; break; }
    on_base=""
  done
fi
v_base=""
if [ -n "$base_file" ]; then
  validate "$on_base" "$base_file on origin/$base, what debates use"
  base_named="$v_base"
  if [ -z "$cfg_file" ]; then
    warn "config: the working copy has no $base_file (deleted on this branch?); debates still use origin/$base's"
  elif [ "$cfg_text" != "$on_base" ]; then
    validate "$cfg_text" "$cfg_file in the working copy, used once merged"
  fi
elif [ -n "$cfg_file" ]; then
  validate "$cfg_text" "$cfg_file in the working copy; origin/$base has none yet, so debates use this one until it is merged"
else
  bad "no .objection.json: this repository is not opted in (run /objection init)"
fi
base="${base_named:-${v_base:-$base}}"

# local gate: the hook files each agent reads.
hooks=""
grep -qs 'gate/hook.mjs' .claude/settings.json && hooks="$hooks claude"
grep -qs 'gate/hook.mjs' .cursor/hooks.json && hooks="$hooks cursor"
grep -qs 'gate/hook.mjs' .codex/hooks.json && hooks="$hooks codex"
grep -qs 'gate/hook.mjs' .gemini/settings.json && hooks="$hooks gemini"
if [ -n "$hooks" ]; then
  ok "local gate hooks:$hooks"
  case "$hooks" in *codex*) warn "codex: the hook runs only once trusted (open codex here once and trust it); an untrusted hook is skipped silently" ;; esac
  case "$hooks" in *gemini*) warn "gemini: project hooks run only in a trusted folder; an untrusted one skips them silently" ;; esac
else
  warn "no hook file in this repository: the local gate is the Claude Code plugin's hook, if installed (other agents: init.sh --host cursor|codex|gemini)"
fi

# CI: a workflow that runs the check, and whether it is required.
# objection's own repository runs its action as `uses: ./`.
own=""
grep -qs '^name: Objection' action.yml && grep -qs 'uses: \./$' .github/workflows/*.yml && own=yes
if [ -n "$own" ] || grep -qsl 'victorserpa/objection\|gate/check-pr.mjs' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null; then
  ok "CI: a GitHub workflow runs the record check"
  if [ -n "${base:-}" ] && command -v "$gh_bin" >/dev/null 2>&1 &&
    required=$("$gh_bin" api "repos/{owner}/{repo}/rules/branches/$base" -q '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null); then
    # Rulesets, plus classic branch protection (a 404 when there is none).
    required="$required
$("$gh_bin" api "repos/{owner}/{repo}/branches/$base/protection/required_status_checks" -q '.contexts[]' 2>/dev/null)"
    printf '%s\n' "$required" | grep -qx record && ok "CI: \"record\" is a required check on $base" ||
      warn "CI: \"record\" is not a required check on $base, so a PR can merge without it (Settings > Rules)"
  else
    warn "CI: could not read the rules of ${base:-the base} (no gh, or no access): check that \"record\" is required"
  fi
elif [ -f .gitlab/objection.gitlab-ci.yml ]; then
  ok "CI: the GitLab job file exists (include it from .gitlab-ci.yml, and turn on Pipelines must succeed)"
else
  warn "CI: no workflow runs the check, so nothing outside the agent's machine enforces the record"
fi

# records
sha=$(git rev-parse HEAD 2>/dev/null) && dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)/objection"
if [ -n "${sha:-}" ] && [ -f "$dir/$sha.md" ]; then
  ok "records: HEAD (${sha:0:7}) has a stamped record: $(grep '^VERDICT:' "$dir/$sha.md" 2>/dev/null | tail -n 1)"
else
  ok "records: none for HEAD yet (debate before the PR)"
fi

echo
if [ "$fails" -gt 0 ]; then
  echo "doctor: $fails problem(s) to fix."
  exit 1
fi
echo "doctor: nothing blocks a debate here."
