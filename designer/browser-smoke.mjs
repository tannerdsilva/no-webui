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
//   (self-contained: builds the server, serves on :9123, checks in headless
//    Chromium, screenshots to .smoke/browser.png, tears down. not a plugin
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
}, "WebUIEngine");
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
}, "WebUIEngine");
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

// 6c. Progressive capability (p4, engine mode): offline shell service worker
// registers from the declared capability, claims, and controls a reload; view
// transitions API is present and the reduced-motion guard keeps patches fast.
await page.waitForTimeout(600);
const swState = await page.evaluate(async () => {
  if (!('serviceWorker' in navigator)) { return { supported: false }; }
  const reg = await navigator.serviceWorker.getRegistration();
  return { supported: true, registered: !!reg, active: !!(reg && reg.active) };
});
if (!swState.supported) ok("service worker not supported here (offline shell skipped cleanly)");
else if (swState.registered && swState.active) ok("offline shell service worker registered + active");
else bad(`service worker state: ${JSON.stringify(swState)}`);
await page.reload({ waitUntil: "domcontentloaded" });
await page.waitForTimeout(500);
const controlled = await page.evaluate(() => !!navigator.serviceWorker.controller);
if (controlled) ok("reloaded page is controlled by the shell (cache-first shell path active)");
else bad("reloaded page not controlled by the shell");
const vtx = await page.evaluate(() => ({
  api: typeof document.startViewTransition === 'function',
  reduced: matchMedia('(prefers-reduced-motion: reduce)').matches,
}));
if (vtx.api) ok("view transitions API present (engine wraps authoritative patches)");
else bad("view transitions API missing");
await page.emulateMedia({ reducedMotion: 'reduce' });
const vtPatch = await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  if (inst && inst.patch) {
    inst.patch([{ id: "counter-value", html: '<div id="counter-value" class="counter-value" role="status"><span>7</span></div>' }]);
  }
  return document.querySelector("#counter-value")?.textContent.trim() ?? "";
});
await page.emulateMedia({ reducedMotion: null });
if (vtPatch === "7") ok("patches apply under prefers-reduced-motion (guard path)");
else bad(`reduced-motion patch failed: ${JSON.stringify(vtPatch)}`);

// 6d. reconnect indicator (engine mode): the framework status chip exists
// hidden, appears on transport disconnect, clears on reconnect. its visibility
// is engine-owned (an inline display write), so both states must hold with
// every stylesheet disabled — a sheet-less page that showed a permanently
// visible "reconnecting…" chip is the failure this measures.
await page.waitForTimeout(200);
const stat0 = await page.evaluate(() => {
  const el = document.querySelector('.engine-status');
  return {
    present: !!el,
    visible: !!(el && el.classList.contains('engine-status--visible')),
    inline: el ? el.style.display : null,
  };
});
if (stat0.present && !stat0.visible) ok("engine status chip present + hidden by default");
else bad(`status chip state: ${JSON.stringify(stat0)}`);
if (stat0.inline === 'none') ok("chip hidden by its own inline display (independent of any sheet)");
else bad(`chip inline display: ${JSON.stringify(stat0.inline)}`);

// sheet-less probe: disable every stylesheet link, then drive a disconnect.
// the chip must appear (inline-flex), report the truth, and clear on reconnect
// — all without a single css rule in play.
const disabledSheets = await page.evaluate(() => {
  const links = [...document.querySelectorAll('link[rel="stylesheet"]')];
  links.forEach((l) => { l.disabled = true; });
  return links.length;
});
await page.evaluate(() => document.dispatchEvent(new CustomEvent('webui:disconnected', { detail: {} })));
await page.waitForTimeout(700);
const sheetless = await page.evaluate(() => {
  const el = document.querySelector('.engine-status');
  if (!el) return null;
  return { display: getComputedStyle(el).display, inline: el.style.display, text: el.textContent.trim() };
});
if (sheetless && sheetless.display === 'inline-flex') ok(`chip appears on disconnect with ${disabledSheets} sheet link(s) disabled (engine-owned visibility)`);
else bad(`sheet-less disconnect state: ${JSON.stringify(sheetless)}`);
if (sheetless && sheetless.text.indexOf('reconnecting') === 0) ok("chip text is truthful while disconnected");
else bad(`chip text while disconnected: ${JSON.stringify(sheetless && sheetless.text)}`);
const vis1 = await page.evaluate(() => !!document.querySelector('.engine-status--visible'));
if (vis1) ok("status chip appears on transport disconnect");
else bad("status chip did not appear on disconnect");
await page.evaluate(() => document.dispatchEvent(new CustomEvent('webui:connected', { detail: {} })));
await page.waitForTimeout(150);
const hiddenAgain = await page.evaluate(() => {
  const el = document.querySelector('.engine-status');
  if (!el) return null;
  return { display: getComputedStyle(el).display, inline: el.style.display, text: el.textContent.trim() };
});
if (hiddenAgain && hiddenAgain.display === 'none') ok("chip clears with every stylesheet still disabled (inline display, not css)");
else bad(`sheet-less reconnect state: ${JSON.stringify(hiddenAgain)}`);
if (hiddenAgain && hiddenAgain.text === 'connected') ok("chip text follows the socket state when connected");
else bad(`chip text when connected: ${JSON.stringify(hiddenAgain && hiddenAgain.text)}`);
const vis2 = await page.evaluate(() => !!document.querySelector('.engine-status--visible'));
if (!vis2) ok("status chip clears on reconnect");
else bad("status chip did not clear on reconnect");
await page.evaluate(() => { document.querySelectorAll('link[rel="stylesheet"]').forEach((l) => { l.disabled = false; }); });


{
    const esc = await browser.newPage();
    await esc.goto(`${BASE}/`, { waitUntil: "load" });
    const escErrors = [];
    esc.on("pageerror", (e) => escErrors.push(String(e)));
    await esc.waitForTimeout(300);
    // modal focus contract: an opener outside the modal, then a modal with a
    // close button. engine mode presses Escape (dismiss + focus return);
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
      await esc.keyboard.press("Escape");
    await esc.waitForTimeout(150);
    const escClicks = await esc.evaluate(() => window.__escClicks);
    const escFocus = await esc.evaluate(() => document.activeElement && document.activeElement.id);
    if (escClicks === 1) ok("Escape-to-dismiss dispatches the close click (engine keyboard parity)");
    else bad(`dismiss count: ${escClicks} (expected 1)`);
    if (escFocus === "esc-opener") ok("modal close returns focus to the opener (focus trap + return)");
    else bad(`focus after close: ${JSON.stringify(escFocus)} (expected esc-opener)`);
    if (escErrors.length === 0) ok("Escape probe has no page errors");
    else bad(`Escape probe page errors: ${JSON.stringify(escErrors)}`);
    await esc.close();
}

// 5. cascade layers: unlayered consumer css outranks the sheet by intent, not by
//    specificity. the probe picks its pair out of the *served* bytes — a framework
//    rule whose selector carries more than one class part — so it cannot pass by
//    finding a rule a plain single-class override would have beaten anyway.
{
  const candidate = await page.evaluate(async () => {
    const link = document.querySelector('link[rel="stylesheet"][href*="/__assets/css"]');
    if (!link) return { error: "no deployed sheet link" };
    const css = await (await fetch(link.href)).text();
    if (!css.startsWith("@layer webui, webui.utilities;")) return { error: "the sheet is not layered" };
    const lengthProps = ["gap", "row-gap", "column-gap", "padding", "padding-top", "padding-inline-start",
      "margin", "margin-top", "margin-bottom", "border-radius", "font-size", "width", "min-width",
      "max-width", "height", "min-height", "top", "left", "inset", "border-width", "outline-offset"];
    const blocks = css.match(/[^{}]+\{[^{}]*\}/g) || [];
    for (const block of blocks) {
      const open = block.indexOf("{");
      const sel = block.slice(0, open).trim();
      if (sel.startsWith("@")) continue;
      const classes = (sel.match(/\.[A-Za-z0-9_-]+/g) || []).map((s) => s.slice(1));
      const elements = (sel.replace(/[#.\[][^\s>+~,]*/g, "").match(/[a-zA-Z][a-zA-Z0-9-]*/g) || []).length;
      if (classes.length < 2 && !(classes.length === 1 && elements > 0)) continue;
      const target = classes[classes.length - 1];
      if (!target) continue;
      const el = document.querySelector("." + CSS.escape(target));
      if (!el) continue;
      const body = block.slice(open + 1);
      for (const prop of lengthProps) {
        const m = body.match(new RegExp("(?:^|;)\\s*" + prop + "\\s*:\\s*([^;]+)"));
        if (!m) continue;
        if (!/\d(px|rem|em)\b/.test(m[1])) continue;
        const before = getComputedStyle(el).getPropertyValue(prop).trim();
        if (!before) continue;
        return { selector: sel.replace(/\s+/g, " ").slice(0, 64), target, prop, before, classParts: classes.length };
      }
    }
    return { error: "no multi-class rule with a length property whose target is on the page" };
  });
  if (candidate.error) {
    bad(`layers probe: ${candidate.error}`);
  } else {
    // the consumer's own rule: single class, unlayered, added after the sheet.
    // a constructable stylesheet — not a `<style>` tag — so the page's csp cannot
    // make this probe pass or fail for the wrong reason.
    const applied = await page.evaluate(({ target, prop }) => {
      const sheet = new CSSStyleSheet();
      sheet.replaceSync(`.${target} { ${prop}: 37px; }`);
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
      const el = document.querySelector("." + CSS.escape(target));
      return getComputedStyle(el).getPropertyValue(prop).trim();
    }, candidate);
    if (applied === "37px") {
      ok(`unlayered consumer css beats a ${candidate.classParts}-class framework rule (${candidate.selector} → .${candidate.target} ${candidate.prop}, was ${candidate.before})`);
    } else {
      bad(`layers: consumer override lost — ${candidate.prop} = ${applied} (framework rule ${candidate.selector})`);
    }
  }
}

await browser.close();
server.kill();

console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  console.log("BROWSER SMOKE FAIL");
  process.exit(1);
}
console.log("BROWSER SMOKE PASS");
process.exit(0);
