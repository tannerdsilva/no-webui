#!/usr/bin/env node
// designer/theme-default-probe.mjs — the W5.4 theming gate.
//
// drives the REAL WebUIExample demo host on :48000 with headless chromium and
// asserts, on COMPUTED STYLE (never markup), the whole W5.4 stack:
//
//   /theme-default  what a host that never themes gets: the framework's own
//                   look THROUGH the theme machinery — `.standard` renders
//                   nothing, so the inline styles carry no theme block and
//                   the framework's token values are provably in force (the
//                   control every other assertion is read against).
//   /theme-light    the demo's three typed token overrides take effect, and
//                   the host component's StyleSheet rules land.
//   /theme-dark     the same three overrides, dark-tuned, its dark values
//                   landing through the theme's own :root tokens (the ambient
//                   OS media state stays put — nothing here depends on it).
//
// the gate also asserts the demo's own bytes: zero `!important` anywhere a
// demo byte ships, and exactly three token overrides per themed page.
// self-contained: builds, spawns the host, drives, tears down. never patches
// the page's runtime, never screenshots.
//
// usage: node designer/theme-default-probe.mjs

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 48000;
const BASE = `http://127.0.0.1:${PORT}`;

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"], ...opts });
    let out = "";
    p.stdout?.on("data", (d) => (out += d));
    p.stderr?.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
  });
}

async function waitForServer(tries = 60) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(BASE + "/theme-light");
      const body = await r.text();
      // prove this is our own freshly spawned demo: the theming page, with
      // the host component's callout id on the wire.
      if (r.ok && body.includes("Theming demo") && body.includes("id=\"theme-callout\"")) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

// the framework values a never-themed host gets — the control set.
const FW = {
  primary: "rgb(79, 70, 229)",     // --color-primary-600 = var(--color-primary-solid)
  bg: "rgb(244, 246, 248)",        // --color-bg
  border: "rgb(226, 232, 240)",    // --color-border
  text: "rgb(15, 23, 42)",         // --color-text
  onPrimary: "rgb(255, 255, 255)", // --color-on-primary-solid
};
// the demo's three overrides, per theme, in css-hex and computed-rgb.
const THEMES = {
  light: {
    css: { primary: "#0d9488", bg: "#faf9f7", border: "#e7e2da" },
    rgb: { primary: "rgb(13, 148, 136)", bg: "rgb(250, 249, 247)", border: "rgb(231, 226, 218)" },
  },
  dark: {
    css: { primary: "#2dd4bf", bg: "#0b1120", border: "#334155" },
    rgb: { primary: "rgb(45, 212, 191)", bg: "rgb(11, 17, 32)", border: "rgb(51, 65, 85)" },
  },
};

console.log("=== theme default probe ===\n");

// 1. build so the demo binary is current.
const built = await run("swift", ["build"]);
if (built.code !== 0) { console.log(built.out.slice(-400)); bad("swift build"); process.exit(1); }
const shown = await run("swift", ["build", "--show-bin-path"]);
const binPath = join(shown.out.trim(), "WebUIExample");

let server = null;
process.on("exit", () => { if (server) { try { server.kill("SIGKILL"); } catch {} } });
server = spawn(binPath, ["--port", String(PORT)], { cwd: ROOT, stdio: ["ignore", "ignore", "ignore"] });
if (!(await waitForServer())) {
  bad("server did not become ready on :48000 (kill any WebUIExample holding the port and re-run)");
  process.exit(1);
}
ok("demo host ready on :48000 (fresh port band)");

const inlineStyles = (html) => [...html.matchAll(/<style>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join("\n");
const themeBlockTokens = (html) => {
  // the theme's `:root` block: every `--name: value;` token declaration
  // inside it (color-scheme is a property, not a --token, so it never counts).
  const m = html.match(/<style>[\s\S]*?:root \{([\s\S]*?)\}/);
  if (!m) return [];
  return [...m[1].matchAll(/--([a-z0-9-]+):\s*([^;]+);/g)].map((x) => x[1]);
};

// 2. byte-level structure: the demo's own bytes, read off each route.
for (const route of ["default", "light", "dark"]) {
  const html = await (await fetch(`${BASE}/theme-${route}`)).text();
  const css = inlineStyles(html);
  if (!css.includes("!important")) ok(`theme-${route}: demo's own bytes contain zero !important`);
  else bad(`theme-${route}: !important leaked into the demo's inline bytes`);
  if (css.includes("@layer webui, webui.utilities, host;") && css.includes("@layer host {"))
    ok(`theme-${route}: host component's @layer host sheet ships`);
  else bad(`theme-${route}: host layer statement/block missing`);
}

{
  const html = await (await fetch(`${BASE}/theme-default`)).text();
  const css = inlineStyles(html);
  const hasThemeBlock = css.includes("color-scheme:") || css.includes("--color-primary-solid:");
  if (!hasThemeBlock) ok("theme-default: a host that never themes ships NO theme bytes (the framework's own look, through the machinery)");
  else bad("theme-default: an empty (.standard) theme must render nothing inline");
}

for (const [name, t] of Object.entries(THEMES)) {
  const html = await (await fetch(`${BASE}/theme-${name}`)).text();
  const css = inlineStyles(html);
  const tokens = themeBlockTokens(html);
  const entries = [
    ["color-primary-solid", t.css.primary],
    ["color-bg", t.css.bg],
    ["color-border", t.css.border],
  ];
  if (entries.every(([k, v]) => css.includes(`--${k}: ${v};`)))
    ok(`theme-${name}: theme block ships the three typed overrides (${entries.map(([k]) => k).join(", ")})`);
  else bad(`theme-${name}: theme block overrides wrong — found ${tokens.join(", ")}`);
  if (tokens.length === 3 && entries.every(([k]) => tokens.includes(k)))
    ok(`theme-${name}: EXACTLY three tokens overridden (${tokens.join(", ")})`);
  else bad(`theme-${name}: expected exactly three overridden tokens, got ${tokens.length}`);
  if (css.includes(`color-scheme: ${name};`)) ok(`theme-${name}: mode declares color-scheme: ${name}`);
  else bad(`theme-${name}: color-scheme: ${name} missing from the theme block`);
}

// 3. computed style: drive all three routes in fresh contexts (no stored
//    theme choice can leak between them), emulated light so the unthemed
//    page reads the framework's light values deterministically.
const browser = await chromium.launch();
try {
  const measure = async (route) => {
    const context = await browser.newContext({ colorScheme: "light" });
    const page = await context.newPage();
    await page.goto(`${BASE}/theme-${route}`, { waitUntil: "load" });
    await page.waitForTimeout(120); // let the linked sheet settle
    const m = await page.evaluate(() => {
      const cs = (sel) => {
        const s = getComputedStyle(document.querySelector(sel));
        return {
          borderTopColor: s.borderTopColor,
          borderTopWidth: s.borderTopWidth,
          borderTopStyle: s.borderTopStyle,
          borderTopLeftRadius: s.borderTopLeftRadius,
          paddingTop: s.paddingTop,
          color: s.color,
          backgroundColor: s.backgroundColor,
        };
      };
      return {
        darkPref: matchMedia("(prefers-color-scheme: dark)").matches,
        lightPref: matchMedia("(prefers-color-scheme: light)").matches,
        colorScheme: getComputedStyle(document.documentElement).colorScheme,
        bodyBg: getComputedStyle(document.body).backgroundColor,
        bodyColor: getComputedStyle(document.body).color,
        callout: cs("#theme-callout"),
        calloutTitle: getComputedStyle(document.querySelector(".theme-callout__title")).color,
        button: cs("#theme-button"),
        card: cs("#theme-card"),
      };
    });
    await context.close();
    return m;
  };

  const d = await measure("default");

  // ── the default page: the CONTROL — the framework's values in force. ──
  if (d.button.backgroundColor === FW.primary) ok(`default: framework primary on the button (${FW.primary})`);
  else bad(`default: button background ${d.button.backgroundColor}, expected ${FW.primary}`);
  if (d.bodyBg === FW.bg) ok(`default: framework page canvas (${FW.bg})`);
  else bad(`default: body background ${d.bodyBg}, expected ${FW.bg}`);
  if (d.card.borderTopColor === FW.border) ok(`default: framework card hairline (${FW.border})`);
  else bad(`default: card border ${d.card.borderTopColor}, expected ${FW.border}`);
  if (d.callout.borderTopColor === FW.primary) ok("default: host component reads the FRAMEWORK token (callout border = framework primary)");
  else bad(`default: callout border ${d.callout.borderTopColor}, expected ${FW.primary}`);
  if (d.calloutTitle === FW.primary) ok("default: callout title colour follows the framework token too");
  else bad(`default: callout title ${d.calloutTitle}, expected ${FW.primary}`);
  if (d.callout.borderTopWidth === "3px" && d.callout.borderTopStyle === "solid")
    ok("default: host sheet's own rule in force (3px solid border)");
  else bad(`default: host rule missing — width ${d.callout.borderTopWidth} style ${d.callout.borderTopStyle}`);
  if (d.callout.paddingTop === "16px") ok("default: host sheet padding via --space-4 (16px)");
  else bad(`default: callout padding ${d.callout.paddingTop}, expected 16px`);
  if (d.callout.borderTopLeftRadius === "12px") ok("default: host sheet radius via --radius-xl (12px)");
  else bad(`default: callout radius ${d.callout.borderTopLeftRadius}, expected 12px`);
  if (d.bodyColor === FW.text && d.button.color === FW.onPrimary)
    ok("default: unoverridden tokens still in force (text + on-primary)");
  else bad(`default: control leak — body color ${d.bodyColor}, button text ${d.button.color}`);
  if (!d.darkPref) ok("default: prefers-color-scheme: dark does NOT match (never-themed host)");
  else bad("default: unexpected dark preference");

  // ── the two themed pages: the overrides demonstrably land. ──
  for (const [name, t] of Object.entries(THEMES)) {
    const m = await measure(name);
    if (m.button.backgroundColor === t.rgb.primary)
      ok(`theme-${name}: button follows the overridden --color-primary-solid (${t.rgb.primary})`);
    else bad(`theme-${name}: button background ${m.button.backgroundColor}, expected ${t.rgb.primary}`);
    if (m.bodyBg === t.rgb.bg) ok(`theme-${name}: page canvas follows the overridden --color-bg (${t.rgb.bg})`);
    else bad(`theme-${name}: body background ${m.bodyBg}, expected ${t.rgb.bg}`);
    if (m.card.borderTopColor === t.rgb.border)
      ok(`theme-${name}: card hairline follows the overridden --color-border (${t.rgb.border})`);
    else bad(`theme-${name}: card border ${m.card.borderTopColor}, expected ${t.rgb.border}`);
    if (m.callout.borderTopColor === t.rgb.primary && m.calloutTitle === t.rgb.primary)
      ok(`theme-${name}: host component restyled by the theme through its own sheet (${t.rgb.primary})`);
    else bad(`theme-${name}: callout border ${m.callout.borderTopColor}, title ${m.calloutTitle}, expected ${t.rgb.primary}`);
    if (m.callout.borderTopWidth === "3px" && m.callout.paddingTop === "16px" && m.callout.borderTopLeftRadius === "12px")
      ok(`theme-${name}: host sheet's own geometry untouched by the theme (3px / 16px / 12px)`);
    else bad(`theme-${name}: host geometry moved under theme — ${m.callout.borderTopWidth}/${m.callout.paddingTop}/${m.callout.borderTopLeftRadius}`);
    if (m.bodyColor === FW.text && m.button.color === FW.onPrimary)
      ok(`theme-${name}: CONTROL — the other 171 tokens still carry framework values (text + on-primary)`);
    else bad(`theme-${name}: theme clobbered unoverridden tokens — body ${m.bodyColor}, button ${m.button.color}`);
    // prefers-color-scheme follows the OS (emulated light), NOT the page's
    // `color-scheme` — measured: headless chromium keeps the media query on
    // the ambient preference even under `color-scheme: dark`. so on every
    // themed page the ambient preference must stay light while the exact
    // rgb assertions above prove the dark values still land through the
    // theme's own :root tokens — none of this demo's looks depend on the OS.
    if (!m.darkPref && m.lightPref)
      ok(`theme-${name}: dark values come from the theme's :root tokens, not the OS media state (prefers-color-scheme stays light)`);
    else bad(`theme-${name}: media state shifted — dark=${m.darkPref} light=${m.lightPref}`);
    if (m.colorScheme.includes(name)) ok(`theme-${name}: computed color-scheme reflects the mode (${m.colorScheme})`);
    else bad(`theme-${name}: computed color-scheme ${m.colorScheme}, expected ${name}`);
  }
} catch (err) {
  bad(`gate threw: ${err}`);
} finally {
  await browser.close().catch(() => {});
}

if (server) { try { server.kill("SIGKILL"); } catch {} }

console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
if (fail > 0) { console.log("THEME DEFAULT PROBE FAIL"); process.exit(1); }
console.log("THEME DEFAULT PROBE PASS");
process.exit(0);
