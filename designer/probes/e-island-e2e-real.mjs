#!/usr/bin/env node
// designer/probes/e-island-e2e-real.mjs — lane-E wave-3: the LIVE handshake,
// e2e against C's REAL WebUIProbeIsland.wasm artifact (not the synthetic
// island). drives the engine's real loader through the served bytes at
// /__assets/webui-e2e.wasm and asserts against the REAL island's vocabulary
// (c-to-e.md): ArrowUp/ArrowDown keydowns, clicks on probe-inc/probe-dec/
// probe-clear, input on probe-field → insert; ids probe-counter/probe-list/
// probe-item-kN; the state channel across a region replace; and the mootness
// of webui_frame_tick / webui_store_get|set for this artifact.
//
// lane port 9263. exit non-zero on failure.
//
// artifact: build with
//   swift package --disable-sandbox plugin wasm-island --product WebUIProbeIsland
// located at .build/out/Products/Release-webassembly-wasm32/WebUIProbeIsland.wasm
// (override with WEBUI_PROBE_WASM)

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9263;

const WASM_CANDIDATES = [
  process.env.WEBUI_PROBE_WASM,
  join(ROOT, ".build/out/Products/Release-webassembly-wasm32/WebUIProbeIsland.wasm"),
].filter(Boolean);

const wasmPath = WASM_CANDIDATES.find((p) => p && existsSync(p));
if (!wasmPath) {
  console.error("e-island-e2e-real: WebUIProbeIsland.wasm not found — run the wasm-island plugin first");
  process.exit(2);
}
const wasmBytes = readFileSync(wasmPath);

// zero-warning artifact surface check: the real island has NO webui_* host
// imports (only wasi) and no webui_frame_tick export — the open conventions
// from e-to-c.md §3/§1 are moot for this artifact (verified against the
// served bytes, not assumed).
const mod = new WebAssembly.Module(wasmBytes);
const imports = WebAssembly.Module.imports(mod);
const exports = WebAssembly.Module.exports(mod).map((e) => e.name);
const webuiImports = imports.filter((i) => i.name.indexOf("webui_") === 0);
const hasTick = exports.indexOf("webui_frame_tick") !== -1;
const hasStore = webuiImports.some((i) => i.name === "webui_store_get" || i.name === "webui_store_set");
if (webuiImports.length !== 0) {
  console.error(`e-island-e2e-real: unexpected webui_* imports: ${webuiImports.map((i) => i.name).join(",")}`);
  process.exit(2);
}

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

const bodyHtml = `<div id="e2e" data-webui-island="e2e" data-webui-island-events='["keydown","click","input"]'></div>`;

const { base, close } = await startProbeServer(PORT, bodyHtml, {
  enginePath: join(ROOT, "designer/assets/webui-engine.js"),
  routes: {
    "/__assets/webui-e2e.wasm": { type: "application/wasm", body: wasmBytes },
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
const warns = [];
page.on("console", (msg) => { if (msg.type() === "warning" && msg.text().includes("[WebUIEngine]")) warns.push(msg.text()); });

await page.goto(base + "/");
await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });
ok("page loaded, engine ready");

// ---- mount: the real island renders its region html ----
await page.waitForFunction(() => {
  const el = document.getElementById("e2e");
  return el && el.getAttribute("data-webui-island-state") === "mounted";
}, { timeout: 20000 });
check("mount: region mounted (real island)", true);

const mounted = await page.evaluate(() => {
  const el = document.getElementById("e2e");
  return {
    counter: !!el.querySelector("#probe-counter"),
    dec: !!el.querySelector("#probe-dec"),
    inc: !!el.querySelector("#probe-inc"),
    clear: !!el.querySelector("#probe-clear"),
    field: !!el.querySelector("#probe-field"),
    list: !!el.querySelector("#probe-list"),
    text: el.querySelector("#probe-counter") && el.querySelector("#probe-counter").textContent,
  };
});
check("mount html: probe-counter/inc/dec/clear/field/list present", mounted.counter && mounted.inc && mounted.dec && mounted.clear && mounted.field && mounted.list, JSON.stringify(mounted));
check("mount html: counter starts at 0", mounted.text === "0", String(mounted.text));

const islandEvents = () => page.evaluate(() => {
  const el = document.querySelector("#e2e .island--probe");
  return el ? { renders: el.getAttribute("data-island-renders"), events: el.getAttribute("data-island-events") } : null;
});

// ---- keydowns: ArrowUp/ArrowDown on the focused field ----
await page.evaluate(() => { document.getElementById("probe-field").focus(); });
await page.keyboard.press("ArrowUp");
await page.keyboard.press("ArrowUp");
await page.waitForFunction(() => document.querySelector("#e2e #probe-counter") && document.querySelector("#e2e #probe-counter").textContent === "2", { timeout: 5000 });
check("keydown ArrowUp ×2 → probe-counter '2' (webui_on_event → take_ops → text op)", true);
await page.keyboard.press("ArrowDown");
await page.waitForFunction(() => document.querySelector("#e2e #probe-counter") && document.querySelector("#e2e #probe-counter").textContent === "1", { timeout: 5000 });
check("keydown ArrowDown → probe-counter '1'", true);

// ---- clicks: probe-inc / probe-dec / probe-clear (key = element id) ----
await page.click("#probe-inc");
await page.click("#probe-inc");
await page.waitForFunction(() => document.querySelector("#e2e #probe-counter") && document.querySelector("#e2e #probe-counter").textContent === "3", { timeout: 5000 });
check("click probe-inc ×2 → '3' (click payload key = element id reconciled)", true);
await page.click("#probe-dec");
await page.waitForFunction(() => document.querySelector("#e2e #probe-counter") && document.querySelector("#e2e #probe-counter").textContent === "2", { timeout: 5000 });
check("click probe-dec → '2'", true);

// ---- input: probe-field → addItem → insert op ----
await page.fill("#probe-field", "alpha");
await page.waitForFunction(() => {
  const li = document.querySelector("#e2e #probe-list #probe-item-k0");
  return li && li.textContent === "alpha";
}, { timeout: 5000 });
check("input probe-field 'alpha' → insert li#probe-item-k0 with escaped text", true);
await page.fill("#probe-field", "beta");
await page.waitForFunction(() => document.querySelector("#e2e #probe-list #probe-item-k1"), { timeout: 5000 });
check("second input → insert li#probe-item-k1 (keys continue)", true);

// ---- clear: empties the keyed list via remove ops ----
await page.click("#probe-clear");
await page.waitForFunction(() => document.querySelectorAll("#e2e #probe-list .island__item").length === 0, { timeout: 5000 });
check("click probe-clear → both items removed (remove ops applied)", true);

// ---- artifact surface: the two open conventions are moot ----
check("artifact imports NO webui_* host fns (store_get/set moot)", webuiImports.length === 0);
check("artifact exports NO webui_frame_tick (rAF moot)", !hasTick);
check("store_get|set absent → store moot (state channel is webui_state_save/restore only)", !hasStore);

// ---- state channel: region replace → save → restore → remount continues ----
await page.click("#probe-inc");
await page.fill("#probe-field", "gamma");
await page.waitForFunction(() => document.querySelector("#e2e #probe-list #probe-item-k2"), { timeout: 5000 });
const beforeReplace = await page.evaluate(() => ({ c: document.querySelector("#e2e #probe-counter").textContent, items: document.querySelectorAll("#e2e #probe-list .island__item").length }));
check("pre-replace state: counter 3, 1 item (k2)", beforeReplace.c === "3" && beforeReplace.items === 1, JSON.stringify(beforeReplace));

await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  inst.patch([{ id: "e2e", op: "replace", html: '<div id="e2e" data-webui-island="e2e" data-webui-island-events=\'["keydown","click","input"]\'></div>' }], 100);
});
await page.waitForFunction(() => {
  const el = document.getElementById("e2e");
  return el && el.getAttribute("data-webui-island-state") === "mounted" && el.querySelector("#probe-counter");
}, { timeout: 10000 });
const remounted = await page.evaluate(() => {
  const el = document.getElementById("e2e");
  return {
    c: el.querySelector("#probe-counter").textContent,
    items: Array.prototype.slice.call(el.querySelectorAll("#probe-list .island__item")).map((li) => li.id),
    ev: (el.querySelector(".island--probe") || {}).getAttribute ? el.querySelector(".island--probe").getAttribute("data-island-events") : null,
  };
});
check("state channel: counter survived the region replace", remounted.c === "3", JSON.stringify(remounted));
check("state channel: items restored with stable ids (k2, no dupes)", JSON.stringify(remounted.items) === JSON.stringify(["probe-item-k2"]), JSON.stringify(remounted.items));
check("state channel: event count restored + mount happened (data-island-events > 0)", remounted.ev !== null && Number(remounted.ev) > 0, String(remounted.ev));

// typing continues the restored state with the next key (k3, not k0)
await page.fill("#probe-field", "delta");
await page.waitForFunction(() => document.querySelector("#e2e #probe-list #probe-item-k3"), { timeout: 5000 });
check("state continued across remount: next insert gets k3 (no id reuse)", true);
await page.click("#probe-inc");
await page.waitForFunction(() => document.querySelector("#e2e #probe-counter") && document.querySelector("#e2e #probe-counter").textContent === "4", { timeout: 5000 });
check("counter continues across remount (+1 → '4')", true);

await browser.close();
close();
console.log("");
if (fail === 0) console.log(`e-island-e2e-real: ${pass} PASS, 0 FAIL (artifact ${wasmBytes.length} B)`);
else console.log(`e-island-e2e-real: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
