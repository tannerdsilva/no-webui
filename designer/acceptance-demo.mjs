#!/usr/bin/env node
// designer/acceptance-demo.mjs — the wave-3 acceptance gate (W3.7).
//
// Builds and starts the WebUIExample server on :38000 (a fresh port band),
// drives it with real headless Chromium, and asserts the four acceptance
// routes end to end:
//   /        the dashboard renders (the page a reviewer reads first)
//   a CLICK  round-trips the counter over the websocket and repaints #dash-count
//   /login   a native urlencoded form POST -> 303; the dashboard proves the
//            parsed FormValues
//   /upload  a real file upload (multipart) -> 303; the server persists the
//            file to a temp dir and the dashboard reports the exact byte count
//            + sha-256, cross-checked against the uploaded bytes
//   /events  three SSE events received by the browser's own EventSource
// Tear-down is unconditional (never leaves an orphaned server or listener).
//
// Usage: node designer/acceptance-demo.mjs

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 38000;
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

async function waitForServer(base, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(base + "/");
      const body = await r.text();
      // prove this is our own freshly spawned demo, not a stale process
      if (r.ok && body.includes("acceptance demo") && body.includes("dash-count")) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

console.log("=== wave-3 acceptance demo gate ===");

// Build first so the binary is current.
const built = await run("swift", ["build"]);
if (built.code !== 0) {
  console.log(built.out.slice(-400));
  bad("swift build");
  process.exit(1);
}
const shown = await run("swift", ["build", "--show-bin-path"]);
const binPath = join(shown.out.trim(), "WebUIExample");

let server = null;
// hard teardown on every exit path: the gate's own spawned server must never
// outlive the gate or poison :38000 for the next run.
process.on("exit", () => { if (server) { try { server.kill("SIGKILL"); } catch {} } });

server = spawn(binPath, ["--port", String(PORT)], {
  cwd: ROOT,
  stdio: ["ignore", "ignore", "ignore"],
});
const up = await waitForServer(BASE);
if (!up) {
  bad("server did not become ready on the gate's own identity (kill any WebUIExample holding :38000 and re-run)");
  process.exit(1);
}
ok("server ready on :38000 (fresh port band)");

let browser = null;
try {
  browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
  const page = await context.newPage();

  // ── 1. the dashboard renders: the surface a reviewer reads first ──
  await page.goto(BASE + "/", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(400); // let the engine websocket connect
  const dashboard = await page.evaluate(() => ({
    count: document.querySelector("#dash-count")?.textContent ?? null,
    login: !!document.querySelector("#login-name"),
    upload: !!document.querySelector("#upload-file"),
    sse: document.querySelector("#sse-log")?.textContent ?? null,
    title: document.title,
  }));
  if (dashboard.title.includes("acceptance demo") && dashboard.count === "count: 0"
      && dashboard.login && dashboard.upload && dashboard.sse?.includes("waiting for /events"))
    ok("dashboard renders / with the counter, login form, upload form and the sse log");
  else bad(`dashboard render: ${JSON.stringify(dashboard)}`);

  // ── 2. a CLICK round-trips and repaints the counter ──
  await page.click("#btn-inc");
  await page.waitForFunction(() => document.querySelector("#dash-count")?.textContent.trim() === "count: 1", null, { timeout: 8000 });
  const afterClick = await page.evaluate(() => document.querySelector("#dash-count")?.textContent.trim() ?? null);
  if (afterClick === "count: 1") ok(`click round-tripped over the websocket (counter -> ${afterClick})`);
  else bad(`counter after click: ${JSON.stringify(afterClick)}`);

  // ── 3. /login: a real urlencoded form POST, answered with a typed response ──
  await page.fill("#login-name", "ada lovelace");
  const loginRespPromise = page.waitForResponse(
    (r) => r.request().method() === "POST" && r.url().endsWith("/login")
  );
  await page.click("#login-submit");
  const loginResp = await loginRespPromise;
  const loginOk = loginResp.status() === 303
    && loginResp.request().postData()?.includes("name=ada+lovelace");
  if (loginOk) ok("native form POST -> 303 with the urlencoded FormValues in the body");
  else bad(`login response: status ${loginResp.status()}, body ${JSON.stringify(loginResp.request().postData())}`);
  await page.waitForFunction(
    (n) => document.querySelector("#signin-status")?.textContent.includes(`signed in as ${n}`),
    "ada lovelace", { timeout: 8000 }
  );
  const signInText = await page.evaluate(() => document.querySelector("#signin-status")?.textContent ?? "");
  if (signInText.includes("signed in as") && signInText.includes("ada lovelace"))
    ok("dashboard proves the parsed form values after the 303 redirect");
  else bad(`sign-in proof: ${JSON.stringify(signInText)}`);

  // ── 4. /upload: a real file upload, persisted + proven by bytes/digest ──
  const uploadDir = mkdtempSync(join(tmpdir(), "w37-acceptance-"));
  const uploadPath = join(uploadDir, "acceptance-report.csv");
  const payload = Buffer.alloc(8192);
  for (let i = 0; i < payload.length; i++) payload[i] = (i * 31 + 7) & 0xff;
  const expectedDigest = createHash("sha256").update(payload).digest("hex");
  writeFileSync(uploadPath, payload);

  await page.setInputFiles("#upload-file", uploadPath);
  const uploadRespPromise = page.waitForResponse(
    (r) => r.request().method() === "POST" && r.url().endsWith("/upload")
  );
  await page.click("#upload-submit");
  const uploadResp = await uploadRespPromise;
  const uploadContentType = uploadResp.request().headers()["content-type"] ?? "";
  if (uploadResp.status() === 303 && uploadContentType.startsWith("multipart/form-data;"))
    ok("real file upload -> 303 as a multipart/form-data POST");
  else bad(`upload response: status ${uploadResp.status()}, content-type ${uploadContentType}`);
  await page.waitForFunction(
    (d) => document.querySelector("#upload-status")?.textContent.includes(d),
    expectedDigest, { timeout: 8000 }
  );
  const uploadText = await page.evaluate(() => document.querySelector("#upload-status")?.textContent ?? "");
  const uploadProven = uploadText.includes(`${payload.length} bytes`)
    && uploadText.includes(expectedDigest)
    && uploadText.includes("acceptance-report.csv");
  if (uploadProven) ok(`upload persisted + proven on the dashboard (${payload.length} bytes, sha-256 ${expectedDigest.slice(0, 12)}…)`);
  else bad(`upload proof: ${JSON.stringify(uploadText)}`);

  // ── 5. /events: the browser's EventSource receives THREE events ──
  await page.evaluate(() => {
    window.__sse = [];
    const es = new EventSource("/events");
    es.addEventListener("tick", (e) => window.__sse.push({ name: "tick", data: e.data }));
    es.addEventListener("done", (e) => window.__sse.push({ name: "done", data: e.data }));
    es.addEventListener("error", () => {});
  });
  await page.waitForFunction(() => window.__sse && window.__sse.length === 3, null, { timeout: 10000 });
  const sse = await page.evaluate(() => window.__sse);
  const sseNames = sse.map((e) => e.name).join(",");
  const sseData = sse.map((e) => e.data).join(",");
  if (sse.length === 3 && sseNames === "tick,tick,done" && sseData === "tick-1,tick-2,done-3")
    ok(`three SSE events received by the page's EventSource (${sseNames} → ${sseData})`);
  else bad(`sse events: ${JSON.stringify(sse)}`);

  // screenshot for the reviewer
  const shotDir = join(ROOT, ".smoke");
  await page.goto(BASE + "/", { waitUntil: "domcontentloaded" });
  await page.screenshot({ path: join(shotDir, "acceptance-demo.png"), fullPage: true });
  console.log(`  screenshot -> ${join(shotDir, "acceptance-demo.png")}`);

  rmSync(uploadDir, { recursive: true, force: true });
} catch (err) {
  bad(`gate threw: ${err}`);
} finally {
  if (browser) await browser.close().catch(() => {});
  if (server) { try { server.kill("SIGKILL"); } catch {} }
}

console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  console.log("ACCEPTANCE DEMO FAIL");
  process.exit(1);
}
console.log("ACCEPTANCE DEMO PASS");
process.exit(0);
