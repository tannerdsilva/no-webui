#!/usr/bin/env node
// designer/gates/b-probe-fold.mjs  lane-B gate-consolidation fold-in (polish).
//
// the b-docs §5 fold-in list, executed: the canonical gates gain lane-B probe
// coverage by invoking THIS script (the lightest wiring — a gate script that
// runs the probe list) instead of inlining probe logic into the Swift plugins
// or browser-smoke. every self-spawned server uses a lane port (9200–9219).
//
//   node designer/gates/b-probe-fold.mjs --lint          # b-lint (standalone, the built tool)
//   node designer/gates/b-probe-fold.mjs --interaction   # b-interaction-smoke (ws, bench host on a lane port)
//   node designer/gates/b-probe-fold.mjs --windowed      # b-windowed-smoke (window advance, bench host on lane port)
//   node designer/gates/b-probe-fold.mjs --d3            # designerdir d3-gate (agg scroll/echo/degrade on 9210/9211)
//   node designer/gates/b-probe-fold.mjs --all           # every lane probe above
//
// exits non-zero on any probe failure. requires `swift build` first (the
// WebUIBench binary + the ContinuumTool binary must exist).

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PROBES = join(ROOT, "designer", "probes");
const BENCH_BIN = process.env.WEBUI_BENCH_SERVER ?? join(ROOT, ".build/debug/WebUIBench");

// lane ports (9200–9219); the canonical ports 9123/9130 are never touched.
const PORT_INTERACTION = 9212;
const PORT_WINDOWED = 9213;

let fail = 0;
const ok = (m) => { console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };

function runNode(path, args = [], env = {}) {
  const r = spawnSync(process.execPath, [path, ...args], {
    cwd: ROOT,
    env: { ...process.env, ...env },
    encoding: "utf8",
  });
  if (r.stdout) process.stdout.write(r.stdout);
  if (r.stderr) process.stderr.write(r.stderr);
  return r.status ?? 1;
}

// one self-spawned WebUIBench host shared by the ws probes (each probe opens
// its own pages against it), torn down on every exit path.
function spawnBench(port) {
  if (!existsSync(BENCH_BIN)) {
    bad(`WebUIBench binary not found at ${BENCH_BIN} — run swift build first`);
    return null;
  }
  const p = spawn(BENCH_BIN, ["--port", String(port)], { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
  let log = "";
  p.stdout.on("data", (d) => (log += d));
  p.stderr.on("data", (d) => (log += d));
  process.on("exit", () => { try { p.kill("SIGKILL"); } catch { /* gone */ } });
  return { p, log: () => log };
}

async function waitFor(url, tries = 40) {
  for (let i = 0; i < tries; i++) {
    try { const r = await fetch(url); if (r.ok) return true; } catch { /* booting */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

const wants = (flag) => process.argv.slice(2).includes(flag);
const all = wants("--all");

if (all || wants("--lint")) {
  console.log("=== lane-B fold: b-lint (capability-lint probe) ===");
  const code = runNode(join(PROBES, "b-lint.mjs"));
  if (code === 0) ok("b-lint.mjs -> exit 0");
  else bad("b-lint.mjs failed (exit " + code + ")");
}

if (all || wants("--interaction")) {
  console.log("=== lane-B fold: b-interaction-smoke (ws interactions) ===");
  const bench = spawnBench(PORT_INTERACTION);
  if (!bench) { bad("skipping --interaction (no WebUIBench binary)"); }
  else {
    const base = `http://127.0.0.1:${PORT_INTERACTION}`;
    if (!(await waitFor(base + "/bench/feed"))) {
      bad(`bench host did not come up on :${PORT_INTERACTION} (${bench.log().slice(-200)})`);
    } else {
      const code = runNode(join(PROBES, "b-interaction-smoke.mjs"), [], { BENCH_URL: base });
      if (code === 0) ok("b-interaction-smoke.mjs -> exit 0");
      else bad("b-interaction-smoke.mjs failed (exit " + code + ")");
    }
  }
}

if (all || wants("--windowed")) {
  console.log("=== lane-B fold: b-windowed-smoke (window advance) ===");
  const bench = spawnBench(PORT_WINDOWED);
  if (!bench) { bad("skipping --windowed (no WebUIBench binary)"); }
  else {
    const base = `http://127.0.0.1:${PORT_WINDOWED}`;
    if (!(await waitFor(base + "/bench/feed"))) {
      bad(`bench host did not come up on :${PORT_WINDOWED} (${bench.log().slice(-200)})`);
    } else {
      const code = runNode(join(PROBES, "b-windowed-smoke.mjs"), [], { BENCH_URL: base });
      if (code === 0) ok("b-windowed-smoke.mjs -> exit 0");
      else bad("b-windowed-smoke.mjs failed (exit " + code + ")");
    }
  }
}

if (all || wants("--d3")) {
  console.log("=== lane-B fold: d3-gate (agg scroll / echo / degrade) ===");
  const code = runNode(join(ROOT, "designer", "d3-gate.mjs"), ["--bench-port", "9210", "--probe-port", "9211"]);
  if (code === 0) ok("d3-gate.mjs -> exit 0");
  else bad("d3-gate.mjs failed (exit " + code + ")");
}

process.exit(fail === 0 ? 0 : 1);
