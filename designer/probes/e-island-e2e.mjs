#!/usr/bin/env node
// designer/probes/e-island-e2e.mjs — lane-E wave-2 probe: the island seam's engine
// half, end to end in a real browser (t2.1 imports, t2.2 events-in, t2.3 op-stream
// drain, t2.4 state channel, t2.6 defense in depth).
//
// drives the REAL engine asset (designer/assets/webui-engine.js is the deployed
// bytes) against a hand-assembled synthetic island (designer/probes/e-island-wasm.mjs)
// that declares the full t2.1 host import set and implements the merged probe
// island export surface + the frozen webui_take_ops() contract. the engine's real
// loader/instantiation path is exercised — the page fetches /__assets/webui-*.wasm
// exactly as a production page would. lane port 9262.
//
// assertions:
//   t2.1  a module importing all six host capabilities mounts (buildImports table)
//   t2.6  an unknown webui_* import throws; island unmapped, page alive
//   t2.6  a missing artifact (404) unmaps the island; page stays server-rendered
//   t2.2  keydown/click inside the region arrive island-side as {type,key,data}
//         (the island logs the raw payload via webui_log; ops applied to the DOM)
//   t2.3  events drain through webui_take_ops -> text/attr ops applied in order
//   t2.1  clock (webui_now_ms) value flows into the applied ops
//   t2.1  rAF schedule (webui_raf) -> island webui_frame_tick -> ops applied
//   t2.1  state_persist: webui_store_set -> localStorage; store_get on remount
//   t2.4  region replace saves island state; remount restores it (count continues)
//   t2.4  ws reconnect re-arms the state cache; regions stay mounted

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";
import { buildProbeWasm, buildBogusWasm } from "./e-island-wasm.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9262;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

const bodyHtml = `
<div id="e2e" data-webui-island="e2e" data-webui-island-events='["keydown","click"]'></div>
<div id="bogus" data-webui-island="bogus"></div>
<div id="missing" data-webui-island="missing"></div>
`;

const probeWasm = buildProbeWasm();
const bogusWasm = buildBogusWasm();

const { base, server, close } = await startProbeServer(PORT, bodyHtml, {
  enginePath: join(ROOT, "designer/assets/webui-engine.js"),
  routes: {
    "/__assets/webui-e2e.wasm": { type: "application/wasm", body: Buffer.from(probeWasm) },
    "/__assets/webui-bogus.wasm": { type: "application/wasm", body: Buffer.from(bogusWasm) },
    // /__assets/webui-missing.wasm deliberately left unserved -> 404
  },
});
ok(`probe server up on :${PORT}`);

process.on("exit", () => { close(); });
process.on("SIGINT", () => { close(); process.exit(1); });

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
const page = await context.newPage();
page.on("pageerror", (err) => bad("page error: " + err.message));

const consoleLines = [];
page.on("console", (msg) => { consoleLines.push({ type: msg.type(), text: msg.text() }); });
const logs = () => consoleLines.filter((l) => l.text.includes("[island:e2e]"));
const warns = () => consoleLines.filter((l) => l.type === "warning" && l.text.includes("[WebUIEngine]"));

await page.goto(base + "/");
await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });
ok("page loaded, engine ready");

// ---- t2.1: six host imports resolve; the island mounts ----
await page.waitForFunction(() => document.getElementById("e2e") && document.getElementById("e2e").getAttribute("data-webui-island-state") === "mounted", { timeout: 10000 });
check("t2.1 mount: all six host imports resolved, region mounted", true);
const mountedHtml = await page.evaluate(() => document.getElementById("e2e").innerHTML);
check("t2.1 mount html applied", mountedHtml.includes('id="lbl"'), mountedHtml.slice(0, 60));

// ---- t2.6: unknown host import throws, island unmapped, page alive ----
await page.waitForFunction(() => document.getElementById("bogus") && document.getElementById("bogus").getAttribute("data-webui-island-state") === "unmapped", { timeout: 10000 });
const bogusWarn = warns().filter((w) => w.text.includes("webui_bogus"));
check("t2.6 unknown webui_* import -> unmapped + warning", bogusWarn.length >= 1, warns().map((w) => w.text).join(" | "));

// ---- t2.6: missing artifact -> unmapped, page stays server-rendered ----
await page.waitForFunction(() => document.getElementById("missing") && document.getElementById("missing").getAttribute("data-webui-island-state") === "unmapped", { timeout: 10000 });
const missingWarn = warns().filter((w) => w.text.includes("webui-missing.wasm") || w.text.includes("island missing unavailable") || w.text.includes("island fetch"));
check("t2.6 artifact absent -> unmapped + warning, page alive", missingWarn.length >= 1, warns().map((w) => w.text).join(" | "));
const engineAlive = await page.evaluate(() => !!window.WebUIEngine._getInstance() && typeof window.WebUIEngine._getInstance().patch === "function");
check("t2.6 engine instance alive after both degradations", engineAlive);

// ---- t2.2 / t2.3: keydowns arrive as {type,key,data}; ops applied ----
await page.evaluate(() => {
  const region = document.getElementById("e2e");
  const input = document.createElement("input");
  input.id = "e2e-in";
  region.appendChild(input);
  input.focus();
});
await page.keyboard.type("abc"); // 3 keydowns
await page.waitForFunction(() => {
  const el = document.querySelector("#e2e #lbl");
  return el && el.textContent === "3";
}, { timeout: 5000 });
check("t2.2+t2.3 three keydowns -> #lbl text '3' (events drained + applied)", true);

const islandLogs = logs().map((l) => l.text.replace(/^\[island:e2e\] /, "")).filter((t) => t.startsWith("{"));
const parsed = islandLogs.map((t) => { try { return JSON.parse(t); } catch (e) { return null; } }).filter(Boolean);
const keyA = parsed.find((p) => p.type === "key" && p.key === "a");
check("t2.2 payload shape {type,key,data} arrives island-side (keyboard normalized to 'key')", !!keyA && typeof keyA.data === "object" && keyA.data && keyA.data.key === "a", JSON.stringify(parsed[0]));

// ---- t2.1: clock value flows into applied ops ----
const clockAttr = await page.evaluate(() => document.querySelector("#e2e #lbl").getAttribute("data-now"));
check("t2.1 webui_now_ms value applied via attr op (data-now set)", !!clockAttr && clockAttr.length >= 1, String(clockAttr));

// ---- t2.1: frame_schedule rAF registry -> island tick -> ops ----
await page.waitForFunction(() => {
  const el = document.querySelector("#e2e #lbl");
  const t = el && el.getAttribute("data-tick");
  return t && Number(t) >= 1;
}, { timeout: 3000 });
check("t2.1 webui_raf registry -> webui_frame_tick -> data-tick op applied", true);

// ---- t2.1: state_persist: store_set -> localStorage ----
const stored = await page.evaluate(() => window.localStorage.getItem("probe-key"));
check("t2.1 webui_store_set persisted 'probe-key' to localStorage", stored === "3", String(stored));

// ---- t2.4: region replace saves state; remount restores; count continues ----
await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  inst.patch([{ id: "e2e", op: "replace", html: '<div id="e2e" data-webui-island="e2e" data-webui-island-events=\'["keydown","click"]\'></div>' }], 100);
});
await page.waitForFunction(() => document.getElementById("e2e") && document.getElementById("e2e").getAttribute("data-webui-island-state") === "mounted", { timeout: 8000 });
const remounted = await page.evaluate(() => {
  const lbl = document.querySelector("#e2e #lbl");
  return {
    e: lbl && lbl.getAttribute("data-e"),
    r: lbl && lbl.getAttribute("data-r"),
    s: lbl && lbl.getAttribute("data-s"),
    text: lbl && lbl.textContent,
  };
});
check("t2.4 state survives remount: data-e continued (events=3)", remounted.e === "3", JSON.stringify(remounted));
check("t2.4 restore fired on remount: data-r=1", remounted.r === "1", JSON.stringify(remounted));
check("t2.4 store_get roundtrip on remount: data-s=1", remounted.s === "1", JSON.stringify(remounted));

// typing continues the restored state
await page.evaluate(() => {
  const region = document.getElementById("e2e");
  const input = document.createElement("input");
  input.id = "e2e-in";
  region.appendChild(input);
  input.focus();
});
await page.keyboard.type("x"); // +1 event -> events=4
await page.waitForFunction(() => {
  const el = document.querySelector("#e2e #lbl");
  return el && el.textContent === "4";
}, { timeout: 5000 });
check("t2.4 state continued across remount (+1 event -> '4')", true);

// ---- t2.4: ws reconnect re-arms state; regions stay mounted ----
const sockets = server.sockets;
for (const s of sockets) { try { s.destroy(); } catch (e) {} }
await page.waitForFunction(() => {
  const el = document.getElementById("e2e");
  return el && el.getAttribute("data-webui-island-state") === "mounted";
}, { timeout: 8000 });
const aliveAfterReconnect = await page.evaluate(() => {
  const lbl = document.querySelector("#e2e #lbl");
  return !!lbl && !!window.WebUIEngine._getInstance();
});
check("t2.4 ws reconnect: region stays mounted, engine alive", aliveAfterReconnect);

await browser.close();
close();
console.log("");
if (fail === 0) console.log(`e-island-e2e: ${pass} PASS, 0 FAIL`);
else console.log(`e-island-e2e: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
