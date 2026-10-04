#!/usr/bin/env node
// designer/probes/b-budget-pins.mjs  the t4.2 per-island budget-pin probe (lane B),
// extended for DX-3 (CONTINUUM_DX §2.3) — the autobuild auto-pin path.
//
// proves that WebUIBudgetPlugin enforces per-island IslandBudget pins from the
// continuum manifest (t4.2 — never a second budget path): with a tight pin on
// a fake island artifact, the gate must fail naming the island; with a loose
// pin it must pass. the global .build/out ceiling stays the fallback for
// islands without a manifest pin (covered by the real gate on the merged tree).
//
// DX-3 additions (the second half of this probe): the measured auto-pin path —
// WebUIAutobuildPlugin writes rows {name/maxBytes/maxGzipBytes + raw/gz/sha/
// url} into its work-dir ContinuumManifest.json; WebUIBudgetPlugin reads that
// manifest too and enforces the TIGHTEST of {declared, measured} per field
// (tightening-only: a declared pin can only lower the measured auto-pin, never
// loosen it). asserts: (5) a measured auto-pin breaches when the artifact
// outgrows ceil(raw×1.05); (6) a declared pin TIGHTER than the measured one
// wins (tightening); (7) a declared pin LOOSER than the measured one does NOT
// loosen the auto-pin (the measured ceiling still enforces).
//
// the plugin accepts --island-dir / --island-manifest / --autobuild-manifest
// overrides so this probe never touches the real .build/out; production
// defaults are unchanged.
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

// context: an artifact set (name -> size) plus a declared-manifest (t4.2) and
// an autobuild-manifest (DX-3 measured). shared across the matrix below.
const ISLAND_DIR = join(TMP, "islands");
writeFileSync(join(ISLAND_DIR, "WebUIProbeIsland.wasm"), Buffer.alloc(90_000, 0x61));

function runBudget({ declaredManifest, autoManifest }) {
  const args = [
    "package", "--disable-sandbox", "plugin", "budget",
    "--island-dir", ISLAND_DIR,
  ];
  if (declaredManifest) args.push("--island-manifest", declaredManifest);
  if (autoManifest) args.push("--autobuild-manifest", autoManifest);
  const r = spawnSync("swift", args, { cwd: ROOT, encoding: "utf8", timeout: 120_000 });
  return { code: r.status, out: (r.stdout ?? "") + (r.stderr ?? "") };
}

function writeManifest(path, islands) {
  const manifest = {
    kind: "continuum-engine-slice",
    version: 2,
    attributeAllowlist: ["class", "aria-*", "data-*"],
    components: {},
    union: [],
    islands,
  };
  writeFileSync(path, JSON.stringify(manifest, null, 2));
}

console.log("t4.2 per-island budget pin probe + DX-3 auto-pin (tightening-only)");

// 1. a declared tight pin -> the gate fails, naming the island.
const declaredTight = join(TMP, "declared-tight.json");
writeManifest(declaredTight, [{ name: "probe", maxBytes: 50_000 }]);
const tight = runBudget({ declaredManifest: declaredTight });
check("declared tight pin fails the gate", tight.code !== 0, `exit=${tight.code}`);
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

// 2. a declared loose pin -> the gate passes (proves the override resolves + no false fail).
const declaredLoose = join(TMP, "declared-loose.json");
writeManifest(declaredLoose, [{ name: "probe", maxBytes: 100_000 }]);
const loose = runBudget({ declaredManifest: declaredLoose });
check("declared loose pin passes", loose.code === 0, `exit=${loose.code}\n${loose.out}`);

// 3. DX-3: a MEASURED auto-pin below the artifact size breaches, naming the island.
//    raw = 90_000 -> maxBytes = ceil(90_000 × 1.05) = 94_500 is still > 90_000,
//    so use a measured maxBytes BELOW the artifact (simulating a grown artifact:
//    auto-pin computed when the artifact was smaller). the auto-pin row carries
//    the additive raw/gz/sha/url beside the pin keys.
const autoBreach = join(TMP, "auto-breach.json");
writeManifest(autoBreach, [{
  name: "WebUIProbeIsland", maxBytes: 60_000, maxGzipBytes: 30_000,
  raw: 57_142, gz: 28_500, sha: "ab" + "0".repeat(62), url: "/__assets/webui-WebUIProbeIsland.wasm",
}]);
const breach = runBudget({ autoManifest: autoBreach });
check("measured auto-pin breaches the gate", breach.code !== 0, `exit=${breach.code}`);
check(
  "auto-pin breach names the island bytes vs the measured ceiling",
  /WebUIProbeIsland\.wasm: 90000 raw bytes > 60000 pinned by island WebUIProbeIsland/.test(breach.out),
  breach.out.split("\n").filter((l) => l.includes("OVER") || l.includes("breach")).join("\n")
);

// 4. DX-3 tightening-only: a declared pin TIGHTER than the measured auto-pin wins.
//    artifact 90_000; measured auto-pin 100_000; declared 80_000 -> both pass
//    (declared is the effective ceiling; nothing exceeds it), and the row shows
//    the tighter declared pin.
const tightDeclared = join(TMP, "tight-declared.json");
writeManifest(tightDeclared, [{ name: "probe", maxBytes: 95_000 }]);
const autoLoose = join(TMP, "auto-loose.json");
writeManifest(autoLoose, [{
  name: "WebUIProbeIsland", maxBytes: 100_000, // measured, looser than declared
  raw: 95_000, gz: 40_000,
}]);
const tightened = runBudget({ declaredManifest: tightDeclared, autoManifest: autoLoose });
check("tightening: declared tighter than measured still passes", tightened.code === 0, `exit=${tightened.code}\n${tightened.out}`);
check(
  "tightening: row shows the declared (tighter) pin, not the measured one",
  /raw≤95000/.test(tightened.out),
  tightened.out.split("\n").find((l) => l.includes("WebUIProbeIsland"))
);

// 5. DX-3 tightening-only, the other direction: a declared pin LOOSER than the
//    measured auto-pin must NOT loosen it — the measured ceiling still enforces.
//    artifact 90_000; measured auto-pin 80_000; declared 200_000 (looser) ->
//    the effective pin is 80_000 and the artifact breaches.
const looseDeclared = join(TMP, "loose-declared.json");
writeManifest(looseDeclared, [{ name: "probe", maxBytes: 200_000 }]);
const autoTight = join(TMP, "auto-tight.json");
writeManifest(autoTight, [{
  name: "WebUIProbeIsland", maxBytes: 80_000,
  raw: 76_000, gz: 32_000,
}]);
const notLoosened = runBudget({ declaredManifest: looseDeclared, autoManifest: autoTight });
check("no-loosening: loose declared pin does not escape the measured auto-pin", notLoosened.code !== 0, `exit=${notLoosened.code}`);
check(
  "no-loosening: breach names the measured ceiling (80_000), not the declared 200_000",
  /90000 raw bytes > 80000 pinned by island WebUIProbeIsland/.test(notLoosened.out),
  notLoosened.out.split("\n").filter((l) => l.includes("OVER") || l.includes("breach")).join("\n")
);

cleanup();
if (failures > 0) {
  console.error(`b-budget-pins: ${failures} failure(s)`);
  process.exit(1);
}
console.log("b-budget-pins: 10/10 PASS");
