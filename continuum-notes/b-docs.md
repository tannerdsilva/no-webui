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

## wave-2 bench re-run (merged tree; base `8eac8ae`)

re-ran the d0 harness once on the merged tree (`node designer/continuum-bench.mjs`
per bench, lane port 9206; loopback + throttled per the recipe-6 gate). all
five benches green (`feed` 7/7, `grid` 5/5, `dashboard` 5/5, `editor` 7/7,
`windowed` 5/5 — 29/29 precondition assertions).

| metric | d0 (recorded) | wave-2 (one run) | delta |
|---|---|---|---|
| tti · feed@10k | 102 ms / 709 ms | 138.2 / 707.5 | loopback +36 ms (noise-tier) |
| tti · grid 500×10 | 43 / 784 | 42.9 / 784.4 | — |
| tti · dashboard 8×100 | 97 / 762 | 99.3 / 783.1 | — |
| tti · editor | 23 / 756 | 24.1 / 767.4 | — |
| scroll fps · feed 10k | p95 62.4 / 61.5 | 62.4 / 62.4 | — |
| echo settled · editor | 311 ms / 368 ms | **448.1 / 434.9** | **material: +137 loopback, +67 throttled** |
| append-100 replace | 1,501,978 B / 46 ms | 1,501,978 B / 71.5 ms | bytes —; rt within noise |
| append-100 op | 19,531 B / 33 ms | 19,531 B / 32.5 ms | — |
| grid sort | 81,920 B / 32 / 86 ms | 81,920 B / 32.2 / 78.6 | — |
| dashboard tick | 278,399 B / 67 / 293 | 278,399 B / 65.4 / 325 | — |
| window step naive/ops | 8,694 B / 2,191 B | 8,694 B / 2,191 B | bytes — (rt 0.8 / 0.8 → 10.5 / 4.8 throttled) |

the one number that moved materially is **editor echo settled**, and it moved
the *wrong way* (slower) despite lane E's t1.4 local echo landing in the merged
tree. likely causes, in order: (a) the editor bench's echo-settled recipe
measures the authoritative-settle edge, which the merged engine now delays
behind local-echo + reconcile rather than a single server round trip — the
metric's meaning may have shifted with the feature, or (b) one noisy run
(repeat=1). flagged to lane E at i2: re-read the echo recipe against t1.4's
contract before treating +137 ms as a regression. everything conclusion-bearing
(the 77× replace/op byte gap, the 4× window-step byte gap, scroll p95 62 ms,
throttled dominance) is unchanged at these scales.

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

## wave 3 — i3-gate prep, echo-settled ruling, bench re-run (base `f9faaba`)

_commit `b3fa06f` (b-lint live-tree) — t2.6 re-verified against D's LANDED
markers. commit `eafa482` (d3-gate harness). the content below is the wave-3
doc contribution (fragments → b-docs.md, never the shared docs)._

### 1. b-lint vs the landed imports shapes (re-verify, wave 3)

ran `designer/probes/b-lint.mjs` against the **real** markers now in the tree:
D's compiled fixture (`Tests/WebUIContinuumMacroTests/ContinuumCompiledFixture.swift`,
`@HotView("counter", imports: [ClockCapability.self], budget: IslandBudget(maxBytes:
16_384, maxGzipBytes: 4_096))`) plus the macro-expansion suite's spellings. the
probe now adds two **live-tree** assertions on top of the six fixture ones
(`8/8`): restricted grants flag the fixture's `clock` import, and the fully
granted run exits 0. **the accepted spelling set needed NO tightening** — every
landed spelling is one the scanner already accepts:

| spelling | live in tree at? | normalized |
|---|---|---|
| array of `.self` types `[ClockCapability.self]` | compiled fixture + `HotViewMacroTests` | `clock` |
| single string `imports: "clock"` | hot-view spellings in tests | `clock` |
| empty array `imports: []` | expansion suite | none |
| dot-case `.surface_acquire` | (fixture `forms/` only today) | `surface_acquire` |
| multi-import `[ClockCapability.self, LogCapability.self]` | `HotViewMacroTests` | `clock, log` |

the two `@HotView` markers that land in the **plugin-scanned** dirs
(`Sources/WebUI` today) carry no imports; the lint gate over the real tree is
green (`2 components, 7 classes, 0 unclaimed`, capability check clean). the
spec message is unchanged and verbatim.

### 2. the d3 gate harness (i3-gate single-command measurement)

`designer/d3-gate.mjs` — ONE command, lane ports 9200–9219. measures the three
i3 gates against the plan's explicit budgets (§5):

```
node designer/d3-gate.mjs [--bench-port 9210] [--probe-port 9211]
                          [--items 10000] [--throttle 80] [--echo-chars 16]
```

1. **feed 10k scroll p95** (plan §5 "60 fps / p95 ≤ 20 ms"): naive full-list +
   the two windowed variants, loopback AND throttled (recipe 6 is a gate, not
   advice). the naive 10k full-render *wall* (~62 ms p95) is **recorded, not
   asserted green** — it is precisely why windowing exists (d0 verdict). the
   budget-bearing checks are the windowed variants.
2. **grid echo < 50 ms @ 80 ms rtt** (plan §5 "keystroke echo < 50 ms at
   80 ms rtt"): the t1.4 **engine-local** echo contract (`data-webui-echo`)
   driven under an 80 ms rtt link, measured entirely in page time (keydown
   recorder + MutationObserver on the echo targets, installed from outside);
   asserts p95 < 50 ms **and zero ws frames during typing** (a server round
   trip can never pass this gate).
3. **degrade** (t2.6): a `data-webui-island` region whose `.wasm` is **not
   served** (404) must stay `unmapped`, keep its **server-rendered content**,
   and leave the engine instance alive.

writes `.bench/d3-gate.json`; exits non-zero on a gate failure.

**dry-run baseline on the merged tree (f9faaba, recorded honestly):**

| gate | result | number |
|---|---|---|
| scroll naive 10k throttled | ⚠ recorded wall | p95 62.4 ms (loopback 62.9) — the full-render wall |
| scroll windowed throttled | **FAIL → t3.3** | p95 52.8–66.4 ms — server-orchestrated window step round-trips *per scroll event* (d0 finding); not the engine-local path yet |
| scroll windowedOps throttled | **FAIL → t3.3** | p95 35.4–66.0 ms — same cause |
| grid echo @ 80 ms rtt | **PASS** | p95 **0.2 ms**, p50 0.1 ms, 16/16 samples, **0 ws frames** (engine-local) — the t1.4 echo is real and in budget |
| echo authoritative wins | **PASS** | server `text` op overwrites the overlay and clears it |
| degrade | **PASS** | `unmapped` + server-rendered `<p>…fallback…</p>` intact + engine alive |

the echo gate passing at 0.2 ms while the bench editor's *server* echo settles
at ~360–450 ms is exactly the desktop-grade story: the engine-local path is
what the <50 ms budget means; the naive round trip is debounce-bound by design.
the gate cannot fully go green until engine/island-local windowing (`t3.3`)
lands — the harness is prepared, the baseline is recorded, and the two FAILs
are now the tracking signal for that work.

### 3. the echo-settled ruling (311→448 ms): run variance, NOT a metric change

asked: is the editor echo-settled move (d0 311/368 → wave-2 448/435) real drift
or a metric-meaning change? re-read the recipe (continuum-bench `echoLatency`),
the engine source, and re-measured **isolated, repeat=5** on the merged tree:

| run | loopback settled (ms) | throttled settled (ms) |
|---|---|---|
| d0 (8eac8ae) | 311 | 368 |
| wave-2 (merged, repeat=1, the "one noisy run" wave-2 itself flagged) | 448.1 | 434.9 |
| wave-3 isolated repeat=5 | 361.1 median (316.3–453.4) | 415.0 median (310.4–444.0) |

**ruling: the wave-3 "spike" was single-run variance on a loaded machine, not
drift and not a metric-meaning change.** three independent facts:

- **the measured circuit is unchanged.** `git diff 8eac8ae..f9faaba --
  Sources/WebUIBench/` is empty (the editor fixture is byte-identical) and the
  engine's debounce (`debounceInputMs 300 / maxWait 1000`) + `echo`/`clearEcho`
  body are unchanged across the merge. t1.4's engine-local echo cannot be the
  cause: it only activates on a `data-webui-echo` attribute, and **the bench
  editor has none** — its echo is still the naive server round trip the recipe
  has always measured. the metric's meaning is unchanged.
- **repeat=5 brackets d0.** the wave-3 isolated loopback samples spread 316.3–
  453.4 (median 361.1); d0's 311 and wave-2's 448 are both inside that spread.
  single-run deltas of ±50–130 ms at the debounce edge are not distinguishable
  from variance at this scale (the trailing debounce timer + MutationObserver
  delivery add real jitter).
- the throttled median (415) sitting *above* loopback (361) by ~54 ms is the
  honest rtt signature; wave-2's throttled-below-loopback inversion (435 < 448)
  is itself the fingerprint of a corrupted (contended) run.

**conclusion for the records: do NOT treat 448 as a regression, and do NOT
change the metric or the recipe** (recipe changes are E/D's). the honest
current reading is editor echo-settled ≈ **361 ms loopback / 415 ms throttled**
(debounce 300 + rtt + server), unchanged within noise of d0. the budget that
matters for the i3 gate is the engine-local echo (see §2, 0.2 ms), not this
server round-trip number. handoff to E at i3 stays informational: the bench
editor echo remains a server-round-trip fixture by design; if it should ever
measure the local path, that is a fixture change + its own pin, to be decided
with E/D, not silently.

### 4. wave-3 bench re-run (merged tree, isolated, repeat=3 except editor repeat=5)

| metric | d0 (recorded) | wave-2 (one run) | wave-3 isolated | delta vs d0 |
|---|---|---|---|---|
| tti feed@10k | 102 / 709 ms | 138.2 / 707.5 | **98.0 / 429.4** | loop −4, thr −280 (throttled tti noisy) |
| tti grid 500×10 | 43 / 784 | 42.9 / 784.4 | **42.9 / 784.4** | — |
| tti dashboard 8×100 | 97 / 762 | 99.3 / 783.1 | **95.0 / 485.5** | thr −277 (noisy) |
| tti editor | 23 / 756 | 24.1 / 767.4 | **11.9 / 467.9** | thr −288 (noisy) |
| scroll p95 feed 10k | 62.4 / 61.5 | 62.4 / 62.4 | **61.1–62.3 / 60.8–62.3** | — (the wall) |
| echo settled editor | 311 / 368 | 448.1 / 434.9 | **361.1 med / 415.0 med** (r5) | +50 / +47, within spread (see §3) |
| append-100 replace | 1,501,978 B / 46 ms | 71.5 ms | **1,501,978 B / 43.0–49.6** | — |
| append-100 op | 19,531 B / 33 ms | 32.5 ms | **19,531 B / 30.4–31.1** | — |
| grid sort | 81,920 B / 32 / 86 | 78.6 | **81,920 B / 32.2** | — |
| dashboard tick | 278,399 B / 67 / 293 | 325 | **278,399 B / 70.6–74.1** | — |
| window step naive/ops | 8,694 / 2,191 B | 10.5 / 4.8 thr | **8,694 / 2,191 B; 0.7–0.9 loop, 4.6–8.8 thr** | — |

all five benches green (feed 7/7, grid 5/5, dashboard 5/5, editor 7/7,
windowed 5/5 = 29/29 preconditions). conclusion-bearing numbers are unchanged:
77× replace/op byte gap, 4× window-step byte gap, the 62 ms full-render scroll
wall, throttled dominance. throttled tti moved *down* ~280 ms vs the wave-2
one-run (contended) reading but stays well above loopback — tti at 80 ms rtt is
noisy at repeat=1; treated as qualitative only.

### 5. canonical-gate fold-in list (wave-3 → polish wave, lane B owns)

which lane-B probes belong in which canonical gate, for the orchestrator's
fold-in (never edited by the lane; listed here for tracking):

| canonical gate | lane-B probes/clients to fold | note |
|---|---|---|
| build ladder (`swift build` + plugin) | `WebUIContinuumTool` lint/generate gate (already wired via `WebUIContinuumPlugin` — t2.6 capability check + budget plugin) | the class-inventory + capability grant gate is already in the build; nothing new to add |
| `plugin smoke` | `designer/probes/b-lint.mjs` (8/8) as a standalone probe; `designer/probes/b-interaction-smoke.mjs` (ws interaction smoke) | fold as a probe list entry, not more build commands |
| `fullstack-smoke` | `designer/probes/b-windowed-smoke.mjs` (naive + ops window advance) | already fullstack-shaped; ensure it's invoked with a lane port on the fold-in |
| `browser-smoke` | engine-path probes stay in the existing browser-smoke; lane-B adds `designer/d3-gate.mjs` as the agg gate | run d3-gate on a lane port **after** the smoke ladder, before the bench refresh |
| bench ladder (i3/eval) | `designer/continuum-bench.mjs` (the five benches) + `designer/d3-gate.mjs` | the d3-gate is the single-command i3 measurement; the five benches are the periodic refresh |

the two windowed-scroll FAILs in §2 are the fold-in's tracking signal: the
polish wave's job is `t3.3` engine/island-local windowing, not a bench change.
