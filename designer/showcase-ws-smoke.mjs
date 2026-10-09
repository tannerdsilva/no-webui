#!/usr/bin/env node
// designer/showcase-ws-smoke.mjs  stable-id dispatch gate (layer 1: a RAW client).
//
// why a raw client: the previous revision drove a headless browser and captured the
// websocket frames by patching `WebSocket` inside the page. that instrument was blind
// twice (the engine assigns `onmessage` on the instance at connect time, and any hook
// installed before boot perturbs the page it measures), so "the server never replied"
// was indistinguishable from "my hook never ran".
//
// this revision observes from OUTSIDE the system under test: it fetches the page over
// HTTP, reads the stable control ids out of the served markup, connects a socket of its
// own, dispatches one event per id, and asserts that a non-empty `update` frame comes
// back. nothing is patched, nothing is inferred, and the frames it prints are the
// server's own bytes.
//
// usage: node designer/showcase-ws-smoke.mjs
//   spawns WebUIShowcaseServer on :9092, probes, tears down. exits non-zero on failure.

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9092;
const BASE = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}/ws`;
// the served page's render token, read from the webui-config meta after the
// page fetch and echoed on every event frame exactly as the engine echoes it.
var RENDER_TOKEN = null;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

// precondition 1: the probe itself needs a runtime with a global WebSocket (node >= 22;
// it was flag-gated in 21). a probe that silently cannot connect is the failure mode this
// asserts away rather than discovering later.
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
      if (res.ok) { return await res.text(); }
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

// a probe whose socket never established is an INSTRUMENT failure, not a dispatch
// verdict — node's built-in WebSocket client can race a connection torn down
// moments earlier. measured 2026-09-28: the second of three back-to-back probes
// errored at ~2ms with zero frames, identically on the pre- and post-render-buffer
// trees, while a raw tcp client on the identical gapless close→reconnect pattern
// answered 20/20. `opened` separates "could not connect" from "server never
// answered"; the caller retries the former once before believing it.
function dispatch(id, eventName) {
  return new Promise((resolve) => {
    let settled = false;
    let opened = false;
    const socket = new WebSocket(WS_URL);
    const finish = (value) => {
      if (settled) { return; }
      settled = true;
      try { socket.close(); } catch (e) {}
      resolve({ value, opened });
    };
    socket.addEventListener("open", () => {
      opened = true;
      const frame = {
        type: "event",
        component: id,
        event: eventName,
        data: { targetId: id, targetClass: "sort" }
      };
      // a token-bound page echoes its render token on every event (the
      // engine reads it Out of the webui-config meta); the probe does the
      // same, or the server — rightly — refuses to route into the page's
      // render session.
      if (RENDER_TOKEN) { frame.token = RENDER_TOKEN; }
      socket.send(JSON.stringify(frame));
    });
    socket.addEventListener("message", (ev) => {
      try {
        const msg = JSON.parse(String(ev.data));
        if (msg.type === "update") { finish(msg); }
      } catch (e) {}
    });
    socket.addEventListener("error", () => finish(null));
    setTimeout(() => finish(null), 3000);
  });
}

const server = spawn(join(ROOT, ".build/debug/WebUIShowcaseServer"), ["--port", String(PORT)], {
  cwd: ROOT,
  stdio: ["ignore", "pipe", "pipe"],
});
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

try {
  const page = await waitForServer();
  if (page === null) {
    bad(`showcase server did not become ready on :${PORT}  run with --disable-sandbox? (no, this is node; check the port)`);
    console.log(serverLog.split("\n").slice(-6).join("\n"));
    process.exit(1);
  }
  ok("showcase server ready on :" + PORT);

  // precondition 2: the page must expose stable-id controls. zero targets is a FAIL.
  const ids = [...new Set([...page.matchAll(/data-component-id="([^"]+)"/g)].map((m) => m[1]))]
    .filter((id) => !/^c\d+$/.test(id));
  if (ids.length === 0) {
    bad("the served page exposes no stable-id controls  nothing to probe");
  } else {
    ok(`served page exposes ${ids.length} stable-id control(s)`);
  }

  // precondition 3: the page's render token, echoed from the webui-config
  // meta exactly as the engine echoes it. a token-bound server routes events
  // only into the session that minted its render, so a probe that does not
  // carry the token can never be answered — and a page that does not emit one
  // (a host that forgot to thread its render token) makes every click probe a
  // silent no-op. both failure modes are asserted away here.
  const configMeta = page.match(/<meta name="webui-config" content="([^"]*)"/);
  if (configMeta) {
    try {
      const cfg = JSON.parse(
        configMeta[1]
          .replace(/&quot;/g, '"').replace(/&lt;/g, "<")
          .replace(/&gt;/g, ">").replace(/&amp;/g, "&")
      );
      RENDER_TOKEN = cfg.renderToken || null;
    } catch (e) { /* unparseable config: treated as tokenless below */ }
  }
  if (RENDER_TOKEN) {
    ok(`served page carries a render token (${RENDER_TOKEN.slice(0, 6)}…)`);
  } else {
    bad("served page carries no render token — the host did not thread it, so clicks cannot route");
  }

  const preferred = ids.filter((id) => id.includes("-sort-"));
  const probes = (preferred.length ? preferred : ids).slice(0, 3);
  console.log(`  probing: ${probes.join(", ")}`);

  for (const id of probes) {
    let { value: reply, opened } = await dispatch(id, "click");
    if (!reply && !opened) {
      // the connect itself failed — retry once on a fresh socket before
      // treating it as evidence (see the note above `dispatch`)
      await new Promise((r) => setTimeout(r, 250));
      ({ value: reply, opened } = await dispatch(id, "click"));
      if (!reply && !opened) {
        bad(`${id} could not establish a websocket in two attempts  probe precondition failed, not a dispatch verdict`);
        continue;
      }
    }
    if (reply && reply.type === "update" && Array.isArray(reply.fragments) && reply.fragments.length > 0) {
      ok(`${id} dispatched and the server answered (${reply.fragments.length} fragment(s))`);
    } else if (reply) {
      bad(`${id} answered but with no fragments: ${JSON.stringify(reply).slice(0, 120)}`);
    } else {
      bad(`${id} sent an event and the server never answered within 3s  stable-id dispatch is broken`);
    }
    // let the previous socket finish tearing down before the next probe opens
    await new Promise((r) => setTimeout(r, 150));
  }

  // W3.2: the navigate round-trip. the engine already sends
  // {type:'navigate', url: location.pathname + location.search} on popstate;
  // a server that discards it (the pre-w3.2 `case .navigate: break`) answers
  // nothing and the probe times out. the router drives the answer: an
  // in-scope path re-renders into an `update` fragment of the page region
  // ("webui-page"); an out-of-scope path is answered with a `redirect`.
  function navigate(url) {
    return new Promise((resolve) => {
      let settled = false;
      let opened = false;
      const socket = new WebSocket(WS_URL);
      const finish = (value) => {
        if (settled) { return; }
        settled = true;
        try { socket.close(); } catch (e) {}
        resolve({ value, opened });
      };
      socket.addEventListener("open", () => {
        opened = true;
        socket.send(JSON.stringify({ type: "navigate", url }));
      });
      socket.addEventListener("message", (ev) => {
        try { finish(JSON.parse(String(ev.data))); } catch (e) {}
      });
      socket.addEventListener("error", () => finish(null));
      setTimeout(() => finish(null), 3000);
    });
  }

  // in scope: the served page path ("/") re-renders into a fragment patch.
  const inScope = await navigate("/");
  if (inScope.value && inScope.value.type === "update" && Array.isArray(inScope.value.fragments) && inScope.value.fragments.length > 0) {
    ok(`navigate "/" answered with an update fragment (${inScope.value.fragments.length} fragment(s), id "${inScope.value.fragments[0].id}")`);
  } else if (inScope.value) {
    bad(`navigate "/" answered but not with an update: ${JSON.stringify(inScope.value).slice(0, 120)}`);
  } else {
    bad(inScope.opened ? "navigate \"/\" never answered within 3s  navigate is still discarded" : "navigate probe could not connect");
  }
  await new Promise((r) => setTimeout(r, 150));

  // out of scope: an unrouted path is answered with a full-page redirect.
  const outScope = await navigate("/definitely/not/routed");
  if (outScope.value && outScope.value.type === "redirect" && typeof outScope.value.url === "string") {
    ok(`navigate "/definitely/not/routed" answered with a redirect`);
  } else if (outScope.value) {
    bad(`navigate to an unrouted path should redirect, got: ${JSON.stringify(outScope.value).slice(0, 120)}`);
  } else {
    bad(outScope.opened ? "navigate to an unrouted path never answered within 3s" : "navigate probe could not connect");
  }
} finally {
  server.kill("SIGTERM");
  await new Promise((r) => setTimeout(r, 300));
  if (!server.killed) { server.kill("SIGKILL"); }
}

console.log("");
console.log(`=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "SHOWCASE WS SMOKE PASS" : "SHOWCASE WS SMOKE FAIL");
process.exit(fail === 0 ? 0 : 1);