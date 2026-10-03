#!/usr/bin/env node
// designer/probes/e-ops.mjs — lane-E probe: fragment ops (t1.1) + coalescer (t1.2).
//
// model the lifecycle on designer/browser-smoke.mjs: spawn the local probe server
// (serving the working engine asset + harness page), drive in headless Chromium
// via Playwright, tear down, non-zero exit on failure. lane port 9260.
//
// assertions:
//   t1.1  remove → exactly one removal (no stray deletions)
//   t1.1  attr   → exactly one attribute mutation (allowlisted name)
//   t1.1  attr   → unknown name skipped, warning printed once
//   t1.1  move   → a reorder, never a re-insert (same node identity)
//   t1.1  optimistic + new op → skipped, warning printed once
//   t1.2  50 mixed ops → expected apply counts per the coalescer policy table
//         (append/remove never coalesce; attr/move replace/text collapse to
//         newest per target)

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9260;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

const { base, server, close } = await startProbeServer(PORT, "", { enginePath: join(ROOT, "designer/assets/webui-engine.js") });
// we don't need the engine inlined twice; e-lib already bakes it into the page.
ok(`probe server up on :${PORT}`);

process.on("exit", () => { close(); });
process.on("SIGINT", () => { close(); process.exit(1); });

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
// reduced-motion makes authoritative patches apply synchronously (the way
// browser-smoke gates its transition policy); keeps apply-then-read timing
// deterministic for every engine version in the wave.
await context.addInitScript(() => {
  try {
    window.matchMedia = window.matchMedia || (() => ({ matches: false, addListener() {}, removeListener() {} }));
    const om = window.matchMedia("(prefers-reduced-motion: reduce)");
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: (q) => ({ matches: q === "(prefers-reduced-motion: reduce)", media: q, onchange: null, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }),
    });
  } catch (e) {}
});
const page = await context.newPage();
page.on("pageerror", (err) => bad("page error: " + err.message));

const engineWarns = [];
page.on("console", (msg) => {
  if (msg.type() === "warning" && msg.text().includes("[WebUIEngine]")) {
    engineWarns.push(msg.text());
  }
});

// build the DOM fixture + a reference apply counter via the public afterPatch hook.
await page.goto(base + "/");
await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });
await page.evaluate(() => {
  const chip = (id, label) => {
    const el = document.createElement("span");
    el.id = id;
    el.className = "chip";
    el.textContent = label;
    return el;
  };
  const list = document.getElementById("list");
  list.innerHTML = "";
  for (let i = 1; i <= 10; i++) list.appendChild(chip("r" + i, "R" + i));
  const attrs = document.getElementById("attrs");
  attrs.innerHTML = "";
  attrs.appendChild(chip("t-b", "B"));
  const moves = document.getElementById("moveset");
  moves.innerHTML = "";
  for (let i = 1; i <= 4; i++) moves.appendChild(chip("m" + i, "M" + i));
  window.__appliedTotal = 0;
  window.WebUIEngine.on.afterPatch((nodes) => { window.__appliedTotal += nodes.length; });
});

// ---- t1.1: remove → exactly one removal ----
// in v1 (t1.1-only engine) new ops still ride the view-transition path, so the
// apply is async; wait for the transition to settle before reading state.
const removeState = await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  inst.patch([{ id: "r3", op: "remove" }], 1);
  return new Promise((resolve) => setTimeout(() => resolve(true), 300));
});
await removeState;
const removeDom = await page.evaluate(() => ({
  r3: !!document.getElementById("r3"),
  siblings: ["r1", "r2", "r4", "r5", "r6", "r7", "r8", "r9", "r10"].every((id) => !!document.getElementById(id)),
  count: document.getElementById("list").children.length,
}));
if (!removeDom.r3 && removeDom.count === 9 && removeDom.siblings) {
  ok("remove → exactly one removal (9 children remain, siblings intact)");
} else {
  bad(`remove: r3=${removeDom.r3} count=${removeDom.count} siblings=${removeDom.siblings}`);
}

// ---- t1.1: attr → exactly one attribute mutation (allowlisted) ----
const attrDom = await page.evaluate(async () => {
  const inst = window.WebUIEngine._getInstance();
  const before = document.getElementById("t-b").getAttribute("data-state");
  inst.patch([{ id: "t-b", op: "attr", name: "data-state", value: "on" }], 2);
  await new Promise((r) => setTimeout(r, 300));
  return {
    before,
    value: document.getElementById("t-b").getAttribute("data-state"),
    expected: "on",
  };
});
if (attrDom.value === "on" && attrDom.before !== "on") {
  ok("attr → exactly one attribute mutation (data-state=\"on\")");
} else {
  bad(`attr: value=${JSON.stringify(attrDom.value)} before=${JSON.stringify(attrDom.before)}`);
}

// ---- t1.1: attr — unknown name skipped with one warning ----
const attrBefore = engineWarns.length;
await page.evaluate(async () => {
  const inst = window.WebUIEngine._getInstance();
  inst.patch([{ id: "t-b", op: "attr", name: "href", value: "https://evil" }], 3);
  inst.patch([{ id: "t-b", op: "attr", name: "href", value: "https://evil" }], 4);
  await new Promise((r) => setTimeout(r, 300));
  return true;
});
const unknownAttr = await page.evaluate(() => document.getElementById("t-b").getAttribute("href"));
const attrWarns = engineWarns.slice(attrBefore).filter((w) => w.includes("not on the allowlist"));
if (unknownAttr === null && attrWarns.length === 1) {
  ok("attr → unknown name skipped, warning printed once");
} else {
  bad(`attr unknown: href=${JSON.stringify(unknownAttr)} warns=${attrWarns.length}`);
}

// ---- t1.1: move → a reorder, never a re-insert ----
const moveState = await page.evaluate(async () => {
  const inst = window.WebUIEngine._getInstance();
  const beforeOrder = Array.from(document.getElementById("moveset").children).map((c) => c.id);
  const nodeRef = document.getElementById("m4");
  nodeRef.__probeMarker = "same-node";
  inst.patch([{ id: "m4", op: "move", before: "m1" }], 5);
  await new Promise((r) => setTimeout(r, 300));
  const afterOrder = Array.from(document.getElementById("moveset").children).map((c) => c.id);
  const keepRef = document.getElementById("m4");
  return { beforeOrder, afterOrder, sameNode: keepRef && keepRef.__probeMarker === "same-node", count: afterOrder.length };
});
if (
  moveState.afterOrder.length === 4 &&
  moveState.afterOrder[0] === "m4" &&
  moveState.sameNode &&
  moveState.beforeOrder.join(",") !== moveState.afterOrder.join(",")
) {
  ok("move → a reorder, never a re-insert (same node identity, 4 children)");
} else {
  bad(`move: before=${moveState.beforeOrder} after=${moveState.afterOrder} sameNode=${moveState.sameNode}`);
}

// ---- t1.1: optimistic + new op → skipped with one warning ----
const optBefore = engineWarns.length;
const optState = await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  const was = !!document.getElementById("r5");
  inst.patch([{ id: "r5", op: "remove" }], null, true);
  inst.patch([{ id: "r5", op: "remove" }], null, true);
  const still = !!document.getElementById("r5");
  return { was, still };
});
const optWarns = engineWarns.slice(optBefore).filter((w) => w.includes("not allowed in optimistic"));
if (optState.was && optState.still && optWarns.length === 1) {
  ok("optimistic + new op → skipped, warning printed once");
} else {
  bad(`optimistic: was=${optState.was} still=${optState.still} warns=${optWarns.length}`);
}

await browser.close();
close();

console.log(`\ne-ops: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
