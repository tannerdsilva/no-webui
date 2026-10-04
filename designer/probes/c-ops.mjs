#!/usr/bin/env node
// designer/probes/c-ops.mjs — lane-C probe: the probe island's real abi (t2.5 wave 2).
//
// loads WebUIProbeIsland.wasm directly in node (no engine, no server), then
// drives the exports exactly as the engine would:
//   webui_render_region → webui_on_event → webui_take_ops (drain until 0)
//   webui_state_save / webui_state_restore across a fresh instance (remount).
//
// the op batches are asserted byte-for-byte against HotOpCodec fixtures — the
// record-v1 layout from continuum-notes/c-to-e.md (little-endian u16/u32,
// before sentinel 0xffff). these are the same ops the native suite pins in
// Tests/WebUISharedCoreTests + Tests/WebUIIslandCoreTests.
//
// usage: node designer/probes/c-ops.mjs  (artifact path resolvable from the repo root)

import { readFileSync } from "node:fs";
import { WASI } from "node:wasi";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const WASM = join(ROOT, ".build/out/Products/Release-webassembly-wasm32/WebUIProbeIsland.wasm");

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

// module-level so both the wasm plumbing and the HotOpCodec fixtures share it.
const utf8 = (s) => new TextEncoder().encode(s);
const utf8d = (u8) => new TextDecoder().decode(u8);

// ── wasm plumbing ──────────────────────────────────────────────────────────

function instantiate() {
  const bytes = readFileSync(WASM);
  const wasi = new WASI({ version: "preview1", args: [], env: {}, preopens: {} });
  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes), {
    wasi_snapshot_preview1: wasi.wasiImport,
  });
  // optional for a reactor we drive directly: node's initialize requires an
  // exported `_initialize`, which the stripped embedded runtime does not have.
  try { wasi.initialize(instance); } catch { /* reactor — no _initialize */ }
  const e = instance.exports;
  const mem = () => new Uint8Array(e.memory.buffer);

  const island = {
    input(ptr, len, text) {
      const bytes = utf8(text);
      const view = mem();
      view.set(bytes, ptr);
      return { ptr, len: bytes.length };
    },
    invoke(name, text) {
      // the ptr call first: Swift lazy-allocates the buffers on first use,
      // which can grow linear memory and detach a previous ArrayBuffer view —
      // so always fetch a fresh view after any wasm call.
      const ptr = e.webui_input_ptr();
      if (text !== undefined && text !== null) {
        mem().set(utf8(text), ptr);
      }
      return this.invokeAfter(name, ptr, text === undefined || text === null ? 0 : utf8(text).length);
    },
    invokeAfter(name, ptr, len) {
      const ret = e[name](ptr, len);
      const fptr = e.webui_frame_ptr();
      const flen = e.webui_frame_len();
      return { ret, frame: mem().slice(fptr, fptr + flen) };
    },
    readFrameText() {
      const fptr = e.webui_frame_ptr();
      const flen = e.webui_frame_len();
      return utf8d(mem().slice(fptr, fptr + flen));
    },
    takeOps() {
      const n = e.webui_take_ops();
      if (n === 0) return null;
      const fptr = e.webui_frame_ptr();
      return mem().slice(fptr, fptr + n);
    },
    render(json) { return this.invoke("webui_render_region", json); },
    event(json) { return this.invoke("webui_on_event", json); },
    save() { return this.invoke("webui_state_save"); },
    restore(json) { return this.invoke("webui_state_restore", json); },
  };
  return island;
}

// ── HotOpCodec fixtures (record-v1, little-endian) ────────────────────────

const u16 = (n) => [n & 0xff, (n >> 8) & 0xff];
const u32 = (n) => [n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff];
const idf = (s) => { const b = [...utf8(s)]; return [...u16(b.length), ...b]; };
const bulk = (s) => { const b = [...utf8(s)]; return [...u32(b.length), ...b]; };
const recText = (id, value) => [1, 1, ...idf(id), ...bulk(value)];
const recRemove = (id) => [1, 4, ...idf(id)];
const recInsert = (parent, before, html) => {
  const beforeField = before === undefined || before === null ? [0xff, 0xff] : idf(before);
  return [1, 3, ...idf(parent), ...beforeField, ...bulk(html)];
};
const bytes = (arr) => Uint8Array.from(arr);

// ── helpers ───────────────────────────────────────────────────────────────

const eq = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
function drainAll(island) {
  const batches = [];
  let n;
  while ((n = island.takeOps()) !== null) batches.push(n);
  return batches;
}

console.log(`c-ops: probing ${WASM}`);
const island = instantiate();

// ── 1. mount: render_region produces the typed region html, no stray ops ──

island.render('{"name":"probe","args":{}}');
let html = island.readFrameText();
if (html.includes('id="probe-counter"') && html.includes('class="island__counter">0<') && html.includes('data-island-renders="1"')) {
  ok("mount: region html stamps counter 0, renders=1");
} else {
  bad(`mount html: ${html.slice(0, 160)}`);
}
if (island.takeOps() === null) {
  ok("mount: take_ops is empty right after mount");
} else {
  bad("mount: unexpected ops after a bare mount");
}

// ── 2. op-stream out: engineered events → byte-exact record-v1 batches ──
// running state tracker: counter starts 0; every event below is against the
// live island state, and each event's batch is drained before the next.

// ArrowUp → text("probe-counter","1"); byte-exact hard fixture.
const expectedUp1 = bytes([1, 1, 13, 0, 0x70, 0x72, 0x6f, 0x62, 0x65, 0x2d, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x65, 0x72, 1, 0, 0, 0, 0x31]);
island.event('{"type":"key","key":"ArrowUp"}');
const b1 = island.takeOps();
if (b1 && eq(b1, expectedUp1)) {
  ok("key ArrowUp → text('probe-counter','1') record — byte-exact");
} else {
  bad(`ArrowUp batch: ${b1 ? [...b1] : "empty"}`);
}
if (island.takeOps() === null) ok("drain returns 0 after one batch");
else bad("drain did not return 0 after a single-op batch");

// ArrowDown twice (counter 1 → 0 → -1) → two back-to-back text records.
island.event('{"type":"key","key":"ArrowDown"}');
island.event('{"type":"key","key":"ArrowDown"}');
const batch2op = drainAll(island);
const fixtureDown2 = [recText("probe-counter", "0"), recText("probe-counter", "-1")];
const expectedDown2 = bytes(fixtureDown2.flat());
if (batch2op.length === 1 && eq(batch2op[0], expectedDown2)) {
  ok("two ArrowDown events → one batch with text 0 and text -1 (per-event records)");
} else {
  bad(`ArrowDown x2 batches: ${JSON.stringify(batch2op.map((b) => [...b]))}`);
}

// click probe-inc (counter -1 → 0) → text("probe-counter","0")
island.event('{"type":"click","key":"probe-inc"}');
const binc = island.takeOps();
if (binc && eq(binc, bytes(recText("probe-counter", "0")))) {
  ok("click probe-inc → text('probe-counter','0') — fixture-built");
} else {
  bad(`click inc batch: ${binc ? [...binc] : "empty"}`);
}

// input → addItem inserts a NEW_LIST_ROW; record carries parent + escaped html.
const itemValue = "todo <one>";
island.event('{"type":"input","key":"probe-field","data":{"value":"' + itemValue + '"}}');
const bAdd = island.takeOps();
const fixtureAdd = bytes(recInsert("probe-list", null, '<li id="probe-item-k0" class="island__item">todo &lt;one&gt;</li>'));
if (bAdd && eq(bAdd, fixtureAdd)) {
  ok("input probe-field → insert(parent:'probe-list', before:null, escaped html) — byte-exact");
} else {
  bad(`addItem batch: ${bAdd ? [...bAdd] : "empty"} vs ${[...fixtureAdd]}`);
}

// ── 3. multi-record back-to-back single batch ──
// add a second item so two inserts queue, then one take_ops returns both records.
island.event('{"type":"input","key":"probe-field","data":{"value":"second"}}');
island.event('{"type":"input","key":"probe-field","data":{"value":"third"}}');
const multi = drainAll(island);
const fixtureMulti = [
  recInsert("probe-list", null, '<li id="probe-item-k1" class="island__item">second</li>'),
  recInsert("probe-list", null, '<li id="probe-item-k2" class="island__item">third</li>'),
];
const expectedMulti = bytes(fixtureMulti.flat());
if (multi.length === 1 && eq(multi[0], expectedMulti)) {
  ok("two queued inserts drain as ONE back-to-back batch (records contiguous)");
} else {
  bad(`multi-record: ${JSON.stringify(multi.map((b) => [...b]))}`);
}

// ── 4. events in: unknown / malformed payloads are noops on the stream ──

island.event('{"type":"hover","key":"probe-inc"}');
island.event('this is not json');
island.event('{"key":"ArrowUp"}');
if (drainAll(island).length === 0) {
  ok("unknown/malformed events emit no ops (drain is empty)");
} else {
  bad("a noop event leaked ops into the stream");
}

// ── 5. clear: one remove per item, back-to-back ──
// state now: counter -1 (after click inc), items k0,k1,k2.
island.event('{"type":"click","key":"probe-clear"}');
const bClear = drainAll(island);
const fixtureClear = [
  recRemove("probe-item-k0"),
  recRemove("probe-item-k1"),
  recRemove("probe-item-k2"),
].flat();
if (bClear.length === 1 && eq(bClear[0], bytes(fixtureClear))) {
  ok("click probe-clear → remove k0,k1,k2 as one back-to-back batch");
} else {
  bad(`clear batch: ${JSON.stringify(bClear.map((b) => [...b]))}`);
}

// ── 6. state channel: save → (fresh instance) restore → remount continues ──

// current live state: counter=0, items cleared (empty), nextItemKey=3.
island.event('{"type":"key","key":"ArrowUp"}'); // counter → 1
island.event('{"type":"input","key":"probe-field","data":{"value":"stateful"}}'); // k3
drainAll(island); // leave the stream empty before the save/restore checks
island.save();
const snapshotText = island.readFrameText();
const snapshot = JSON.parse(snapshotText);
if (snapshot.probe && snapshot.probe.counter === 1 && snapshot.probe.items.length === 1 && snapshot.probe.items[0].key === "k3" && snapshot.probe.items[0].value === "stateful") {
  ok(`state_save: snapshot json carries counter=1 + keyed list [k3] (${snapshotText.length} B)`);
} else {
  bad(`state_save snapshot: ${snapshotText}`);
}

// a remount = a fresh wasm instance (retained state wiped) + restore + render.
const fresh = instantiate();
fresh.restore(snapshotText);
const ack = fresh.readFrameText();
if (ack.includes('"ok":true') && ack.includes('"restored":' + snapshotText.length)) {
  ok("state_restore acks the byte length");
} else {
  bad(`state_restore ack: ${ack}`);
}
fresh.render('{"name":"probe","args":{}}');
html = fresh.readFrameText();
if (html.includes('class="island__counter">1<') && html.includes('id="probe-item-k3"') && html.includes('>stateful<')) {
  ok("remount: restored counter + keyed list survive the fresh instance (RETAINED_OPEN generalized)");
} else {
  bad(`remount html: ${html.slice(0, 220)}`);
}
// and the restored island still emits ops against the live ids
fresh.event('{"type":"key","key":"ArrowUp"}');
const bRestored = fresh.takeOps();
if (bRestored && eq(bRestored, bytes(recText("probe-counter", "2")))) {
  ok("post-remount event → text('probe-counter','2') — op stream live again");
} else {
  bad(`post-remount op: ${bRestored ? [...bRestored] : "empty"}`);
}

// defensive: save/restore rejects garbage and keeps live state
island.restore("garbage");
if (drainAll(island).length === 0) ok("garbage restore leaves the stream empty (state not wiped)");
else bad("garbage restore corrupted the stream");

console.log(`\nc-ops: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
