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

// a page-side predicate polled to a deadline: a filter, a class flip or a
// hidden-attribute write lands on the engine's own schedule, so one sample is
// a race, never a measurement. the predicate returns `{ ok, ... }`.
async function settled(predicate, arg = undefined, tries = 40) {
  let last = null;
  for (let i = 0; i < tries; i++) {
    last = await page.evaluate(predicate, arg);
    if (last && last.ok) return last;
    await page.waitForTimeout(50);
  }
  return last;
}

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
  const started = Date.now();
  await page.click("#to-target");
  const flashed = await page.evaluate(() => document.getElementById("scroll-target").hasAttribute("data-scroll-flash"));
  // smooth scroll duration grows with the distance, and this fixture keeps
  // growing: poll the settled position instead of sampling one frame.
  const near = await page.waitForFunction(() => {
    const r = document.getElementById("scroll-target").getBoundingClientRect();
    return Math.abs(r.top) < 400;
  }, null, { timeout: 3000 }).then(() => true).catch(() => false);
  const cleared = await page.waitForFunction(() => !document.getElementById("scroll-target").hasAttribute("data-scroll-flash"), null, { timeout: 4000 }).then(() => true).catch(() => false);
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
      open: panel ? panel.hasAttribute("data-open") : null,
      display: panel ? getComputedStyle(panel).display : null,
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
  // read before any focus reaches the combo: the panel is open only while the
  // engine says so (`data-open`), and nothing has said so at load.
  if (wiring.open === false && wiring.display === "none") ok("data-open: the combo panel is closed at load (no attribute, display:none)");
  else bad(`data-open: the combo panel at load was ${JSON.stringify({ open: wiring.open, display: wiring.display })}`);
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
// 10d. data-filter-list with an external source, and the write-back:
//      `data-filter-insert` + `data-filter-template` + `data-filter-clear`.
//      the query is typed into a composer outside the list; the selection is
//      written back at the composer's caret, and the typed token is stripped
//      first. one behavior per attribute, three attributes, one consequence.
// ---------------------------------------------------------------------------
{
  const wiring = await page.evaluate(() => {
    const el = document.getElementById("fx-palette");
    return {
      source: el ? el.getAttribute("data-filter-list") : null,
      insert: el ? el.getAttribute("data-filter-insert") : null,
      template: el ? el.getAttribute("data-filter-template") : null,
      clear: el ? el.hasAttribute("data-filter-clear") : false,
      items: el ? Array.from(el.querySelectorAll("[role=menuitem]")).map((i) => (i.textContent || "").trim()) : [],
    };
  });
  const wired = wiring.source === "#fx-composer" && wiring.insert === "fx-composer" &&
    wiring.template === "{value} " && wiring.clear && wiring.items.length === 3;
  if (wired) {
    ok(`data-filter-insert + data-filter-template + data-filter-clear: the region names the external source (${wiring.source}), the write-back target (${wiring.insert}) and the template (${JSON.stringify(wiring.template)})`);
  } else {
    bad(`data-filter-list source/write-back wiring was ${JSON.stringify(wiring)}`);
  }

  // typing in the SOURCE filters the region's items (the source is outside the
  // region, so this only holds if the binder resolves it).
  await page.fill("#fx-composer", "hel");
  const filtered = await settled(() => {
    const items = Array.from(document.querySelectorAll("#fx-palette [role=menuitem]"));
    const visible = items.filter((i) => !i.hidden).map((i) => (i.textContent || "").trim());
    return { ok: visible.join(",") === "hello,help", visible, hidden: items.filter((i) => i.hidden).map((i) => (i.textContent || "").trim()) };
  });
  if (filtered && filtered.ok) {
    ok(`data-filter-list: typing in the external source filters the items (visible ${filtered.visible.join(",")}; hidden ${filtered.hidden.join(",")})`);
  } else {
    bad(`data-filter-list: the external source left ${JSON.stringify(filtered)}`);
  }

  // a click selects: the token before the caret ("hel") is stripped, the
  // template is resolved against the item's trimmed text and inserted at the
  // caret, and the caret lands after it.
  await page.evaluate(() => {
    const box = document.getElementById("fx-composer");
    box.focus();
    box.setSelectionRange(box.value.length, box.value.length);
  });
  await page.click("#fx-item-help");
  const clicked = await settled(() => {
    const box = document.getElementById("fx-composer");
    return { ok: box.value === "help " && box.selectionStart === 5, value: box.value, caret: box.selectionStart };
  });
  if (clicked && clicked.ok) {
    ok(`data-filter-clear + data-filter-template: a click writes "${clicked.value}" — the query token stripped, the template inserted at the caret (caret ${clicked.caret})`);
  } else {
    bad(`data-filter-clear: after the click the composer read ${JSON.stringify(clicked)}, expected "help " with the caret at 5`);
  }

  // the caret decides the insertion point, not the end of the field: the same
  // query with the caret at 0 inserts at 0 and leaves the text after it.
  await page.fill("#fx-composer", "hel");
  await page.evaluate(() => document.getElementById("fx-composer").setSelectionRange(0, 0));
  await page.click("#fx-item-hello");
  const atCaret = await settled(() => {
    const box = document.getElementById("fx-composer");
    return { ok: box.value === "hello hel" && box.selectionStart === 6, value: box.value, caret: box.selectionStart };
  });
  if (atCaret && atCaret.ok) {
    ok(`data-filter-insert: the insertion follows the caret, not the end of the field ("${atCaret.value}", caret ${atCaret.caret})`);
  } else {
    bad(`data-filter-insert: a caret at 0 produced ${JSON.stringify(atCaret)}, expected "hello hel" with the caret at 6`);
  }

  // Enter on a focused item selects it too.
  await page.fill("#fx-composer", "wor");
  await page.focus("#fx-item-world");
  await page.keyboard.press("Enter");
  const entered = await settled(() => {
    const box = document.getElementById("fx-composer");
    return { ok: box.value === "world ", value: box.value };
  });
  if (entered && entered.ok) ok(`data-filter-insert: Enter on a focused item writes it back ("${entered.value}")`);
  else bad(`data-filter-insert: Enter left the composer at ${JSON.stringify(entered)}, expected "world "`);
}

// ---------------------------------------------------------------------------
// 10e. the combo's open state: `.combo__panel` is hidden unless it carries
//      `data-open` (engine-written). the field's focus opens it, typing keeps
//      it open, and Escape closes it through the engine's layer path.
// ---------------------------------------------------------------------------
{
  await page.focus("#fx-filter .combo input");
  const opened = await settled(() => {
    const panel = document.querySelector("#fx-filter .combo__panel");
    return { ok: !!panel && panel.hasAttribute("data-open") && panel.getClientRects().length > 0,
      open: !!panel && panel.hasAttribute("data-open"), display: panel ? getComputedStyle(panel).display : null };
  });
  if (opened && opened.ok) ok("data-open: the field's focus opens the combo panel (attribute set, panel on screen)");
  else bad(`data-open: focus left the combo panel ${JSON.stringify(opened)}`);

  await page.fill("#fx-filter .combo input", "bet");
  const whileTyping = await settled(() => {
    const panel = document.querySelector("#fx-filter .combo__panel");
    const visible = Array.from(document.querySelectorAll("#fx-filter .combo__option"))
      .filter((o) => !o.hidden).map((o) => (o.textContent || "").trim());
    return { ok: !!panel && panel.hasAttribute("data-open") && visible.join(",") === "beta", open: !!panel && panel.hasAttribute("data-open"), visible };
  });
  if (whileTyping && whileTyping.ok) {
    ok(`data-open: the panel stays open while typing and the filter still hides the non-matches (visible ${whileTyping.visible.join(",")})`);
  } else {
    bad(`data-open: typing left ${JSON.stringify(whileTyping)}, expected the panel open and only beta visible`);
  }

  await page.keyboard.press("Escape");
  const escaped = await settled(() => {
    const panel = document.querySelector("#fx-filter .combo__panel");
    const live = Array.from(document.querySelectorAll("[data-dismiss]")).filter((el) => el.getClientRects().length > 0);
    return { ok: !!panel && !panel.hasAttribute("data-open") && getComputedStyle(panel).display === "none" && live.length === 0,
      open: !!panel && panel.hasAttribute("data-open"), display: panel ? getComputedStyle(panel).display : null, live: live.length };
  });
  if (escaped && escaped.ok) ok("data-open: Escape closes the combo and leaves no layer on screen");
  else bad(`data-open: Escape left ${JSON.stringify(escaped)}, expected the panel closed and no live layer`);

  // a click into the field is not "outside": the open state survives it.
  await page.click("#fx-filter .combo input");
  const reclined = await settled(() => {
    const panel = document.querySelector("#fx-filter .combo__panel");
    return { ok: !!panel && panel.hasAttribute("data-open"), open: !!panel && panel.hasAttribute("data-open") };
  });
  if (reclined && reclined.ok) ok("data-open: clicking the field keeps the panel open (a field click is not an outside click)");
  else bad(`data-open: a click into the field closed the panel (${JSON.stringify(reclined)})`);

  await page.keyboard.press("Escape");
  await page.waitForTimeout(150);

  // the one main-asset change (`closeLayer`'s `data-open` branch) is reachable
  // only while the panel is still in the engine's layer list. a fresh page whose
  // FIRST gesture is focus has not run the outside-click pass that prunes
  // off-screen layers, so there the panel is the registered top layer and the
  // engine's escape closes it through `closeLayer` (the binder's own listener
  // then finds it already closed).
  const freshPage = await context.newPage();
  await freshPage.goto(BASE + "/behaviour", { waitUntil: "domcontentloaded" });
  await freshPage.waitForTimeout(900);
  await freshPage.focus("#fx-filter .combo input");
  await freshPage.waitForTimeout(200);
  const freshOpen = await freshPage.evaluate(() => document.querySelector("#fx-filter .combo__panel").hasAttribute("data-open"));
  await freshPage.keyboard.press("Escape");
  await freshPage.waitForTimeout(200);
  const freshClosed = await freshPage.evaluate(() => ({
    open: document.querySelector("#fx-filter .combo__panel").hasAttribute("data-open"),
    live: Array.from(document.querySelectorAll("[data-dismiss]")).filter((el) => el.getClientRects().length > 0).length,
  }));
  if (freshOpen && !freshClosed.open && freshClosed.live === 0) {
    ok("data-open: on a page whose first gesture is focus, the registered layer's Escape clears data-open (closeLayer's branch)");
  } else {
    bad(`data-open: the fresh-page layer Escape left ${JSON.stringify({ freshOpen, freshClosed })}`);
  }
  await freshPage.close();
}

// ---------------------------------------------------------------------------
// 10f. the drawer's open state. it is one surface with two forms, split at the
//      860px breakpoint the navbar collapses at: at 600px the closed drawer is
//      off-canvas and `data-open` is the layer (scrim, focus entry, Escape and
//      its own close control); at 1200px it is the static rail and the toggle
//      cannot move it. the drawer page is its own tab so the always-rendered
//      rail never changes the main page's "no layer on screen" measurements,
//      and the closed drawer doubles as the layer-ordering witness: with it
//      shut, Escape must reach an unrelated open layer.
// ---------------------------------------------------------------------------
{
  const drawerPage = await context.newPage();
  const drawerErrors = [];
  drawerPage.on("pageerror", (e) => drawerErrors.push(String(e)));
  await drawerPage.setViewportSize({ width: 600, height: 800 });
  await drawerPage.goto(BASE + "/behaviour?drawer=1", { waitUntil: "domcontentloaded" });
  await drawerPage.waitForTimeout(900);

  // a drawer-page predicate polled to a deadline — the engine writes the
  // attribute on its own schedule, so one sample is a race.
  const drawerSettled = async (predicate, tries = 40) => {
    let last = null;
    for (let i = 0; i < tries; i++) {
      last = await drawerPage.evaluate(predicate);
      if (last && last.ok) return last;
      await drawerPage.waitForTimeout(50);
    }
    return last;
  };
  const drawerState = () => drawerPage.evaluate(() => {
    const root = document.getElementById("fx-drawer");
    const panel = root ? root.querySelector(".drawer__panel") : null;
    const scrim = root ? root.querySelector(".drawer__scrim") : null;
    const active = document.activeElement;
    return {
      root: !!root,
      open: root ? root.hasAttribute("data-open") : null,
      display: root ? getComputedStyle(root).display : null,
      panel: panel ? panel.getClientRects().length > 0 : false,
      scrim: scrim ? (scrim.getClientRects().length > 0 && getComputedStyle(scrim).display !== "none") : false,
      focus: active ? (active.id || active.tagName) : null,
      inside: !!(panel && active && panel.contains(active)),
    };
  });

  const atLoad = await drawerState();
  const wiring = await drawerPage.evaluate(() => {
    const root = document.getElementById("fx-drawer");
    const panel = root ? root.querySelector(".drawer__panel") : null;
    const scrim = root ? root.querySelector(".drawer__scrim") : null;
    return {
      rootID: root ? root.id : null,
      scrim: scrim ? scrim.getAttribute("data-drawer-toggle") : null,
      close: document.getElementById("fx-drawer-close")?.getAttribute("data-drawer-toggle") || null,
      host: document.getElementById("fx-drawer-open")?.getAttribute("data-drawer-toggle") || null,
      tabindex: panel ? panel.getAttribute("tabindex") : null,
      dismiss: panel ? panel.hasAttribute("data-dismiss") : false,
    };
  });
  if (atLoad.root && atLoad.open === false && atLoad.display === "none" && !atLoad.panel && !atLoad.scrim) {
    ok("drawer: at 600px the closed drawer is off-canvas at load (no data-open, root display:none, panel and scrim off screen)");
  } else {
    bad(`drawer: at load the drawer was ${JSON.stringify(atLoad)}`);
  }
  const wired = wiring.rootID === "fx-drawer" && wiring.scrim === "fx-drawer" &&
    wiring.close === "fx-drawer" && wiring.host === "fx-drawer" &&
    wiring.tabindex === "-1" && wiring.dismiss;
  if (wired) {
    ok(`data-drawer-toggle: the root id is the state, and the host button, the scrim and the close control all name it (panel tabindex ${wiring.tabindex}, panel data-dismiss ${wiring.dismiss})`);
  } else {
    bad(`data-drawer-toggle: the drawer wiring was ${JSON.stringify(wiring)}`);
  }

  await drawerPage.click("#fx-drawer-open");
  const opened = await drawerSettled(() => {
    const root = document.getElementById("fx-drawer");
    const panel = root.querySelector(".drawer__panel");
    const scrim = root.querySelector(".drawer__scrim");
    const active = document.activeElement;
    return {
      ok: root.hasAttribute("data-open") && root.getClientRects().length > 0 &&
        panel.getClientRects().length > 0 && scrim.getClientRects().length > 0 &&
        getComputedStyle(scrim).display !== "none" && !!active && panel.contains(active),
      open: root.hasAttribute("data-open"),
      display: getComputedStyle(root).display,
      panel: panel.getClientRects().length > 0,
      scrim: scrim.getClientRects().length > 0,
      focus: active ? (active.id || active.tagName) : null,
    };
  });
  if (opened && opened.ok) {
    ok(`data-drawer-toggle: a click opens the drawer with no round-trip (data-open set, root and panel on screen, scrim shown, focus inside the panel on ${opened.focus})`);
  } else {
    bad(`data-drawer-toggle: the opening click left ${JSON.stringify(opened)}`);
  }

  await drawerPage.click("#fx-drawer .drawer__scrim", { position: { x: 20, y: 20 } });
  const byScrim = await drawerSettled(() => {
    const root = document.getElementById("fx-drawer");
    return {
      ok: !root.hasAttribute("data-open") && getComputedStyle(root).display === "none" && document.activeElement?.id === "fx-drawer-open",
      open: root.hasAttribute("data-open"),
      display: getComputedStyle(root).display,
      focus: document.activeElement?.id || null,
    };
  });
  if (byScrim && byScrim.ok) ok("data-open: a scrim click closes the drawer and returns focus to the toggle");
  else bad(`data-open: the scrim click left ${JSON.stringify(byScrim)}`);

  await drawerPage.click("#fx-drawer-open");
  await drawerSettled(() => ({ ok: document.getElementById("fx-drawer").hasAttribute("data-open") }));
  await drawerPage.keyboard.press("Escape");
  const byEscape = await drawerSettled(() => {
    const root = document.getElementById("fx-drawer");
    return {
      ok: !root.hasAttribute("data-open") && getComputedStyle(root).display === "none" && document.activeElement?.id === "fx-drawer-open",
      open: root.hasAttribute("data-open"),
      focus: document.activeElement?.id || null,
    };
  });
  if (byEscape && byEscape.ok) ok("data-open: Escape on the panel closes the drawer through the dismiss stack and returns focus to the toggle");
  else bad(`data-open: Escape on the drawer panel left ${JSON.stringify(byEscape)}`);

  await drawerPage.click("#fx-drawer-open");
  await drawerSettled(() => ({ ok: document.getElementById("fx-drawer").hasAttribute("data-open") }));
  await drawerPage.click("#fx-drawer-close");
  const byClose = await drawerSettled(() => {
    const root = document.getElementById("fx-drawer");
    return {
      ok: !root.hasAttribute("data-open") && getComputedStyle(root).display === "none" && document.activeElement?.id === "fx-drawer-open",
      open: root.hasAttribute("data-open"),
      focus: document.activeElement?.id || null,
    };
  });
  if (byClose && byClose.ok) ok("data-drawer-toggle: the drawer's own close control shuts it and returns focus to the host toggle");
  else bad(`data-drawer-toggle: the close control left ${JSON.stringify(byClose)}`);

  // layer ordering: the drawer is closed, so its panel must not be the layer
  // Escape reaches — the layer the reader opened is.
  await drawerPage.evaluate(() => document.getElementById("open-a").click());
  await drawerPage.waitForTimeout(500);
  const layerBefore = await drawerPage.evaluate(() => ({
    layer: !!document.getElementById("layer-a"),
    open: document.getElementById("fx-drawer").hasAttribute("data-open"),
  }));
  await drawerPage.keyboard.press("Escape");
  await drawerPage.waitForTimeout(500);
  const layerAfter = await drawerPage.evaluate(() => ({
    layer: !!document.getElementById("layer-a"),
    open: document.getElementById("fx-drawer").hasAttribute("data-open"),
  }));
  if (layerBefore.layer && !layerBefore.open && !layerAfter.layer && !layerAfter.open) {
    ok("data-dismiss: with the drawer closed, Escape closes the open layer and leaves the drawer shut (the closed drawer never takes the key)");
  } else {
    bad(`data-dismiss: the closed-drawer Escape left ${JSON.stringify({ layerBefore, layerAfter })}`);
  }

  await drawerPage.setViewportSize({ width: 1200, height: 800 });
  await drawerPage.waitForTimeout(300);
  const railBefore = await drawerState();
  await drawerPage.click("#fx-drawer-open");
  await drawerPage.waitForTimeout(250);
  const railAfter = await drawerState();
  const railHeld = railBefore.open === false && railBefore.display !== "none" && railBefore.panel && !railBefore.scrim &&
    railAfter.open === false && railAfter.panel && railAfter.display === railBefore.display && !railAfter.scrim;
  if (railHeld) {
    ok(`drawer: at 1200px the drawer is the static rail (display ${railBefore.display}, no data-open, no scrim) and the toggle does not change its visibility`);
  } else {
    bad(`drawer: the 1200px rail was ${JSON.stringify({ railBefore, railAfter })}`);
  }

  if (drawerErrors.length === 0) ok("drawer: no uncaught page exceptions while driving the open state");
  else bad(`drawer: uncaught page exceptions while driving the open state: ${drawerErrors.join(" | ")}`);
  await drawerPage.close();
}

// ---------------------------------------------------------------------------
// 11. data-scrollspy — the section in view marks its own anchor.
// ---------------------------------------------------------------------------
{
  // the page scrolls smooth (the sheet's default), so a fixed wait samples
  // mid-animation: poll the marker to a deadline instead of reading one frame.
  await page.evaluate(() => document.getElementById("sec-c").scrollIntoView({ block: "start" }));
  const atC = await settled(() => ({
    ok: document.getElementById("spy-link-c").getAttribute("aria-current") === "true" &&
      document.getElementById("spy-link-a").getAttribute("aria-current") === null,
    cur: ["spy-link-a", "spy-link-b", "spy-link-c"].map((id) => document.getElementById(id).getAttribute("aria-current")),
    y: Math.round(window.scrollY),
    tops: ["sec-a", "sec-b", "sec-c"].map((id) => Math.round(document.getElementById(id).getBoundingClientRect().top)),
  }));
  await page.evaluate(() => document.getElementById("sec-a").scrollIntoView({ block: "start" }));
  const atA = await settled(() => {
    const cur = ["spy-link-a", "spy-link-b", "spy-link-c"].map((id) => document.getElementById(id).getAttribute("aria-current"));
    return { ok: cur[0] === "true" && cur[2] === null, cur, y: Math.round(window.scrollY) };
  });
  if (atC && atC.ok) ok("data-scrollspy: the section in view marks its anchor aria-current=true");
  else bad(`data-scrollspy: at section C the anchors were ${JSON.stringify(atC)}`);
  if (atA && atA.ok) ok("data-scrollspy: scrolling back moves the current marker (the old one is cleared)");
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

  // the second patch kind: a streamed-text delta on the feed's tail. nothing is
  // replaced, so the old bind-time memo could never see it; capture runs on
  // every patch kind and syncFollow applies the pass after the ops land.
  await page.evaluate(() => {
    const el = document.getElementById("feed");
    el.scrollTop = el.scrollHeight;
    el.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(150);
  await page.evaluate(() => document.getElementById("stream").click());
  await page.waitForTimeout(450);
  await page.evaluate(() => document.getElementById("stream").click());
  await page.waitForTimeout(450);
  const streamed = await page.evaluate(() => {
    const el = document.getElementById("feed");
    return {
      gap: el.scrollHeight - el.scrollTop - el.clientHeight,
      state: el.getAttribute("data-follow-state"),
      lines: (document.getElementById("feed-tail")?.textContent || "").split("\n").length,
    };
  });
  if (streamed.gap <= 24 && streamed.state === null && streamed.lines === 2) {
    ok(`data-follow: two streamed text deltas from the bottom stay pinned (gap ${streamed.gap}px, no data-follow-state, ${streamed.lines} lines)`);
  } else {
    bad(`data-follow: streamed deltas from the bottom produced ${JSON.stringify(streamed)}`);
  }

  await page.evaluate(() => {
    const el = document.getElementById("feed");
    el.scrollTop = 0;
    el.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(150);
  await page.evaluate(() => document.getElementById("stream").click());
  await page.waitForTimeout(450);
  const awayText = await page.evaluate(() => ({
    state: document.getElementById("feed").getAttribute("data-follow-state"),
    top: document.getElementById("feed").scrollTop,
  }));
  if (awayText.state === "away" && awayText.top <= 24) {
    ok(`data-follow-state: a streamed text delta while the reader is up does not yank it (top ${awayText.top}px, state "away")`);
  } else {
    bad(`data-follow-state: a streamed text delta while detached produced ${JSON.stringify(awayText)}`);
  }
}

// ---------------------------------------------------------------------------
// 17b. data-reading-keys — the keyboard drives the scroller, and a layer's
//      Escape wins before the reader's return to the live tail.
// ---------------------------------------------------------------------------
{
  await page.focus("#reader");
  const focused = await page.evaluate(() => document.activeElement?.id ?? null);
  await page.keyboard.press("End");
  await page.waitForTimeout(150);
  const atEnd = await page.evaluate(() => {
    const el = document.getElementById("reader");
    return { top: el.scrollTop, max: el.scrollHeight - el.clientHeight };
  });
  if (focused === "reader" && atEnd.max > 0 && atEnd.top >= atEnd.max - 2) {
    ok(`data-reading-keys: End scrolls the focused region to the bottom (${atEnd.top}/${atEnd.max})`);
  } else {
    bad(`data-reading-keys: focus ${JSON.stringify(focused)}, End left ${JSON.stringify(atEnd)}`);
  }

  await page.keyboard.press("Home");
  await page.waitForTimeout(150);
  const atHome = await page.evaluate(() => document.getElementById("reader").scrollTop);
  if (atHome === 0) ok("data-reading-keys: Home scrolls it back to the top");
  else bad(`data-reading-keys: Home left scrollTop ${atHome}`);

  await page.evaluate(() => { const el = document.getElementById("reader"); el.scrollTop = el.scrollHeight; });
  const fromEnd = await page.evaluate(() => document.getElementById("reader").scrollTop);
  await page.keyboard.press("PageUp");
  await page.waitForTimeout(150);
  const afterPageUp = await page.evaluate(() => document.getElementById("reader").scrollTop);
  await page.keyboard.press("ArrowUp");
  await page.waitForTimeout(150);
  const afterArrow = await page.evaluate(() => document.getElementById("reader").scrollTop);
  if (afterPageUp < fromEnd && afterArrow < afterPageUp) {
    ok(`data-reading-keys: PageUp and ArrowUp scroll the region up (${fromEnd} -> ${afterPageUp} -> ${afterArrow})`);
  } else {
    bad(`data-reading-keys: PageUp/ArrowUp produced ${fromEnd} -> ${afterPageUp} -> ${afterArrow}`);
  }

  // a layer's Escape is the reader's first intent: open layer A programmatically
  // so focus stays on the reader, then press Escape. the layer must close and
  // the reader must not move.
  await page.evaluate(() => document.getElementById("open-a").click());
  await page.waitForTimeout(500);
  await page.focus("#reader");
  const beforeLayer = await page.evaluate(() => {
    const el = document.getElementById("reader");
    el.scrollTop = 40;
    return { top: el.scrollTop, layer: !!document.getElementById("layer-a") };
  });
  await page.keyboard.press("Escape");
  await page.waitForTimeout(500);
  const afterLayer = await page.evaluate(() => ({
    top: document.getElementById("reader").scrollTop,
    layer: !!document.getElementById("layer-a"),
  }));
  if (beforeLayer.layer && !afterLayer.layer && afterLayer.top === beforeLayer.top) {
    ok("data-reading-keys: with a layer open, Escape closes the layer and does NOT move the reader");
  } else {
    bad(`data-reading-keys: layer Escape produced before ${JSON.stringify(beforeLayer)}, after ${JSON.stringify(afterLayer)}`);
  }

  // the fixture no longer renders a permanently-visible dismiss layer (the
  // combo panel is open-stateful now), so "a layer keeps the key" is the block
  // above: layer-a was open, focus was on the reader, and Escape closed the
  // layer without moving the reader. this pins the consequence of that pass:
  // the stack is empty, so the next Escape reaches the reader and returns it to
  // the live tail — the no-layer branch, on the main page, not only on `bare`.
  await page.keyboard.press("Escape");
  await page.waitForTimeout(300);
  const afterNoLayer = await page.evaluate(() => ({
    top: document.getElementById("reader").scrollTop,
    max: document.getElementById("reader").scrollHeight - document.getElementById("reader").clientHeight,
    live: Array.from(document.querySelectorAll("[data-dismiss]")).filter((el) => el.getClientRects().length > 0).length,
  }));
  if (afterNoLayer.live === 0 && afterNoLayer.max > 0 && afterNoLayer.top >= afterNoLayer.max - 2) {
    ok(`data-reading-keys: with no layer on screen, Escape returns the reader to the live tail (${afterNoLayer.top}/${afterNoLayer.max})`);
  } else {
    bad(`data-reading-keys: the no-layer Escape on the main page left ${JSON.stringify(afterNoLayer)}`);
  }

  const barePage = await context.newPage();
  await barePage.goto(BASE + "/behaviour?bare=reader", { waitUntil: "domcontentloaded" });
  await barePage.waitForTimeout(700);
  await barePage.focus("#reader");
  const bareBefore = await barePage.evaluate(() => {
    const el = document.getElementById("reader");
    el.scrollTop = 40;
    return {
      top: el.scrollTop,
      max: el.scrollHeight - el.clientHeight,
      layers: document.querySelectorAll("[data-dismiss]").length,
    };
  });
  await barePage.keyboard.press("Escape");
  await barePage.waitForTimeout(200);
  const bareAfter = await barePage.evaluate(() => {
    const el = document.getElementById("reader");
    return { top: el.scrollTop, max: el.scrollHeight - el.clientHeight };
  });
  if (bareBefore.layers === 0 && bareBefore.max > 0 && bareAfter.top >= bareAfter.max - 2) {
    ok(`data-reading-keys: with no layer open, Escape returns the reader to the live tail (${bareAfter.top}/${bareAfter.max})`);
  } else {
    bad(`data-reading-keys: the no-layer Escape left ${JSON.stringify({ before: bareBefore, after: bareAfter })}`);
  }
  await barePage.close();
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
// 18b. data-focus-return by opener id — a dialog opened from a button and
//      closed by a SERVER round trip (not Escape) returns focus to the opener.
//      focus is parked on a field inside the dialog first, so the restore is
//      the removal pass's work and not the still-present-element shortcut.
// ---------------------------------------------------------------------------
{
  await page.click("#fx-dialog-open");
  await page.waitForFunction(() => !!document.getElementById("fx-dialog"), null, { timeout: 4000 }).catch(() => {});
  const opened = await page.evaluate(() => ({
    dialog: !!document.getElementById("fx-dialog"),
    state: (document.getElementById("fx-dialog-state")?.textContent || "").trim(),
  }));
  if (opened.dialog && opened.state === "dialog: open") {
    ok("focus return by id: the opener's click round-tripped and the server rendered the dialog region");
  } else {
    bad(`focus return by id: after the open click ${JSON.stringify(opened)}`);
  }

  await page.focus("#fx-dialog-field");
  const parked = await page.evaluate(() => document.activeElement?.id ?? null);
  await page.evaluate(() => document.getElementById("fx-dialog-close").click());
  await page.waitForFunction(() => !document.getElementById("fx-dialog"), null, { timeout: 4000 }).catch(() => {});
  await page.waitForTimeout(80);
  const closed = await page.evaluate(() => ({
    dialog: !!document.getElementById("fx-dialog"),
    state: (document.getElementById("fx-dialog-state")?.textContent || "").trim(),
    focus: document.activeElement?.id ?? null,
  }));
  if (parked === "fx-dialog-field" && !closed.dialog && closed.state === "dialog: closed" && closed.focus === "fx-dialog-open") {
    ok("focus return by id: the server's patch removed the dialog and focus came back to the opener (#fx-dialog-open)");
  } else {
    bad(`focus return by id: parked ${JSON.stringify(parked)}, after the close ${JSON.stringify(closed)}`);
  }
}

// ---------------------------------------------------------------------------
// 18c. T26 — a focused button whose own click replaces the region holding it
//      keeps focus by id (the button records `focus:<id>`, not form state).
// ---------------------------------------------------------------------------
{
  const before = await page.evaluate(() => ({
    text: (document.getElementById("fx-t26")?.textContent || "").trim(),
    focus: document.activeElement?.id ?? null,
  }));
  await page.click("#fx-t26");
  await page.waitForFunction(() => (document.getElementById("t26-out")?.textContent || "").trim() === "t26: 1", null, { timeout: 4000 }).catch(() => {});
  await page.waitForTimeout(80);
  const after = await page.evaluate(() => ({
    text: (document.getElementById("fx-t26")?.textContent || "").trim(),
    out: (document.getElementById("t26-out")?.textContent || "").trim(),
    focus: document.activeElement?.id ?? null,
  }));
  if (before.text === "Replace me (render 0)" && after.out === "t26: 1" && after.focus === "fx-t26") {
    ok("T26: a focused button replaced by its own region patch keeps focus by id (#fx-t26)");
  } else {
    bad(`T26: before ${JSON.stringify(before)}, after ${JSON.stringify(after)}`);
  }
}

// ---------------------------------------------------------------------------
// 18d. an EMPTY-FRAGMENT close — the patch targets the dialog itself, so the
//      frame carries no changed node; the removal pass must still run.
// ---------------------------------------------------------------------------
{
  await page.click("#fx-dialog2-open");
  await page.waitForFunction(() => !!document.getElementById("fx-dialog2"), null, { timeout: 4000 }).catch(() => {});
  const opened = await page.evaluate(() => !!document.getElementById("fx-dialog2"));
  await page.focus("#fx-dialog2-field");
  const parked = await page.evaluate(() => document.activeElement?.id ?? null);
  await page.evaluate(() => document.getElementById("fx-dialog2-close").click());
  await page.waitForFunction(() => !document.getElementById("fx-dialog2"), null, { timeout: 4000 }).catch(() => {});
  await page.waitForTimeout(80);
  const after = await page.evaluate(() => ({
    dialog: !!document.getElementById("fx-dialog2"),
    focus: document.activeElement?.id ?? null,
  }));
  if (opened && parked === "fx-dialog2-field" && !after.dialog && after.focus === "fx-dialog2-open") {
    ok("focus return by id: a dialog removed by an EMPTY fragment still returns focus to the opener");
  } else {
    bad(`focus return by empty fragment: opened ${opened}, parked ${JSON.stringify(parked)}, after ${JSON.stringify(after)}`);
  }
}

// ---------------------------------------------------------------------------
// 18e. focus the reader moved while the round trip was in flight is not stolen
//      by the removal pass.
// ---------------------------------------------------------------------------
{
  await page.click("#fx-dialog-open");
  await page.waitForFunction(() => !!document.getElementById("fx-dialog"), null, { timeout: 4000 }).catch(() => {});
  await page.focus("#fx-dialog-close");
  await page.evaluate(() => {
    document.getElementById("fx-dialog-close").click();
    document.getElementById("reader").focus();
  });
  await page.waitForFunction(() => !document.getElementById("fx-dialog"), null, { timeout: 4000 }).catch(() => {});
  await page.waitForTimeout(80);
  const focus = await page.evaluate(() => document.activeElement?.id ?? null);
  if (focus === "reader") ok("focus return by id: focus moved before the patch lands is not stolen");
  else bad(`focus theft: activeElement after the patch was ${JSON.stringify(focus)} (expected reader)`);
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
// 21c. data-draft-value — a server seed, and the identity precedence rule:
//      a changed identity writes the seed (not the typed value, not the old
//      store); the same identity re-rendered keeps the reader's keystrokes.
// ---------------------------------------------------------------------------
{
  const draftValue = () => page.evaluate(() => document.getElementById("fx-seed")?.value ?? null);
  const stored = (key) => page.evaluate((k) => {
    try { return sessionStorage.getItem("webui-draft:" + k); } catch { return null; }
  }, key);
  const settled = async (expected, timeout = 4000) => {
    const deadline = Date.now() + timeout;
    for (;;) {
      if ((await draftValue()) === expected) return true;
      if (Date.now() > deadline) return false;
      await page.waitForTimeout(50);
    }
  };

  const start = await page.evaluate(() => {
    const el = document.getElementById("fx-seed");
    return {
      value: el?.value ?? null,
      identity: el?.getAttribute("data-draft-id") ?? null,
      seed: el?.getAttribute("data-draft-value") ?? null,
    };
  });
  if (start.value === "server-a" && start.identity === "a" && start.seed === "server-a") {
    ok("data-draft-value: the control carries an identity and a seed, and starts at the server's text");
  } else {
    bad(`data-draft-value: the fixture field read ${JSON.stringify(start)}`);
  }

  await page.fill("#fx-seed", "typed-a");
  await page.waitForTimeout(120);
  const storedA = await stored("a");
  if (storedA === "typed-a") ok("data-draft-id: typing under identity a persists under webui-draft:a");
  else bad(`data-draft-id: webui-draft:a held ${JSON.stringify(storedA)} after typing`);

  await page.click("#fx-seed-switch");
  const switched = await settled("server-b");
  const afterSwitch = await page.evaluate(() => {
    const el = document.getElementById("fx-seed");
    return { value: el?.value ?? null, identity: el?.getAttribute("data-draft-id") ?? null };
  });
  if (switched && afterSwitch.identity === "b") {
    ok('data-draft-value: an identity change writes the server\'s seed ("server-b"), not the typed value');
  } else {
    bad(`data-draft-value: after the switch to identity b the field read ${JSON.stringify(afterSwitch)} (deadline ${switched})`);
  }
  if (afterSwitch.value !== "typed-a") ok("data-draft-value: the old identity's typed text did not leak into the new identity");
  else bad("data-draft-value: the old identity's typed value survived the identity change");
  const storedB = await stored("b");
  if (storedB === "server-b") ok("data-draft-value: the seed is persisted under the new identity's key");
  else bad(`data-draft-value: webui-draft:b held ${JSON.stringify(storedB)} after the switch`);

  await page.fill("#fx-seed", "typed-b");
  await page.waitForTimeout(120);
  await page.click("#fx-seed-repatch");
  const repatched = await settled("typed-b");
  const afterRepatch = await page.evaluate(() => ({
    value: document.getElementById("fx-seed")?.value ?? null,
    identity: document.getElementById("fx-seed")?.getAttribute("data-draft-id") ?? null,
    state: (document.getElementById("fx-seed-state")?.textContent || "").trim(),
  }));
  if (repatched && afterRepatch.identity === "b" && /identity: b/.test(afterRepatch.state)) {
    ok("data-draft-value: the same identity re-rendered keeps the reader's keystrokes (typed-b survived the patch)");
  } else {
    bad(`data-draft-value: after the same-identity re-patch the field read ${JSON.stringify(afterRepatch)} (deadline ${repatched})`);
  }

  await page.click("#fx-seed-switch");
  const switchedBack = await settled("server-a");
  const storedBackA = await stored("a");
  if (switchedBack && storedBackA === "server-a") {
    ok("data-draft-value: switching back is another identity change — the seed wins over the stale store and rewrites it");
  } else {
    bad(`data-draft-value: switching back read ${JSON.stringify(await draftValue())}, webui-draft:a held ${JSON.stringify(storedBackA)} (deadline ${switchedBack})`);
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

// ---------------------------------------------------------------------------
// 25. the residue proof page: every §20 row, zero consumer JavaScript.
// ---------------------------------------------------------------------------
{
  const residueHTML = await (await fetch(BASE + "/residue")).text();
  const scriptTags = [...residueHTML.matchAll(/<script\b[^>]*>/g)].map((m) => m[0]);
  const foreign = scriptTags.filter((s) => !/src="\/ui\//.test(s) && !/nonce=/.test(s));
  const wiredInPage = /addEventListener\s*\(/.test(residueHTML);
  if (foreign.length === 0 && !wiredInPage) {
    ok(`residue page carries no consumer script (${scriptTags.length} script tag(s): engine/shell + the nonce'd prelude only)`);
  } else {
    bad(`residue page carries consumer script: foreign=${JSON.stringify(foreign)} wiredInPage=${wiredInPage}`);
  }

  const residue = await browser.newContext({
    viewport: { width: 1200, height: 800 },
    permissions: ["clipboard-read", "clipboard-write"],
  });
  const rp = await residue.newPage();
  const residueErrors = [];
  rp.on("pageerror", (e) => residueErrors.push(String(e)));
  await rp.goto(BASE + "/residue", { waitUntil: "domcontentloaded" });
  await rp.waitForTimeout(700);

  // outline: a server-rendered anchor scrolls and flashes.
  await rp.click('#res-outline a[data-scroll-to="res-sec-2"]');
  const flashed = await rp.evaluate(() => document.getElementById("res-sec-2")?.hasAttribute("data-scroll-flash") === true);
  await rp.waitForTimeout(600);
  const jumped = await rp.evaluate(() => Math.abs(document.getElementById("res-sec-2").getBoundingClientRect().top) < 220);
  if (jumped && flashed) ok("residue/outline: the anchor scrolled the section into view and flashed it");
  else bad(`residue/outline: jumped=${jumped} flashed=${flashed}`);

  // rename: inline edit + native submit + .refresh.
  await rp.fill("#res-name-input", "renamed plan");
  await rp.click("#res-rename-save");
  await rp.waitForFunction(() => (document.getElementById("res-rename-value")?.textContent || "").includes("renamed plan"), null, { timeout: 4000 }).catch(() => {});
  const namePatched = await rp.evaluate(() => (document.getElementById("res-rename-value")?.textContent || "").includes("renamed plan"));
  if (namePatched) ok("residue/rename: the inline edit saved and .refresh patched the region with the new name");
  else bad("residue/rename: the refreshed region did not carry the new name");

  // card rename: the same shape on a second region.
  await rp.fill("#res-card-input", "ship it now");
  await rp.click("#res-card-save");
  await rp.waitForFunction(() => (document.getElementById("res-card-value")?.textContent || "").includes("ship it now"), null, { timeout: 4000 }).catch(() => {});
  const cardPatched = await rp.evaluate(() => (document.getElementById("res-card-value")?.textContent || "").includes("ship it now"));
  if (cardPatched) ok("residue/card: the card rename round-tripped through .refresh");
  else bad("residue/card: the card region did not carry the new title");

  // session menus: two layers, Escape closes the topmost (LIFO).
  await rp.click("#res-open-a");
  await rp.waitForTimeout(250);
  await rp.click("#res-open-b");
  await rp.waitForTimeout(250);
  await rp.keyboard.press("Escape");
  await rp.waitForTimeout(300);
  const afterFirst = await rp.evaluate(() => ({
    a: !!document.getElementById("res-menu-a"),
    b: !!document.getElementById("res-menu-b"),
  }));
  await rp.keyboard.press("Escape");
  await rp.waitForTimeout(300);
  const afterSecond = await rp.evaluate(() => ({ a: !!document.getElementById("res-menu-a") }));
  if (afterFirst.a && !afterFirst.b && !afterSecond.a) {
    ok("residue/menus: Escape closed the topmost layer first, then the next (LIFO)");
  } else {
    bad(`residue/menus: after first ${JSON.stringify(afterFirst)}, after second ${JSON.stringify(afterSecond)}`);
  }

  // disclosures: native details toggle, and open state survives a refresh.
  await rp.click("#res-chip > summary");
  await rp.waitForTimeout(150);
  const chipOpen = await rp.evaluate(() => document.getElementById("res-chip").open === true);
  await rp.fill("#res-name-input", "renamed again");
  await rp.click("#res-rename-save");
  await rp.waitForTimeout(700);
  const chipAfterPatch = await rp.evaluate(() => document.getElementById("res-chip").open === true);
  await rp.click("#res-group > summary");
  await rp.click("#res-skills > summary");
  await rp.waitForTimeout(150);
  const othersOpen = await rp.evaluate(() => document.getElementById("res-group").open === true && document.getElementById("res-skills").open === true);
  if (chipOpen && chipAfterPatch && othersOpen) {
    ok("residue/disclosure: the chip, session group and skill category toggle, and an open disclosure survives a refresh patch");
  } else {
    bad(`residue/disclosure: chipOpen=${chipOpen} afterPatch=${chipAfterPatch} others=${othersOpen}`);
  }

  // copy halves: data-copy writes the clipboard and the engine shows its toast.
  await rp.click("#res-copy-btn");
  await rp.waitForTimeout(400);
  const copied = await rp.evaluate(() => navigator.clipboard.readText().catch(() => ""));
  const toast = await rp.evaluate(() => (document.querySelector("[data-webui-toast]")?.textContent || "").trim());
  if (copied === "echo hello" && /Copied/i.test(toast)) {
    ok("residue/copy: data-copy wrote the clipboard and the engine's toast reported it");
  } else {
    bad(`residue/copy: clipboard=${JSON.stringify(copied)} toast=${JSON.stringify(toast)}`);
  }

  if (residueErrors.length === 0) ok("residue: no uncaught page errors while driving every row");
  else bad(`residue page errors: ${JSON.stringify(residueErrors)}`);
  await residue.close();
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
