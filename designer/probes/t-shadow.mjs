#!/usr/bin/env node
// designer/probes/t-shadow.mjs  the DX-15b anti-shadow probe (lane T).
//
// proves, against the BUILT WebUIContinuumTool `shadow` verb (additive):
//   1. a planted consumer sheet shadowing the 9 DS classes is caught, with
//      each collision NAMING its owning component;
//   2. a clean namespaced sheet reports ZERO against the DS union;
//   3. the real demo tree (Sources/WebUIExample) is clean — demo target ZERO;
//   4. the verb never runs over DS sources (it refuses/skips them).
//
// requires `swift build` first (the tool binary must exist).
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const BIN = join(ROOT, ".build/out/Products/Debug/WebUIContinuumTool");
const DEMO = join(ROOT, "Sources", "WebUIExample");
const DS = join(ROOT, "Sources", "WebUIDesignSystemCore");

if (!existsSync(BIN)) {
  console.error(`t-shadow: tool binary not built at ${BIN} — run swift build first`);
  process.exit(1);
}

let failures = 0;
function check(label, cond, detail) {
  if (cond) { console.log(`  PASS  ${label}`); }
  else { failures += 1; console.error(`  FAIL  ${label}\n        ${detail}`); }
}

function run(args) {
  const r = spawnSync(BIN, args, { encoding: "utf8" });
  return { code: r.status, out: r.stdout ?? "", err: r.stderr ?? "" };
}

// the 9 shadowed DS classes, each with its expected owner.
const SHADOWED = {
  chip: "WebUIChip",
  kv: "design-system.css",
  toast: "WebUIToast",
  "modal-overlay": "WebUIModal",
  "log-line": "design-system.css",
  md: "WebUIDesignSystemCore.markdownBody",
  swatch: "design-system.css",
  "inline-edit": "WebUIInlineEdit",
  "tool-btn": "design-system.css",
};

console.log("DX-15b anti-shadow probe (selector-extraction leg)");

// 1. planted fixture: every shadowed class expressed through all three legs
//    (string-literal CSS, CSSRule args, class= literals).
const planted = mkdtempSync(join(tmpdir(), "t-shadow-planted-"));
try {
  writeFileSync(join(planted, "PlantedChrome.swift"), `import WebUIDesignSystem
enum PlantedChrome {
  static let sheet = """
.chip {
  background: #111;
}
"""
  static let kvSheet = ".kv { color: red; }"
  static let rules: [CSSRule] = [
    CSSRule(".toast", [CSSDeclaration("background", "black")]),
    CSSRule(".modal-overlay", [CSSDeclaration("position", "fixed")]),
  ]
  static let more = "a .log-line { } and .md"
  static let attr = "<span class=\\"swatch tool-btn\\"></span>"
  static let inline = CSSRule(".inline-edit", [CSSDeclaration("border", "1px solid red")])
}
`);
  const p = run(["shadow", "--sources", planted, "--demo"]);
  check("planted fixture scanned", p.code === 0, `exit=${p.code}, err=${p.err}`);
  for (const [cls, owner] of Object.entries(SHADOWED)) {
    const want = `class '${cls}' shadows design-system class '${cls}' (owned by ${owner})`;
    check(`planted '${cls}' named with owner '${owner}'`, p.out.includes(want), `missing: ${want}\n---out---\n${p.out}`);
  }
} finally {
  rmSync(planted, { recursive: true, force: true });
}

// 2. clean namespaced sheet -> zero.
const clean = mkdtempSync(join(tmpdir(), "t-shadow-clean-"));
try {
  writeFileSync(join(clean, "CleanChrome.swift"), `import WebUIDesignSystem
enum CleanChrome {
  static let sheet = """
.app-chrome-toolbar {
  display: flex;
}
"""
  static let rules: [CSSRule] = [
    CSSRule(".app-status-pill", [CSSDeclaration("color", "var(--color-success)")]),
  ]
}
`);
  const c = run(["shadow", "--sources", clean, "--demo"]);
  check("clean namespaced sheet -> 0 collisions", c.code === 0 && /shadow: 0 collision/.test(c.out), `out=${c.out}`);
} finally {
  rmSync(clean, { recursive: true, force: true });
}

// 3. the demo tree -> zero (demo target).
if (existsSync(DEMO)) {
  const d = run(["shadow", "--sources", DEMO, "--demo"]);
  check("demo tree (WebUIExample) -> 0 collisions", d.code === 0 && /shadow: 0 collision/.test(d.out), `out=${d.out}`);
} else {
  console.log("  SKIP  demo tree (WebUIExample not present)");
}

// 4. never runs over DS sources: pointing at the DS core is refused.
if (existsSync(DS)) {
  const s = run(["shadow", "--sources", DS, "--demo"]);
  check("DS sources are skipped, not scanned", s.code === 0 && s.out.includes("never runs over design-system sources"), `out=${s.out.slice(0, 200)}`);
} else {
  console.log("  SKIP  DS-source refusal (tree not present)");
}

// 5. --fail flips to a non-zero exit on a collision.
const p2 = mkdtempSync(join(tmpdir(), "t-shadow-fail-"));
try {
  writeFileSync(join(p2, "Bad.swift"), `import WebUIDesignSystem
let bad = CSSRule(".chip", [CSSDeclaration("background", "red")])
`);
  const f = run(["shadow", "--sources", p2, "--fail"]);
  check("--fail exits non-zero on a collision", f.code === 1, `exit=${f.code}`);
  check("--fail names the collision on stderr", f.err.includes("class(es) shadowing the design system"), f.err);
} finally {
  rmSync(p2, { recursive: true, force: true });
}

if (failures > 0) { console.error(`t-shadow: ${failures} failure(s)`); process.exit(1); }
console.log("t-shadow: all checks passed");
