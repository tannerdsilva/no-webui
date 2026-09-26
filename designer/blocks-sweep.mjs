#!/usr/bin/env node
// designer/blocks-sweep.mjs  the p6 blocks gate.
//
// spawns the standalone blocks server once per block, sweeps 320 / 768 / 1440 in
// both themes, asserts that nothing overflows horizontally and that every block
// renders the parts it claims to, and writes the evidence to .smoke/blocks-<date>/.
//
// usage: node designer/blocks-sweep.mjs [--keep]

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9093;
const BLOCKS = ["index", "dashboard", "login", "signup",
                "sidebar-default", "sidebar-collapsible", "sidebar-rail", "sidebar-inset"];
const VIEWPORTS = [{ w: 320, h: 900 }, { w: 768, h: 900 }, { w: 1440, h: 900 }];
const THEMES = ["light", "dark"];
const expect = {
  index: [".card"],
  dashboard: [".chart__svg", ".table"],
  login: ["input[type=email]", "input[type=password]"],
  signup: [".field__hint--error", ".field__hint--success"],
  "sidebar-default": [".sidebar", ".sidebar__item--active"],
  "sidebar-collapsible": [".sidebar", ".sidebar__item-label"],
  "sidebar-rail": [".sidebar--collapsed"],
  "sidebar-inset": [".sidebar"],
};

const stamp = new Date().toISOString().slice(0, 10);
const OUT = join(ROOT, ".smoke", "blocks-" + stamp);
mkdirSync(OUT, { recursive: true });

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };

async function waitFor(url) {
  for (let i = 0; i < 40; i++) {
    try { const r = await fetch(url); if (r.ok) { return true; } } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

const browser = await chromium.launch();

for (const name of BLOCKS) {
  console.log("block: " + name);
  const server = spawn(join(ROOT, ".build/debug/WebUIBlocksServer"),
                       ["--port", String(PORT), "--block", name], { cwd: ROOT });
  let log = "";
  server.stdout.on("data", (d) => (log += d));
  server.stderr.on("data", (d) => (log += d));

  if (!(await waitFor("http://127.0.0.1:" + PORT + "/"))) {
    bad(name + ": server did not come up (" + log.slice(-200) + ")");
    server.kill("SIGTERM");
    continue;
  }

  // precondition: the page we are about to measure must be THIS block. a stray
  // server holding the port answers happily and every block then measures the
  // same page - the failure mode that read as "the fix broke three pages".
  {
    const probe = await (await fetch("http://127.0.0.1:" + PORT + "/")).text();
    const want = name === "index" ? "WebUI blocks" : "WebUI block";
    if (!probe.includes("<title>" + want)) {
      bad(name + ": port " + PORT + " is serving a different page; kill the stray server and retry");
      server.kill("SIGTERM");
      continue;
    }
    ok(name + ": served page is this block");
  }

  const context = await browser.newContext();
  const page = await context.newPage();
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text().slice(0, 140)); });
  page.on("pageerror", (e) => errors.push("pageerror: " + String(e).slice(0, 140)));

  for (const theme of THEMES) {
    for (const vp of VIEWPORTS) {
      await page.setViewportSize({ width: vp.w, height: vp.h });
      await page.goto("http://127.0.0.1:" + PORT + "/", { waitUntil: "load" });
      await page.evaluate((t) => {
        try { localStorage.setItem("webui-theme", t); } catch (e) {}
        document.documentElement.setAttribute("data-theme", t);
      }, theme);
      await page.waitForTimeout(400);

      const m = await page.evaluate(() => ({
        scrollW: document.documentElement.scrollWidth,
        innerW: window.innerWidth,
      }));
      const slide = name + "-" + vp.w + "-" + theme;
      await page.screenshot({ path: join(OUT, slide + ".png"), fullPage: true });
      const over = m.scrollW - m.innerW;
      if (over > 1) { bad(slide + ": horizontal overflow " + over + "px"); }
      else { ok(slide + ": no overflow"); }
    }
  }


  for (const sel of expect[name] ?? []) {
    const found = await page.locator(sel).count();
    if (found > 0) { ok(name + ": " + sel); }
    else { bad(name + ": expected " + sel + " in the page, found none"); }
  }
  if (errors.length) { bad(name + ": console errors: " + errors.slice(0, 2).join(" | ")); }
  else { ok(name + ": no console errors"); }

  await context.close();
  server.kill("SIGTERM");
  await new Promise((r) => setTimeout(r, 250));
}

await browser.close();
console.log("");
console.log("evidence: " + OUT);
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
console.log(fail === 0 ? "BLOCKS SWEEP PASS" : "BLOCKS SWEEP FAIL");
process.exit(fail === 0 ? 0 : 1);