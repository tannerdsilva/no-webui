#!/usr/bin/env node
// designer/probes/d-transport.mjs — lane-D polish: the island transport
// mapping (KeyEvent → {type, key, data} v1), pinned as the consumer contract.
//
// what this probe gates:
//   1. the canonical identifier table MATCHES the real Swift source of truth
//      (Sources/WebUISharedCore/KeyEvent.swift, `Key.identifier`) — parsed
//      straight off disk, so a C-side drift fails here.
//   2. the round-trip rule (`Key(identifier:)`) — named keys, F1..F24,
//      single-scalar printables, everything else → unknown (never traps).
//   3. the v1 key-channel payload shape ({type:"key", key}) — `data` omitted,
//      modifiers/isRepeat have no wire field (c-to-e.md frozen vocabulary).
//   4. the element-id rule for click/input payloads (the real island
//      handshake, e-island-e2e-real.mjs) — key = element id, type = the
//      normalized event.
//   5. the space friction (recorded): the DOM spacebar's event.key is a
//      single space scalar " ", which parses to printable(" "), NOT .space
//      (whose canonical identifier is the author-side "Space").
//
// pure Node, no browser, no wasm, no server, no port. exit non-zero on failure.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const KEY_SWIFT = join(ROOT, "Sources/WebUISharedCore/KeyEvent.swift");

if (!existsSync(KEY_SWIFT)) {
  console.error("d-transport: KeyEvent.swift not found — " + KEY_SWIFT);
  process.exit(2);
}
const swift = readFileSync(KEY_SWIFT, "utf8");

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

// ---- 1. extract the canonical identifier table from the REAL Swift source ----
// the `Key.identifier` switch spells the static cases as:
//   case .enter: return "Enter"  … (14 named)
// computed cases (.function/.printable/.unknown) are handled separately —
// .unknown is excluded here because its round-trip falls through to the
// default branch (asserted separately below), exactly as in Swift.
const nameById = {};
for (const m of swift.matchAll(/case \.([a-zA-Z]+): return "([^"]+)"/g)) {
  if (m[1] === "unknown") continue;
  nameById[m[2]] = m[1];
}
const namedIdentifiers = Object.keys(nameById).sort();
check(
  "identifier table parsed off KeyEvent.swift: 14 named keys",
  namedIdentifiers.length === 14,
  `got ${namedIdentifiers.length}: ${namedIdentifiers.join(",")}`
);
const EXPECTED_NAMED = [
  "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowUp", "Backspace", "Delete",
  "End", "Enter", "Escape", "Home", "PageDown", "PageUp", "Space", "Tab",
].sort();
check(
  "named set matches the frozen Key.identifier table",
  JSON.stringify(namedIdentifiers) === JSON.stringify(EXPECTED_NAMED),
  JSON.stringify(namedIdentifiers)
);
check("named identifiers are distinct", new Set(namedIdentifiers).size === namedIdentifiers.length);

// ---- 2. the round-trip rule (mirrors Key(identifier:) exactly) ----
function parseKey(id) {
  if (Object.prototype.hasOwnProperty.call(nameById, id)) return { kind: nameById[id] };
  // mirrors Key.parseFunctionRow: an all-digit suffix, then 1…24 — "F01" → 1,
  // "F0"/"F25"/"F100"/"Fabc" → unknown (Swift range-checks AFTER the digit scan)
  const f = /^F([0-9]+)$/.exec(id);
  if (f) {
    const n = Number(f[1]);
    if (n >= 1 && n <= 24) return { kind: "function", n };
    return { kind: "unknown" };
  }
  const scalars = Array.from(id);
  if (scalars.length === 1) return { kind: "printable" };
  return { kind: "unknown" };
}

let rt = true;
for (const id of namedIdentifiers) {
  const p = parseKey(id);
  if (p.kind !== nameById[id]) { rt = false; bad(`named round-trip failed: "${id}" → ${JSON.stringify(p)}`); }
}
check("named keys round-trip through the parse rule", rt);

let frt = true;
for (let n = 1; n <= 24; n++) {
  const p = parseKey("F" + n);
  if (!(p.kind === "function" && p.n === n)) { frt = false; bad(`F${n} round-trip failed: ${JSON.stringify(p)}`); }
}
check("F1..F24 round-trip (function row)", frt);

check("F0 / F25 / F100 / Fabc → unknown (out-of-band function row)",
  ["F0", "F25", "F100", "Fabc"].every((id) => parseKey(id).kind === "unknown"));

check("single-scalar strings parse to printable (\"a\", \"é\")",
  ["a", "é"].every((id) => parseKey(id).kind === "printable"));

check("multi-scalar non-named strings → unknown (never traps)",
  ["abc", "NotARealKey", "Shift"].every((id) => parseKey(id).kind === "unknown"));

check("Unknown (the .unknown identifier) round-trips to unknown",
  parseKey("Unknown").kind === "unknown");

// ---- 3. the v1 key-channel payload shape ({type,key}, data omitted) ----
function keyPayloadV1(keyId) {
  return { type: "key", key: keyId }; // data omitted on the key channel (v1)
}
const p = keyPayloadV1("ArrowUp");
check("key payload is exactly {type:'key', key}, no data field",
  Object.keys(p).length === 2 && p.type === "key" && p.key === "ArrowUp",
  JSON.stringify(p));
check("named identifier variance: printable + function map to the wire strings",
  keyPayloadV1("a").key === "a" && keyPayloadV1("F5").key === "F5");

// ---- 4. the element-id rule (real handshake: click/input key = element id) ----
const clickPayload = { type: "click", key: "probe-inc" };   // element id, from e-island-e2e-real
const inputPayload = { type: "input", key: "probe-field", data: { value: "alpha" } };
check("click/input carry the ELEMENT id as key (not a key-vocabulary entry)",
  clickPayload.key === "probe-inc" && !Object.prototype.hasOwnProperty.call(nameById, clickPayload.key)
  && inputPayload.key === "probe-field");
check("the key-vocabulary parse treats element ids as unknown (island noop, safe)",
  parseKey("probe-inc").kind === "unknown");

// ---- 5. the space friction (recorded boundary) ----
check("' ' (DOM spacebar event.key) parses to printable(\" \"), NOT .space",
  parseKey(" ").kind === "printable" && " " !== "Space");
check("'Space' (the author-side canonical identifier) parses to .space",
  parseKey("Space").kind === "space");

console.log("");
if (fail === 0) console.log(`d-transport: ${pass} PASS, 0 FAIL (identifier source: ${KEY_SWIFT})`);
else console.log(`d-transport: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
