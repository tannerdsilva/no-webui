#!/usr/bin/env node
// designer/probes/e-island-decoder.mjs — lane-E wave-2 probe (t2.3 engine half).
//
// pure-function checks in node: extracts `decodeHotOpRecord` + `drainIslandOps`
// verbatim from the served engine asset (designer/assets/webui-engine.js — the
// bytes a client receives) and exercises them against crafted byte sequences
// and a stubbed export surface. no browser, no ws, deterministic.
//
// assertions:
//   decode: text/attr/insert/remove/move round-trip from the c-to-e record
//           table (little-endian, 0xffff sentinel, strict single record)
//   decode: invalid utf-8 -> U+FFFD (never a trap)
//   decode: reserved version/opcode -> throws (never guessed)
//   decode: truncated records -> throws
//   drain:  webui_take_ops() batches drained until 0, ops applied in order
//   drain:  batch length cap + malformed-record abort (defense in depth)
//   drain:  bytes are copied out before the next take_ops call (the freeze:
//           never hold a reference across calls — a memory that mutates
//           between calls must not corrupt the decode)

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const engine = readFileSync(join(ROOT, "designer/assets/webui-engine.js"), "utf8");

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };

// ---- extract a top-level function declaration verbatim (balanced braces) ----
function extractFn(src, name) {
  const start = src.indexOf("function " + name + "(");
  if (start === -1) throw new Error("function not found: " + name);
  const open = src.indexOf("{", start);
  let depth = 0;
  let i = open;
  for (; i < src.length; i++) {
    const ch = src[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) break;
    }
  }
  return src.slice(start, i + 1);
}

const decodeSrc = extractFn(engine, "decodeHotOpRecord");
const drainSrc = extractFn(engine, "drainIslandOps");

const warnings = [];
let _islandApply = null;
let _islandLog = (msg, level) => { warnings.push(level + ": " + msg); };

// decodeHotOpRecord is dependency-free (TextDecoder + RangeError only).
const decodeHotOpRecord = eval("(" + decodeSrc + ")");
// drainIslandOps closes over decodeHotOpRecord/_islandApply/_islandLog from this scope.
const drainIslandOps = eval("(" + drainSrc + ")");

// ---- tiny record builders mirroring HotOpCodec.encode (little-endian) ----
const u16 = (n) => [n & 255, (n >>> 8) & 255];
const u32 = (n) => [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255];
const utf8 = (s) => Array.from(Buffer.from(s, "utf8"));
const ident = (s) => u16(utf8(s).length).concat(utf8(s));
const optId = (s) => (s === null ? u16(0xffff) : ident(s));
const bulk = (s) => u32(utf8(s).length).concat(utf8(s));

const recText = (id, value) => [1, 1].concat(ident(id), bulk(value));
const recAttr = (id, name, value) => [1, 2].concat(ident(id), ident(name), bulk(value));
const recInsert = (parent, before, html) => [1, 3].concat(ident(parent), optId(before), bulk(html));
const recRemove = (id) => [1, 4].concat(ident(id));
const recMove = (id, before) => [1, 5].concat(ident(id), optId(before));

// ---- decode checks ----
{
  const bytes = Uint8Array.from(recText("t1", "abc"));
  const rec = decodeHotOpRecord(bytes, 0);
  check("text decodes", [rec.op.c, rec.op.id, rec.op.value, rec.next, bytes.length], ["text", "t1", "abc", bytes.length, bytes.length]);
}

function check(name, got, want) {
  if (JSON.stringify(got) === JSON.stringify(want)) ok(name);
  else bad(`${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
}

{
  const bytes = Uint8Array.from(recAttr("t2", "data-on", "yes"));
  const rec = decodeHotOpRecord(bytes, 0);
  check("attr decodes", [rec.op.c, rec.op.id, rec.op.name, rec.op.value, rec.next], ["attr", "t2", "data-on", "yes", bytes.length]);
}
{
  const bytes = Uint8Array.from(recInsert("par", null, "<b>hi</b>"));
  const rec = decodeHotOpRecord(bytes, 0);
  check("insert(append-at-end) decodes", [rec.op.c, rec.op.parent, rec.op.before, rec.op.html, rec.next], ["insert", "par", null, "<b>hi</b>", bytes.length]);
}
{
  const bytes = Uint8Array.from(recInsert("par", "anch", "x"));
  const rec = decodeHotOpRecord(bytes, 0);
  check("insert(anchor) decodes", [rec.op.c, rec.op.parent, rec.op.before, rec.op.html], ["insert", "par", "anch", "x"]);
}
{
  const bytes = Uint8Array.from(recRemove("r9"));
  const rec = decodeHotOpRecord(bytes, 0);
  check("remove decodes", [rec.op.c, rec.op.id, rec.next], ["remove", "r9", bytes.length]);
}
{
  const bytes = Uint8Array.from(recMove("m4", null));
  const rec = decodeHotOpRecord(bytes, 0);
  check("move(to-end sentinel) decodes", [rec.op.c, rec.op.id, rec.op.before], ["move", "m4", null]);
}
{
  const bytes = Uint8Array.from(recMove("m4", "m1"));
  const rec = decodeHotOpRecord(bytes, 0);
  check("move(anchor) decodes", [rec.op.c, rec.op.id, rec.op.before], ["move", "m4", "m1"]);
}
{
  // invalid utf-8 in the id slot -> U+FFFD, never a trap
  const bytes = Uint8Array.from([1, 1, 1, 0, 0xff, 1, 0, 0, 0, 0x41]);
  const rec = decodeHotOpRecord(bytes, 0);
  check("invalid utf-8 -> U+FFFD", rec.op.id, "\uFFFD");
}
{
  // invalid utf-8 continuation -> U+FFFD on the bad scalar; the following
  // byte decodes on its own (the codec consumes one byte per bad scalar)
  const bytes = Uint8Array.from([1, 1, 2, 0, 0xc3, 0x28, 1, 0, 0, 0, 0]);
  const rec = decodeHotOpRecord(bytes, 0);
  check("stray continuation -> U+FFFD", rec.op.id, "\uFFFD(");
}
{
  // reserved version -> throw
  const bytes = Uint8Array.from([2, 1, 1, 0, 0x61, 1, 0, 0, 0, 0]);
  let threw = null;
  try { decodeHotOpRecord(bytes, 0); } catch (e) { threw = e; }
  check("reserved version throws", threw !== null, true);
}
{
  // reserved opcode -> throw
  const bytes = Uint8Array.from([1, 9, 1, 0, 0x61]);
  let threw = null;
  try { decodeHotOpRecord(bytes, 0); } catch (e) { threw = e; }
  check("reserved opcode throws", threw !== null, true);
}
{
  // truncated id length field
  const bytes = Uint8Array.from([1, 1, 5, 0, 0x61]);
  let threw = null;
  try { decodeHotOpRecord(bytes, 0); } catch (e) { threw = e; }
  check("truncated record throws", threw !== null, true);
}
{
  // truncated bulk (len claims more bytes than present)
  const bytes = Uint8Array.from([1, 1, 1, 0, 0x61, 50, 0, 0, 0, 0x62, 0x63]);
  let threw = null;
  try { decodeHotOpRecord(bytes, 0); } catch (e) { threw = e; }
  check("truncated bulk throws", threw !== null, true);
}
{
  // multi-record frame decodes one record at a time, offsets chain
  const frame = Uint8Array.from(recRemove("r1").concat(recText("t1", "x")));
  const a = decodeHotOpRecord(frame, 0);
  const b = decodeHotOpRecord(frame, a.next);
  check("multi-record chain", [a.op.c, a.op.id, b.op.c, b.op.id, b.next], ["remove", "r1", "text", "t1", frame.length]);
}

// ---- drain checks ----
function mkExports(opts) {
  const mem = opts.memory || new Uint8Array(1024);
  const calls = opts.calls || [];
  const framePtr = opts.framePtr || 512;
  let round = 0;
  return {
    memory: { get buffer() { return mem.buffer; } },
    webui_frame_ptr: () => framePtr,
    webui_take_ops: () => {
      if (round >= calls.length) return 0;
      const c = calls[round];
      round++;
      if (typeof c === "number") return c;
      mem.set(c.bytes, framePtr);
      return c.len;
    },
  };
}

{
  const applied = [];
  _islandApply = (op) => { applied.push(op.c + ":" + op.id); };
  const b1 = recText("a", "1");
  const b2 = recRemove("b");
  const b3 = recMove("c", null);
  const ex = mkExports({
    calls: [
      { len: b1.concat(b2).length, bytes: b1.concat(b2) }, // batch 1: 2 records
      { len: b3.length, bytes: b3 },                       // batch 2: 1 record
      0,                                                   // batch 3: empty -> stop
    ],
  });
  const appliedCount = drainIslandOps("probe", ex);
  check("drain applies 3 ops across 2 batches then stops", [appliedCount, applied, warnings.length], [3, ["text:a", "remove:b", "move:c"], 0]);
}
{
  // the freeze: bytes are copied before the next take_ops call. the stub
  // overwrites the same frame region on every call; if drain held a reference,
  // the first batch would decode as the second batch's bytes.
  const applied = [];
  _islandApply = (op) => { applied.push(op.c + ":" + op.id); };
  const first = recText("first", "1");
  const second = recRemove("second");
  const ex = mkExports({
    calls: [
      { len: first.length, bytes: first },
      { len: second.length, bytes: second },
      0,
    ],
  });
  const n = drainIslandOps("probe", ex);
  check("no held references across take_ops calls", [n, applied], [2, ["text:first", "remove:second"]]);
}
{
  // batch length sanity cap: an island claiming > 262144 bytes is stopped
  const ex = mkExports({ calls: [262145, 0] });
  const n = drainIslandOps("probe", ex);
  check("oversized batch length stops the drain (0 applied)", n, 0);
}
{
  // malformed record inside a batch -> drain stops, warns once, partial apply kept
  const applied = [];
  _islandApply = (op) => { applied.push(op.c + ":" + op.id); };
  const good = Uint8Array.from(recRemove("ok1"));
  const badBytes = Uint8Array.from([1, 9, 1, 0, 0x61]); // reserved opcode
  const frame = new Uint8Array(good.length + badBytes.length);
  frame.set(good, 0);
  frame.set(badBytes, good.length);
  warnings.length = 0;
  const ex = mkExports({ calls: [{ len: frame.length, bytes: frame }, 0] });
  const n = drainIslandOps("probe", ex);
  check("malformed record aborts the drain with a warning", [n, applied, warnings.filter((w) => w.indexOf("malformed") !== -1).length], [1, ["remove:ok1"], 1]);
}
{
  // no webui_take_ops export (wave-1 islands) -> drain is a no-op
  const ex = { webui_frame_ptr: () => 0 };
  const n = drainIslandOps("probe", ex);
  check("island without take_ops drains to zero", n, 0);
}

console.log("");
if (fail === 0) console.log(`e-island-decoder: ${pass} PASS, 0 FAIL`);
else console.log(`e-island-decoder: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
