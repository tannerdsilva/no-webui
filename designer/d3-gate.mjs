#!/usr/bin/env node
// designer/d3-gate.mjs  the i3 gate harness (lane B, wave 3).
//
// ONE COMMAND measures the three desktop-grade gates on lane ports
// (9200–9219), each against the plan's explicit budgets:
//
//   1. FEED-10K SCROLL p95 (plan §5: "60 fps / p95 ≤ 20 ms")
//      naive full-list (/bench/feed?items=10000)
//      + windowed variants (/bench/feed?windowed=1[&ops=1]&items=10000)
//      loopback AND throttled (recipe 6: 80 ms rtt — a loopback-only green
//      is not a green). the naive full-render wall (~62 ms p95) is the
//      honest recorded baseline; the windowed variants are where the budget
//      is reachable today.
//
//   2. GRID ECHO < 50 ms @ 80 ms rtt (plan §5 "keystroke echo < 50 ms at
//      80 ms rtt"): the t1.4 ENGINE-LOCAL echo contract (data-webui-echo)
//      — an echo source wired to a target, driven under an 80 ms rtt link.
//      because the echo is engine-local (zero ws frames), it must land in
//      well under 50 ms even when the wire is slow; a server round trip at
//      80 ms rtt can never pass this gate (≥ debounce + 160 ms).
//
//   3. DEGRADE (island artifact absent → server rendering intact): a
//      data-webui-island region whose .wasm is NOT served (404) must stay
//      unmapped, keep its server-rendered content, and leave the engine
//      instance alive (t2.6). absence must degrade, never blank.
//
// invocation:
//   node designer/d3-gate.mjs [--bench-port 9210] [--probe-port 9211]
//                             [--items 10000] [--throttle 80] [--echo-chars 16]
// the WebUIBench binary may be overridden: WEBUI_BENCH_SERVER=/path.
// writes .bench/d3-gate.json; exit non-zero on a gate failure.
// NOTE: this gate cannot fully pass until the desktop-grade windowing /
// echo / island living in E/D's work merged at i2 is in the tree — it is
// now (f9faaba), so the harness asserts for real; every FAIL is recorded
// in the json, never papered over.

import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./probes/e-lib.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SERVER = process.env.WEBUI_BENCH_SERVER ?? join(ROOT, ".build/debug/WebUIBench");

// ── args ────────────────────────────────────────────────────────────────────
function arg(argv, name, fallback) {
  const i = argv.indexOf(name);
  return i !== -1 && argv[i + 1] !== undefined ? argv[i + 1] : fallback;
}
const argv = process.argv.slice(2);
const BENCH_PORT = parseInt(arg(argv, "--bench-port", "9210"), 10);
const PROBE_PORT = parseInt(arg(argv, "--probe-port", "9211"), 10);
const ITEMS = parseInt(arg(argv, "--items", "10000"), 10);
const THROTTLE = parseInt(arg(argv, "--throttle", "80"), 10);
const ECHO_CHARS = parseInt(arg(argv, "--echo-chars", "16"), 10);
// plan §5 budgets (the gate ceilings)
const SCROLL_P95_CEILING_MS = 20;
const ECHO_P95_CEILING_MS = 50;

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const results = { gate: "d3", generated: new Date().toISOString(), ports: { bench: BENCH_PORT, probe: PROBE_PORT }, checks: {} };

// ── stats ───────────────────────────────────────────────────────────────────
function percentile(sorted, p) {
  if (!sorted.length) return null;
  const idx = (p / 100) * (sorted.length - 1);
  const lo = Math.floor(idx), hi = Math.ceil(idx);
  if (lo === hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
}
function stats(samples) {
  const s = [...samples].sort((a, b) => a - b);
  return { n: s.length, p50: percentile(s, 50), p95: percentile(s, 95), p99: percentile(s, 99) };
}

// ── WebUIBench lifecycle ────────────────────────────────────────────────────
const bench = spawn(SERVER, ["--port", String(BENCH_PORT)], { cwd: ROOT });
let benchLog = "";
bench.stdout.on("data", (d) => (benchLog += d));
bench.stderr.on("data", (d) => (benchLog += d));
function teardown() {
  try { bench.kill("SIGTERM"); } catch { /* gone */ }
  try { probeClose && probeClose(); } catch { /* gone */ }
}
process.on("exit", teardown);
process.on("SIGINT", () => { teardown(); process.exit(130); });
process.on("SIGTERM", () => { teardown(); process.exit(143); });

async function waitFor(url, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try { const r = await fetch(url); if (r.ok) return true; } catch { /* booting */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

// ── throttle (recipe 6) ─────────────────────────────────────────────────────
async function withThrottle(context, page, latency, fn) {
  const cdp = await context.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", {
    offline: false, latency,
    downloadThroughput: 10 * 1024 * 1024,
    uploadThroughput: 5 * 1024 * 1024,
  });
  try { return await fn(); } finally {
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1,
    });
  }
}

// ── metric 1: scroll p95 (rAF sampler + wheel, scrolls a target element) ────
// `scrollable` is a page-eval expression selecting the scroll container
// (document for the naive feed; #feed-window for the windowed variants).
async function scrollP95(page, scrollableExpr, { durationMs = 6000 } = {}) {
  await page.evaluate((sel) => {
    window.__ss = [];
    let last = performance.now(), running = true;
    function tick() {
      if (!running) return;
      const now = performance.now();
      window.__ss.push(now - last);
      last = now;
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    window.__stopSS = () => { running = false; };
  }, scrollableExpr);
  const before = await page.evaluate((sel) => {
    const el = sel === "document" ? (document.scrollingElement || document.documentElement) : document.querySelector(sel);
    return el ? el.scrollTop : null;
  }, scrollableExpr);
  if (scrollableExpr === "document") {
    await page.mouse.move(400, 400);
    for (let i = 0; i < Math.floor(durationMs / 60); i++) {
      await page.mouse.wheel(0, 120);
      await page.waitForTimeout(50);
    }
  } else {
    // windowed container: wheel over it directly
    await page.evaluate((sel) => { const el = document.querySelector(sel); if (el) el.scrollTop = 0; }, scrollableExpr);
    const box = await page.locator(scrollableExpr).boundingBox().catch(() => null);
    if (box) await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    for (let i = 0; i < Math.floor(durationMs / 60); i++) {
      await page.mouse.wheel(0, 120);
      await page.waitForTimeout(50);
    }
  }
  await page.evaluate(() => window.__stopSS && window.__stopSS());
  await page.waitForTimeout(150);
  const after = await page.evaluate((sel) => {
    const el = sel === "document" ? (document.scrollingElement || document.documentElement) : document.querySelector(sel);
    return el ? el.scrollTop : null;
  }, scrollableExpr);
  const samples = await page.evaluate(() => window.__ss || []);
  return { st: stats(samples), moved: before !== null && after !== null && after !== before };
}

// ── metric 2: engine-local grid echo under 80 ms rtt ────────────────────────
// the probe page wires `<input data-webui-echo="echo-out">` → `<span id="echo-out">`
// (the t1.4 contract). under throttle we type; the echo is engine-local so the
// update must land WITHOUT any ws frame and without waiting on the wire. latency
// is measured entirely in PAGE time: a keydown recorder + a MutationObserver on
// the echo targets (the local echo sets textContent -> characterData mutation),
// both installed from outside, then each mutation paired with the most recent
// keydown before it (p50/p95 of mutation−keydown).
async function gridEcho(page, { chars, throttle }) {
  await page.waitForFunction(() => {
    const host = document.querySelector("#probe");
    return host && host.getAttribute("data-ready") === "1";
  }, null, { timeout: 15000 });
  await page.evaluate(() => {
    const host = document.getElementById("probe");
    // a small grid of echo cells — the "grid echo" at desktop grade
    host.innerHTML = "";
    for (let i = 0; i < 4; i++) {
      const cell = document.createElement("div");
      cell.className = "echo-cell";
      cell.style.margin = "4px 0";
      const input = document.createElement("input");
      input.id = "echo-src-" + i;
      input.type = "text";
      input.setAttribute("data-webui-echo", "echo-out-" + i);
      const target = document.createElement("span");
      target.id = "echo-out-" + i;
      target.textContent = "INIT";
      cell.appendChild(input);
      cell.appendChild(target);
      host.appendChild(cell);
    }
    // observers from OUTSIDE: a keydown recorder + a MutationObserver on the
    // echo targets. the local echo writes textContent of the target (a
    // characterData mutation); an authoritative server text/replace shows up
    // as childList (replace) or characterData (text). we observe the targets
    // directly and pair each mutation with the most recent keydown.
    window.__echoGate = { keydowns: [], mutations: [], done: false };
    document.addEventListener("keydown", (e) => {
      if (e.target && e.target.id && e.target.id.startsWith("echo-src-")) {
        window.__echoGate.keydowns.push(performance.now());
      }
    });
    for (let i = 0; i < 4; i++) {
      const target = document.getElementById("echo-out-" + i);
      const obs = new MutationObserver(() => {
        window.__echoGate.mutations.push({ at: performance.now(), id: target.id, text: target.textContent });
      });
      obs.observe(target, { characterData: true, characterDataOldValue: true, childList: true, subtree: true });
    }
  });

  let frames = [];
  const onWs = (ws) => ws.on("framesent", (e) => frames.push(Date.now()));
  page.on("websocket", onWs);

  const seed = "d3-echo-" + Date.now().toString(36);
  await page.focus("#echo-src-0");
  for (let i = 0; i < chars; i++) {
    await page.keyboard.type(seed[i % seed.length], { delay: 1 });
  }
  page.off("websocket", onWs);
  await page.waitForTimeout(250);

  const data = await page.evaluate(() => window.__echoGate || { keydowns: [], mutations: [], done: false });
  // pair each echo mutation with the most recent keydown before it
  const latencies = [];
  for (const m of data.mutations) {
    const prior = data.keydowns.filter((k) => k <= m.at);
    if (prior.length) latencies.push(m.at - prior[prior.length - 1]);
  }
  // authoritative patch wins: confirm a server text op overwrites the local echo
  const authoritative = await page.evaluate(() => {
    const inst = window.WebUIEngine && window.WebUIEngine._getInstance && window.WebUIEngine._getInstance();
    if (!inst || !inst.fragmentPatcher) return { ok: false, why: "no engine" };
    inst.fragmentPatcher.echo("echo-out-0", "SERVER");
    inst.patch([{ id: "echo-out-0", op: "text", text: "AUTH" }], 1);
    const overlays = Object.keys(inst.fragmentPatcher.echoOverlay || {}).length;
    return { text: document.getElementById("echo-out-0").textContent, overlays };
  });
  return { latencies, st: stats(latencies), framesDuring: frames.length, keydowns: data.keydowns.length, mutations: data.mutations.length, authoritative };
}

// ── metric 3: degrade — island artifact absent → server rendering intact ────
async function degradeCheck(page) {
  await page.waitForFunction(() => {
    const el = document.getElementById("missing");
    return el && el.getAttribute("data-webui-island-state");
  }, null, { timeout: 8000 });
  const state = await page.evaluate(() => ({
    state: document.getElementById("missing").getAttribute("data-webui-island-state"),
    html: document.getElementById("missing").innerHTML,
    engineAlive: !!(window.WebUIEngine && window.WebUIEngine._getInstance && typeof window.WebUIEngine._getInstance().patch === "function"),
  }));
  return state;
}

// ── run ─────────────────────────────────────────────────────────────────────
const benchBase = `http://127.0.0.1:${BENCH_PORT}`;
if (!(await waitFor(benchBase + "/bench/feed"))) {
  console.log("  FAIL bench server did not come up on :" + BENCH_PORT + " (" + benchLog.slice(-200) + ")");
  process.exit(1);
}
const probeHtml = `
<style>
  .echo-cell { display: inline-block; margin: 4px 8px 4px 0; }
  #echo-root { display: grid; grid-template-columns: repeat(2, 220px); gap: 8px; margin: 8px 0; }
</style>
<div id="echo-root"></div>
<div id="missing" data-webui-island="missing"><p id="server-rendered">server-rendered fallback content</p></div>
`;
// the .wasm for "missing" is deliberately NOT registered -> 404 -> degrade
let probeClose = null;
const probeServer = await startProbeServer(PROBE_PORT, probeHtml, {
  enginePath: join(ROOT, "designer/assets/webui-engine.js"),
}).catch((e) => { console.log("  FAIL probe server: " + e.message); process.exit(1); });
probeClose = probeServer.close;
ok("probe server up on :" + PROBE_PORT);

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
await context.addInitScript(() => {
  try {
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: (q) => ({ matches: q === "(prefers-reduced-motion: reduce)", media: q, onchange: null, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }),
    });
  } catch (e) {}
});

// ── 1. feed 10k scroll p95 ─────────────────────────────────────────────────
{
  const page = await context.newPage();
  const scroll = { naive: null, windowed: null, windowedOps: null };
  const variants = [
    ["naive", `${benchBase}/bench/feed?items=${ITEMS}`, "document"],
    ["windowed", `${benchBase}/bench/feed?windowed=1&items=${ITEMS}`, "#feed-window"],
    ["windowedOps", `${benchBase}/bench/feed?windowed=1&ops=1&items=${ITEMS}`, "#feed-window"],
  ];
  for (const [name, url, sel] of variants) {
    for (const mode of ["loopback", "throttled"]) {
      await page.goto(url, { waitUntil: "load" });
      await page.waitForSelector(sel === "document" ? "#feed-list" : "#feed-window");
      const r = mode === "throttled"
        ? await withThrottle(context, page, THROTTLE, () => scrollP95(page, sel))
        : await scrollP95(page, sel);
      scroll[name] = scroll[name] || {};
      scroll[name][mode] = r;
      const key = `scroll-${name}-${mode}`;
      results.checks[key] = { p95: r.st.p95, moved: r.moved };
      if (r.moved) ok(`scroll ${name} ${mode}: p95=${r.st.p95?.toFixed(1)} ms, scroll moved`);
      else bad(`scroll ${name} ${mode}: scroll did not move — precondition failed`);
    }
  }
  for (const [name, sel] of [["naive", "document"], ["windowed", "#feed-window"], ["windowedOps", "#feed-window"]]) {
    const p95 = scroll[name]?.throttled?.st?.p95; // the throttled number is the gate
    const key = `scroll-${name}-throttled`;
    if (name === "naive") {
      // the naive full-render 10k list is the documented ~62 ms wall (d0) —
      // it CANNOT meet the 20 ms budget and is precisely why windowing exists.
      // recorded as the baseline, never asserted green.
      console.log(`  note scroll naive throttled p95 ${p95?.toFixed(1)} ms — the full-render wall, recorded baseline (windowing is the fix)`);
      ok(`scroll naive precondition green (moved + measured)`);
    } else if (p95 !== null && p95 !== undefined && p95 <= SCROLL_P95_CEILING_MS) {
      ok(`scroll ${name} throttled p95 ${p95.toFixed(1)} ms ≤ ${SCROLL_P95_CEILING_MS} ms (plan §5 budget) — gate green`);
    } else {
      bad(`scroll ${name} throttled p95 ${p95?.toFixed(1)} ms > ${SCROLL_P95_CEILING_MS} ms — the server-orchestrated window step round-trips per scroll event (d0 finding); engine/island-local windowing (t3.3) is the pending fix`);
    }
  }
  await page.close();
}

// ── 2. grid echo < 50 ms @ 80 ms rtt ───────────────────────────────────────
{
  const page = await context.newPage();
  const echo = await withThrottle(context, page, THROTTLE, async () => {
    await page.goto(`http://127.0.0.1:${PROBE_PORT}/`);
    return gridEcho(page, { chars: ECHO_CHARS, throttle: THROTTLE });
  });
  results.checks["echo-80rtt"] = { p95: echo.st.p95, p50: echo.st.p50, n: echo.st.n, framesDuring: echo.framesDuring, authoritative: echo.authoritative };
  if (echo.st.p95 !== null && echo.st.p95 < ECHO_P95_CEILING_MS && echo.framesDuring === 0) {
    ok(`grid echo @ ${THROTTLE} ms rtt: p95=${echo.st.p95.toFixed(1)} ms < ${ECHO_P95_CEILING_MS} ms, 0 ws frames (engine-local)`);
  } else {
    bad(`grid echo @ ${THROTTLE} ms rtt: p95=${echo.st.p95?.toFixed(1)} ms ceil=${ECHO_P95_CEILING_MS} ms frames=${echo.framesDuring} — engine-local echo not within budget`);
  }
  if (echo.authoritative?.text === "AUTH" && echo.authoritative.overlays === 0) ok("echo: authoritative text op wins and clears the overlay");
  else bad("echo: authoritative text op did not win/clear (got " + JSON.stringify(echo.authoritative) + ")");
  await page.close();
}

// ── 3. degrade: island artifact absent → server rendering intact ───────────
{
  const page = await context.newPage();
  await page.goto(`http://127.0.0.1:${PROBE_PORT}/`);
  // page must have engine ready (the degrade path leaves the engine alive)
  await page.waitForFunction(() => {
    const e = window.WebUIEngine && window.WebUIEngine._getInstance && window.WebUIEngine._getInstance();
    return !!(e && e.wsClient && e.wsClient.isConnected && e.wsClient.isConnected());
  }, null, { timeout: 15000 }).catch(() => {});
  const d = await degradeCheck(page);
  results.checks["degrade"] = d;
  const contentIntact = d.html && d.html.includes("server-rendered fallback content");
  if (d.state === "unmapped" && contentIntact && d.engineAlive) {
    ok("degrade: island artifact absent → unmapped, server-rendered content intact, engine alive");
  } else {
    bad("degrade: state=" + d.state + " contentIntact=" + contentIntact + " engineAlive=" + d.engineAlive);
  }
  await page.close();
}

await browser.close();
teardown();

// write the evidence
mkdirSync(join(ROOT, ".bench"), { recursive: true });
writeFileSync(join(ROOT, ".bench", "d3-gate.json"), JSON.stringify(results, null, 2) + "\n");
console.log("results: .bench/d3-gate.json");

console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
console.log(fail === 0 ? "D3 GATE PASS" : "D3 GATE FAIL (recorded in .bench/d3-gate.json)");
process.exit(fail === 0 ? 0 : 1);
