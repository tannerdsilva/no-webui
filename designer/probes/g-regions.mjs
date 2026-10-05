#!/usr/bin/env node
// designer/probes/g-regions.mjs  lane G's live-region probe (DX-13 live regions + DX-16 state, W2).
//
// shape copied from designer/showcase-ws-smoke.mjs, via g-seam.mjs — a RAW client:
// fetch the page over HTTP, read the region/control ids out of the SERVED markup,
// connect its own socket, dispatch events, and assert on the server's own frames.
// no browser, no page patching, nothing inferred. lane ports 9370–9379 only.
//
// usage:
//   node designer/probes/g-regions.mjs                             # green build, :9371
//   node designer/probes/g-regions.mjs --port 9372 --binary <path>
//
// asserts (appendix C steps 4–6 + the d-k ordering rule):
//   1. the served markup carries the four region roots and the five controls
//   2. DX-13 invalidation: one nudge -> EXACTLY ONE update, fragment id == the
//      region id, and the frame is <= the rendered html + 512 B (I8)
//   3. I7 silence: after a push has settled, an idle window carries ZERO frames
//   4. DX-16: a LiveBox-backed region, a custom-LiveRegion-struct-backed region
//      and a custom-LiveState-actor-backed region each push exactly once per
//      state change
//   5. d-k ordering: a COMBINED outcome writes its fragment BEFORE the region
//      push it wakes (dispatch frame first, registry frame second)
//   6. racing invalidates converge: two rapid nudges never let an older render
//      land last (the value sequence is strictly increasing)

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const PORT = Number(flag("--port", "9371"));
const BINARY = flag("--binary", join(ROOT, ".build", "debug", "WebUIExample"));

if (PORT < 9370 || PORT > 9379) {
  console.log(`  FAIL port ${PORT} is outside the lane block 9370–9379 (canonical ports are orchestrator-only)`);
  process.exit(1);
}
const major = Number(process.versions.node.split(".")[0]);
if (!(major >= 22) || typeof WebSocket !== "function") {
  console.log(`  FAIL probe precondition: needs node >= 22 with a global WebSocket (have ${process.version})`);
  process.exit(1);
}

const BASE = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}/ws`;
let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

const event = (id) => JSON.stringify({ type: "event", component: id, event: "click", data: { targetId: id } });

/// connect, run `send(socket)` on open, collect every inbound frame for windowMs.
function collect(send, windowMs = 1500) {
  return new Promise((resolve) => {
    const frames = [];
    let opened = false;
    const socket = new WebSocket(WS_URL);
    socket.addEventListener("open", () => { opened = true; if (send) send(socket); });
    socket.addEventListener("message", (ev) => {
      try { frames.push({ raw: String(ev.data), msg: JSON.parse(String(ev.data)) }); } catch (e) {}
    });
    socket.addEventListener("error", () => {});
    setTimeout(() => { try { socket.close(); } catch (e) {} resolve({ frames, opened }); }, windowMs);
  });
}
const updates = (frames) => frames.filter((f) => f.msg.type === "update");
const idsOf = (frames) => updates(frames).flatMap((f) => (f.msg.fragments ?? []).map((fr) => fr.id));
const valuesOf = (frames, id) =>
  updates(frames)
    .flatMap((f) => (f.msg.fragments ?? []).filter((fr) => fr.id === id).map((fr) => fr.html))
    .map((html) => Number((/value (\d+)/.exec(html) ?? [])[1] ?? NaN));

async function waitForServer(timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(BASE + "/", { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.text();
    } catch (e) {}
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

const server = spawn(BINARY, ["--port", String(PORT)], { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

async function run() {
  const page = await waitForServer();
  if (page === null) {
    bad(`server did not become ready on :${PORT} (binary: ${BINARY})`);
    console.log(serverLog.split("\n").slice(-6).join("\n"));
    process.exitCode = 1;
    return;
  }
  ok(`server ready on :${PORT}`);

  // 1. the served markup carries the four region roots and the five controls.
  const roots = ["g-region-a", "g-region-b", "g-region-c", "g-region-d"];
  const controls = ["g-region-nudge", "g-region-combined", "g-region-b-bump", "g-region-c-bump", "g-region-d-bump"];
  const missingRoots = roots.filter((id) => !page.includes(`id="${id}"`));
  const missingControls = controls.filter((id) => !page.includes(`data-component-id="${id}"`));
  if (missingRoots.length === 0) ok(`served markup carries the four region roots (${roots.join(", ")})`);
  else bad(`region roots missing from the served markup: ${missingRoots.join(", ")}`);
  if (missingControls.length === 0) ok(`served markup carries the five region controls`);
  else bad(`region controls missing: ${missingControls.join(", ")}`);

  // 2. DX-13 invalidation — exactly one update, fragment id == the region id, I8 bytes.
  {
    const { frames } = await collect((s) => s.send(event("g-region-nudge")), 1500);
    const ups = updates(frames);
    const frags = ups.flatMap((f) => f.msg.fragments ?? []);
    if (ups.length === 1 && frags.length === 1 && frags[0].id === "g-region-a") {
      ok(`nudge -> exactly one update carrying fragment id g-region-a`);
      const frameBytes = Buffer.byteLength(ups[0].raw, "utf8");
      const htmlBytes = Buffer.byteLength(frags[0].html, "utf8");
      if (frameBytes <= htmlBytes + 512) ok(`I8: frame ${frameBytes} B <= html ${htmlBytes} B + 512`);
      else bad(`I8: frame ${frameBytes} B exceeds html ${htmlBytes} B + 512`);
    } else {
      bad(`nudge -> expected exactly one update with fragment id g-region-a, got ${JSON.stringify(ups.map((u) => u.msg))}`);
    }
  }

  // 3. I7 silence — once a push has settled, an idle window carries zero frames.
  {
    const { frames } = await collect(null, 1600);
    if (frames.length === 0) ok(`I7: an idle window after a settled push carries ZERO frames`);
    else bad(`I7: ${frames.length} unsolicited frame(s) in an idle window: ${frames.map((f) => f.raw).join(" | ").slice(0, 200)}`);
  }

  // 4. DX-16 — the three state-driven drivers each push exactly once per change.
  for (const [control, region] of [["g-region-b-bump", "g-region-b"], ["g-region-c-bump", "g-region-c"], ["g-region-d-bump", "g-region-d"]]) {
    const { frames } = await collect((s) => s.send(event(control)), 1500);
    const ups = updates(frames);
    const frags = ups.flatMap((f) => f.msg.fragments ?? []);
    if (ups.length === 1 && frags.length === 1 && frags[0].id === region) {
      ok(`${control} -> exactly one update carrying fragment id ${region}`);
    } else {
      bad(`${control} -> expected one update with fragment id ${region}, got ${JSON.stringify(ups.map((u) => u.msg))}`);
    }
  }

  // 5. d-k ordering — the combined control's fragment lands BEFORE the region push.
  {
    const { frames } = await collect((s) => s.send(event("g-region-combined")), 1800);
    const ids = idsOf(frames);
    if (ids.length >= 2 && ids[0] === "g-combined-out" && ids.includes("g-region-a")) {
      ok(`d-k: the dispatch frame (g-combined-out) precedes the region push (g-region-a) — order [${ids.join(", ")}]`);
    } else {
      bad(`d-k: expected [g-combined-out, …, g-region-a], got [${ids.join(", ")}]`);
    }
  }

  // 6. racing invalidates converge — the LAST value is the newest state.
  {
    const { frames } = await collect((s) => {
      s.send(event("g-region-nudge"));
      setTimeout(() => s.send(event("g-region-nudge")), 40);
    }, 2000);
    const values = valuesOf(frames, "g-region-a").filter((v) => !Number.isNaN(v));
    const mono = values.every((v, i) => i === 0 || v > values[i - 1]);
    if (values.length >= 1 && mono) {
      ok(`racing: the g-region-a value sequence is strictly increasing [${values.join(", ")}] — no stale-wins`);
    } else {
      bad(`racing: value sequence not strictly increasing [${values.join(", ")}]`);
    }
  }

  try { server.kill(); } catch (e) {}
  console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    console.log(serverLog.split("\n").slice(-8).join("\n"));
    process.exitCode = 1;
  } else {
    console.log("G-REGIONS GREEN PASS");
  }
}

run().catch((e) => { bad(`probe crashed: ${e}`); try { server.kill(); } catch (_) {} process.exitCode = 1; });