#!/usr/bin/env node
// designer/probes/c-parity.mjs — lane-C probe: the t4.2 native↔island parity gate.
//
// the SAME kernel corpus runs natively (swift test → writes
// .build/webui-kernel-corpus-native.json) and inside the probe island's wasm
// (webui_run_corpus export). this probe compares the two hash sets:
//
//   EQUAL HASHES = the gate. a single differing hash (or a missing/extra
//   case, or a corrupt frame) fails the probe with a non-zero exit.
//
// usage: node designer/probes/c-parity.mjs
//   requires: `swift test` (writes the native artifact) then
//             `swift package --disable-sandbox plugin wasm-island
//                --product WebUIProbeIsland` (serves the island artifact).

import { readFileSync, existsSync } from "node:fs";
import { WASI } from "node:wasi";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const WASM = join(ROOT, ".build/out/Products/Release-webassembly-wasm32/WebUIProbeIsland.wasm");
const NATIVE = join(ROOT, ".build/webui-kernel-corpus-native.json");

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

function instantiate() {
  const bytes = readFileSync(WASM);
  const wasi = new WASI({ version: "preview1", args: [], env: {}, preopens: {} });
  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes), {
    wasi_snapshot_preview1: wasi.wasiImport,
  });
  try { wasi.initialize(instance); } catch { /* reactor — no _initialize */ }
  const e = instance.exports;
  const mem = () => new Uint8Array(e.memory.buffer);
  const view = (ptr, len) => mem().slice(ptr, ptr + len);
  return (name) => {
    const ret = e[name]();
    const fptr = e.webui_frame_ptr();
    const flen = e.webui_frame_len();
    return { ret, text: new TextDecoder().decode(view(fptr, flen)) };
  };
}

console.log(`c-parity: probing ${WASM}`);

// 0. preconditions — the native artifact must exist (produced by swift test).
if (!existsSync(NATIVE)) {
  console.error(`c-parity: native corpus artifact missing at ${NATIVE}`);
  console.error("  run `swift test` first (KernelParityTests writes it), then re-run this probe");
  process.exit(1);
}
const native = JSON.parse(readFileSync(NATIVE, "utf8"));

// 1. the island side: webui_run_corpus serves the same-shaped JSON.
const invoke = instantiate();
const islandDoc = invoke("webui_run_corpus");
let island;
try {
  island = JSON.parse(islandDoc.text);
} catch {
  bad(`webui_run_corpus did not return json: ${islandDoc.text.slice(0, 120)}`);
  process.exit(1);
}

const nativeCases = new Map(native.cases.map((c) => [c.name, c.hash]));
const islandCases = new Map(island.cases.map((c) => [c.name, c.hash]));

// 2. structural parity.
ok(`island corpus format "${island.format}" (native "${native.format}")`);
ok(`case count ${island.cases.length} == native ${native.cases.length}`);

// 3. hash parity — the gate.
let mismatches = 0;
for (const [name, nativeHash] of nativeCases) {
  const islandHash = islandCases.get(name);
  if (islandHash === undefined) {
    mismatches += 1;
    bad(`island is missing case "${name}" (native ${nativeHash})`);
  } else if (islandHash !== nativeHash) {
    mismatches += 1;
    bad(`case "${name}": island ${islandHash} != native ${nativeHash}`);
  }
}
for (const name of islandCases.keys()) {
  if (!nativeCases.has(name)) {
    mismatches += 1;
    bad(`island has unexpected case "${name}"`);
  }
}
if (mismatches === 0) {
  ok(`all ${nativeCases.size} hashes equal — native ↔ island parity holds`);
} else {
  bad(`${mismatches} hash mismatch(es)`);
}

// 4. the island hash set must be internally complete (16 hex, no junk).
let malformed = 0;
for (const [name, h] of islandCases) {
  if (typeof h !== "string" || !/^[0-9a-f]{16}$/.test(h)) {
    malformed += 1;
    bad(`case "${name}" has a malformed hash "${h}"`);
  }
}
if (malformed === 0) ok("every island hash is a well-formed 16-hex FNV-1a");

console.log(`\nc-parity: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
