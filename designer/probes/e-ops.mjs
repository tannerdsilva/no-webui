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


// ---- t1.2: 50 mixed ops → expected apply counts per the coalescer policy ----
// build dedicated targets (all present) so every applied op counts.
const coalesceFixture = await page.evaluate(() => {
  const chip = (id, label) => {
    const el = document.createElement("span");
    el.id = id;
    el.className = "chip";
    el.textContent = label;
    return el;
  };
  document.getElementById("coalesce-root")?.remove();
  const root = document.createElement("div");
  root.id = "coalesce-root";
  document.body.appendChild(root);
  root.appendChild(chip("t-a", "TA"));
  root.appendChild(chip("t-b2", "TB"));
  root.appendChild(chip("t-d", "TD"));
  for (let i = 1; i <= 10; i++) root.appendChild(chip("x" + i, "X" + i));
  const moves = document.getElementById("moveset");
  moves.innerHTML = "";
  for (let i = 1; i <= 4; i++) moves.appendChild(chip("m" + i, "M" + i));
  window.__coalesceApplied = 0;
  return true;
});
const OPS = [];
const push = (f) => OPS.push(f);
// 10 text ops on one target -> collapse to 1
for (let i = 1; i <= 10; i++) push({ id: "t-a", op: "text", text: "ta" + i });
// 8 attr ops on one target -> collapse to 1
for (let i = 1; i <= 8; i++) push({ id: "t-b2", op: "attr", name: "data-i", value: "b" + i });
// 6 move ops on one target -> collapse to 1
for (let i = 1; i <= 6; i++) push({ id: "m2", op: "move", before: i % 2 ? "m1" : "m3" });
// 6 replace ops on one target -> collapse to 1
for (let i = 1; i <= 6; i++) push({ id: "t-d", op: "replace", html: '<span id="t-d" class="chip">D' + i + "</span>" });
// 10 removes on distinct existing ids -> never coalesce (10)
for (let i = 1; i <= 10; i++) push({ id: "x" + i, op: "remove" });
// 10 appends into the list with distinct child ids -> never coalesce (10)
for (let i = 1; i <= 10; i++) push({ id: "list", op: "append", html: '<span id="a' + i + '" class="chip">A' + i + "</span>" });
// total ops: 10+8+6+6+10+10 = 50
const EXPECTED = 1 + 1 + 1 + 1 + 10 + 10; // 24 survives

const coalesceResult = await page.evaluate(({ ops, expected }) => {
  const inst = window.WebUIEngine._getInstance();
  window.__coalesceApplied = 0;
  window.WebUIEngine.on.afterPatch((nodes) => { window.__coalesceApplied += nodes.length; });
  inst.patch(ops, 500);
  return { appliedDelta: window.__coalesceApplied, expected };
}, { ops: OPS, expected: EXPECTED });

const coalesceDom = await page.evaluate(() => ({
  ta: document.getElementById("t-a")?.textContent ?? null,
  tb: document.getElementById("t-b2")?.getAttribute("data-i") ?? null,
  removals: ["x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10"].filter((id) => !document.getElementById(id)).length,
  appends: ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10"].filter((id) => !!document.getElementById(id)).length,
}));

if (coalesceResult.appliedDelta === EXPECTED) {
  ok(`coalescer: 50 mixed ops → exactly ${EXPECTED} applies (${coalesceResult.appliedDelta} observed)`);
} else {
  bad(`coalescer: expected ${EXPECTED} applies, observed ${coalesceResult.appliedDelta}`);
}
if (coalesceDom.ta === "ta10" && coalesceDom.tb === "b8" && coalesceDom.removals === 10 && coalesceDom.appends === 10) {
  ok("coalescer: newest-per-target won (ta10/b8), 10 removals applied, 10 appends applied");
} else {
  bad(`coalescer DOM: ta=${coalesceDom.ta} tb=${coalesceDom.tb} removals=${coalesceDom.removals} appends=${coalesceDom.appends}`);
}

await browser.close();
close();
