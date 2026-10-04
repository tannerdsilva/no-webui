#!/usr/bin/env node
// designer/probes/e-manifest.mjs — lane-E wave-3: the served allowlist slice.
// the engine fetches /ui/continuum-manifest.json at boot (B's
// ContinuumEngineManifest served asset) and REPLACES the wave-1 static seed
// (ATTR_ALLOW_EXACT / ATTR_ALLOW_PREFIX) with the manifest's
// `attributeAllowlist`; a missing/malformed manifest falls back to the seed
// silently. probed with a mocked route on a lane-E port (9267):
//   page A (manifest served): exact entry "x-accent" allowed; prefix "y-*"
//     allowed; "aria-*" NOT re-granted (replace semantics — proves the seed was
//     replaced, not unioned); seed-only names stay allowed when present.
//   page B (404): the seed still governs (x-accent skipped, data-*/aria-*
//     allowed), and no warning is emitted for the absent manifest.
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startProbeServer } from "./e-lib.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PORT = 9267;

// intentionally omits aria-* (present in the wave-1 seed) to prove the engine
// REPLACES the seed with the manifest rather than unioning it.
const MANIFEST = { attributeAllowlist: ["class", "data-*", "x-accent", "y-*"] };

const bodyHtml = `<div id="t-a"></div><div id="t-b"></div><div id="t-c"></div><div id="t-d"></div><div id="t-e"></div>`;

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const check = (name, cond, extra) => (cond ? ok(name) : bad(`${name}${extra ? " — " + extra : ""}`));

async function runCase(serveManifest) {
  const { base, close } = await startProbeServer(PORT, bodyHtml, {
    enginePath: join(ROOT, "designer/assets/webui-engine.js"),
    routes: serveManifest ? { "/ui/continuum-manifest.json": { type: "application/json", body: Buffer.from(JSON.stringify(MANIFEST)) } } : {},
  });
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 800, height: 600 } });
  const page = await context.newPage();
  const warns = [];
  page.on("console", (m) => { if (m.type() === "warning" && m.text().includes("[WebUIEngine]")) warns.push(m.text()); });
  await page.goto(base + "/", { waitUntil: "load" });
  await page.waitForSelector("#probe[data-ready]", { timeout: 15000 });
  if (serveManifest) {
    await page.waitForResponse((r) => r.url().includes("/ui/continuum-manifest.json"), { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(300); // allow the allowlist swap to land
  } else {
    await page.waitForTimeout(600); // 404 path resolves; seed governs
  }
  const label = serveManifest ? "manifest-served" : "manifest-404";
  // one attr op per target element (the coalescer collapses per-target)
  const applyAttr = (tid, name, value, seq) => page.evaluate((a) => {
    window.WebUIEngine._getInstance().patch([{ id: a.tid, op: "attr", name: a.name, value: a.value }], a.seq);
  }, { tid, name, value, seq });
  const attr = (tid, name) => page.evaluate((a) => { const el = document.getElementById(a.tid); return el ? el.getAttribute(a.name) : null; }, { tid, name });

  if (serveManifest) {
    await applyAttr("t-a", "x-accent", "1", 1);
    await applyAttr("t-b", "y-mark", "2", 2);
    await applyAttr("t-c", "aria-label", "replaced?", 3);
    await applyAttr("t-d", "class", "c", 4);
    await applyAttr("t-e", "data-tag", "d", 5);
    await page.waitForTimeout(250);
    check(`${label}: exact manifest entry x-accent applied`, (await attr("t-a", "x-accent")) === "1");
    check(`${label}: prefix manifest entry y-* applied`, (await attr("t-b", "y-mark")) === "2");
    check(`${label}: aria-* NOT re-granted (seed replaced, not unioned)`, (await attr("t-c", "aria-label")) === null);
    check(`${label}: class still allowed`, (await attr("t-d", "class")) === "c");
    check(`${label}: data-* re-granted by manifest`, (await attr("t-e", "data-tag")) === "d");
    const skipped = warns.filter((w) => w.includes("aria-label")).length;
    check(`${label}: aria-label skipped with one warning`, skipped === 1, warns.join(" | "));
  } else {
    await applyAttr("t-a", "x-accent", "1", 1);
    await applyAttr("t-b", "data-ok", "2", 2);
    await applyAttr("t-c", "aria-label", "3", 3);
    await page.waitForTimeout(250);
    check(`${label}: x-accent not on the seed → skipped`, (await attr("t-a", "x-accent")) === null);
    check(`${label}: data-* seed prefix still allowed`, (await attr("t-b", "data-ok")) === "2");
    check(`${label}: aria-* seed prefix still allowed`, (await attr("t-c", "aria-label")) === "3");
    check(`${label}: manifest 404 emitted no warning`, warns.every((w) => !w.includes("continuum-manifest.json")), warns.join(" | "));
  }
  await browser.close();
  close();
}

await runCase(true);
await runCase(false);
console.log("");
if (fail === 0) console.log(`e-manifest: ${pass} PASS, 0 FAIL`);
else console.log(`e-manifest: ${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
