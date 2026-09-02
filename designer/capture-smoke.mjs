#!/usr/bin/env node
// designer/capture-smoke.mjs — full-size light+dark previews of the live
// smoke page (the one carrying the typed per-control routing wiring).
// usage: node designer/capture-smoke.mjs
// builds, serves on :9123, captures full-page at 2x in both schemes to
// designer/previews/screenshots/, verifies the theme flip via computed styles,
// tears down. mirrors capture-previews.mjs conventions.

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9123;
const BASE = `http://127.0.0.1:${PORT}`;
const OUT = join(ROOT, "designer/previews/screenshots");

const run = (cmd, args, opts = {}) =>
  new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"], ...opts });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
  });

const waitForServer = async (base, tries = 40) => {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(base + "/");
      if (r.ok) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
};

console.log("=== capture smoke page (light + dark) ===");
const built = await run("swift", ["build"]);
if (built.code !== 0) {
  console.log(built.out.slice(-400));
  process.exit(1);
}
const shown = await run("swift", ["build", "--show-bin-path"]);
const binPath = join(shown.out.trim(), "WebUISmokeTest");

const server = spawn(binPath, {}, { cwd: ROOT, stdio: ["ignore", "ignore", "ignore"] });
if (!(await waitForServer(BASE))) {
  console.log("server did not become ready — run with --disable-sandbox");
  process.exit(1);
}

mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();

// expected flips per theme-preview-captures.md probe table (only smoke-page
// surfaces exist here: body bg, primary button, table, chart svg bg stays).
const probes = [
  ["body", "color"],
  ["body", "backgroundColor"],
  [".card", "backgroundColor"],
  ["table", "backgroundColor"],
  ["figure.chart", "backgroundColor"],
];

try {
  for (const scheme of ["light", "dark"]) {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 2400 },
      deviceScaleFactor: 2,
      colorScheme: scheme,
    });
    const page = await context.newPage();
    page.on("pageerror", (e) => console.log(`  console error (${scheme}): ${e.message}`));
    await page.goto(BASE, { waitUntil: "networkidle" });
    const file = join(OUT, `smoke-${scheme}.png`);
    await page.screenshot({ path: file, fullPage: true });
    console.log(`  wrote ${file}`);

    // computed-style probe: both surfaces flip WITH the scheme.
    const got = await page.evaluate((pairs) => {
      const out = {};
      for (const [sel, prop] of pairs) {
        const el = document.querySelector(sel);
        out[`${sel}.${prop}`] = el ? getComputedStyle(el)[prop] : "(missing)";
      }
      return out;
    }, probes);
    console.log(`  [${scheme}] ${JSON.stringify(got, null, 0)}`);

    // component surface survives: the interactive table rendered routed controls.
    const wired = await page.evaluate(
      () => document.querySelectorAll("[data-component-id]").length
    );
    console.log(`  [${scheme}] routed components on page: ${wired}`);

    // structural probes (this model is not multimodal, so verify the DOM
    // rather than the pixels): table geometry, chart svg, and the specific
    // typed-routing affordances that carry data-component-id now.
    const structure = await page.evaluate(() => {
      const pick = (sel) => (document.querySelector(sel) ? 1 : 0);
      return {
        tableHeaders: document.querySelectorAll("#interactive-table thead th").length,
        tableRows: document.querySelectorAll("#interactive-table tbody tr:not(.table__detail-row)").length,
        sortHeaders: document.querySelectorAll("[data-component-id*='-sort-']").length,
        selectAll: pick("[data-component-id$='-select-all']"),
        chartFigure: pick("figure.chart"),
        chartSvg: pick("figure.chart svg"),
        chartBars: document.querySelectorAll("[data-component-id*='-mark-']").length,
        rangeInputs: document.querySelectorAll("input, select").length,
        toasts: document.querySelectorAll("[role='alert']").length,
      };
    });
    console.log(`  [${scheme}] structure ${JSON.stringify(structure)}`);

    await context.close();
  }
} finally {
  await browser.close();
  server.kill();
  console.log("=== done ===");
}
