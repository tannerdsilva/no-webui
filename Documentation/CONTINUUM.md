# CONTINUUM — the engine ⇄ DOM ⇄ wasm seam

_status: living reference — grown through the desktop-grade build (d0–d4),
2026-10-03. the canonical record of the seam's wire contracts, the placement
ladder, the generated surfaces, and the gates. folded at integration from the
per-lane design digests in `continuum-notes/` (b/e/c/d-docs + the contract
notes); the plan of record is `.hermes/plans/2026-10-02_231218-DESKTOP_GRADE.md`._

## 0. the ladder

an interaction's work executes at one of four placements; each degrades to the
one below, and no page ever requires the rungs above the server.

| placement | state lives in | rendering path | typical work | degrade |
|---|---|---|---|---|
| server (default) | the host (authority) | ssr html + fragment ops | everything | — (it *is* the degrade) |
| engine | engine-local, leased | dom ops applied by the engine | windowing, echo, chrome motion | server path |
| island | wasm state, snapshot/patched | op stream (steady) / region html (mount) | hot lists, grids, editors | engine → server |
| island surface *(deferred)* | wasm state | canvas | extreme density — only if a bench forces it | island → engine → server |

three typed seams carry the work: `FragmentOp` (server → engine), `HotOp`
(island → engine), host imports + events (engine ⇄ island).

## 1. the fragment seam (server → engine)

### 1.1 the op vocabulary

`FragmentOp` is six ops, additive over the original `replace` (absent `op` on
the wire stays `replace` — pinned). swift constructors live beside the
precedent in `Sources/WebUICore/WebSocketProtocol.swift`.

| op | wire (json inside `fragments[]`) | meaning | carries markup? | optimistic |
|---|---|---|---|---|
| `replace` | `{"id":"x","html":"…"}` | swap subtree | yes — sanitized | allowed (armed) |
| `append` | `{"id":"x","op":"append","html":"…","before":"child"?}` | insert child (end, or before anchor) | yes — sanitized | allowed |
| `text` | `{"id":"x","op":"text","text":"…"}` | write textContent (characterData in steady state) | no | forbidden v1 (skip + warn once) |
| `remove` | `{"id":"x","op":"remove"}` | delete `#x` | no | forbidden v1 |
| `attr` | `{"id":"x","op":"attr","name":"…","value":"…"}` | set ONE attribute | attribute value only | forbidden v1 |
| `move` | `{"id":"x","op":"move","before":"y"?}` | reorder within parent | no | forbidden v1 |

engine apply rules (`applyFragments`, `webui-engine.js`): `remove` uses a real
`element.remove()` (the empty-fragment-removes-element branch stays
`replace`-only — pinned); `move` is a reorder of the existing node, never a
re-insert; `attr` validates the name against the allowlist then
`setAttribute` (DOM escaping); unknown op / unknown attr name / forbidden
optimistic op → skip + warn once.

### 1.2 the coalescer policy

1. queued application: fragments enqueue and flush as one batch.
2. last-write-wins per target: a later non-append, non-remove op for an id
   collapses onto the newest queued entry for that id (scan from the tail,
   never across a queued `remove`).
3. `remove` never coalesces — a deletion always executes, and no later op may
   swallow a queued `remove`.
4. `attr`/`move` collapse to newest per target; `append` is never reordered
   relative to ops on other targets (array order is semantic).
5. never-animate hot ops: view transitions only ever animate plain `replace`.

probe: `designer/probes/e-ops.mjs` — 50 mixed ops → exact applied counts.

### 1.3 the attr allowlist

`attr` names are allowlisted: `class`, `aria-*`, `data-*`, plus whatever the
generated inventory claims. url-bearing attributes (`href`, `src`, `style`)
and `on*` handlers stay out of the hot plane by construction. the engine boots
with a conservative static seed and swaps it for the generated slice when the
host serves `/ui/continuum-manifest.json` (§5.2): exact entries replace exact,
entries ending `*` or `-` become prefixes; a missing or malformed manifest
falls back to the seed silently. probe: `designer/probes/e-manifest.mjs`.

### 1.4 engine-local echo (the first lease)

contract attribute `data-webui-echo="<id>"` on an input: on `input`, the engine
writes the element's value into `#<id>`'s text in the same turn — locally,
zero websocket traffic. the authoritative patch always wins: a `text` op or a
`replace` for the echo target overwrites the local overlay and clears it. a
component-wired echo source still sends its event at the debounce edge
(300 ms trailing / 1,000 ms max-wait — unchanged). probe:
`designer/probes/e-echo.mjs` (updates per keystroke; 0 ws frames during the
typing window, counted from outside; authoritative wins).

## 2. the island seam (engine ⇄ wasm)

### 2.1 the region contract

a page declares an island region as an element carrying `data-webui-island`
(name) — the engine lazy-fetches the matching content-addressed `.wasm`,
instantiates it, calls `webui_render_region` (mount html; sanitized once at
the boundary) and marks `data-webui-island-state` (`mounted` / `unmapped`).
a missing artifact (404) degrades to `unmapped`; the page stays
server-rendered and the engine instance stays alive in every failure path.

### 2.2 host imports (typed, keyed by function name)

`buildImports` keys on the import's function name (module namespace agnostic);
the known set:

| import | engine behavior |
|---|---|
| `webui_log(ptr, len)` | `console.log('[island:<name>] ' + utf8(ptr,len))` |
| `webui_now_ms() -> f64` | `performance.now()` (fallback `Date.now()`) |
| `webui_raf(callback_index) -> u32` | engine-owned rAF registry; on each frame calls the island export `webui_frame_tick(idx)` then drains |
| `webui_store_get(ptr, len) -> i32` | read key → `localStorage`; writes `[u32le len][value]` at the island's `webui_frame_ptr()` and returns that pointer; `0` when missing |
| `webui_store_set(kp, kl, vp, vl)` | key + value, typed per the two (ptr,len) pairs |
| `webui_surface() -> u32` | `0` (declared, unimplemented — island degrades to region output) |

an unknown `webui_*` import **throws** (t2.6 defense-in-depth — the build-time
capability lint catches it first, §5.3); other namespaces (wasi) keep the
`() -> 0` stub. the six capability *types* live in `WebUISharedCore`
(`HostCapability` + `FrameSchedule`/`InputSubscription`/`SurfaceAcquisition`/
`StatePersistence`/`ClockCapability`/`LogCapability`). `webui_frame_tick` and
`store_get|set` are conventions no current island exercises (the probe imports
nothing) — they exist for future islands and are verified against the frozen
table.

### 2.3 events in

the region element carries an additive descriptor
`data-webui-island-events='["keydown","click"]'` (JSON array). the engine
delivers delegated events that bubble inside the region and are in that list
to `webui_on_event(ptr, len)` with the payload the server sees:
`{"type": …, "key": …, "data": …}` v1. keyboard kinds normalize to
`type:"key"`; clicks carry `key` = the nearest id-bearing element within the
region; `focusin`/`focusout` normalize to `focus`/`blur`. subscribed events
are **island-owned** — no server round-trip, and the legacy
`data-island-input` full-region re-render is skipped for subscribed regions.
the island maps payload → typed action itself (decoder-side mapping; natively
tested).

### 2.4 op stream out

steady-state mutations come back through the frame buffer as **record v1**;
`HotOpCodec` (`WebUISharedCore`) is the encoder, the engine is the decoder.

| field | bytes | endian | notes |
|---|---|---|---|
| version | u8 | — | always `1` |
| opcode | u8 | — | 1 text · 2 attr · 3 insert · 4 remove · 5 move |
| id len | u16 | little | utf-8 byte count |
| id | n | — | the element the op targets (insert: the **parent**; the engine allocates the new element's id on apply) |
| payload | opcode-specific | — | text: `u32 len` + bytes · attr: `u16 name` + `u32 value` · insert: `u16 before` (`0xffff` = end) + `u32 html` · remove: — · move: `u16 before` |

rules: multi-byte ints little-endian; `0xffff` is a sentinel only in the
optional `before` position; invalid utf-8 decodes to U+FFFD (never a trap);
reserved versions/opcodes reject. record ints are input-bounded (1<<16), a
single record always fits the 1<<18 frame buffer.

**the drain contract.** `webui_take_ops() -> u32` returns the next batch's
byte length in the frame buffer (`0` = empty); batches are whole records
back-to-back, never split; the engine drains until `0`, copying each batch out
of wasm memory before the next call. a batch over 262,144 B or a malformed
record stops the drain with one warning. `webui_on_event` queues — it never
serves ops; mount (`webui_render_region`) produces no ops.

trust: `text`/`attr`/`remove`/`move` carry no markup (attribute names
allowlisted, values escaped); `insert` carries html and is sanitized **once**
at the boundary — steady state is never re-scrubbed.

### 2.5 the state channel

`webui_state_save() -> ptr` (value at ptr; length via `webui_frame_len()`) and
`webui_state_restore(ptr, len)` (the engine writes the bytes into the input
buffer). the engine keys a save map by `island name + region element id`;
saves fire before a fragment `replace` of a region root and on ws reconnect;
restore fires on every remount (initial mount and post-replace reconcile). a
malformed restore keeps the live state (never wipes). the probe proves a
counter + keyed list survive remounts.

### 2.6 artifacts and budget

| artifact | size (stripped) | declared budget |
|---|---|---|
| `WebUIValidateIsland.wasm` | 164,921 B | global ceiling 240,000 |
| `WebUIProbeIsland.wasm` | 231,984 B / 99,360 gz | `IslandBudget(240_000, 105_000)` |

islands are cross-built by `swift package --disable-sandbox plugin wasm-island
[--product …]` into `.build/out/Products/Release-webassembly-wasm32/`
(embedded tier via the swiftly-hosted 6.4 toolchain; scalar-clean leaf —
unicodeScalars only, no Foundation, no `Character(…)` by-value, no
`String(decoding:as:)`). `IslandBudget` pins are enforced by
`WebUIBudgetPlugin`: per-island pins come from `@HotView(…, budget:)` markers
via `ContinuumManifest.json`; unmatched artifacts ride the global ceiling.

### 2.7 the author surface

one declaration produces the server path, the island adapter, the codec
stubs, and the registry entries.

- `@HotView("name", imports: [ClockCapability.self], budget: IslandBudget(…))`
  on a struct with `State`/`Action`/`reduce`: emits
  `static let continuumDescriptor` (name/grants/budget/className),
  `struct <Type>Island: ContinuumIsland` (aliases, `reduce` forwarding, the
  `<name>_encode`/`<name>_decode` codec stubs), peer-emitted global
  `@_expose(wasm, …)` shims, and the `ContinuumServerPath` conformance.
- `@HotClass("a","b")` → `static let continuumClasses: [String]` (claims the
  classes for the inventory; a sibling `@HotClass` feeds the descriptor's
  className).
- the hot body is `@HotBuilder func render(state:) -> HotTree`: a restricted
  builder whose `buildBlock` accepts only `HotPrimitive`-convertible views —
  the vocabulary is a **type-checker guarantee**, not a lint. v1 primitives:
  `Hot.Text`, `Hot.Container`, `Hot.Spacer`, `Hot.KeyedList` (keyed row
  reconcile), `Hot.AttrWrapper`/`HotTree.attended` (the component-promotion
  carrier). `HotTree.hotOps(previous:)` is a survivors-order diff (not a
  minimal LCS — pinned).
- diagnostics (file/line + fix hint, never `fatalError`): missing
  `State`/`Action`; render not `@HotBuilder`; `imports:` naming a
  non-`HostCapability` type; non-empty `imports:` without `budget:`; a
  non-hot view in a hot body (the builder's unavailable-overload message).
- placement is load-bearing: macro declarations live in `WebUI`; the
  implementation is a host-only compiler plugin; the seam vocabulary lives in
  `WebUISharedCore` (wasm-visible). `@_expose(wasm,…)` accepts **globals
  only** — the shims are peer-emitted global functions named
  `_continuumEncode<Type>`; the ABI string stays `<name>_encode`.
- the hand-written equivalent: `WebUIIslandCore.ProbeIsland` is a
  hand-written `ContinuumIsland` (typed state, pure `reduce`, natively
  tested) — the anti-shackle rule's living fixture, and the parity suite's
  island side.

### 2.8 placement hints and delivery

`.lease(.viewport)` / `.lease(.echo, echoTo:)` are inert by design (no
markup, no bytes — the hint lives in the type). delivery wiring:

- `.lease(.echo, echoTo: "..")` → `data-webui-echo` emission (§1.4); a bare
  `.lease(.echo)` stays byte-identical.
- `InputParity` descriptor: `data-webui-input='["key","composition"]'` (the
  sibling spell of the island-events descriptor) + `onKeyEvent` +
  `compositionForwarded()` (ime channel). the delivery surface rides
  `WebUISharedCore`'s typed `KeyEvent`/`ModifierSet`/`Key` (the wave-3 twins
  were deleted in polish); `KeyEvent.islandPayloadV1` is the transport
  mapping `{"type":"key","key":<Key.identifier>}` — `data` omitted on the
  key channel, `modifiers`/`isRepeat` pre-seed v2, and `event.key == " "`
  parses to `.printable(" ")` (the recorded space friction). probe:
  `designer/probes/d-transport.mjs`. wiring `data-webui-input` into the
  engine's island delivery is the next slice.

## 3. windowing (t3.3)

`Viewport<ID, Item>` (`WebUIDesignSystemCore/Viewport.swift`) renders the DOM
contract the engine windows by; the engine's `createWindowManager` is the
client-side twin.

| signal | meaning |
|---|---|
| `[data-webui-viewport]` | the windowed container (also carries `data-webui-lease="viewport"` when the engine path is wanted) |
| `data-viewport-total` / `-rowsize` / `-overscan` | pool size, row height (52 = 3.25rem), overscan factor (2×) |
| `data-viewport-slice="first..last"` | the server-rendered slice bounds |
| `data-viewport-safe` | the safe page size (10,000 — the d0-measured full-render ceiling; beyond it the server degrades to pagination) |
| row `id="<id>-r<i>"` + `data-key` | positional slot + keyed identity (`data-key` is the identity channel both placements share) |
| `.viewport-pad` | height pads for sliced server renders |

engine semantics: pool = direct children (detached); attached = viewport ±
overscan rows positioned absolutely at `i × rowHeight`; an injected spacer
holds the full height; re-windowing is engine-local on scroll (both
document-flow and self-scrolling containers); a whole-container replace keeps
scroll position and reforms the same visible row; only entering/leaving rows
are inserted/removed per scroll.

measured (e-windowed, 10k rows): rAF p95 **35.8 ms** (= this host's 30 Hz
display floor; the full-render control is 62 ms), engine scroll-work p95
**2.2–2.3 ms**, window-only mutation census, attached rows 45–71 (≤ 90),
memory flat over 60 s.

## 4. shared kernels + parity (d4)

`WebUISharedCore/Kernels/`: `Normalizer`/`Lexer`, `NumberAggregator` +
`Aggregate`, `KeyedSorter.stableSorted` (stable keyed sort), `Filter` (+
paginate), `NumberFormat` (hand-rolled: integer/grouped/fixed/percent),
`CivilDate` (Hinnant civil algorithms) — pure, generic, foundation-free,
scalar-clean.

**parity by construction:** one frozen corpus (`KernelCorpus`) runs the same
swift natively and inside the probe island (`webui_run_corpus` export serves
FNV-1a hashes of every canonical result); `designer/probes/c-parity.mjs`
compares sets — equal hashes = the gate (25/25). portability contracts:
`Int` is 32-bit on wasm32, so formatting entry points are `Int64`-explicit;
canonical strings never interpolate raw `Double`s (they pass through
`NumberFormat.fixed`).

## 5. generated surfaces

### 5.1 `Continuum+Generated.swift` (into the WebUI target, every build)

| member | consumer |
|---|---|
| `ContinuumClassInventory.components` | per-component claimed classes (literal `class="…"` + `@HotClass` markers) |
| `.union` | the orphan ratchet's static half + css reachability |
| `.attributeAllowlist` | the engine's `attr` plane + validators |
| `.unclaimedLiterals` | the warn-only lint (the error level stays the orphan ratchet) |

scanner semantics: components are `public struct WebUI…` at brace depth 0 in
`Sources/WebUIDesignSystemCore/*.swift`; interpolated class values are out of
the literal scan by design (the ratchet owns rendered coverage). build line:
`[WebUIContinuumPlugin] inventory: N components, M classes, K unclaimed (warn)`.

### 5.2 `ContinuumEngineManifest` (the served engine slice)

a `WebUIShippedAsset` (same emit machinery as the css/js: one sha256 stamp,
one gzip variant, prose-gated) whose payload is the `continuum-engine-slice`
json (`attributeAllowlist`, `components`, `union`). a host registers it:

```swift
WebUIServerConfig(
    host: "0.0.0.0", port: port,
    assets: [
        WebUIAsset(ContinuumEngineManifest.self, path: "/ui/continuum-manifest.json").registration
    ]
)
```

the engine fetches `/ui/continuum-manifest.json` at boot and replaces its attr
seed (§1.3); a 404/malformed response keeps the seed silently. reference hosts
register it (example, showcase, blocks, smoke); a real host should too.

### 5.3 the capability lint (t2.6)

`WebUIContinuumTool lint` reads `@HotView` markers' `imports:` and compares
against the host grant list (`ContinuumGrants` constant → `--grants` →
framework default of all six). a mismatch is a **build error**:

```
island "feed" imports "surface_acquire" — not granted by the host manifest (add it to ContinuumGrants or drop the import)
```

the plugin runs the lint as a second build step and writes a
`Capabilities.ok` stamp on success (cached-green, fail-red). accepted
`imports:` spellings: array of `.self` types, single string, dot-case, empty.

## 6. probes and gates

| probe | proves |
|---|---|
| `designer/probes/e-ops.mjs` | op apply + coalescer counts |
| `e-echo.mjs` | engine-local echo, 0 frames while typing |
| `e-island-decoder.mjs` | record-v1 decode + drain (pure) |
| `e-island-wasm.mjs` | a hand-assembled synthetic island (test fixture) |
| `e-island-e2e.mjs` / `e-island-e2e-real.mjs` | the seam live: synthetic / the real probe artifact |
| `e-windowed.mjs` | windowing: scroll-work p95, census, memory, anchoring |
| `e-manifest.mjs` | the served allowlist slice (replace-not-union) |
| `c-ops.mjs` | the island's ABI byte-exact in node (no engine) |
| `c-parity.mjs` | native↔island equal hashes |
| `d-viewport.mjs` | source ⇄ sheet ⇄ handoff contract |
| `d-transport.mjs` | the KeyEvent → `{type,key,data}` v1 transport rule (parses the real identifier table) |
| `b-lint.mjs` / `b-budget-pins.mjs` | grants lint / per-island pins |
| `b-interaction-smoke.mjs` / `b-windowed-smoke.mjs` | bench interactions |
| `designer/continuum-bench.mjs` | the six §3 recipes (d0 harness) |
| `designer/d3-gate.mjs` | the d3 gate: echo budget, degrade, scroll (engine-local fixture, floor-based criterion) |
| `designer/gates/b-probe-fold.mjs` | the fold-in runner the canonical gates invoke |

the in-repo ladder: `plugin wasm-island` (fresh clones) → `swift build` →
`swift test` → `plugin smoke` (folds b-lint + b-interaction; 19/19 pin holds)
→ `plugin fullstack-smoke` (folds b-windowed; 22/22 pin holds) →
`plugin budget` → `node designer/browser-smoke.mjs` (folds the d3 gate as its
agg; 46/46) → the wave probes. canonical ports
(9090/9091/9092/9123/9130) are for the orchestrator; lanes use their blocks.

## 7. decisions of record + open items

decisions (full rationale in `continuum-notes/`): record ints little-endian;
insert's id slot = parent; `0xffff` sentinel reuse; attr payload
length-prefixed both fields; `Codable` gated `#if !hasFeature(Embedded)`;
drain = whole-record batches (the i1 freeze); `HotView` does not inherit
`View`; `Int64`-explicit formatting; `ContinuumDescriptor` stays host-side in
WebUI; the engine budget's four deliberate re-pins (the plugin comment holds
the trip history).

open items: the d3 gate is
**closed** (14/14 — engine-local fixture rendering `Viewport`, criterion
re-based onto engine scroll-work p95 ≤ 20 ms per the measured 30 Hz host
floor; a 60 Hz host run can re-enable the absolute rAF assertion); align the
component's `data-webui-viewport` discovery attribute with the lease
attribute the engine consumes; wire `data-webui-input` into the engine's
island delivery; v2 key-channel `modifiers`/`isRepeat`; row-level ops for
detached window rows; a server-side window-slice fetch path; `@HotView`
consumer-page wiring; `AttrWrapper` dynamic attr ops; d5 (durable local state
/ live documents) and d6 (webview shell) remain separable future arcs.