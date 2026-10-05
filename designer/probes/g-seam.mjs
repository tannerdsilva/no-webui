#!/usr/bin/env node
// designer/probes/g-seam.mjs  lane G's raw-WS seam probe (DX-12 + DX-14, W1).
//
// the shape is copied from designer/showcase-ws-smoke.mjs — a RAW client: fetch
// the page over HTTP, read the control ids out of the SERVED markup, connect its
// own socket, dispatch one event per id, and assert on the server's own frames.
// no browser, no page patching, nothing inferred. (the one thing NOT copied is
// showcase's hardcoded 9092 — lane G drives lane ports 9370–9379 only.)
//
// usage:
//   node designer/probes/g-seam.mjs                                # green build, :9370
//   node designer/probes/g-seam.mjs --port 9373 --binary <path>    # custom lane port/binary
//   node designer/probes/g-seam.mjs --mode hostile                 # seam-reverted build:
//     the SAME clicks — the handler-rendered stage-2 control answers with ZERO frames
//     (frames-only; the debug-line half is asserted in-process via router.observers
//     in SubstitutionTests-style tests, NOT here).
//
// green asserts (appendix C steps 2–3):
//   1. the served page exposes g-swap / g-outcome / g-region-nudge
//   2. SWAP: click g-swap -> an update whose fragment carries a NEW control id
//      (g-swap-stage2, rendered inside the handler body — self-registered)
//   3. SWAP: click g-swap-stage2 (never in the served markup) -> an update
//   4. ViewOutcome: click g-outcome -> one update whose fragment id IS in the
//      served markup's id set and whose html contains the rendered view
//   5. RegionInvalidations (W1): the control renders; clicking yields NO frame
//      (i0's invalidate provider is a no-op; the i1 registry push is asserted by
//      the acceptance harness once lane R's `regions:` lands)

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const PORT = Number(flag("--port", "9370"));
const BINARY = flag("--binary", join(ROOT, ".build", "debug", "WebUIExample"));
const MODE = flag("--mode", "green");
if (MODE !== "green" && MODE !== "hostile") {
  console.log(`  FAIL unknown --mode "${MODE}" (expected green | hostile)`);
  process.exit(1);
}
if (PORT < 9370 || PORT > 9379) {
  console.log(`  FAIL port ${PORT} is outside the lane block 9370–9379 (canonical ports are orchestrator-only)`);
  process.exit(1);
}

const BASE = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}/ws`;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

// precondition 1: node >= 22 with a global WebSocket (probe-shaped like showcase).
const major = Number(process.versions.node.split(".")[0]);
if (!(major >= 22) || typeof WebSocket !== "function") {
  console.log(`  FAIL probe precondition: needs node >= 22 with a global WebSocket (have ${process.version})`);
  process.exit(1);
}
ok(`runtime: node ${process.version} with global WebSocket and fetch`);

async function waitForServer(timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(BASE + "/", { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.text();
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

// one dispatch round-trip: open a socket, send the event on open, resolve with
// the (single) update frame or null. `opened` separates "could not connect"
// from "server never answered" (the showcase-ws-smoke lesson — its note on
// racing a teardown is copied verbatim in spirit).
function dispatch(id, eventName, windowMs = 3000) {
  return new Promise((resolve) => {
    let settled = false;
    let opened = false;
    const socket = new WebSocket(WS_URL);
    const finish = (value) => {
      if (settled) return;
      settled = true;
      try { socket.close(); } catch (e) {}
      resolve({ value, opened });
    };
    socket.addEventListener("open", () => {
      opened = true;
      socket.send(JSON.stringify({
        type: "event",
        component: id,
        event: eventName,
        data: { targetId: id }
      }));
    });
    socket.addEventListener("message", (ev) => {
      try {
        const msg = JSON.parse(String(ev.data));
        if (msg.type === "update") finish(msg);
      } catch (e) {}
    });
    socket.addEventListener("error", () => finish(null));
    setTimeout(() => finish(null), windowMs);
  });
}

// quiet window asserts "nothing arrives" — every inbound frame collected, closed
// after `windowMs`.
function expectSilence(windowMs = 2000) {
  return new Promise((resolve) => {
    const frames = [];
    const socket = new WebSocket(WS_URL);
    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({
        type: "event",
        component: "g-region-nudge",
        event: "click",
        data: { targetId: "g-region-nudge" }
      }));
    });
    socket.addEventListener("message", (ev) => {
      try { frames.push(JSON.parse(String(ev.data))); } catch (e) {}
    });
    socket.addEventListener("error", () => {});
    setTimeout(() => {
      try { socket.close(); } catch (e) {}
      resolve(frames);
    }, windowMs);
  });
}

const server = spawn(BINARY, ["--port", String(PORT)], {
  cwd: ROOT,
  stdio: ["ignore", "pipe", "pipe"],
});
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

const idsFromMarkup = (page) =>
  [...new Set([...page.matchAll(/data-component-id="([^"]+)"/g)].map((m) => m[1]))]
    .filter((id) => !/^c\d+$/.test(id));
const domIdsFromMarkup = (page) => [...new Set([...page.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]))];

async function run() {
  const page = await waitForServer();
  if (page === null) {
    bad(`server did not become ready on :${PORT}  (binary: ${BINARY})`);
    console.log(serverLog.split("\n").slice(-6).join("\n"));
    process.exitCode = 1;
    return;
  }
  ok(`server ready on :${PORT} (${MODE})`);

  const ids = idsFromMarkup(page);
  const domIds = domIdsFromMarkup(page);
  ok(`served markup exposes ${ids.length} stable-id control(s): ${ids.join(", ")}`);

  // precondition: the demo's W1 controls are all present in the served markup.
  for (const id of ["g-swap", "g-outcome", "g-region-nudge"]) {
    if (ids.includes(id)) ok(`${id} present in served markup`);
    else bad(`${id} MISSING from served markup`);
  }
  // the ViewOutcome control's replaceable root must carry id == component id
  // (rev4/a2) — its update fragment id is therefore in the served id set.
  if (domIds.includes("g-outcome")) ok(`served markup id set contains "g-outcome" (ViewOutcome replaceable root)`);
  else bad(`served markup id set does NOT contain "g-outcome"`);
  // stage-2 must NOT be in the served markup — it appears only when the
  // stage-1 handler renders it (the whole point of the seam).
  if (page.includes("g-swap-stage2")) bad(`g-swap-stage2 should not exist in the served markup`);
  else ok(`g-swap-stage2 absent from served markup (handler-rendered, not page-rendered)`);

  // --- the SWAP control ---
  let { value: reply, opened } = await dispatch("g-swap", "click");
  if (!reply && !opened) {
    await new Promise((r) => setTimeout(r, 250));
    ({ value: reply, opened } = await dispatch("g-swap", "click"));
  }
  if (!reply || reply.type !== "update" || !Array.isArray(reply.fragments)) {
    bad(`g-swap click: no update frame  ${opened ? "(socket opened, server silent)" : "(socket never opened)"}`);
  } else {
    const frag = reply.fragments[0] || {};
    const carried = String(frag.html || "").includes("data-component-id=\"g-swap-stage2\"");
    const rightId = frag.id === "g-swap-panel";
    console.log(`    frame: ${JSON.stringify(reply).slice(0, 180)}`);
    if (carried && rightId) {
      ok(`g-swap click -> update carrying the NEW handler-rendered control id g-swap-stage2 (fragment id g-swap-panel)`);
    } else if (rightId) {
      bad(`g-swap click -> fragment id ok but the new control id is NOT in the fragment html`);
    } else {
      bad(`g-swap click -> unexpected fragment id: ${JSON.stringify(reply.fragments).slice(0, 120)}`);
    }
  }
  await new Promise((r) => setTimeout(r, 150));

  // --- the handler-rendered control answers a later event ---
  // green: g-swap-stage2 is registered by the seam during the dispatch render.
  // hostile: the seam is reverted, so that render had no context -> ZERO frames.
  ({ value: reply, opened } = await dispatch("g-swap-stage2", "click"));
  if (!reply && !opened) {
    await new Promise((r) => setTimeout(r, 250));
    ({ value: reply, opened } = await dispatch("g-swap-stage2", "click"));
  }
  await new Promise((r) => setTimeout(r, 500)); // a late frame would still land here
  const stage2GotFrame = !!reply && reply.type === "update" && Array.isArray(reply.fragments) && reply.fragments.length > 0;
  if (MODE === "green") {
    if (stage2GotFrame) {
      ok(`g-swap-stage2 click -> update (the seam-registered, handler-rendered control answers a later event)`);
    } else {
      bad(`g-swap-stage2 click -> ZERO frames  the seam-${
        opened ? "" : " (socket never opened)"}  handler-introduced control is dead  ${JSON.stringify(reply)}`);
    }
  } else {
    if (stage2GotFrame) {
      bad(`hostile build: g-swap-stage2 click -> a frame arrived  the reverted seam must leave it dead`);
      console.log(`    frame: ${JSON.stringify(reply).slice(0, 180)}`);
    } else if (!opened) {
      bad(`hostile build: g-swap-stage2 click -> socket never opened  probe precondition failed, not a verdict`);
    } else {
      ok(`hostile build: g-swap-stage2 click -> ZERO frames  (the handler-rendered control is dead without the dispatch seam)`);
    }
  }
  await new Promise((r) => setTimeout(r, 150));

  // --- the ViewOutcome control (appendix C step 3) ---
  ({ value: reply, opened } = await dispatch("g-outcome", "click"));
  if (!reply && !opened) {
    await new Promise((r) => setTimeout(r, 250));
    ({ value: reply, opened } = await dispatch("g-outcome", "click"));
  }
  if (!reply || reply.type !== "update" || !Array.isArray(reply.fragments)) {
    bad(`g-outcome click -> no update frame  ${opened ? "(socket opened, server silent)" : "(socket never opened)"}`);
  } else {
    const frag = reply.fragments[0] || {};
    const idInServed = domIds.includes(frag.id);
    const hasView = String(frag.html || "").includes("replaced by ViewOutcome");
    console.log(`    frame: ${JSON.stringify(reply).slice(0, 180)}`);
    if (frag.id === "g-outcome" && idInServed && hasView) {
      ok(`g-outcome click -> one update, fragment id "g-outcome" IS in the served markup id set, html carries the rendered View`);
    } else if (frag.id !== "g-outcome") {
      bad(`g-outcome click -> fragment id "${frag.id}" != component id (minted-id context would be out of contract)`);
    } else if (!hasView) {
      bad(`g-outcome click -> fragment html does not carry the rendered View`);
    } else {
      bad(`g-outcome click -> fragment id NOT in the served markup id set`);
    }
  }
  await new Promise((r) => setTimeout(r, 150));

  // --- the RegionInvalidations control (W1: renders; i1: registry push) ---
  if (ids.includes("g-region-nudge")) {
    // at i0 the invalidate provider is a no-op, so resolve carries no fragments
    // and the server sends no frame at all (`guard !updates.isEmpty`).
    const frames = await expectSilence(1500);
    if (frames.length === 0) {
      ok(`g-region-nudge click -> silence in the i0 no-op window (resolve carried no fragments; registry push asserted at i1)`);
    } else {
      bad(`g-region-nudge click -> ${frames.length} frame(s) arrived  (at i0 resolve must carry none)`);
      console.log(`    frames: ${JSON.stringify(frames).slice(0, 200)}`);
    }
  }
}

try {
  await run();
} finally {
  server.kill("SIGTERM");
  await new Promise((r) => setTimeout(r, 300));
  if (!server.killed) server.kill("SIGKILL");
}

console.log("");
console.log(`=== summary: ${pass} passed, ${fail} failed (mode ${MODE}) ===`);
console.log(fail === 0 ? `G-SEAM ${MODE.toUpperCase()} PASS` : `G-SEAM ${MODE.toUpperCase()} FAIL`);
process.exit(fail === 0 ? 0 : 1);
