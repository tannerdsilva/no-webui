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
                "sidebar-default", "sidebar-collapsible", "sidebar-rail", "sidebar-inset", "patterns"];
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
  patterns: [".carousel__track", ".menubar__trigger", ".radio-group", ".checkbox-group"],
};

// geometry the sweep could not see before: the auth card IS the block's point
// ("a centered auth card"), and a capped-width box in a centered column must be
// centered — the block-fill shim (`align-self: stretch` on .card) parked it at
// the cross-start edge at 768/1440 while looking perfectly fine at 320. the
// width check guards the other half of the contract: centering must not shrink
// the card to its content, it must keep the cap.
const centered = {
  login: { sel: ".card", cap: 416 },
  signup: { sel: ".card", cap: 416 },
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

      const spec = centered[name];
      if (spec) {
        const geo = await page.evaluate((s) => {
          const el = document.querySelector(s.sel);
          if (!el) return null;
          const c = el.getBoundingClientRect();
          const p = el.parentElement.getBoundingClientRect();
          const ps = getComputedStyle(el.parentElement);
          const contentW = p.width - parseFloat(ps.paddingLeft) - parseFloat(ps.paddingRight);
          return {
            dx: Math.round((c.x + c.width / 2) - (p.x + p.width / 2)),
            w: Math.round(c.width),
            expected: Math.round(Math.min(contentW, s.cap)),
          };
        }, spec);
        if (!geo) {
          bad(slide + ": " + spec.sel + " not found");
        } else if (Math.abs(geo.dx) > 2) {
          bad(slide + ": " + spec.sel + " off-center by " + geo.dx + "px (card " + geo.w + "px in a centered column)");
        } else if (Math.abs(geo.w - geo.expected) > 2) {
          bad(slide + ": " + spec.sel + " width " + geo.w + "px != min(column, cap) " + geo.expected + "px");
        } else {
          ok(slide + ": " + spec.sel + " centered, cap honored (" + geo.w + "px)");
        }
      }
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