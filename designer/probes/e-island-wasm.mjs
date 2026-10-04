// lane-e scratch: minimal wasm module assembler + the "e2e" probe island (loop-free).
// self-tests in node with stub host imports. mirrors C's wave-2 probe island export
// surface (Sources/WebUIProbeIsland/main.swift) + the frozen webui_take_ops contract,
// imports the full t2.1 host set, and emits static canned op batches (each dynamic
// value is a single patched byte). uses bulk memory.copy for the html copy.

function uleb(n) {
  const out = [];
  do { let b = n & 0x7f; n >>>= 7; if (n) b |= 0x80; out.push(b); } while (n);
  return out;
}
function sleb(n) {
  const out = [];
  let more = true;
  while (more) {
    let b = n & 0x7f;
    n >>= 7;
    if ((n === 0 && (b & 0x40) === 0) || (n === -1 && (b & 0x40) !== 0)) more = false;
    else b |= 0x80;
    out.push(b);
  }
  return out;
}
class B {
  constructor() { this.b = []; }
  u8(...v) { for (const x of v) this.b.push(x & 0xff); return this; }
  raw(a) { for (const x of a) this.b.push(x & 0xff); return this; }
  i32c(n) { this.b.push(0x41); this.b.push(...sleb(n)); return this; }
  str(s) { const e = new TextEncoder().encode(s); this.b.push(...e); return this; }
  bytes() { return this.b; }
}
const INS = {
  local_get: (i) => [0x20, i], local_set: (i) => [0x21, i],
  global_get: (i) => [0x23, i], global_set: (i) => [0x24, i],
  i32_store8: () => [0x3a, 0, 0], i32_store16: () => [0x3b, 0, 0], i32_store: () => [0x36, 0, 0],
  i32_load8_u: () => [0x2d, 0, 0], i32_load: () => [0x28, 0, 0],
  i32_add: () => [0x6a], i32_and: () => [0x71], i32_eqz: () => [0x45], i32_ne: () => [0x47],
  trunc_f64_s: () => [0xab],
  call: (i) => [0x10, ...uleb(i)],
  if_: () => [0x04, 0x40], if_i32: () => [0x04, 0x7f], else_: () => [0x05], end: () => [0x0b],
  drop: () => [0x1a], ret: () => [0x0f], memcopy: () => [0xfc, 0x0a, 0x00, 0x00],
};
export const LAYOUT = { INPUT: 0x0000, FRAME: 0x1000, TPL: 0x4000 };

// ---- record/string helpers to compute static byte arrays ----
const enc = (s) => new TextEncoder().encode(s);
const u16 = (n) => [n & 255, (n >>> 8) & 255];
const u32 = (n) => [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255];

export function buildProbeWasm() {
  const L = LAYOUT;
  const FRAME = L.FRAME;
  const TPL = L.TPL;

  // static content
  const lbl = "lbl";
  const key = "probe-key";
  const okJson = '{"ok":true}';
  // mount html with five 1-char slots (data-e, data-t, data-now, data-r, data-s)
  const html = '<span id="' + lbl + '" data-e="0" data-t="0" data-now="0" data-r="0" data-s="0"></span>';
  // text op batch (served for events): text(id=lbl, value=1 byte) then attr(id=lbl, name="data-now", value=1 byte)
  const evtBatch = [
    1, 1, ...u16(enc(lbl).length), ...enc(lbl), ...u32(1), 0x30,      // text "0"
    1, 2, ...u16(enc(lbl).length), ...enc(lbl), ...u16(enc("data-now").length), ...enc("data-now"), ...u32(1), 0x30, // attr data-now="0"
  ];
  const tickBatch = [1, 2, ...u16(enc(lbl).length), ...enc(lbl), ...u16(enc("data-tick").length), ...enc("data-tick"), ...u32(1), 0x30]; // attr data-tick="0"
  const snap = enc('{"events":0}');
  const ok = enc(okJson);

  // static regions inside FRAME area (below TPL):
  //   FRAME+0x000 ..+001FF : html (len <= 512)
  //   FRAME+0x200 ..+2xx   : evtBatch
  //   FRAME+0x280 ..       : tickBatch
  //   FRAME+0x300 ..       : snapshot
  //   FRAME+0x340 ..       : ok
  //   TPL (0x4000)         : the key string (also html source for memcopy? html copies from TPL area)
  // We'll keep html at TPL too as the source for memory.copy, and the canned
  // batches preloaded at their FRAME offsets (they never need copying).
  const segHtml = TPL;
  const segKey = TPL + html.length;
  const SEG_EV = FRAME + 0x200;
  const SEG_TICK = FRAME + 0x280;
  const SEG_SNAP = FRAME + 0x300;
  const SEG_OK = FRAME + 0x340;
  const DATA = [
    { off: segHtml, b: enc(html) },
    { off: segKey, b: enc(key) },
    { off: SEG_EV, b: evtBatch },
    { off: SEG_TICK, b: tickBatch },
    { off: SEG_SNAP, b: snap },
    { off: SEG_OK, b: ok },
  ];
  const HTML_LEN = enc(html).length;
  const EV_LEN = evtBatch.length;
  const TICK_LEN = tickBatch.length;
  const SNAP_LEN = snap.length;
  const OK_LEN = ok.length;
  const KEY_LEN = enc(key).length;

  // slot offsets inside html (digit position of each attribute value)
  const eSlot = html.indexOf("0", html.indexOf("data-e=\""));
  const tSlot = html.indexOf("0", html.indexOf("data-t=\""));
  const nSlot = html.indexOf("0", html.indexOf("data-now=\""));
  const rSlot = html.indexOf("0", html.indexOf("data-r=\""));
  const sSlot = html.indexOf("0", html.indexOf("data-s=\""));
  // slot offsets inside evtBatch: value byte of the text record = index 11; value byte of attr = last
  const EV_EVTSLOT = 11;
  const EV_CLOCKSLOT = evtBatch.length - 1;
  // slot in tickBatch: value byte = last
  const TICK_SLOT = tickBatch.length - 1;
  // slot in snapshot: the '0'
  const SNAP_SLOT = enc('{"events":').length;

  // ---- types ----
  // 0 ()->i32 · 1 (i32,i32)->i32 · 2 ()->f64 · 3 (i32)->i32 · 4 (i32,i32,i32,i32)->i32 · 5 ()->void
  const types = [
    [0x60, [], [0x7f]],
    [0x60, [0x7f, 0x7f], [0x7f]],
    [0x60, [], [0x7c]],
    [0x60, [0x7f], [0x7f]],
    [0x60, [0x7f, 0x7f, 0x7f, 0x7f], [0x7f]],
    [0x60, [], []],
  ];
  const typeB = new B();
  {
    typeB.raw(uleb(types.length));
    for (const [tag, params, results] of types) {
      typeB.u8(tag).raw(uleb(params.length));
      for (const p of params) typeB.u8(p);
      typeB.raw(uleb(results.length));
      for (const r of results) typeB.u8(r);
    }
  }

  // ---- imports (module "continuum"): 0 log · 1 now_ms · 2 raf · 3 store_get · 4 store_set · 5 surface ----
  const IMPORTS = [
    ["webui_log", 1], ["webui_now_ms", 2], ["webui_raf", 3],
    ["webui_store_get", 1], ["webui_store_set", 4], ["webui_surface", 0],
  ];
  const importB = new B();
  {
    const mod = "continuum";
    importB.raw(uleb(IMPORTS.length));
    for (const [nm, ti] of IMPORTS) {
      importB.raw(uleb(mod.length)).str(mod);
      importB.raw(uleb(nm.length)).str(nm);
      importB.u8(0x00).raw(uleb(ti));
    }
  }

  // ---- functions: internal 6..16 ----
  //  6 input_ptr ()->i32 · 7 frame_ptr ()->i32 · 8 frame_len ()->i32
  //  9 render_region (i32,i32)->i32 · 10 on_event (i32,i32)->i32
  // 11 take_ops ()->i32 · 12 state_save ()->i32 · 13 state_restore (i32,i32)->i32
  // 14 frame_tick (i32)->i32 · 15 _start ()->void
  const FUNCS = [0, 0, 0, 1, 1, 0, 0, 1, 3, 5];
  const funcSec = new B();
  { funcSec.raw(uleb(FUNCS.length)); for (const ft of FUNCS) funcSec.raw(uleb(ft)); }

  // ---- memory: 1 page ----
  const memSec = new B().u8(0x01).u8(0x00).raw(uleb(1));

  // ---- globals: 0 frameLen · 1 events · 2 ticks · 3 restoreOk · 4 served · 5 clockLow ----
  const globSec = new B();
  { globSec.raw(uleb(6)); for (let i = 0; i < 6; i++) globSec.u8(0x7f).u8(0x01).i32c(0).u8(0x0b); }

  // ---- exports ----
  const EXPORTS = [
    ["memory", 0x02, 0],
    ["webui_input_ptr", 0x00, 6], ["webui_frame_ptr", 0x00, 7], ["webui_frame_len", 0x00, 8],
    ["webui_render_region", 0x00, 9], ["webui_on_event", 0x00, 10], ["webui_take_ops", 0x00, 11],
    ["webui_state_save", 0x00, 12], ["webui_state_restore", 0x00, 13],
    ["webui_frame_tick", 0x00, 14], ["_start", 0x00, 15],
  ];
  const expSec = new B();
  {
    expSec.raw(uleb(EXPORTS.length));
    for (const [nm, kind, idx] of EXPORTS) {
      expSec.raw(uleb(nm.length)).str(nm);
      expSec.u8(kind).raw(uleb(idx));
    }
  }

  // ---- bodies ----
  const decl = (n) => (n === 0 ? new B().u8(0x00) : new B().u8(0x01).raw(uleb(n)).u8(0x7f));
  const bd = (locals, fn) => { const b = decl(locals); fn(b); b.u8(0x0b); return b; };

  const inputPtrBody = bd(0, (b) => { b.i32c(L.INPUT).raw(INS.ret()); });
  const framePtrBody = bd(0, (b) => { b.i32c(FRAME).raw(INS.ret()); });
  const frameLenBody = bd(0, (b) => { b.raw(INS.global_get(0)).raw(INS.ret()); });

  // render_region(p,l) -> i32  (local 2 = g from store_get)
  const renderBodyFinal = bd(2, (b) => {
    b.i32c(segKey).i32c(KEY_LEN).raw(INS.call(3)).raw(INS.local_set(2)); // g = store_get
    b.i32c(FRAME).i32c(segHtml).i32c(HTML_LEN).raw(INS.memcopy());        // copy html
    // store slot: '1' if g != 0 else '0'
    b.raw(INS.local_get(2)).raw(INS.i32_eqz()).raw(INS.if_());
    b.i32c(FRAME + sSlot).i32c(0x30).raw(INS.i32_store8());          // '0'
    b.raw(INS.else_());
    b.i32c(FRAME + sSlot).i32c(0x31).raw(INS.i32_store8());          // '1'
    b.raw(INS.end());
    // patch 4 digit slots
    b.i32c(FRAME + eSlot).raw(INS.global_get(1)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(FRAME + tSlot).raw(INS.global_get(2)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(FRAME + nSlot).raw(INS.global_get(5)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(FRAME + rSlot).raw(INS.global_get(3)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(HTML_LEN).raw(INS.global_set(0));
    b.i32c(FRAME).raw(INS.ret());
  });

  // on_event(p,l) -> i32: log the raw payload, events++, clock, raf, patch batch, copy to frame, served=0
  const onEventBody = bd(0, (b) => {
    // webui_log(p, l) — proves the delivered payload {type,key,data} reached the island
    b.raw(INS.local_get(0)).raw(INS.local_get(1)).raw(INS.call(0)).raw(INS.drop());
    b.raw(INS.global_get(1)).i32c(1).raw(INS.i32_add()).raw(INS.global_set(1)); // events++
    // clockLow = (i32)(now_ms) & 0xff
    b.raw(INS.call(1)).raw(INS.trunc_f64_s()).i32c(0xff).raw(INS.i32_and()).raw(INS.global_set(5));
    // webui_raf(events) — registers the island with the engine's rAF registry
    b.raw(INS.global_get(1)).raw(INS.call(2)).raw(INS.drop());
    // patch evtBatch slots
    b.i32c(SEG_EV + EV_EVTSLOT).raw(INS.global_get(1)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(SEG_EV + EV_CLOCKSLOT).raw(INS.global_get(5)).raw(INS.i32_store8());
    // store_set(key, KEY_LEN, &evtbyte, 1) — persist the current event digit
    b.i32c(segKey).i32c(KEY_LEN).i32c(SEG_EV + EV_EVTSLOT).i32c(1).raw(INS.call(4));
    // copy the patched batch into the frame buffer (drain reads at frame_ptr)
    b.i32c(FRAME).i32c(SEG_EV).i32c(EV_LEN).raw(INS.memcopy());
    b.i32c(EV_LEN).raw(INS.global_set(0)); // frameLen
    b.i32c(0).raw(INS.global_set(4));      // served=0
    b.i32c(FRAME).raw(INS.ret());
  });

  // take_ops() -> i32: serve once, then 0
  const takeOpsBody = bd(0, (b) => {
    b.raw(INS.global_get(4)).raw(INS.i32_eqz()).raw(INS.if_i32());
    b.i32c(1).raw(INS.global_set(4));
    b.raw(INS.global_get(0));
    b.raw(INS.else_());
    b.i32c(0);
    b.raw(INS.end());
  });

  // state_save() -> i32: patch the events digit into the snapshot; copy to frame; frameLen=SNAP_LEN
  const stateSaveBody = bd(0, (b) => {
    b.i32c(SEG_SNAP + SNAP_SLOT).raw(INS.global_get(1)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(FRAME).i32c(SEG_SNAP).i32c(SNAP_LEN).raw(INS.memcopy());
    b.i32c(SNAP_LEN).raw(INS.global_set(0));
    b.i32c(FRAME).raw(INS.ret());
  });

  // state_restore(p,l) -> i32: restoreOk = (l == SNAP_LEN) ? 1 : 0
  const stateRestoreBody = bd(0, (b) => {
    // l is param1: restoreOk = 1 if l == SNAP_LEN
    b.raw(INS.local_get(1)).i32c(SNAP_LEN).raw(INS.i32_ne()).raw(INS.if_());
    b.i32c(0).raw(INS.global_set(3));
    b.raw(INS.else_());
    b.i32c(1).raw(INS.global_set(3));
    b.raw(INS.end());
    b.i32c(OK_LEN).raw(INS.global_set(0));
    b.i32c(SEG_OK).raw(INS.ret());
  });

  // frame_tick(idx) -> i32: ticks++, patch tick batch, copy to frame, frameLen, served=0
  const frameTickBody = bd(0, (b) => {
    b.raw(INS.global_get(2)).i32c(1).raw(INS.i32_add()).raw(INS.global_set(2));
    b.i32c(SEG_TICK + TICK_SLOT).raw(INS.global_get(2)).i32c(48).raw(INS.i32_add()).raw(INS.i32_store8());
    b.i32c(FRAME).i32c(SEG_TICK).i32c(TICK_LEN).raw(INS.memcopy());
    b.i32c(TICK_LEN).raw(INS.global_set(0));
    b.i32c(0).raw(INS.global_set(4));
    b.i32c(FRAME).raw(INS.ret());
  });

  const startBody = bd(0, () => {});

  const CODE_BODIES = [
    inputPtrBody, framePtrBody, frameLenBody,
    renderBodyFinal, onEventBody, takeOpsBody, stateSaveBody, stateRestoreBody, frameTickBody, startBody,
  ];
  const codeSec = new B();
  {
    codeSec.raw(uleb(CODE_BODIES.length));
    for (const c of CODE_BODIES) {
      const bytes = c.bytes();
      codeSec.raw(uleb(bytes.length)).raw(bytes);
    }
  }

  // ---- data ----
  const dataSec = new B();
  {
    dataSec.raw(uleb(DATA.length));
    for (const { off, b: bb } of DATA) {
      dataSec.u8(0x00).i32c(off).u8(0x0b);
      dataSec.raw(uleb(bb.length)).raw(bb);
    }
  }

  // ---- assemble ----
  const out = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
  const sections = [
    [1, typeB], [2, importB], [3, funcSec], [5, memSec],
    [6, globSec], [7, expSec], [10, codeSec], [11, dataSec],
  ];
  for (const [id, t] of sections) {
    const payload = t.bytes();
    out.push(id);
    out.push(...uleb(payload.length));
    out.push(...payload);
  }
  return Uint8Array.from(out);
}

// ---- bogus module: imports a KNOWN host fn plus an UNKNOWN webui_* fn ----
// buildImports must throw on the unknown one; the engine degrades the island
// to unmapped while the page stays alive.
export function buildBogusWasm() {
  const enc = (s) => new TextEncoder().encode(s);
  const mod = "continuum";
  const names = [["webui_log", 1], ["webui_bogus", 0]]; // log is (i32,i32)->i32 (type1)
  const types = [[0x60, [], [0x7f]], [0x60, [0x7f, 0x7f], [0x7f]], [0x60, [], []]];
  const typeB = new B();
  {
    typeB.raw(uleb(types.length));
    for (const [tag, params, results] of types) {
      typeB.u8(tag).raw(uleb(params.length));
      for (const p of params) typeB.u8(p);
      typeB.raw(uleb(results.length));
      for (const r of results) typeB.u8(r);
    }
  }
  const importB = new B();
  {
    importB.raw(uleb(names.length));
    for (const [nm, ti] of names) {
      importB.raw(uleb(mod.length)).str(mod);
      importB.raw(uleb(nm.length)).str(nm);
      importB.u8(0x00).raw(uleb(ti));
    }
  }
  // internal funcs: 2=input_ptr 3=frame_ptr 4=frame_len 5=render_region 6=_start
  const funcSec = new B();
  { funcSec.raw(uleb(5)); for (let i = 0; i < 3; i++) funcSec.raw(uleb(0)); funcSec.raw(uleb(1)).raw(uleb(2)); }
  const memSec = new B().u8(0x01).u8(0x00).raw(uleb(1));
  const globSec = new B();
  { globSec.raw(uleb(1)); globSec.u8(0x7f).u8(0x01).i32c(0).u8(0x0b); }
  const expSec = new B();
  {
    const E = [
      ["memory", 0x02, 0],
      ["webui_input_ptr", 0x00, 2], ["webui_frame_ptr", 0x00, 3], ["webui_frame_len", 0x00, 4],
      ["webui_render_region", 0x00, 5], ["_start", 0x00, 6],
    ];
    expSec.raw(uleb(E.length));
    for (const [nm, kind, idx] of E) {
      expSec.raw(uleb(nm.length)).str(nm);
      expSec.u8(kind).raw(uleb(idx));
    }
  }
  const decl = (n) => (n === 0 ? new B().u8(0x00) : new B().u8(0x01).raw(uleb(n)).u8(0x7f));
  const bd = (locals, fn) => { const b = decl(locals); fn(b); b.u8(0x0b); return b; };
  const bodies = [
    bd(0, (b) => { b.i32c(0x1000).raw(INS.ret()); }),
    bd(0, (b) => { b.i32c(0x2000).raw(INS.ret()); }),
    bd(0, (b) => { b.raw(INS.global_get(0)).raw(INS.ret()); }),
    bd(2, (b) => { b.i32c(0x2000).raw(INS.ret()); }),
    bd(0, () => {}),
  ];
  const codeSec = new B();
  {
    codeSec.raw(uleb(bodies.length));
    for (const c of bodies) {
      const bytes = c.bytes();
      codeSec.raw(uleb(bytes.length)).raw(bytes);
    }
  }
  const out = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
  for (const [id, t] of [[1, typeB], [2, importB], [3, funcSec], [5, memSec], [6, globSec], [7, expSec], [10, codeSec]]) {
    const payload = t.bytes();
    out.push(id);
    out.push(...uleb(payload.length));
    out.push(...payload);
  }
  return Uint8Array.from(out);
}

export function selfTest(print) {
  const p = print || (() => {});
  const mod = new WebAssembly.Module(buildProbeWasm());
  const imports = WebAssembly.Module.imports(mod);
  if (imports.length !== 6) throw new Error("expected 6 imports, got " + imports.length);
  p("imports: " + imports.map((i) => i.module + "." + i.name).join(", "));
  let instRef = null;
  let cached = {};
  let logged = [];
  const stub = {
    continuum: {
      webui_log: (ptr, len) => { instRef.exports && logged.push(new TextDecoder().decode(new Uint8Array(instRef.exports.memory.buffer, ptr, len))); return 0; },
      webui_now_ms: () => 123456.75,
      webui_raf: () => 0,
      webui_store_get: (p2, l2) => {
        const k = new TextDecoder().decode(new Uint8Array(instRef.exports.memory.buffer, p2, l2));
        if (!(k in cached)) return 0;
        const v = cached[k];
        const f = instRef.exports.webui_frame_ptr();
        const w = new Uint8Array(instRef.exports.memory.buffer, f, v.length + 4);
        w[0] = v.length & 255; w[1] = (v.length >>> 8) & 255;
        w.set(new TextEncoder().encode(v), 4);
        return f;
      },
      webui_store_set: (p2, l2, vp, vl) => {
        const k = new TextDecoder().decode(new Uint8Array(instRef.exports.memory.buffer, p2, l2));
        cached[k] = new TextDecoder().decode(new Uint8Array(instRef.exports.memory.buffer, vp, vl));
        return 0;
      },
      webui_surface: () => 0,
    },
  };
  const inst = new WebAssembly.Instance(mod, stub);
  instRef = inst;
  const mem = inst.exports.memory;
  if (mem.buffer.byteLength < 0x6000) throw new Error("memory too small");
  const read = (p, l) => new TextDecoder().decode(new Uint8Array(mem.buffer, p, l));

  const fp = inst.exports.webui_frame_ptr();
  const html0 = read(fp, inst.exports.webui_frame_len());
  // initial render: events=0, restore=0, store=0
  inst.exports.webui_render_region(0, 0);
  const h1 = read(fp, inst.exports.webui_frame_len());
  if (!h1.includes('data-e="0"') || !h1.includes('data-s="0"') || !h1.includes('data-r="0"')) {
    throw new Error("initial html odd: " + h1);
  }
  // on_event -> take_ops serves evtBatch (text digit + attr clock byte)
  inst.exports.webui_on_event(0, 2);
  const len1 = inst.exports.webui_take_ops();
  const rec = new Uint8Array(mem.buffer, fp, len1);
  if (len1 !== 34) throw new Error("evt batch len " + len1 + " wanted 34");
  if (rec[1] !== 1 || rec[11] !== 0x31) throw new Error("text record/evt value wrong");
  if (inst.exports.webui_take_ops() !== 0) throw new Error("take_ops must empty");
  if (cached["probe-key"] !== "1") throw new Error("store_set did not persist: " + cached["probe-key"]);
  // render again: events slot '1', and the store_get roundtrip shows store slot '1'
  inst.exports.webui_render_region(0, 0);
  const h2 = read(fp, inst.exports.webui_frame_len());
  if (!h2.includes('data-e="1"')) throw new Error("render events slot not updated: " + h2);
  if (!h2.includes('data-s="1"')) throw new Error("store_get roundtrip slot not set: " + h2);
  // state roundtrip: save snapshot (events=1), then restore with matching length sets restoreOk
  inst.exports.webui_state_save();
  const snap = read(fp, inst.exports.webui_frame_len());
  if (snap !== '{"events":1}') throw new Error("snapshot = " + snap);
  const snapBytes = new Uint8Array(mem.buffer, fp, inst.exports.webui_frame_len());
  const ip = inst.exports.webui_input_ptr();
  new Uint8Array(mem.buffer, ip, snapBytes.length).set(snapBytes);
  inst.exports.webui_state_restore(ip, snapBytes.length);
  inst.exports.webui_render_region(0, 0);
  const h3 = read(fp, inst.exports.webui_frame_len());
  if (!h3.includes('data-r="1"')) throw new Error("restore flag not set: " + h3);
  // frame_tick patches the tick batch
  inst.exports.webui_frame_tick(7);
  const len2 = inst.exports.webui_take_ops();
  const t2 = new Uint8Array(mem.buffer, fp, len2);
  if (t2[t2.length - 1] !== 0x31) throw new Error("tick value not '1': " + Array.from(t2).join(","));
  p("self-test ok (loop-free module): mount + events + take_ops + state roundtrip + frame_tick");
}
