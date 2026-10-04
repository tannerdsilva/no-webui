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

**EXECUTED in the polish wave (commit `a9bd58a`).** the final mapping (what
each canonical gate now invokes, via the fold-in runner
`designer/gates/b-probe-fold.mjs`):

| canonical gate | lane-B probes/clients folded (final) | how |
|---|---|---|
| build ladder (`swift build` + plugin) | `WebUIContinuumTool` lint/generate gate (already wired via `WebUIContinuumPlugin` — t2.6 capability check + budget plugin; the class-inventory + capability grant gate lives in the build) | nothing new to add — already in the build |
| `plugin smoke` | `designer/probes/b-lint.mjs` (8/8) + `designer/probes/b-interaction-smoke.mjs` (6/6) | `b-probe-fold.mjs --lint --interaction`, appended to `WebUISmokePlugin` after the smoke checks; traffic on lane port 9212 |
| `fullstack-smoke` | `designer/probes/b-windowed-smoke.mjs` (5/5) | `b-probe-fold.mjs --windowed`, appended to `WebUIFullstackSmokePlugin` after the ws round-trips; lane port 9213 |
| `browser-smoke` | `designer/d3-gate.mjs` as the aggregate gate | `b-probe-fold.mjs --d3` (d3-gate on lane ports 9210/9211), invoked at the end of `designer/browser-smoke.mjs` **after** the smoke ladder |
| bench ladder (i3/eval) | `designer/continuum-bench.mjs` (the five benches, `--repeat 3` default) + `designer/d3-gate.mjs` | the d3 gate is the single-command i3 measurement on lane ports; the five benches are the periodic refresh |

fold-in runner: `node designer/gates/b-probe-fold.mjs [--lint] [--interaction]
[--windowed] [--d3] [--all]` — exits non-zero on any probe failure; every
self-spawned server uses a lane port (9200–9219) and is killed on exit; the
canonical ports 9123/9130 are never touched.

constraints honored: the smoke gate's pins (25-component count, byte
integrity, CSP) are untouched (`SMOKE PASS 19/19` before the fold);
fullstack's round-trip checks are untouched (`22/22`); browser-smoke's
layout/Escape/layers checks are untouched (`46/46` including the folded d3
gate). the pre-polish table listed which probes belong where; this table
records the executed wiring.

---

## POLISH wave — §1: the d3 gate closes, with the fps criterion re-based (base `d5cb0c4`)

_commit `a1e33a5` (gate) — polish §1. the §2 FAIL rows are now historical:
the gate drives the engine-local fixture and is green._

### the criterion re-basing (why the absolute rAF ≤ 20 ms budget is gone)

the plan's §5 "60 fps / p95 ≤ 20 ms" budget is a **display-refresh-coupled**
number: on a 60 Hz host one frame is 16.7 ms, so "p95 ≤ 20 ms" means "no
frame ever misses a refresh". this host's display is **30 Hz (measured in
gate: refresh floor p50 **33.4 ms**, p95 **66.8 ms** on an idle rAF loop —
CoreGraphics `refreshRate == 30`, never hardcoded)**: one refresh is ~33 ms,
so an absolute "p95 ≤ 20 ms" rAF budget is **unmeasurable here by
construction** — even a perfectly idle page exceeds it every frame. this is
not a performance regression; it is the host floor (E's e-docs t3.3
resolution, same measurement).

**the budget re-bases onto the display-independent quantity: ENGINE
SCROLL-WORK p95 ≤ 20 ms** (scroll-dispatch → rewind window → mutations
settle, measured entirely in page time via a capture-phase listener
installed before the engine's own — the e-windowed recipe). scroll-work is
the t3.3 "frame budget" that matters: it is the engine's _actual_ windowing
work per scroll event, independent of when the display happens to paint.
the absolute rAF numbers are **recorded** (`.bench/d3-gate.json`) so a 60 Hz
host can assert the original budget; on this 30 Hz host the gate asserts
scroll-work + the window invariants.

### the fixture that engages the engine (the §2 fixture mismatch)

the old windowed rows drove `/bench/feed?windowed=1[&ops=1]` — a
**server-orchestrated** window whose step round-trips to the server per
scroll event (the d0 finding), which is precisely why it could never meet
the budget. the polish fixture is `/bench/feed?windowed=engine`:

- **renders lane D's `Viewport` component** (the real Swift component,
  `Sources/WebUIDesignSystemCore/Viewport.swift`) server-side as the full
  **degrade** render (all 10k rows ≤ `pageSizeLimit`, no pager);
- **serves E's `data-webui-lease="viewport"` contract on the root** (the
  server-adapter lease emission that e-to-d.md t3.3 and d-to-e.md explicitly
  sanction — D's component emits `data-webui-viewport`; the lease is the
  engine's consumption attribute, added by the bench host as the adapter);
- the engine's `createWindowManager` then takes over client-side:
  engine-local scroll delivery, ~56 attached rows of the 10k pool, spacer-
  held document height.

### gate row (merged tree, `d5cb0c4`; lane ports 9210/9211; two runs stable)

| gate | result | number |
|---|---|---|
| host refresh floor (in-gate, measured) | note | p50 33.4 ms / p95 66.8 ms (30 Hz host) — the rAF budget's host floor |
| scroll naive 10k (recorded baseline) | recorded, never asserted | p95 39.4 (loop) / 58.4 (throttled) ms — the full-render wall |
| scroll engine-local loopback | **PASS** | scroll-work p95 **2.40 ms** (≤ 20), attached 34–56 (≤ 90), childList-only churn (902, 0 char/attr), moved 0→24000 |
| scroll engine-local throttled (80 ms rtt) | **PASS** | scroll-work p95 **2.60 ms** (≤ 20), attached 55–56 (≤ 90), childList-only (923), moved 24000→48000 |
| engine-local rAF p95 (recorded; floor-bound on 30 Hz host) | note | 65.9 / 66.2 ms ≈ host floor — for 60 Hz hosts, not asserted here |
| grid echo @ 80 ms rtt | **PASS** | p95 0.2–0.3 ms, 0 ws frames (engine-local) |
| echo authoritative wins | **PASS** | text op overwrites overlay and clears it |
| degrade | **PASS** | unmapped + server-rendered content intact + engine alive |

**D3 GATE PASS** (`node designer/d3-gate.mjs` → 14/14, exit 0), stable across
two consecutive runs. the t3.3 engine scroll-work (2.4–2.6 ms p95) is the
number that carries the "20 ms frame-budget" claim on this host — 8× under
budget, unchanged by throttle (engine-local: the wire isn't in the path).

---

## POLISH wave — §2: bench `--repeat` default 3 + final numbers refresh (base `d5cb0c4`)

_commit `822dd13` (this section). the `--repeat` default in
`designer/continuum-bench.mjs` is bumped **1 → 3** (each metric now samples
three times by default; the isolation lesson of the echo-settled ruling §3 —
single-run numbers on this loaded host are noise-tier)._

### final refresh (merged tree, repeat=3 default; all five benches green)

preconditions 29/29 (feed 7/7, grid 5/5, dashboard 5/5, editor 7/7, windowed
5/5) on lane port 9206. medians-of-3 below:

| metric | d0 (recorded) | wave-3 (r1–r5) | polish repeat=3 | delta vs d0 |
|---|---|---|---|---|
| tti feed@10k | 102 / 709 ms | 98.0 / 429.4 | **91.3 / 407.0** | loop −11 (noise-tier), thr within spread |
| tti grid 500×10 | 43 / 784 | 42.9 / 784.4 | **30.2 / 525.6** | both down (throttled tti noisy) |
| tti dashboard 8×100 | 97 / 762 | 95.0 / 485.5 | **91.1 / 429.0** | loop −6, thr within spread |
| tti editor | 23 / 756 | 11.9 / 467.9 | **12.4 / 497.4** | — |
| scroll p95 feed 10k | 62.4 / 61.5 | 61.1–62.3 / 60.8–62.3 | **62.4 / 62.2** (r3) | the wall, unchanged |
| echo settled editor | 311 / 368 | 361.1 med / 415.0 med | **448.9 med / 443.3 med** (r3) | within the §3 spread (variance, not drift) |
| append-100 replace | 1,501,978 B / 46 ms | 43.0–49.6 | **1,501,978–1,532,378 B / 48.1 med; thr 1,427 ms** | bytes —, rt within noise |
| append-100 op | 19,531 B / 33 ms | 30.4–31.1 | **19,531 B / 54.2 med (32.7–65.6)** | — |
| grid sort | 81,920 B / 32 / 86 | 32.2 | **81,920 B / 32.8 med / 85.7 med** | — |
| dashboard tick | 278,399 B / 67 / 293 | 70.6–74.1 | **278,399 B / 73.1 med / 326 med** | — |
| window step naive/ops | 8,694 / 2,191 B | 0.7–0.9 / 4.6–8.8 thr | **8,694 / 2,191 B; 0.78 / 0.72 loop, 9.8 / 4.1 thr** | — |

conclusion-bearing numbers are unchanged at repeat=3: the 77× replace/op
byte gap (1,501,978 vs 19,531 B), the 4× window-step byte gap (8,694 vs
2,191 B), the 62 ms full-render scroll wall, throttled dominance. editor
echo-settled medians (448.9/443.3) sit inside the §3-ruled single-run spread
(316.3–453.4 loopback) — no new signal.

### d3-gate rows (polish, for the §1 table)

`node designer/d3-gate.mjs` (lane ports 9210/9211, two consecutive runs):
**14/14 PASS both**. the engine-local scroll rows (loopback / throttled):
scroll-work p95 **2.40 / 2.60 ms** ≤ 20; attached rows 34–56 / 55–56 ≤ 90;
childList-only census (902 / 923, 0 char/attr); scroll moved 0→24000→48000.
grid echo @ 80 ms rtt p95 0.2–0.4 ms, 0 ws frames; authoritative-wins PASS;
degrade PASS. host refresh floor measured in-gate: p50 33.4 ms / p95 66.8 ms
(30 Hz host) — recorded, never hardcoded.

### gates (exact, this run)

```
swift build                                                 -> Build complete
swift test (full)                                           -> (terminal gate, see below)
swift package --disable-sandbox plugin smoke                -> SMOKE PASS 19/19 + b-lint 8/8 + b-interaction 6/6
swift package --disable-sandbox plugin fullstack-smoke      -> FULL-STACK 22/22 + b-windowed 5/5
node designer/browser-smoke.mjs                             -> BROWSER SMOKE PASS 46/46 (incl. d3 gate 14/14)
node designer/continuum-bench.mjs --bench {feed,grid,dashboard,editor,windowed} (repeat=3 default) -> PASS ×5 (29/29)
node designer/d3-gate.mjs                                   -> D3 GATE PASS 14/14 (2× stable)
swift package --disable-sandbox plugin budget               -> budget: PASS (see budget gate)
```

---

## CONTINUUM_DX W1 — lane B (base `ec1bcbc`): autobuild demo-or-kill, content pin, scaffold/auto-pin designs

_this wave's lane-B scope per CONTINUUM_DX §4.3: the DX-5 demo-or-kill spike,
`dx-content-pin.mjs` implementation, and the DX-2/DX-3 designs (implementation
is W2). the verdict sections below carry the measured numbers._

### DX-5 verdict + the mechanism (the load-bearing result)

see the report (`lane: b` final answer) and `designer/gates/dx5-demo.sh` for the
reproducible runner; one-line verdict: **candidate (b) — direct two-stage swiftc
from a build-tool plugin — cross-builds the REAL island graph from a plain
`swift build` in a home-dir scratch app.** details:

- the plugin: `Plugins/WebUIAutobuildPlugin` (buildTool, product `WebUIAutobuildPlugin`).
  consumer attaches it to its own target; at every `swift build` it emits one
  build command per island. the graph root is found in the attached package or
  via `context.package.dependencies` (`PackageDependency.package.directoryURL`;
  verified — no `PackageDependency.name` in Swift 6.0's API). islands are
  discovered by the house text rule: a `Sources/<Name>/main.swift|Main.swift`
  that imports `WebUIIslandCore`. consumer islands (the DX-5 end state) live in
  the ATTACHED package's Sources and are cross-built too (`--main-dir`).
- the command: `WebUIContinuumTool wasm-cross` (new verb, `Sources/WebUIContinuumTool/WasmCross.swift`).
  two-stage swiftc reproducing EXACTLY the ground-truth lines SwiftPM emits for
  `--swift-sdk swift-6.4.0-RELEASE_wasm-embedded` (captured via `swift build -v`):
  compile each module (`-parse-as-library -package-name no-webui -static-stdlib
  -enable-experimental-feature Embedded -Osize -wmo`, `-emit-module` for the two
  leaves so the next module imports them), link (`-emit-executable --gc-sections
  -static-stdlib -enable-experimental-feature Embedded -wmo -lswift_Concurrency
  -lc++`) + `-lswiftUnicodeDataTables` from the sdk's
  `…/embedded/wasm32-unknown-wasip1/` dir — the one piece the stock line omits,
  without which the link fails on `_swift_stdlib_getNormData` (measured; the
  `wasm-island` verb already worked around it).
- the compiler is the **swiftly-hosted toolchain swiftc**
  (`~/Library/Developer/Toolchains/swift-*.xctoolchain/usr/bin/swiftc`, resolved
  host-side, `WEBUI_WASM_SWIFTC` override) — the ground-truth log itself execs
  that path; the Xcode frontend cannot (no `swift-autolink-extract`, sdk modules
  unreadable). the sandbox's `(allow process*)` lets the command exec it.
- the trap honored: artifact lands in **`context.pluginWorkDirectoryURL`** (the
  only package-adjacent writable zone under the `(allow file-read*)`+tmp-only
  seatbelt on a home-dir checkout), never `.build/out/Products/…` (a build
  command may not write that on a home-dir project; `/tmp` runners get it "for
  free" — the acceptance test must keep its home-dir shape).
- equivalence anchor: direct-build Probe = 232878 B stripped vs the nested
  release 231984 B (i3 record) → 0.4%; Validate 163708 vs 164921 → 0.7%.
- warm cost ≈ 0 from llbuild (declared inputs/outputs), NOT an in-tool hash —
  measured in the runner; targeted invalidation (an edit to ONE consumer island
  re-runs exactly its command).
- same-wave machinery the plan demanded: recursion-guard env convention
  (`WEBUI_ISLAND_NESTED=1` — backstop in the tool, set on children), named
  prereq diagnostics (missing swiftc → `[WebUIAutobuild] cannot cross-build …
  swiftly toolchain is a one-time machine prerequisite`; missing sdk → names
  `swift sdk list`).

### dx-content-pin — the I1 harness (implemented, clean at base)

`node designer/dx-content-pin.mjs` (hermetic default; `--serve` for live
servers on lane ports 9201-9205) + the golden fixtures under
`designer/dx-baseline/` (pages + manifest + base.txt + pages.txt; captured at
W0 into `/tmp/dx-content-baseline/`, committed verbatim). three mechanics per
§3.1:

1. **nonce canonicalization** — `nonce="…"` / `'nonce-…'` → `nonce="N"` /
   `'nonce-N'` before hashing. the model is self-proving: `blocks-index` vs
   `blocks-standalone` are the same 4090-byte page from TWO processes — raw
   hashes differ, canonical hashes equal (asserted in both modes).
2. **the exemption register** — `/ui/continuum-manifest.json`: byte-identical at
   base, a diff fails unless registered-additive (version key bumped, additive
   keys only); `webui-engine.js`: I3-governed, NEVER a byte fail — raw+gz delta
   account reported (the `plugin budget` gate owns the ceiling); page migrations
   (DX-11a): byte-identical to the captured bytes or the migration is wrong.
   everything else (smoke/blocks-index/block-1(dashboard)/showcase pages, shell,
   minified sheet `served == comment-stripped working file`) is byte-pinned.
3. **provenance note**: the W0 record's "canonical" values were NOT reproducible
   from the captured bytes by any nonce-normalizing transform (unrecorded W0
   transform, most likely a fixed-nonce re-render hash). the committed PAGE
   BYTES are the gold (raw hashes match W0's raw column exactly); pages.txt's
   canonical column was regenerated with the harness's documented transform
   (same spec intent, one format of record). recorded in the baseline README.

### DX-2 scaffold — design (implementation W2)

the `continuum` surface lands as a new command plugin
(`WebUIScaffoldPlugin`, verb `scaffold`, `--writeToPackageDirectory`), executing
`WebUIContinuumTool scaffold` (the tool already owns every other build-side
verb; a plugin cannot import a library). no port. two sub-surfaces:

- **`--add-island <Name>`** — appends the two Package entries (product +
  executableTarget, beside their sibling blocks, one per commit per the shared
  hygiene) and generates `Sources/<Name>/main.swift` — the **3-line form once
  lane-C's DX-1 `IslandRuntime<NameIsland>.run()` lands** (`#if os(WASI)
  IslandRuntime<NameIsland>.run() #endif`); until then the reactor-shell
  template (the exact FeedIsland main from this wave's demo runner). every
  generated file carries the house `generated — do not edit` header. zero
  Package.swift edits for the SECOND island onward (the autobuild plugin scans
  the package; no manifest-side magic — candidate (c) is dead).
- **`--bootstrap [--name <App>]`** — for an EXISTING app: inserts the
  once-per-app inert continuum block (the §0.3 acceptance "template for new
  apps" has an equivalent committed block; this is the existing-app path): the
  framework path dep + `WebUIAutobuildPlugin` on the app target. the block is
  STATIC ("never changes per island" — the §0.3 frontier stated honestly);
  afterwards islands need no further manifest edits.
- prereq/UX: refuses to patch a manifest with uncommitted structure it cannot
  anchor on (append-only anchors only); a `--print` mode emits the snippet for
  teams that decline write permission; port-free (command plugin, on demand).
- W2 gate: scaffold a fixture consumer under the acceptance runner's prep, then
  the §0.3 preflight; the generated main compiles for BOTH host (inert) and wasm
  (autobuild cross-builds it).

### DX-3 auto-pin — design (implementation W2)

the measured pin rides the artifact the autobuild command already produces; no
second measurement pass:

- `wasm-cross` (or a tiny sibling `measure` mode) computes, at build time:
  `sha` (sha256 over the stripped artifact — via WebUIBuild's rawdog-sha path),
  `raw` (stripped byte count), `gz` (gzip length), and the pins
  `maxBytes = ceil(raw × 1.05)`, `maxGzipBytes = ceil(gz × 1.05)`.
- writes into `ContinuumManifest.json`'s `islands[]` per island: the pin keys
  stay EXACTLY `name/maxBytes/maxGzipBytes` — the schema `WebUIBudgetPlugin`
  already reads (one budget path — I5; no silent fall-back to the global
  ceiling). the NEW `raw/gz/sha/url` keys sit ALONGSIDE the pins, additive +
  versioned (the manifest route's exemption-register rule: version bump, no key
  removals); they never replace the pin — the red-team fold.
- `budget:` becomes tightening-only: a declared pin below the measured auto-pin
  is the error; non-empty `imports:` auto-defaults the budget and the
  remembered rule retires. the diagnostic change lives in the **macro**
  (`WebUIContinuumMacro`, lane D §2.3), which needs the measured row exposed —
  handoff to D at i1.
- the manifest emission (currently the `generate` verb's
  `ContinuumEngineManifest+Generated.swift` → served `/ui/continuum-manifest.json`)
  and the autobuild's measured rows must MERGE in one payload; design keeps the
  generate path authoritative for the allowlist/union and merges islands[] from
  the work-dir manifest at serve-emission time. pin stays green because the
  route is on the register (additive-only change at the version bump).

### handoffs (this wave)

- to C (DX-1, W2): `IslandRuntime` must absorb the reactor-shell boilerplate the
  demo's FeedIsland main still carries (utf8Decode/writeFrame/buffer discipline
  — the same block the probe hand-copies, now shown to be consumer-visible); the
  scaffold template (B, W2) emits the 3-line form only when it lands.
- to D (W2): the measured-row exposure for the macro-side tightening diagnostic
  (§2.3) — B exposes `maxBytes/raw/gz/sha` per island in the work-dir manifest;
  D consumes for the `imports:→budget` retirement.
- to B-W2 (self): the gorilla in the room is the map of the plan's §4.5 row:
  `--add-island/--bootstrap` impl, auto-pin impl, W2's artillery on the verb
  surface.
- to E (acceptance, W2): `~/dx-demo` is the home-dir shape the §0.3 acceptance
  run must use (never /tmp — it flatters the sandbox); the serving seam reads
  artifacts from the plugin work dir (lane-E's `WebUIServer` island routes +
  the built-in manifest route should read `designer`-produced assets at i1+,
  decided with the plan's DX-6 row).

---

## CONTINUUM_DX W1 — lane B addendum (measured numbers + the pin's channel finding)

_committed `2c86d84` → this addendum (final green, base `ec1bcbc`)._

### the demo, measured (candidate (b), `designer/gates/dx5-demo.sh --clean`, ~/dx-demo)

| step | wall | evidence |
|---|---|---|
| cold `swift build` (home-dir app, plain, no flags; includes one-time network resolution of the framework's 5 remote deps + host tool build + the app) | **41.7 s** (SwiftPM phase 28.3 s) | 3 islands cross-built (Probe 232878 / Validate 163708 / Feed (consumer) 151895 B, all stripped embedded, valid \0asm) |
| warm `swift build` (no edits) | **2.2 s** (SwiftPM 0.66 s) | **0 cross-build re-runs** — llbuild-declared inputs/outputs skipped the commands |
| edit ONE consumer island source, rebuild | 11.2 s | FeedIsland re-cross-built only; WebUIProbeIsland/WebUIValidateIsland untouched (targeted invalidation) |
| `WEBUI_WASM_SWIFTC=/nonexistent swift build` | fails exit 1 | named `[WebUIAutobuild] cannot cross-build … swiftly toolchain is a one-time machine prerequisite` |
| `WEBUI_ISLAND_NESTED=1 wasm-cross …` | skip | recursion-guard backstop short-circuits, no artifact written |

equivalence anchor: direct swiftc Probe = 232878 B vs the nested `swift build
--swift-sdk …-embedded -c release` 231984 B (i3 record) → **0.4%**; Validate
163708 vs 164921 → **0.7%**. the artifact lands in the plugin work dir (the
sandbox-writable zone; `.build/out/Products/…` is unwritable from a build
command on home dirs — the acceptance app must keep its home-dir shape).

### the pin's channel finding (beyond the red-team's nonce fold)

the red-team's fold (a) mapped the CSP nonce; live-serve at base measured the
showcase page carries **three more per-process channels** the harness must
normalize or that surface can never pin: the hidden `_csrf` input (fresh HMAC
token per process), the RenderContext auto-generated `data-component-id="c<n>"`
counter (shifted per process), and any JSON-Dictionary-serialized attribute
(`data-optimistic`) whose Swift Dictionary key order randomizes per process
(`{html,id}` vs `{id,html}` — the skill's JSON-in-markup hazard, confirmed
live). `node designer/dx-content-pin.mjs --serve` is GREEN at base with all
four channels canonicalized; pages.txt's canonical column reflects the extended
transform (the raw column is untouched — fixtures authentic). the served sheet
is NOT the naive comment-stripped working file (the asset tool's minify is more
aggressive); serve mode asserts served-sheet determinism across processes +
the pinned working-file hash (fixture mode), and W2 may fold the exact
transform if a stricter assertion is wanted.

---

## CONTINUUM_DX W2 — lane B (base `95ba7b7`): DX-5 serving seam, DX-2 scaffold, DX-3 auto-pin, DX-6b server routes

_commits `6ca7431` (DX-3) · `2041634` (DX-6b seam) · `5d0a040` (DX-2 scaffold) · `b22e5aa` (bench lease retire). this section is the W2 doc contribution (fragments → b-docs, never the shared docs)._

### DX-3 auto-pin (commit `6ca7431`) — measured rows become the budget

- `WebUIContinuumTool measure` (new verb): scans the WebUIAutobuildPlugin work dir for the cross-built `<Product>.wasm` artifacts and writes the measured per-island rows into the work-dir `ContinuumManifest.json` islands[]:
  - pin keys stay EXACTLY `name/maxBytes/maxGzipBytes` — the schema `WebUIBudgetPlugin` reads (one budget path, I5; no silent fall-back to the global ceiling).
  - NEW `raw/gz/sha/url` sit ALONGSIDE the pins (additive, version 2) — never replacing them (the red-team fold).
  - `maxBytes = ceil(raw × 1.05)`; `maxGzipBytes = ceil(gz × 1.05)`; `sha` = sha256 of the STRIPPED artifact via `WebUIBuild.sha256Hex` (made public — the rawdog-sha path, one sha implementation for every build-side consumer).
- the plugin emits `measure` as its OWN build command: inputFiles = the island artifacts, outputFiles = the work-dir manifest — so llbuild orders it after every cross-build, skips it warm, and there is no shared-file race.
- `WebUIBudgetPlugin` now reads the autobuild work-dir manifest too (via the same plugin-outputs walk + a `--autobuild-manifest` override for probes) and enforces the TIGHTEST of declared-vs-measured per FIELD (tightening-only: a declared pin can only lower the auto-pin, never loosen it; the macro-side diagnostic for a wasted looser declaration is lane D's).
- `b-budget-pins.mjs` grew 4 → 10 checks: measured breach + both tightening directions.

### DX-6b + the serving seam (commit `2041634`)

- `WebUIServerConfig.islandWorkDirectory: URL?` (default nil). nil = every reference host's byte-identical behavior (no island routes; absent seam, the manifest route does not exist — the content pin stays green, both fixture and serve modes verified). set = WebUIServer serves:
  - `/__assets/webui-<name>.wasm` reading the autobuild work-dir artifact, name matched by the same case-insensitive containment the budget plugin uses — the existing URL convention is preserved (`webui-validate.wasm` <-> `WebUIValidateIsland.wasm`, `webui-feed.wasm` <-> `FeedIsland.wasm`); absent artifact = 404 = the engine's degrade path. ([DX-5 b-docs:601-603] artifact lands in the plugin work dir — `.build/out/Products/…` is unwritable from a build command on home dirs.)
  - `/ui/continuum-manifest.json` = the MERGED payload: the generate path stays authoritative for allowlist/union/components; the DX-3 measured islands[] are spliced into the islands slot with the additive version bump 1 → 2 (the manifest route's exemption-register rule). work-dir manifest absent/empty = the generated slice byte-verbatim.
- `dx5-demo.sh` grew step F: the home-dir app's DemoApp is now a real WebUIServer host (a `WebUIIsland("feed")` region + the seam config) and the runner asserts the served page renders the island region, `/__assets/webui-feed.wasm` returns the work-dir artifact byte-for-byte (valid wasm), and `/ui/continuum-manifest.json` carries the generate path + 3 measured islands at version 2 — all with ZERO manual verbs (plain `swift build` + `swift run`).
- 3 new `WebUIServerSeamsTests`: island routes from a scratch work dir (`webui-feed`/`webui-validate`/404 ghost), byte-identity without the seam (registered-manifest case), and an empty work dir keeping the generated slice verbatim.

### DX-2 scaffold (commit `5d0a040`)

- `WebUIContinuumTool scaffold` verb + `Plugins/WebUIScaffoldPlugin` (command plugin, `writeToPackageDirectory`, port-free):
  - `--add-island <Name>` — appends the two Package entries (product + executableTarget) beside their SIBLING blocks (append-only line-start anchors; refuses a manifest it cannot anchor on, never partially patches) and generates `Sources/<Name>/main.swift` — the W2 three-line RUNTIME form (lane-C landed): inert `@main` stub + `webui_island_bind` shim calling `IslandRuntime<<Type>.<Type>Island>.run()`.
  - **the D-coordination pin**: the generated main names the macro-produced adapter (`<Type>.<Type>Island` — lane D's expansion emits `struct FeedIsland` nested in `extension Feed`). the exact string `IslandRuntime<Feed.FeedIsland>.run()` is asserted in BOTH `WebUIContinuumToolTests` and lane D's expansion suite, so a rename breaks both loudly. `--print` previews without writing; a second island onward is idempotent (regenerates the main, appends nothing).
  - `--bootstrap --name <App> --framework <path>` — the existing-app path: inserts the once-per-app INERT continuum block (framework path dep + `WebUIAutobuildPlugin` on the app target), idempotent; refuses unanchorable manifests.
- `designer/gates/scaffold-demo.sh` proves the whole flow on a home-dir scratch app: bootstrap → add-island → the generated main compiles for HOST (`swift build` — which also cross-builds the island + writes the DX-3 manifest via the autobuild plugin, zero manual verbs) AND WASM (`wasm-cross`, 132171 B stripped embedded, valid \0asm).
- `WebUIContinuumToolTests` (7): adapter pin, generated header/form, --print is a dry run, append-only add, idempotent add, bootstrap insert + idempotence, unanchorable refusal.

### bench lease retire (commit `b22e5aa`)

- `Sources/WebUIBench/main.swift` (lane-B owned): the pre-DX-7d server-adapter string-replace that injected `data-webui-lease="viewport"` is retired — the Viewport COMPONENT has emitted it natively since DX-7d, so the replace left the attribute TWICE on the served page. the bench now serves the component's bytes verbatim (d-docs:466, d-to-e:54). d3 gate 14/14 still green.

### gates (exact, W2)

```
swift build                                                   -> Build complete
swift test (full)                                             -> 987 tests green (incl. 3 DX-6b seam tests + 7 scaffold tests)
swift package --disable-sandbox plugin budget                -> budget: PASS (frame; measured auto-pins enforce on the consumer)
node designer/probes/b-budget-pins.mjs                        -> 10/10 PASS
node designer/probes/b-lint.mjs                               -> 8/8 PASS
node designer/d3-gate.mjs                                     -> D3 GATE PASS 14/14
node designer/dx-content-pin.mjs                              -> clean (fixture)
node designer/dx-content-pin.mjs --serve                      -> clean (live, byte-identical at base)
bash designer/gates/dx5-demo.sh --clean                       -> DX5DEMO PASS incl. seam step F
bash designer/gates/scaffold-demo.sh --clean                  -> SCAFFOLDDEMO PASS (host + wasm)
```

### measured numbers (this wave)

- dx5-demo seam step F: 3 islands cross-built into the work dir, served byte-for-byte at `/__assets/webui-feed.wasm`; merged manifest version 2 with 3 measured rows.
- scaffold-demo: Feed 132171 B stripped embedded, valid wasm; host build compiles natively; wasm-cross cold ~40 s.
