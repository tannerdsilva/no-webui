#!/usr/bin/env node
// designer/probes/g-theme.mjs  lane G's theme-pipeline probe (DX-15a, W2) — VERDICT-PARAMETRIC.
//
// mechanism (a) ran: the consumer declares a `ThemeCatalog` in its own target and
// attaches the framework's `WebUIThemePlugin`; the plugin emits `DemoCatalogSheet`
// as a compilable source. there is NO consumer tool target and no shim — so this
// probe asserts the (a) branch and would fail loudly on a (b)-shaped tree.
//
// usage:
//   node designer/probes/g-theme.mjs                             # :9372
//   node designer/probes/g-theme.mjs --port 9373 --binary <path>
//
// asserts (appendix C step 7 + step 9's theme conformances):
//   1. mechanism (a): the demo target attaches the plugin and declares no consumer
//      theme tool target, and no consumer shim file exists
//   2. the demo declares a ThemeCatalog AND a hand-written WebUIThemeProvider
//   3. the plugin emitted `DemoCatalogSheet` (a WebUIShippedAsset conformance)
//   4. the served page LINKS the emitted sheet's content address, and that address
//      IS the sha256 of the emitted bytes
//   5. the theme route serves those exact bytes
//   6. the emitted css carries the hand-written twin's scheme (macro-free provider
//      through the same path)
//   7. stamp stability: a second tool run over the same catalog is byte-identical

import { spawn, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, statSync, mkdtempSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const PORT = Number(flag("--port", "9372"));
const BINARY = flag("--binary", join(ROOT, ".build", "debug", "WebUIExample"));
const TOOL = join(ROOT, ".build", "out", "Products", "Debug", "WebUIThemeTool");
const CATALOG_SOURCE = join(ROOT, "Sources", "WebUIExample", "DemoTheme.swift");

if (PORT < 9370 || PORT > 9379) {
  console.log(`  FAIL port ${PORT} is outside the lane block 9370–9379 (canonical ports are orchestrator-only)`);
  process.exit(1);
}
let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

/// find the plugin's emitted sheet inside .build/plugins/outputs.
function findEmitted() {
  const stack = [join(ROOT, ".build", "plugins", "outputs")];
  while (stack.length) {
    const dir = stack.pop();
    let entries = [];
    try { entries = readdirSync(dir); } catch (e) { continue; }
    for (const e of entries) {
      const p = join(dir, e);
      let st;
      try { st = statSync(p); } catch (err) { continue; }
      if (st.isDirectory()) stack.push(p);
      else if (e === "DemoCatalogSheet.swift") return p;
    }
  }
  return null;
}

/// decode the `bodyBase64` literal out of the generated sheet source.
function emittedBytes(source) {
  const m = /bodyBase64 = "([^"]+)"/.exec(source);
  return m ? Buffer.from(m[1], "base64") : null;
}

async function waitForServer(timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/`, { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.text();
    } catch (e) {}
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

const server = spawn(BINARY, ["--port", String(PORT)], { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

async function run() {
  // 1. mechanism (a).
  const manifest = readFileSync(join(ROOT, "Package.swift"), "utf8");
  // the demo's TARGET block (the manifest also has a product entry with the same
  // name earlier, so anchor on the declaration, not the bare name).
  const targetMatch = /\.executableTarget\(\s*\n\s*name: "WebUIExample"/.exec(manifest);
  const afterStart = targetMatch ? manifest.slice(targetMatch.index) : "";
  const nextTarget = afterStart.indexOf(".executableTarget(", 1);
  const exampleBlock = nextTarget > 0 ? afterStart.slice(0, nextTarget) : afterStart.slice(0, 900);
  if (exampleBlock.includes('.plugin(name: "WebUIThemePlugin")')) ok(`mechanism (a): the demo target attaches WebUIThemePlugin (one line, no consumer tool)`);
  else bad(`mechanism (a): the demo target does not attach WebUIThemePlugin`);
  if (!/name: "[A-Za-z]*ThemeTool"/.test(exampleBlock)) ok(`mechanism (a): no consumer theme TOOL target in the demo block`);
  else bad(`mechanism (a) violated: the demo block declares a consumer theme tool target`);
  const shim = join(ROOT, "Sources", "WebUIExample", "ThemeShim.swift");
  if (!existsSync(shim)) ok(`mechanism (a): no consumer shim (Sources/WebUIExample/ThemeShim.swift absent)`);
  else bad(`mechanism (b) shape present: ${shim} exists`);

  // 2. the consumer's declarations.
  const themeSource = readFileSync(CATALOG_SOURCE, "utf8");
  if (/:\s*ThemeCatalog/.test(themeSource)) ok(`the demo declares a ThemeCatalog conformance`);
  else bad(`no ThemeCatalog conformance in ${CATALOG_SOURCE}`);
  if (/:\s*WebUIThemeProvider/.test(themeSource)) ok(`the demo carries the hand-written WebUIThemeProvider twin`);
  else bad(`no hand-written WebUIThemeProvider conformance in ${CATALOG_SOURCE}`);

  // 3. the plugin emitted the sheet.
  const emittedPath = findEmitted();
  if (emittedPath === null) {
    bad(`the plugin emitted no DemoCatalogSheet.swift under .build/plugins/outputs — is the plugin attached?`);
    process.exitCode = 1;
    return;
  }
  const emittedSource = readFileSync(emittedPath, "utf8");
  ok(`the plugin emitted ${emittedPath.replace(ROOT + "/", "")}`);
  if (/enum DemoCatalogSheet: WebUIShippedAsset/.test(emittedSource)) ok(`the emitted type is a WebUIShippedAsset conformance`);
  else bad(`the emitted type is not a WebUIShippedAsset conformance`);

  const bytes = emittedBytes(emittedSource);
  if (bytes === null) {
    bad(`could not decode the emitted body`);
    process.exitCode = 1;
    return;
  }
  const sha = createHash("sha256").update(bytes).digest("hex");
  ok(`emitted sheet: ${bytes.length} B, sha256 ${sha.slice(0, 16)}…`);

  // 6. the macro-free twin rode the same path.
  if (bytes.toString("utf8").includes('data-scheme="DemoHandWritten"') && bytes.toString("utf8").includes("#dc2626"))
    ok(`the emitted sheet carries the hand-written twin's scheme (macro-free provider through the same path)`);
  else bad(`the emitted sheet does not carry the hand-written twin's scoping`);

  // 4 + 5. the page links the emitted address; the route serves the emitted bytes.
  const page = await waitForServer();
  if (page === null) {
    bad(`server did not become ready on :${PORT} (binary: ${BINARY})`);
    console.log(serverLog.split("\n").slice(-6).join("\n"));
    process.exitCode = 1;
    return;
  }
  ok(`server ready on :${PORT}`);
  const link = /\/__assets\/theme\.[a-f0-9]{64}/.exec(page)?.[0];
  if (link === undefined) {
    bad(`the served page links no content-addressed theme sheet`);
  } else if (link.endsWith(sha)) {
    ok(`the page links the EMITTED bytes' address (${link.slice(0, 40)}…)`);
  } else {
    bad(`the linked address does not match sha256(emitted bytes): link ${link.slice(-16)} vs ${sha.slice(-16)}`);
  }
  if (link !== undefined) {
    const res = await fetch(`http://127.0.0.1:${PORT}${link}`);
    const served = Buffer.from(await res.arrayBuffer());
    if (res.status === 200 && served.equals(bytes)) ok(`the theme route serves the emitted bytes verbatim (HTTP 200, ${served.length} B)`);
    else bad(`theme route mismatch: HTTP ${res.status}, ${served.length} B vs emitted ${bytes.length} B`);
  }

  // 7. stamp stability across a second tool run.
  if (!existsSync(TOOL)) {
    try { execFileSync("swift", ["build", "--target", "WebUIThemeTool"], { cwd: ROOT, stdio: "inherit" }); } catch (e) {}
  }
  if (existsSync(TOOL)) {
    const dir = mkdtempSync(join(tmpdir(), "g-theme-"));
    try {
      const runs = [1, 2].map((n) => {
        const out = join(dir, `Run${n}.swift`);
        execFileSync(TOOL, ["--sources", CATALOG_SOURCE, "--catalog", "DemoCatalog",
                            "--type-name", `Run${n}Sheet`, "--output", out, "--work-dir", dir], { stdio: "pipe" });
        return emittedBytes(readFileSync(out, "utf8"));
      });
      if (runs[0] && runs[1] && runs[0].equals(runs[1])) ok(`stamp stable: two tool runs over the same catalog are byte-identical (${runs[0].length} B)`);
      else bad(`stamp instability: the two tool runs differ`);
      if (runs[0] && runs[0].equals(bytes)) ok(`the tool's direct output equals the plugin-emitted bytes`);
      else bad(`the tool's direct output differs from the plugin-emitted bytes`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  } else {
    bad(`WebUIThemeTool binary unavailable — cannot check stamp stability`);
  }

  try { server.kill(); } catch (e) {}
  console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    console.log(serverLog.split("\n").slice(-8).join("\n"));
    process.exitCode = 1;
  } else {
    console.log("G-THEME GREEN PASS (verdict-parametric: mechanism (a))");
  }
}

run().catch((e) => { bad(`probe crashed: ${e}`); try { server.kill(); } catch (_) {} process.exitCode = 1; });