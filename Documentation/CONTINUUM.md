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

**the region view (`WebUIIsland`, dx-4a).** server-side a region is declared
with the `WebUIIsland(id:name:args:)` view (WebUI); its byte contract is
pinned: attributes in order `id` → `data-webui-island` → `data-webui-args`;
args single-quoted; the args payload is the declaration-ordered typed
`WebUIIslandArgs` (a hand-rolled ordered-pair value, never a `[String: Any]`
/ `JSONSerialization` — `int` renders `4`, never `4.0`, and `'`/`&` in values
become `&#39;`/`&amp;` so the single-quoted attribute round-trips the
browser's entity decoding + the engine's `JSON.parse`, identity on captured
bytes). the region `id` is explicit with an `island-<name>` derived default
(`WebUIIsland("feed", args:)` derives; no derivation rule reproduces every
captured id — the designated `id:name:args:` form pins the full contract);
`args` defaults to `.empty` (`{}`). byte-identity is proven against the
committed fixture (`Tests/WebUITests/Fixtures/dx-w0-island-regions.html`)
and by spelling out both captured lines as raw-string assertions. a
pre-emitted region needs an event descriptor (`data-webui-island-events`,
§2.3) to receive events — mount alone delivers none. the reference host
(smoke) renders its validate + never-built regions with this view,
byte-identical to the hand-written markup it replaced (the smoke fixture pin
and `content-pin` hold).

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

decode-side (dx-w3): `HotOpCodec.decodeBatch` decodes a back-to-back record-v1
stream to ops — the exact inverse of `encodeBatch`, sharing the
`decodeRecord` core (the strict single-record trailing-bytes guard stays in
`decode`). the runtime exposes two READ accessors on the bound instance:
`IslandRuntime<I>.encodedState()` (the retained-state snapshot = the exact
`webui_state_save` payload) and `.decodePendingOps()` (the currently-pending
records decoded back into leaf effects). `decodePendingOps` reads, never
drains — `webui_take_ops` stays the only queue consumer, so a decode accessor
can never double-apply.

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
| `WebUIProbeIsland.wasm` | 233,952 B / 100,469 gz | `IslandBudget(240_000, 105_000)` |
| `WebUIValidateIsland.wasm` | 176,669 B / 81,205 gz | `IslandBudget(185_503, 85_265)` |

both islands run on the `IslandRuntime` slice (§2.9); these are the
runtime-current anchors. the probe's 233,952 B is the byte-identity
regression backstop — "byte identity" here means the SIZE and the
section-level layout (the opaque data-section tail re-rolls on any module
edit; chasing full-sha equality is wrong), and it moves only under an
arc-accounted change. cross-builds happen automatically inside a plain
`swift build` (`WebUIAutobuildPlugin`, §5.4); `plugin wasm-island` is the
in-repo ladder verb (into `.build/out/Products/Release-webassembly-wasm32/`;
embedded tier via the swiftly-hosted 6.4 toolchain; scalar-clean leaf —
unicodeScalars only, no Foundation).

budget enforcement (`WebUIBudgetPlugin`) reads **two** manifests and enforces
the TIGHTEST per field (one budget path): the declared-pins source and the
autobuild work-dir manifest with the DX-3 measured `islands[]` rows §5.2.
declared `budget:` is tightening-only — positive literal pins only; a
declared `maxBytes: 0` is the auto spelling (auto-defaulted by non-empty
`imports:`), refused as a pin. `BudgetDriftTests` (swift-testing,
`.enabled(if:)` on artifact presence; gz via `gzip -n -9 -c` — the budget
plugin's own tool) asserts each declared `IslandBudget` dimension lives in
`[measured, ceil(measured × 1.05)]` per field and names the exact re-pin on
drift — the upper bound IS the DX-3 auto-pin convention, so a tighter-than-
auto declaration is legal tightening. the measurements that matter are
assert-vs-measured (never a generated constant — the constant compiles into
the artifact it pins). unmatched artifacts ride the global ceiling (240,000
today). in the in-repo ladder `plugin wasm-island` (both products) arms the
drift check before `swift test`; `plugin budget` is the enforcement gate.
verify-path numbers (scaffold-demo, DX-8): Feed 132,171 B, validate 175,525 B,
probe 235,982 B stripped embedded — budget rows PASS (ceil × 1.05).

### 2.7 the author surface

one declaration produces the server path, the island adapter, the codec
stubs, and the registry entries.

- `@HotView("name", imports: [ClockCapability.self], budget: IslandBudget(…))`
  on a struct with `State`/`Action`/`reduce`: emits
  `static let continuumDescriptor` (name/grants/budget/className),
  `struct <Type>Island: ContinuumIsland` (aliases, `reduce` forwarding, the
  `<name>_encode`/`<name>_decode` codec entry points), peer-emitted global
  `@_expose(wasm, …)` shims, and the `ContinuumServerPath` conformance; and —
  the DX-9 half — walks the `@HotBuilder` body and emits
  `static let elementIDs: Set<ElementID>` (the literal `id:` arguments,
  sorted + deduped, ALWAYS present — `[]` when the body spells none, the
  strict default a check build fails loudly on; over-collection is
  permissive-safe; interpolated/dynamic ids defer to the runtime dev check,
  §2.9). an author-declared `elementIDs` collides → build error with the fix
  hint.
- **the strict marker form.** `@HotView("<name>")` is a strict ASCII single
  token `[A-Za-z_][A-Za-z0-9_-]*` (the scan's first-quoted-token form + wasm
  export suffix + URL segment + manifest key). duplicate attributes and
  author-declared `continuumDescriptor` / `<Type>Island` collisions are build
  errors with fix hints, never `fatalError`.
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
  non-`HostCapability` type; an elementIDs collision (above); a non-hot view
  in a hot body (the builder's unavailable-overload message). the old
  "non-empty `imports:` without `budget:`" refusal is **deleted** —
  non-empty `imports:` auto-defaults the budget (the auto/unset sentinel
  `IslandBudget(maxBytes: 0, maxGzipBytes: nil)`); a declared `budget:` must
  be a POSITIVE literal pin (`maxBytes: 0` is the auto spelling misread as a
  pin, and non-literal pins are refused).
- placement is load-bearing: macro declarations live in `WebUI`; the
  implementation is a host-only compiler plugin; the seam vocabulary lives in
  `WebUISharedCore` (wasm-visible). `@_expose(wasm,…)` accepts **globals
  only** — the shims are peer-emitted global functions named
  `_continuumEncode<Type>`; the ABI string stays `<name>_encode`.
- the hand-written equivalent: `WebUIIslandCore.ProbeIsland` is a
  hand-written `ContinuumIsland` (typed state, pure `reduce`, natively
  tested) — the anti-shackle rule's living fixture, and the parity suite's
  island side.
- **shipped (dx-7d):** the `Viewport` COMPONENT emits the engine's lease
  `data-webui-lease="viewport"` (immediately after the `data-webui-viewport`
  discovery marker); the `.lease(.viewport)` MODIFIER stays inert and
  byte-identical — emission lives in the component, never the modifier.

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
  `designer/probes/d-transport.mjs`.
- **dx-8e — `data-webui-input` delivery wired.** the engine's
  `islandRegionSubscribed`/`deliverIslandEvent` accept the descriptor as a
  sibling of `data-webui-island-events` (same JSON-array parser; union of
  both). channel table: `key` = `keydown` **only** (keypress is legacy,
  keyup double-counts); `composition` = `compositionstart/update/end`
  (island-only via a `handleEvent` short-circuit — zero new per-page network
  for non-opted pages); `selection`/`clipboard`/`undo` = subscribed, DOM
  events not yet delegated. the `key` payload also carries the modifier
  booleans (`ctrlKey`/`shiftKey`/`altKey`/`metaKey`, booleans-as-strings) —
  informational, the v2 pre-seed. the DOM spacebar stays the single space
  scalar `" "` (the wire form of `Key.printable(" ")`); `"Spacebar"` is
  normalized to it, and `" "` is deliberately NOT normalized to `"Space"`
  (`.space`/`"Space"` will not fire from a real browser). probe:
  `designer/probes/e-input-desc.mjs`.

### 2.9 the island runtime slice (continuum_dx, dx-1/dx-2)

`Sources/WebUIIslandCore/IslandRuntime.swift` owns the ENTIRE wasm export
surface (`webui_input_ptr`/`webui_frame_ptr`/`webui_frame_len` ·
`webui_render_region` · `webui_on_event` · `webui_take_ops` ·
`webui_state_save`/`webui_state_restore`), parameterized by a
`ContinuumIsland`-typed island through `IslandRuntimeSurface` — the four
hooks `decodeEvent`/`regionHTML`/`stateToJSON`/`stateFromJSON` plus the
`IslandEmptyState` init refinement. the concrete island is bound lazily from
the first stateful export call via `webui_island_bind` — a `@_silgen_name`
symbol the island's main defines, one per wasm image (`@_expose(wasm:)`
accepts globals only on this toolchain, so the export surface lives as global
trampolines).

the island main is the slim form (~20 lines): an inert `@main` stub + the
`webui_island_bind` shim (`IslandRuntime<<Type>Island>.run()`) + each EXTRA
export as a one-line global shim through `IslandRuntime.writeExport(...)`.
`IslandRuntimeCore` is buffer-free — methods return exact frame-payload
bytes, the wasm bridge copies them into the physical frame — so one code path
is native-testable and wasm-exact. `reduce` is the runtime's op source
(`onEvent` collects every `.ops` effect; `.save`/`.log` are deferred until a
backend lands). behavior-equivalence is proven twice: the native suites
(`IslandRuntimeTests`, `ValidateIslandRuntimeTests`) drive the SAME
`IslandRuntimeCore<I>` the wasm executes (the exact c-ops.mjs script,
byte-exact batches), and the node probes stay green on the converted
artifacts (c-ops 15/15, c-parity 25/25).

two additive runtime hooks, both probe-neutral (the probe artifact stays
byte-identical — the regression backstop):

- `IslandRuntimeSurface.consumeMountEnvelope(_:state:)` — a protocol
  REQUIREMENT with a no-op default: the runtime decodes the `{name, args}`
  mount envelope and hands it to the island before rendering, so an
  args-derived island can fold it into retained state.
- `IslandRuntime.writeExport(input:_:compute:)` — the lockstep input-driven
  extras entry: reads the raw input buffer, decodes scalar-clean, calls the
  island's compute, writes the payload, returns the frame ptr (empty input →
  0 without touching the frame). `webui_validate` is its first consumer, with
  the hand-written contract preserved byte-exact: input = raw `{value, rules}`
  json; response = `{"ok":<bool>,"message":"<escaped>"}`.

**the id dev check (dx-9).** `-DCONTINUUM_ID_CHECK` (or
`.define("CONTINUUM_ID_CHECK")` in a consumer package) compiles the check
into the runtime: every op an island emits through `webui_on_event` must
target a known element id; unknown → the diagnostic naming the id is written
into the frame buffer and the runtime TRAPS — dev-time failure, never a
silent engine drop. the vocabulary surface is gated requirements on
`IslandRuntimeSurface`: `static var elementIDs: Set<ElementID>` (the literal
targets — the `@HotView` emission, §2.7) + `static func isKnownElementID(_:)`
(runtime-derived families the literal set cannot carry; the default consults
`elementIDs`). an island declaring nothing fails loudly on any op
(fail-closed — a silently-skipped island would hollow the check out).
`ProbeIslandIDs` stays the always-compiled, natively-tested hand-written
fallback. `before` anchors are references, never checked. production builds
compile the check AND its vocabulary out — zero runtime tax (binary-grepped:
no `CONTINUUM_ID_CHECK`/`elementIDs`/`IslandIDCheck` string in the artifact;
the probe stays at its 233,952 B anchor). natively testable via
`swift test -Xswiftc -DCONTINUUM_ID_CHECK` (both modes native-tested), and
check-mode wasm proven end-to-end (c-ops 15/15 + c-parity 4/4 on the check
build).

### 2.10 the ops id vocabulary (continuum_dx, dx-11a)

interactive components carry typed ids the op plane addresses — ONE id
vocabulary, no string math:

| component | id scheme |
|---|---|
| `WebUITable` rows — wired tables only (at least one typed handler) | `<tr id="{id}-r{i}" data-key="{rowId}">` (attribute order id → data-key → class; `data-key` is the SAME `rowId` the controls derive from) |
| sortable table headers | `{id}-sort-{i}` on the `.sort` span INSIDE the `<th>` (pinned there by the smoke gate; the `<th>` itself carries no id) |
| row select / expand controls | `{id}-select-{rowId}` / `{id}-expand-{rowId}` |
| `WebUIPagination` | `{id}-prev/next/page-{n}/rows` |
| `WebUIChart` marks | `{id}-mark-{i}` (sectors/categorical), `{id}-mark-pt` (points), `{id}-mark-{cat}-{series}` (categorical bars) |

static (unwired) tables and charts emit no row ids / `data-key` — their bytes
are untouched (the BEM pins `<tr class="tr--selected">` etc. hold). the wired
rows change the smoke page's served bytes: a registered byte-identity
exception for the `dx-content-pin` harness (page `smoke`, table
`interactive-table`; additive to the row tag only; the 25 `data-component-id`
count is unchanged — no other reference page carries a wired table).

### 2.11 the op-emitting handlers (continuum_dx, dx-11b) — shipped

`ComponentOps` (WebUIDesignSystemCore) turns component events into
`FragmentOp` payloads (`.attr`/`.text` on the §2.10 id vocabulary) instead of
whole-region replaces. id derivation, one spelling: `tableRowID`
(`{id}-r{i}`), `tableSortControlID` (`{id}-sort-{i}`),
`tableSelectControlID` (`{id}-select-{rowId}`), `tableExpandControlID`,
`paginationPageID` (`{id}-page-{n}`), `chartMarkID` (`{id}-mark-{i}`).

- **atomics** — `classOp` / `ariaCheckedOp` / `ariaExpandedOp` /
  `ariaCurrentOp` / `textOp`: the hand-written dictionaries every composed
  helper is pinned against (a host may write these by hand and get identical
  bytes — the anti-shackle).
- **composed event→ops** — `tableRowSelect` (row class + control
  aria-checked), `tableSelectAll` (select-all + every row), `tableSort`
  (header affordance on active + previously-active columns), `tableExpand`
  (row class + aria-expanded), `chartMarkSelect` (toggles
  `chart__mark--selected` onto the host's base classes), `paginationPage`
  (active page class + aria-current; previous reverts).

the contract: every helper returns a REAL op (`op != nil && op != .replace &&
html.isEmpty`) — a handler returning these never triggers a whole-region
replace. boundaries (conservative, recorded): `aria-sort` lives on the
`<th>`, which carries no DX-11a id (the id is on the inner `.sort` span), so
the sort helper patches the pinned span via `attr class` — the visible sort
affordance — NOT `aria-sort` (the th-id re-target is the gate for a true
aria-sort op); structural items (expand detail-row insert, row reorder) stay
out of the attr/text plane — the helpers own the affordance + selection
deltas, the rung the `FragmentOp` plane supports today. the components
themselves are UNTOUCHED — static tables/charts/pagers stay byte-identical;
no new byte exceptions beyond the registered DX-11a row-id one. the
acceptance dogfood's hand-written ops are exactly these dictionaries —
`ComponentOps` is the built-in factory they can now adopt.

## 3. windowing (t3.3)

`Viewport<ID, Item>` (`WebUIDesignSystemCore/Viewport.swift`) renders the DOM
contract the engine windows by; the engine's `createWindowManager` is the
client-side twin.

| signal | meaning |
|---|---|
| `[data-webui-viewport]` / `[data-webui-lease="viewport"]` | the windowed container — the engine accepts EITHER discovery spelling (dx-7e); `Viewport` emits both (the lease first, then the discovery marker) |
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

windowing parameters are read from **both name sets**, declared-value-first
(dx-7e): `data-webui-row-height`/`data-viewport-rowsize` and
`data-webui-overscan`/`data-viewport-overscan`; the first-row `offsetHeight`
fallback (then 24 px) runs only when NEITHER name set is present. the two
overscan spellings read DIFFERENT units (the A1 ruling, binding):
`data-webui-overscan` is ABSOLUTE rows each side; `data-viewport-overscan` is
a FACTOR — `per-side = ceil(vis × (ovF−1)/2)` with `vis = ceil(viewportPx /
rowHeight)` (factor 1 → 0; neither declared → one visible band each side,
≈ 3×visible). probes discriminate at mid-scroll: factor 2 → 12–13 rows,
absolute 2 → 10–11, undeclared → 16–20 (a range admitting both readings
verifies nothing — the ruling).

measured (e-windowed, 10k rows): rAF p95 **35.8 ms** (= this host's 30 Hz
display floor; the full-render control is 62 ms), engine scroll-work p95
**2.2–2.6 ms** (≤ 20 — the budget-bearing row), window-only mutation census
(childList only), attached rows 34–71 (≤ 90), memory flat over 60 s.

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

### 5.2 the served manifest (`/ui/continuum-manifest.json`)

the payload's base shape is a `WebUIShippedAsset` (same emit machinery as the
css/js: one sha256 stamp, one gzip variant, prose-gated) whose
`continuum-engine-slice` json carries `attributeAllowlist`, `components`,
`union` — that is **version 1**. version 2 (additive) adds `islands[]`: one
row per island, pin keys EXACTLY `name/maxBytes/maxGzipBytes` (the
`WebUIBudgetPlugin` schema — one budget path, no fall-back to the global
ceiling) with NEW additive `raw/gz/sha/url` beside them (`sha` = sha256 of
the stripped artifact via `WebUIBuild.sha256Hex`; `maxBytes = ceil(raw ×
1.05)`) — never replacing the pins. a host can register the generated asset:

```swift
WebUIServerConfig(
    host: "0.0.0.0", port: port,
    assets: [
        WebUIAsset(ContinuumEngineManifest.self, path: "/ui/continuum-manifest.json").registration
    ]
)
```

the engine fetches `/ui/continuum-manifest.json` at boot: it replaces its
attr seed (§1.3) and resolves island URLs from the `islands[]` `url` keys with
the name-convention `/__assets/webui-<name>.wasm` fallback (v1 payload / 404)
— chained on the shared manifest promise, so a region mounted before the
manifest lands still resolves the right URL, zero extra requests (dx-6e).

**the DX-6b serving seam.** `WebUIServerConfig.islandWorkDirectory: URL?`
(default nil): set, `WebUIServer` serves the island routes itself —
`/__assets/webui-<name>.wasm` reads the autobuild work-dir artifact
(case-insensitive containment; absent = 404 = the degrade path) — and the
built-in manifest route serves the MERGED payload: the generate path stays
authoritative for allowlist/union/components with the DX-3 measured
`islands[]` spliced in (version 1 → 2, additive only — the route's
exemption-register rule). nil = every reference host's byte-identical
behavior. the DX-3 `measure` verb (`WebUIContinuumTool measure`) is its OWN
llbuild command after all cross-builds (inputFiles = the artifacts,
outputFiles = the work-dir manifest — no shared-file race): it writes the
islands[] rows above; `WebUIBudgetPlugin` reads both manifests and enforces
the TIGHTEST per field (tightening-only, §2.6).

the `dx-content-pin` harness (`designer/dx-content-pin.mjs`, the I1
content-pin) holds every served surface: the manifest route is on the
exemption register (byte-identical at base; a diff fails unless registered-
additive — version bump, additive keys only), `webui-engine.js` is
I3-governed (never a byte fail; the raw+gz delta account is reported), page
migrations (the DX-11a row-id exception §2.10) are byte-identical to the
captured bytes or the migration is wrong, and everything else is byte-pinned
with the four per-process render channels canonicalized (nonce, `_csrf`,
`data-component-id` counter, Dictionary-key-order attributes).

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

### 5.4 islands for consumers — scaffold, verify, zero manual steps

the getting-started path is **zero manual verbs**: a plain `swift build`
cross-builds every island (`WebUIAutobuildPlugin`, a build-tool plugin on the
app target — the once-per-app inert block) and auto-pins its budget (the
`measure` command, §5.2); `swift run` serves it.

- **`WebUIContinuumTool scaffold`** (+ the `WebUIScaffoldPlugin` command
  plugin). `--add-island <Name>` appends the two Package entries (product +
  executableTarget beside their sibling blocks — line-start anchors, refuses a
  manifest it cannot anchor on) and generates `Sources/<Name>/main.swift` —
  the runtime form naming the MACRO-PRODUCED adapter
  (`IslandRuntime<<Type>.<Type>Island>.run()`; the exact string is
  cross-pinned in the tool tests + lane D's expansion suite, so a rename
  breaks both). `--bootstrap --name <App> --framework <path>` inserts the
  once-per-app inert continuum block (framework dependency + the autobuild
  plugin on the app target); afterwards islands need no manifest edits
  (SwiftPM tolerates the undeclared `Sources/<Island>/` dir — the scan
  cross-builds it). `--print` previews the snippet without writing (for teams
  that decline the write permission). idempotent.
- **`WebUIContinuumTool verify`** (+ the `WebUIVerifyPlugin` command plugin) —
  the ONE consumer-facing island-verification verb: **build** (host, into a
  work-dir-owned build root) → **cross-build** (every island via the SAME
  imports-scan the autobuild plugin uses; `--product <Island>` filters) →
  **measure/pin** (the DX-3 rows into the work-dir manifest) → **budget row**
  (`WebUIBudgetPlugin` re-invoked over the work-dir — one enforcement locus,
  no second path). prints a per-stage verdict; any budget breach fails it.
  flags: `--skip-swift-build`, `--no-strip`, `--swiftc`, `--work-dir`
  (default `<pkg>/.build/continuum-verify`), `--product` (repeatable).
  framework home: `swift package --disable-sandbox plugin verify`; a consumer
  app (command plugins are not invocable across the dependency boundary):
  `webui-continuum verify --package-dir . --framework <no-webui path>`.
  belt-and-suspenders by design — the plain build already runs stages 2–3 via
  the autobuild plugin; verify performs every stage explicitly for a package
  without wiring.
- `wasm-island` is an INTERNAL verb (the in-repo ladder + acceptance keep
  calling it); no getting-started path names it. `plugin budget` is the
  enforcement gate.
- re-entrancy note: verify points its nested SwiftPM children at a
  work-dir-owned tmp — the OUTER plugin invocation holds a per-package build
  lock keyed on the package's `.build` path in `$TMPDIR` (not the build
  root), so any nested `swift build`/`plugin budget` on the same package
  deadlocks without the isolation (measured; `--build-path` alone does not
  relocate the lock). no future verb nests SwiftPM without it.
- the appendix-A consumer template + acceptance harness
  (`templates/app/` + `designer/dx-acceptance.mjs`) prove the whole flow on a
  home-dir project (`~/dx-accept`, never /tmp): one `@HotView` struct →
  plain `swift build` cross-builds the feed island in-build → `swift run`
  serves it → the region mounts via the manifest `islands[]` content-
  addressed URL → the DOGFOOD assertion gets attr+text ops back with zero
  whole-region replaces. the template ships a pre-emitted
  `WebUIIsland("feed")` region + the `data-webui-island-events='["click"]'`
  splice and no capability allowlist (nil = permissive).

## 6. probes and gates

| probe | proves |
|---|---|
| `designer/probes/e-ops.mjs` | op apply + coalescer counts |
| `e-echo.mjs` | engine-local echo, 0 frames while typing |
| `e-island-decoder.mjs` | record-v1 decode + drain (pure) |
| `e-island-wasm.mjs` | a hand-assembled synthetic island (test fixture) |
| `e-island-e2e.mjs` / `e-island-e2e-real.mjs` | the seam live: synthetic / the real probe artifact |
| `e-windowed.mjs` | windowing: scroll-work p95, census, memory, anchoring, both discovery spellings + the overscan discriminators (dx-7e/A1) |
| `e-manifest.mjs` | the served manifest: v1/v2/404 — allowlist replace-not-union + the islands[] content-addressed resolve (CA URL hit, convention NOT) |
| `e-input-desc.mjs` | `data-webui-input` delivery: key keydown-only, space `" "`, composition island-only (dx-8e) |
| `c-ops.mjs` | the island's ABI byte-exact in node (no engine) |
| `c-parity.mjs` | native↔island equal hashes |
| `d-viewport.mjs` | source ⇄ sheet ⇄ handoff contract |
| `d-transport.mjs` | the KeyEvent → `{type,key,data}` v1 transport rule (parses the real identifier table) |
| `b-lint.mjs` / `b-budget-pins.mjs` | grants lint / the DX-3 measured pins + both tightening directions |
| `b-interaction-smoke.mjs` / `b-windowed-smoke.mjs` | bench interactions |
| `designer/continuum-bench.mjs` | the six §3 recipes (d0 harness) |
| `designer/d3-gate.mjs` | the d3 gate: echo budget, degrade, scroll (engine-local fixture, scroll-work ≤ 20 ms criterion) — 14/14 |
| `designer/dx-content-pin.mjs` | the I1 content-pin: 4-channel canonicalization, the exemption register, byte-pinned pages/manifest |
| `designer/dx-acceptance.mjs` | the appendix-A acceptance: home-dir template → zero verbs → mount via CA URL → dogfood ops |
| `designer/gates/dx5-demo.sh` / `scaffold-demo.sh` | the autobuild demo (reproducible) + the scaffold→verify e2e |
| `designer/gates/b-probe-fold.mjs` | the fold-in runner the canonical gates invoke |

the in-repo ladder: `plugin wasm-island` (both products — arms the budget
drift check) → `swift build` → `swift test` → `plugin smoke` (folds b-lint +
b-interaction) → `plugin fullstack-smoke` (folds b-windowed) → `plugin budget`
→ `plugin verify` (the full path, framework home) → `node
designer/browser-smoke.mjs` (folds the d3 gate as its agg; 46/46) → the wave
probes → `dx-content-pin` + `dx-acceptance` (orchestration gates). canonical
ports (9090/9091/9092/9123/9130) are for the orchestrator; lanes use their
blocks (9200–9219).

## 7. decisions of record + open items

decisions (full rationale in `continuum-notes/`): record ints little-endian;
insert's id slot = parent; `0xffff` sentinel reuse; attr payload
length-prefixed both fields; `Codable` gated `#if !hasFeature(Embedded)`;
drain = whole-record batches (the i1 freeze); `HotView` does not inherit
`View`; `Int64`-explicit formatting; `ContinuumDescriptor` stays host-side in
WebUI; the engine budget's deliberate re-pins (the plugin comment holds the
trip history). the CONTINUUM_DX additions: `@_expose(wasm:)` globals-only →
the export surface lives as global trampolines + `webui_island_bind`; the
wasip1 `_start` never runs Swift entry code → the runtime binds lazily;
`IslandRuntimeCore` is buffer-free (one code path native + wasm); the
args-derived mount contract is a protocol REQUIREMENT with a no-op default
(consumeMountEnvelope); `decodePendingOps` reads, never drains; the id dev
check lives in `IslandRuntime.swift` (no new compilation unit — the link
layout is size-sensitive) with empty-vocabulary fail-closed and `before`
anchors unchecked; `budget:` is tightening-only (positive literal pins;
zero = the auto spelling); DX-3 auto-pin convention `ceil(measured × 1.05)`;
the DX-11a/v flywheel — wired components get one id vocabulary, static
components stay byte-identical; ComponentOps boundaries (aria-sort lives on a
`<th>` carrying no id; structural items stay out of the attr/text plane); the
A1 overscan factor-vs-absolute ruling; the region `id` is explicit with an
`island-<name>` derived default (no derivation rule reproduces every
captured id).

open items: the d3 gate is
**closed** (14/14 — engine-local fixture rendering `Viewport`, criterion
re-based onto engine scroll-work p95 ≤ 20 ms per the measured 30 Hz host
floor; a 60 Hz host run can re-enable the absolute rAF assertion); v2
key-channel `modifiers`/`isRepeat`; row-level ops for detached window rows;
a server-side window-slice fetch path; `AttrWrapper` dynamic attr ops; the
generated codec bodies still carry the HotOpCodec drained-batch form — they
swap to `IslandRuntime<<Type>Island>.encodedState()` /
`.decodePendingOps()` once the consumer graph exposes `WebUIIslandCore`
(the accessors are live); `@HotView` island DISCOVERY (an island's source BEING
the `@HotView` struct, not a scan-found `Sources/<Name>/main.swift`) is next —
keep a consumer island self-contained until it lands; d5 (durable local state
/ live documents) and d6 (webview shell) remain separable future arcs. the
i2-recorded engine-budget owner sign-off exception (the +2,304 raw vs +2,048
ceiling reading; the registry-handling reading +1,699/+480) is the one
outstanding byte account item, unchanged by the DX waves.