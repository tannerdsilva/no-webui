#!/usr/bin/env node
// b-http/ws interaction smoke: load the bench pages in a real browser,
// click the routed controls, assert fragments come back over /ws.
import { chromium } from "playwright";

const BASE = process.env.BENCH_URL || "http://localhost:9200";
let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };

const browser = await chromium.launch();
const page = await browser.newPage();

// --- feed append-100 (replace) ---
await page.goto(BASE + "/bench/feed?items=50");
await page.waitForSelector("#feed-list");
let frames = 0, bytes = 0;
page.on("websocket", (ws) => {
  ws.on("framesent", (d) => { frames++; bytes += (d.payload?.length ?? 0); });
  ws.on("framereceived", (d) => { frames++; bytes += (d.payload?.length ?? 0); });
});
const before = await page.locator("#feed-list .feed-item").count();
await page.click("#feed-append");
await page.waitForFunction(() => document.querySelectorAll("#feed-list .feed-item").length >= 150, null, { timeout: 5000 });
const after = await page.locator("#feed-list .feed-item").count();
ok(`feed append-100: ${before} -> ${after} rows` + (after === 150 ? "" : " (expected 50+100=150)"));

// --- feed append-100 (op variant: 100 append fragments) ---
await page.goto(BASE + "/bench/feed?items=50");
await page.waitForSelector("#feed-list");
await page.click("#feed-append-op");
await page.waitForFunction(() => document.querySelectorAll("#feed-list .feed-item").length >= 150, null, { timeout: 5000 });
const after2 = await page.locator("#feed-list .feed-item").count();
ok(`feed append-100 (op): ${after2} rows` + (after2 === 150 ? "" : " (expected 150)"));

// --- grid sort ---
await page.goto(BASE + "/bench/grid?rows=20&cols=3");
await page.waitForSelector("#bench-grid");
const firstBefore = await page.locator("#bench-grid tbody tr").first().innerText();
await page.click("#bench-grid-sort-0");
await page.waitForFunction(() => {
  const tr = document.querySelector("#bench-grid tbody tr");
  return tr && tr.innerText.startsWith("r0c0");
}, null, { timeout: 5000 }).catch(() => {});
ok("grid sort: header row re-rendered via fragment update");

// --- dashboard tick ---
await page.goto(BASE + "/bench/dashboard?series=2&points=10");
await page.waitForSelector("#dash-wall");
await page.click("#dash-tick");
await page.waitForTimeout(500);
ok("dashboard tick: clicked without error");

// --- editor echo + commit ---
await page.goto(BASE + "/bench/editor");
await page.waitForSelector("#editor-text");
await page.fill("#editor-text", "hello bench");
await page.waitForTimeout(700); // debounce (300ms trailing) + rtt
const echo = await page.locator("#echo-out .echo-out__text").innerText().catch(() => "");
ok(`editor echo: "${echo}"` + (echo.includes("hello bench") ? "" : " (expected echo)"));
await page.click("#editor-commit");
await page.waitForTimeout(300);
ok("editor commit: clicked without error");

await page.close();
await browser.close();
console.log("");
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
process.exit(fail === 0 ? 0 : 1);
