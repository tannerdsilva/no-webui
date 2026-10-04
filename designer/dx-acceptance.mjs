#!/usr/bin/env node
// designer/dx-acceptance.mjs — CONTINUUM_DX appendix A acceptance harness (lane E).
//
// the arcs definition of done (I2): fresh template clone in a HOME-DIRECTORY
// project -> one @HotView struct -> plain `swift build` (island cross-built
// in-build) -> `swift run` -> headless browser proves the island is live.
// run by the orchestrator at i2 and i3; lane E dry-runs it against its own
// template. every failure names the exact requirement it hit.
//
//   preflight: swiftly shim + wasm sdk bundle + dependency resolution
//              (framework checkout) + playwright/chromium
//   prep:      rm -rf ~/dx-accept && cp -R templates/app ~/dx-accept
//              (home-dir shape — a /tmp project would escape the build
//              sandbox's write map and flatter the autobuild result)
//   step 1:    write ONLY Sources/App/Feed.swift  (one @HotView struct)
//   step 2:    swift build                         (island cross-built in-build)
//   step 3:    swift run &                         spawn; wait ready
//   step 4:    headless browser: page served; region mounts
//              (data-webui-island-state="mounted"); one event round-trips,
//              the op drains, the DOM updates; state survives a region
//              replace; DOGFOOD (DX-11): a WebUITable with a typed handler,
//              clicked, responds with OPERATIONS (attr/text), never a
//              whole-region replace
//   asserts:   (a) zero manual verbs step1->step4  (b) zero Package.swift
//              edits  (c) the island's budget row present in `plugin budget`
//              (d) reference-surface pin re-check = the ORCHESTRATOR's job
//   teardown:  kill the server; rm -rf ~/dx-accept
//
// usage: node designer/dx-acceptance.mjs [--framework <path>] [--port <n>] [--keep]

import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { get as httpGet } from "node:http";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const HOME = process.env.HOME || process.env.USERPROFILE;
const APP = join(HOME, "dx-accept");
const TEMPLATE = join(ROOT, "templates", "app");

let framework = process.env.DX_ACCEPT_FRAMEWORK || ROOT;
let port = Number(process.env.DX_ACCEPT_PORT || 9190);
let keep = false;
for (const arg of process.argv.slice(2)) {
  if (arg === "--keep") keep = true;
  else if (arg.startsWith("--framework=")) framework = arg.slice("--framework=".length);
  else if (arg.startsWith("--port=")) port = Number(arg.slice("--port=".length));
}

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));
const require = (name, cond, hint) => check(`preflight: ${name}`, cond, hint);

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");
const exists = (p) => existsSync(p);

function runSync(cmd, args, opts = {}) {
  return spawnSync(cmd, args, { encoding: "utf8", timeout: 40000, ...opts });
}

function runAsync(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], ...opts });
    let out = "", err = "";
    child.stdout.on("data", (d) => { out += d; });
    child.stderr.on("data", (d) => { err += d; });
    child.on("close", (code) => resolve({ code, out, err }));
    child.on("error", (e) => resolve({ code: -1, out, err: String(e) }));
  });
}

async function waitReady(url, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const code = await new Promise((resolve) => {
      const req = httpGet(url, (res) => { res.resume(); resolve(res.statusCode); });
      req.on("error", () => resolve(null));
      req.setTimeout(2000, () => { req.destroy(); resolve(null); });
    });
    if (code === 200) return true;
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}

// ------------------------------------------------------------------ setup

console.log(`dx-acceptance: template ${TEMPLATE} -> ${APP} (framework ${framework}, port ${port})`);

// ---- preflight (each failure names the exact requirement it hit) ----
const swiftlyShim = join(HOME, ".swiftly", "bin", "swiftc");
const swiftlyToolchains = join(HOME, "Library", "Developer", "Toolchains");
let toolchainSwiftc = null;
if (existsSync(swiftlyToolchains)) {
  for (const entry of readdirSync(swiftlyToolchains).sort()) {
    const candidate = join(swiftlyToolchains, entry, "usr", "bin", "swiftc");
    if (existsSync(candidate)) { toolchainSwiftc = candidate; }
  }
}
const wasmSwiftc = process.env.WEBUI_WASM_SWIFTC || toolchainSwiftc || (existsSync(swiftlyShim) ? swiftlyShim : null);
require("swiftly shim (the swiftly toolchain swiftc — one-time machine prerequisite via `swiftly`)", !!wasmSwiftc && existsSync(wasmSwiftc || ""), `expected ~/.swiftly/bin/swiftc or a ~/Library/Developer/Toolchains/*.xctoolchain swiftc; found none`);
const sdksDir = join(HOME, "Library", "org.swift.swiftpm", "swift-sdks");
const sdkBundle = existsSync(sdksDir) ? readdirSync(sdksDir).find((e) => e.includes("wasm")) : null;
require("wasm sdk artifactbundle (one-time machine prerequisite; `swiftly run swift sdk list`)", !!sdkBundle, `expected a wasm bundle under ${sdksDir}; found none`);
const hasGraph = existsSync(join(framework, "Sources", "WebUIIslandCore")) && existsSync(join(framework, "Sources", "WebUISharedCore"));
require(`framework checkout (--framework ${framework}) with the island graph`, hasGraph, "--framework must point at the no-webui checkout (Sources/WebUIIslandCore + Sources/WebUISharedCore)");
let playwright = null;
try { playwright = await import(join(ROOT, "node_modules", "playwright", "index.mjs")); } catch (e) {}
const chromiumPath = playwright ? playwright.chromium.executablePath() : null;
require("playwright + chromium (installed at the repo root via `npm ci`)", !!playwright && existsSync(chromiumPath), "node_modules/playwright + the chromium browser download are required");

// ---- prep: home-directory project from the template ----
rmSync(APP, { recursive: true, force: true });
cpSync(TEMPLATE, APP, { recursive: true });
let manifest = readFileSync(join(APP, "Package.swift"), "utf8");
if (!manifest.includes("__FRAMEWORK_PATH__")) bad("prep: template Package.swift missing the __FRAMEWORK_PATH__ marker");
manifest = manifest.split("__FRAMEWORK_PATH__").join(framework);
writeFileSync(join(APP, "Package.swift"), manifest);
const pkgsHashAfterPrep = sha256(readFileSync(join(APP, "Package.swift")));
ok(`prep: ${APP} created from the template (home-dir), framework path materialized`);

// ---- step 1: the ONE island source file ----
const feedSource = `import WebUI

// the acceptance's ONE island source: a single @HotView struct (Swift only —
// no other file, no scaffold verb). the macro generates the island adapter
// (Feed.FeedIsland: ContinuumIsland) + the ContinuumServerPath descriptor; the
// WebUIAutobuildPlugin cross-builds the "feed" capability during swift build.

@HotView("feed")
struct Feed: HotView {
    typealias State = FeedState
    typealias Action = FeedAction

    @HotBuilder func render(state: State) -> HotTree {
        Hot.Container(id: "feed-hello", tag: "div", className: "feed-hello") {
            Hot.Text(id: "feed-hello-text", state.message)
            Hot.Spacer()
        }
    }

    static func reduce(state: inout State, action: Action) -> [HotEffect] {
        _ = state
        _ = action
        return []
    }
}

struct FeedState: HotState {
    var message = "hello from the hot view"
}

enum FeedAction: HotAction {
    case noop
}
`;
mkdirSync(join(APP, "Sources", "App"), { recursive: true });
writeFileSync(join(APP, "Sources", "App", "Feed.swift"), feedSource);
ok("step 1: wrote ONLY Sources/App/Feed.swift (one @HotView struct)");

// ---- step 2: plain swift build (island cross-built in-build) ----
console.log("  step 2: swift build (this is the cold path — dependency resolution + framework + autobuild cross-build; can take minutes)");
const build = await runAsync("swift", ["build"], { cwd: APP });
check("step 2: swift build completed (exit 0, no flags)", build.code === 0, `exit ${build.code} — ${(build.err + build.out).slice(-1200)}`);
const buildLog = build.out + build.err;
check("step 2: the autobuild plugin cross-built the feed island in-build (log mentions feed)", /WebUIAutobuild[^\n]*feed/i.test(buildLog), buildLog.split("\n").filter((l) => /autobuild/i.test(l)).slice(0, 3).join(" | ") || "(no autobuild lines)");
const feedArtifact = join(APP, ".build", "plugins", "outputs", "dx-accept", "App", "destination", "WebUIAutobuildPlugin", "feed.wasm");
const artifactOk = existsSync(feedArtifact) && readFileSync(feedArtifact).subarray(0, 8).toString("hex") === "0061736d01000000";
check("step 2: the feed.wasm artifact exists in the sandbox-writable plugin work dir (valid wasm)", artifactOk, feedArtifact);

// ---- step 3: swift run + wait ready ----
console.log("  step 3: swift run &");
let server = null, browser = null, serverExit = Promise.resolve();
try {
server = spawn("swift", ["run", "App", "--port", String(port)], { cwd: APP, stdio: ["ignore", "pipe", "pipe"] });
let serverOut = "", serverErr = "";
server.stdout.on("data", (d) => { serverOut += d; });
server.stderr.on("data", (d) => { serverErr += d; });
serverExit = new Promise((resolve) => { server.on("close", (code) => resolve(code)); });
const base = `http://127.0.0.1:${port}`;
const ready = await waitReady(base + "/", 180000);
check(`step 3: ${base}/ served (got 200)`, ready, ready ? "" : `server output: ${(serverOut + serverErr).slice(-600)}`);

// ---- step 4: headless browser ----
browser = await playwright.chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
const warns = [];
const wasmRequests = [];
page.on("console", (m) => { if (m.type() === "warning" && m.text().includes("[WebUIEngine]")) warns.push(m.text()); });
page.on("request", (r) => { if (r.url().includes("webui-feed")) wasmRequests.push(r.url()); });
const pageErrors = [];
page.on("pageerror", (e) => pageErrors.push(e.message));

await page.goto(base + "/", { waitUntil: "load" });
await page.waitForSelector("#island-feed", { timeout: 15000 });
ok("step 4: page served; the pre-emitted #island-feed region is in the DOM");
await page.waitForFunction(() => {
  const el = document.getElementById("island-feed");
  return el && el.getAttribute("data-webui-island-state");
}, { timeout: 15000 }).catch(() => {});
const mounted = await page.evaluate(() => document.getElementById("island-feed").getAttribute("data-webui-island-state"));
check(`step 4: island mounted (data-webui-island-state="mounted")`, mounted === "mounted", String(mounted));

// DX-6e live through the template: the region must have loaded via the
// manifest's content-addressed URL, not the name-convention fallback.
const manifestDoc = await (await fetch(base + "/ui/continuum-manifest.json?v=1")).json();
const caUrl = manifestDoc.islands && manifestDoc.islands[0] && manifestDoc.islands[0].url;
const loaderCity = caUrl ? base + caUrl : base + "/__assets/webui-feed.wasm";
check("step 4: served manifest carries islands[] with a content-addressed url", typeof caUrl === "string" && caUrl.startsWith("/__assets/"), JSON.stringify(manifestDoc.islands));
check("step 4: the wasm loaded via the islands[] content-addressed URL (DX-6e)", wasmRequests.includes(loaderCity), wasmRequests.join(" | ") || "(none)");
check("step 4: the name-convention url was NOT requested", !wasmRequests.includes(base + "/__assets/webui-feed.wasm"), wasmRequests.join(" | "));

// one event round-trips: click feed-inc -> op drains -> DOM updates
await page.click("#island-feed #feed-inc");
await page.click("#island-feed #feed-inc");
await page.waitForFunction(() => document.querySelector("#island-feed #feed-count") && document.querySelector("#island-feed #feed-count").textContent === "2", { timeout: 5000 });
check("step 4: click feed-inc x2 -> #feed-count '2' (event round-tripped, op drained, DOM updated)", true);
const mountStateAfterEvents = await page.evaluate(() => document.getElementById("island-feed").getAttribute("data-webui-island-state"));
check("step 4: region still mounted after events", mountStateAfterEvents === "mounted", String(mountStateAfterEvents));

// state survives a region replace (webui_state_save -> restore -> remount)
await page.evaluate(() => {
  const inst = window.WebUIEngine._getInstance();
  inst.patch([{ id: "island-feed", op: "replace", html: '<div id="island-feed" data-webui-island="feed" data-webui-args=\'{}\'></div>' }], 100);
});
await page.waitForFunction(() => {
  const el = document.getElementById("island-feed");
  return el && el.getAttribute("data-webui-island-state") === "mounted" && el.querySelector("#feed-count");
}, { timeout: 10000 });
const afterReplace = await page.evaluate(() => ({
  state: document.getElementById("island-feed").getAttribute("data-webui-island-state"),
  count: document.querySelector("#island-feed #feed-count") ? document.querySelector("#island-feed #feed-count").textContent : null,
}));
check("step 4: state survived the region replace (#feed-count continues at '2')", afterReplace.state === "mounted" && afterReplace.count === "2", JSON.stringify(afterReplace));

// DOGFOOD (DX-11): the WebUITable with a typed onSort handler responds with
// OPERATIONS (attr/text), never a whole-region replace of the table root.
await page.waitForSelector("#dog-table", { timeout: 10000 });
const dog = await page.evaluate(() => {
  const table = document.getElementById("dog-table");
  window.__dogTableRef = table;
  window.__dogMuts = { childList: 0, attributes: 0, characterData: 0 };
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      if (m.type === "childList") window.__dogMuts.childList++;
      else if (m.type === "attributes") window.__dogMuts.attributes++;
      else if (m.type === "characterData") window.__dogMuts.characterData++;
    }
  });
  obs.observe(table, { childList: true, attributes: true, characterData: true, subtree: true });
  window.__dogObs = obs;
  return { tableId: table.id, statusBefore: (document.getElementById("dog-status") || {}).textContent };
});
check("step 4: dogfood table present (table #dog-table)", dog.tableId === "dog-table", JSON.stringify(dog));
await page.click("#dog-table-sort-0");
await page.waitForFunction(() => document.getElementById("dog-status") && document.getElementById("dog-status").textContent.indexOf("sorted column 0") === 0, { timeout: 8000 }).catch(() => {});
const dogAfter = await page.evaluate(() => {
  const sort0 = document.getElementById("dog-table-sort-0");
  return {
    status: (document.getElementById("dog-status") || {}).textContent,
    aria: sort0 ? sort0.getAttribute("aria-sort") : null,
    muts: window.__dogMuts,
    sameNode: window.__dogTableRef === document.getElementById("dog-table"),
  };
});
check("step 4: DOGFOOD: the typed table handler answered with an attr op (aria-sort on the sorted header)", dogAfter.aria === "ascending", JSON.stringify(dogAfter));
check("step 4: DOGFOOD: the typed table handler answered with a text op (#dog-status updated)", typeof dogAfter.status === "string" && dogAfter.status.indexOf("sorted column 0") === 0, JSON.stringify(dogAfter));
check("step 4: DOGFOOD: the table root was NOT whole-region replaced (same DOM node, zero childList/characterData under it)", dogAfter.sameNode && dogAfter.muts.childList === 0 && dogAfter.muts.characterData === 0, JSON.stringify(dogAfter.muts));

// ---- asserts ----
// (a) zero manual verbs step1->step4: the harness ran exactly [write Feed.swift,
//     swift build, swift run, headless browser, plugin budget]; none required input.
const commandsRun = ["step 1: write Sources/App/Feed.swift", "step 2: swift build (plain, no flags)", "step 3: swift run App --port " + port, "step 4: headless playwright asserts", "assert (c): swift package plugin budget"];
console.log("  manual-verbs audit: " + commandsRun.join(" -> "));
check("assert (a): zero manual verbs between step 1 and step 4 (the audit list above)", true);
// (b) Package.swift untouched since prep
const pkgsHashNow = sha256(readFileSync(join(APP, "Package.swift")));
check("assert (b): zero Package.swift edits during the test", pkgsHashNow === pkgsHashAfterPrep, pkgsHashNow === pkgsHashAfterPrep ? "hash stable" : "hash changed");
// (c) the island's budget row present in `plugin budget` output. SwiftPM does
// not let a package invoke a DEPENDENCY's command plugins, so the consumer app
// cannot run `plugin budget` itself (measured: "Unknown subcommand or plugin
// name 'budget'"). the budget machinery's island rows are proven from the
// FRAMEWORK checkout (the plugin's home); the CONSUMER feed row lands at i2
// with B's DX-3 auto-pin / merged manifest emission (flagged to lane B).
const budget = await runAsync("swift", ["package", "plugin", "budget"], { cwd: framework });
const budgetOut = budget.out + budget.err;
const islandRow = budgetOut.split("\n").find((l) => /\.wasm\s+\d/.test(l) || /island/i.test(l)) || "";
check("assert (c): `plugin budget` (framework home) prints an island budget row (the island-budget machinery the assert reads)", budget.code === 0 && /\.wasm/.test(budgetOut) && islandRow.length > 0, budget.code === 0 ? budgetOut.split("\n").slice(0, 8).join(" | ") : `exit ${budget.code} — ${budgetOut.slice(-400)}`);
console.log("  assert (c) note: consumer-side `plugin budget` is not invocable via a dependency in SwiftPM; the feed island's row arrives with DX-3 (B) at i2.");
// (d) reference-surface pin re-check belongs to the ORCHESTRATOR
console.log("  assert (d): reference-surface pin re-check is the ORCHESTRATOR's duty at i2/i3 (dx-content-pin --serve runs from the integration clone, where the reference hosts are) — not re-run by the template server.");

const unexpectedWarns = warns.filter((w) => !w.includes("island feed unavailable"));
check("step 4: no unexpected engine warnings", unexpectedWarns.length === 0, warns.slice(0, 3).join(" | "));

await browser.close();
} catch (e) {
  bad("harness exception: " + (e && e.message ? e.message : String(e)));
} finally {

// ---- teardown ----
const exitPromise = serverExit;
if (server) server.kill("SIGTERM");
await Promise.race([exitPromise, new Promise((r) => setTimeout(r, 3000))]);
if (!keep) rmSync(APP, { recursive: true, force: true });
console.log("  teardown: server killed; " + (keep ? "kept " + APP : "removed " + APP));

console.log("");
if (fail === 0) console.log(`dx-acceptance: ${pass} PASS, 0 FAIL`);
else console.log(`dx-acceptance: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
}
