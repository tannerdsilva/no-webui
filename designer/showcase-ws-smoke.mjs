#!/usr/bin/env node
// designer/showcase-ws-smoke.mjs — dispatch gate for the showcase server.
//
// why this exists: `smoke` checks served bytes and `fullstack-smoke` drives the
// *smoke* page. neither dispatches a **stable-id** control (`controlAttributes`,
// e.g. a table sort header) against the *showcase* server, so a break in that
// path ships invisibly. this gate does exactly that one thing: it clicks a
// stable-id control in a real browser, captures the websocket frames, and
// requires a reply.
//
// assertion: for each probed stable-id control, an outbound `event` frame AND an
// inbound `update` frame must both be observed. a click that sends but never
// receives is the failure this gate exists for.
//
// usage: node designer/showcase-ws-smoke.mjs
//   spawns WebUIShowcaseServer on :9092, drives headless Chromium, tears down.
//   exits non-zero on failure and prints the captured frames.

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9092;
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = join(ROOT, ".smoke");

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

function run(cmd, args) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
  });
}

async function waitForServer(timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(BASE + "/", { signal: AbortSignal.timeout(2000) });
      if (res.ok) { return true; }
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 400));
  }
  return false;
}

const server = spawn(join(ROOT, ".build/debug/WebUIShowcaseServer"), ["--port", String(PORT)], {
  cwd: ROOT,
  stdio: ["ignore", "pipe", "pipe"],
});
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

let browser = null;
try {
  if (!(await waitForServer())) {
    bad("showcase server did not become ready on :" + PORT);
    console.log(serverLog.split("\n").slice(-8).join("\n"));
    process.exit(1);
  }
  mkdirSync(SHOTS, { recursive: true });

  browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 950 } });
  const consoleErrors = [];
  page.on("console", (m) => { if (m.type() === "error") { consoleErrors.push(m.text()); } });

  await page.goto(BASE + "/", { waitUntil: "load" });
  await page.waitForTimeout(1500);

  // record every websocket frame the engine sends and receives
  await page.evaluate(() => {
    window.__frames = [];
    const send = WebSocket.prototype.send;
    WebSocket.prototype.send = function (data) {
      try { if (typeof data === "string") { window.__frames.push({ dir: "out", body: data }); } } catch (e) {}
      return send.apply(this, arguments);
    };
    const add = WebSocket.prototype.addEventListener;
    WebSocket.prototype.addEventListener = function (type, fn, opts) {
      if (type === "message") {
        const wrapped = function (ev) {
          try { window.__frames.push({ dir: "in", body: String(ev.data) }); } catch (e) {}
          return fn.apply(this, arguments);
        };
        return add.call(this, type, wrapped, opts);
      }
      return add.call(this, type, fn, opts);
    };
  });

  // collect stable-id controls: the page's own ids, excluding render-minted cN ids
  const controls = await page.evaluate(() => {
    const seen = new Set();
    const out = [];
    document.querySelectorAll("[data-component-id]").forEach((el) => {
      const id = el.getAttribute("data-component-id");
      if (!id || /^c\d+$/.test(id) || seen.has(id)) { return; }
      seen.add(id);
      out.push({ id: id, event: el.getAttribute("data-event"), tag: el.tagName });
    });
    return out;
  });

  if (controls.length === 0) {
    bad("the showcase page exposes no stable-id controls to dispatch");
  } else {
    ok("showcase page exposes " + controls.length + " stable-id control(s)");
  }

  // probe up to three, preferring the table's sort header (the flagship pattern)
  const preferred = controls.filter((c) => c.id.includes("-sort-"));
  const probes = (preferred.length ? preferred : controls).slice(0, 3);

  for (const probe of probes) {
    await page.evaluate(() => { window.__frames = []; });
    const clicked = await page.evaluate((id) => {
      const el = Array.from(document.querySelectorAll("[data-component-id]")).find((n) => n.getAttribute("data-component-id") === id);
      if (!el) { return false; }
      el.click();
      return true;
    }, probe.id);
    if (!clicked) { bad("could not click " + probe.id); continue; }
    await page.waitForTimeout(1200);

    const frames = await page.evaluate(() => window.__frames || []);
    const sent = frames.find((f) => f.dir === "out" && f.body.includes(probe.id));
    const got = frames.find((f) => f.dir === "in" && f.body.includes("\"type\":\"update\""));
    if (sent && got) {
      ok(probe.id + " dispatched and answered (" + got.body.length + " byte update)");
    } else if (sent && !got) {
      bad(probe.id + " sent an event but the server never answered — stable-id dispatch is broken");
      console.log("      sent:   " + sent.body.slice(0, 160));
      console.log("      frames: " + frames.length + " total, 0 update replies");
    } else {
      bad(probe.id + " produced no outbound event frame at all");
    }
  }

  if (consoleErrors.length === 0) { ok("no console errors"); } else { bad("console errors: " + consoleErrors.slice(0, 3).join(" | ")); }

  await page.screenshot({ path: join(SHOTS, "showcase-ws.png"), fullPage: false });
} finally {
  if (browser) { await browser.close(); }
  server.kill("SIGTERM");
  await new Promise((r) => setTimeout(r, 400));
  if (!server.killed) { server.kill("SIGKILL"); }
}

console.log("");
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
console.log(fail === 0 ? "SHOWCASE WS SMOKE PASS" : "SHOWCASE WS SMOKE FAIL");
process.exit(fail === 0 ? 0 : 1);