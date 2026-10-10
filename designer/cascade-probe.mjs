#!/usr/bin/env node
// designer/cascade-probe.mjs — browser proof that a host StyleSheet wins the
// cascade by origin, with zero `!important`.
//
// the page bytes come from the REAL emission path: WebUICascadeProbe renders
// a host page (framework sheet + a host StyleSheet) and a control page (the
// same markup, no host sheet) through WebUIDocument, and this gate drives both
// in headless chromium. each probe pair faces a real shipped framework rule,
// and the host rule is EQUAL or LOWER specificity than the framework rule it
// overrides — so the only way the host value can win is the later `host`
// layer. the control page proves the framework rule was genuinely in force
// (removing the host layer reverts to the framework value).
//
//   node designer/cascade-probe.mjs
//
// exits non-zero on any failure. self-contained: builds, renders, serves,
// drives, tears down. not a plugin verb (headless Chromium cannot run inside
// the plugin sandbox).

import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "node:http";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

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

console.log("=== host cascade probe ===");

// 1. build and render the two pages through the real emission path.
const built = await run("swift", ["build"]);
if (built.code !== 0) { console.log(built.out.slice(-400)); bad("swift build"); process.exit(1); }
const shown = await run("swift", ["build", "--show-bin-path"]);
const probeBin = join(shown.out.trim(), "WebUICascadeProbe");

const tmp = mkdtempSync(join(tmpdir(), "w53-cascade-"));
const hostPath = join(tmp, "host.html");
const controlPath = join(tmp, "control.html");
const g = await run(probeBin, ["--generate", hostPath]);
const c = await run(probeBin, ["--control", controlPath]);
if (g.code !== 0 || c.code !== 0) {
	bad(`WebUICascadeProbe failed (${g.code}/${c.code}): ${(g.out + c.out).slice(-400)}`);
	process.exit(1);
}
const hostPage = readFileSync(hostPath, "utf8");
const controlPage = readFileSync(controlPath, "utf8");
ok("host and control pages rendered through the real emission path");

// 2. byte-level structure: the host layer is declared after the framework's
//    statement, and the control page never names it.
const frameworkStmt = "@layer webui, webui.utilities;";
const hostStmt = "@layer webui, webui.utilities, host;";
const fwIdx = hostPage.indexOf(frameworkStmt);
const hsIdx = hostPage.indexOf(hostStmt);
const hbIdx = hostPage.indexOf("@layer host {");
if (fwIdx >= 0 && hsIdx > fwIdx && hbIdx > hsIdx) ok("host page: order statement + @layer host block land after the framework statement");
else bad(`host order wrong: framework=${fwIdx} hostStatement=${hsIdx} hostBlock=${hbIdx}`);
if (!hostPage.includes(".button--icon.button--sm")) bad("host page must still ship the framework's 2-class rule the probe overrides");
else ok("host page ships the framework's higher-specificity rule (.button--icon.button--sm)");
if (controlPage.includes(hostStmt) || controlPage.includes("@layer host")) bad("control page must not declare any host layer");
else ok("control page: no host layer anywhere (a no-host document is untouched)");

// 3. the host sheet's own bytes carry no `!important`. (the framework sheet
//    legitimately ships a few, for reduced-motion + screen-reader text; the
//    promise being proven is that the HOST wins without them.)
const hostTail = hostPage.slice(hsIdx);
if (hostTail.includes("!important")) bad("host-emitted bytes contain !important");
else ok("host-emitted bytes contain zero !important (host wins without it)");

// 4. serve and drive in headless chromium.
let server;
process.on("exit", () => { if (server) server.close(); });
await new Promise((resolve) => {
	server = createServer((req, res) => {
		const body = req.url === "/host" ? hostPage : req.url === "/control" ? controlPage : null;
		if (body === null) { res.writeHead(404); res.end(); return; }
		res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
		res.end(body);
	});
	server.listen(0, "127.0.0.1", resolve);
});
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
try {
	const page = await browser.newPage();

	// read one page's computed styles for the three probe ids.
	const measure = (url) => page.goto(base + url, { waitUntil: "domcontentloaded" }).then(async () => {
		await page.waitForTimeout(120);
		return page.evaluate(() => {
			const rootFs = parseFloat(getComputedStyle(document.documentElement).fontSize);
			const styles = {};
			for (const id of ["p-base", "p-primary", "p-size"]) {
				const el = document.getElementById(id);
				styles[id] = el
					? {
						padding: getComputedStyle(el).padding,
						background: getComputedStyle(el).backgroundColor,
						width: getComputedStyle(el).width,
					}
					: null;
			}
			return { rootFs, styles };
		});
	});

	const host = await measure("/host");
	const control = await measure("/control");

	if (host.rootFs > 0) ok(`root font-size ${host.rootFs}px (rem expectations computed live)`);
	else bad(`unreadable root font-size: ${host.rootFs}`);

	// pair A — equal specificity: framework `.button { padding: 0.5rem 1rem }`
	// vs host `.button { padding: 43px 7px }`.
	const padExp = `${host.rootFs * 0.5}px ${host.rootFs}px`;
	if (host.styles["p-base"]?.padding === "43px 7px") ok("host wins over framework at EQUAL specificity (.button padding → 43px 7px)");
	else bad(`host .button padding: ${JSON.stringify(host.styles["p-base"]?.padding)}`);
	if (control.styles["p-base"]?.padding === padExp) ok(`control reverts to the framework padding (${padExp}) with no host layer`);
	else bad(`control .button padding: ${JSON.stringify(control.styles["p-base"]?.padding)} (expected ${padExp})`);

	// pair B — equal specificity, token-backed: framework
	// `.button--primary { background: var(--color-primary-solid) }` vs host
	// `.button--primary { background: rgb(240, 20, 20) }`.
	if (host.styles["p-primary"]?.background === "rgb(240, 20, 20)") ok("host wins over the framework's token background at EQUAL specificity (→ rgb(240, 20, 20))");
	else bad(`host .button--primary background: ${JSON.stringify(host.styles["p-primary"]?.background)}`);
	if (control.styles["p-primary"]?.background === "rgb(79, 70, 229)") ok("control reverts to the framework's primary solid (rgb(79, 70, 229)) with no host layer");
	else bad(`control .button--primary background: ${JSON.stringify(control.styles["p-primary"]?.background)} (expected rgb(79, 70, 229))`);

	// pair C — host at LOWER specificity: framework
	// `.button--icon.button--sm { width: 2rem }` (two classes) vs host
	// `.button--sm { width: 9rem }` (one class). without layers the 2-class
	// rule wins; the control equal-lock proves it.
	const wExp = `${host.rootFs * 2}px`;
	if (host.styles["p-size"]?.width === `${host.rootFs * 9}px`) ok(`host wins over a HIGHER-specificity framework rule (2 classes) by layer alone (.button--sm width → ${host.rootFs * 9}px)`);
	else bad(`host .button--sm width: ${JSON.stringify(host.styles["p-size"]?.width)}`);
	if (control.styles["p-size"]?.width === wExp) ok(`control reverts to the 2-class framework width (${wExp}) with no host layer`);
	else bad(`control .button--sm width: ${JSON.stringify(control.styles["p-size"]?.width)} (expected ${wExp})`);
} finally {
	await browser.close();
}
server.close();

console.log(`\n=== summary: ${pass} passed, ${fail} failed ===`);
if (fail > 0) {
	console.log("CASCADE PROBE FAIL");
	process.exit(1);
}
console.log("CASCADE PROBE PASS");
process.exit(0);
