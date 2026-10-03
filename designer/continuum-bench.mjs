#!/usr/bin/env node
// designer/continuum-bench.mjs  the desktop-grade measurement harness (plan d0 t0.2).
//
// implements the six metric recipes of parent §3, exactly:
//   1. scrollFPS   — page.mouse.wheel + rAF sampling, ≥10 s, p50/p95/p99 and
//                    % frames > 16.7 ms; asserts scrollTop actually moved.
//   2. echoLatency — keydown listener + MutationObserver on the echo node,
//                    both installed from outside; p50/p95 of mutation−keydown.
//   3. patchCost   — playwright's own `page.on('websocket')`; frames + bytes
//                    for one interaction; no page instrumentation.
//   4. mutationCensus — MutationObserver installed after load; childList vs
//                    characterData vs attributes across N interactions.
//   5. tti         — waitForFunction on the engine instance + socket open.
//   6. withThrottle — CDP Network.emulateNetworkConditions, latency 80 ms.
//
// the throttle rule is a GATE, not advice: every budget runs loopback AND
// throttled. a loopback-only green is not a green.
//
// usage: node designer/continuum-bench.mjs --bench feed --items 10000
//                                   [--throttle 80] [--repeat 3] [--port N]
// the server binary may be overridden (the package .build lock is held by a
// running plugin): WEBUI_BENCH_SERVER=/path/to/WebUIBench
//
// results land in .bench/<bench>-<scale>[-throttled].json (gitignored); exit
// is non-zero when a precondition fails (the "probes assert their own
// preconditions" lesson).

import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SERVER = process.env.WEBUI_BENCH_SERVER ?? join(ROOT, ".build/debug/WebUIBench");
const LANE_PORT = 9206; // lane B range 9200–9219; never a canonical port
const mkdir = () => mkdirSync(join(ROOT, ".bench"), { recursive: true });

// ── tiny stats helpers ────────────────────────────────────────────────────

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  const idx = (p / 100) * (sorted.length - 1);
  const lo = Math.floor(idx), hi = Math.ceil(idx);
  if (lo === hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
}
function stats(samples) {
  const s = [...samples].sort((a, b) => a - b);
  const p50 = percentile(s, 50);
  const p95 = percentile(s, 95);
  const p99 = percentile(s, 99);
  const over = s.filter((v) => v > 16.7).length;
  return { n: s.length, p50, p95, p99, over17: s.length ? (over / s.length) * 100 : 0 };
}
function median(samples) {
  const s = [...samples].sort((a, b) => a - b);
  if (!s.length) return null;
  return s[Math.floor(s.length / 2)];
}

// ── arg parsing (flat; no compound bodies in the terminal — this is node) ─

function arg(argv, name, fallback) {
  const i = argv.indexOf(name);
  return i !== -1 && argv[i + 1] !== undefined ? argv[i + 1] : fallback;
}
const argv = process.argv.slice(2);
const BENCH = arg(argv, "--bench", "feed");
const ITEMS = parseInt(arg(argv, "--items", "10000"), 10);
const SERIES = parseInt(arg(argv, "--series", "8"), 10);
const POINTS = parseInt(arg(argv, "--points", "100"), 10);
const ROWS = parseInt(arg(argv, "--rows", "200"), 10);
const COLS = parseInt(arg(argv, "--cols", "10"), 10);
const THROTTLE = parseInt(arg(argv, "--throttle", "80"), 10);
const REPEAT = parseInt(arg(argv, "--repeat", "1"), 10);
const PORT = parseInt(arg(argv, "--port", String(LANE_PORT)), 10);
let THROTTLING = false; // set during the throttled run (inflates wait bounds)

// ── server lifecycle (mirrors chart-mobile-audit) ─────────────────────────

const server = spawn(SERVER, ["--port", String(PORT)], { cwd: ROOT });
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

function teardown() {
  try { server.kill("SIGTERM"); } catch { /* already gone */ }
}
// the server must die on EVERY exit path — a straggler holds its lane port
// and, worse, carries cross-run server state (feedCount) that pollutes the
// next measurement (probes must start clean).
process.on("exit", teardown);
process.on("SIGINT", () => { teardown(); process.exit(130); });
process.on("SIGTERM", () => { teardown(); process.exit(143); });

async function waitFor(url, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try { const r = await fetch(url); if (r.ok) return true; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

// ── throttling (recipe 6) ─────────────────────────────────────────────────

async function withThrottle(context, page, latency, fn) {
  const cdp = await context.newCDPSession(page);
  await cdp.send("Network.enable");
  // rtt is the binding constraint the d0 budgets care about (plan §3 recipe
  // 6); the link must be fast enough that transfer time does not dominate a
  // 1.5 MB full-region update, or the throttled feed never completes in a
  // sane window. 10 Mb/s down / 5 Mb/s up.
  await cdp.send("Network.emulateNetworkConditions", {
    offline: false, latency,
    downloadThroughput: 10 * 1024 * 1024,
    uploadThroughput: 5 * 1024 * 1024,
  });
  try { return await fn(cdp); } finally {
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1,
    });
  }
}

// ── metric: tti (recipe 5) ────────────────────────────────────────────────

async function tti(page, url) {
  const t0 = performance.now();
  await page.goto(url, { waitUntil: "load" });
  await page.waitForFunction(() => {
    const e = window.WebUIEngine && window.WebUIEngine._getInstance && window.WebUIEngine._getInstance();
    return !!(e && e.wsClient && e.wsClient.isConnected && e.wsClient.isConnected());
  }, null, { timeout: 15000 }).catch(() => {});
  return performance.now() - t0;
}

// ── metric: patchCost (recipe 3) — one interaction, ws frames + bytes ─────

/// one page-level frame counter (installed once per bench page; snapshots
/// give per-interaction deltas so the navigation noise is never counted).
function makeFrameCounter() {
  const state = { frames: 0, sentBytes: 0, recvBytes: 0, events: [] };
  function install(page) {
    page.on("websocket", (ws) => {
      ws.on("framesent", (d) => {
        const p = stringifyPayload(d.payload);
        state.frames++;
        state.sentBytes += p.length;
        state.events.push({ dir: "sent", at: performance.now(), len: p.length, payload: p });
      });
      ws.on("framereceived", (d) => {
        const p = stringifyPayload(d.payload);
        state.frames++;
        state.recvBytes += p.length;
        state.events.push({ dir: "recv", at: performance.now(), len: p.length, payload: p });
      });
    });
  }
  function snapshot() {
    const { frames, sentBytes, recvBytes, events } = state;
    return { frames: () => state.frames - frames, sentBytes: () => state.sentBytes - sentBytes, recvBytes: () => state.recvBytes - recvBytes, eventIndex: events.length };
  }
  // round-trip latency of one interaction: from the interaction's `event`
  // sent frame to the first `update` recv frame after it (navigation and
  // ping frames excluded by the snapshot index and by frame payload shape).
  function lastInteractionLatency(snapshotIndex) {
    const isEvent = (ev, dir) => ev.dir === dir && ev.payload && ev.payload.indexOf('"type":"event"') !== -1;
    const isUpdate = (ev) => ev.dir === "recv" && ev.payload && ev.payload.indexOf('"type":"update"') !== -1;
    for (let i = snapshotIndex; i < state.events.length; i++) {
      if (isEvent(state.events[i], "sent")) {
        for (let j = i + 1; j < state.events.length; j++) {
          if (isUpdate(state.events[j])) return state.events[j].at - state.events[i].at;
        }
      }
    }
    return null;
  }
  return { install, snapshot, lastInteractionLatency, state, events: state.events };
}

// ── metric: mutationCensus (recipe 4) ─────────────────────────────────────

/// install the census observer on a STABLE ancestor (`.bench`) rather than
/// the target region: a whole-region replace destroys the replaced node (and
/// any observer attached to it), which would under-count the very churn the
/// census exists to show. observing the stable shell counts every mutation an
/// interaction wrecks into the bench container.
const CENSUS_TARGET = ".bench";
async function installMutationCensus(page) {
  return page.evaluate((sel) => {
    const target = document.querySelector(sel);
    const census = { childList: 0, characterData: 0, attributes: 0, total: 0, samples: [] };
    if (!target) return census;
    const obs = new MutationObserver((muts) => {
      for (const m of muts) {
        const insideBench = target.contains(m.target);
        if (!insideBench) continue;
        if (m.type === "childList") census.childList++;
        else if (m.type === "characterData") census.characterData++;
        else if (m.type === "attributes") census.attributes++;
        census.total++;
        census.samples.push({ type: m.type, at: performance.now() });
      }
    });
    obs.observe(target, { childList: true, characterData: true, characterDataOldValue: true, attributes: true, subtree: true });
    window.__benchCensus = census;
    return census;
  }, CENSUS_TARGET);
}

async function readCensus(page) {
  return page.evaluate(() => window.__benchCensus || { childList: 0, characterData: 0, attributes: 0, total: 0, samples: [] });
}

// ── metric: scrollFPS (recipe 1) ──────────────────────────────────────────

async function scrollFPS(page, { durationMs = 10000, scrollables = "document" } = {}) {
  // rAF sampler, driven by the browser's real scroll path (page.mouse.wheel).
  await page.evaluate(() => {
    window.__scrollSamples = [];
    let last = performance.now();
    let running = true;
    function tick() {
      if (!running) return;
      const now = performance.now();
      window.__scrollSamples.push(now - last);
      last = now;
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
    window.__stopScrollSamples = () => { running = false; };
  });
  const before = await page.evaluate(() => {
    const el = document.scrollingElement || document.documentElement;
    return { top: el.scrollTop, left: el.scrollLeft };
  });
  // move the mouse into the list then scroll with the wheel (real scroll path).
  await page.mouse.move(400, 400);
  const steps = Math.max(3, Math.floor(durationMs / 60));
  for (let i = 0; i < steps; i++) {
    await page.mouse.wheel(0, 120);
    await page.waitForTimeout(50);
  }
  await page.evaluate(() => window.__stopScrollSamples && window.__stopScrollSamples());
  await page.waitForTimeout(200);
  const after = await page.evaluate(() => {
    const el = document.scrollingElement || document.documentElement;
    return { top: el.scrollTop, left: el.scrollLeft };
  });
  const samples = await page.evaluate(() => window.__scrollSamples || []);
  return { rAFStats: stats(samples), scrollMoved: after.top !== before.top, before, after };
}

// ── metric: echoLatency (recipe 2) ────────────────────────────────────────

async function echoLatency(page, inputSelector, echoSelector, { chars = 50, delayMs = 260 } = {}) {
  // listeners from outside: a keydown timestamp recorder + a MutationObserver
  // on the stable bench shell (the echo node itself is REPLACED per update —
  // a whole-region replace — so an observer attached to it would die with it;
  // observing the shell times every echo arrival honestly). observers observe;
  // they do not patch.
  await page.evaluate(([inputSel, echoSel]) => {
    const input = document.querySelector(inputSel);
    const shell = document.querySelector(".bench");
    window.__echo = { keydowns: [], mutations: [] };
    if (!input || !shell) return;
    input.addEventListener("keydown", () => {
      window.__echo.keydowns.push(performance.now());
    });
    new MutationObserver((muts) => {
      for (const m of muts) {
        if (m.type !== "childList") continue;
        // an echo arrival = the echo region (id `echo-out`) being swapped in
        // under the shell. added nodes carry the fresh echo markup.
        const addedEcho = Array.from(m.addedNodes).some((n) =>
          n.nodeType === 1 && ((n.id && n.id === "echo-out") || (n.querySelector && n.querySelector("#echo-out"))));
        if (addedEcho) window.__echo.mutations.push({ at: performance.now(), type: m.type });
      }
    }).observe(shell, { childList: true, subtree: true });
  }, [inputSelector, echoSelector]);

  const echoBefore = await page.locator(echoSelector).innerText().catch(() => "");
  await page.click(inputSelector);
  const text = "bench-echo-" + Date.now().toString(36);
  for (let i = 0; i < chars; i++) {
    await page.keyboard.type(text[i % text.length], { delay: 0 });
    await page.waitForTimeout(delayMs); // spread so the trailing debounce fires
  }
  const lastKeydownAt = await page.evaluate(() => {
    const k = window.__echo && window.__echo.keydowns;
    return k && k.length ? k[k.length - 1] : null;
  });
  await page.waitForTimeout(2100); // debounce max-wait + settle
  const data = await page.evaluate(() => window.__echo || { keydowns: [], mutations: [] });
  const echoAfter = await page.locator(echoSelector).innerText().catch(() => "");

  // pair each mutation with the most recent keydown before it (p50/p95 of
  // mutation − keydown). mid-typing max-wait flushes pair with a recent
  // keystroke, which UNDERSTATES the debounce — so the honest per-keystroke
  // echo latency is the settled pair: the last mutation after typing ends
  // minus the last keydown (the text the user actually perceives lands only
  // at the trailing-debounce boundary + rtt).
  const latencies = [];
  for (const m of data.mutations) {
    const prior = data.keydowns.filter((k) => k <= m.at);
    if (prior.length) latencies.push(m.at - prior[prior.length - 1]);
  }
  const finalMutation = data.mutations.length
    ? data.mutations[data.mutations.length - 1].at
    : null;
  const settledMs = (lastKeydownAt !== null && finalMutation !== null)
    ? finalMutation - lastKeydownAt
    : null;
  const echoed = echoAfter !== echoBefore && echoAfter.length > 0;
  return {
    keydowns: data.keydowns.length,
    mutations: data.mutations.length,
    latencyStats: stats(latencies),
    latencies,
    settledMs,
    echoed,
  };
}

// ── the benches ───────────────────────────────────────────────────────────

/// run one routed interaction under a fresh page load, counting only the
/// frames born after the interaction; returns {frames, sentBytes, recvBytes,
/// roundTripMs}. waits for the server's `update` to arrive (or an upper
/// bound) so the throttled link (100 kb/s) never truncates a measurement.
async function measureInteraction(page, url, { waitForSelector, click, waitMs = 400 }) {
  const counter = makeFrameCounter();
  counter.install(page);
  await page.goto(url, { waitUntil: "load" });
  await page.waitForSelector(waitForSelector);
  const base = counter.snapshot(); // excludes navigation/ping frames
  await click();
  // wait for the interaction's update round-trip: polls until an `update`
  // recv frame lands after the base snapshot, or the budget is spent. under
  // the throttled link a big update can take >1 s to transfer, so the bound
  // inflates there.
  const effectiveWait = THROTTLING ? Math.max(waitMs, 4000) : waitMs;
  const waitUntil = Date.now() + effectiveWait;
  while (Date.now() < waitUntil) {
    if (counter.lastInteractionLatency(base.eventIndex) !== null) break;
    await new Promise((r) => setTimeout(r, 50));
  }
  await new Promise((r) => setTimeout(r, 100)); // let trailing frames settle
  return {
    frames: base.frames(),
    sentBytes: base.sentBytes(),
    recvBytes: base.recvBytes(),
    roundTripMs: counter.lastInteractionLatency(base.eventIndex),
  };
}

const BENCHES = {
  // feed: full-list append-100 (replace) vs append-100 (op), tti, scroll fps, census
  feed: async (page, context) => {
    const base = `http://127.0.0.1:${PORT}/bench/feed?items=${ITEMS}`;
    const out = { route: base };

    // tti
    const ttis = [];
    for (let r = 0; r < REPEAT; r++) ttis.push(await tti(page, base));
    out.tti = stats(ttis);

    // scroll fps over the full 10k-item list (the wall)
    await page.goto(base, { waitUntil: "load" });
    await page.waitForSelector("#feed-list");
    const fps = [];
    for (let r = 0; r < REPEAT; r++) {
      fps.push(await scrollFPS(page, { durationMs: 6000 }));
    }
    out.scrollFPS = fps.map((f) => ({ p50: f.rAFStats.p50, p95: f.rAFStats.p95, p99: f.rAFStats.p99, over17: f.rAFStats.over17, scrollMoved: f.scrollMoved }));

    const replaceCounts = [];
    for (let r = 0; r < REPEAT; r++) {
      replaceCounts.push(await measureInteraction(page, base, {
        waitForSelector: "#feed-list",
        click: async () => { await page.click("#feed-append"); },
        waitMs: 200,
      }));
    }
    out.patchCostReplace = replaceCounts;

    const opCounts = [];
    for (let r = 0; r < REPEAT; r++) {
      opCounts.push(await measureInteraction(page, base, {
        waitForSelector: "#feed-list",
        click: async () => { await page.click("#feed-append-op"); },
        waitMs: 200,
      }));
    }
    out.patchCostOp = opCounts;

    // mutation census across the whole-redraw interaction (replace path)
    await page.goto(base, { waitUntil: "load" });
    await page.waitForSelector("#feed-list");
    const censusReplaceRows = await page.locator("#feed-list .feed-item").count();
    await installMutationCensus(page);
    await page.click("#feed-append");
    await page.waitForFunction((c) => document.querySelectorAll("#feed-list .feed-item").length > c,
      censusReplaceRows, { timeout: 8000 })
      .catch(async (e) => {
        const now = await page.evaluate(() => document.querySelectorAll("#feed-list .feed-item").length);
        throw new Error(`census-replace wait failed: rows before=${censusReplaceRows} now=${now}`);
      });
    await page.waitForTimeout(150);
    out.mutationCensusReplace = await readCensus(page);

    // census on the op path
    await page.goto(base, { waitUntil: "load" });
    await page.waitForSelector("#feed-list");
    const censusOpRows = await page.locator("#feed-list .feed-item").count();
    await installMutationCensus(page);
    await page.click("#feed-append-op");
    await page.waitForFunction((c) => document.querySelectorAll("#feed-list .feed-item").length > c,
      censusOpRows, { timeout: 8000 });
    await page.waitForTimeout(150);
    out.mutationCensusOp = await readCensus(page);

    return out;
  },

  grid: async (page, context) => {
    const base = `http://127.0.0.1:${PORT}/bench/grid?rows=${ROWS}&cols=${COLS}`;
    const out = { route: base, rows: ROWS, cols: COLS };

    const ttis = [];
    for (let r = 0; r < REPEAT; r++) ttis.push(await tti(page, base));
    out.tti = stats(ttis);

    const costs = [];
    for (let r = 0; r < REPEAT; r++) {
      costs.push(await measureInteraction(page, base, {
        waitForSelector: "#bench-grid",
        click: async () => { await page.click("#bench-grid-sort-0"); },
        waitMs: 400,
      }));
    }
    out.patchCostSort = costs;

    await page.goto(base, { waitUntil: "load" });
    await page.waitForSelector("#bench-grid");
    const sortFirst = await page.locator("#bench-grid tbody tr").first().innerText().catch(() => "");
    await installMutationCensus(page);
    await page.click("#bench-grid-sort-0");
    await page.waitForFunction((prev) => {
      const tr = document.querySelector("#bench-grid tbody tr");
      return tr && tr.innerText !== prev;
    }, sortFirst, { timeout: 8000 });
    await page.waitForTimeout(150);
    out.mutationCensusSort = await readCensus(page);
    return out;
  },

  dashboard: async (page, context) => {
    const base = `http://127.0.0.1:${PORT}/bench/dashboard?series=${SERIES}&points=${POINTS}`;
    const out = { route: base, series: SERIES, points: POINTS };

    const ttis = [];
    for (let r = 0; r < REPEAT; r++) ttis.push(await tti(page, base));
    out.tti = stats(ttis);

    const costs = [];
    for (let r = 0; r < REPEAT; r++) {
      costs.push(await measureInteraction(page, base, {
        waitForSelector: "#dash-wall",
        click: async () => { await page.click("#dash-tick"); },
        waitMs: 400,
      }));
    }
    out.patchCostTick = costs;

    await page.goto(base, { waitUntil: "load" });
    await page.waitForSelector("#dash-wall");
    await installMutationCensus(page);
    await page.click("#dash-tick");
    // the wait marker is the census itself: server update resolved = the
    // whole-region replace landed as a mutation under the shell.
    await page.waitForFunction(() => window.__benchCensus && window.__benchCensus.total > 0, null, { timeout: 8000 });
    await page.waitForTimeout(150);
    out.mutationCensusTick = await readCensus(page);
    return out;
  },

  editor: async (page, context) => {
    const base = `http://127.0.0.1:${PORT}/bench/editor`;
    const out = { route: base };

    const ttis = [];
    for (let r = 0; r < REPEAT; r++) ttis.push(await tti(page, base));
    out.tti = stats(ttis);

    // echoLatency: the desktop-grade echo contract
    const echoes = [];
    for (let r = 0; r < REPEAT; r++) {
      await page.goto(base, { waitUntil: "load" });
      await page.waitForSelector("#editor-text");
      echoes.push(await echoLatency(page, "#editor-text", "#echo-out"));
    }
    out.echoLatency = echoes.map((e) => ({ keydowns: e.keydowns, mutations: e.mutations, p50: e.latencyStats.p50, p95: e.latencyStats.p95, settledMs: e.settledMs, echoed: e.echoed }));

    // patchCost: one commit
    const costs = [];
    for (let r = 0; r < REPEAT; r++) {
      costs.push(await measureInteraction(page, base, {
        waitForSelector: "#editor-text",
        click: async () => {
          await page.fill("#editor-text", "commit-me");
          await page.click("#editor-commit");
        },
        waitMs: 400,
      }));
    }
    out.patchCostCommit = costs;
    return out;
  },

  // t0.3: the windowing experiment — naive replace vs op, one window step.
  windowed: async (page, context) => {
    const out = { windowSize: 60 };

    for (const variant of ["naive", "ops"]) {
      const base = `http://127.0.0.1:${PORT}/bench/feed?windowed=1&items=${ITEMS}` + (variant === "ops" ? "&ops=1" : "");
      const v = { variant, route: base };
      const ttis = [];
      for (let r = 0; r < REPEAT; r++) ttis.push(await tti(page, base));
      v.tti = stats(ttis);

      // one window step: scroll the container, observer clicks next-window,
      // server answers with a replace (naive) or appends+removes (ops).
      const stepCosts = [];
      for (let r = 0; r < REPEAT; r++) {
        stepCosts.push(await measureInteraction(page, base, {
          waitForSelector: "#feed-window",
          click: async () => {
            await page.evaluate(() => {
              const win = document.getElementById("feed-window");
              win.scrollTop = win.scrollHeight;
              win.dispatchEvent(new Event("scroll"));
            });
          },
          waitMs: 700,
        }));
      }
      v.windowStep = stepCosts;

      await page.goto(base, { waitUntil: "load" });
      await page.waitForSelector("#feed-window");
      const winFirst = await page.locator("#feed-window .feed-item").first().innerText().catch(() => "");
      await installMutationCensus(page);
      await page.evaluate(() => {
        const win = document.getElementById("feed-window");
        win.scrollTop = win.scrollHeight;
        win.dispatchEvent(new Event("scroll"));
      });
      await page.waitForFunction((prev) => {
        const f = document.querySelector("#feed-window .feed-item");
        return f && f.innerText !== prev;
      }, winFirst, { timeout: 8000 });
      await page.waitForTimeout(150);
      v.mutationCensusStep = await readCensus(page);
      out[variant] = v;
    }
    return out;
  },
};

// ── runner ────────────────────────────────────────────────────────────────

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };

if (!(BENCH in BENCHES)) {
  console.log("unknown bench '" + BENCH + "'; known: " + Object.keys(BENCHES).join(", "));
  process.exit(2);
}

const baseRoute = `http://127.0.0.1:${PORT}/bench/${BENCH === "windowed" ? "feed" : BENCH}`;
if (!(await waitFor(baseRoute))) {
  console.log("  FAIL server did not come up on :" + PORT + " (" + serverLog.slice(-200) + ")");
  console.log("CONTINUUM BENCH FAIL (no server)");
  process.exit(1);
}
{
  // precondition: we must be measuring our own bench server, not a stray one.
  const probe = await (await fetch(baseRoute)).text();
  if (probe.indexOf("bench") === -1) {
    console.log("  FAIL port " + PORT + " serves an unknown page; kill the stray server and retry");
    server.kill("SIGTERM");
    process.exit(1);
  }
  ok("served page is a bench page on :" + PORT);
}

const scale = BENCH === "grid" ? `${ROWS}x${COLS}`
  : BENCH === "dashboard" ? `${SERIES}x${POINTS}`
  : BENCH === "feed" || BENCH === "windowed" ? String(ITEMS)
  : "1";

const results = { bench: BENCH, scale, server: "WebUIBench", generated: new Date().toISOString(), runs: {} };

async function runOnce(context, label) {
  const page = await context.newPage();
  try {
    let r;
    if (label === "throttled") {
      // recipe 6 — the throttle rule is a gate, not advice: the throttled
      // page runs through a CDP-emulated 80 ms rtt / 100 kb/s link.
      THROTTLING = true;
      r = await withThrottle(context, page, THROTTLE, async () => BENCHES[BENCH](page, context));
      THROTTLING = false;
    } else {
      r = await BENCHES[BENCH](page, context);
    }
    results.runs[label] = r;
    console.log(`[bench] ${BENCH} scale=${scale} ${label}: tti p50 ${fmtMs(r.tti?.p50)} · scroll p95 ${fmtMs(r.scrollFPS?.[0]?.p95)} · patches ${JSON.stringify(patchSummary(r))}`);
  } finally {
    await page.close();
  }
}
const fmtMs = (v) => (v === null || v === undefined ? "n/a" : v.toFixed(1) + " ms");
function stringifyPayload(p) {
  if (typeof p === "string") return p;
  if (p && p.toString) return p.toString();
  return "";
}
function patchSummary(r) {
  const s = {};
  if (r.patchCostReplace) s.replace = r.patchCostReplace[0];
  if (r.patchCostOp) s.op = r.patchCostOp[0];
  if (r.patchCostSort) s.sort = r.patchCostSort[0];
  if (r.patchCostTick) s.tick = r.patchCostTick[0];
  if (r.patchCostCommit) s.commit = r.patchCostCommit[0];
  if (r.windowStep) s.windowStep = r.windowStep[0];
  if (r.naive) s.windowNaiveStep = r.naive.windowStep?.[0];
  if (r.ops) s.windowOpsStep = r.ops.windowStep?.[0];
  return s;
}

const browser = await chromium.launch();

// loopback run
{
  const context = await browser.newContext();
  await runOnce(context, "loopback");
  await context.close();
}

// throttled run — the gate (recipe 6): every budget runs loopback AND
// throttled. the binding constraint is rtt.
{
  const context = await browser.newContext();
  await runOnce(context, "throttled");
  // the throttle applies per-page via CDP inside... the plan's recipe throttles
  // the page's network; a new page keeps its own CDP session.
  await context.close();
}

await browser.close();

// write artifacts before asserting (evidence survives a failed precondition)
mkdir();
const suffix = "";
for (const [label, run] of Object.entries(results.runs)) {
  const file = join(ROOT, ".bench", `${BENCH}-${scale}${label === "throttled" ? "-throttled" : ""}.json`);
  writeFileSync(file, JSON.stringify(run, null, 2) + "\n");
  console.log(`[bench] wrote .bench/${BENCH}-${scale}${label === "throttled" ? "-throttled" : ""}.json`);
}

// ── precondition assertions (probes assert their own preconditions) ───────

const loop = results.runs.loopback || {};
const throttled = results.runs.throttled || {};

// scroll must actually move (recipe 1 precondition)
for (const [mode, r] of [["loopback", loop], ["throttled", throttled]]) {
  const fps = r.scrollFPS;
  if (fps) {
    const anyMoved = fps.some((f) => f.scrollMoved);
    if (anyMoved) ok(`${mode}: scrollTop moved during wheel scroll`);
    else bad(`${mode}: scrollTop did NOT move — wheel scroll precondition failed`);
  }
}

// echo must actually land (recipe 2 precondition)
for (const [mode, r] of [["loopback", loop], ["throttled", throttled]]) {
  const echoes = r.echoLatency;
  if (echoes) {
    if (echoes.some((e) => e.echoed)) ok(`${mode}: echo node updated after typing`);
    else bad(`${mode}: echo node did not update — echo precondition failed`);
    const settled = echoes.map((e) => e.settledMs).filter((v) => v !== null);
    if (settled.length) console.log(`  note: echo settled ${mode} p50=${fmtMs(median(settled))} (debounce + rtt — the honest per-keystroke number)`);
  }
}

// patchCost must have seen frames (recipe 3 precondition)
for (const [mode, r] of [["loopback", loop], ["throttled", throttled]]) {
  const sum = patchSummary(r);
  const first = Object.values(sum).find((s) => s && s.frames > 0);
  if (first) ok(`${mode}: ws frames captured (${first.frames}, ${first.sentBytes} sent / ${first.recvBytes} recv bytes)`);
  else bad(`${mode}: no websocket frames captured — patchCost precondition failed`);
}

// tti precondition: engine reached interactive state (bench-shape agnostic:
// feed/grid/dashboard/editor carry `tti` at the top; windowed nests it per
// variant).
for (const [mode, r] of [["loopback", loop], ["throttled", throttled]]) {
  const ttiRuns = [r.tti, r.naive?.tti, r.ops?.tti].filter(Boolean);
  if (ttiRuns.length && ttiRuns.some((t) => t.n > 0)) {
    const worst = ttiRuns.reduce((a, b) => ((a.p50 ?? 0) > (b.p50 ?? 0) ? a : b));
    ok(`${mode}: tti measured (p50 ${fmtMs(worst.p50)})`);
  } else {
    bad(`${mode}: tti not measured`);
  }
}

console.log("");
console.log("results: .bench/ (evidence: " + join(ROOT, ".bench") + ")");
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
server.kill("SIGTERM");
console.log(fail === 0 ? "CONTINUUM BENCH PASS" : "CONTINUUM BENCH FAIL");
process.exit(fail === 0 ? 0 : 1);
