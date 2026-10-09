#!/usr/bin/env node
// designer/a11y-audit.mjs  w4.4's browser gate.
//
// honest-observer discipline, layer 1: this gate fetches each framework page
// over a RAW http fetch and re-implements the six a11y rules (the same six
// `A11yAudit` applies in Swift) over the served bytes. it never launches a
// browser, never patches the page's runtime, never takes a screenshot. if a
// framework page ships markup that violates one of the six rules, this gate
// fails naming the rule and the element.
//
// a self-test runs first: the six rules must fire on a fixture that breaks
// each of them, so a rule that silently stopped matching is a gate failure,
// not merely an unexercised code path.
//
// usage: node designer/a11y-audit.mjs
//   spawns WebUIShowcaseServer on :43000, then WebUIBlocksServer per block on
//   the same port, probes, tears down each. exits non-zero on any failure.

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 43000;
const BASE = `http://127.0.0.1:${PORT}`;

const RULES = {
  buttonNoName: "button-no-name",
  imageNoAlt: "image-no-alt",
  controlNoLabel: "control-no-label",
  interactiveNoName: "interactive-no-name",
  headingSkip: "heading-skip",
  roleMissingAria: "role-missing-aria",
};

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL ${m}`); };

// --- tokenizer: a tiny html tree over the raw string (no dependencies) ---

const VOID_TAGS = new Set([
  "area", "base", "br", "col", "embed", "hr", "img", "input",
  "link", "meta", "param", "source", "track", "wbr",
]);

function parseHTML(html) {
  const roots = [];
  const stack = [];
  let pending = "";
  let i = 0;
  const n = html.length;

  const flushText = () => {
    if (!pending) return;
    const node = { tag: "", text: pending, attrs: {}, children: [] };
    (stack.length ? stack[stack.length - 1].children : roots).push(node);
    pending = "";
  };
  const append = (node) => {
    (stack.length ? stack[stack.length - 1].children : roots).push(node);
  };
  const isNameChar = (c) => /[A-Za-z0-9\-:._]/.test(c);
  const isAttrEnd = (c) => c === undefined || /\s/.test(c) || c === "=" || c === ">" || c === "/";

  while (i < n) {
    const c = html[i];
    if (c !== "<") { pending += c; i += 1; continue; }
    const next = html[i + 1];

    if (next === "!") {
      if (html[i + 2] === "-" && html[i + 3] === "-") {
        let j = i + 4;
        while (j + 2 < n && !(html[j] === "-" && html[j + 1] === "-" && html[j + 2] === ">")) j += 1;
        i = Math.min(j + 3, n);
      } else {
        let j = i + 2;
        while (j < n && html[j] !== ">") j += 1;
        i = Math.min(j + 1, n);
      }
      continue;
    }

    if (next === "/") {
      flushText();
      let j = i + 2;
      while (j < n && html[j] !== ">") j += 1;
      if (stack.length) stack.pop();
      i = Math.min(j + 1, n);
      continue;
    }

    flushText();
    let j = i + 1;
    while (j < n && isNameChar(html[j])) j += 1;
    const node = { tag: html.slice(i + 1, j).toLowerCase(), attrs: {}, children: [] };

    let selfClosing = false;
    while (j < n) {
      while (j < n && /\s/.test(html[j])) j += 1;
      if (j >= n) break;
      if (html[j] === ">") { j += 1; break; }
      if (html[j] === "/") {
        if (html[j + 1] === ">") { selfClosing = true; j += 2; break; }
        j += 1;
        continue;
      }
      const attrStart = j;
      while (j < n && !isAttrEnd(html[j])) j += 1;
      const attrName = html.slice(attrStart, j).toLowerCase();
      while (j < n && /\s/.test(html[j])) j += 1;
      let value = "";
      if (html[j] === "=") {
        j += 1;
        while (j < n && /\s/.test(html[j])) j += 1;
        const q = html[j];
        if (q === '"' || q === "'") {
          j += 1;
          const vStart = j;
          while (j < n && html[j] !== q) j += 1;
          value = html.slice(vStart, j);
          if (j < n) j += 1;
        } else {
          const vStart = j;
          while (j < n && !/\s/.test(html[j]) && html[j] !== ">") j += 1;
          value = html.slice(vStart, j);
        }
      }
      if (attrName) node.attrs[attrName] = value;
    }

    if (VOID_TAGS.has(node.tag) || selfClosing || node.tag === "script" || node.tag === "style") {
      append(node);
      if (node.tag === "script" || node.tag === "style") {
        const needle = "</" + node.tag;
        let k = j;
        while (k < n) {
          if (html[k] === "<" && html.slice(k, k + needle.length).toLowerCase() === needle) {
            let m = k + needle.length;
            while (m < n && html[m] !== ">") m += 1;
            i = Math.min(m + 1, n);
            break;
          }
          k += 1;
        }
        if (k >= n) i = n;
      } else {
        i = j;
      }
    } else {
      append(node);
      stack.push(node);
      i = j;
    }
  }
  flushText();
  return roots;
}

// --- entity decoding (the subset the pages actually use) ---

const NAMED = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: "\u00A0",
  times: "\u00D7", minus: "\u2212", copy: "\u00A9", hellip: "\u2026",
  mdash: "\u2014", ndash: "\u2013", laquo: "\u00AB", raquo: "\u00BB",
  lsaquo: "\u2039", rsaquo: "\u203A",
};

function decodeEntities(s) {
  if (!s.includes("&")) return s;
  return s.replace(/&(#x?[0-9A-Fa-f]+|[a-zA-Z][a-zA-Z0-9]*);/g, (whole, body) => {
    if (body[0] === "#") {
      const hex = body[1] === "x" || body[1] === "X";
      const code = parseInt(body.slice(hex ? 2 : 1), hex ? 16 : 10);
      return Number.isFinite(code) && code >= 0 ? String.fromCodePoint(code) : whole;
    }
    return NAMED[body] !== undefined ? NAMED[body] : whole;
  });
}

const trimWS = (s) => s.replace(/^\s+|\s+$/g, "");

// --- the six rules (mirrors of Sources/WebUICore/A11y.swift) ---

function indexByID(roots) {
  const map = new Map();
  const visit = (n) => {
    if (n.attrs.id) map.set(n.attrs.id, n);
    n.children.forEach(visit);
  };
  roots.forEach(visit);
  return map;
}

function labelForIDs(roots) {
  const set = new Set();
  const visit = (n) => {
    if (n.tag === "label" && n.attrs["for"]) set.add(n.attrs["for"]);
    n.children.forEach(visit);
  };
  roots.forEach(visit);
  return set;
}

const isHidden = (n) => n.attrs["aria-hidden"] === "true" || n.attrs["hidden"] !== undefined;
const isPresentation = (n) => n.attrs.role === "presentation" || n.attrs.role === "none";

function subtreeText(node) {
  let out = "";
  const visit = (n) => {
    if (n.tag === "") { out += decodeEntities(n.text); return; }
    if (n.tag === "script" || n.tag === "style") return;
    if (isHidden(n)) return;
    n.children.forEach(visit);
  };
  visit(node);
  return out;
}

function explicitName(node, ids) {
  const label = node.attrs["aria-label"];
  if (label && trimWS(decodeEntities(label))) return trimWS(decodeEntities(label));
  const refs = node.attrs["aria-labelledby"];
  if (refs) {
    let collected = "";
    for (const part of refs.split(/\s+/)) {
      const target = ids.get(part);
      if (target) collected += subtreeText(target) + " ";
    }
    if (trimWS(collected)) return trimWS(collected);
  }
  if (node.attrs.title) return trimWS(node.attrs.title);
  return "";
}

function accessibleName(node, ids) {
  const explicit = explicitName(node, ids);
  if (explicit) return explicit;
  if (node.tag === "img" && node.attrs.alt !== undefined) return trimWS(decodeEntities(node.attrs.alt));
  if (node.tag === "input" && node.attrs.type === "image" && node.attrs.alt) return trimWS(node.attrs.alt);
  if (node.attrs.placeholder) return trimWS(decodeEntities(node.attrs.placeholder));
  return trimWS(subtreeText(node));
}

const isButton = (n) => n.tag === "button" || n.attrs.role === "button";

function isFormControl(n) {
  if (n.tag === "select" || n.tag === "textarea") return true;
  if (n.tag === "input") {
    const t = n.attrs.type || "text";
    return !["hidden", "submit", "button", "reset", "image"].includes(t);
  }
  return false;
}

function isOtherInteractive(n) {
  if (n.tag === "a" && n.attrs.href !== undefined) return true;
  if (n.tag === "summary") return true;
  if (isButton(n)) return false;
  if (isFormControl(n)) return false;
  if (n.attrs.tabindex !== undefined && n.attrs.tabindex !== "-1") return true;
  switch (n.attrs.role) {
    case "link": case "checkbox": case "radio": case "switch":
    case "menuitem": case "menuitemcheckbox": case "menuitemradio":
    case "tab": case "option": case "treeitem":
      return true;
    default:
      return false;
  }
}

const requiredAria = (role) => {
  switch (role) {
    case "checkbox": case "radio": case "switch":
    case "menuitemcheckbox": case "menuitemradio":
      return [{ attr: "aria-checked" }];
    case "tab": case "option":
      return [{ attr: "aria-selected" }];
    case "slider": case "scrollbar":
      return [{ attr: "aria-valuenow" }];
    case "dialog": case "img":
      return [{ name: true }];
    default:
      return [];
  }
};

const headingLevel = (tag) => (/^h([1-6])$/.test(tag) ? Number(tag[1]) : 0);

function describe(node) {
  let out = `<${node.tag}`;
  let shown = 0;
  for (const key of Object.keys(node.attrs).sort()) {
    if (shown >= 3) break;
    out += ` ${key}="${node.attrs[key]}"`;
    shown += 1;
  }
  out += ">";
  return out.length > 90 ? out.slice(0, 87) + "..." : out;
}

function audit(html) {
  const roots = parseHTML(html);
  const ids = indexByID(roots);
  const labelled = labelForIDs(roots);
  const findings = [];
  let lastHeading = 0;

  const visit = (node, hidden, inLabel) => {
    if (node.tag === "") return;
    const nodeHidden = hidden || isHidden(node);
    const presentation = isPresentation(node);

    if (!nodeHidden && !presentation) {
      const level = headingLevel(node.tag);
      if (level) {
        if (lastHeading !== 0 && level > lastHeading + 1) {
          findings.push({
            rule: RULES.headingSkip,
            element: describe(node),
            message: `heading level ${level} follows level ${lastHeading}, skipping a level in the outline`,
          });
        }
        lastHeading = level;
      }

      const name = accessibleName(node, ids);
      if (isButton(node)) {
        if (!name) {
          findings.push({ rule: RULES.buttonNoName, element: describe(node),
            message: `a <${node.tag}> renders no accessible name (no text, aria-label, or aria-labelledby)` });
        }
      } else if (node.tag === "img") {
        if (node.attrs.alt === undefined) {
          findings.push({ rule: RULES.imageNoAlt, element: describe(node),
            message: 'an <img> without an alt attribute is unlabeled — use alt="" for a decorative image' });
        }
      } else if (isFormControl(node)) {
        const id = node.attrs.id || "";
        const hasLabel = explicitName(node, ids) !== ""
          || (id !== "" && labelled.has(id))
          || inLabel;
        if (!hasLabel) {
          findings.push({ rule: RULES.controlNoLabel, element: describe(node),
            message: "a form control renders without a label (no <label>, aria-label, or aria-labelledby)" });
        }
      } else if (isOtherInteractive(node) && !name) {
        findings.push({ rule: RULES.interactiveNoName, element: describe(node),
          message: "an interactive element renders without an accessible name (no text, aria-label, or aria-labelledby)" });
      }

      if (node.attrs.role) {
        for (const req of requiredAria(node.attrs.role)) {
          if (req.attr) {
            if (node.attrs[req.attr] === undefined) {
              findings.push({ rule: RULES.roleMissingAria, element: describe(node),
                message: `role="${node.attrs.role}" requires ${req.attr}, which is missing` });
            }
          } else if (explicitName(node, ids) === "") {
            findings.push({ rule: RULES.roleMissingAria, element: describe(node),
              message: `role="${node.attrs.role}" requires an accessible name (aria-label or aria-labelledby)` });
          }
        }
      }
    }

    const childInLabel = inLabel || node.tag === "label";
    if (node.tag === "script" || node.tag === "style") return;
    for (const child of node.children) visit(child, nodeHidden, childInLabel);
  };

  for (const root of roots) visit(root, false, false);
  return findings;
}

// --- self-test: every rule must fire on a fixture that breaks it ---

function selfTest() {
  const cases = [
    [RULES.buttonNoName, `<button><svg aria-hidden="true"></svg></button>`],
    [RULES.imageNoAlt, `<img src="x.png">`],
    [RULES.controlNoLabel, `<input type="text" placeholder="Name">`],
    [RULES.interactiveNoName, `<a href="/x"></a>`],
    [RULES.headingSkip, `<h1>A</h1><h3>C</h3>`],
    [RULES.roleMissingAria, `<div role="checkbox">accept</div>`],
  ];
  let fired = 0;
  for (const [rule, fixture] of cases) {
    const found = audit(fixture).some((f) => f.rule === rule);
    if (found) { fired += 1; ok(`self-test: ${rule} fires on its fixture`); }
    else { bad(`self-test: ${rule} did NOT fire on its fixture — the gate is blind`); }
  }
  return fired;
}

// --- server orchestration ---

async function waitFor(timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(BASE + "/", { signal: AbortSignal.timeout(2000) });
      if (res.ok) return await res.text();
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 400));
  }
  return null;
}

async function auditServed(name, args) {
  const server = spawn(join(ROOT, args[0]), args.slice(1), { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
  let serverLog = "";
  server.stdout.on("data", (d) => (serverLog += d));
  server.stderr.on("data", (d) => (serverLog += d));
  try {
    const page = await waitFor();
    if (page === null) {
      bad(`${name}: server did not become ready on :${PORT}`);
      server.kill("SIGTERM");
      return;
    }
    ok(`${name}: served page fetched (${page.length} bytes)`);
    const findings = audit(page);
    if (findings.length === 0) {
      ok(`${name}: zero a11y findings across the six rules`);
    } else {
      for (const f of findings) {
        bad(`${name}: [${f.rule}] ${f.element} — ${f.message}`);
      }
    }
  } finally {
    server.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 300));
    if (!server.killed) server.kill("SIGKILL");
  }
}

console.log("self-test: proving the six rules are not blind (fixtures)");
selfTest();
console.log("");

const BLOCKS = ["dashboard", "login", "signup", "sidebar-default", "sidebar-collapsible", "sidebar-rail", "sidebar-inset", "patterns"];

await auditServed("showcase", [".build/debug/WebUIShowcaseServer", "--port", String(PORT)]);
await auditServed("blocks index", [".build/debug/WebUIBlocksServer", "--port", String(PORT)]);
for (const block of BLOCKS) {
  await auditServed(`block ${block}`, [".build/debug/WebUIBlocksServer", "--port", String(PORT), "--block", block]);
}

console.log("");
console.log(`=== summary: ${pass} passed, ${fail} failed ===`);
console.log(fail === 0 ? "A11Y AUDIT PASS" : "A11Y AUDIT FAIL");
process.exit(fail === 0 ? 0 : 1);
