#!/usr/bin/env node
// url-smoke.mjs — drives the SHARED url-payloads.json fixture against the js
// side of the url policy. the three definitions below mirror
// designer/assets/webui-runtime.js (lines ~702-710) VERBATIM; a swift-side pin
// (URLPolicyFixtureTests.probeMirrorsRuntime) asserts these exact spans exist
// in the runtime, so any drift on either side fails CI.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

var UNSAFE_PROTOCOLS = /^(javascript|data|vbscript):/i;

function stripUrlControlChars(url) {
  return String(url).replace(/[\u0000-\u0020\u007F]/g, '');
}

function isSafeUrl(url) {
  return !UNSAFE_PROTOCOLS.test(stripUrlControlChars(url));
}

const fixture = JSON.parse(readFileSync(join(root, 'designer/url-payloads.json'), 'utf8'));
let failures = 0;
for (const entry of fixture) {
  const actual = isSafeUrl(entry.payload);
  if (actual !== entry.safe) {
    failures += 1;
    console.log(`FAIL ${JSON.stringify(entry.payload)}: expected safe=${entry.safe}, got ${actual}`);
  }
}
if (failures > 0) {
  console.error(`url-smoke: ${failures}/${fixture.length} mismatches`);
  process.exit(1);
}
console.log(`url-smoke: ${fixture.length}/${fixture.length} payloads match the shared fixture`);
