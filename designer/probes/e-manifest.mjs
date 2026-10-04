#!/usr/bin/env node
// designer/probes/e-manifest.mjs — lane-E probe: the served manifest slice
// (DX-6e extended). the engine fetches /ui/continuum-manifest.json at boot and:
//   - v1 payload: `attributeAllowlist` REPLACES the wave-1 static seed
//     (exact + prefix entries; replace, not union — probe page A);
//   - v2 payload (DX-6e): `islands[]` maps capability name -> content-addressed
//     URL the engine's loadIsland consumes, with the name-convention URL
//     `/__assets/webui-<name>.wasm` kept as the fallback when islands[] is
//     absent (v1) or the manifest 404s;
//   - a missing/malformed manifest falls back to the seed silently.
// probed with mocked routes on lane ports (9267):
//   v1 page: the seed is replaced by the manifest allowlist, and island "feed"
//     loads via the CONVENTION url (no islands[] in v1).
//   v2 page: allowlist semantics identical, and island "feed" loads via the
//     CONTENT-ADDRESSED url from islands[]; the convention url is NOT hit.
//   404 page: the seed governs; island "feed" loads via the convention url;
//     no warning is emitted for the absent manifest.
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";
import { buildProbeWasm } from "./e-island-wasm.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9267;

// intentionally omits aria-* (present in the wave-1 seed) to prove the engine
// REPLACES the seed with the manifest rather than unioning it.
const ALLOWLIST = ["class", "data-*", "x-accent", "y-*"];
// content-addressed variant of the convention URL (the sha-stamp form).
const CA_URL = "/__assets/webui-feed-81c4b1a2.wasm";
const V1_MANIFEST = { version: 1, attributeAllowlist: ALLOWLIST };
const V2_MANIFEST = { version: 2, attributeAllowlist: ALLOWLIST, islands: [{ name: "feed", url: CA_URL }] };

const probeWasm = buildProbeWasm();

const bodyHtml = `<div id="t-a"></div><div id="t-b"></div><div id="t-c"></div><div id="t-d"></div><div id="t-e"></div><div id="feed" data-webui-island="feed"></div>`;

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

async function runCase(label, manifest) {
  const routes = { "/__assets/webui-feed.wasm": { type: "application/wasm", body: Buffer.from(probeWasm) }, [CA_URL]: { type: "application/wasm", body: Buffer.from(probeWasm) } };
  if (manifest) routes["/ui/continuum-manifest.json"] = { type: "application/json", body: Buffer.from(JSON.stringify(manifest)) };
  const { base, close } = await startProbeServer(PORT, bodyHtml, {
    enginePath: join(ROOT, "designer/assets/webui-engine.js"),
    routes,
  });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 800, height: 600 } });
  const page = await context.newPage();
  const warns = [];
  const wasmRequests = [];
  page.on("console", (m) => { if (m.type() === "warning" && m.text().includes("[WebUIEngine]")) warns.push(m.text()); });
  page.on("request", (r) => { if (r.url().includes("webui-feed")) wasmRequests.push(r.url()); });
  await page.goto(base + "/", { waitUntil: "load" });
  await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });
  if (manifest) {
    await page.waitForResponse((r) => r.url().includes("/ui/continuum-manifest.json"), { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(300); // allow the allowlist swap to land
  } else {
    await page.waitForTimeout(600); // 404 path resolves; seed governs
  }
  // the feed island must mount through whichever URL path the manifest chose.
  await page.waitForFunction(() => {
    const el = document.getElementById("feed");
    return el && el.getAttribute("data-webui-island-state") === "mounted";
  }, { timeout: 10000 }).catch(() => {});
  // one attr op per target element (the coalescer collapses per-target)
  const applyAttr = (tid, name, value, seq) => page.evaluate((a) => {
    window.WebUIEngine._getInstance().patch([{ id: a.tid, op: "attr", name: a.name, value: a.value }], a.seq);
  }, { tid, name, value, seq });
  const attr = (tid, name) => page.evaluate((a) => { const el = document.getElementById(a.tid); return el ? el.getAttribute(a.name) : null; }, { tid, name });

  if (manifest) {
    await applyAttr("t-a", "x-accent", "1", 1);
    await applyAttr("t-b", "y-mark", "2", 2);
    await applyAttr("t-c", "aria-label", "replaced?", 3);
    await applyAttr("t-d", "class", "c", 4);
    await applyAttr("t-e", "data-tag", "d", 5);
  } else {
    await applyAttr("t-a", "x-accent", "1", 1);
    await applyAttr("t-b", "data-ok", "2", 2);
    await applyAttr("t-c", "aria-label", "3", 3);
  }
  await page.waitForTimeout(250);

  if (manifest) {
    check(`${label}: exact manifest entry x-accent applied`, (await attr("t-a", "x-accent")) === "1");
    check(`${label}: prefix manifest entry y-* applied`, (await attr("t-b", "y-mark")) === "2");
    check(`${label}: aria-* NOT re-granted (seed replaced, not unioned)`, (await attr("t-c", "aria-label")) === null);
    check(`${label}: class still allowed`, (await attr("t-d", "class")) === "c");
    check(`${label}: data-* re-granted by manifest`, (await attr("t-e", "data-tag")) === "d");
    const skipped = warns.filter((w) => w.includes("aria-label")).length;
    check(`${label}: aria-label skipped with one warning`, skipped === 1, warns.join(" | "));
  } else {
    check(`${label}: x-accent not on the seed → skipped`, (await attr("t-a", "x-accent")) === null);
    check(`${label}: data-* seed prefix still allowed`, (await attr("t-b", "data-ok")) === "2");
    check(`${label}: aria-* seed prefix still allowed`, (await attr("t-c", "aria-label")) === "3");
    check(`${label}: manifest 404 emitted no warning`, warns.every((w) => !w.includes("continuum-manifest.json")), warns.join(" | "));
  }

  // DX-6e: the island URL path is a function of the manifest payload.
  const mounted = await page.evaluate(() => document.getElementById("feed").getAttribute("data-webui-island-state") === "mounted");
  if (manifest && manifest.islands) {
    check(`${label}: feed loaded via the CONTENT-ADDRESSED islands[] url (${CA_URL})`, mounted && wasmRequests.includes(base + CA_URL), wasmRequests.join(" | ") || "(none)");
    check(`${label}: the name-convention url was NOT hit when islands[] names a url`, !wasmRequests.includes(base + "/__assets/webui-feed.wasm"), wasmRequests.join(" | "));
  } else {
    check(`${label}: feed loaded via the name-convention fallback url`, mounted && wasmRequests.includes(base + "/__assets/webui-feed.wasm"), wasmRequests.join(" | ") || "(none)");
  }
  await browser.close();
  close();
}

await runCase("v1-manifest", V1_MANIFEST);
await runCase("v2-manifest", V2_MANIFEST);
await runCase("manifest-404", null);
console.log("");
if (fail === 0) console.log(`e-manifest: ${pass} PASS, 0 FAIL`);
else console.log(`e-manifest: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
