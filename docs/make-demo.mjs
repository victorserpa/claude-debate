// Builds docs/demo.svg: an animated terminal replaying a real debate
// (a toy cart with a planted bug, run on sonnet through debate.sh; the
// numbers and findings below are that run's). node docs/make-demo.mjs
import { writeFileSync } from "node:fs";

const C = { cmd: "#e6edf3", dim: "#8b949e", red: "#ff7b72", ora: "#ffa657", grn: "#7ee787", blu: "#79c0ff", yel: "#e3b341" };
// [delay before the line (s), color, text]
const scene = [
  [0.4, C.dim, "# the agent added fixed-amount coupons to a cart; invariant: a total is never negative"],
  [1.2, C.cmd, "$ bash debate.sh main \"Add fixed-amount coupons\""],
  [1.4, C.dim, "objection: accuser used 2708 input + 632 output tokens ($0.010)"],
  [0.5, C.dim, "objection: defender used 3168 input + 292 output tokens ($0.008)"],
  [0.5, C.cmd, "findings: 1 BLOCKER, 1 HIGH, 1 MEDIUM, 0 LOW"],
  [0.7, C.red, " 1 BLOCKER  cart.js:10  $10 off a $4 cart: total = -600 (invariant broken)"],
  [0.5, C.ora, " 2 HIGH     cart.js:10  amount: 0 falls through to percent: total = NaN"],
  [0.5, C.blu, " defender:  UPHELD both: no clamp anywhere (cart.js:4)"],
  [1.4, C.cmd, "$ gh pr create --base main --fill"],
  [0.6, C.red, "[objection] Blocked: no /objection record for commit 2b5d414."],
  [1.6, C.dim, "# the agent fixes both, runs round 2 on the fix only"],
  [0.9, C.cmd, "$ bash debate.sh --since 2b5d414 main"],
  [1.2, C.ora, " 1 HIGH     cart.js:10  amount: NaN still passes the check: total = NaN"],
  [1.2, C.dim, "# fixed again; the session judges every finding, then stamps the record"],
  [0.9, C.cmd, "$ bash stamp.sh record.md"],
  [0.6, C.grn, "record stored for 69e9b18   VERDICT: APPROVED"],
  [1.0, C.cmd, "$ gh pr create --base main --fill"],
  [0.6, C.grn, "(allowed: gh runs and opens the PR)"],
  [0.8, C.yel, "3 real bugs caught before the PR existed: 2 rounds, $0.041 of reviewers"],
];
const hold = 5; // seconds the full screen stays before the loop restarts
const lineH = 22, top = 52, W = 940;
const H = top + scene.length * lineH + 18;
let t = 0;
const times = scene.map(([d]) => (t += d));
const total = t + hold;
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const pct = (x) => ((x / total) * 100).toFixed(2);
let css = "", body = "";
scene.forEach(([, color, text], i) => {
  const on = pct(times[i]);
  css += `@keyframes l${i}{0%,${on}%{opacity:0}${(Number(on) + 0.01).toFixed(2)}%,98%{opacity:1}100%{opacity:0}}.l${i}{animation:l${i} ${total.toFixed(1)}s linear infinite}\n`;
  body += `<text class="l${i}" x="20" y="${top + i * lineH}" fill="${color}">${esc(text)}</text>\n`;
});
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="objection catches a negative cart total and a NaN, blocks the PR, then approves it after the fixes">
<style>
text{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13.5px;white-space:pre;opacity:0}
@media (prefers-reduced-motion: reduce){text{animation:none!important;opacity:1}}
${css}</style>
<rect width="${W}" height="${H}" rx="10" fill="#0d1117"/>
<circle cx="22" cy="20" r="6" fill="#ff5f57"/><circle cx="42" cy="20" r="6" fill="#febc2e"/><circle cx="62" cy="20" r="6" fill="#28c840"/>
<text x="${W / 2}" y="24" fill="#8b949e" text-anchor="middle" style="opacity:1">objection: a real debate on a toy cart</text>
${body}</svg>
`;
writeFileSync(new URL("./demo.svg", import.meta.url), svg);
console.log(`docs/demo.svg: ${scene.length} lines, ${total.toFixed(1)}s loop`);
