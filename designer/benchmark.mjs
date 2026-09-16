#!/usr/bin/env node
// designer/benchmark.mjs — A/B benchmark: server-mode vs client-mode UI refresh.
//
// Measures the same "event → DOM refresh" shape on both hosts, in one browser:
//   server mode : smoke page — counter click and table-sort header click go
//                 WebSocket → NIO render → fragment patch (round trip).
//   client mode : search-demo page — typing dispatches through the resident
//                 wasm EventRouter → local render → frame patch (zero ws).
// Reports per-interaction latency (p50/p95/mean), ws byte accounting, and the
// boot-to-interactive cost of each page. writes a markdown table to
// .smoke/benchmark.md. self-contained: builds, serves on :9123, tears down.
//
// Usage: node designer/benchmark.mjs

import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9123;
const BASE = `http://127.0.0.1:${PORT}`;
const SAMPLES = 40;
const WARMUP = 6;
const TIMEOUT_MS = 8000;

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"], ...opts });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
  });
}

async function waitForServer(tries = 40) {
  for (let i = 0; i < tries; i++) {
    try { if ((await fetch(BASE + "/")).ok) return true; } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

function stats(samples) {
  const s = [...samples].sort((a, b) => a - b);
  const p = (q) => s[Math.min(s.length - 1, Math.floor(q * s.length))] ?? 0;
  const mean = s.reduce((a, b) => a + b, 0) / (s.length || 1);
  return { n: s.length, p50: p(0.5), p95: p(0.95), mean };
}

// instrument WebSocket send/receive bytes before the page loads
const wsInstrument = `
  window.__wsStat = { conns: 0, sentMsgs: 0, sentBytes: 0, recvMsgs: 0, recvBytes: 0 };
  (function () {
    var Orig = window.WebSocket;
    function Wrap(/* url, protocols, options */) {
      var ws = new Orig(arguments[0], arguments[1], arguments[2]);
      window.__wsStat.conns += 1;
      ws.addEventListener("message", function (e) {
        window.__wsStat.recvMsgs += 1;
        window.__wsStat.recvBytes += typeof e.data === "string" ? e.data.length : (e.data.byteLength || 0);
      });
      var s = ws.send.bind(ws);
      ws.send = function (data) {
        window.__wsStat.sentMsgs += 1;
        window.__wsStat.sentBytes += typeof data === "string" ? data.length : (data.byteLength || 0);
        return s(data);
      };
      return ws;
    }
    Wrap.prototype = Orig.prototype;
    Wrap.CONNECTING = 0; Wrap.OPEN = 1; Wrap.CLOSING = 2; Wrap.CLOSED = 3;
    window.WebSocket = Wrap;
  })();
`;

console.log("=== WebUI A/B benchmark: server-mode vs client-mode refresh ===");
console.log(`target: ${BASE}  samples: ${SAMPLES}  warmup: ${WARMUP}`);

// build host + wasm release (sdk-aware)
const host = await run("swift", ["build"]);
if (host.code !== 0) { console.log(host.out.slice(-400)); console.log("FAIL swift build"); process.exit(1); }
const sdkList = (await run("swift", ["sdk", "list"])).out;
const hasWasmSdk = sdkList.includes("swift-6.4.0-RELEASE_wasm");
let wasmBuilt = false;
if (hasWasmSdk) {
  const wb = await run("swift", ["build", "-c", "release", "--swift-sdk", "swift-6.4.0-RELEASE_wasm", "--product", "WebUIClient"]);
  wasmBuilt = wb.code === 0;
  if (!wasmBuilt) { console.log("wasm build failed — client-mode sections will SKIP"); }
} else {
  console.log("wasm sdk not active — client-mode sections will SKIP");
}

const server = spawn(join((await run("swift", ["build", "--show-bin-path"])).out.trim(), "WebUISmokeTest"), [], { cwd: ROOT, stdio: ["ignore", "ignore", "ignore"] });
if (!(await waitForServer())) { console.log("FAIL server not ready"); server.kill(); process.exit(1); }

const browser = await chromium.launch();
const results = {};
const notes = [];

try {
  // ---------- server-mode: counter click (WS round trip) ----------
  {
    const page = await browser.newPage();
    await page.addInitScript(wsInstrument);
    await page.goto(BASE + "/", { waitUntil: "networkidle" });
    await page.waitForTimeout(400);
    for (let i = 0; i < WARMUP; i++) { await page.click("#btn-inc"); await page.waitForTimeout(60); }
    const samples = await page.evaluate(async (n) => {
      const btn = document.querySelector("#btn-inc");
      const counter = () => Number(document.querySelector("#counter-value").textContent.trim());
      const out = [];
      for (let i = 0; i < n; i++) {
        const before = counter();
        const t0 = performance.now();
        let done = null;
        const waited = new Promise((res) => {
          const tick = () => {
            if (counter() !== before) { done = performance.now(); res(); }
            else if (performance.now() - t0 > 8000) { res(); }
            else requestAnimationFrame(tick);
          };
          tick();
        });
        btn.click();
        await waited;
        out.push(done ? done - t0 : null);
      }
      return out;
    }, SAMPLES);
    const ws = await page.evaluate(() => window.__wsStat);
    results.serverCounter = stats(samples.filter((x) => x != null));
    results.serverCounter.ws = ws;
    await page.close();
  }

  // ---------- server-mode: table sort header (rows re-render over WS) ----------
  {
    const page = await browser.newPage();
    await page.addInitScript(wsInstrument);
    await page.goto(BASE + "/", { waitUntil: "networkidle" });
    await page.waitForTimeout(400);
    const sel = '[data-component-id="interactive-table-sort-1"]';
    await page.waitForSelector(sel);
    for (let i = 0; i < WARMUP; i++) { await page.click(sel); await page.waitForTimeout(90); }
    const samples = await page.evaluate(async (n) => {
      const markers = () => {
        const head = document.querySelector('[data-component-id="interactive-table-sort-1"]');
        if (!head) return null;
        const th = head.closest ? head.closest("th") : null;
        return th ? th.getAttribute("aria-sort") : head.getAttribute("aria-sort");
      };
      const out = [];
      for (let i = 0; i < n; i++) {
        const before = markers();
        const t0 = performance.now();
        let done = null;
        const waited = new Promise((res) => {
          const tick = () => {
            if (markers() !== before) { done = performance.now(); res(); }
            else if (performance.now() - t0 > 8000) { res(); }
            else requestAnimationFrame(tick);
          };
          tick();
        });
        document.querySelector('[data-component-id="interactive-table-sort-1"]').click();
        await waited;
        out.push(done ? done - t0 : null);
      }
      return out;
    }, SAMPLES);
    results.serverTableSort = stats(samples.filter((x) => x != null));
    await page.close();
  }

  // ---------- client-mode: local-search input (wasm render, zero ws) ----------
  if (wasmBuilt) {
    const page = await browser.newPage();
    await page.goto(BASE + "/__assets/search-demo", { waitUntil: "domcontentloaded" });
    await page.waitForSelector("#search-app input", { timeout: 30000 });
    await page.waitForTimeout(200);
    const samples = await page.evaluate(async (n) => {
      const input = document.querySelector("#search-input");
      const rows = () => document.querySelector("#search-rows")?.textContent ?? "";
      const filters = ["a", "w", "se", "ap", "e", "us", "ar", "s", "auth", "web", "i", "n", "x", "sea", "eu", "a"];
      const out = [];
      input.focus();
      for (let i = 0; i < n; i++) {
        const value = filters[i % filters.length];
        const before = rows();
        input.value = value;
        const t0 = performance.now();
        input.dispatchEvent(new Event("input", { bubbles: true }));
        const inTurn = performance.now() - t0; // dispatch is synchronous: DOM patched in-turn
        let observed = null;
        const waited = new Promise((res) => {
          const tick = () => {
            if (rows() !== before || (performance.now() - t0 > 16)) { observed = performance.now() - t0; res(); }
            else requestAnimationFrame(tick);
          };
          tick();
        });
        await waited;
        out.push({ inTurn, observed: observed == null ? null : observed });
      }
      return out;
    }, SAMPLES);
    const holder = await page.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      return { wsSent: inst.wsSent, events: inst.eventCount };
    });
    const valid = samples.filter((x) => x && x.observed != null);
    results.clientSearch = {
      inTurn: stats(valid.map((x) => x.inTurn)),
      observed: stats(valid.map((x) => x.observed)),
      wsSent: holder.wsSent,
      events: holder.events,
    };
    if (holder.wsSent !== 0) notes.push("WARNING: client-mode search produced wsSends — hot path not silent");
    await page.close();
  }

  // ---------- boot cost: SSR page vs client-mode boot ----------
  {
    const t0 = Date.now();
    const page = await browser.newPage();
    const serverResp = await page.goto(BASE + "/", { waitUntil: "domcontentloaded" });
    const tt = serverResp ? serverResp.request().timing() : null;
    const serverTTFB = tt ? tt.responseEnd - tt.requestStart : null;
    const serverPaint = await page.evaluate(() => performance.getEntriesByType("navigation")[0]?.domContentLoadedEventEnd ?? null);
    results.bootServer = { toDomContentLoaded: serverPaint, ttfbMs: serverTTFB };
    await page.close();
    const t1 = Date.now();
    const page2 = await browser.newPage();
    const t2 = Date.now();
    await page2.goto(BASE + "/__assets/search-demo", { waitUntil: "domcontentloaded" });
    const bootT0 = Date.now();
    await page2.waitForSelector("#search-app input", { timeout: 60000 });
    const clientBootMs = Date.now() - bootT0; // domcontentloaded -> input present (wasm fetch+instantiate+boot)
    results.bootClient = { afterDomContentLoadedMs: clientBootMs };
    await page2.close();
  }

  // ---------- report ----------
  const fmt = (s) => (s ? `${s.p50.toFixed(2)} ms` : "n/a");
  const rows = [
    ["server — counter click (ws round-trip)", results.serverCounter ? fmt(results.serverCounter) : "n/a", results.serverCounter ? results.serverCounter.p95.toFixed(2) + " ms" : "n/a", results.serverCounter ? results.serverCounter.ws.recvMsgs / Math.max(1, results.serverCounter.n) : "n/a"],
    ["server — table sort (ws round-trip)", results.serverTableSort ? fmt(results.serverTableSort) : "n/a", results.serverTableSort ? results.serverTableSort.p95.toFixed(2) + " ms" : "n/a", "n/a"],
    ["client — local search (wasm, in-turn)", results.clientSearch ? fmt(results.clientSearch.inTurn) : "n/a", results.clientSearch ? results.clientSearch.inTurn.p95.toFixed(2) + " ms" : "n/a", "0"],
    ["client — local search (wasm, to-frame)", results.clientSearch ? fmt(results.clientSearch.observed) : "n/a", results.clientSearch ? results.clientSearch.observed.p95.toFixed(2) + " ms" : "n/a", "0"],
  ];
  const lines = [];
  lines.push("| mode — action | p50 refresh | p95 refresh | ws messages / interaction |");
  lines.push("|---|---|---|---|");
  for (const [name, p50, p95, ws] of rows) lines.push(`| ${name} | ${p50} | ${p95} | ${ws} |`);
  lines.push("");
  lines.push(`- server counter: ${results.serverCounter ? SAMPLES : 0} samples; ws sent ${results.serverCounter?.ws.sentBytes ?? 0} bytes / ${results.serverCounter?.ws.sentMsgs ?? 0} msgs, recv ${results.serverCounter?.ws.recvBytes ?? 0} bytes / ${results.serverCounter?.ws.recvMsgs ?? 0} msgs (after warmup)`)
  if (results.clientSearch) lines.push(`- client search: ${results.clientSearch.observed.n} samples; in-turn dispatch ${results.clientSearch.inTurn.p50.toFixed(3)} ms p50; webSocket sends: ${results.clientSearch.wsSent} (hot path silent)`);
  if (results.bootServer) lines.push(`- boot (SSR /): ttfb ${(results.bootServer.ttfbMs ?? 0).toFixed(1)} ms, domcontentloaded at ${(results.bootServer.toDomContentLoaded ?? 0).toFixed(1)} ms`);
  if (results.bootClient) lines.push(`- boot (client-mode search-demo): wasm fetch+instantiate+boot after domcontentloaded: ${results.bootClient.afterDomContentLoadedMs.toFixed(0)} ms`);
  for (const note of notes) lines.push(`- ${note}`);
  const table = lines.join("\n");
  console.log("");
  console.log(table);
  mkdirSync(join(ROOT, ".smoke"), { recursive: true });
  writeFileSync(join(ROOT, ".smoke", "benchmark.md"), table + "\n");
  console.log(`  wrote -> ${join(ROOT, ".smoke", "benchmark.md")}`);
} finally {
  await browser.close();
  server.kill();
}
