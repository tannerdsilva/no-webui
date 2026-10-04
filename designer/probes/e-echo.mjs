#!/usr/bin/env node
// designer/probes/e-echo.mjs — lane-E probe: engine-local echo (t1.4).
//
// contract: an element carrying data-webui-echo="<id>" writes its value into
// #<id>'s text in the same turn, engine-locally, with zero websocket traffic;
// the authoritative patch (a text op or replace) always wins and clears the
// overlay. probe: type 20 chars → echo target updates per keystroke AND 0 ws
// frames during the typing window. frames are counted from OUTSIDE via
// playwright's page.on('websocket') — the runtime is never patched under
// measurement.
//
// lane port 9261.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9261;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

const { base, close } = await startProbeServer(PORT, "", {
  enginePath: join(ROOT, "designer/assets/webui-engine.js"),
  config: { debounceInputMs: 300, debounceMaxWaitMs: 1000 },
});
ok(`probe server up on :${PORT}`);

process.on("exit", () => { close(); });
process.on("SIGINT", () => { close(); process.exit(1); });

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
// reduced-motion makes authoritative patches apply synchronously — same
// determinism guarantee as e-ops; nothing in the runtime is patched.
await context.addInitScript(() => {
  try {
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: (q) => ({ matches: q === "(prefers-reduced-motion: reduce)", media: q, onchange: null, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }),
    });
  } catch (e) {}
});
const page = await context.newPage();
page.on("pageerror", (err) => bad("page error: " + err.message));

// count frames from OUTSIDE the page — playwright observes the page's own
// WebSocket objects; nothing in the page is instrumented.
let framesSent = [];
const onWsFrame = (ws) => {
  ws.on("framesent", (evt) => {
    framesSent.push({ t: Date.now(), frame: evt.payload?.toString?.() ?? String(evt) });
  });
};
page.on("websocket", onWsFrame);

await page.goto(base + "/");
await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });

// fixture: an echo source input + an echo target span, inside #echo.
await page.evaluate(() => {
  const host = document.getElementById("echo");
  host.innerHTML = "";
  const input = document.createElement("input");
  input.id = "echo-src";
  input.type = "text";
  input.setAttribute("data-webui-echo", "echo-out");
  const target = document.createElement("span");
  target.id = "echo-out";
  target.textContent = "INIT";
  host.appendChild(input);
  host.appendChild(target);
});

const inputSel = "#echo-src";
const targetSel = "#echo-out";

async function typeAndSample(char, idx) {
  await page.keyboard.type(char, { delay: 12 });
  const text = await page.evaluate((sel) => document.querySelector(sel)?.textContent ?? null, targetSel);
  return text;
}

// type "abcdefghijklmnopqrst" — 20 chars, sampling the echo target after each.
const text20 = "abcdefghijklmnopqrst";
const samples = [];
await page.focus(inputSel);
for (let i = 0; i < text20.length; i++) {
  samples.push(await typeAndSample(text20[i], i));
}

// how many frames crossed during the typing window?
const duringTyping = framesSent.length;

// authoritative patch wins: server confirms a different value for the target.
const authoritative = await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  inst.patch([{ id: "echo-out", op: "text", text: "SERVER" }], 1);
  const text = document.getElementById("echo-out").textContent;
  const overlayCleared = !(inst.fragmentPatcher.echoOverlay["echo-out"]);
  return { text, overlayCleared };
});

// every sample equals the typed prefix, ending with the full 20 chars
const monotonic = samples.every((s, i) => s === text20.slice(0, i + 1));
if (monotonic && samples[samples.length - 1] === text20) {
  ok("echo target updated per keystroke (20/20 samples match typed prefix)");
} else {
  bad(`echo per-keystroke: samples="${samples[samples.length - 1]}" expect="${text20}" monotonic=${monotonic}`);
}

if (duringTyping === 0) {
  ok("0 websocket frames sent during the typing window (echo is engine-local)");
} else {
  bad(`echo sent ${duringTyping} ws frame(s) during typing (expected 0)`);
}

if (authoritative.text === "SERVER" && authoritative.overlayCleared) {
  ok("authoritative text op wins over the local overlay and clears it");
} else {
  bad(`authoritative: text=${JSON.stringify(authoritative.text)} overlayCleared=${authoritative.overlayCleared}`);
}

// extra: replace, not just text, also clears the overlay.
const replaceWins = await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  inst.fragmentPatcher.echo("echo-out", "STALE");
  inst.patch([{ id: "echo-out", html: '<span id="echo-out">REPLACED</span>' }], 2);
  return {
    text: document.getElementById("echo-out").textContent,
    overlayCleared: !(inst.fragmentPatcher.echoOverlay["echo-out"]),
  };
});
if (replaceWins.text === "REPLACED" && replaceWins.overlayCleared) {
  ok("authoritative replace wins over the local overlay and clears it");
} else {
  bad(`replace: text=${JSON.stringify(replaceWins.text)} overlayCleared=${replaceWins.overlayCleared}`);
}

// wire path still flows: a component-wired echo input shows the local echo AND
// sends exactly one debounced event frame at the edge (frames only at the
// debounce edges — the echo suppresses none of them).
const wiredState = await page.evaluate(() => {
  const host = document.getElementById("echo");
  host.innerHTML = "";
  const box = document.createElement("div");
  box.setAttribute("data-component-id", "echo-probe");
  box.setAttribute("data-event", "input");
  const input = document.createElement("input");
  input.id = "echo-wired";
  input.type = "text";
  input.setAttribute("data-webui-echo", "echo-wired-out");
  const target = document.createElement("span");
  target.id = "echo-wired-out";
  target.textContent = "OPEN";
  box.appendChild(input);
  box.appendChild(target);
  host.appendChild(box);
  return true;
});
const framesBeforeWired = framesSent.length;
await page.focus("#echo-wired");
await page.keyboard.type("hi", { delay: 12 });
const wiredEcho = await page.evaluate(() => document.getElementById("echo-wired-out").textContent);
await page.waitForTimeout(650); // debounce edge (300ms) plus margin
const wiredFinal = await page.evaluate(() => document.getElementById("echo-wired-out").textContent);
const framesAfterWired = framesSent.length;
const wiredFrames = framesAfterWired - framesBeforeWired;
if (wiredEcho === "hi" && wiredFinal === "hi" && wiredFrames >= 1) {
  ok(`wired echo: local echo visible, ${wiredFrames} frame(s) at the debounce edge (edge-only)`);
} else {
  bad(`wired echo: text=${JSON.stringify(wiredEcho)} final=${JSON.stringify(wiredFinal)} frames=${wiredFrames}`);
}

await browser.close();
close();

console.log(`\ne-echo: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
