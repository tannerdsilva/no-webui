# dx-baseline — the served-content golden fixtures (invariant I1)

captured once at W0 (2026-10-04, base `ec1bcbc`) by the LANE-B capture pass
into `/tmp/dx-content-baseline/` and committed here verbatim. the pin harness
(`../dx-content-pin.mjs`) verifies every committed byte against these records
and — in `--serve` mode — against live servers.

## layout

```
pages/
  smoke.page.html            WebUISmokeTest GET /            (26,907 B)
  blocks-index.page.html     WebUIBlocksServer --block index (4,090 B)
  block-1.page.html          WebUIBlocksServer --block dashboard (9,355 B)
  blocks-standalone.page.html  WebUIBlocksServer --block index, second process (4,090 B)
  showcase.page.html         WebUIShowcaseServer GET /      (167,764 B)
manifest/
  continuum-manifest.json    the engine slice the manifest route served at capture
base.txt                     base sha + the asset hashes (engine/shell/css/manifest)
pages.txt                    per-page canonical (nonce-normalized) + raw sha256 + bytes
```

`blocks-index` vs `blocks-standalone` are the SAME page captured from TWO
server processes: their raw hashes differ (per-process random CSP nonce) and
their canonical hashes are equal. that pair is the canonicalization's own test.

## the canonicalization (the harness owns the definition)

every document carries PER-PROCESS render noise that has no deterministic page
structure — a cross-process page diff must ignore all of it. the harness
canonicalizes four channels BEFORE hashing (all four measured live at base):

```
nonce="<base64url…>"            → nonce="N"          (the CSP prelude attr)
'nonce-<base64url…>'            → 'nonce-N'          (the CSP policy source)
name="_csrf" value="<…>"        → name="_csrf" value="CSRF"   (per-process HMAC token)
data-component-id="c<digits>"   → data-component-id="cN"       (per-process RenderContext counter)
data-optimistic="<json>"        → data-optimistic="OPS"        (Dictionary key order is per-process)
```

`data-optimistic` (and any JSON-Dictionary-serialized inline payload) cannot be
byte-pinned: Swift Dictionary key order is randomized per process, so even
identical data serializes differently across processes — the pin asserts the
marker, never the serialization. stable literal ids (`data-component-id="btn-x"`)
are untouched by the narrow `c\d+` shape.

deterministic, length-free, form-preserving. the same transformation applies to
committed fixtures and live bytes, so "clean" means the live page equals the
captured page modulo exactly these randomized channels.

## note: the pages.txt canonical column was regenerated at W1

the W0 record's "canonical" values were NOT reproducible from the captured
bytes by any nonce-normalizing transform (the W0 capture script's transform was
unrecorded — most likely a fixed-nonce re-render hash). the committed PAGE
BYTES are the load-bearing gold (their raw hashes match W0's raw column
exactly), and the harness regenerated the canonical column with the
documented transform above — same spec intent (nonce-normalized,
cross-process-stable), one format of record. `base.txt` is untouched.

## the exemption register

carried by the harness (see its header comment): `/ui/continuum-manifest.json`
is a named route with additive, versioned keys (byte-identical at base; a diff
fails unless registered-additive); `webui-engine.js` is I3-governed (never a
byte fail — the byte account is reported; `plugin budget` owns the ceiling);
page migrations must be byte-identical to the captured bytes (a diff = the
migration is wrong). everything else is byte-pinned.
