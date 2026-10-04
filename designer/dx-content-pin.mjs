#!/usr/bin/env node
// designer/dx-content-pin.mjs — served-content byte identity for the
// reference surfaces (CONTINUUM_DX §3.1, invariant I1). lane B owns.
//
// usage:
//   node designer/dx-content-pin.mjs              # hermetic: committed fixtures
//                                                 # vs the recorded hashes
//                                                 # (no servers, no build needed)
//   node designer/dx-content-pin.mjs --serve      # live: spawns the reference
//                                                 # servers on lane ports
//                                                 # (9200-9219), fetches the
//                                                 # pages + served assets,
//                                                 # canonicalizes, compares to
//                                                 # the committed fixtures. run
//                                                 # after `swift build`.
//   node designer/dx-content-pin.mjs --serve --base-url <url>  # fetch from a
//                                                 # running server (debug)
//
// canonicalization (the red-team's fold a): every document mints a random CSP
// nonce per process (`HTMLDocument` echoes it into the policy AND the inline
// prelude), so a raw hash is unique per process and cross-process diffs always
// false-fire. the harness canonicalizes `nonce="…"` and `'nonce-…'` BEFORE
// hashing; cross-process equivalence is asserted by serving the SAME page from
// TWO processes (blocks-index vs blocks-standalone at base hash identically
// canonical while their raw hashes differ — that pair is the living proof).
//
// the exemption register (the red-team's fold b), carried here:
//   register                      status            rule
//   ---------------------------   ----------------  -----------------------------
//   /ui/continuum-manifest.json   named route,      byte-identical at base; a
//                                  additive+        diff fails UNLESS it is a
//                                                    registered additive change
//                                                    (version key bumped, only
//                                                    additive keys)
//   webui-engine.js               I3-gated          NEVER a byte fail: raw + gz
//                                                    deltas vs the baseline are
//                                                    reported (the plugin budget
//                                                    gate owns the ceiling, §3.2)
//   page migrations               byte-identical    a migrated page whose live
//                                                    bytes differ from the
//                                                    captured bytes is a FAIL —
//                                                    the migration is wrong
//   everything else               byte-pinned       any diff stops the wave
//                                                    (smoke, blocks index + the
//                                                    dashboard block, showcase,
//                                                    shell, minified sheet)
//
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const BASELINE = path.join(ROOT, 'designer', 'dx-baseline');
const PAGES_DIR = path.join(BASELINE, 'pages');
const MANIFEST_FIXTURE = path.join(BASELINE, 'manifest', 'continuum-manifest.json');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

// the two nonce spellings every document carries: the CSP `'nonce-…'` source
// and the inline prelude's `nonce="…"` attribute. base64url alphabet. the
// replacement is the same fixed placeholder in both forms (so the transform is
// documented, deterministic and length-free: cross-process pages hash equal).
const NONCE_RE = /(nonce="|'nonce-)[A-Za-z0-9_\-]*(?:"|')/g;
const NONCE_SUB = (m) => (m.startsWith("'") ? "'nonce-N'" : 'nonce="N"');

const canonicalize = (bytes) => {
  const text = bytes.toString('utf8');
  return Buffer.from(text.replace(NONCE_RE, NONCE_SUB), 'utf8');
};

// canonicalized sha256 of raw bytes: the cross-process-stable hash.
const canonicalSha = (bytes) => sha256(canonicalize(bytes));
const rawSha = (bytes) => sha256(bytes);

// the reference surfaces; `bin` names the server binary + args that serve it
// live (serve mode). `fixture` is the committed golden capture.
const SURFACES = {
  smoke:            { bin: 'WebUISmokeTest',     args: [],                        fixture: 'smoke.page.html' },
  'blocks-index':   { bin: 'WebUIBlocksServer',  args: ['--block', 'index'],      fixture: 'blocks-index.page.html' },
  'block-1':        { bin: 'WebUIBlocksServer',  args: ['--block', 'dashboard'],  fixture: 'block-1.page.html' },
  'blocks-standalone': { bin: 'WebUIBlocksServer', args: ['--block', 'index'],    fixture: 'blocks-standalone.page.html' },
  showcase:         { bin: 'WebUIShowcaseServer', args: [],                       fixture: 'showcase.page.html' },
};

// a hard failure (exit 1) or a register warning (exit still 0).
let failures = [];
let warnings = [];

function check(name, ok, detail) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
  if (!ok) failures.push(name);
}
function warn(name, detail) {
  console.log(`REPORT ${name}  — ${detail}`);
  warnings.push(name);
}

// ── the committed fixture + recorded-hash ground truth ──────────────────────
function recordedHashes() {
  const out = {};
  for (const line of readFileSync(path.join(BASELINE, 'pages.txt'), 'utf8').split('\n')) {
    const m = line.match(/^(\S+) canonical: ([0-9a-f]{64})/);
    if (m) out[m[1]] = { canonical: m[2], ...(out[m[1]] || {}) };
    const r = line.match(/^(\S+) raw:\s+([0-9a-f]{64})/);
    if (r) out[r[1]] = { ...(out[r[1]] || {}), raw: r[2] };
    const b = line.match(/^(\S+) bytes:\s+(\d+)/);
    if (b) out[b[1]] = { ...(out[b[1]] || {}), bytes: Number(b[2]) };
  }
  return out;
}

function assetHashesFromBase() {
  const out = {};
  for (const line of readFileSync(path.join(BASELINE, 'base.txt'), 'utf8').split('\n')) {
    const m = line.match(/^([0-9a-f]{64})  (?:.*?)([^/\s]+)$/);
    if (m) out[m[2]] = m[1];
  }
  return out;
}

// ── hermetic fixture mode (the "passes clean at base" run) ───────────────────
function runFixtures() {
  const recorded = recordedHashes();
  const baseAssets = assetHashesFromBase();

  for (const [surface, spec] of Object.entries(SURFACES)) {
    const file = path.join(PAGES_DIR, spec.fixture);
    const bytes = readFileSync(file);
    const rec = recorded[surface];
    if (!rec) { check(`${surface}: fixture`, false, 'no recorded hashes in pages.txt'); continue; }
    check(`${surface}: byte count`, bytes.length === rec.bytes, `${bytes.length} vs recorded ${rec.bytes}`);
    check(`${surface}: canonical sha`, canonicalSha(bytes) === rec.canonical, canonicalSha(bytes).slice(0, 12));
    check(`${surface}: raw sha`, rawSha(bytes) === rec.raw, rawSha(bytes).slice(0, 12));
  }

  // the cross-process pair: blocks-index vs blocks-standalone are the SAME
  // page captured from two processes — identical canonical (nonce was the only
  // difference) but different raw. this pair is the canonicalization's own test.
  const bi = readFileSync(path.join(PAGES_DIR, 'blocks-index.page.html'));
  const bs = readFileSync(path.join(PAGES_DIR, 'blocks-standalone.page.html'));
  check('nonce model: same bytes', bi.length === bs.length, `${bi.length} vs ${bs.length}`);
  check('nonce model: raw differs per process', rawSha(bi) !== rawSha(bs), 'two independent nonces');
  check('nonce model: canonical equal', canonicalSha(bi) === canonicalSha(bs), 'nonce stripped before hashing');

  // assets. engine is ON the register (I3 owns it): report the delta account,
  // never fail. shell + sheet are byte-pinned. the manifest route is pinned
  // byte-identical at base (additive rule active beyond base).
  for (const asset of ['webui-engine.js', 'webui-shell.js', 'design-system.css']) {
    const file = path.join(ROOT, 'designer', 'assets', asset);
    if (!existsSync(file)) { check(`asset ${asset}`, false, 'missing on disk'); continue; }
    const bytes = readFileSync(file);
    const rec = baseAssets[asset];
    if (asset === 'webui-engine.js') {
      const gz = gzipSync(bytes).length;
      const rawDelta = rec ? bytes.length - 0 : null;
      // baseline engine sha is the register anchor: report the byte account.
      const account = rec
        ? `raw ${bytes.length} B (recorded ${rec.slice(0, 12)}…), gz ${gz} B — I3 governs, reported not pinned`
        : `raw ${bytes.length} B, gz ${gz} B — no baseline recorded`;
      warn('webui-engine.js (I3 register)', account);
    } else {
      check(`asset ${asset}`, rec !== undefined && sha256(bytes) === rec, sha256(bytes).slice(0, 12));
    }
  }

  // the manifest route at base must be byte-identical to its fixture.
  const manifest = readFileSync(MANIFEST_FIXTURE);
  const recManifest = baseAssets['continuum-manifest.json'];
  check('manifest route (fixture vs base.txt)', recManifest !== undefined && sha256(manifest) === recManifest,
    sha256(manifest).slice(0, 12));
  check('manifest fixture parses as the engine slice', JSON.parse(manifest.toString('utf8')).kind === 'continuum-engine-slice');

  // page migrations register: a migrated page must remain byte-identical to
  // its captured bytes. at base no migration is in flight; the mechanism is
  // the same canonical-compare the serve mode runs per surface.
}

// ── serve mode (live surfaces, canonical compare) ────────────────────────────
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchText(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return Buffer.from(await res.arrayBuffer());
}

async function waitReady(url, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try { await fetchText(url); return true; } catch { await wait(500); }
  }
  return false;
}

function findBinary(name) {
  const candidates = [
    path.join(ROOT, '.build', 'out', 'Products', 'Debug', name),
    path.join(ROOT, '.build', 'debug', name),
  ];
  return candidates.find((p) => existsSync(p));
}

async function serveOn(bin, args, port) {
  const child = spawn(bin, [...args, '--port', String(port)], {
    cwd: ROOT,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return child;
}

async function runServe({ baseUrls }) {
  const built = {};
  let neededBuild = false;
  for (const [surface, spec] of Object.entries(SURFACES)) {
    if (!baseUrls[surface]) {
      const bin = findBinary(spec.bin);
      if (!bin) { neededBuild = true; built[surface] = { bin: spec.bin, missing: true }; continue; }
      built[surface] = bin;
    }
  }
  if (neededBuild) {
    console.error(`dx-content-pin: missing build binaries — run \`swift build\` first (referenced: ${
      [...new Set(Object.values(built).filter((b) => b.missing).map((b) => b.bin))].join(', ')
    }).`);
    process.exit(2);
  }

  const children = [];
  const urlFor = {};
  let port = 9201;
  if (!baseUrls.smoke) {
    children.push(await serveOn(built.smoke, [], port));
    urlFor.smoke = `http://127.0.0.1:${port}`;
    port += 1;
    children.push(await serveOn(built['blocks-index'], ['--block', 'index'], port));
    urlFor['blocks-index'] = `http://127.0.0.1:${port}`;
    port += 1;
    children.push(await serveOn(built['block-1'], ['--block', 'dashboard'], port));
    urlFor['block-1'] = `http://127.0.0.1:${port}`;
    port += 1;
    children.push(await serveOn(built['blocks-standalone'], ['--block', 'index'], port));
    urlFor['blocks-standalone'] = `http://127.0.0.1:${port}`;
    port += 1;
    children.push(await serveOn(built.showcase, [], port));
    urlFor.showcase = `http://127.0.0.1:${port}`;
    port += 1;
  } else {
    Object.assign(urlFor, baseUrls);
  }

  console.log('dx-content-pin --serve: spawned on lane ports 9201-9205 (sandbox-inhibited servers read-only on 127.0.0.1)');
  try {
    // wait for all servers
    for (const surface of Object.keys(urlFor)) {
      const ready = await waitReady(`${urlFor[surface]}/`);
      check(`server ${surface} ready`, ready, urlFor[surface]);
      if (!ready) console.error(`  (server for ${surface} never became ready)`);
    }

    const recorded = recordedHashes();
    const live = {};
    for (const surface of Object.keys(urlFor)) {
      try {
        live[surface] = await fetchText(`${urlFor[surface]}/`);
      } catch (err) {
        check(`fetch ${surface}`, false, String(err));
      }
    }

    for (const [surface, spec] of Object.entries(SURFACES)) {
      if (!live[surface]) continue;
      const fixture = readFileSync(path.join(PAGES_DIR, spec.fixture));
      const rec = recorded[surface];
      check(`${surface}: live byte count == fixture`,
        live[surface].length === fixture.length, `${live[surface].length} vs ${fixture.length}`);
      check(`${surface}: live canonical == recorded canonical`,
        canonicalSha(live[surface]) === rec?.canonical,
        canonicalSha(live[surface]).slice(0, 12));
      check(`${surface}: live bytes == captured fixture (byte-identical)`,
        live[surface].equals(fixture), 'nonce aside, the served bytes must not move');
    }

    // cross-process nonce proof IN the live set: two independent index
    // processes must canonicalize equal and raw-differ.
    check('live nonce model: raw differs', live['blocks-index'] && live['blocks-standalone']
      && rawSha(live['blocks-index']) !== rawSha(live['blocks-standalone']), 'two processes, two nonces');
    check('live nonce model: canonical equal', live['blocks-index'] && live['blocks-standalone']
      && canonicalSha(live['blocks-index']) === canonicalSha(live['blocks-standalone']), 'nonce stripped');

    // served assets. engine ships verbatim (no minifier) and is ON the
    // register: served == on-disk == report, never fail. shell is pinned
    // verbatim. the sheet's served form is the minified working file (the
    // documented one-transform); assert served == comment-stripped working
    // file. the manifest route is byte-identical at base (additive register
    // beyond base).
    const anchor = urlFor['blocks-index'] || urlFor.showcase;
    const engineServed = await fetchText(`${anchor}/ui/webui-engine.js`);
    const engineDisk = readFileSync(path.join(ROOT, 'designer', 'assets', 'webui-engine.js'));
    check('engine: served == on-disk (verbatim)',
      engineServed.equals(engineDisk), `${engineServed.length} B`);
    const gz = gzipSync(engineServed).length;
    warn('webui-engine.js (I3 register)', `served raw ${engineServed.length} B / gz ${gz} B — I3 owns the ceiling; reported`);

    const shellServed = await fetchText(`${anchor}/ui/webui-shell.js`);
    const shellDisk = readFileSync(path.join(ROOT, 'designer', 'assets', 'webui-shell.js'));
    check('shell: served == on-disk (verbatim, pinned)', shellServed.equals(shellDisk), `${shellServed.length} B`);

    const cssServed = await fetchText(`${anchor}/__assets/css`);
    const cssWorking = readFileSync(path.join(ROOT, 'designer', 'assets', 'design-system.css'));
    const minified = Buffer.from(
      cssWorking.toString('utf8')
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .split('\n').filter((l) => l.trim() !== '').join('\n'),
      'utf8');
    check('sheet: served == minified working file (one-transform contract)',
      cssServed.equals(minified), `${cssServed.length} vs ${minified.length} B servable-transform`);

    const manifestServed = await fetchText(`${anchor}/ui/continuum-manifest.json`);
    const manifestFixture = readFileSync(MANIFEST_FIXTURE);
    check('manifest route: served == fixture (byte-identical at base)',
      manifestServed.equals(manifestFixture), `${manifestServed.length} B`);
  } finally {
    for (const child of children) child.kill('SIGTERM');
  }
}

// ── main ─────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const serve = args.includes('--serve');
const baseUrlArg = args.find((a) => a.startsWith('--base-url='));
let baseUrls = {};
if (baseUrlArg) {
  const u = baseUrlArg.split('=')[1];
  baseUrls = { smoke: u, 'blocks-index': u, 'block-1': u, 'blocks-standalone': u, showcase: u };
}

if (serve) {
  await runServe({ baseUrls });
} else {
  runFixtures();
}

if (failures.length > 0) {
  console.error(`\ndx-content-pin: ${failures.length} FAILURE(S) — ${failures.join(', ')}`);
  process.exit(1);
}
console.log(`\ndx-content-pin: clean (${warnings.length === 0 ? 'no register reports' : warnings.length + ' register report(s): ' + warnings.join(', ')}).`);
