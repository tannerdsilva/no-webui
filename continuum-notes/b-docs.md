# lane B — docs fragment (for the orchestrator to fold into the shared docs)

_commit `3c47a1f` (t1.3) · this is the lane-B doc contribution; the shared
docs (`CONTINUUM.md`, `CHANGELOG.md`, `ASSEMBLY.md`) are orchestrator-owned._

## the continuum class inventory (d1, plan §1.5 — contract for lanes E + D)

`Continuum+Generated.swift` — emitted into the **WebUI target** every build by
the `WebUIContinuumPlugin` build-tool plugin (runs `WebUIContinuumTool
generate --sources Sources/WebUIDesignSystemCore --output …`), land in
`.build/plugins/outputs/…/WebUIContinuumPlugin/`. never hand-edited.

the generated value (`public enum ContinuumClassInventory`):

| member | type | consumer |
|---|---|---|
| `components: [String: [String]]` | per-component claimed class vocabularies (literal `class="…"` + `@HotClass` declarations) | css reachability, the landed orphan ratchet's static half |
| `union: [String]` | every claimed class, sorted unique | `HTMLClassValidator` / css reachability |
| `attributeAllowlist: [String]` | base attr-op allowlist: `class`, `aria-*`, `data-*` | engine `attr` apply + validator (lane E d1 t1.1) |
| `unclaimedLiterals: [String]` | literals no component claims (warn-only source) | the lint; error level stays the orphan ratchet |

### scanner semantics (keep these strict)

- components are `public struct WebUI…` declarations at brace depth 0 in
  `Sources/WebUIDesignSystemCore/*.swift`.
- a `class="…"` literal inside a component body is claimed by that component;
  a literal outside any component is **unclaimed** (the lint warn).
- `@HotClass("a", "b")` markers (the d3 macro form) are recognized today and
  attach to the current component; a marker outside a component is a
  strict-marker violation (counts as unclaimed).
- the scanner reads sources as text (plan t1.3); interpolated class values
  (`class="\(var)"`) and classes built by concatenation are NOT in the static
  scan — they are the orphan ratchet's rendered-side coverage.
- `lint` re-scans and warns on literals the generated union does not claim;
  **warn-only in d1** — always exits 0. the build line is
  `[WebUIContinuumPlugin] inventory: N components, M classes, K unclaimed (warn)`.

### today's measured inventory (d0 tree)

`2 components, 7 classes, 0 unclaimed`: `WebUIEngineStatus` (engine-status-*
×5) and `WebUIThemeToggle` (theme-toggle* ×2). expected — the rest of the
design system builds class strings via interpolation, out of the literal scan
by design; the inventory grows when `@HotClass` vocabularies land (d3).

## d2 wave-2 additions (capability lint + the engine-facing served slice)

_commit `f75873f` (t2.6 lint) + the served-slice unit (wave 2)._

### the capability-grants lint (t2.6, commit `f75873f`)

`WebUIContinuumTool lint` now reads `@HotView` descriptors for their
`imports:` list and compares it against the **host grant list**: a
`ContinuumGrants` constant declared in the scanned sources wins, then
`--grants a,b,c`, then the framework default (every engine capability,
§1.3.4). a capability the host does not grant is a **build error** with the
parent plan's exact message:

```
island "feed" imports "surface_acquire" — not granted by the host manifest (add it to ContinuumGrants or drop the import)
```

the `WebUIContinuumPlugin` runs the lint as a second build step over the
design-system core + `Sources/WebUI` (where the consumer surface lives); a
clean scan writes a `Capabilities.ok` cache stamp, a violation exits non-zero
and the stamp never lands, so the gate is cached-green and fail-red.
accepted `imports:` spellings — array, dot-case (`.clock`), `.self` types
(`ClockCapability.self`), single string — so lane D's wave-2 marker shape
reconciles without negotiation. probe: `designer/probes/b-lint.mjs` (6/6).

### the engine's served slice (§1.5, closes E's static-seed handoff)

the engine cannot read swift, so the attribute allowlist (+ the class
inventory) is **also** emitted as a served, content-addressed asset: the
plugin emits `ContinuumEngineManifest+Generated.swift` into the WebUI target
— a `WebUIShippedAsset` conformance produced by the same
`WebUIAssetBuilder.emit` machinery as the css/js (one sha256 stamp, one gzip
variant, prose-gated). the payload is the `continuum-engine-slice` json
(`attributeAllowlist`, `components`, `union`).

**served path (for lane E at i2):** a host registers it like any shipped
asset — `WebUIAsset(ContinuumEngineManifest.self, path: "/ui/continuum-manifest.json")`
— and the engine fetches `/ui/continuum-manifest.json?v=<stamp>` (the stamp
is the content address; a rebuilt allowlist is a different url, so a
year-long immutable cache is safe). the payload's `attributeAllowlist`
(`["class","aria-*","data-*"]` today; component-declared names join when
`@HotClass` lands) is the superset of the wave-1 static seed — the engine
replaces `ATTR_ALLOW_EXACT`/`ATTR_ALLOW_PREFIX` with it. until the fetch is
wired, the engine stays conservative (its seed is harmless); the byte counts
the generated asset ships are reported on every build:
`[WebUIContinuumPlugin] engine slice: N bytes, sha <stamp>`.

### bench tooling contract (lanes consuming d0 numbers)

- `WebUIBench` — raw NIO host on `--port`/`WEBUI_BENCH_PORT` (default 9130;
  measure on lane-B 9200–9219). routes: `/bench/feed[?items=&windowed=&ops=]`,
  `/bench/grid?rows=&cols=`, `/bench/dashboard?series=&points=`,
  `/bench/editor`. one routed interaction per bench (feed append/sort/tick/
  commit). text responses all `charset=utf-8`.
- `designer/continuum-bench.mjs` — the §3 six-recipe harness. CLI:
  `node designer/continuum-bench.mjs --bench <feed|grid|dashboard|editor|windowed>
  [--items N --rows R --cols C --series S --points P --repeat N --port N]`.
  runs loopback **and** throttled (CDP latency 80 ms, 10 Mb/s down / 5 Mb/s
  up); writes `.bench/<bench>-<scale>[-throttled].json` (gitignored); non-zero
  exit on failed precondition. implementation notes: frame counter must be
  installed **before** `page.goto` (playwright only sees sockets born after);
  mutation census must observe a stable ancestor (a whole-region replace kills
  observers attached to the replaced node).
- the d0 verdict lives in `continuum-notes/b-d0-results.md`.
