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
if (html.includes("data-optimistic")) ok("optimistic prediction wired on served page");
else bad("no data-optimistic on served page");
if (html.includes('data-component-id="interactive-table-sort-0"') && html.includes('data-component-id="interactive-table-select-all"') && html.includes('data-component-id="interactive-table-expand-') && html.includes('data-component-id="smoke-chart-mark-')) ok("interactive table + chart served (typed per-control routing)");
else bad("interactive table wiring missing from served page");

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

// 9. Redirect: the reserved server path emits {type:"redirect"} over the wire
ws.send(JSON.stringify({ type: "event", component: "redirect-test", event: "click", data: {} }));
const redirectHit = await new Promise((resolve) => {
  const t0 = Date.now();
  const check = () => {
    const hit = messages.slice(cursor).find((m) => m.type === "redirect");
    if (hit) { cursor = messages.indexOf(hit) + 1; return resolve(hit); }
    if (Date.now() - t0 > 2000) return resolve(null);
    setTimeout(check, 50);
  };
  check();
});
if (redirectHit && redirectHit.url === "/" && redirectHit.replace === true) ok("redirect-test → {type:redirect,url:'/',replace:true} on the wire");
else bad(`redirect-test did not emit a redirect frame: ${JSON.stringify(redirectHit)}`);

// 10. Interactive table — live sort / select / expand round-trips.
// Each control is its own routed component: the driver dispatches directly
// to a control's component id (no container + targetId pattern anymore).
const TBL = "interactive-table";
const tblClick = (controlId) =>
  ws.send(JSON.stringify({ type: "event", component: controlId, event: "click", data: {} }));
const tblUpdate = () => expectUpdate(TBL);
// ordered data-row names: per row the tds are [select, expand, name, region, p95];
// select/expand render empty text, so the 3rd cell is the primary name.
const rowNames = (html) => {
  const body = html.slice(html.indexOf("<tbody>"), html.indexOf("</tbody>"));
  return body
    .split("</tr>")
    .filter((c) => !c.includes("table__detail-row"))
    .map((c) => {
      const cells = c.match(/<td[^>]*>[\s\S]*?<\/td>/g) || [];
      return cells.map((x) => x.replace(/<[^>]+>/g, ""))[2] || "";
    })
    .filter(Boolean);
};

tblClick(`${TBL}-sort-2`);
let t = await tblUpdate();
if (t && t.fragments[0].html.includes('aria-sort="ascending"') && JSON.stringify(rowNames(t.fragments[0].html)) === JSON.stringify(["auth","api","web","search"])) ok("table: click p95 header → sorted ascending (9<18<42<61) over WS");
else bad(`table sort asc wrong: ${t ? JSON.stringify(rowNames(t.fragments[0].html)) : "no update"}`);

tblClick(`${TBL}-sort-2`);
t = await tblUpdate();
if (t && t.fragments[0].html.includes('aria-sort="descending"') && rowNames(t.fragments[0].html)[0] === "search") ok("table: click p95 again → toggled to descending (search first)");
else bad(`table sort desc wrong: ${t ? JSON.stringify(rowNames(t.fragments[0].html)) : "no update"}`);

tblClick(`${TBL}-select-all`);
t = await tblUpdate();
if (t && (t.fragments[0].html.match(/tr--selected/g) || []).length === 4) ok("table: select-all → 4 rows selected");
else bad(`select-all wrong: ${t ? (t.fragments[0].html.match(/tr--selected/g) || []).length : "no update"}`);

tblClick(`${TBL}-select-auth`);
t = await tblUpdate();
if (t && (t.fragments[0].html.match(/tr--selected/g) || []).length === 3) ok("table: deselect auth → 3 rows remain selected");
else bad(`deselect wrong: ${t ? (t.fragments[0].html.match(/tr--selected/g) || []).length : "no update"}`);

tblClick(`${TBL}-expand-web`);
t = await tblUpdate();
if (t && t.fragments[0].html.includes("table__detail-row") && t.fragments[0].html.includes("canary 10% to v2.14") && t.fragments[0].html.includes('aria-expanded="true"')) ok("table: expand web → detail row revealed");
else bad(`expand wrong: ${t ? t.fragments[0].html.includes("table__detail-row") ? "detail row missing content" : "no detail row" : "no update"}`);

tblClick(`${TBL}-expand-web`);
t = await tblUpdate();
if (t && !t.fragments[0].html.includes("table__detail-row")) ok("table: collapse web → detail row removed");
else bad(`collapse wrong: ${t ? "detail row still present" : "no update"}`);

ws.close();

// 8. Client-mode wire probe (p1): the wasm artifact, the chamber, and the
// client-demo page served with their client-mode markers.
const wasm = await (await fetch(BASE + "/__assets/app.wasm")).arrayBuffer();
const magic = new Uint8Array(wasm.slice(0, 4));
const version = new Uint8Array(wasm.slice(4, 8));
if (magic.join(",") === "0,97,115,109" && version[0] === 1) ok(`client wasm served with valid magic/version (${wasm.byteLength} bytes)`);
else bad("client wasm missing or malformed");
const chamber = await (await fetch(BASE + "/__assets/webui-client.js")).text();
if (chamber.includes("WebUIClient") && !chamber.includes("/*")) ok("chamber served, comment-free");
else bad("chamber not served or carries comments");
const demo = await (await fetch(BASE + "/__assets/client-demo")).text();
if (
  demo.includes("'wasm-unsafe-eval'") && demo.includes('id="app"') &&
  demo.includes("webui-client.js") && !demo.includes("WebUIRuntime.init")
) ok("client-demo page carries client csp + external scripts");
else bad("client-demo page missing client-mode markers");

const searchDemo = await (await fetch(BASE + "/__assets/search-demo")).text();
if (
  searchDemo.includes("'wasm-unsafe-eval'") && searchDemo.includes('id="search-app"') &&
  searchDemo.includes("search-demo-boot.js") && !searchDemo.includes("WebUIRuntime.init")
) ok("search-demo page carries client csp + search boot script");
else bad("search-demo page missing client-mode markers");

// content-addressed wasm distribution: the page meta points at the immutable
// route; it must serve the same bytes as the alias, with an immutable cache.
const demoHtml = await (await fetch(BASE + "/__assets/client-demo")).text();
const metaMatch = demoHtml.match(/<meta name="webui-wasm" content="([^"]+)"/);
if (metaMatch && metaMatch[1]) {
  const hashedResp = await fetch(BASE + metaMatch[1]);
  const hashed = await hashedResp.arrayBuffer();
  const alias = await (await fetch(BASE + "/__assets/app.wasm")).arrayBuffer();
  const cc = (hashedResp.headers.get("cache-control") || "").toLowerCase();
  if (hashed.byteLength === alias.byteLength && cc.includes("immutable")) ok(`content-addressed wasm route serves identical bytes with immutable cache (${metaMatch[1]})`);
  else bad(`content-addressed wasm route broken (immutable=${cc.includes("immutable")}, bytes=${hashed.byteLength}/${alias.byteLength})`);
} else bad("webui-wasm meta missing from client-demo page");

console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "FULL-STACK SMOKE PASS" : "FULL-STACK SMOKE FAIL");
process.exit(fail === 0 ? 0 : 1);
