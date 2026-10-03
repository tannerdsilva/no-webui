#!/usr/bin/env node
// designer/rtl-audit.mjs  p7-t5's both-direction, both-theme audit.
//
// for each audited block it renders the page twice: once LTR (the control) and
// once RTL (--dir rtl), in both themes and at three widths. it asserts
//   * the document really carries dir="rtl" (the precondition),
//   * nothing overflows horizontally,
//   * the sidebar/main order actually mirrors (the sidebar is left of main in
//     LTR and right of main in RTL) - checked as a relation, not a hardcoded x,
// and writes both-direction screenshots to .smoke/rtl-<date>/.
//
// usage: node designer/rtl-audit.mjs

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9096;
const BLOCKS = ["dashboard", "patterns", "sidebar-default"];
const VIEWPORTS = [{ w: 320, h: 900 }, { w: 768, h: 900 }, { w: 1440, h: 900 }];
const THEMES = ["light", "dark"];
const stamp = new Date().toISOString().slice(0, 10);
const OUT = join(ROOT, ".smoke", "rtl-" + stamp);
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

for (const block of BLOCKS) {
  console.log("block: " + block);
  for (const dir of ["ltr", "rtl"]) {
    const server = spawn(join(ROOT, ".build/debug/WebUIBlocksServer"),
                         ["--port", String(PORT), "--block", block, "--dir", dir], { cwd: ROOT });
    let log = "";
    server.stdout.on("data", (d) => (log += d));
    server.stderr.on("data", (d) => (log += d));
    if (!(await waitFor("http://127.0.0.1:" + PORT + "/"))) {
      bad(block + "/" + dir + ": server did not come up (" + log.slice(-140) + ")");
      server.kill("SIGTERM");
      continue;
    }
    // precondition: is this the page and the direction we asked for?
    const probe = await (await fetch("http://127.0.0.1:" + PORT + "/")).text();
    // the server always receives --dir, so ltr is explicitly declared too
    const wanted = '<html lang="en" dir="' + dir + '">';
    if (!probe.includes(wanted)) {
      bad(block + "/" + dir + ": served html does not carry " + wanted);
      server.kill("SIGTERM");
      continue;
    }
    ok(block + "/" + dir + ": served html declares its direction");

    const context = await browser.newContext();
    const page = await context.newPage();
    for (const theme of THEMES) {
      for (const vp of VIEWPORTS) {
        await page.setViewportSize({ width: vp.w, height: vp.h });
        await page.goto("http://127.0.0.1:" + PORT + "/", { waitUntil: "load" });
        await page.evaluate((t) => {
          try { localStorage.setItem("webui-theme", t); } catch (e) {}
          document.documentElement.setAttribute("data-theme", t);
        }, theme);
        await page.waitForTimeout(350);

        const m = await page.evaluate(() => {
          const side = document.querySelector(".sidebar");
          const main = document.querySelector("main");
          const r = (el) => (el ? el.getBoundingClientRect() : null);
          return {
            docDir: document.documentElement.getAttribute("dir"),
            scrollW: document.documentElement.scrollWidth,
            innerW: window.innerWidth,
            sideX: r(side) ? Math.round(r(side).x) : null,
            sideRight: r(side) ? Math.round(r(side).right) : null,
            mainX: r(main) ? Math.round(r(main).x) : null,
          };
        });
        const slide = block + "-" + dir + "-" + vp.w + "-" + theme;
        await page.screenshot({ path: join(OUT, slide + ".png"), fullPage: true });

        const over = m.scrollW - m.innerW;
        if (over > 1) { bad(slide + ": horizontal overflow " + over + "px"); }
        else { ok(slide + ": no overflow"); }

        if (m.sideX !== null && m.mainX !== null) {
          const sideFirst = m.sideX < m.mainX;
          if (dir === "ltr" && !sideFirst) { bad(slide + ": sidebar should lead in ltr"); }
          else if (dir === "rtl" && sideFirst) { bad(slide + ": sidebar should trail in rtl"); }
          else { ok(slide + ": order is " + (sideFirst ? "sidebar-first" : "main-first") + " as " + dir + " requires"); }
        }
      }
    }
    await context.close();
    server.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 250));
  }
}

await browser.close();
console.log("");
console.log("evidence: " + OUT);
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
console.log(fail === 0 ? "RTL AUDIT PASS" : "RTL AUDIT FAIL");
process.exit(fail === 0 ? 0 : 1);