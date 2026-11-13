#!/usr/bin/env node
// designer/behaviour-probe.mjs — the behavior dispatch table's browser gate.
//
// Self-contained like `browser-smoke.mjs`: builds if needed, spawns
// `.build/debug/WebUISmokeTest --port 9124` with a nonce, waits for THAT
// process, drives `/behaviour` in headless Chromium, tears down hard.
//
// Every assertion names the attribute it measures. The page is driven through
// real DOM events and the real websocket — the runtime is never patched, and
// the probe's only in-page writes are user gestures (focus, fill, key presses,
// synthetic drag events) plus observers it installs to count dispatches.
//
// `[SKIP] <reason>` is reserved for environmental gaps (no clipboard grant on
// this host, no chromium). It is never a pass.
//
// Usage: node designer/behaviour-probe.mjs

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9124;
const BASE = `http://127.0.0.1:${PORT}`;

let pass = 0;
let fail = 0;
let skip = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };
const skipWithReason = (m) => { skip++; console.log(`  SKIP ${m}`); };

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"], ...opts });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
  });
}

async function waitForServer(base, nonce, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(base + "/behaviour");
      if (r.ok && r.headers.get("x-webui-smoke-nonce") === nonce) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

const binPath = await (async () => {
  const built = await run("swift", ["build"]);
  if (built.code !== 0) {
    console.log(built.out.slice(-600));
    bad("swift build");
    process.exit(1);
  }
  const shown = await run("swift", ["build", "--show-bin-path"]);
  return join(shown.out.trim(), "WebUISmokeTest");
})();

console.log("=== behaviour probe ===");
const nonce = randomUUID();
let server = null;
process.on("exit", () => { if (server) { try { server.kill("SIGKILL"); } catch {} } });
server = spawn(binPath, ["--port", String(PORT)], {
  cwd: ROOT,
  stdio: ["ignore", "ignore", "ignore"],
  env: { ...process.env, WEBUI_SMOKE_NONCE: nonce },
});
if (!(await waitForServer(BASE, nonce))) {
  bad("server did not become ready with the probe's own identity (kill any WebUISmokeTest holding :9124 and re-run)");
  process.exit(1);
}
ok("server ready on :9124 (nonce-matched child)");

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1200, height: 800 } });
let clipboardGranted = true;
try {
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: BASE });
} catch {
  clipboardGranted = false;
}
const page = await context.newPage();

const pageErrors = [];
const consoleErrors = [];
page.on("pageerror", (e) => pageErrors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });

// the extension's boot fetch, counted per page load. the first assertion reads
// it; the reload in §21 is a second load and is deliberately not re-counted.
const extResponses = [];
page.on("response", (r) => {
  if (r.url().includes("/webui-engine-ext.js")) extResponses.push(r.status());
});

await page.goto(BASE + "/behaviour", { waitUntil: "domcontentloaded" });
await page.waitForTimeout(700);

// ---------------------------------------------------------------------------
// 0. the second asset: one fetch at boot, 200, before the first assertion
//    needs a consequence it owns.
// ---------------------------------------------------------------------------
{
  for (let i = 0; i < 20 && extResponses.length === 0; i++) await page.waitForTimeout(100);
  const once = extResponses.length === 1;
  const served = extResponses[0] === 200;
  if (once && served) ok("the engine fetches /ui/webui-engine-ext.js exactly once at boot and the route answers 200");
  else bad(`the extension boot fetch was ${JSON.stringify(extResponses)} — expected exactly one 200`);
}

const $ = (sel) => page.evaluate((s) => {
  const el = document.querySelector(s);
  return el ? { text: (el.textContent || "").trim(), value: el.value ?? null, attrs: Array.from(el.attributes).map((a) => a.name + "=" + a.value) } : null;
}, sel);
const attr = (sel, name) => page.evaluate(([s, n]) => {
  const el = document.querySelector(s);
  return el ? el.getAttribute(n) : null;
}, [sel, name]);
const exists = (sel) => page.evaluate((s) => !!document.querySelector(s), sel);

// ---------------------------------------------------------------------------
// 1. data-reltime — the §22.9 ladder, painted from the ms epoch.
// ---------------------------------------------------------------------------
{
  const labels = await page.evaluate(() => ["rel-1", "rel-2", "rel-3", "rel-4", "rel-5"]
    .map((id) => (document.getElementById(id)?.textContent || "").trim()));
  const expect = [
    ["1m", "a diff under 60 s paints 1m"],
    ["5m", "a diff under 60 min paints floor(diff/60s)m"],
    ["3h", "a diff under 24 h paints floor(diff/1h)h"],
    ["2d", "calendar days under 7 paint max(days,1)d"],
    ["Jan 1, 20", "an older stamp paints Mon D and appends , YY when the year differs"],
  ];
  expect.forEach(([want, why], i) => {
    if (labels[i] === want) ok(`data-reltime: ${why} (${labels[i]})`);
    else bad(`data-reltime: ${why} — got ${JSON.stringify(labels[i])}, expected ${JSON.stringify(want)}`);
  });
}

// ---------------------------------------------------------------------------
// 2. data-started — floor(s/60):SS, one tick a second, data-elapsed on mount.
// ---------------------------------------------------------------------------
{
  const first = await $ ("#elapsed");
  const hasElapsed = await page.evaluate(() => document.getElementById("elapsed")?.hasAttribute("data-elapsed") ?? false);
  if (/^2:0\d$|^2:[1-5]\d$/.test(first.text)) ok(`data-started: paints floor(s/60):SS from the epoch (${first.text})`);
  else bad(`data-started: painted ${JSON.stringify(first.text)}, expected floor(s/60):SS around 2:05`);
  if (hasElapsed) ok("data-elapsed: presence is set on mount (engine-written)");
  else bad("data-elapsed: the engine did not write the presence attribute");
  await page.waitForTimeout(1250);
  const second = await $ ("#elapsed");
  if (second.text !== first.text && /^\d+:\d\d$/.test(second.text)) ok(`data-started: ticks once a second (${first.text} -> ${second.text})`);
  else bad(`data-started: did not tick (${first.text} -> ${second.text})`);
}

// ---------------------------------------------------------------------------
// 3. data-autogrow — the textarea follows scrollHeight at bind and on input.
// ---------------------------------------------------------------------------
{
  const before = await page.evaluate(() => document.getElementById("grow").getBoundingClientRect().height);
  await page.fill("#grow", "line 1\nline 2\nline 3\nline 4\nline 5\nline 6");
  await page.waitForTimeout(120);
  const after = await page.evaluate(() => document.getElementById("grow").getBoundingClientRect().height);
  if (after > before + 10) ok(`data-autogrow: textarea height follows content (${Math.round(before)}px -> ${Math.round(after)}px)`);
  else bad(`data-autogrow: height did not grow (${Math.round(before)}px -> ${Math.round(after)}px)`);
}

// ---------------------------------------------------------------------------
// 4. data-clamp — min,max enforced on change and blur.
// ---------------------------------------------------------------------------
{
  await page.fill("#clamp", "99");
  await page.evaluate(() => document.getElementById("clamp").blur());
  await page.waitForTimeout(80);
  const high = await page.evaluate(() => document.getElementById("clamp").value);
  await page.fill("#clamp", "-5");
  await page.evaluate(() => document.getElementById("clamp").dispatchEvent(new Event("change", { bubbles: true })));
  await page.waitForTimeout(80);
  const low = await page.evaluate(() => document.getElementById("clamp").value);
  if (high === "10") ok("data-clamp: a value above max is clamped on blur (99 -> 10)");
  else bad(`data-clamp: blur clamp produced ${JSON.stringify(high)}, expected "10"`);
  if (low === "1") ok("data-clamp: a value below min is clamped on change (-5 -> 1)");
  else bad(`data-clamp: change clamp produced ${JSON.stringify(low)}, expected "1"`);
}

// ---------------------------------------------------------------------------
// 5. data-roving — one tab stop for the group, arrows move focus.
// ---------------------------------------------------------------------------
{
  const initial = await page.evaluate(() => ["rov-1", "rov-2", "rov-3"].map((id) => document.getElementById(id).getAttribute("tabindex")));
  await page.focus("#rov-1");
  await page.keyboard.press("ArrowDown");
  await page.waitForTimeout(80);
  const moved = await page.evaluate(() => ({
    active: document.activeElement?.id ?? null,
    tabs: ["rov-1", "rov-2", "rov-3"].map((id) => document.getElementById(id).getAttribute("tabindex")),
  }));
  if (initial[0] === "0" && initial[1] === "-1" && initial[2] === "-1") ok("data-roving: the group is one tab stop at mount (0,-1,-1)");
  else bad(`data-roving: initial tabindex was ${JSON.stringify(initial)}, expected ["0","-1","-1"]`);
  if (moved.active === "rov-2" && moved.tabs[1] === "0" && moved.tabs[0] === "-1") ok("data-roving: ArrowDown moves focus and the tab stop with it");
  else bad(`data-roving: ArrowDown left ${JSON.stringify(moved)}`);
}

// ---------------------------------------------------------------------------
// 6. data-table-enhance — sort (numeric vs locale) + aria-sort, and the
//    filter input. one click toggles once, which is also the witness that the
//    binder is not double-bound.
// ---------------------------------------------------------------------------
{
  const order = () => page.evaluate(() => Array.from(document.querySelectorAll("#fx-table tbody tr")).map((r) => r.id));
  const sorts = () => page.evaluate(() => ["th-name", "th-size"].map((id) => document.getElementById(id).getAttribute("aria-sort")));
  await page.click("#th-size");
  await page.waitForTimeout(120);
  const asc = { order: await order(), sorts: await sorts() };
  await page.click("#th-size");
  await page.waitForTimeout(120);
  const desc = { order: await order(), sorts: await sorts() };
  await page.click("#th-name");
  await page.waitForTimeout(120);
  const byName = { order: await order(), sorts: await sorts() };
  if (asc.order.join(",") === "row-a,row-b,row-c" && asc.sorts[1] === "ascending") ok("data-table-enhance: one click sorts numerically ascending and marks aria-sort (3,20,100)");
  else bad(`data-table-enhance: ascending sort produced ${JSON.stringify(asc)}`);
  if (desc.order.join(",") === "row-c,row-b,row-a" && desc.sorts[1] === "descending") ok("data-table-enhance: the next click toggles to descending (one toggle per click — single bind)");
  else bad(`data-table-enhance: descending sort produced ${JSON.stringify(desc)}`);
  if (byName.order.join(",") === "row-a,row-b,row-c" && byName.sorts[0] === "ascending" && byName.sorts[1] === null) ok("data-table-enhance: a text column sorts by localeCompare and moves aria-sort");
  else bad(`data-table-enhance: text sort produced ${JSON.stringify(byName)}`);
  await page.fill("#table-filter", "bet");
  await page.waitForTimeout(120);
  const visible = await page.evaluate(() => Array.from(document.querySelectorAll("#fx-table tbody tr")).filter((r) => !r.hidden).map((r) => r.id));
  if (visible.join(",") === "row-b") ok("data-table-filter: typing filters rows by any cell containing the text");
  else bad(`data-table-filter: visible rows were ${JSON.stringify(visible)}, expected ["row-b"]`);
  await page.fill("#table-filter", "");
  await page.waitForTimeout(80);
}

// ---------------------------------------------------------------------------
// 7. data-copy — clipboard + the engine-owned toast.
// ---------------------------------------------------------------------------
if (!clipboardGranted) {
  skipWithReason("data-copy: this host refused the clipboard permission grant — the write path is unexercised (not a pass)");
} else {
  await page.bringToFront();
  await page.click("#copy-text");
  await page.waitForTimeout(150);
  let clip = null;
  try { clip = await page.evaluate(() => navigator.clipboard.readText()); } catch { clip = null; }
  const toast = await $ ("[data-webui-toast]");
  if (clip === "pinned text") ok("data-copy: click writes the attribute value to the clipboard");
  else bad(`data-copy: clipboard held ${JSON.stringify(clip)}, expected "pinned text"`);
  if (toast && toast.text === "Copied") ok("data-copy: the engine-owned toast shows Copied");
  else bad(`data-copy: toast was ${JSON.stringify(toast)}`);
  await page.click("#copy-empty");
  await page.waitForTimeout(150);
  let clip2 = null;
  try { clip2 = await page.evaluate(() => navigator.clipboard.readText()); } catch { clip2 = null; }
  if (clip2 === "Copy me") ok("data-copy: an empty value copies the element's own text");
  else bad(`data-copy: empty-value copy put ${JSON.stringify(clip2)} on the clipboard`);
  await page.waitForTimeout(2100);
  if (!(await exists("[data-webui-toast]"))) ok("data-copy: the toast is removed after 2 s");
  else bad("data-copy: the toast outlived its 2 s window");
}

// ---------------------------------------------------------------------------
// 8. data-reorder — synthetic drag reorders, writes the id list, fires change.
// ---------------------------------------------------------------------------
{
  await page.evaluate(() => {
    window.__orderChanges = 0;
    document.getElementById("order-input").addEventListener("change", () => { window.__orderChanges++; });
  });
  const dropped = await page.evaluate(() => {
    const dt = new DataTransfer();
    const a = document.getElementById("item-a");
    const c = document.getElementById("item-c");
    a.dispatchEvent(new DragEvent("dragstart", { bubbles: true, cancelable: true, dataTransfer: dt }));
    const r = c.getBoundingClientRect();
    const opts = { bubbles: true, cancelable: true, dataTransfer: dt, clientY: r.bottom - 1 };
    c.dispatchEvent(new DragEvent("dragover", opts));
    c.dispatchEvent(new DragEvent("drop", opts));
    return {
      order: Array.from(document.querySelectorAll("#reorder > li")).map((li) => li.id),
      value: document.getElementById("order-input").value,
      changes: window.__orderChanges,
    };
  });
  if (dropped.order.join(",") === "item-b,item-c,item-a") ok("data-reorder: a drop reorders the id-bearing children");
  else bad(`data-reorder: DOM order after drop was ${JSON.stringify(dropped.order)}`);
  if (dropped.value === "item-b,item-c,item-a") ok("data-reorder: the hidden input receives the comma-joined id list");
  else bad(`data-reorder: hidden input held ${JSON.stringify(dropped.value)}`);
  if (dropped.changes >= 1) ok("data-reorder: change is dispatched on that input");
  else bad("data-reorder: no change event was dispatched on the hidden input");
}

// ---------------------------------------------------------------------------
// 9. data-skip-to — focus moves to the target, tabindex added, no navigation.
// ---------------------------------------------------------------------------
{
  await page.click("#skip");
  await page.waitForTimeout(150);
  const state = await page.evaluate(() => ({
    active: document.activeElement?.id ?? null,
    tabindex: document.getElementById("skip-target").getAttribute("tabindex"),
    hash: location.hash,
  }));
  if (state.active === "skip-target") ok("data-skip-to: click moves real focus to the target");
  else bad(`data-skip-to: focus landed on ${JSON.stringify(state.active)}`);
  if (state.tabindex === "-1") ok("data-skip-to: tabindex=-1 is added when the target has none");
  else bad(`data-skip-to: tabindex was ${JSON.stringify(state.tabindex)}`);
  if (state.hash !== "#skip-target") ok("data-skip-to: the anchor navigation is prevented (the engine owns the move)");
  else bad("data-skip-to: the hash navigation was not prevented");
}

// ---------------------------------------------------------------------------
// 10. data-scroll-to — smooth scroll into view + the 1.4 s flash.
// ---------------------------------------------------------------------------
{
  await page.click("#to-target");
  const flashed = await page.evaluate(() => document.getElementById("scroll-target").hasAttribute("data-scroll-flash"));
  await page.waitForTimeout(900);
  const near = await page.evaluate(() => {
    const r = document.getElementById("scroll-target").getBoundingClientRect();
    return Math.abs(r.top) < 400;
  });
  await page.waitForTimeout(800);
  const cleared = await page.evaluate(() => !document.getElementById("scroll-target").hasAttribute("data-scroll-flash"));
  if (flashed) ok("data-scroll-to: click sets data-scroll-flash on the target");
  else bad("data-scroll-to: data-scroll-flash was not set");
  if (near) ok("data-scroll-to: the target is scrolled into view");
  else bad("data-scroll-to: the target never came into view");
  if (cleared) ok("data-scroll-to: the flash is removed after 1400 ms");
  else bad("data-scroll-to: the flash was still set after 1.7 s");
}

// ---------------------------------------------------------------------------
// 10b. data-scroll-to with an empty value — the document top. dispatched from
//      the bottom of the page by script, because a playwright click would
//      scroll the button into view first and pass on its own.
// ---------------------------------------------------------------------------
{
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(120);
  const from = await page.evaluate(() => window.scrollY);
  await page.evaluate(() => {
    document.getElementById("to-top").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
  });
  await page.waitForTimeout(2000);
  const at = await page.evaluate(() => window.scrollY);
  if (from > 800 && at < 80) ok(`data-scroll-to: an empty value scrolls the document to the top (${Math.round(from)}px -> ${Math.round(at)}px)`);
  else bad(`data-scroll-to: the empty value did not reach the document top (${Math.round(from)}px -> ${Math.round(at)}px)`);
}

// ---------------------------------------------------------------------------
// 10c. data-filter-list — the region's input filters its role=option items by
//      case-insensitive substring, hiding non-matches. driven through the real
//      `WebUIComboBox` markup, so the component's wiring is what is measured.
// ---------------------------------------------------------------------------
{
  const wiring = await page.evaluate(() => {
    const region = document.querySelector("#fx-filter .combo");
    const panel = region ? region.querySelector(".combo__panel") : null;
    const options = region ? Array.from(region.querySelectorAll(".combo__option")) : [];
    return {
      region: region ? region.hasAttribute("data-filter-list") : false,
      roving: panel ? panel.hasAttribute("data-roving") : false,
      dismiss: panel ? panel.hasAttribute("data-dismiss") : false,
      tabindex: options.map((o) => o.getAttribute("tabindex")),
      role: options.map((o) => o.getAttribute("role")),
      tabStops: options.filter((o) => o.getAttribute("tabindex") === "0").length,
    };
  });
  const labelled = wiring.region && wiring.role.every((r) => r === "option");
  const rovingBound = wiring.roving && wiring.dismiss && wiring.tabStops === 1 &&
    wiring.tabindex.filter((t) => t === "0").length === 1;
  if (labelled) ok("data-filter-list: the combo region carries the marker and its items are role=option");
  else bad(`data-filter-list: the combo region wiring was ${JSON.stringify(wiring)}`);
  if (rovingBound) ok("data-roving + data-dismiss: the combo panel carries both and roving left exactly one tab stop");
  else bad(`data-roving/data-dismiss on the combo panel was ${JSON.stringify(wiring)}`);
  await page.fill("#fx-filter .combo input", "BET");
  await page.waitForTimeout(150);
  const filtered = await page.evaluate(() => Array.from(document.querySelectorAll("#fx-filter .combo__option"))
    .map((o) => ({ text: (o.textContent || "").trim(), hidden: o.hidden, display: getComputedStyle(o).display })));
  await page.fill("#fx-filter .combo input", "");
  await page.waitForTimeout(150);
  const restored = await page.evaluate(() => Array.from(document.querySelectorAll("#fx-filter .combo__option"))
    .filter((o) => o.hidden || getComputedStyle(o).display === "none").length);
  const visibleText = filtered.filter((o) => !o.hidden && o.display !== "none").map((o) => o.text);
  const hiddenRight = filtered.filter((o) => o.text !== "beta").every((o) => o.hidden && o.display === "none");
  if (visibleText.join(",") === "beta" && hiddenRight) ok(`data-filter-list: a case-insensitive substring hides the non-matches (${JSON.stringify(filtered.map((o) => o.text + ":" + o.display))})`);
  else bad(`data-filter-list: filtering left ${JSON.stringify(filtered)}`);
  if (restored === 0) ok("data-filter-list: clearing the input restores every item");
  else bad(`data-filter-list: ${restored} items stayed hidden after the input was cleared`);
}

// ---------------------------------------------------------------------------
// 11. data-scrollspy — the section in view marks its own anchor.
// ---------------------------------------------------------------------------
{
  await page.evaluate(() => document.getElementById("sec-c").scrollIntoView({ behavior: "instant", block: "start" }));
  await page.waitForTimeout(400);
  const atC = await page.evaluate(() => ["spy-link-a", "spy-link-b", "spy-link-c"].map((id) => document.getElementById(id).getAttribute("aria-current")));
  await page.evaluate(() => document.getElementById("sec-a").scrollIntoView({ behavior: "instant", block: "start" }));
  await page.waitForTimeout(400);
  const atA = await page.evaluate(() => ["spy-link-a", "spy-link-b", "spy-link-c"].map((id) => document.getElementById(id).getAttribute("aria-current")));
  if (atC[2] === "true" && atC[0] === null) ok("data-scrollspy: the section in view marks its anchor aria-current=true");
  else bad(`data-scrollspy: at section C the anchors were ${JSON.stringify(atC)}`);
  if (atA[0] === "true" && atA[2] === null) ok("data-scrollspy: scrolling back moves the current marker (the old one is cleared)");
  else bad(`data-scrollspy: at section A the anchors were ${JSON.stringify(atA)}`);
}

// ---------------------------------------------------------------------------
// 12. data-inline-edit — local entry, focus inside, Escape cancels, submit
//     saves through the server and clears the marker.
// ---------------------------------------------------------------------------
{
  await page.click("#inline-label");
  await page.waitForTimeout(120);
  const entered = await page.evaluate(() => ({
    editing: document.getElementById("inline").hasAttribute("data-editing"),
    active: document.activeElement?.id ?? null,
  }));
  await page.keyboard.press("Escape");
  await page.waitForTimeout(100);
  const cancelled = await page.evaluate(() => document.getElementById("inline").hasAttribute("data-editing"));
  await page.click("#inline-label");
  await page.fill("#inline-input", "renamed by the probe");
  await page.keyboard.press("Enter");
  await page.waitForTimeout(400);
  const saved = await page.evaluate(() => ({
    editing: document.getElementById("inline").hasAttribute("data-editing"),
    text: (document.getElementById("inline-saved")?.textContent || "").trim(),
  }));
  if (entered.editing && entered.active === "inline-input") ok("data-inline-edit: click sets data-editing and focuses the first input");
  else bad(`data-inline-edit: entry produced ${JSON.stringify(entered)}`);
  if (!cancelled) ok("data-inline-edit: Escape cancels (data-editing removed, no round trip)");
  else bad("data-inline-edit: Escape left data-editing set");
  if (!saved.editing && saved.text.includes("renamed by the probe")) ok("data-inline-edit: the native form submit saves through the server and clears data-editing");
  else bad(`data-inline-edit: submit produced ${JSON.stringify(saved)}`);
}

// ---------------------------------------------------------------------------
// 13. data-submit-on-enter + data-clear-on-submit.
// ---------------------------------------------------------------------------
{
  await page.click("#submit-input");
  await page.keyboard.type("hello");
  await page.keyboard.press("Enter");
  await page.waitForTimeout(400);
  const submitted = await page.evaluate(() => ({
    out: (document.getElementById("submit-out")?.textContent || "").trim(),
    value: document.getElementById("submit-input").value,
  }));
  if (submitted.out.includes("hello")) ok("data-submit-on-enter: Enter in a single-line input submits its form (server echoed q)");
  else bad(`data-submit-on-enter: the form did not submit — ${JSON.stringify(submitted)}`);
  if (submitted.value === "") ok("data-clear-on-submit: the control clears on the form's submit event");
  else bad(`data-clear-on-submit: the control still held ${JSON.stringify(submitted.value)}`);

  await page.click("#submit-area");
  await page.keyboard.type("line one");
  await page.keyboard.press("Enter");
  await page.keyboard.type("line two");
  await page.waitForTimeout(200);
  const area = await page.evaluate(() => ({
    value: document.getElementById("submit-area").value,
    out: (document.getElementById("submit-out")?.textContent || "").trim(),
  }));
  if (area.value.includes("\n") && area.out.includes("hello")) ok("data-submit-on-enter: a textarea is exempt (Enter inserts a newline, no submit)");
  else bad(`data-submit-on-enter: textarea exemption failed — ${JSON.stringify(area)}`);

  await page.click("#submit-exempt");
  await page.keyboard.type("keep");
  await page.keyboard.press("Enter");
  await page.waitForTimeout(300);
  const exempt = await page.evaluate(() => ({
    value: document.getElementById("submit-exempt").value,
    out: (document.getElementById("submit-out")?.textContent || "").trim(),
  }));
  if (exempt.value === "keep" && exempt.out.includes("hello")) ok('data-submit-on-enter: data-prevent-enter="false" exempts the control');
  else bad(`data-submit-on-enter: prevent-enter exemption failed — ${JSON.stringify(exempt)}`);
}

// ---------------------------------------------------------------------------
// 14. data-dismiss — one LIFO stack; Escape closes the topmost, an outside
//     click closes the topmost, and closing dispatches the layer's own control.
// ---------------------------------------------------------------------------
{
  await page.click("#open-a");
  await page.waitForTimeout(400);
  await page.click("#open-b");
  await page.waitForTimeout(400);
  const opened = await page.evaluate(() => ({
    children: Array.from(document.querySelectorAll("#layers > *")).map((el) => el.id),
    hasA: !!document.getElementById("layer-a"),
    hasB: !!document.getElementById("layer-b"),
  }));
  await page.evaluate(() => {
    window.__closeAClicks = 0;
    document.getElementById("close-a").addEventListener("click", () => { window.__closeAClicks++; });
  });
  await page.keyboard.press("Escape");
  await page.waitForTimeout(450);
  const afterFirst = await page.evaluate(() => ({
    hasA: !!document.getElementById("layer-a"),
    hasB: !!document.getElementById("layer-b"),
  }));
  await page.keyboard.press("Escape");
  await page.waitForTimeout(450);
  const afterSecond = await page.evaluate(() => ({
    hasA: !!document.getElementById("layer-a"),
    clicks: window.__closeAClicks,
  }));
  if (opened.hasA && opened.hasB && opened.children[0] === "layer-b") {
    ok("data-dismiss: two visible layers stack (the later-opened layer is first in the document)");
  } else {
    bad(`data-dismiss: layer stack was ${JSON.stringify(opened)}`);
  }
  if (!afterFirst.hasB && afterFirst.hasA) ok("data-dismiss: Escape closes the TOPMOST layer, not the last in document order (LIFO)");
  else bad(`data-dismiss: after the first Escape ${JSON.stringify(afterFirst)}`);
  if (!afterSecond.hasA && afterSecond.clicks === 1) ok("data-dismiss: the second Escape closes the next layer through its own close control");
  else bad(`data-dismiss: after the second Escape ${JSON.stringify(afterSecond)}`);

  await page.click("#open-a");
  await page.waitForTimeout(400);
  await page.click("#outside");
  await page.waitForTimeout(450);
  if (!(await exists("#layer-a"))) ok("data-dismiss: a click outside the topmost layer closes it");
  else bad("data-dismiss: an outside click left the layer open");
}

// ---------------------------------------------------------------------------
// 15. data-preserve-open — the open state is the reader's, across a patch.
// ---------------------------------------------------------------------------
{
  await page.evaluate(() => { document.getElementById("feed-more").open = true; });
  await page.waitForTimeout(80);
  await page.evaluate(() => document.getElementById("patch").click());
  await page.waitForTimeout(450);
  const stillOpen = await page.evaluate(() => document.getElementById("feed-more")?.open ?? null);
  await page.evaluate(() => { document.getElementById("feed-more").open = false; });
  await page.waitForTimeout(80);
  await page.evaluate(() => document.getElementById("patch").click());
  await page.waitForTimeout(450);
  const stillClosed = await page.evaluate(() => document.getElementById("feed-more")?.open ?? null);
  if (stillOpen === true) ok("data-preserve-open: an open <details> stays open across a patch");
  else bad(`data-preserve-open: open state after the patch was ${JSON.stringify(stillOpen)}`);
  if (stillClosed === false) ok("data-preserve-open: a reader-closed <details> stays closed across a patch");
  else bad(`data-preserve-open: closed state after the patch was ${JSON.stringify(stillClosed)}`);
}

// ---------------------------------------------------------------------------
// 16. data-scroll-key — the offset follows the key, not the element id.
// ---------------------------------------------------------------------------
{
  const before = await page.evaluate(() => {
    const el = document.querySelector("#feed [data-scroll-key]");
    el.scrollTop = 40;
    return { id: el.id, top: el.scrollTop };
  });
  await page.evaluate(() => document.getElementById("patch").click());
  await page.waitForTimeout(450);
  const after = await page.evaluate(() => {
    const el = document.querySelector("#feed [data-scroll-key]");
    return { id: el.id, top: el.scrollTop };
  });
  if (before.top === 40 && after.top === 40 && after.id !== before.id) {
    ok(`data-scroll-key: the offset is restored across a patch to a different element id (${before.id} -> ${after.id})`);
  } else {
    bad(`data-scroll-key: offset was ${before.top} on ${before.id}, then ${after.top} on ${after.id}`);
  }
}

// ---------------------------------------------------------------------------
// 17. data-follow — pinned at the bottom, released when the reader scrolls up,
//     re-stuck at the bottom; data-follow="off" does nothing.
// ---------------------------------------------------------------------------
{
  const atBottom = () => page.evaluate(() => {
    const el = document.getElementById("feed");
    return el.scrollHeight - el.scrollTop - el.clientHeight;
  });
  await page.evaluate(() => {
    const el = document.getElementById("feed");
    el.scrollTop = el.scrollHeight;
    el.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(120);
  const stuckState = await page.evaluate(() => document.getElementById("feed").getAttribute("data-follow-state"));
  await page.evaluate(() => document.getElementById("patch").click());
  await page.waitForTimeout(450);
  const gap = await atBottom();
  if (stuckState === null && gap <= 24) ok(`data-follow: a patch from the bottom stays at the bottom (gap ${gap}px <= 24)`);
  else bad(`data-follow: after the patch the gap was ${gap}px (state ${JSON.stringify(stuckState)})`);

  await page.evaluate(() => {
    const el = document.getElementById("feed");
    el.scrollTop = 0;
    el.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(120);
  const away = await page.evaluate(() => document.getElementById("feed").getAttribute("data-follow-state"));
  await page.evaluate(() => document.getElementById("patch").click());
  await page.waitForTimeout(450);
  const awayAfter = await page.evaluate(() => ({
    state: document.getElementById("feed").getAttribute("data-follow-state"),
    top: document.getElementById("feed").scrollTop,
  }));
  if (away === "away") ok('data-follow-state: a reader scroll-up releases the pin (data-follow-state="away")');
  else bad(`data-follow-state: release produced ${JSON.stringify(away)}`);
  if (awayAfter.state === "away" && awayAfter.top <= 24) ok("data-follow: a patch while detached does not yank the reader back to the bottom");
  else bad(`data-follow: detached patch produced ${JSON.stringify(awayAfter)}`);

  const offState = await page.evaluate(() => {
    const el = document.getElementById("follow-off");
    el.scrollTop = 0;
    el.dispatchEvent(new Event("scroll"));
    return el.getAttribute("data-follow-state");
  });
  if (offState === null) ok('data-follow="off": the region is never bound (no follow state is written)');
  else bad(`data-follow="off": the engine wrote ${JSON.stringify(offState)}`);
}

// ---------------------------------------------------------------------------
// 18. data-focus-return — focus lost with the replaced region comes back to
//     the declared id.
// ---------------------------------------------------------------------------
{
  await page.focus("#feed-link");
  const had = await page.evaluate(() => document.activeElement?.id ?? null);
  await page.evaluate(() => document.getElementById("patch").click());
  await page.waitForTimeout(450);
  const now = await page.evaluate(() => document.activeElement?.id ?? null);
  if (had === "feed-link" && now === "panel-search") ok("data-focus-return: focus inside a replaced region returns to the declared id");
  else bad(`data-focus-return: focus was ${JSON.stringify(had)} then ${JSON.stringify(now)}, expected feed-link then panel-search`);
}

// ---------------------------------------------------------------------------
// 19. data-theme-choice — the existing reconciliation, extended not duplicated.
// ---------------------------------------------------------------------------
{
  await page.click("#theme-dark");
  await page.waitForTimeout(150);
  const dark = await page.evaluate(() => ({
    theme: document.documentElement.getAttribute("data-theme"),
    pressed: [document.getElementById("theme-dark").getAttribute("aria-pressed"), document.getElementById("theme-light").getAttribute("aria-pressed")],
  }));
  await page.click("#theme-light");
  await page.waitForTimeout(150);
  const light = await page.evaluate(() => document.documentElement.getAttribute("data-theme"));
  if (dark.theme === "dark" && dark.pressed[0] === "true" && dark.pressed[1] === "false") ok("data-theme-choice: the choice applies and aria-pressed reconciles (existing path)");
  else bad(`data-theme-choice: dark produced ${JSON.stringify(dark)}`);
  if (light === "light") ok("data-theme-choice: the second choice applies too");
  else bad(`data-theme-choice: light produced ${JSON.stringify(light)}`);
}

// ---------------------------------------------------------------------------
// 20. island inertness — a behavior inside [data-webui-island] is never bound.
// ---------------------------------------------------------------------------
{
  const island = await page.evaluate(() => {
    const region = document.getElementById("fx-island");
    const inner = document.getElementById("island-follow");
    inner.scrollTop = 0;
    inner.dispatchEvent(new Event("scroll"));
    const control = document.getElementById("feed");
    control.scrollTop = 0;
    control.dispatchEvent(new Event("scroll"));
    return {
      state: region.getAttribute("data-webui-island-state"),
      inside: !!inner.closest("[data-webui-island]"),
      islandState: inner.getAttribute("data-follow-state"),
      controlState: control.getAttribute("data-follow-state"),
    };
  });
  if (island.inside && island.islandState === null) ok("data-follow inside [data-webui-island]: no consequence runs (islands are behavior-free)");
  else bad(`island inertness: ${JSON.stringify(island)}`);
  if (island.controlState === "away") ok("island inertness control: the same scroll on a page region does write data-follow-state");
  else bad(`island inertness control failed (the probe would pass vacuously): ${JSON.stringify(island)}`);
}

// ---------------------------------------------------------------------------
// 21. data-draft-id — the unsubmitted value survives a reload.
// ---------------------------------------------------------------------------
{
  await page.fill("#draft", "hello draft");
  await page.waitForTimeout(120);
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForTimeout(700);
  const restored = await page.evaluate(() => document.getElementById("draft")?.value ?? null);
  if (restored === "hello draft") ok("data-draft-id: the draft is restored from sessionStorage at bind when the field is empty");
  else bad(`data-draft-id: after the reload the field held ${JSON.stringify(restored)}`);
}

// ---------------------------------------------------------------------------
// 21b. HandlerOutcome.refresh — a `.control` whose handler returns `.refresh`:
//      the server re-renders the page in the dispatch session, diffs it against
//      the session's baseline, ships the region whose bytes moved, and the
//      engine's afterPatch funnel restores the reader's state inside it.
// ---------------------------------------------------------------------------
{
  // the reader's state, every bit of it INSIDE the region the refresh replaces.
  await page.fill("#refresh-draft", "draft survives a refresh");
  await page.evaluate(() => {
    document.querySelector("#fx-refresh-region [data-scroll-key]").scrollTop = 30;
    document.getElementById("refresh-link").focus();
    window.__refreshSurvives = 1;
    // a node OUTSIDE the region: it must be the same node after the refresh,
    // which is what makes "a region patch" true and "a document/body replace"
    // false. the draft field below is deliberately inside the region.
    window.__refreshOutsideNode = document.getElementById("draft");
  });
  await page.waitForTimeout(150);
  const before = await page.evaluate(() => {
    const thread = document.querySelector("#fx-refresh-region [data-scroll-key]");
    return {
      count: (document.getElementById("refresh-count")?.textContent || "").trim(),
      focus: document.activeElement?.id ?? null,
      scroll: thread ? thread.scrollTop : null,
      draft: document.getElementById("refresh-draft")?.value ?? null,
    };
  });

  // a programmatic click: it fires the delegated handler without moving focus,
  // so the focus-return assertion below is about the patch, not about the click.
  await page.evaluate(() => document.getElementById("refresh").click());
  await page.waitForTimeout(800);

  const after = await page.evaluate(() => {
    const thread = document.querySelector("#fx-refresh-region [data-scroll-key]");
    return {
      count: (document.getElementById("refresh-count")?.textContent || "").trim(),
      focus: document.activeElement?.id ?? null,
      scroll: thread ? thread.scrollTop : null,
      draft: document.getElementById("refresh-draft")?.value ?? null,
      sameOutsideNode: window.__refreshOutsideNode === document.getElementById("draft"),
      marker: window.__refreshSurvives,
      region: !!document.getElementById("fx-refresh-region"),
    };
  });

  if (before.count === "refreshes: 0" && after.count === "refreshes: 1" && after.region) {
    ok("refresh: a .control returning .refresh re-rendered the page and patched the region carrying the new state");
  } else {
    bad(`refresh: region count went ${JSON.stringify(before.count)} -> ${JSON.stringify(after.count)} (region present: ${after.region})`);
  }
  if (after.sameOutsideNode && after.marker === 1) {
    ok("refresh: the update was a region patch, not a document load (a node outside the region and page state survived)");
  } else {
    bad(`refresh: expected a region patch; outside node reused=${after.sameOutsideNode}, page state=${after.marker}`);
  }
  if (before.focus === "refresh-link" && after.focus === "refresh-search") {
    ok("refresh: focus inside a data-focus-return region survives the refresh (restored to the declared id)");
  } else {
    bad(`refresh: focus was ${JSON.stringify(before.focus)} then ${JSON.stringify(after.focus)}`);
  }
  if (before.scroll === 30 && after.scroll === 30) {
    ok("refresh: a data-scroll-key offset survives the refresh (the region was replaced, the offset came back)");
  } else {
    bad(`refresh: data-scroll-key offset was ${JSON.stringify(before.scroll)} then ${JSON.stringify(after.scroll)}`);
  }
  if (before.draft === "draft survives a refresh" && after.draft === before.draft) {
    ok("refresh: a data-draft-id value survives the refresh (the replaced field was repopulated)");
  } else {
    bad(`refresh: draft value was ${JSON.stringify(before.draft)} then ${JSON.stringify(after.draft)}`);
  }
}

// ---------------------------------------------------------------------------
// 22. data-reltime repaints on its 60 s tick (the last assertion: it waits).
// ---------------------------------------------------------------------------
{
  const before = await page.evaluate(() => (document.getElementById("rel-2")?.textContent || "").trim());
  await page.waitForTimeout(61000);
  const after = await page.evaluate(() => (document.getElementById("rel-2")?.textContent || "").trim());
  if (/^\d+m$/.test(before) && /^\d+m$/.test(after) && after !== before) {
    ok(`data-reltime: the label repaints on the 60 s tick (${before} -> ${after})`);
  } else {
    bad(`data-reltime: no repaint in 61 s (${JSON.stringify(before)} -> ${JSON.stringify(after)})`);
  }
}

// ---------------------------------------------------------------------------
// 23. runtime hygiene: no uncaught exceptions, no unexpected console errors.
// ---------------------------------------------------------------------------
{
  const unexpected = consoleErrors.filter((t) =>
    !/behaviour-island\.wasm/.test(t) && !/Failed to load resource/.test(t) && !/websocket|ws:\/\//i.test(t)
  );
  if (pageErrors.length === 0) ok("no uncaught page exceptions while driving every consequence");
  else bad(`page exceptions: ${JSON.stringify(pageErrors)}`);
  if (unexpected.length === 0) ok("no unexpected console errors (the island 404 degrade and ws handshake noise filtered)");
  else bad(`unexpected console errors: ${JSON.stringify(unexpected.slice(0, 5))}`);
}

// ---------------------------------------------------------------------------
// 24. the documented degrade: abort the extension request and the page keeps
//     its core consequences. a fresh context, so this page's error budget is
//     its own — no uncaught exception, one warning, data-follow still writes
//     its state, and the extension's consequences stay inert.
// ---------------------------------------------------------------------------
{
  const degraded = await browser.newContext({ viewport: { width: 1200, height: 800 } });
  await degraded.route("**/webui-engine-ext.js", (route) => route.abort());
  const degradedPage = await degraded.newPage();
  const degradedErrors = [];
  const degradedWarnings = [];
  degradedPage.on("pageerror", (e) => degradedErrors.push(String(e)));
  degradedPage.on("console", (m) => { if (m.type() === "warning") degradedWarnings.push(m.text()); });
  await degradedPage.goto(BASE + "/behaviour", { waitUntil: "domcontentloaded" });
  await degradedPage.waitForTimeout(900);
  const state = await degradedPage.evaluate(() => {
    const feed = document.getElementById("feed");
    feed.scrollTop = 0;
    feed.dispatchEvent(new Event("scroll"));
    return {
      follow: feed.getAttribute("data-follow-state"),
      reltime: (document.getElementById("rel-1")?.textContent || "").trim(),
      roving: document.getElementById("rov-1").getAttribute("tabindex"),
    };
  });
  const warned = degradedWarnings.some((t) => /behavior extension unavailable/.test(t));
  const coreWorks = state.follow === "away";
  const extInert = state.reltime === "-" && state.roving === null;
  if (degradedErrors.length === 0 && warned && coreWorks && extInert) {
    ok(`extension fetch aborted: no uncaught errors, one warning, data-follow still writes data-follow-state="${state.follow}", and data-reltime/data-roving stay inert (${JSON.stringify(state.reltime)}, tabindex ${JSON.stringify(state.roving)})`);
  } else {
    bad(`the degrade path failed — errors ${JSON.stringify(degradedErrors)}, warned ${warned}, follow ${JSON.stringify(state.follow)}, reltime ${JSON.stringify(state.reltime)}, roving-tabindex ${JSON.stringify(state.roving)}`);
  }
  await degraded.close();
}

await browser.close();
server.kill();

console.log(`\n=== summary: ${pass} passed, ${fail} failed${skip > 0 ? `, ${skip} skipped` : ""} ===`);
if (fail > 0) {
  console.log("BEHAVIOUR PROBE FAIL");
  process.exit(1);
}
console.log(skip > 0 ? "BEHAVIOUR PROBE PASS (with skips — an environmental gap was reported, never a pass)" : "BEHAVIOUR PROBE PASS");
process.exit(0);
