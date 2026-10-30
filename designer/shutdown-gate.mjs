#!/usr/bin/env node
// designer/shutdown-gate.mjs — a server must exit on SIGTERM even while a page
// is connected.
//
// the regression this pins: `WebUIServer.stop()` closed the listener, but the
// accept loop's task group still awaited its connection handlers, and a handler
// parked on an idle websocket has no reason to leave. the listener went down,
// `stop()` returned, and the process lived on until the browser disconnected.
// that leaked orphan servers (a `serve` invocation that will not die, a gate
// whose next run binds the port the previous one never released) and it is what
// made rtl-audit blame a direction on a different block each run.
//
// usage: node designer/shutdown-gate.mjs

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 9094;
const BIN = join(ROOT, ".build/debug/WebUIBlocksServer");
const EXIT_BUDGET_MS = 5000;

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log("  PASS " + m); };
const bad = (m) => { fail++; console.log("  FAIL " + m); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitReady(child) {
  for (let i = 0; i < 40; i++) {
    if (child.exitCode !== null) return false;
    try { const r = await fetch(`http://127.0.0.1:${PORT}/`); if (r.ok) return true; } catch {}
    await sleep(250);
  }
  return false;
}

// 1. the regression case: SIGTERM with a connected page must still exit.
{
  const server = spawn(BIN, ["--port", String(PORT), "--block", "dashboard", "--dir", "ltr"], { cwd: ROOT });
  let log = "";
  server.stdout.on("data", (d) => (log += d));
  server.stderr.on("data", (d) => (log += d));

  if (!(await waitReady(server))) {
    bad("server did not come up (" + log.slice(-160) + ")");
  } else {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws`);
    const opened = await new Promise((resolve) => {
      ws.onopen = () => resolve(true);
      ws.onerror = () => resolve(false);
      setTimeout(() => resolve(false), 5000);
    });
    if (!opened) bad("websocket did not open; the connected-page case was not exercised");
    else {
      ok("a page is connected (websocket open)");
      const exited = new Promise((resolve) => server.once("exit", (code, signal) => resolve({ code, signal })));
      const t0 = Date.now();
      server.kill("SIGTERM");
      const outcome = await Promise.race([exited, sleep(EXIT_BUDGET_MS).then(() => "timeout")]);
      if (outcome === "timeout") {
        bad(`server still running ${EXIT_BUDGET_MS}ms after SIGTERM with a page connected — an orphan`);
      } else {
        ok(`server exited on SIGTERM with a page connected (${Date.now() - t0}ms)`);
        if (outcome.code === 0 || outcome.signal === "SIGTERM") ok("shutdown was clean, not a crash");
        else bad("unexpected exit: " + JSON.stringify(outcome));
      }
      try { ws.close(); } catch {}
    }
  }
  if (server.exitCode === null) server.kill("SIGKILL");
}

// 2. the control: no connection, SIGTERM still exits (this one never regressed).
{
  const server = spawn(BIN, ["--port", String(PORT), "--block", "login", "--dir", "ltr"], { cwd: ROOT });
  let log = "";
  server.stdout.on("data", (d) => (log += d));
  server.stderr.on("data", (d) => (log += d));
  if (!(await waitReady(server))) {
    bad("control server did not come up (" + log.slice(-160) + ")");
  } else {
    const exited = new Promise((resolve) => server.once("exit", (code, signal) => resolve({ code, signal })));
    server.kill("SIGTERM");
    const outcome = await Promise.race([exited, sleep(EXIT_BUDGET_MS).then(() => "timeout")]);
    if (outcome === "timeout") bad(`idle server still running ${EXIT_BUDGET_MS}ms after SIGTERM`);
    else ok("idle server exited on SIGTERM");
  }
  if (server.exitCode === null) server.kill("SIGKILL");
}

console.log("");
console.log(`=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "SHUTDOWN GATE PASS" : "SHUTDOWN GATE FAIL");
process.exit(fail === 0 ? 0 : 1);
