#!/usr/bin/env node
// designer/probes/e-input-desc.mjs — lane-E wave-1 (CONTINUUM_DX) probe: the
// DX-8e `data-webui-input` delivery wiring in islandRegionSubscribed /
// deliverIslandEvent. the descriptor (`data-webui-input='["key","composition"]'`)
// is a SIBLING of `data-webui-island-events` — the same JSON-array parser; its
// tokens are InputParity channel names (key/selection/clipboard/undo/composition)
// mapped from DOM event types by the engine's INPUT_CHAN table.
//
// assertions:
//   1. a region carrying ONLY data-webui-input='["key"]' receives keydowns as
//      {type:"key", key:<id>, data:{...}} — descriptor-gated subscription.
//   2. modifier booleans ride `data` (ctrlKey/shiftKey/altKey/metaKey as
//      booleans-as-strings) — the v2 modifier pre-seed.
//   3. space: the DOM spacebar arrives as key:" " (the wire form of
//      Key.printable(" ") per d-to-e; never "Space"/".space").
//   4. composition: a region declaring ["key","composition"] receives
//      composition events as {type:"composition", key:"composition", data:{...}}.
//   5. a DOM event outside the declared channels is NOT delivered (click in a
//      key-only region) — descriptor-gated, no silent cross-channel delivery.
//
// lane port 9271. probe exits non-zero on any failed assertion.

import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";
import { buildProbeWasm } from "./e-island-wasm.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9271;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

const bodyHtml = `
<div id="iv1" data-webui-island="iv1" data-webui-input='["key"]'></div>
<div id="iv2" data-webui-island="iv2" data-webui-input='["key","composition"]'></div>
`;

const probeWasm = buildProbeWasm();

const { base, server, close } = await startProbeServer(PORT, bodyHtml, {
  enginePath: join(ROOT, "designer/assets/webui-engine.js"),
  routes: {
    "/__assets/webui-iv1.wasm": { type: "application/wasm", body: Buffer.from(probeWasm) },
    "/__assets/webui-iv2.wasm": { type: "application/wasm", body: Buffer.from(probeWasm) },
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
const islandPayloads = (region) =>
  consoleLines
    .filter((l) => l.text.includes(`[island:${region}]`))
    .map((l) => l.text.replace(`[island:${region}] `, ""))
    .filter((t) => t.startsWith("{"))
    .map((t) => { try { return JSON.parse(t); } catch (e) { return null; } })
    .filter(Boolean);

await page.goto(base + "/");
await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });

// ---- mount both regions (same synthetic island, distinct module instances) ----
await page.waitForFunction(() =>
  document.getElementById("iv1") && document.getElementById("iv1").getAttribute("data-webui-island-state") === "mounted",
{ timeout: 10000 });
await page.waitForFunction(() =>
  document.getElementById("iv2") && document.getElementById("iv2").getAttribute("data-webui-island-state") === "mounted",
{ timeout: 10000 });
check("mount: iv1 and iv2 both mounted via the data-webui-input descriptor (no data-webui-island-events)", true);

// ---- 1+2: key channel via descriptor; modifiers ride data (v2 pre-seed) ----
await page.evaluate(() => {
  const region = document.getElementById("iv1");
  const input = document.createElement("input");
  input.id = "iv1-in";
  region.appendChild(input);
  input.focus();
});
await page.keyboard.type("a");
await page.waitForFunction(() => {
  const el = document.querySelector("#iv1 #lbl");
  return el && el.textContent === "1";
}, { timeout: 5000 });
const keyA = islandPayloads("iv1").find((p) => p.type === "key" && p.key === "a");
check("DX-8e: data-webui-input='[\"key\"]' delivers keydown as {type:\"key\", key:\"a\"}", !!keyA, JSON.stringify(islandPayloads("iv1")[0]));
check(
  "DX-8e: modifier booleans ride data (ctrlKey/shiftKey/altKey/metaKey — the v2 pre-seed)",
  !!keyA && keyA.data && typeof keyA.data === "object" && keyA.data.ctrlKey === "false" && keyA.data.shiftKey === "false" && keyA.data.altKey === "false" && keyA.data.metaKey === "false",
  JSON.stringify(keyA && keyA.data)
);

// ---- 3: space normalization — key stays " " (the .printable(" ") wire form) ----
await page.keyboard.press("Space");
await page.waitForFunction(() => {
  const el = document.querySelector("#iv1 #lbl");
  return el && el.textContent === "2";
}, { timeout: 5000 });
const spaceP = islandPayloads("iv1").find((p) => p.type === "key" && p.key === " ");
check("DX-8e: space key normalized to key:\" \" (single space scalar — .printable(' ') wire, never \"Space\")", !!spaceP, JSON.stringify(islandPayloads("iv1").at(-1)));

// ---- 4: composition channel on iv2 (["key","composition"]) ----
await page.evaluate(() => {
  const region = document.getElementById("iv2");
  const input = document.createElement("input");
  input.id = "iv2-in";
  region.appendChild(input);
  input.focus();
});
await page.evaluate(() => {
  const input = document.getElementById("iv2-in");
  input.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true, data: "" }));
  input.dispatchEvent(new CompositionEvent("compositionupdate", { bubbles: true, data: "héllo" }));
});
await page.waitForTimeout(300);
const compP = islandPayloads("iv2").find((p) => p.type === "composition" && p.data && p.data.data === "héllo");
check(
  "DX-8e: composition delivered as {type:\"composition\", key:\"composition\", data:{data,...}}",
  !!compP && compP.key === "composition" && compP.data && compP.data.data === "héllo",
  JSON.stringify(compP)
);

// ---- 5: ungated DOM events are NOT delivered (click in a key-only region) ----
await page.evaluate(() => {
  document.getElementById("iv1-in").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
});
await page.waitForTimeout(300);
const clickP = islandPayloads("iv1").find((p) => p.type === "click");
check("DX-8e: click in a key-only region is NOT delivered (descriptor-gated)", !clickP, clickP ? JSON.stringify(clickP) : "");

await browser.close();
close();
console.log("");
if (fail === 0) console.log(`e-input-desc: ${pass} PASS, 0 FAIL`);
else console.log(`e-input-desc: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
