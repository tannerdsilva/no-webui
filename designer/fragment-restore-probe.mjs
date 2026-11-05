#!/usr/bin/env node
// designer/fragment-restore-probe.mjs — fragment patch input-state contract.
//
// The engine is loaded into a blank page (no server): `patch(fragments, seq,
// optimistic)` applies synchronously in optimistic mode, so the exact
// saveInputState -> replace -> restoreInputState path a websocket patch takes
// runs in a real browser.
//
// Cases:
//   1. cross-form swap — an empty add form is replaced by an edit form that
//      reuses its field ids; the server-rendered value must survive. (Before the
//      fix, the outgoing form's empty value was keyed by id only and blanked the
//      incoming form. Measured live in arc's model-configuration editor.)
//   2. same-form patch — a value the user typed survives the server re-render
//      (the documented "value/checked/caret survive a patch" behaviour).
//   3. data-no-restore — the server's value wins over a transient user value,
//      which is what the attribute arc already emits asks for.
//
// Usage: node designer/fragment-restore-probe.mjs   (exit 1 on failure)

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const engine = readFileSync(join(ROOT, "designer", "assets", "webui-engine.js"), "utf8");

let pass = 0;
let fail = 0;
const check = (name, ok, detail) => {
  if (ok) {
    pass++;
    console.log(`  PASS ${name}`);
  } else {
    fail++;
    console.log(`  FAIL ${name}${detail ? " — " + detail : ""}`);
  }
};

const browser = await chromium.launch();
const page = await browser.newPage();
const pageErrors = [];
page.on("pageerror", (e) => pageErrors.push(e.message));

await page.setContent(`<!doctype html><html><head>
<meta name="webui-config" content='{"wsUrl":"ws://127.0.0.1:9/ws","logLevel":"critical"}'>
</head><body>
<div id="region"><form id="add-form"><input id="title" name="title" value=""></form></div>
</body></html>`);
await page.addScriptTag({ content: engine });
await page.waitForFunction(
  "!!(window.WebUIEngine && window.WebUIEngine._getInstance && window.WebUIEngine._getInstance())",
  null,
  { timeout: 10000 }
);

const patch = (html) =>
  page.evaluate(
    (fragment) => {
      window.WebUIEngine._getInstance().patch([{ id: "region", html: fragment }], null, true);
    },
    html
  );

// 1. a different form with the same field ids must not inherit the old values.
await patch('<div id="region"><form id="edit-form"><input id="title" name="title" value="prefilled"></form></div>');
let value = await page.inputValue("#edit-form input");
check(
  "cross-form swap keeps the incoming form's server value",
  value === "prefilled",
  `got ${JSON.stringify(value)}`
);

// 2. the same form keeps what the user typed across a patch.
await page.evaluate(() => {
  document.getElementById("region").innerHTML =
    '<form id="edit-form"><input id="title" name="title" value="server"></form>';
  document.getElementById("title").value = "typed";
});
await patch('<div id="region"><form id="edit-form"><input id="title" name="title" value="server-2"></form></div>');
value = await page.inputValue("#title");
check("same-form patch keeps the user's value", value === "typed", `got ${JSON.stringify(value)}`);

// 3. data-no-restore hands the control back to the server.
await page.evaluate(() => {
  document.getElementById("region").innerHTML =
    '<form id="edit-form"><input id="toggle" name="toggle" value="server" data-no-restore></form>';
  document.getElementById("toggle").value = "typed";
});
await patch(
  '<div id="region"><form id="edit-form"><input id="toggle" name="toggle" value="server-2" data-no-restore></form></div>'
);
value = await page.inputValue("#toggle");
check("data-no-restore lets the server value win", value === "server-2", `got ${JSON.stringify(value)}`);

check("no page errors", pageErrors.length === 0, pageErrors.join("; "));

await browser.close();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
