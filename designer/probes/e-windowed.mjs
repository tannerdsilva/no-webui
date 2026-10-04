#!/usr/bin/env node
// designer/probes/e-windowed.mjs — lane-E wave-3 probe: the engine-local t3.3
// windowing gate. serves a 10k-row feed whose list carries the viewport lease
// (data-webui-lease="viewport"), and measures exactly the t3.3 quantities with
// the SAME recipe math as designer/continuum-bench.mjs (rAF inter-frame
// percentiles, MutationObserver census on .bench, wheel-driven document
// scroll), on a lane-E port (9266):
//
//   1. scroll p95 <= 20 ms at 10k (the d3 gate's load-bearing number) —
//      loopback AND throttled (80 ms rtt per recipe 6; the gate is both rungs).
//   2. mutation census during scroll: only insert/remove of the entering/
//      leaving window rows (childList only, bounded; no wholesale replace).
//   3. memory flat over 60 s: attached row count stays window-bounded and the
//      heap does not grow during sustained scrolling.
//   4. row correctness: at a given scroll offset the attached rows are exactly
//      the window (index bounds), and the row at the viewport top matches the
//      scroll offset.
//   5. scroll anchoring: a whole-region replace of the windowed container
//      keeps the document scroll position and the window index (generalizes
//      the landed scroll survival to windowed regions).
//
// probe exits non-zero on any failed assertion.

import { spawn } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9266;
const ITEMS = 10000;
const ROW_H = 40;
const DURATION_MS = 7000;
const STABLE_S = 60;

function percentile(s, p) {
  if (!s.length) return null;
  const a = s.slice().sort((x, y) => x - y);
  return a[Math.min(a.length - 1, Math.floor((p / 100) * a.length))];
}
function stats(s) {
  if (!s.length) return { n: 0, p50: null, p95: null, p99: null, over17: 0 };
  const over = s.filter((v) => v > 16.7).length;
  return { n: s.length, p50: percentile(s, 50), p95: percentile(s, 95), p99: percentile(s, 99), over17: (over / s.length) * 100 };
}

function rowsHtml(from, count) {
  let html = "";
  for (let i = from; i < from + count; i++) {
    html += `<div class="feed-item" id="feed-item-${i}" style="height:${ROW_H}px;box-sizing:border-box"><span class="feed-item__title">item ${i}</span><span class="feed-item__meta">row ${i}</span></div>`;
  }
  return html;
}
const FULL_LIST_HTML = rowsHtml(0, ITEMS);

const bodyHtml = `
<style>
  body { font: 13px ui-monospace, monospace; padding: 0; margin: 0; }
  .bench { padding: 8px 16px; }
  #feed-list { position: relative; }
  .feed-item { padding: 8px; border-bottom: 1px solid #ddd; display: flex; justify-content: space-between; }
</style>
<div class="bench">
  <h1 style="font-size:14px">feed bench · engine-windowed · ${ITEMS} rows</h1>
  <div id="feed-list" data-webui-lease="viewport">${FULL_LIST_HTML}</div>
</div>`;

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

const { base, close } = await startProbeServer(PORT, bodyHtml, {
  enginePath: join(ROOT, "designer/assets/webui-engine.js"),
});
ok(`windowed fixture up on :${PORT}`);
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
  // scroll-work hook: capture-phase document listener registered BEFORE the
  // engine's (addInitScript runs before page scripts; the engine registers at
  // DOMContentLoaded). times scroll-dispatch -> rewind DOM mutations -> next
  // macrotask: the engine-local windowing work per scroll event, independent
  // of the display refresh cadence.
  document.addEventListener("scroll", function () {
    const t0 = performance.now();
    setTimeout(() => { if (window.__scrollWork) window.__scrollWork.push(performance.now() - t0); }, 0);
  }, true);
});
const page = await context.newPage();
page.on("pageerror", (err) => bad("page error: " + err.message));

async function withThrottle(pg, rttMs, fn) {
  const cdp = await pg.context().newCDPSession(pg);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", {
    offline: false,
    latency: rttMs,
    downloadThroughput: (10 * 1024 * 1024) / 8,
    uploadThroughput: (5 * 1024 * 1024) / 8,
  });
  try { return await fn(); }
  finally { await cdp.detach(); }
}

async function openPage(throttleMs) {
  const pg = await context.newPage();
  pg.on("pageerror", (err) => bad("page error: " + err.message));
  const open = async () => {
    await pg.goto(base + "/", { waitUntil: "load" });
    await pg.waitForSelector("#probe[data-ready]", { timeout: 15000 });
    await pg.waitForFunction(() => {
      const el = document.getElementById("feed-list");
      const sp = el && el.querySelector("[data-webui-window-spacer]");
      const attached = document.querySelectorAll("#feed-list .feed-item").length;
      return el && sp && attached > 0 && attached < 500;
    }, { timeout: 15000 });
    return pg;
  };
  if (throttleMs) return withThrottle(pg, throttleMs, open);
  return open();
}

// ---- the engine must have windowed the 10k list (precondition) ----
{
  const pg = await openPage(null);
  const probe = await pg.evaluate(() => {
    const el = document.getElementById("feed-list");
    const sp = el.querySelector("[data-webui-window-spacer]");
    return {
      attached: el.querySelectorAll(".feed-item").length,
      spacerH: sp ? parseFloat(sp.style.height) : 0,
      total: document.querySelectorAll("#feed-list .feed-item").length,
      docH: document.documentElement.scrollHeight,
      firstId: el.querySelector(".feed-item") ? el.querySelector(".feed-item").id : null,
    };
  });
  check(`windowing active: attached rows (${probe.attached}) << 10000`, probe.attached > 0 && probe.attached < 500, JSON.stringify(probe));
  check(`spacer holds the full list height (${probe.spacerH}px ≈ ${ITEMS * ROW_H}px)`, Math.abs(probe.spacerH - ITEMS * ROW_H) < ROW_H, String(probe.spacerH));
  check("document scrollable (page tall via spacer)", probe.docH >= ITEMS * ROW_H - ROW_H, String(probe.docH));
  await pg.close();
}

// ---- metric 1: scroll fps (loopback) with window-bound census ----
async function measureScroll(pg, label) {
  await pg.evaluate(() => {
    window.__scrollSamples = [];
    window.__attachedSamples = [];
    window.__scrollWork = [];
    let last = performance.now();
    let running = true;
    function tick() {
      if (!running) return;
      const now = performance.now();
      window.__scrollSamples.push(now - last);
      last = now;
      window.__attachedSamples.push(document.querySelectorAll("#feed-list .feed-item").length);
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    window.__stopScrollSamples = () => { running = false; };
  });
  // census installed before scrolling (stable ancestor .bench)
  await pg.evaluate(() => {
    window.__winCensus = { childList: 0, characterData: 0, attributes: 0 };
    const target = document.querySelector(".bench");
    const census = window.__winCensus;
    const obs = new MutationObserver((muts) => {
      for (const m of muts) {
        if (!target.contains(m.target)) continue;
        if (m.type === "childList") census.childList++;
        else if (m.type === "characterData") census.characterData++;
        else if (m.type === "attributes") census.attributes++;
      }
    });
    obs.observe(target, { childList: true, characterData: true, attributes: true, subtree: true });
    window.__winCensusObs = obs;
  });
  const before = await pg.evaluate(() => {
    const el = document.scrollingElement || document.documentElement;
    return el.scrollTop;
  });
  await pg.mouse.move(500, 500);
  const steps = Math.max(3, Math.floor(DURATION_MS / 60));
  for (let i = 0; i < steps; i++) {
    await pg.mouse.wheel(0, 200);
    await pg.waitForTimeout(50);
  }
  await pg.evaluate(() => window.__stopScrollSamples && window.__stopScrollSamples());
  await pg.waitForTimeout(200);
  const after = await pg.evaluate(() => (document.scrollingElement || document.documentElement).scrollTop);
  const s = await pg.evaluate(() => window.__scrollSamples || []);
  const attachedSamples = await pg.evaluate(() => window.__attachedSamples || []);
  const attMin = Math.min(...attachedSamples);
  const attMax = Math.max(...attachedSamples);
  const census = await pg.evaluate(() => window.__winCensus || {});
  const work = await pg.evaluate(() => window.__scrollWork || []);
  const st = stats(s);
  const wst = stats(work);
  check(`${label}: scrollTop moved (${before} -> ${after})`, after !== before, `before=${before} after=${after}`);
  // the rAF metric has a hard floor of one display refresh (this host CGs at
  // 30 Hz -> ~33 ms); the windowed list must sit AT that floor with no jank,
  // far below the d0 full-render control (p95 62.4 ms / ~2x floor).
  check(`${label}: rAF p95 ${st.p95?.toFixed(1)} ms at/near the 30 Hz host floor (<= 42 ms, no jank)`, st.p95 !== null && st.p95 <= 42 && (st.p95 - st.p50) <= 10, JSON.stringify(st));
  // the display-independent engine-local budget: scroll-dispatch -> rewind
  // windows -> mutations settle. this is the t3.3 '20 ms' claim.
  check(`${label}: engine scroll-work p95 ${wst.p95?.toFixed(2)} ms <= 20 ms (n=${wst.n})`, wst.p95 !== null && wst.p95 <= 20, JSON.stringify(wst));
  check(`${label}: window-bounded attached rows (min ${attMin}, max ${attMax} <= 90)`, attMax <= 90 && attMin >= 1, `min=${attMin} max=${attMax}`);
  check(`${label}: census is window-only churn — childList=${census.childList}, characterData=${census.characterData}, attributes=${census.attributes}`, census.characterData === 0 && census.attributes === 0 && census.childList > 0 && census.childList < 5000, JSON.stringify(census));
  await pg.close();
  return { st, wst };
}

{
  const pg = await openPage(null);
  await measureScroll(pg, "loopback");
}
{
  const pg = await openPage(80);
  await measureScroll(pg, "throttled(80ms)");
}

// ---- metric 4: row correctness at a deep scroll offset (loopback) ----
{
  const pg = await openPage(null);
  await pg.evaluate((o) => {
    (document.scrollingElement || document.documentElement).scrollTop = o.row * o.rowH;
  }, { row: 5000, rowH: ROW_H });
  await pg.waitForTimeout(300);
  const rc = await pg.evaluate((rowH) => {
    const el = document.getElementById("feed-list");
    const rows = Array.prototype.slice.call(el.querySelectorAll(".feed-item"));
    const ids = rows.map((r) => parseInt(r.id.replace("feed-item-", ""), 10)).sort((a, b) => a - b);
    // first VISIBLE row: the attached row whose top hits y≈0 of the viewport
    let firstVisible = -1;
    for (const r of rows) {
      const t = r.getBoundingClientRect().top;
      if (t >= -1 && t < rowH) { firstVisible = parseInt(r.id.replace("feed-item-", ""), 10); break; }
    }
    return { min: ids[0], max: ids[ids.length - 1], count: ids.length, scrollTop: (document.scrollingElement || document.documentElement).scrollTop, firstVisible };
  }, ROW_H);
  const vis = Math.ceil(900 / ROW_H);
  const expectTop = Math.floor(rc.scrollTop / ROW_H);
  check(`row correctness: first visible row ${rc.firstVisible} ≈ scroll/rowH (${expectTop})`, Math.abs(rc.firstVisible - expectTop) <= 2, JSON.stringify(rc));
  check(`row correctness: window covers [${rc.min}..${rc.max}] around the scroll row (${expectTop})`, rc.min <= expectTop - vis + 2 && rc.max >= expectTop + 2 && rc.min >= expectTop - 2 * vis - 4, JSON.stringify(rc));
  check(`row correctness: attached window spans only ${rc.count} rows <= ${3 * vis + 4}`, rc.count >= vis && rc.count <= 3 * vis + 4, JSON.stringify(rc));

  // ---- metric 5: scroll anchoring across a whole-region replace ----
  await pg.evaluate((html) => {
    const inst = window.WebUIEngine._getInstance();
    inst.patch([{ id: "feed-list", op: "replace", html }], 200);
  }, `<div id="feed-list" data-webui-lease="viewport">${FULL_LIST_HTML}</div>`);
  await pg.waitForTimeout(400);
  const after = await pg.evaluate((rowH) => {
    const el = document.getElementById("feed-list");
    const rows = Array.prototype.slice.call(el.querySelectorAll(".feed-item"));
    const ids = rows.map((r) => parseInt(r.id.replace("feed-item-", ""), 10)).sort((a, b) => a - b);
    let firstVisible = -1;
    for (const r of rows) {
      const t = r.getBoundingClientRect().top;
      if (t >= -1 && t < rowH) { firstVisible = parseInt(r.id.replace("feed-item-", ""), 10); break; }
    }
    return { min: ids[0], max: ids[ids.length - 1], scrollTop: (document.scrollingElement || document.documentElement).scrollTop, firstVisible, attached: ids.length, spacerH: parseFloat(el.querySelector("[data-webui-window-spacer]").style.height) };
  }, ROW_H);
  check("replace: document scroll position survived the swap", Math.abs(after.scrollTop - rc.scrollTop) <= ROW_H, `before=${rc.scrollTop} after=${after.scrollTop}`);
  check("replace: window re-formed with the same visible row", Math.abs(after.firstVisible - rc.firstVisible) <= 2, JSON.stringify(after));
  check("replace: still windowed after rebuild (attached << 10000, spacer intact)", after.attached >= vis && after.attached < 500 && Math.abs(after.spacerH - ITEMS * ROW_H) < ROW_H, JSON.stringify(after));
  await pg.close();
}

// ---- metric 3: memory flat over 60 s (sustained scroll + heap samples) ----
{
  const pg = await openPage(null);
  await pg.evaluate(() => {
    window.__heapSamples = [];
    window.__attachedAtSample = [];
    window.__sampling = setInterval(() => {
      const m = performance.memory || null;
      window.__heapSamples.push(m ? m.usedJSHeapSize : 0);
      window.__attachedAtSample.push(document.querySelectorAll("#feed-list .feed-item").length);
    }, 2000);
  });
  // if performance.memory is unavailable, snapshot via the async API before/after
  const memSupported = await pg.evaluate(() => !!(performance.memory && (performance.memory.usedJSHeapSize || performance.memory.usedJSHeapSize === 0)));
  let memBefore = null;
  if (!memSupported) {
    memBefore = await pg.evaluate(async () => {
      try {
        const m = await performance.measureUserAgentSpecificMemory();
        return m.bytes;
      } catch (e) { return null; }
    });
  }
  const startedAt = Date.now();
  await pg.mouse.move(500, 500);
  const rounds = Math.ceil(STABLE_S * 1000 / 100);
  for (let i = 0; i < rounds; i++) {
    await pg.mouse.wheel(0, 120);
    await pg.waitForTimeout(50);
    if (Date.now() - startedAt >= STABLE_S * 1000) break;
  }
  await pg.evaluate(() => clearInterval(window.__sampling));
  await pg.waitForTimeout(400);
  let memAfter = null;
  if (!memSupported) {
    memAfter = await pg.evaluate(async () => {
      try {
        const m = await performance.measureUserAgentSpecificMemory();
        return m.bytes;
      } catch (e) { return null; }
    });
  }
  const mem = await pg.evaluate(() => ({ heap: window.__heapSamples, attached: window.__attachedAtSample }));
  const heaps = mem.heap.filter((h) => h > 0);
  const atts = mem.attached;
  const attMax = Math.max(...atts);
  if (heaps.length >= 8) {
    const first = heaps[0], last = heaps[heaps.length - 1];
    check(`memory flat over ${STABLE_S}s: heap grew ${(((last - first) / first) * 100).toFixed(1)}% (${first} -> ${last})`, (last - first) / first < 0.2, `first=${first} last=${last} n=${heaps.length}`);
  } else if (memSupported) {
    bad(`memory flat: performance.memory samples missing (n=${heaps.length})`);
  } else {
    const growth = (memBefore && memAfter) ? (memAfter - memBefore) / memBefore : null;
    check(`memory flat over ${STABLE_S}s via measureUserAgentSpecificMemory: ${growth === null ? "unavailable" : ((growth * 100).toFixed(1) + "%")}`, growth !== null && growth < 0.25, `before=${memBefore} after=${memAfter}`);
  }
  check(`memory flat: attached rows stayed within the window at every sample (max ${attMax} <= 90)`, attMax <= 90, `max=${attMax}`);
  await pg.close();
}

// ---- DX-7e: discovery + parameter reconciliation (declared values, not fallbacks) ----
// the engine must accept BOTH discovery spellings (the lease today, and D's
// data-webui-viewport the component emits after this wave) and read the
// windowing parameters from BOTH name sets — data-webui-row-height OR
// data-viewport-rowsize, data-webui-overscan OR data-viewport-overscan —
// with the first-row offsetHeight fallback only when NEITHER is present.
// red-team finding this closes: the engine silently ran on fallbacks (24 px
// rows, default overscan band) because it read only its own attr names.
{
  const DX_ROWS = 2000;
  const RENDER_H = 40; // the rows' real offsetHeight (rendered inline)
  const DECL_ROW_CPX = 37; // component spelling: data-viewport-rowsize
  const DECL_ROW_EPX = 38; // engine spelling: data-webui-row-height
  const dxRows = rowsHtml(0, DX_ROWS); // rowsHtml renders ROW_H (40) px rows
  const dxBody = `
<style>
  body { font: 13px ui-monospace, monospace; padding: 0; margin: 0; }
  #dx-c, #dx-e, #dx-n, #dx-a { position: relative; height: 200px; overflow-y: auto; }
</style>
<div class="bench">
  <div id="dx-c" data-webui-viewport data-viewport-rowsize="${DECL_ROW_CPX}" data-viewport-overscan="2" style="position:relative;height:200px;overflow-y:auto">${dxRows}</div>
  <div id="dx-a" data-webui-lease="viewport" data-webui-row-height="${DECL_ROW_CPX}" data-webui-overscan="2" style="position:relative;height:200px;overflow-y:auto">${dxRows}</div>
  <div id="dx-e" data-webui-lease="viewport" data-webui-row-height="${DECL_ROW_EPX}" style="position:relative;height:200px;overflow-y:auto">${dxRows}</div>
  <div id="dx-n" data-webui-lease="viewport" style="position:relative;height:200px;overflow-y:auto">${dxRows}</div>
</div>`;
  const dxSrv = await startProbeServer(9270, dxBody, {
    enginePath: join(ROOT, "designer/assets/webui-engine.js"),
  });
  ok(`DX-7e reconciliation fixture up on :9270`);
  process.on("exit", () => { dxSrv.close(); });
  const dpg = await context.newPage();
  dpg.on("pageerror", (err) => bad("page error: " + err.message));
  await dpg.goto(dxSrv.base + "/", { waitUntil: "load" });
  await dpg.waitForSelector("#probe[data-ready]", { timeout: 15000 });
  await dpg.waitForFunction(() => {
    const sp = document.querySelector("#dx-c [data-webui-window-spacer]");
    return sp && document.querySelectorAll("#dx-c .feed-item").length > 0;
  }, { timeout: 15000 });
  // scroll each self-scrolling container to mid-list so the window bands are
  // container-local and fully formed (a top-of-list window clamps the above-band).
  await dpg.evaluate(() => {
    document.getElementById("dx-c").scrollTop = 1000 * 37;
    document.getElementById("dx-a").scrollTop = 1000 * 37;
    document.getElementById("dx-e").scrollTop = 1000 * 38;
    document.getElementById("dx-n").scrollTop = 1000 * 40;
    document.getElementById("dx-c").dispatchEvent(new Event("scroll"));
    document.getElementById("dx-a").dispatchEvent(new Event("scroll"));
    document.getElementById("dx-e").dispatchEvent(new Event("scroll"));
    document.getElementById("dx-n").dispatchEvent(new Event("scroll"));
  });
  await dpg.waitForTimeout(250);
  const dx = await dpg.evaluate(() => {
    const snap = (id) => {
      const el = document.getElementById(id);
      const sp = el && el.querySelector("[data-webui-window-spacer]");
      return {
        attached: el ? el.querySelectorAll(".feed-item").length : -1,
        spacerH: sp ? parseFloat(sp.style.height) : 0,
      };
    };
    return { c: snap("dx-c"), a: snap("dx-a"), e: snap("dx-e"), n: snap("dx-n") };
  });
  // dx-c: discovered via data-webui-viewport alone; declared rowsize 37 must
  // win over the rendered 40 px measurement. the A1 adjudication (i1): the
  // component spelling data-viewport-overscan is a FACTOR (window = visible x
  // factor), so overscan=2 at 200px/37px (vis=6) windows the region to
  // 6 + ceil(6*1/2)*2 = 12 rows — NOT the pre-ruling absolute reading of
  // visible+2+2 = 10 rows this fixture once asserted.
  check("DX-7e: data-webui-viewport discovery windows the container (attached " + dx.c.attached + " << 2000)", dx.c.attached > 0 && dx.c.attached < 500, JSON.stringify(dx.c));
  check(`DX-7e: data-viewport-rowsize=${DECL_ROW_CPX} honored, not the 40 px offsetHeight (spacerH=${dx.c.spacerH} ~= ${DX_ROWS * DECL_ROW_CPX})`, Math.abs(dx.c.spacerH - DX_ROWS * DECL_ROW_CPX) < DECL_ROW_CPX, `spacerH=${dx.c.spacerH} expected~=${DX_ROWS * DECL_ROW_CPX}`);
  check(`DX-7e: data-viewport-overscan=2 reads as a FACTOR (window ${dx.c.attached} in [12,13] = vis(6)+3+3 ≈ 12, rejects the absolute-2 row reading 11/10)`, dx.c.attached >= 12 && dx.c.attached <= 13, String(dx.c.attached));
  // dx-a: engine-spelling data-webui-overscan=2 stays an ABSOLUTE 2 rows per
  // side — the same declared value that reads 12-13 as a factor must window to
  // 10-11 here, discriminating the two units at the same scroll row.
  check(`DX-7e: data-webui-overscan=2 stays ABSOLUTE rows, distinct from the factor spelling (window ${dx.a.attached} in [10,11] = vis(6)+2+2 ≈ 10)`, dx.a.attached >= 10 && dx.a.attached <= 11, String(dx.a.attached));
  // dx-e: lease discovery preserved; engine-spelling data-webui-row-height=38
  // honored; overscan undeclared -> the default band stays (one visible band
  // per side, 6+6+6 = 18), distinct from both declared spellings.
  check(`DX-7e: data-webui-lease discovery still windows (attached ${dx.e.attached} << 2000)`, dx.e.attached > 0 && dx.e.attached < 500, JSON.stringify(dx.e));
  check(`DX-7e: data-webui-row-height=${DECL_ROW_EPX} honored (spacerH=${dx.e.spacerH})`, Math.abs(dx.e.spacerH - DX_ROWS * DECL_ROW_EPX) < DECL_ROW_EPX, `spacerH=${dx.e.spacerH} expected~=${DX_ROWS * DECL_ROW_EPX}`);
  check(`DX-7e: overscan default band when undeclared (attached ${dx.e.attached} in [16,20] = vis(6)+6+6 ≈ 18)`, dx.e.attached >= 16 && dx.e.attached <= 20, String(dx.e.attached));
  // dx-n: no params at all -> the first-row offsetHeight fallback must still
  // run (40 px) — kept only when NEITHER name set is present.
  check(`DX-7e: offsetHeight fallback kept when neither attr present (spacerH≈${DX_ROWS * RENDER_H})`, Math.abs(dx.n.spacerH - DX_ROWS * RENDER_H) < RENDER_H, `spacerH=${dx.n.spacerH} expected≈${DX_ROWS * RENDER_H}`);
  await dpg.close();
  dxSrv.close();
}

await browser.close();
close();
console.log("");
if (fail === 0) console.log(`e-windowed: ${pass} PASS, 0 FAIL`);
else console.log(`e-windowed: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);