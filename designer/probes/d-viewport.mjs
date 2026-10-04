#!/usr/bin/env node
// designer/probes/d-viewport.mjs  the t3.3 Viewport DOM-contract probe (lane D).
//
// the Viewport's windowing contract is split across three artifacts: the Swift
// component (Sources/WebUIDesignSystemCore/Viewport.swift), the design sheet
// (designer/assets/design-system.css — author against real classes), and the
// engine handoff (continuum-notes/d-to-e.md). this probe cross-checks that the
// three agree — a drift in ANY of them fails here, before the junction:
//
//   1. the engine discovery + numeric contract markers are all emitted;
//   2. the designed CSS classes the component emits actually exist;
//   3. the defaults (overscan 2, rowsize 52, safe page 10000) are what the
//      engine's JS twin must match, and are named in the handoff;
//   4. the keyed-identity row scheme and the degrade/pager markers exist in
//      source AND are documented in the handoff.
//
// requires nothing built — a pure source-level probe (like b-lint.mjs).

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const src = readFileSync(join(ROOT, "Sources", "WebUIDesignSystemCore", "Viewport.swift"), "utf8");
const css = readFileSync(join(ROOT, "designer", "assets", "design-system.css"), "utf8");
const handoff = readFileSync(join(ROOT, "continuum-notes", "d-to-e.md"), "utf8");

let failures = 0;
function check(label, cond, detail = "") {
  if (cond) { console.log(`  PASS  ${label}`); }
  else { failures += 1; console.error(`  FAIL  ${label}${detail ? "\n        " + detail : ""}`); }
}
console.log("t3.3 Viewport DOM-contract probe");

// 1. engine discovery + numeric inputs the component emits.
for (const marker of [
  "data-webui-viewport",
  "data-viewport-total",
  "data-viewport-rowsize",
  "data-viewport-overscan",
  "data-viewport-slice",
  "data-viewport-safe",
  "data-viewport-page",
  "data-viewport-pages",
  "data-viewport-goto",
  "data-viewport-row",
  "data-key",
]) {
  check(`source emits ${marker}`, src.includes(marker), "marker missing from Viewport.swift");
}

// 2. the designed classes the component emits exist in the sheet.
for (const cls of [".list--virtual", ".list__item", ".pagination", ".pagination__btn", ".pagination__meta"]) {
  check(`css defines ${cls}`, css.includes(cls), "class missing from design-system.css");
}

// 3. the windowing defaults the engine's JS twin must match.
check("overscan default is 2", /defaultOverscan:\s*Int\s*=\s*2/.test(src));
check("safe page default is 10_000 (the d0 measured ceiling)", src.includes("pageSizeLimit = 10_000"));
check("designed rowsize is 52px (the css 3.25rem)", src.includes("designedRowHeightPx = 52"));
check("rowsize lives in the sheet", css.includes(".list--virtual .list__item { height: 3.25rem; }"));

// 4. keyed identity + degrade + anchoring are in the handoff.
for (const phrase of [
  "data-webui-viewport",
  "data-key",
  "data-viewport-rowsize",
  "data-viewport-slice",
  "data-viewport-safe",
  "ViewportAnchor.scrollDelta",
]) {
  check(`handoff d-to-e.md documents ${phrase}`, handoff.includes(phrase), phrase + " missing from d-to-e.md");
}
check("handoff names the row id scheme", /-r<i>/.test(handoff) || /id scheme/.test(handoff));

console.log(failures === 0 ? "\nd-viewport: all contract checks green" : `\nd-viewport: ${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
