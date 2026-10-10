#!/usr/bin/env node
// designer/theme-default-probe.mjs  the engine's theme-default contract, in a real browser.
//
// the contract has two rules, and both must agree with the pre-paint prelude:
//   1. a stored choice wins outright;
//   2. with NO stored choice, the attributes the SERVER rendered are the default —
//      not storing a choice is not the same as choosing nothing.
//
// rule 2 is the one that regressed: `reflect()` overrode a server-rendered `data-theme`
// with `system` on every fresh client, so a host's server-side default mode was silently
// discarded. the scheme half was fixed in 8c72e86; the prelude had both shapes right from
// the start. this probe is the gate.
//
// the page under test is served by WebUIShowcaseServer, but the probe stamps the
// `data-scheme`/`data-theme` a HOST would have server-rendered onto <html> via route
// interception — so the default is deterministic and the engine's boot is the only
// variable.
//
// usage: node designer/theme-default-probe.mjs
//   spawns WebUIShowcaseServer on :9093, runs two browser contexts, tears down.
//   exits non-zero on failure. needs `playwright` resolvable from the repo root.

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9093;
const BASE = `http://127.0.0.1:${PORT}`;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

async function ping() {
  try {
    const res = await fetch(BASE + "/", { signal: AbortSignal.timeout(1500) });
    return res.ok;
  } catch {
    return false;
  }
}

async function waitForServer(timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) { return null; }   // the spawn died: bad port, bad binary
    if (await ping()) { return true; }
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

// pre-flight: a server left over from an earlier run would answer `ping()` and silently
// become the system under test — the instrument would be measuring the wrong bytes.
if (await ping()) {
  console.log(`  FAIL probe precondition: something is already serving :${PORT}`);
  console.log("       a stale server would invalidate this probe — kill it and re-run.");
  process.exit(1);
}

const server = spawn(join(ROOT, ".build/debug/WebUIShowcaseServer"), ["--port", String(PORT)], {
  cwd: ROOT,
  stdio: ["ignore", "pipe", "pipe"],
});
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

/// SIGTERM, then wait for the process to exit for real — a probe that returns while its
/// server still holds the port poisons the next run (measured: exactly that).
async function stopServer() {
  if (server.exitCode !== null) { return; }
  server.kill("SIGTERM");
  const deadline = Date.now() + 3000;
  while (server.exitCode === null && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 100));
  }
  if (server.exitCode === null) {
    server.kill("SIGKILL");
    await new Promise((r) => setTimeout(r, 300));
  }
}

// what a host's server-side render would put on <html>.
const SERVER_ATTRS = ' data-scheme="poseidon" data-theme="dark"';

// The page under test is synthesised, but served from the showcase's origin so that
// `/ui/webui-engine.js` resolves. Synthesised because the showcase's own page renders its
// own theme plumbing and the prelude; on a page that carries no theme attributes at all a
// bug in the engine's fallback is invisible. Here the ONLY code that touches the theme
// attributes is the engine (plus the host's server-rendered attributes), which is what
// makes these assertions about the engine and nothing else.
const PAGE_BODY = `<!DOCTYPE html>
<html lang="en"${SERVER_ATTRS}>
<head>
  <meta name="webui-config" content="{}">
  <script src="/ui/webui-engine.js"></script>
</head>
<body><p>theme-default probe</p></body>
</html>`;

const browser = await chromium.launch();

async function stamp(page) {
  await page.route(BASE + "/", (route) =>
    route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: PAGE_BODY })
  );
}

async function bootState(context) {
  const page = await context.newPage();
  await stamp(page);
  await page.goto(BASE + "/", { waitUntil: "load" });
  await page.waitForFunction(() => typeof window.WebUIEngine !== "undefined", null, { timeout: 5000 });
  await page.waitForTimeout(200);
  const state = await page.evaluate(() => ({
    scheme: document.documentElement.getAttribute("data-scheme"),
    theme: document.documentElement.getAttribute("data-theme"),
    lsTheme: localStorage.getItem("webui-theme"),
    lsScheme: localStorage.getItem("webui-scheme"),
  }));
  await page.close();
  return state;
}

try {
  if ((await waitForServer()) === null) {
    bad(`showcase server did not become ready on :${PORT}`);
    console.log(serverLog.split("\n").slice(-6).join("\n"));
    process.exit(1);
  }
  ok(`showcase server ready on :${PORT}`);

  // 1. fresh client, no stored choice: the server-rendered default survives, both axes.
  const fresh = await bootState(await browser.newContext());
  console.log(`  observed: ${JSON.stringify(fresh)}`);
  fresh.theme === "dark"
    ? ok("fresh client keeps the server-rendered mode (dark)")
    : bad(`fresh client discarded the server-rendered mode: data-theme=${fresh.theme} (expected dark)`);
  fresh.scheme === "poseidon"
    ? ok("fresh client keeps the server-rendered scheme (poseidon)")
    : bad(`fresh client discarded the server-rendered scheme: data-scheme=${fresh.scheme} (expected poseidon)`);
  fresh.lsTheme === null && fresh.lsScheme === null
    ? ok("a fresh client persists nothing — no choice is not stored as a choice")
    : bad(`a fresh client wrote storage: theme=${fresh.lsTheme} scheme=${fresh.lsScheme}`);

  // 2. a stored choice wins over the server's default.
  const context = await browser.newContext();
  await context.addInitScript(() => {
    localStorage.setItem("webui-theme", "light");
    localStorage.setItem("webui-scheme", "dracula");
  });
  const chosen = await bootState(context);
  console.log(`  observed: ${JSON.stringify(chosen)}`);
  chosen.theme === "light" && chosen.scheme === "dracula"
    ? ok("a stored choice overrides the server-rendered default (light / dracula)")
    : bad(`stored choice not applied: data-theme=${chosen.theme} data-scheme=${chosen.scheme}`);
} finally {
  await browser.close();
  await stopServer();
}

console.log("");
console.log(`=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "THEME DEFAULT PROBE PASS" : "THEME DEFAULT PROBE FAIL");
process.exit(fail === 0 ? 0 : 1);