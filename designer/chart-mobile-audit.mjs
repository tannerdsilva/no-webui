#!/usr/bin/env node
// designer/chart-mobile-audit.mjs  the chart responsive-text gate.
//
// spawns the showcase server, sweeps 320 / 390 / 480 / 768 / 1024 / 1440 in both
// themes, and asserts the contract every chart must hold: text is never painted
// below 11px, axis labels never collide, the page never overflows horizontally,
// and no hover tip is clipped by the scroller that lets a plot pan instead of
// shrinking. evidence (screenshots + the measured table) lands in
// .smoke/chart-mobile-<date>/.
//
// painted px = css font-size x (rendered svg width / viewBox width). html text
// (the legend) is not inside the viewBox and is measured at its css size.
//
// usage: node designer/chart-mobile-audit.mjs
// the server binary may be overridden for a scratch build (the package .build
// lock is held by a running plugin): WEBUI_CHART_AUDIT_SERVER=/path/to/binary

import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9099;
const SERVER = process.env.WEBUI_CHART_AUDIT_SERVER ?? join(ROOT, ".build/debug/WebUIShowcaseServer");
const VIEWPORTS = [{ w: 320, h: 900 }, { w: 390, h: 900 }, { w: 480, h: 900 },
                   { w: 768, h: 900 }, { w: 1024, h: 900 }, { w: 1440, h: 900 }];
const THEMES = ["light", "dark"];
const MIN_PAINTED_PX = 11;

const stamp = new Date().toISOString().slice(0, 10);
const OUT = join(ROOT, ".smoke", "chart-mobile-" + stamp);
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

const MEASURE = () => {
  const cls = [".chart__axis-label", ".chart__axis-title", ".chart__legend-item",
               ".chart__donut-value", ".chart__tip text"];
  const svgScale = (el) => {
    const svg = el.closest("svg");
    if (!svg) { return 1; }
    const vb = (svg.getAttribute("viewBox") || "").trim().split(/\s+/);
    const vbw = parseFloat(vb[2]) || svg.getBoundingClientRect().width;
    const rw = svg.getBoundingClientRect().width;
    return vbw > 0 ? rw / vbw : 1;
  };
  const figures = [];
  document.querySelectorAll("figure.chart").forEach((fig) => {
    const svg = fig.querySelector("svg");
    const scroller = fig.querySelector(".chart__plot") || fig;
    const sr = scroller.getBoundingClientRect();
    const svgR = svg ? svg.getBoundingClientRect() : null;
    const texts = [];
    cls.forEach((sel) => {
      fig.querySelectorAll(sel).forEach((el) => {
        const cs = getComputedStyle(el);
        const painted = parseFloat(cs.fontSize) * svgScale(el);
        const r = el.getBoundingClientRect();
        texts.push({ sel, painted: +painted.toFixed(2), box: [r.left, r.top, r.right, r.bottom] });
      });
    });
    const axis = [];
    fig.querySelectorAll(".chart__axis-label").forEach((el) => {
      const r = el.getBoundingClientRect();
      axis.push([r.left, r.top, r.right, r.bottom]);
    });
    let collisions = 0;
    for (let i = 0; i < axis.length; i++) {
      for (let j = i + 1; j < axis.length; j++) {
        const a = axis[i], b = axis[j];
        const ox = Math.min(a[2], b[2]) - Math.max(a[0], b[0]);
        const oy = Math.min(a[3], b[3]) - Math.max(a[1], b[1]);
        if (ox > 0.5 && oy > 0.5) { collisions++; }
      }
    }
    let clippedTips = 0;
    let pannedTips = 0;
    const svgBox = svgR;
    fig.querySelectorAll(".chart__tip").forEach((tip) => {
      const r = tip.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) { return; }
      if (!svgBox) { return; }
      // vertical ink outside the svg box is unreachable: the scroller hides
      // overflow-y, so a tip that escapes vertically is genuinely lost.
      if (r.top < svgBox.top - 1 || r.bottom > svgBox.bottom + 1) { clippedTips++; }
      // horizontal ink outside the svg box is reachable by panning the plot.
      if (r.left < svgBox.left - 1 || r.right > svgBox.right + 1) { pannedTips++; }
    });
    figures.push({
      title: (fig.querySelector(".chart__title") || {}).textContent || "(untitled)",
      designW: parseFloat(fig.style.getPropertyValue("--chart-w")) || null,
      viewBoxW: svg ? parseFloat((svg.getAttribute("viewBox") || "").split(/\s+/)[2]) : null,
      svgW: svgR ? Math.round(svgR.width) : null,
      containerW: Math.round(sr.width),
      pans: scroller.scrollWidth > scroller.clientWidth + 1,
      visiblePct: svgR && svgR.width > 0 ? Math.min(100, Math.round((sr.width / svgR.width) * 100)) : null,
      minPainted: texts.length ? Math.min(...texts.map((t) => t.painted)) : null,
      worstSel: texts.length ? texts.reduce((m, t) => (t.painted < m.painted ? t : m), texts[0]).sel : null,
      collisions,
      clippedTips,
      pannedTips,
    });
  });
  return {
    figures,
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  };
};

const server = spawn(SERVER, ["--port", String(PORT)], { cwd: ROOT });
let log = "";
server.stdout.on("data", (d) => (log += d));
server.stderr.on("data", (d) => (log += d));

if (!(await waitFor("http://127.0.0.1:" + PORT + "/"))) {
  console.log("  FAIL server did not come up on :" + PORT + " (" + log.slice(-200) + ")");
  console.log("CHART MOBILE AUDIT FAIL (no server)");
  process.exit(1);
}

// precondition: we must be measuring the showcase, not a stray server.
{
  const probe = await (await fetch("http://127.0.0.1:" + PORT + "/")).text();
  const figs = (probe.match(/<figure class="chart/g) || []).length;
  if (probe.indexOf("WebUI Showcase") === -1) {
    console.log("  FAIL port " + PORT + " is serving a different page; kill the stray server and retry");
    server.kill("SIGTERM");
    process.exit(1);
  }
  if (figs < 12) {
    console.log("  FAIL expected >= 12 chart figures on the showcase, found " + figs);
    server.kill("SIGTERM");
    process.exit(1);
  }
  ok("served page is the showcase with " + figs + " chart figures");
}

const browser = await chromium.launch();
const context = await browser.newContext();
const page = await context.newPage();
const rows = [];

for (const theme of THEMES) {
  for (const vp of VIEWPORTS) {
    await page.setViewportSize({ width: vp.w, height: vp.h });
    await page.goto("http://127.0.0.1:" + PORT + "/", { waitUntil: "load" });
    await page.evaluate((t) => {
      try { localStorage.setItem("webui-theme", t); } catch (e) {}
      document.documentElement.setAttribute("data-theme", t);
    }, theme);
    await page.locator("#charts").scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(500);

    const m = await page.evaluate(MEASURE);
    const slide = vp.w + "-" + theme;
    await page.locator("#charts").screenshot({ path: join(OUT, "charts-" + slide + ".png") }).catch(() => {});

    const pans = m.figures.filter((f) => f.pans).length;
    const worst = m.figures.reduce((a, b) => (a.minPainted ?? 99) <= (b.minPainted ?? 99) ? a : b, m.figures[0]);
    const leastVisible = m.figures.reduce((a, b) => (a.visiblePct ?? 100) <= (b.visiblePct ?? 100) ? a : b, m.figures[0]);
    console.log("  " + slide + ": worst painted " + (worst.minPainted ?? "n/a") + "px (" + worst.worstSel +
                "), " + pans + "/" + m.figures.length + " pan, least visible " + (leastVisible.visiblePct ?? "n/a") +
                "%, overflow " + m.overflow + "px");


    if (m.overflow > 1) { bad(slide + ": page overflows horizontally by " + m.overflow + "px"); }
    else { ok(slide + ": no page overflow"); }

    // fitting is the other half of the contract: from 390px up the page must
    // give every chart enough room, so nothing hides behind a pan. 320px is
    // reported, not asserted (that width leaves the page ~256px of arena).
    if (vp.w >= 390) {
      const cut = m.figures.filter((f) => f.visiblePct !== null && f.visiblePct < 100);
      if (cut.length) {
        bad(slide + ": " + cut.length + " figure(s) not fully visible, e.g. " + cut[0].title.trim() +
            " shows " + cut[0].visiblePct + "%, container " + cut[0].containerW + "px");
      } else { ok(slide + ": every chart fully visible"); }
    }

    const thin = m.figures.filter((f) => f.minPainted !== null && f.minPainted < MIN_PAINTED_PX);
    if (thin.length) {
      bad(slide + ": " + thin.length + " figure(s) paint text below " + MIN_PAINTED_PX + "px (worst " +
          thin[0].minPainted + "px on " + thin[0].worstSel + " in '" + thin[0].title.trim() + "')");
    } else { ok(slide + ": every chart paints text at >= " + MIN_PAINTED_PX + "px"); }

    const collide = m.figures.filter((f) => f.collisions > 0);
    if (collide.length) {
      bad(slide + ": " + collide.length + " figure(s) with colliding axis labels ('" + collide[0].title.trim() + "')");
    } else { ok(slide + ": no colliding axis labels"); }

    // the contract: the plot may compress to 92% of its design width - painted
    // text still lands at >= 11px - and pans rather than going below that.
    const shrunk = m.figures.filter((f) => f.designW && f.svgW !== null && f.svgW < f.designW * 0.92 - 1);
    if (shrunk.length) {
      bad(slide + ": " + shrunk.length + " figure(s) render below the 92% compression floor, e.g. " +
          shrunk[0].title.trim() + " at " + shrunk[0].svgW + "px");
    } else { ok(slide + ": no chart renders below the 92% compression floor"); }

    // desktop layout sanity: a chart that panning-hides part of its plot at a
    // desktop width means the page sized the chart by its content, not by a
    // declared width (the regression this assertion was written for: the plot
    // collapsed to the width of its own heading text).
    if (vp.w >= 768) {
      const squeezed = m.figures.filter((f) => f.designW && f.containerW < f.designW * 0.92 - 1);
      if (squeezed.length) {
        bad(slide + ": " + squeezed.length + " figure(s) squeezed below their design width at desktop ('" +
            squeezed[0].title.trim() + "': container " + squeezed[0].containerW + "px < design " + squeezed[0].designW + "px)");
      } else { ok(slide + ": desktop containers fit every chart's design width"); }
    }

    const clipped = m.figures.filter((f) => f.clippedTips > 0);
    if (clipped.length) {
      bad(slide + ": " + clipped.length + " figure(s) with hover tips escaping the plot vertically ('" + clipped[0].title.trim() + "')");
    } else { ok(slide + ": hover tips stay within the plot (pan-reachable counts as inside)"); }

    const csv = m.figures.map((f) => [vp.w, theme, f.containerW, f.designW, f.viewBoxW, f.svgW, f.pans, f.minPainted,
      f.worstSel, f.collisions, f.clippedTips, f.pannedTips, f.visiblePct].join(","));
    rows.push(...csv);
  }
}

await context.close();
await browser.close();
server.kill("SIGTERM");

const header = ["viewport", "theme", "containerW", "designW", "viewBoxW", "svgW", "pans", "minPainted", "worstSel", "collisions", "clippedTips", "pannedTips", "visiblePct"];
const csv = [header.join(",")].concat(rows).join("\n");
writeFileSync(join(OUT, "measurements.csv"), csv + "\n");

console.log("");
console.log("evidence: " + OUT);
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
console.log(fail === 0 ? "CHART MOBILE AUDIT PASS" : "CHART MOBILE AUDIT FAIL");
process.exit(fail === 0 ? 0 : 1);