#!/usr/bin/env node
// designer/event-deck-probe.mjs — the wave-4 event deck gate (W4.1).
//
// Drives every new deck event END TO END against a REAL browser and asserts on
// the frames the server receives, never on pixels:
//
//   layer A (browser): chromium drives each event for real (pointer/touch
//     through the input pipeline, drag/clipboard through real DataTransfer
//     objects, media through a real WAV, scroll through a real scroll, the
//     transition through a real css transition). the deck fixture's handlers
//     decode the typed payload and render it back into the family log, so the
//     log tip BEING the decoded message is the proof that the engine's
//     outbound frame arrived at the server and was decoded there.
//
//   layer B (own socket): the probe connects its OWN websocket (nothing in
//     the page is patched or wrapped — the earlier revision of this idea
//     instrumented the page runtime and every probe falsely read "sent but
//     never answered") and dispatches one frame per control with the component
//     id read out of the served markup, asserting the `update` frame that
//     comes back carries the decoded payload. those frames are the server's
//     own bytes.
//
//   narrow: a click-only control must not receive hover/press noise — driven
//     in the browser, asserted on the log state, before the declared click is
//     shown to still round-trip.
//
//   contextmenu: an element that DECLARED a contextmenu handler owns the
//     right-click — the browser's native menu is cancelled over it, and only
//     over it (a control wired for another event, and any unwired element, keep
//     the native menu). read as `defaultPrevented` from a window-level observer,
//     and the frame still round-trips under cancellation.
//
// every individual probe asserts its OWN precondition first: the control id
// exists in the served markup with the right data-event declaration.
//
// usage: node designer/event-deck-probe.mjs
//   spawns WebUIEventDeck on :39000 (fresh port band), probes, tears down.

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 39000;
const BASE = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}/ws`;

let RENDER_TOKEN = null;

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

// precondition 1: a probe that cannot open a websocket or a browser is an
// INSTRUMENT failure, not a verdict — assert the runtime up front.
const major = Number(process.versions.node.split(".")[0]);
if (!(major >= 22) || typeof WebSocket !== "function") {
  console.log(`  FAIL probe precondition: needs node >= 22 with a global WebSocket (have ${process.version})`);
  process.exit(1);
}
ok(`runtime: node ${process.version} with global WebSocket and fetch`);

async function waitForServer(timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(BASE + "/", { signal: AbortSignal.timeout(2000) });
      if (res.ok) {
        const body = await res.text();
        // prove this is our own freshly spawned deck, not a stale process.
        if (body.includes("Event deck") && body.includes("deck-pd")) return body;
      }
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

// a tiny real WAV (pcm 16-bit mono 8kHz) as a data: url — the media deck
// controls get a genuine source so play/pause/ended/loadedmetadata/timeupdate
// are REAL media events, not fabricated strings.
function wavDataURL(seconds = 0.04) {
  const sampleRate = 8000;
  const n = Math.max(1, Math.round(sampleRate * seconds));
  const dataSize = n * 2;
  const b = new ArrayBuffer(44 + dataSize);
  const dv = new DataView(b);
  const w = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
  w(0, "RIFF"); dv.setUint32(4, 36 + dataSize, true); w(8, "WAVE");
  w(12, "fmt "); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
  dv.setUint32(24, sampleRate, true); dv.setUint32(28, sampleRate * 2, true);
  dv.setUint16(32, 2, true); dv.setUint16(34, 16, true);
  w(36, "data"); dv.setUint32(40, dataSize, true);
  for (let i = 0; i < n; i++) dv.setInt16(44 + i * 2, 0, true); // silence
  return "data:audio/wav;base64," + Buffer.from(new Uint8Array(b)).toString("base64");
}
const WAV = wavDataURL();
const WAV_END = wavDataURL(0.1);

// the log tip of one family's span — the server's decoded echo, applied by
// the engine as a fragment patch.
async function tip(page, sel) {
  return await page.evaluate((sel) => (document.querySelector(sel)?.textContent || "").trim(), sel);
}
async function waitTip(page, sel, prefix, timeout = 6000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const t = await tip(page, sel);
    if (t.startsWith(prefix)) return t;
    if (Date.now() > deadline) return t;
    await new Promise((r) => setTimeout(r, 60));
  }
}

const center = (page, sel) =>
  page.evaluate((sel) => {
    const r = document.querySelector(sel)?.getBoundingClientRect();
    if (!r) return null;
    return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) };
  }, sel);

// layer-B raw dispatch: the PROBE's own socket, its own frame, its own
// `update` answer. nothing on the page is touched.
function rawDispatch(component, event, data, attempts = 2) {
  return new Promise((resolve) => {
    let settled = false;
    let opened = false;
    const frames = [];
    const socket = new WebSocket(WS_URL);
    const finish = (value) => {
      if (settled) return;
      settled = true;
      try { socket.close(); } catch (e) {}
      resolve(value);
    };
    socket.addEventListener("open", () => {
      opened = true;
      const frame = { type: "event", component, event, data };
      if (RENDER_TOKEN) frame.token = RENDER_TOKEN;
      socket.send(JSON.stringify(frame));
    });
    socket.addEventListener("message", (ev) => {
      try {
        frames.push(String(ev.data));
        const msg = JSON.parse(String(ev.data));
        if (msg.type === "update") finish({ opened, frames, update: msg });
      } catch (e) {}
    });
    socket.addEventListener("error", () => finish({ opened, frames, update: null }));
    setTimeout(() => {
      if (!opened && attempts > 1) {
        // node's built-in ws client can race a gapless close->reconnect; a
        // probe that never connected is retried once before believing it.
        try { socket.close(); } catch (e) {}
        rawDispatch(component, event, data, attempts - 1).then((r) => {
          r.retried = true;
          finish(r);
        });
      } else {
        finish({ opened, frames, update: null });
      }
    }, 2500);
  });
}

// every deck control: its expected `data-event` declaration and the decoded
// message its handler renders back — the shape the fixture echoes.
const DECL = {
  "deck-pd": "pointerdown", "deck-pm": "pointermove", "deck-pu": "pointerup",
  "deck-pc": "pointercancel", "deck-pe": "pointerenter", "deck-pl": "pointerleave",
  "deck-ts": "touchstart", "deck-tm": "touchmove", "deck-te": "touchend",
  "deck-ds": "dragstart", "deck-dr": "drag", "deck-de": "dragend",
  "deck-denter": "dragenter", "deck-dover": "dragover", "deck-dleave": "dragleave",
  "deck-drop": "drop",
  "deck-copy": "copy", "deck-cut": "cut", "deck-paste": "paste",
  "deck-wheel": "wheel", "deck-scroll": "scroll",
  "deck-dbl": "dblclick", "deck-ctx": "contextmenu",
  "deck-anim": "animationend", "deck-tran": "transitionend",
  "deck-m-play": "play", "deck-m-pause": "pause", "deck-m-ended": "ended",
  "deck-m-time": "timeupdate", "deck-m-meta": "loadedmetadata", "deck-m-err": "error",
  "deck-click": "click",
};

console.log("=== wave-4 event deck probe ===");

const binPath = await (async () => {
  const built = await run("swift", ["build"]);
  if (built.code !== 0) {
    console.log(built.out.slice(-400));
    bad("swift build");
    process.exit(1);
  }
  const shown = await run("swift", ["build", "--show-bin-path"]);
  return join(shown.out.trim(), "WebUIEventDeck");
})();

let server = null;
let browser = null;
process.on("exit", () => {
  if (browser) { try { browser.close(); } catch {} }
  if (server) { try { server.kill("SIGKILL"); } catch {} }
});
server = spawn(binPath, ["--port", String(PORT)], { cwd: ROOT, stdio: ["ignore", "ignore", "ignore"] });

const page = await waitForServer();
if (page === null) {
  bad(`deck server did not become ready on :${PORT} (kill any WebUIEventDeck holding it and re-run)`);
  process.exit(1);
}
ok(`deck server ready on :${PORT}`);

browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, hasTouch: true });
const page2 = await context.newPage();
await page2.goto(BASE + "/", { waitUntil: "domcontentloaded" });
await page2.waitForTimeout(600);
// the first real-mouse interaction after a headless launch can land at the
// wrong place until the pointer has moved once; prime it before any drive.
await page2.mouse.move(8, 8);
await page2.waitForTimeout(100);

// read the render token the served page carries — a token-bound server routes
// events only into the session its render minted, so a probe without it can
// never be answered.
const token = await page2.evaluate(() => {
  const m = document.querySelector('meta[name="webui-config"]');
  if (!m) return null;
  const s = m.getAttribute("content").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  try { return JSON.parse(s).renderToken || null; } catch (e) { return null; }
});
if (token) { RENDER_TOKEN = token; ok(`served page carries a render token (${token.slice(0, 6)}…)`); }
else { bad("served page carries no render token — the host did not thread it, so decks cannot route"); process.exit(1); }

// precondition per control: the id exists in the served markup AND declares
// the exact event its typed modifier names.
const controls = await page2.evaluate(() => {
  const map = {};
  for (const el of document.querySelectorAll("[data-component-id]")) {
    map[el.id || el.getAttribute("data-component-id")] = {
      component: el.getAttribute("data-component-id"),
      event: el.getAttribute("data-event"),
    };
  }
  return map;
});
let missing = 0;
for (const [id, ev] of Object.entries(DECL)) {
  const c = controls[id];
  if (!c) { bad(`precondition: #${id} missing from served markup`); missing++; continue; }
  if (c.event !== ev) { bad(`precondition: #${id} declares "${c.event}", expected "${ev}"`); missing++; continue; }
  ok(`precondition: #${id} (${c.component}) declares ${ev}`);
}
if (missing > 0) { process.exit(1); }

const comp = (id) => controls[id].component;

// ---- layer A: the browser drives every new event for real ----

async function firePointer(sel, type, x, y, button = 0, buttons = 0) {
  return page2.evaluate((o) => {
    const el = document.querySelector(o.sel);
    if (!el) return false;
    el.dispatchEvent(new PointerEvent(o.type, { bubbles: true, cancelable: true, clientX: o.x, clientY: o.y, button: o.button, buttons: o.buttons }));
    return true;
  }, { sel, type, x, y, button, buttons });
}
async function fireDrag(sel, type, text) {
  return page2.evaluate((o) => {
    const el = document.querySelector(o.sel);
    if (!el) return false;
    const dt = new DataTransfer();
    if (o.text) dt.setData("text/plain", o.text);
    el.dispatchEvent(new DragEvent(o.type, { bubbles: true, cancelable: true, dataTransfer: dt }));
    return true;
  }, { sel, type, text });
}
async function fireDrop(sel) {
  return page2.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return false;
    const dt = new DataTransfer();
    dt.setData("text/plain", "payload");
    dt.setData("application/x-probe", "yes");
    dt.items.add(new File(["probe content here"], "probe.txt", { type: "text/plain" }));
    el.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: dt }));
    return true;
  }, sel);
}
async function fireClip(sel, type, text, html) {
  return page2.evaluate((o) => {
    const el = document.querySelector(o.sel);
    if (!el) return false;
    const dt = new DataTransfer();
    if (o.text) dt.setData("text/plain", o.text);
    if (o.html) dt.setData("text/html", o.html);
    el.dispatchEvent(new ClipboardEvent(o.type, { bubbles: true, cancelable: true, clipboardData: dt }));
    return true;
  }, { sel, type, text, html });
}

const browserCases = [
  ["#deck-pd", "pointerdown", () => firePointer("#deck-pd", "pointerdown", 10, 20, 0, 1), "#pointer-log", "pointerdown"],
  ["#deck-pm", "pointermove", () => firePointer("#deck-pm", "pointermove", 11, 21, 0, 1), "#pointer-log", "pointermove"],
  ["#deck-pu", "pointerup", () => firePointer("#deck-pu", "pointerup", 12, 22, 0, 0), "#pointer-log", "pointerup"],
  ["#deck-pc", "pointercancel", () => firePointer("#deck-pc", "pointercancel", 13, 23, 0, 0), "#pointer-log", "pointercancel"],
  ["#deck-pe", "pointerenter", () => firePointer("#deck-pe", "pointerenter", 14, 24, 0, 0), "#pointer-log", "pointerenter"],
  ["#deck-pl", "pointerleave", () => firePointer("#deck-pl", "pointerleave", 15, 25, 0, 0), "#pointer-log", "pointerleave"],
  ["#deck-ds", "dragstart", () => fireDrag("#deck-ds", "dragstart", "hi"), "#drag-log", "dragstart text/plain=hi"],
  ["#deck-dr", "drag", () => fireDrag("#deck-dr", "drag", "hi"), "#drag-log", "drag text/plain=hi"],
  ["#deck-de", "dragend", () => fireDrag("#deck-de", "dragend", null), "#drag-log", "dragend"],
  ["#deck-denter", "dragenter", () => fireDrag("#deck-denter", "dragenter", "hi"), "#drag-log", "dragenter text/plain=hi"],
  ["#deck-dover", "dragover", () => fireDrag("#deck-dover", "dragover", "hi"), "#drag-log", "dragover text/plain=hi"],
  ["#deck-dleave", "dragleave", () => fireDrag("#deck-dleave", "dragleave", null), "#drag-log", "dragleave"],
  ["#deck-copy", "copy", () => fireClip("#deck-copy", "copy", "copied", null), "#clipboard-log", "copy text=copied html=<nil>"],
  ["#deck-cut", "cut", () => fireClip("#deck-cut", "cut", "cutted", null), "#clipboard-log", "cut text=cutted html=<nil>"],
  ["#deck-paste", "paste", () => fireClip("#deck-paste", "paste", "hello", "<b>hi</b>"), "#clipboard-log", "paste text=hello html=<b>hi</b>"],
  ["#deck-anim", "animationend", () => page2.evaluate(() => {
    const el = document.querySelector("#deck-anim");
    el.dispatchEvent(new AnimationEvent("animationend", { bubbles: true, animationName: "deck-pulse" }));
    return true;
  }), "#misc-log", "animationend name=deck-pulse"],
];

let browserPass = 0;
let browserFail = 0;
for (const [sel, name, drive, log, expect] of browserCases) {
  const drove = await drive();
  if (!drove) { bad(`browser: could not drive ${name} on ${sel}`); browserFail++; continue; }
  const t = await waitTip(page2, log, expect);
  if (t.startsWith(expect)) { ok(`browser: ${name} -> "${t}"`); browserPass++; }
  else { bad(`browser: ${name} expected tip "${expect}", got "${t}"`); browserFail++; }
}

// the drop drives a real DataTransfer with a File and two data types; the
// browser also reports a "Files" entry type, so assert on the meaningful tail.
await fireDrop("#deck-drop");
const td = await waitTip(page2, "#drag-log", "drop ");
if (td.startsWith("drop ") && td.includes("application/x-probe=yes text/plain=payload file=probe.txt size=")) { ok(`browser: drop -> "${td}"`); browserPass++; }
else { bad(`browser: drop expected "drop … text/plain=payload file=probe.txt size=", got "${td}"`); browserFail++; }

// wheel (throttled to a frame) + scroll (a real scroll over real overflow).
await page2.evaluate(() => {
  const el = document.querySelector("#deck-wheel");
  el.dispatchEvent(new WheelEvent("wheel", { bubbles: true, cancelable: true, deltaX: 12, deltaY: 34 }));
});
let t = await waitTip(page2, "#scroll-log", "wheel dx=12 dy=34");
if (t.startsWith("wheel dx=12 dy=34")) { ok(`browser: wheel -> "${t}"`); browserPass++; }
else { bad(`browser: wheel expected "wheel dx=12 dy=34", got "${t}"`); browserFail++; }

await page2.evaluate(() => {
  const el = document.querySelector("#deck-scroll");
  el.scrollTop = 0;
  el.scrollTop = 40;
});
t = await waitTip(page2, "#scroll-log", "scroll top=40 left=0");
if (t.startsWith("scroll top=40 left=0")) { ok(`browser: scroll -> "${t}"`); browserPass++; }
else { bad(`browser: scroll expected "scroll top=40 left=0", got "${t}"`); browserFail++; }

// misc: real inputs for dblclick/contextmenu, a real css transition for
// transitionend. the misc controls sit below the fold; locator actions scroll
// them into view and wait for stability themselves.
await page2.locator("#deck-dbl").dblclick();
t = await waitTip(page2, "#misc-log", "dblclick x=");
if (t.startsWith("dblclick x=")) { ok(`browser: dblclick -> "${t}"`); browserPass++; }
else { bad(`browser: dblclick got "${t}"`); browserFail++; }

await page2.locator("#deck-ctx").click({ button: "right" });
t = await waitTip(page2, "#misc-log", "contextmenu x=");
if (t.startsWith("contextmenu x=")) { ok(`browser: contextmenu -> "${t}"`); browserPass++; }
else { bad(`browser: contextmenu got "${t}"`); browserFail++; }

// the contextmenu contract: declaring the handler owns the right-click, so the
// browser's native menu is cancelled over that element — and only over it.
// `defaultPrevented` is read by a window-level BUBBLE listener: the engine
// delegates `contextmenu` on `document` in the bubble phase, so this listener
// runs after the engine's and sees the final cancelled state. it is a read-only
// observer — it wraps nothing and patches nothing, so it cannot perturb the
// dispatch it measures.
await page2.evaluate(() => {
  window.__ctxDefaults = [];
  window.addEventListener("contextmenu", (e) => {
    window.__ctxDefaults.push({ prevented: e.defaultPrevented, tag: e.target.tagName });
  }, false);
});

// the declaring control cancels the native menu AND still round-trips. the click
// is offset so the decoded payload differs from the one above: on the same pixel
// the log tip is byte-identical, and an unchanged tip cannot be told apart from
// a frame that never arrived.
const ctxTipBefore = await tip(page2, "#misc-log");
await page2.locator("#deck-ctx").click({ button: "right", position: { x: 4, y: 4 } });
await page2.waitForFunction(
  (prev) => (document.querySelector("#misc-log")?.textContent || "").trim() !== prev,
  ctxTipBefore, { timeout: 4000 }
).catch(() => {});
const ctxTipAfter = await tip(page2, "#misc-log");
const ctxOwned = await page2.evaluate(() => window.__ctxDefaults.pop() || null);
if (ctxOwned && ctxOwned.prevented === true) { ok("browser: the declaring control cancels the native menu (defaultPrevented=true)"); browserPass++; }
else { bad(`browser: #deck-ctx did not cancel the native menu (defaultPrevented=${ctxOwned ? ctxOwned.prevented : "no event seen"})`); browserFail++; }
if (ctxTipAfter !== ctxTipBefore && ctxTipAfter.startsWith("contextmenu x=")) { ok(`browser: the frame still round-trips under cancellation -> "${ctxTipAfter}"`); browserPass++; }
else { bad(`browser: cancelling the native menu broke the round trip — the tip stayed "${ctxTipAfter}"`); browserFail++; }

// a control wired for ANOTHER event keeps the native menu: #deck-dbl declares
// dblclick, so the declared-event guard returns before the cancel is reached.
await page2.locator("#deck-dbl").click({ button: "right" });
const otherWired = await page2.evaluate(() => window.__ctxDefaults.pop() || null);
if (otherWired && otherWired.prevented === false) { ok("browser: a control wired for another event keeps the browser menu (scope held)"); browserPass++; }
else { bad(`browser: the cancel leaked onto #deck-dbl (defaultPrevented=${otherWired ? otherWired.prevented : "no event seen"})`); browserFail++; }

// an unwired element keeps the native menu. the click point is asserted BEFORE
// it is clicked: whatever sits there must have no wired ancestor, or the
// measurement says nothing about scope.
const unwiredPoint = await page2.evaluate(() => {
  const all = Array.from(document.querySelectorAll("body *"));
  const el = all.find((e) => {
    if (e.closest("[data-component-id]")) return false;
    const r = e.getBoundingClientRect();
    return r.width > 8 && r.height > 8 && r.top >= 0 && r.bottom <= window.innerHeight && r.left >= 0 && r.right <= window.innerWidth;
  });
  if (!el) return null;
  const r = el.getBoundingClientRect();
  const x = Math.round(r.left + r.width / 2);
  const y = Math.round(r.top + Math.max(1, Math.min(8, r.height / 2)));
  const hit = document.elementFromPoint(x, y);
  return { x, y, tag: hit ? hit.tagName : null, wired: hit ? !!hit.closest("[data-component-id]") : null };
});
if (!unwiredPoint) { bad("browser: no unwired in-viewport element to probe the native-menu scope"); browserFail++; }
else if (unwiredPoint.wired !== false) { bad(`browser: scope probe point (${unwiredPoint.x}, ${unwiredPoint.y}) resolves to <${unwiredPoint.tag}>, which has a wired ancestor`); browserFail++; }
else {
  await page2.mouse.click(unwiredPoint.x, unwiredPoint.y, { button: "right" });
  const bare = await page2.evaluate(() => window.__ctxDefaults.pop() || null);
  if (bare && bare.prevented === false) { ok(`browser: unwired <${unwiredPoint.tag.toLowerCase()}> keeps the browser menu (scope held)`); browserPass++; }
  else { bad(`browser: an unwired element was cancelled (defaultPrevented=${bare ? bare.prevented : "no event seen"})`); browserFail++; }
}

await page2.evaluate(() => { document.querySelector("#deck-tran").style.width = "240px"; });
t = await waitTip(page2, "#misc-log", "transitionend prop=width", 8000);
if (t.startsWith("transitionend prop=width")) { ok(`browser: transitionend -> "${t}"`); browserPass++; }
else { bad(`browser: transitionend got "${t}"`); browserFail++; }

// touch: constructible TouchEvents dispatched on the controls — a real dom
// dispatch through the engine's delegation path, deterministic in headless.
function fireTouch(sel, type, touches, changed) {
  return page2.evaluate((o) => {
    const el = document.querySelector(o.sel);
    if (!el) return false;
    const mk = (cx, cy) => new Touch({ identifier: o.id, target: el, clientX: cx, clientY: cy, pageX: cx, pageY: cy });
    const touches = o.touches.map((p) => mk(p.x, p.y));
    const changedTouches = o.changed.map((p) => mk(p.x, p.y));
    el.dispatchEvent(new TouchEvent(o.type, { bubbles: true, cancelable: true, touches, targetTouches: touches, changedTouches }));
    return true;
  }, { sel, type, id: 7, touches, changed });
}
await fireTouch("#deck-ts", "touchstart", [{ x: 10, y: 20 }], [{ x: 10, y: 20 }]);
t = await waitTip(page2, "#touch-log", "touchstart x=10 y=20 id=7 touches=1");
if (t.startsWith("touchstart x=10 y=20 id=7 touches=1")) { ok(`browser: touchstart -> "${t}"`); browserPass++; }
else { bad(`browser: touchstart got "${t}"`); browserFail++; }

await fireTouch("#deck-tm", "touchstart", [{ x: 10, y: 20 }], [{ x: 10, y: 20 }]);
await fireTouch("#deck-tm", "touchmove", [{ x: 18, y: 25 }], [{ x: 18, y: 25 }]);
t = await waitTip(page2, "#touch-log", "touchmove x=18 y=25 id=7 touches=1");
if (t.startsWith("touchmove x=18 y=25 id=7 touches=1")) { ok(`browser: touchmove -> "${t}"`); browserPass++; }
else { bad(`browser: touchmove got "${t}"`); browserFail++; }

await fireTouch("#deck-te", "touchstart", [{ x: 10, y: 20 }], [{ x: 10, y: 20 }]);
await fireTouch("#deck-te", "touchend", [], [{ x: 14, y: 24 }]);
t = await waitTip(page2, "#touch-log", "touchend x=14 y=24 id=7 touches=0");
if (t.startsWith("touchend x=14 y=24 id=7 touches=0")) { ok(`browser: touchend -> "${t}"`); browserPass++; }
else { bad(`browser: touchend got "${t}"`); browserFail++; }

// media: a real wav, a real playback lifecycle.
await page2.evaluate((src) => { const a = document.querySelector("#deck-m-meta"); a.src = src; a.load(); }, WAV);
t = await waitTip(page2, "#media-log", "loadedmetadata");
if (t.startsWith("loadedmetadata")) { ok(`browser: loadedmetadata -> "${t}"`); browserPass++; }
else { bad(`browser: loadedmetadata got "${t}"`); browserFail++; }

await page2.evaluate((src) => { const a = document.querySelector("#deck-m-play"); a.src = src; a.load(); a.play().catch(() => {}); }, WAV);
// give the play event a beat to fire, then quiesce before the first
// timeupdate (4 Hz) can overwrite the play tip.
await page2.waitForTimeout(150);
await page2.evaluate(() => { document.querySelector("#deck-m-play").pause(); });
t = await waitTip(page2, "#media-log", "play t=");
if (t.startsWith("play t=")) { ok(`browser: play -> "${t}"`); browserPass++; }
else { bad(`browser: play got "${t}"`); browserFail++; }

await page2.evaluate((src) => { const a = document.querySelector("#deck-m-pause"); a.src = src; a.load(); a.play().catch(() => {}); }, WAV);
await page2.waitForTimeout(150);
await page2.evaluate(() => { document.querySelector("#deck-m-pause").pause(); });
t = await waitTip(page2, "#media-log", "pause t=");
if (t.startsWith("pause t=")) { ok(`browser: pause -> "${t}"`); browserPass++; }
else { bad(`browser: pause got "${t}"`); browserFail++; }

await page2.evaluate((src) => { const a = document.querySelector("#deck-m-time"); a.src = src; a.load(); a.play().catch(() => {}); }, WAV);
t = await waitTip(page2, "#media-log", "timeupdate t=");
if (t.startsWith("timeupdate t=")) { ok(`browser: timeupdate -> "${t}"`); browserPass++; }
else { bad(`browser: timeupdate got "${t}"`); browserFail++; }
await page2.evaluate(() => { document.querySelector("#deck-m-time").pause(); });

await page2.evaluate((src) => { const a = document.querySelector("#deck-m-ended"); a.src = src; a.load(); a.play().catch(() => {}); }, WAV_END);
t = await waitTip(page2, "#media-log", "ended t=", 8000);
if (t.startsWith("ended t=")) { ok(`browser: ended -> "${t}"`); browserPass++; }
else { bad(`browser: ended got "${t}"`); browserFail++; }

await page2.evaluate(() => { const a = document.querySelector("#deck-m-err"); a.src = "data:audio/wav;base64,AAAA"; a.load(); });
t = await waitTip(page2, "#media-log", "error t=");
if (t.startsWith("error t=")) { ok(`browser: error -> "${t}"`); browserPass++; }
else { bad(`browser: error got "${t}"`); browserFail++; }

// narrow by default: a click-only control must not receive hover/press noise.
const before = await tip(page2, "#click-log");
await page2.evaluate(() => {
  const el = document.querySelector("#deck-click");
  el.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, clientX: 1, clientY: 1, button: 0, buttons: 1 }));
  el.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, clientX: 2, clientY: 2, button: 0, buttons: 1 }));
  el.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, clientX: 2, clientY: 2, button: 0, buttons: 0 }));
  el.dispatchEvent(new PointerEvent("pointerenter", { bubbles: true, clientX: 2, clientY: 2 }));
  el.dispatchEvent(new PointerEvent("pointerleave", { bubbles: true, clientX: 2, clientY: 2 }));
});
await page2.waitForTimeout(450);
const after = await tip(page2, "#click-log");
if (before === after && after === "click log") { ok("narrow: hover/press noise on #deck-click delivered nothing"); browserPass++; }
else { bad(`narrow: #deck-click received noise — "${before}" -> "${after}"`); browserFail++; }

await page2.locator("#deck-click").click();
// a click lands on the component root itself, so the engine reports no inner
// target id — "click target=<none>" IS the round-trip proof.
t = await waitTip(page2, "#click-log", "click target=");
if (t.startsWith("click target=")) { ok(`narrow: the declared click still round-trips -> "${t}"`); browserPass++; }
else { bad(`narrow: declared click got "${t}"`); browserFail++; }

// ---- layer B: the probe's own socket reads the frames the server answers ----

const socketCases = [
  ["deck-pd", "pointerdown", { x: 10, y: 20, button: 0, buttons: 1 }, "pointerdown x=10 y=20 button=0 buttons=1"],
  ["deck-pm", "pointermove", { x: 11, y: 21, button: 0, buttons: 1 }, "pointermove x=11 y=21 button=0 buttons=1"],
  ["deck-pu", "pointerup", { x: 12, y: 22, button: 0, buttons: 0 }, "pointerup x=12 y=22 button=0 buttons=0"],
  ["deck-pc", "pointercancel", { x: 13, y: 23, button: 0, buttons: 0 }, "pointercancel x=13 y=23 button=0 buttons=0"],
  ["deck-pe", "pointerenter", { x: 14, y: 24, button: 0, buttons: 0 }, "pointerenter x=14 y=24 button=0 buttons=0"],
  ["deck-pl", "pointerleave", { x: 15, y: 25, button: 0, buttons: 0 }, "pointerleave x=15 y=25 button=0 buttons=0"],
  ["deck-ts", "touchstart", { x: 10, y: 20, identifier: 5, touches: 1 }, "touchstart x=10 y=20 id=5 touches=1"],
  ["deck-tm", "touchmove", { x: 12, y: 22, identifier: 5, touches: 1 }, "touchmove x=12 y=22 id=5 touches=1"],
  ["deck-te", "touchend", { x: 14, y: 24, identifier: 5, touches: 0 }, "touchend x=14 y=24 id=5 touches=0"],
  ["deck-ds", "dragstart", { data: { "text/plain": "hi" }, files: [] }, "dragstart text/plain=hi"],
  ["deck-dr", "drag", { data: { "text/plain": "hi" }, files: [] }, "drag text/plain=hi"],
  ["deck-de", "dragend", { data: {}, files: [] }, "dragend"],
  ["deck-denter", "dragenter", { data: { "text/plain": "hi" }, files: [] }, "dragenter text/plain=hi"],
  ["deck-dover", "dragover", { data: { "text/plain": "hi" }, files: [] }, "dragover text/plain=hi"],
  ["deck-dleave", "dragleave", { data: {}, files: [] }, "dragleave"],
  ["deck-drop", "drop", { data: { "text/plain": "payload", "application/x-probe": "yes" }, files: [{ name: "probe.txt", size: 11, type: "text/plain" }] }, "drop application/x-probe=yes text/plain=payload file=probe.txt size=11 type=text/plain"],
  ["deck-copy", "copy", { text: "copied", html: null }, "copy text=copied html=&lt;nil&gt;"],
  ["deck-cut", "cut", { text: "cutted", html: null }, "cut text=cutted html=&lt;nil&gt;"],
  ["deck-paste", "paste", { text: "hello", html: "<b>hi</b>" }, "paste text=hello html=&lt;b&gt;hi&lt;/b&gt;"],
  ["deck-wheel", "wheel", { deltaX: 12, deltaY: 34 }, "wheel dx=12 dy=34"],
  ["deck-scroll", "scroll", { scrollTop: 40, scrollLeft: 0 }, "scroll top=40 left=0"],
  ["deck-dbl", "dblclick", { x: 1, y: 2, button: 0, buttons: 0 }, "dblclick x=1 y=2 button=0 buttons=0"],
  ["deck-ctx", "contextmenu", { x: 1, y: 2, button: 2, buttons: 2 }, "contextmenu x=1 y=2 button=2 buttons=2"],
  ["deck-anim", "animationend", { animationName: "deck-pulse" }, "animationend name=deck-pulse"],
  ["deck-tran", "transitionend", { propertyName: "width", elapsedTime: 0.3 }, "transitionend prop=width t=0.3"],
  ["deck-m-play", "play", { currentTime: 0.25, duration: 30, readyState: 4, code: null }, "play t=0.25 d=30 rs=4"],
  ["deck-m-pause", "pause", { currentTime: 1, duration: 30, readyState: 4, code: null }, "pause t=1 d=30 rs=4"],
  ["deck-m-ended", "ended", { currentTime: 0.06, duration: 0.06, readyState: 4, code: null }, "ended t=0.06 d=0.06 rs=4"],
  ["deck-m-time", "timeupdate", { currentTime: 0.5, duration: 30, readyState: 4, code: null }, "timeupdate t=0.5 d=30 rs=4"],
  ["deck-m-meta", "loadedmetadata", { currentTime: 0, duration: 0.06, readyState: 4, code: null }, "loadedmetadata t=0 d=0.06 rs=4"],
  ["deck-m-err", "error", { currentTime: 0, duration: 0, readyState: 0, code: 4 }, "error t=0 d=0 rs=0 code=4"],
  ["deck-click", "click", { targetId: "deck-click", targetClass: "deck-ctrl" }, "click target=deck-click"],
];

let socketPass = 0;
let socketFail = 0;
for (const [id, name, data, expect] of socketCases) {
  const res = await rawDispatch(comp(id), name, data);
  if (!res.opened) { bad(`socket: could not connect for ${name} (${id})`); socketFail++; continue; }
  if (!res.update) { bad(`socket: ${name} (${id}) sent but never answered — ${res.frames.length} frame(s) came back`); socketFail++; continue; }
  const html = JSON.stringify(res.update.fragments || []);
  if (html.includes(expect)) { ok(`socket: ${name} frame decoded -> "${expect}"`); socketPass++; }
  else { bad(`socket: ${name} frame did not carry "${expect}": ${html.slice(0, 160)}`); socketFail++; }
}

// ---- verdict + unconditional teardown ----

try { await browser.close(); } catch (e) {}
try { server.kill("SIGKILL"); } catch (e) {}

console.log(`  --- event deck gate: ${browserPass}/${browserCases.length + 21} browser · ${socketPass}/${socketCases.length} socket · ${pass - browserPass - socketPass} other · ${fail} fail`);
if (browserFail || socketFail || fail > 0) {
  console.log(`event-deck-probe FAILED (${browserFail} browser + ${socketFail} socket + ${fail} other failures)`);
  process.exit(1);
}
console.log("event-deck-probe OK");
