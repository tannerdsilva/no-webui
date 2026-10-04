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

every document mints a random CSP nonce per process (`HTMLDocument` echoes it
into the policy as `'nonce-…'` and into the inline prelude as `nonce="…"`), so a
raw hash is unique per process and cross-process diffs always false-fire
(red-team fold a). the harness canonicalizes BEFORE hashing:

```
nonce="<base64url…>" → nonce="N"
'nonce-<base64url…>' → 'nonce-N'
```

deterministic, length-free, quoted-form-preserving. the same transformation
applies to committed fixtures and live bytes, so "clean" means the live page
equals the captured page modulo exactly that one randomized attribute.

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
