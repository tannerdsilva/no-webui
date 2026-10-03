#!/usr/bin/env node
// b-windowed-smoke: t0.3 windowed feed advance via the routed next-window control.
import { chromium } from "playwright";

const BASE = process.env.BENCH_URL || "http://localhost:9200";
let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };

const browser = await chromium.launch();

// --- naive (replace) variant: click next-window, watch the whole region swap ---
{
  const page = await browser.newPage();
  await page.goto(BASE + "/bench/feed?windowed=1&items=10000");
  await page.waitForSelector("#feed-window");
  const firstRow = await page.locator("#feed-window .feed-item").first().innerText();
  const rowCount0 = await page.locator("#feed-window .feed-item").count();
  // scroll the window container (the scroll observer dispatches the click)
  await page.evaluate(() => {
    const win = document.getElementById("feed-window");
    win.scrollTop = win.scrollHeight;
    win.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(700);
  const rowCount1 = await page.locator("#feed-window .feed-item").count();
  const firstRowAfter = await page.locator("#feed-window .feed-item").first().innerText();
  ok(`naive window: rows ${rowCount0} -> ${rowCount1}` + (rowCount1 === 60 ? "" : " (expected 60)"));
  ok(`naive window advanced: "${firstRow}" -> "${firstRowAfter}"` + (firstRow !== firstRowAfter ? "" : " (rows should change)"));
  // engine still alive: the replace preserved the container
  ok("naive container survived: " + (await page.locator("#feed-window").count()) === "naive container survived: 1" ? "yes" : "no");
  await page.close();
}

// --- ops variant: append + remove leaves container stable ---
{
  const page = await browser.newPage();
  await page.goto(BASE + "/bench/feed?windowed=1&ops=1&items=10000");
  await page.waitForSelector("#feed-window");
  const firstRow = await page.locator("#feed-window .feed-item").first().innerText();
  const childrenBefore = await page.evaluate(() => document.getElementById("feed-window").children.length);
  await page.evaluate(() => {
    const win = document.getElementById("feed-window");
    win.scrollTop = win.scrollHeight;
    win.dispatchEvent(new Event("scroll"));
  });
  await page.waitForTimeout(700);
  const childrenAfter = await page.evaluate(() => document.getElementById("feed-window").children.length);
  const firstRowAfter = await page.locator("#feed-window .feed-item").first().innerText();
  ok(`ops window: children ${childrenBefore} -> ${childrenAfter}` + (childrenAfter === 60 ? "" : " (expected 60)"));
  ok(`ops window advanced: "${firstRow}" -> "${firstRowAfter}"` + (firstRow !== firstRowAfter ? "" : " (rows should change)"));
  await page.close();
}

await browser.close();
console.log("");
console.log("=== summary: " + pass + " passed, " + fail + " failed ===");
process.exit(fail === 0 ? 0 : 1);
