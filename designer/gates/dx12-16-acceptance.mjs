#!/usr/bin/env node
// designer/gates/dx12-16-acceptance.mjs  the LIVE_DX acceptance harness (lane G, appendix C).
//
// W1 state: the DX-12 / DX-14 asserts (steps 1–3) and the no-layer audit (step 9)
// are LIVE and runnable now against the i0 base. the i1/i2-only parts — the four
// live regions (steps 4–6), the theme pipeline (step 7), and the integration gate
// ladder (step 8) — are STRUCTURAL STUBS behind a clear "pending: lane R/T symbols"
// guard: they are skipped (with the exact requirement named), never silently assumed
// green. the orchestrator runs this file at i1 and i2; it is committed runnable now.
//
// usage (lane ports 9370–9379 only):
//   node designer/gates/dx12-16-acceptance.mjs
//   node designer/gates/dx12-16-acceptance.mjs --binary <path>            # custom binary
//   node designer/gates/dx12-16-acceptance.mjs --hostile-binary <path>    # + the scratch
//     seam-reverted build's frames-only hostile control run (appendix C step 2)

import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const PORT = Number(flag("--port", "9375"));
const BINARY = flag("--binary", join(ROOT, ".build", "debug", "WebUIExample"));
const HOSTILE_BINARY = flag("--hostile-binary", null);
if (PORT < 9370 || PORT > 9379) {
  console.log(`FAIL port ${PORT} is outside the lane block 9370–9379 (canonical ports are orchestrator-only)`);
  process.exit(1);
}

const BASE = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}/ws`;

let pass = 0, fail = 0, pending = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };
const skip = (m) => { pending++; console.log(`  PENDING ${m}`); };

const major = Number(process.versions.node.split(".")[0]);
if (!(major >= 22) || typeof WebSocket !== "function") {
  console.log(`FAIL probe precondition: needs node >= 22 with a global WebSocket (have ${process.version})`);
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

function dispatch(id, eventName, windowMs = 3000) {
  return new Promise((resolve) => {
    let settled = false, opened = false;
    const socket = new WebSocket(WS_URL);
    const finish = (value) => {
      if (settled) return;
      settled = true;
      try { socket.close(); } catch (e) {}
      resolve({ value, opened });
    };
    socket.addEventListener("open", () => {
      opened = true;
      socket.send(JSON.stringify({ type: "event", component: id, event: eventName, data: { targetId: id } }));
    });
    socket.addEventListener("message", (ev) => {
      try { const msg = JSON.parse(String(ev.data)); if (msg.type === "update") finish(msg); } catch (e) {}
    });
    socket.addEventListener("error", () => finish(null));
    setTimeout(() => finish(null), windowMs);
  });
}

async function runServer(binary) {
  const server = spawn(binary, ["--port", String(PORT)], { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
  let serverLog = "";
  server.stdout.on("data", (d) => (serverLog += d));
  server.stderr.on("data", (d) => (serverLog += d));
  return { server, serverLog };
}

// step 9's exact banned-construct token set (appendix C, rev4/c6).
const BANNED_TOKENS = [
  "Timer.publish", "scheduledTimer", "DispatchSourceTimer", "Task.sleep", "asyncAfter",
  "IntervalService", "startPolling", "wire(", "withValueBody", "btn(", ".register(",
];
const EXAMPLE_SOURCE = join(ROOT, "Sources", "WebUIExample", "main.swift");

async function run() {
  const { server, serverLog } = await runServer(BINARY);
  try {
    // ── 1. preflight: the tree warm-built, lane port free, server ready ──
    const page = await waitForServer();
    if (page === null) {
      bad(`step 1: server did not become ready on :${PORT} (${BINARY})`);
      console.log(serverLog.split("\n").slice(-6).join("\n"));
      return;
    }
    ok("step 1: WebUIExample ready on lane port " + PORT);
    const ids = [...new Set([...page.matchAll(/data-component-id="([^"]+)"/g)].map((m) => m[1]))]
      .filter((i) => !/^c\d+$/.test(i));
    const domIds = [...new Set([...page.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]))];

    // ── 2. DX-12 (the seam) ──
    ok(`step 2 (DX-12): served markup exposes ${ids.length} stable-id control(s)`);
    if (ids.includes("g-swap")) ok("  SWAP control present (id read from the SERVED markup)");
    else bad("  SWAP control (g-swap) missing from served markup");
    let { value: reply, opened } = await dispatch("g-swap", "click");
    if (!reply && !opened) { await new Promise((r) => setTimeout(r, 250)); ({ value: reply, opened } = await dispatch("g-swap", "click")); }
    const carriedNew = !!(reply && reply.fragments && String(reply.fragments[0]?.html || "").includes("data-component-id=\"g-swap-stage2\""));
    if (carriedNew) ok("  click g-swap -> update carrying a NEW control id (g-swap-stage2, rendered inside the handler)");
    else bad("  click g-swap -> no update carrying a NEW control id  " + JSON.stringify(reply).slice(0, 140));
    await new Promise((r) => setTimeout(r, 150));
    ({ value: reply, opened } = await dispatch("g-swap-stage2", "click"));
    if (!reply && !opened) { await new Promise((r) => setTimeout(r, 250)); ({ value: reply, opened } = await dispatch("g-swap-stage2", "click")); }
    await new Promise((r) => setTimeout(r, 500));
    if (reply && reply.type === "update" && (reply.fragments || []).length > 0) {
      ok("  click g-swap-stage2 (never in served markup) -> an update  the handler-rendered control self-registered");
    } else {
      bad("  click g-swap-stage2 -> ZERO frames  the handler-rendered control is dead  " + JSON.stringify(reply));
    }

    // ── 2b. the hostile control run (appendix C step 2) — frames-only, debug line
    // asserted in-process via router.observers in SubstitutionTests-style tests ──
    if (HOSTILE_BINARY) {
      await new Promise((r) => setTimeout(r, 150));
      server.kill("SIGTERM");
      await new Promise((r) => setTimeout(r, 400));
      const hostile = await runServer(HOSTILE_BINARY);
      try {
        const hPage = await waitForServer();
        if (hPage === null) {
          bad("  step 2b (hostile): seam-reverted build did not become ready");
        } else {
          ok("  step 2b (hostile): seam-reverted build serving on :" + PORT);
          ({ value: reply, opened } = await dispatch("g-swap", "click"));
          if (!reply && !opened) { await new Promise((r) => setTimeout(r, 250)); ({ value: reply, opened } = await dispatch("g-swap", "click")); }
          const firstStillAnswers = !!(reply && reply.fragments && reply.fragments.length > 0);
          if (firstStillAnswers) ok("    hostile: click g-swap -> STILL an update (page render registered it; dispatch works)");
          else bad("    hostile: click g-swap -> no update  server broken, not a seam verdict");
          await new Promise((r) => setTimeout(r, 150));
          ({ value: reply, opened } = await dispatch("g-swap-stage2", "click"));
          if (!reply && !opened) { await new Promise((r) => setTimeout(r, 250)); ({ value: reply, opened } = await dispatch("g-swap-stage2", "click")); }
          await new Promise((r) => setTimeout(r, 500));
          if (reply && reply.type === "update" && (reply.fragments || []).length > 0) {
            bad("    hostile: click g-swap-stage2 -> a frame arrived  MUST be zero without the seam");
          } else if (!opened) {
            bad("    hostile: click g-swap-stage2 -> socket never opened  probe precondition, not a verdict");
          } else {
            ok("    hostile: click g-swap-stage2 -> ZERO frames  (the i0 seam is load-bearing; the hostile half is frames-only)");
          }
        }
      } finally {
        hostile.server.kill("SIGTERM");
        await new Promise((r) => setTimeout(r, 300));
        if (!hostile.server.killed) hostile.server.kill("SIGKILL");
      }
      // bring the green server back for the remaining steps
      server.kill("SIGKILL");
      const revived = await runServer(BINARY);
      const rPage = await waitForServer();
      void revived;
      if (rPage === null) { bad("  teardown glitch: green server did not come back after the hostile run"); return; }
    }

    // ── 3. DX-14 (outcomes) ──
    ({ value: reply, opened } = await dispatch("g-outcome", "click"));
    if (!reply && !opened) { await new Promise((r) => setTimeout(r, 250)); ({ value: reply, opened } = await dispatch("g-outcome", "click")); }
    if (reply && reply.type === "update" && Array.isArray(reply.fragments) && reply.fragments.length === 1) {
      const frag = reply.fragments[0];
      const idInServed = domIds.includes(frag.id);
      const hasView = String(frag.html || "").includes("replaced by ViewOutcome");
      if (frag.id === "g-outcome" && idInServed && hasView) {
        ok("step 3 (DX-14): ViewOutcome click -> one update, fragment id IS in the served markup id set, html carries the rendered view");
      } else if (frag.id !== "g-outcome") {
        bad(`step 3 (DX-14): fragment id "${frag.id}" != component id (minted-id context out of contract)`);
      } else if (!hasView) {
        bad("step 3 (DX-14): fragment html does not carry the rendered view");
      } else {
        bad("step 3 (DX-14): fragment id NOT in the served markup id set");
      }
    } else {
      bad("step 3 (DX-14): ViewOutcome click -> expected exactly one update  " + JSON.stringify(reply));
    }
    await new Promise((r) => setTimeout(r, 150));

    // RegionInvalidations end-to-end — PENDING: lane R's registry (i1)
    if (ids.includes("g-region-nudge")) skip("step 3 (DX-14): RegionInvalidations control present; registry-driven push is asserted at i1 once lane R attaches regions: — pending: lane R symbols");
    else bad("step 3 (DX-14): RegionInvalidations control (g-region-nudge) missing from served markup");

    // ── 4–6. DX-13 / DX-16: the four live regions — PENDING (i1: lane R) ──
    skip("step 4 (DX-13): invalidation -> exactly one update, fragment id == region id, bytes <= html + 512 (I8) — pending: lane R symbols");
    skip("step 5 (DX-13): silence -> ZERO frames in max(1.5 s, 2xcadence) (I7) — pending: lane R symbols");
    skip("step 6 (DX-16): LiveBox + custom-LiveState region pushes; bounded burst form (M=200) — pending: lane R symbols");

    // ── 7. DX-15a (theme) — PENDING (i2: lane T) ──
    skip("step 7 (DX-15a): theme pipeline verdict-parametric emissions — pending: lane T symbols");

    // ── 8. the gate ladder — PENDING (orchestrator at i1/i2; canonical ports) ──
    skip("step 8: swift test · plugin smoke · fullstack-smoke · budget · dx-content-pin --serve · browser-smoke · g-* probes · shadow check — orchestrator at i1/i2");

    // ── 9. NO-LAYER AUDIT (positive assertion, rev4/c6) — W1 slice LIVE ──
    // the W1-required conformances: the demo wires its controls ONLY through the
    // generic seam (control(_:handler:)) with EventOutcome conforming types.
    // (the full enumeration — ViewOutcome control · RegionInvalidations control ·
    // 4 region drivers · ThemeCatalog + hand-written provider — completes at i2.)
    const src = readFileSync(EXAMPLE_SOURCE, "utf8");
    const requiredW1 = [
      ["control(", "the generic seam control(_:handler:) drives the demo controls"],
      ["ViewOutcome", "a ViewOutcome control whose root carries id == data-component-id"],
      ["RegionInvalidations", "a RegionInvalidations control returning the declared region id"],
    ];
    for (const [token, what] of requiredW1) {
      if (src.includes(token)) ok(`step 9: required conformance present — ${what} (${token})`);
      else bad(`step 9: required conformance MISSING — ${what} (${token})`);
    }
    for (const t of BANNED_TOKENS) {
      if (src.includes(t)) bad(`step 9: banned construct PRESENT — exact token "${t}"`);
      else ok(`step 9: banned construct absent — "${t}"`);
    }
    if (!src.includes("RenderContext.withCurrent")) bad("step 9: the demo must adopt the framework seam RenderContext.withCurrent(router:) (no withValueBody hand-roll)");
    else ok("step 9: demo adopts RenderContext.withCurrent(router:) (no hand-rolled render context)");
    skip("step 9: 4 region drivers + ThemeCatalog + hand-written provider conformances — pending: lane R/T symbols (i2)");
    skip("step 9: shadow-check leg reuses the one shadow-check implementation — pending: lane T (i2)");

    // ── 10. teardown ──
    ok("step 10: teardown — server(s) killed");
  } finally {
    server.kill("SIGKILL");
    await new Promise((r) => setTimeout(r, 300));
  }
}

run().then(() => {
  console.log("");
  console.log(`=== dx12-16-acceptance: ${pass} passed, ${fail} failed, ${pending} pending (i1/i2) ===`);
  if (fail === 0) console.log("ACCEPTANCE W1 SLICE PASS (pending parts remain for i1/i2)");
  else console.log("ACCEPTANCE W1 SLICE FAIL");
  process.exit(fail === 0 ? 0 : 1);
});
