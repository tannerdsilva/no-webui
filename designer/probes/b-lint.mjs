#!/usr/bin/env node
// designer/probes/b-lint.mjs  the t2.6 capability-lint probe (lane B).
//
// proves, against the BUILT WebUIContinuumTool binary:
//   1. a deliberate violation produces the parent plan's EXACT message and a
//      non-zero exit (the message shape is a contract — lane D codes its
//      @HotView imports: against it);
//   2. the same marker with all capabilities granted exits 0 (no false fail);
//   3. every accepted imports: spelling (array, dot-case, .self type, single
//      string) is scanned, so D's wave-2 marker shape reconciles cleanly.
//
// requires `swift build` first (the tool binary must exist).
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const BIN = join(ROOT, ".build/out/Products/Debug/WebUIContinuumTool");
const FIX = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
const ALL_GRANTS = "surface_acquire,clock,frame_schedule,input_subscribe,state_persist,log";

if (!existsSync(BIN)) {
  console.error(`b-lint: tool binary not built at ${BIN} — run swift build first`);
  process.exit(1);
}

function run(args) {
  const r = spawnSync(BIN, args, { encoding: "utf8" });
  return { code: r.status, out: r.stdout ?? "", err: r.stderr ?? "" };
}

let failures = 0;
function check(label, cond, detail) {
  if (cond) { console.log(`  PASS  ${label}`); }
  else { failures += 1; console.error(`  FAIL  ${label}\n        ${detail}`); }
}

console.log("t2.6 capability lint probe");

// 1. deliberate violation — the exact message + non-zero exit.
const v = run(["lint", "--sources", join(FIX, "violation"), "--grants", "clock,log"]);
const want = 'island "feed" imports "surface_acquire" — not granted by the host manifest (add it to ContinuumGrants or drop the import)';
check("violation exits non-zero", v.code === 1, `exit=${v.code}`);
check("violation prints the exact t2.6 message", v.err.includes(want), JSON.stringify(v.err));

// 2. same marker, all capabilities granted -> green.
const g = run(["lint", "--sources", join(FIX, "violation"), "--grants", ALL_GRANTS]);
check("granted marker exits 0", g.code === 0, `exit=${g.code}, stderr=${g.err}`);

// 3. every imports: spelling is scanned (miss a spelling -> count drops).
const f = run(["lint", "--sources", join(FIX, "forms"), "--grants", "surface_acquire"]);
// forms fixture: a1 imports surface_acquire+clock, a2 (dot-case) imports both,
// a3 (.self types) imports both, a4 (single string + budget) imports only
// surface_acquire. with only surface_acquire granted, expect 3 clock
// violations (a1..a3) + 0 surface violations.
const clockViols = (f.err.match(/imports "clock"/g) ?? []).length;
check("forms: all three clock imports flagged", clockViols === 3, `clockViols=${clockViols}`);
check("forms: granted surface_acquire not flagged", !f.err.includes('imports "surface_acquire"'), f.err);
check("forms: non-zero exit", f.code === 1, `exit=${f.code}`);

if (failures > 0) {
  console.error(`b-lint: ${failures} failure(s)`);
  process.exit(1);
}
console.log("b-lint: 6/6 PASS");
