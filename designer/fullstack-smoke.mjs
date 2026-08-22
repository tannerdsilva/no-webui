#!/usr/bin/env node
// Full-stack deployment smoke test (live WS round-trip).
//
// Connects to the deployed server, verifies the WebSocket upgrade, then drives
// real events through the wire protocol the WebUIRuntime uses and asserts the
// Swift EventRouter patches the DOM via FragmentUpdate. This proves the whole
// stack (HTTP + WS upgrade + event routing + fragment rendering) deploys.
//
// Component ids are extracted in document order, which matches render order:
//   [0]=btn-dec [1]=btn-inc [2]=btn-reset [3]=btn-pdec [4]=btn-pinc [5]=echo-input

const BASE = "http://127.0.0.1:9123";
const WS = "ws://127.0.0.1:9123/ws";

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 1. Page serves the full-stack app with event wiring + runtime bootstrap.
const html = await (await fetch(BASE + "/")).text();
if (html.includes("Full-Stack Smoke Test")) ok("page serves full-stack design-system app");
else bad("page title wrong");
if (html.includes("data-component-id")) ok("event-delegation attributes present");
else bad("no data-component-id");
if (html.includes("WebUIRuntime.init")) ok("runtime auto-bootstraps (WebUIRuntime.init)");
else bad("runtime bootstrap missing");
if (html.includes('id="counter-value"') && html.includes('id="echo-input"')) ok("interactive view ids present");
else bad("interactive view ids missing");

// 2. Real WebSocket — proves the upgrade + WS stack.
const messages = [];
const ws = new WebSocket(WS);
const opened = await new Promise((resolve) => {
  ws.onopen = () => resolve(true);
  ws.onerror = () => resolve(false);
  ws.onmessage = (e) => messages.push(JSON.parse(e.data));
  setTimeout(() => resolve(false), 5000);
});
if (opened) ok("WebSocket handshake succeeded (101 switching protocols)");
else { bad("WebSocket did not open"); process.exit(1); }
await sleep(150);

// 3. ping → pong
ws.send(JSON.stringify({ type: "ping" }));
await sleep(250);
if (messages.some((m) => m.type === "pong")) ok("ping → pong round-trip");
else bad(`ping got no pong; got ${JSON.stringify(messages)}`);

// 4. Component ids in document order.
const ids = [...html.matchAll(/data-component-id="([^"]+)"/g)].map((m) => m[1]);
if (ids.length >= 6) ok(`found ${ids.length} component ids in document order`);
else bad(`expected >=6 component ids, found ${ids.length}: ${JSON.stringify(ids)}`);
const [DEC, INC, RESET, PDEC, PINC, ECHO] = ids;

// Consume messages so each expectation matches the NEXT update, not a stale one.
let cursor = 0;
const expectUpdate = (targetId) =>
  new Promise((resolve) => {
    const t0 = Date.now();
    const check = () => {
      const hit = messages
        .slice(cursor)
        .find((m) => m.type === "update" && m.fragments?.some((f) => f.id === targetId));
      if (hit) {
        cursor = messages.indexOf(hit) + 1;
        return resolve(hit);
      }
      if (Date.now() - t0 > 2000) return resolve(null);
      setTimeout(check, 50);
    };
    check();
  });

// 5. Click + → counter 0 → 1
ws.send(JSON.stringify({ type: "event", component: INC, event: "click", data: {} }));
let upd = await expectUpdate("counter-value");
if (upd && upd.fragments[0].html.includes(">1<")) ok("click + → #counter-value patched to 1");
else bad(`+ did not patch counter: ${JSON.stringify(upd)}`);

// 6. Click + again → 2, then reset → 0
ws.send(JSON.stringify({ type: "event", component: INC, event: "click", data: {} }));
upd = await expectUpdate("counter-value");
if (upd && upd.fragments[0].html.includes(">2<")) ok("click + again → counter 2");
else bad(`+2 did not patch to 2: ${JSON.stringify(upd)}`);

ws.send(JSON.stringify({ type: "event", component: RESET, event: "click", data: {} }));
upd = await expectUpdate("counter-value");
if (upd && upd.fragments[0].html.includes(">0<")) ok("click Reset → counter back to 0");
else bad(`reset did not zero counter: ${JSON.stringify(upd)}`);

// 7. Progress +10% → re-renders #progress-value with a new progress bar
ws.send(JSON.stringify({ type: "event", component: PINC, event: "click", data: {} }));
upd = await expectUpdate("progress-value");
if (upd && upd.fragments[0].html.includes('role="progressbar"')) ok("click +10% → #progress-value re-rendered");
else bad(`+10% did not patch progress: ${JSON.stringify(upd)}`);

// 8. Echo: input event → server echoes value to #echo-out
ws.send(JSON.stringify({ type: "event", component: ECHO, event: "input", data: { value: "hello webui" } }));
upd = await expectUpdate("echo-out");
if (upd && upd.fragments[0].html.includes("hello webui")) ok("type 'hello webui' → echoed to #echo-out over WS");
else bad(`echo did not round-trip: ${JSON.stringify(upd)}`);

ws.close();
console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "FULL-STACK SMOKE PASS" : "FULL-STACK SMOKE FAIL");
process.exit(fail === 0 ? 0 : 1);
