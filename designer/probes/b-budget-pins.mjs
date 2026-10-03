#!/usr/bin/env node
// designer/probes/b-budget-pins.mjs  the t4.2 per-island budget-pin probe (lane B).
//
// proves that WebUIBudgetPlugin enforces per-island IslandBudget pins from the
// continuum manifest (t4.2 — never a second budget path): with a tight pin on
// a fake island artifact, the gate must fail naming the island; with a loose
// pin it must pass. the global .build/out ceiling stays the fallback for
// islands without a manifest pin (covered by the real gate on the merged tree).
//
// the plugin accepts --island-dir / --island-manifest overrides so this probe
// never touches the real .build/out; production defaults are unchanged.
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const TMP = join(ROOT, ".bench", "budget-pins-probe");

function cleanup() { rmSync(TMP, { recursive: true, force: true }); }
cleanup();
mkdirSync(join(TMP, "islands"), { recursive: true });

let failures = 0;
function check(label, cond, detail) {
  if (cond) { console.log(`  PASS  ${label}`); }
  else { failures += 1; console.error(`  FAIL  ${label}\n        ${detail}`); }
}

// a fake island artifact, 90_000 bytes — inside the global 200_000 ceiling but
// far over a 50_000 per-island pin, so ONLY the per-island pin can trip it.
writeFileSync(join(TMP, "islands", "WebUIProbeIsland.wasm"), Buffer.alloc(90_000, 0x61));

function runBudget(pinBytes) {
  const manifest = {
    kind: "continuum-engine-slice",
    version: 1,
    attributeAllowlist: ["class", "aria-*", "data-*"],
    components: {},
    union: [],
    islands: [{ name: "probe", maxBytes: pinBytes }],
  };
  const mf = join(TMP, "ContinuumManifest.json");
  writeFileSync(mf, JSON.stringify(manifest, null, 2));
  const r = spawnSync(
    "swift", [
      "package", "--disable-sandbox", "plugin", "budget",
      "--island-dir", join(TMP, "islands"),
      "--island-manifest", mf,
    ],
    { cwd: ROOT, encoding: "utf8", timeout: 120_000 }
  );
  return { code: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
}

console.log("t4.2 per-island budget pin probe");

// 1. tight pin -> the gate fails, naming the island.
const tight = runBudget(50_000);
check("tight pin fails the gate", tight.code !== 0, `exit=${tight.code}`);
check(
  "breach names the island + its pin",
  /WebUIProbeIsland\.wasm: 90000 raw bytes > 50000 pinned by island probe/.test(tight.out),
  tight.out.split("\n").filter((l) => l.includes("OVER") || l.includes("breach")).join("\n")
);
check(
  "per-island row shows the pin",
  tight.out.includes("raw≤50000"),
  tight.out.split("\n").find((l) => l.includes("WebUIProbeIsland"))
);

// 2. loose pin -> the gate passes (proves the override resolves + no false fail).
const loose = runBudget(100_000);
check("loose pin passes", loose.code === 0, `exit=${loose.code}\n${loose.out}`);

cleanup();
if (failures > 0) {
  console.error(`b-budget-pins: ${failures} failure(s)`);
  process.exit(1);
}
console.log("b-budget-pins: 4/4 PASS");
