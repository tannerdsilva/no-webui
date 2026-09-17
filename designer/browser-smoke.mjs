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
if (hasWasmSdk) {
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
page.on("console", (m) => {
  if (m.type() === "error") consoleErrors.push(m.text());
});
page.on("requestfailed", (r) => failedRequests.push(r.url()));
page.on("response", (r) => {
  if (r.status() >= 400 && !/favicon/i.test(r.url())) failedRequests.push(`${r.status()} ${r.url()}`);
});

await page.goto(BASE + "/", { waitUntil: "networkidle" });
await page.waitForTimeout(400);

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
const realErrors = consoleErrors.filter((t) => !isExpectedWs(t) && !/favicon/i.test(t));
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
const patcherRollback = await page.evaluate(
  (ms) =>
    new Promise((resolve) => {
      const inst = window.WebUIRuntime._getInstance();
      const patcher = inst.fragmentPatcher;
      patcher.patch(
        [{ id: "counter-value", html: '<div id="counter-value" class="counter-value" role="status"><span>9</span></div>' }],
        null,
        true
      );
      const immediate = document.querySelector("#counter-value").textContent.trim();
      setTimeout(() => resolve({ immediate, after: document.querySelector("#counter-value").textContent.trim() }), ms);
    }),
  5600
);
if (patcherRollback.immediate === "9" && patcherRollback.after === "0") ok("patcher rolled back unconfirmed optimistic patch to last-known-good after settle window");
else bad(`patcher rollback failed: ${JSON.stringify(patcherRollback)}`);

// 5. Save/restore hardening: a scrollable element inside a patched fragment
// keeps its scroll position across the replacement.
const scrollProbe = await page.evaluate(() => {
  const holder = document.createElement("div");
  holder.id = "scroll-probe";
  holder.style.cssText = "overflow:auto;height:40px;width:200px;";
  holder.innerHTML = '<div style="height:200px">a<br>b<br>c</div>';
  document.body.appendChild(holder);
  holder.scrollTop = 30;
  const before = holder.scrollTop;
  const inst = window.WebUIRuntime._getInstance();
  inst.fragmentPatcher.patch(
    [{ id: "scroll-probe", html: '<div id="scroll-probe" style="overflow:auto;height:40px;width:200px"><div style="height:200px">x<br>y<br>z</div></div>' }],
    null,
    false
  );
  const after = document.getElementById("scroll-probe").scrollTop;
  holder.remove();
  return { before, after };
});
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
  if (h.status === "match") ok(`client wasm hydrated the DOM, byte-identical to SSR (${h.len} chars)`);
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
  else bad("search vertical did not mount (chamber boot failed)");
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
    if (hasAPI && hasAuth && !hasWeb) ok(`local search filtered in wasm (api+auth, no web; ${result.events} events)`);
    else bad(`local search wrong: ${JSON.stringify(result.text)}`);
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
    if (sortState.aria === "ascending") ok("typed table sort header carries aria-sort");
    else bad(`sort aria-sort missing: ${JSON.stringify(sortState.aria)}`);
    if (sortState.text && sortState.text !== beforeSort) ok("typed table sort reordered rows in wasm");
    else bad("table sort did not reorder rows client-side");
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
    const de = sErrors.filter((t) => !/favicon/i.test(t));
    if (de.length === 0) ok("local-search probe has no console errors");
    else bad(`local-search console errors: ${JSON.stringify(de)}`);
  }
  await s.close();
} else {
  skipped++;
  console.log("  SKIP local-search vertical probe (wasm sdk not registered)");
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
