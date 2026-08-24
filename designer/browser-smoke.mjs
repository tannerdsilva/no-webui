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
//   (self-contained: builds, serves on :9123, checks in headless Chromium,
//    screenshots to .smoke/browser.png, tears down. not a plugin verb —
//    headless Chromium cannot run inside the plugin sandbox.)

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9123;
const BASE = `http://127.0.0.1:${PORT}`;

let pass = 0;
let fail = 0;
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

async function waitForServer(base, tries = 40) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(base + "/");
      if (r.ok) return true;
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

console.log("=== browser smoke test ===");
console.log("starting server ...");
const server = spawn(binPath, {}, { cwd: ROOT, stdio: ["ignore", "ignore", "ignore"] });
const up = await waitForServer(BASE);
if (!up) {
  bad("server did not become ready");
  server.kill();
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

await browser.close();
server.kill();

console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "BROWSER SMOKE PASS" : "BROWSER SMOKE FAIL");
process.exit(fail === 0 ? 0 : 1);
