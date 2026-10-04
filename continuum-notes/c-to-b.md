# lane-c → lane-b: DX-3 measured-row coordination (W2 — the auto-declared-budget half)

## what lane C landed (measurement-fed budgets for both hand-written islands)

- **the band conformance check** — `Tests/WebUIIslandCoreTests/BudgetDriftTests.swift`:
  each declared `IslandBudget` pin (raw and gzip separately) must live in

      measured ≤ declared ≤ ceil(measured × 1.05)

  — never below the built artifact (a pin that lies), never looser than the
  auto-pin convention your DX-3 writes (measured × 1.05; plan §2.3). inside
  the band a human may tighten; outside it the check fails naming the exact
  re-pin. measurement source: the stripped artifacts
  `.build/out/Products/Release-webassembly-wasm32/*.wasm`; gzip = `gzip -n -9
  -c` (the tool `WebUIBudgetPlugin` already measures with). arm it by running
  `swift package --disable-sandbox plugin wasm-island` (both products) before
  `swift test`; artifact-less runs skip via `.enabled(if:)`.
- **validate re-pinned** → `IslandBudget(maxBytes: 185_503, maxGzipBytes: 85_265)`
  (was 200,000 / 90,000 — a 13%-loose guess from before the runtime
  conversion). measured: 176,669 raw / 81,205 gz. **probe stays
  240,000 / 105,000** (measured 233,952 / 100,186 — already inside the band;
  and a probe source touch is byte-anchor-sensitive, so its number must not
  move gratuitously).

## the cross-check your DX-3 rows arm (already implemented, dormant)

`BudgetDriftTests` walks `.build/plugins/outputs/*/*/destination/WebUIContinuumPlugin/ContinuumManifest.json`
(the same shape `WebUIBudgetPlugin.islandManifestURL` walks). when an
`islands[]` row matches an artifact by name containment (your `probe` ↔
`WebUIProbeIsland.wasm` rule), it asserts:

    row.raw == artifact file size      (measurement agreement)
    declared.maxBytes ≤ row.maxBytes   (tightening-only)
    declared.maxGzipBytes ≤ row.maxGzipBytes

today the manifest's `islands[]` is empty (the t4.2 scan reads `@HotView`
markers only; no marker-bearing sources), so the check prints a note and
skips. please keep your row keys as designed — `name/maxBytes/maxGzipBytes`
pins with `raw/gz/sha` alongside (§2.3): the checker reads
`raw`/`maxBytes`/`maxGzipBytes` and ignores extras.

## notes / asks

1. if your DX-3 scan extension covers hand-written `ContinuumIsland.budget`
   declarations (the wave-3 handoff noted in c-docs), the manifest rows for
   probe/validate will agree with the code declarations by construction —
   same formula, same headroom — and the cross-check goes live with no
   further lane-C change.
2. optional (W3 nicety, no W2 action): `wasm-island` has no `-D` passthrough;
   check-mode island builds currently need the manual swiftc recipe recorded
   in c-docs (the DX-9 section).
3. the band check does NOT require an exact `ceil(measured × 1.05)` match —
   a declared pin tighter than the auto-pin (but ≥ measured) is legal
   ("tightening-only"); it fails only on under-declaration or on slack wider
   than the conventional 5%.