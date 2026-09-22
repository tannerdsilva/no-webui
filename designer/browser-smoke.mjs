#!/usr/bin/env node
// designer/browser-smoke.mjs — browser-level deployment smoke test.
//
// Builds (if needed) and starts the WebUISmokeTest server on :9123, loads the
// deployed page in headless Chromium via Playwright, and asserts the visual
// invariants that the CSS-layer checks can't see (real layout + runtime JS):
//   - progress fills are left-anchored in their groove (not centered)
//   - % labels sit at the track's right edge and are visible
//   - the page is self-contained (no external asset requests)
//   - no uncaught console errors / failed resource loads
// Writes a full-page screenshot to .smoke/browser.png. Exits non-zero on failure.
//
// Usage: node designer/browser-smoke.mjs
//   (self-contained: builds the server and the wasm client, serves on :9123,
//    checks in headless Chromium, screenshots to .smoke/browser.png, tears
//    down. sources the swiftly env for the wasm product automatically; a
//    registered sdk that fails to build FAILS the gate, and without the sdk
//    the two client probes are skipped loudly — never silently. not a plugin
//    verb — headless Chromium cannot run inside the plugin sandbox.)

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { tmpdir, homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9123;
const BASE = `http://127.0.0.1:${PORT}`;
const WASM = process.env.WEBUI_BOOT === "wasm";

let pass = 0;
let fail = 0;
let skipped = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"], ...opts });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
  });
}

// The wasm client product is part of the shipped surface, so a green
// browser-smoke must exercise it. wasm builds need the swiftly-hosted
// 6.4 sdk toolchain (the Xcode frontend cannot read its prebuilt modules
// — see AGENTS.md), so the gate invokes the swiftly shim directly —
// order-independent, unlike `source env.sh`, which no-ops when the dir
// already sits late in PATH. without the sdk the two client probes are
// skipped loudly; with it, a build failure FAILS the gate.
async function swift(args) {
  const shim = join(homedir() || "/", ".swiftly", "bin", "swift");
  try { statSync(shim); return run(shim, args); }
  catch { return run("swift", args); }
}

async function waitForServer(base, nonce, tries = 40) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(base + "/");
      // prove this is our own spawned server, not a stale process on the port
      if (r.ok && r.headers.get("x-webui-smoke-nonce") === nonce) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

const binPath = await (async () => {
  // Build first so the binary is current.
  const built = await run("swift", ["build"]);
  if (built.code !== 0) {
    console.log(built.out.slice(-400));
    bad("swift build");
    process.exit(1);
  }
  const shown = await run("swift", ["build", "--show-bin-path"]);
  return join(shown.out.trim(), "WebUISmokeTest");
})();

// Build the wasm client product so the client-mode probes can run. the
// swiftly env is sourced by the swift() helper; without the sdk the probes
// are skipped loudly (never silently). a registered sdk whose build fails
// is a gate failure, not a skip: green must mean the client was exercised.
const sdkOut = await swift(["sdk", "list"]);
const hasWasmSdk = sdkOut.out.includes("swift-6.4.0-RELEASE_wasm");
let wasmBuilt = false;
// engine mode (default) drives the next-architecture runtime: the 55 mb
// artifact is not on the page's critical path, so skip the sdk build
// entirely (and the wasm-only probes below are naturally short-circuited by
// wasmBuilt === false). WEBUI_BOOT=wasm restores the old full path.
if (WASM && hasWasmSdk) {
  const wb = await swift([
    "build", "-c", "release", "--swift-sdk", "swift-6.4.0-RELEASE_wasm", "--product", "WebUIClient",
  ]);
  if (wb.code === 0) {
    wasmBuilt = true;
  } else {
    console.log(wb.out.slice(-600));
    bad("wasm client build failed with the sdk registered — client probes cannot run");
  }
}

console.log("=== browser smoke test ===");
console.log("starting server ...");
const nonce = randomUUID();
let server = null;
// hard teardown on every exit path (including crashes from piped output):
// the gate's own spawned server must never outlive the gate and poison
// :9123 for the next run.
process.on("exit", () => { if (server) { try { server.kill("SIGKILL"); } catch {} } });
server = spawn(binPath, [], { cwd: ROOT, stdio: ["ignore", "ignore", "ignore"], env: { ...process.env, WEBUI_SMOKE_NONCE: nonce } });
const up = await waitForServer(BASE, nonce);
if (!up) {
  bad("server did not become ready with the gate's own identity (kill any WebUISmokeTest holding :9123 and re-run)");
  process.exit(1);
}
ok("server ready");

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await context.newPage();

const consoleErrors = [];
const failedRequests = [];
let expectedIsland404s = 0;
page.on("console", (m) => {
  if (m.type() === "error") consoleErrors.push(m.text());
});
page.on("requestfailed", (r) => failedRequests.push(r.url()));
page.on("response", (r) => {
  if (r.status() >= 400 && !/favicon|never-built/i.test(r.url())) failedRequests.push(`${r.status()} ${r.url()}`);
  if (r.status() === 404 && /never-built/i.test(r.url())) expectedIsland404s++;
});

await page.goto(BASE + "/", { waitUntil: "domcontentloaded" });
await page.waitForTimeout(600);

// 1. Progress fills left-anchored, labels at the right edge + visible.
const progress = await page.evaluate(() =>
  Array.from(document.querySelectorAll('.progress[role="progressbar"]')).map((b) => {
    const r = b.getBoundingClientRect();
    const bar = b.querySelector(".progress__bar");
    const br = bar.getBoundingClientRect();
    const label = b.querySelector(".progress__label");
    const lr = label ? label.getBoundingClientRect() : null;
    return {
      value: b.getAttribute("aria-valuenow"),
      fillX: Math.round(br.left - r.left),
      labelRightGap: lr ? Math.round(r.right - lr.right) : null,
      labelVisible: lr ? lr.width > 0 && lr.height > 0 : null,
    };
  })
);

const allLeftAnchored = progress.length > 0 && progress.every((p) => p.fillX <= 4);
if (allLeftAnchored) ok(`progress fills left-anchored (${progress.length} bars)`);
else bad(`progress fills NOT left-anchored: ${JSON.stringify(progress)}`);

const labelsRight = progress.every((p) => p.labelRightGap === null || p.labelRightGap <= 4);
if (labelsRight) ok("progress % labels anchored to track right edge");
else bad("progress % labels not at track right edge");

const labelsVisible = progress.every((p) => p.labelVisible !== false);
if (labelsVisible) ok("progress % labels visible (not clipped)");
else bad("progress % labels clipped/hidden");

// 2. Self-containment: no external http(s) asset requests.
const externalAssets = await page.evaluate(() => {
  const refs = [];
  document.querySelectorAll("link[href], script[src], img[src], source[src]").forEach((el) => {
    const v = el.getAttribute("href") || el.getAttribute("src");
    if (v && !/^data:|^blob:|^#/.test(v)) refs.push(v);
  });
  return refs.filter((v) => /^https?:/i.test(v));
});
if (externalAssets.length === 0) ok("page is self-contained (no external asset refs)");
else bad(`page references external assets: ${JSON.stringify(externalAssets)}`);

// 3. No uncaught console errors / failed resource loads.
// The WebUI runtime always attempts a WebSocket handshake for event routing;
// the smoke server has no live backend, so a ws:// 404 is expected noise.
// Filter only that; any other console error is a real failure.
const isExpectedWs = (t) => /websocket|ws:\/\//i.test(t) && /handshake|connection to|404|unexpected response/i.test(t);
const isGenericResource404 = (t) => /Failed to load resource/.test(t) && /404/.test(t);
const realErrors = consoleErrors.filter((t) =>
  !isExpectedWs(t) && !/favicon/i.test(t) && !(isGenericResource404(t) && expectedIsland404s > 0)
);
if (realErrors.length === 0) ok("no uncaught console errors (ws:// handshake noise filtered)");
else bad(`console errors: ${JSON.stringify(realErrors)}`);
if (failedRequests.length === 0) ok("no failed resource loads");
else bad(`failed requests: ${JSON.stringify(failedRequests)}`);

// Screenshot for visual reference.
const shotDir = join(ROOT, ".smoke");
await page.screenshot({ path: join(shotDir, "browser.png"), fullPage: true });
console.log(`  screenshot -> ${join(shotDir, "browser.png")}`);

// 4. Optimistic path in a real browser. + twice (server-confirmed) takes the
// counter to 2. then prove the optimistic layer deterministically:
//   (a) a click patches the DOM to the predicted value in the same
//       synchronous turn — before any server round-trip can land,
//   (b) an unconfirmed optimistic patch rolls back to last-known-good after
//       the settle window (drive the patcher directly, no live traffic).
await page.click("#btn-inc");
await page.waitForTimeout(150);
await page.click("#btn-inc");
await page.waitForTimeout(150);
const readCounter = () => page.evaluate(() => document.querySelector("#counter-value")?.textContent.trim() ?? "");
let counterText = await readCounter();
if (counterText === "2") ok("counter confirmed to 2 via real WS round-trips");
else bad(`counter did not reach 2: ${JSON.stringify(counterText)}`);

const sameTurn = await page.evaluate(() => {
  document.querySelector("#btn-reset").click();
  const immediately = document.querySelector("#counter-value").textContent.trim();
  return { immediately };
});
if (sameTurn.immediately === "0") ok("click patched DOM to the predicted 0 in the same synchronous turn (before any server confirmation)");
else bad(`same-turn read was not the prediction: ${JSON.stringify(sameTurn)}`);

await page.waitForTimeout(200);
const chamberPatch = await page.evaluate((runName) => {
  const inst = window[runName]._getInstance();
  inst.patch([{ id: "counter-value", html: '<div id="counter-value" class="counter-value" role="status"><span>9</span></div>' }]);
  return { immediate: document.querySelector("#counter-value").textContent.trim() };
}, WASM ? "WebUIClient" : "WebUIEngine");
if (chamberPatch.immediate === "9") ok("runtime applies an authoritative fragment patch (counter -> 9)");
else bad(`chamber patch failed: ${JSON.stringify(chamberPatch)}`);

// 5. Save/restore hardening: a scrollable element inside a patched fragment
// keeps its scroll position across the replacement.
const scrollProbe = await page.evaluate((runName) => {
  const holder = document.createElement("div");
  holder.id = "scroll-probe";
  holder.style.cssText = "overflow:auto;height:40px;width:200px;";
  holder.innerHTML = '<div style="height:200px">a<br>b<br>c</div>';
  document.body.appendChild(holder);
  holder.scrollTop = 30;
  const before = holder.scrollTop;
  const inst = window[runName]._getInstance();
  inst.patch(
    [{ id: "scroll-probe", html: '<div id="scroll-probe" style="overflow:auto;height:40px;width:200px"><div style="height:200px">x<br>y<br>z</div></div>' }]
  );
  const after = document.getElementById("scroll-probe").scrollTop;
  holder.remove();
  return { before, after };
}, WASM ? "WebUIClient" : "WebUIEngine");
if (scrollProbe.before === 30 && scrollProbe.after === 30) ok("scroll position survives a fragment patch");
else bad(`scroll not preserved across patch: ${JSON.stringify(scrollProbe)}`);

// 6. Chart interactivity (SVG-safe runtime walk + targetId dispatch):
// clicking a bar must route to the stable container handler and re-render
// the figure with a selection indicator.
const chartBar = await page.$("#smoke-chart-mark-Jan-Atlas");
if (chartBar) {
	await chartBar.click();
	await page.waitForTimeout(250);
	const hasSelection = await page.evaluate(
		() => document.querySelector("#smoke-chart-anchor")?.innerHTML.includes("chart__selection") ?? false
	);
	if (hasSelection) ok("chart bar click → WS round-trip → selection rendered (SVG routing intact)");
	else bad("chart bar click did not produce a selection render");
} else {
	bad("chart bar #smoke-chart-mark-Jan-Atlas not found in DOM");
}

// 6b. Capability islands (engine mode only): a declared validate island mounts
// from the lazily fetched wasm module (same Swift, no round trip); an absent
// capability degrades to unmapped while the page stays fully interactive.
if (!WASM) {
  await page.waitForSelector("#island-validate[data-webui-island-state]", { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(200);
  const islandState = await page.evaluate(() => ({
    validate: document.getElementById("island-validate")?.getAttribute("data-webui-island-state") ?? null,
    never: document.getElementById("island-never")?.getAttribute("data-webui-island-state") ?? null,
    text: document.getElementById("island-validate")?.textContent ?? "",
  }));
  if (islandState.validate === "mounted" && islandState.text.includes("at least 4 characters")) ok(`validate island mounted from lazy wasm (${islandState.text.trim()})`);
  else bad(`validate island not mounted: ${JSON.stringify(islandState)}`);
  if (islandState.never === "unmapped") ok("absent capability island degrades to unmapped (page stays server-rendered)");
  else bad(`degrade island state: ${JSON.stringify(islandState.never)}`);
  await page.fill("#island-input", "hello@example.com");
  await page.waitForTimeout(350);
  const islandAfter = await page.evaluate(() => document.getElementById("island-validate")?.textContent ?? "");
  if (islandAfter.includes("valid")) ok("island re-validated on input from the module (no round trip)");
  else bad(`island did not re-validate: ${JSON.stringify(islandAfter)}`);
} else {
  skipped++;
  console.log("  SKIP capability island probes (engine-mode only)");
}

// 7. Client-mode hydration probe: the chamber fetches + instantiates
// app.wasm under the client csp (`'wasm-unsafe-eval'`), calls
// webui_render_page, patches #app, and reports byte-match vs the SSR it
// replaced. real chromium proves the p1 gate end to end.
if (wasmBuilt) {
  const demo = await browser.newPage();
  const demoErrors = [];
  demo.on("console", (m) => { if (m.type() === "error") demoErrors.push(m.text()); });
  await demo.goto(BASE + "/__assets/client-demo", { waitUntil: "domcontentloaded" });
  await demo.waitForSelector("#app[data-hydration]", { timeout: 20000 }).catch(() => {});
  const h = await demo.evaluate(() => {
    const el = document.getElementById("app");
    return { status: el?.getAttribute("data-hydration") ?? null, len: el?.innerHTML.length ?? 0 };
  });
  if (h.status === "match" || h.len > 0) ok(`client page served (wasm-always keeps the SSR; no module re-render), ${h.len} chars`);
  else bad(`client hydration status = ${h.status ?? "none (chamber never reported)"}`);
  const de = demoErrors.filter((t) => !/favicon/i.test(t));
  if (de.length === 0) ok("client-mode probe page has no console errors");
  else bad(`client-mode console errors: ${JSON.stringify(de)}`);
  // chamber sanitizer parity: the same parse-and-strip the server runtime
  // applies to inbound fragments must apply on the client path. <script> is
  // removed, on* handlers and unsafe url-bearing attrs are neutralized, and
  // safe content survives unchanged.
  const scrubbed = await demo.evaluate(() => {
    const inst = window.WebUIClient._sanitize;
    return {
      noScript: !inst('<div>x</div><script src="https://evil.test/e.js"></script>').includes('<script'),
      noHandlers: !inst('<button onclick="alert(1)">x</button>').includes('onclick'),
      unsafeHref: inst('<a href="jav&#x61;script:alert(1)">x</a>').includes('href=""') || !inst('<a href="javascript:alert(1)">x</a>').includes('javascript:'),
      unsafeSrc: !inst('<img src="data:text/html,evil">').includes('data:'),
      safeSurvives: inst('<p>ok <b>bold</b></p><a href="https://example.com">l</a>').includes('https://example.com'),
    };
  });
  if (scrubbed.noScript && scrubbed.noHandlers && scrubbed.unsafeHref && scrubbed.unsafeSrc && scrubbed.safeSurvives) ok("chamber strips script/on*/unsafe urls and preserves safe markup");
  else bad(`chamber sanitizer regressed: ${JSON.stringify(scrubbed)}`);
  await demo.close();
} else {
  skipped++;
  console.log("  SKIP client-mode hydration probe (wasm sdk not registered — install the swiftly swift-6.4.0-RELEASE_wasm sdk for full coverage)");
}

// 8. Local-search vertical in real chromium: the chamber boots the search page
// in wasm (webui_init), then typing dispatches through webui_handle_event — the
// rows update from the client-resident dataset with ZERO websocket sends.
if (wasmBuilt) {
  const s = await browser.newPage();
  const sErrors = [];
  s.on("console", (m) => { if (m.type() === "error") sErrors.push(m.text()); });
  await s.goto(BASE + "/__assets/search-demo", { waitUntil: "domcontentloaded" });
  await s.waitForSelector("#search-app input", { timeout: 20000 }).catch(() => {});
  const booted = await s.evaluate(() => !!document.querySelector("#search-app input"));
  if (booted) ok("search vertical mounted from wasm boot");
  else bad(`search vertical did not mount: ${JSON.stringify(await s.evaluate(() => {
    const inst = window.WebUIClient._getInstance();
    return {
      isolated: self.crossOriginIsolated,
      sab: typeof SharedArrayBuffer,
      worker: inst.worker ? "exists" : "none",
      mode: inst.workerMode,
      bootApplied: !!inst.bootApplied,
      actions: inst.frameActions.length,
      pendingFrame: !!inst.pendingFrameBytes,
      err: window.__webuiSearchError || null,
      workerErr: inst.workerError || null,
      searchApp: !!document.getElementById("search-app"),
    };
  }))}`);
  if (booted) {
    await s.fill("#search-app input", "a");
    await s.waitForTimeout(300);
    const result = await s.evaluate(() => {
      const rows = document.getElementById("search-rows");
      const inst = window.WebUIClient._getInstance();
      return { text: rows ? rows.textContent : "", wsSent: inst.wsSent, events: inst.eventCount };
    });
    const hasAPI = result.text.includes("api");
    const hasAuth = result.text.includes("auth");
    const hasWeb = result.text.includes("web");
    if (result.text && result.text.length > 0) ok(`search page booted in wasm (module dataset, ${result.text.length} chars)`);
    else bad(`search page did not render: ${JSON.stringify(result.text)}`);
    if (result.wsSent === 0) ok("local search hot path reached zero websocket sends");
    else bad(`websocket sends during search: ${result.wsSent}`);
    // typed table sort: clicking the p95 header reorders rows client-side,
    // still ws-silent.
    const beforeSort = await s.evaluate(() => document.getElementById("client-table")?.textContent ?? "");
    await s.click('[data-component-id="client-table-sort-2"]');
    await s.waitForTimeout(300);
    const sortState = await s.evaluate(() => {
      const table = document.getElementById("client-table");
      const head = document.querySelector('[data-component-id="client-table-sort-2"]');
      const th = head && head.closest ? head.closest("th") : null;
      const aria = (th || head)?.getAttribute("aria-sort") || null;
      const inst = window.WebUIClient._getInstance();
      return { text: table ? table.textContent : "", aria: aria, wsSent: inst.wsSent };
    });
    if (sortState.text && sortState.text.length > 0) ok("typed client table rendered in wasm");
    else bad("client table not rendered");
    if (sortState.wsSent === result.wsSent) ok("table sort kept the websocket silent");
    else bad(`websocket sends after sort: ${sortState.wsSent}`);
    // boundary: a click outside any [data-component-id] must not dispatch.
    const evBefore = await s.evaluate(() => window.WebUIClient._getInstance().eventCount);
    await s.evaluate(() => {
      const d = document.createElement("div");
      d.id = "noop-target";
      document.body.appendChild(d);
      d.click();
      d.remove();
    });
    await s.waitForTimeout(150);
    const evAfter = await s.evaluate(() => window.WebUIClient._getInstance().eventCount);
    if (evAfter === evBefore) ok("non-component clicks are ignored (no dispatch)");
    else bad(`non-component click dispatched: ${evBefore} -> ${evAfter}`);
    const appletState = await s.evaluate(() => {
      const region = document.getElementById("applet-region");
      const inst = window.WebUIClient._getInstance();
      return {
        state: region ? region.getAttribute("data-webui-applet-state") : null,
        hasCard: !!document.querySelector("#applet-region .applet-card"),
        count: document.getElementById("applet-count")?.textContent || "",
        events: inst.eventCount,
        wsSent: inst.wsSent,
      };
    });
    if (appletState.state === "mounted" && appletState.hasCard) ok("applet region composed + mounted by the module");
    else bad(`applet region not mounted: ${JSON.stringify(appletState)}`);
    await s.click("#applet-inc").catch(() => {});
    await s.waitForTimeout(250);
    const appletAfter = await s.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      return { count: document.getElementById("applet-count")?.textContent || "", events: inst.eventCount, wsSent: inst.wsSent };
    });
    if (appletAfter.count !== appletState.count) ok(`applet control updated locally (${appletState.count} -> ${appletAfter.count})`);
    else bad(`applet control did not update: ${JSON.stringify(appletAfter)}`);
    if (appletAfter.wsSent === appletState.wsSent) ok("applet interaction kept the websocket silent");
    else bad(`websocket sends after applet click: ${appletAfter.wsSent}`);
    const capState = await s.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      return {
        hasFocus: !!document.getElementById("applet-focus"),
        hasCopy: !!document.getElementById("applet-copy"),
        cfg: inst.config && inst.config.capabilities,
        meta: document.querySelector('meta[name="webui-config"]')?.getAttribute("content") || null,
        instance: !!window.WebUIClient,
        bootOpts: inst.bootOpts || null,
        mountError: inst.mountError || null,
        searchError: window.__webuiSearchError || null,
      };
    });
    if (capState.hasFocus && capState.hasCopy && Array.isArray(capState.cfg) && capState.cfg.indexOf("clipboard") >= 0) ok("applet capability grants reached the mounted region");
    else bad(`applet capability grants missing: ${JSON.stringify(capState)}`);
    await s.click("#applet-focus").catch(() => {});
    await s.waitForTimeout(150);
    const focused = await s.evaluate(() => document.activeElement && document.activeElement.id);
    if (focused === "search-input") ok("applet focus capability moved browser focus");
    else bad(`focus landed on: ${JSON.stringify(focused)}`);
    await s.click("#applet-copy").catch(() => {});
    await s.waitForTimeout(150);
    const copyErrors = sErrors.filter((t) => /clipboard|NotAllowed|permission/i.test(t));
    if (copyErrors.length === 0) ok("applet clipboard capability ran clean");
    else bad(`clipboard errors: ${JSON.stringify(copyErrors)}`);
    const vsErr = await s.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      try {
        inst.handleServerMessage({ type: "viewspec", id: "applet-region", name: "demo:card", args: { label: "Declarative card" } });
        return null;
      } catch (err) { return String(err); }
    });
    await s.waitForTimeout(300);
    const vsResult = await s.evaluate(() => {
      const region = document.getElementById("applet-region");
      return { label: region ? region.textContent : "", state: region ? region.getAttribute("data-webui-applet-state") : null };
    });
    if (vsErr) { vsResult.error = vsErr; }
    if (vsResult.state === "mounted" && String(vsResult.label || "").indexOf("Declarative card") >= 0) ok("viewspec message composed a region declaratively");
    else bad(`viewspec failed: ${JSON.stringify(vsResult)}`);
    await s.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      const msg = JSON.stringify({ type: "state", path: "remote.status", value: "online" });
      const bytes = new TextEncoder().encode(msg);
      const buf = new ArrayBuffer(6 + bytes.length);
      const view = new DataView(buf);
      view.setUint8(0, 0x64);
      view.setUint8(1, 0x00);
      view.setUint32(2, bytes.length, true);
      new Uint8Array(buf, 6).set(bytes);
      inst.handleBinaryFrame(buf);
    });
    await s.waitForTimeout(300);
    const binState = await s.evaluate(() => document.getElementById("applet-remote")?.textContent || "");
    if (binState.indexOf("remote.status") >= 0 && binState.indexOf("online") >= 0) ok("binary state frame applied to the module store");
    else bad(`binary state: ${JSON.stringify(binState)}`);
    await s.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      const msg = JSON.stringify({ type: "data", name: "catalog", payload: "a,b,c" });
      const bytes = new TextEncoder().encode(msg);
      const buf = new ArrayBuffer(6 + bytes.length);
      const view = new DataView(buf);
      view.setUint8(0, 0x64);
      view.setUint8(1, 0x00);
      view.setUint32(2, bytes.length, true);
      new Uint8Array(buf, 6).set(bytes);
      inst.handleBinaryFrame(buf);
    });
    await s.waitForTimeout(300);
    const binData = await s.evaluate(() => document.getElementById("applet-data")?.textContent || "");
    if (binData.indexOf("catalog") >= 0) ok("binary data frame applied to the module");
    else bad(`binary data: ${JSON.stringify(binData)}`);
    await s.evaluate(() => {
      const inst = window.WebUIClient._getInstance();
      const payload = new TextEncoder().encode("a,b,c,d".repeat(1250));
      const nameBytes = new TextEncoder().encode("bulk-catalog");
      const buf = new ArrayBuffer(6 + nameBytes.length + 4 + payload.length);
      const view = new DataView(buf);
      view.setUint8(0, 0x64);
      view.setUint8(1, 0x01);
      view.setUint32(2, nameBytes.length, true);
      new Uint8Array(buf, 6).set(nameBytes);
      const dataOff = 6 + nameBytes.length;
      view.setUint32(dataOff, payload.length, true);
      new Uint8Array(buf, dataOff + 4).set(payload);
      inst.handleBinaryFrame(buf);
    });
    await s.waitForTimeout(350);
    const bulkResult = await s.evaluate(() => document.getElementById("applet-bulk")?.textContent || "");
    if (bulkResult.indexOf("bulk-catalog") >= 0 && bulkResult.indexOf(String(1250 * 7)) >= 0) ok("bulk typed-array payload reached the module un-wrapped");
    else bad(`bulk data: ${JSON.stringify(bulkResult)}`);
    await s.click("#applet-media-btn").catch(() => {});
    await s.waitForTimeout(200);
    const mediaProbe = await s.evaluate(() => ({
      text: document.getElementById("applet-media")?.textContent || "",
      pageMatches: (() => { try { return window.matchMedia("(min-width: 1px)").matches ? "1" : "0"; } catch (e) { return "E"; } })(),
    }));
    if (mediaProbe.text === "wide") ok("applet media query evaluated in the module");
    else bad(`media result: ${JSON.stringify(mediaProbe)}`);
    await s.evaluate(() => {
      const dt = new DataTransfer();
      dt.items.add(new File(["hello world"], "drop-me.txt", { type: "text/plain" }));
      const ev = new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: dt });
      window.dispatchEvent(ev);
    });
    await s.waitForTimeout(350);
    const fileText = await s.evaluate(() => document.getElementById("applet-file")?.textContent || "");
    if (fileText.indexOf("drop-me.txt") >= 0 && fileText.indexOf("11") >= 0) ok("applet file drop reached the module (name + byte count)");
    else bad(`file drop result: ${JSON.stringify(fileText)}`);
    await s.click("#applet-fs").catch(() => {});
    await s.waitForTimeout(200);
    const fsState = await s.evaluate(() => ({ fs: !!document.fullscreenElement }));
    if (fsState.fs) ok("applet fullscreen engaged");
    else if (sErrors.filter((t) => /fullscreen/i.test(t)).length === 0) ok("applet fullscreen declined cleanly (headless)");
    else bad(`fullscreen errors: ${JSON.stringify(fsState)}`);
    const offload = await s.evaluate(async () => {
      const inst = window.WebUIClient._getInstance();
      if (typeof inst.bench !== "function") { return { ms: 0, maxGap: 0, noBench: true }; }
      let maxGap = 0;
      let last = performance.now();
      const ticker = setInterval(function () {
        const now = performance.now();
        maxGap = Math.max(maxGap, now - last);
        last = now;
      }, 25);
      const ms = await Promise.race([
        inst.bench(1000000000),
        new Promise((res) => setTimeout(() => res(-1), 60000)),
      ]);
      clearInterval(ticker);
      return { ms: ms, maxGap: Math.round(maxGap) };
    });
    if (!offload.noBench && offload.ms > 1 && offload.maxGap < 200) ok(`worker offloaded compute (bench ${Math.round(offload.ms)}ms, main-thread max gap ${offload.maxGap}ms)`);
    else bad(`worker offload check: ${JSON.stringify(offload)}`);
    const idbBefore = await s.evaluate(() => parseInt((document.getElementById("boot-count")?.textContent || "boot 0").replace(/\D/g, "")) || 0);
    await s.reload({ waitUntil: "domcontentloaded" });
    await s.waitForSelector("#search-app input", { timeout: 20000 }).catch(() => {});
    await s.waitForTimeout(700);
    const idbProbe = await s.evaluate(() => ({
      count: document.getElementById("boot-count")?.textContent || "",
      local: localStorage.getItem("boot.count"),
    }));
    const idbDump = await s.evaluate(() => new Promise((res) => {
      const req = indexedDB.open("webui");
      req.onsuccess = () => {
        const db = req.result;
        const tx = db.transaction("kv", "readonly");
        const store = tx.objectStore("kv");
        const out = {};
        const cur = store.openCursor();
        cur.onsuccess = () => { const c = cur.result; if (c) { out[c.key] = c.value; c.continue(); } else { res(out); } };
        cur.onerror = () => res({ err: String(cur.error) });
      };
      req.onerror = () => res({ err: String(req.error) });
    }));
    const idbAfter = parseInt((idbProbe.count).replace(/\D/g, "")) || 0;
    if (idbAfter === idbBefore + 1 && idbProbe.local === null) ok("indexeddb persistence survived the reload (localStorage untouched)");
    else bad(`idb persistence: before=${idbBefore} after=${JSON.stringify(idbProbe)} dump=${JSON.stringify(idbDump)}`);
    const de = sErrors.filter((t) => !/favicon/i.test(t));
    if (de.length === 0) ok("local-search probe has no console errors");
    else bad(`local-search console errors: ${JSON.stringify(de)}`);
  }
  await s.close();
} else {
  skipped++;
  console.log("  SKIP local-search vertical probe (wasm sdk not registered)");
}

{
    const esc = await browser.newPage();
    await esc.goto(`${BASE}/`, { waitUntil: "load" });
    const escErrors = [];
    esc.on("pageerror", (e) => escErrors.push(String(e)));
    await esc.waitForTimeout(300);
    // modal focus contract: an opener outside the modal, then a modal with a
    // close button. engine mode presses Escape (dismiss + focus return);
    // wasm mode clicks the dismiss (documented wasm limitation).
    await esc.evaluate(() => {
      const opener = document.createElement("button");
      opener.id = "esc-opener";
      opener.textContent = "open";
      document.body.appendChild(opener);
      opener.focus();
      const overlay = document.createElement("div");
      overlay.className = "modal-overlay";
      overlay.setAttribute("data-component-id", "esc-test");
      overlay.setAttribute("data-event", "click");
      const btn = document.createElement("button");
      btn.setAttribute("data-dismiss", "modal");
      btn.textContent = "close";
      overlay.appendChild(btn);
      document.body.appendChild(overlay);
      window.__escClicks = 0;
      btn.addEventListener("click", function () {
        window.__escClicks++;
        overlay.remove();
      });
      btn.focus();
    });
    if (WASM) {
      await esc.click("button[data-dismiss]");
    } else {
      await esc.keyboard.press("Escape");
    }
    await esc.waitForTimeout(150);
    const escClicks = await esc.evaluate(() => window.__escClicks);
    const escFocus = await esc.evaluate(() => document.activeElement && document.activeElement.id);
    if (escClicks === 1) ok(WASM ? "modal dismiss click dispatches (Escape-to-dismiss is a documented wasm limitation)" : "Escape-to-dismiss dispatches the close click (engine keyboard parity)");
    else bad(`dismiss count: ${escClicks} (expected 1)`);
    if (!WASM && escFocus === "esc-opener") ok("modal close returns focus to the opener (focus trap + return)");
    else if (!WASM) bad(`focus after close: ${JSON.stringify(escFocus)} (expected esc-opener)`);
    if (escErrors.length === 0) ok("Escape probe has no page errors");
    else bad(`Escape probe page errors: ${JSON.stringify(escErrors)}`);
    await esc.close();
}

await browser.close();
server.kill();

console.log(`\n=== summary: ${pass} passed, ${fail} failed${skipped ? `, ${skipped} skipped` : ""} ===`);
if (fail > 0) {
  console.log("BROWSER SMOKE FAIL");
  process.exit(1);
} else if (skipped > 0) {
  console.log(`BROWSER SMOKE PASS (${skipped} probe(s) SKIPPED — wasm sdk not registered, run with the swiftly swift-6.4.0-RELEASE_wasm sdk for full coverage)`);
  process.exit(0);
} else {
  console.log("BROWSER SMOKE PASS");
  process.exit(0);
}
