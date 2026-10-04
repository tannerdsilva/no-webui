# lane B → lane D handoff (DX-3 measured-row shape + DX-2 adapter pin)

## 1. the measured-row shape for the macro-side tightening diagnostic (DX-3)

b-docs:571-573 promised "B exposes maxBytes/raw/gz/sha per island in the
work-dir manifest; D consumes for the imports:→budget retirement". the W2
implementation lands the row in the **WebUIAutobuildPlugin work-dir
ContinuumManifest.json** — NOT the WebUIContinuumPlugin/generate-path one.
both manifests coexist; the budget plugin now reads BOTH
(`WebUIContinuumPlugin` declared pins + `WebUIAutobuildPlugin` measured rows /
`--autobuild-manifest` override for probes) and enforces the tightest per field.

### the exact row

`islands[]` entry, per artifact, in the work-dir manifest (version 2):

```json
{"name": "FeedIsland", "maxBytes": 138780, "maxGzipBytes": 65777,
 "raw": 132171, "gz": 62644,
 "sha": "d7f201185100ca5813c143573dd2c98d0555346c99bef54f4c780ca5bcd40b04",
 "url": "/__assets/webui-FeedIsland.wasm"}
```

- **pin keys EXACTLY `name/maxBytes/maxGzipBytes`** — what WebUIBudgetPlugin
  reads (one budget path, I5). `maxBytes = ceil(raw×1.05)`,
  `maxGzipBytes = ceil(gz×1.05)`.
- **`name` = the PRODUCT/target name (the artifact dir basename)**, not the
  `@HotView` island name. the product ↔ island-name mapping is NOT in the row.
  consumers must use the same case-insensitive containment the budget plugin
  uses to match (a declared "feed" row and a measured "FeedIsland" row collide
  onto one island). this is the one deliberate deviation from a literal
  "island name" reading — documented here so D matches by containment, exactly
  like the budget plugin does today.
- `sha` is over the STRIPPED artifact (what ships), via `WebUIBuild.sha256Hex`
  (now public — a rename/removal breaks `measure`, the budget-adjacent probe
  and any D consumer loudly).
- `url` = the existing URL convention for the artifact name.

### the served manifest

`WebUIServer` (DX-6b, config `islandWorkDirectory`) splices these measured rows
into the served `/ui/continuum-manifest.json` islands[] (version 1→2, additive;
generate path stays authoritative for allowlist/union/components). the engine
consumes islands[] when present (DX-6e, lane E's side).

## 2. the DX-2 adapter pin (break-both-loudly)

the scaffold-generated island main names the macro-produced adapter
`<Type>.<Type>Island` (qualified). the pin string:

```
IslandRuntime<Feed.FeedIsland>.run()
```

- lane D's expansion emits `struct <Type>Island: ContinuumIsland` nested in
  `extension <Type>` (islandQualifiedName "<Type>.<Type>Island" recorded in
  d-docs/d-built fixture).
- `Tests/WebUIContinuumToolTests/ScaffoldTests.swift` asserts the generated
  main contains exactly `IslandRuntime<Feed.FeedIsland>.run()` and NOT the
  unqualified `IslandRuntime<FeedIsland>` — so a rename on D's side breaks the
  scaffold test loudly, and a main-format change on B's side breaks D's fixture
  compile equally loudly. keep them in lockstep.
- the generated main carries the `@_silgen_name("webui_island_bind")` shim +
  `#if os(WASI)` guard; the host build sees an inert `@main` stub.

## 3. open items / observations for the reconciler

- **`plugin budget` on the FRAME's own checkout is unchanged** (no autobuild
  work dir exists there — WebUIAutobuildPlugin is consumer-attached only); a
  consumer app gets auto-pins enforced by the SAME gate with a plain run from
  its own package root (the work-dir walk finds the consumer's autobuild
  manifest), or via `--island-dir` for probes.
- the work-dir manifest is a build product in the plugin work dir — never
  committed, never a source of truth for the generate path.
- `WebUIBuild.SHA256`/`sha256Hex`: `sha256Hex(_:)` made `public` (additive);
  the budget pin `b-budget-pins.mjs` probes the raw/gz/sha keys only.
