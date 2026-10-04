# lane-c docs fragment (wave 1)

for orchestrator folding into `Documentation/CONTINUUM.md` + `CHANGELOG.md` at
integration. sources of truth: `Sources/WebUISharedCore/Continuum.swift`
(commit 7283904) and `Sources/WebUIProbeIsland/main.swift` (probe commit).

## what landed (lane c, wave 1)

- **seam vocabulary** in the zero-dep leaf `WebUISharedCore/Continuum.swift`,
  shapes per DESKTOP_GRADE §1.3.3–§1.3.5: `ElementID`, `AttributeName`,
  `HotOp` (text/attr/insert/remove/move), `HostCapability` +
  FrameSchedule/InputSubscription/SurfaceAcquisition/StatePersistence/
  ClockCapability/LogCapability, `HotState`/`HotAction`, `HotEffect`,
  `IslandBudget`, `ContinuumIsland`.
- **`HotOpCodec`** — hand-rolled, scalar-clean record codec (format v1,
  §t2.3): little-endian multi-byte ints, u16 length-prefixed identifiers,
  u32 length-prefixed bulk strings, `before` field shared by insert/move with
  `0xffff` = end sentinel, invalid utf-8 → U+FFFD, strict single-record decode
  (trailing bytes rejected). `decode`/`encode` never touch Foundation and stay
  embedded-clean (verified: compiles with `swift-6.4.0-RELEASE_wasm-embedded`).
- **`WebUIProbeIsland`** (t2.5 skeleton): the stateful probe — same
  region contract as the validate island (`webui_input_ptr`/`webui_frame_ptr`/
  `webui_frame_len`), plus `webui_render_region` (mount html), `webui_on_event`
  (wave-1 ack + counter), `webui_state_save`/`webui_state_restore` (counters
  survive remounts — the RETAINED_OPEN precedent generalized). `utf8Decode` +
  `writeFrame` copied verbatim from the validate template. wave 2 fills typed
  state + the op stream.

## decisions recorded (conservative choices on ambiguity)

1. **endianness**: record integers are little-endian (wasm32 + every in-tree
   host). not stated in §t2.3; documented in-file.
2. **insert id slot = parent**: `HotOp.insert(parent:before:html:)` has no
   "new element id" associated value, so the record `id` field carries the
   parent (the element the op operates on); the engine allocates the new
   element's id on apply. the only reading that round-trips the frozen type.
3. **`before` sentinel for insert**: §t2.3 names `0xffff = end` only under
   `move`; reused for insert's optional `before` (append-at-end), consistent
   semantic.
4. **attr payload layout**: "u16 name + u32 value" read as length-prefixed
   name (u16) + length-prefixed value (u32), mirroring every other string
   field.
5. **codable gating**: `Codable` is `@_unavailableInEmbedded`; conformances
   and protocol refinements are wrapped in `#if !hasFeature(Embedded)` (the
   JSONValue precedent). host surface unchanged vs the spec; island path uses
   JSONValue + HotOpCodec.
6. **strict single-record decode**: `decode` rejects trailing bytes; the
   multi-record `webui_take_ops()` call shape is a wave-2 decision (open,
   flagged to lane E).
7. **probe product**: an explicit `.executable` product was added for
   `WebUIProbeIsland` (parent t2.5 says "+ island product"); the validate
   island predates a product entry and rides SwiftPM's implicit executable
   product.

## wave-2 queue (lane c)

encoder consumer wiring (probe emits ops via `HotOpCodec`); typed
`ContinuumIsland` state in the probe; `webui_take_ops` multi-record call
shape; kernels (t4.1/t4.2) + parity; t3.4 input types
(`KeyEvent`/`ModifierSet`/`Selection`/`ClipboardPayload`/`UndoStack`).

---

# lane-c docs fragment — WAVE 2 (t2.5 full: the probe island becomes real)

for orchestrator folding into `Documentation/CONTINUUM.md` + `CHANGELOG.md` at
i2. sources of truth: `Sources/WebUISharedCore/Continuum.swift`
(`HotOpCodec.encodeBatch`, commit 85d323e), `Sources/WebUIIslandCore/ProbeIsland.swift`
(2281abe), `Sources/WebUIProbeIsland/main.swift` (692cf17),
`designer/probes/c-ops.mjs` (bf4d867).

## what landed (lane c, wave 2)

- **the probe island is real.** `WebUIIslandCore.ProbeIsland` is a hand-written
  `ContinuumIsland` (the "one hand-written equivalent" rule): typed state —
  a counter plus a small keyed list — and typed actions; `reduce` is pure and
  placement-free (runs in wasm and in native unit tests: parity by
  construction). `decodeEvent` maps the engine's `{type, key, data}` v1 payload
  to actions; `stateToJSON`/`stateFromJSON` round-trip the typed state through
  `JSONValue`; `regionHTML` stamps the element ids the reduce ops target.
- **op-stream out under the freeze.** `HotOpCodec.encodeBatch` concatenates
  record-v1 encodings back-to-back; `webui_take_ops() -> u32` (implemented in
  the probe's wasm surface) serves the next batch's byte length in the frame
  buffer — 0 = empty — serving whole records until the drain returns 0. that
  resolves wave 1's open "multi-record call shape" decision (documented in
  c-to-e.md against lane E's decoder).
- **events in.** `webui_on_event(ptr, len)` decodes the payload with
  `JSONValue` (scalar-clean), routes into the typed reduce, and queues the
  encoded record. recognized vocabulary: `key` ArrowUp/ArrowDown,
  `click` probe-inc/probe-dec/probe-clear, `input` probe-field (see c-to-e.md).
  unknown/malformed → `.noop` (empty stream).
- **state channel.** `webui_state_save`/`webui_state_restore` carry the typed
  state + render/event counters across remounts (the RETAINED_OPEN precedent,
  generalized); a malformed restore keeps the live state (never wipes).
- **the node-load probe.** `designer/probes/c-ops.mjs` loads the stripped wasm
  in node (no engine/server), drives every export, and asserts the op batches
  byte-for-byte against HotOpCodec record-v1 fixtures — including a
  fresh-instance remount proving state survives. 15/15 green.
- **wasm artifact.** `WebUIProbeIsland.wasm` 173,846 B stripped / 80,620 B
  gzip — kB tier (validate: 164,670 B); `IslandBudget(maxBytes: 200_000,
  maxGzipBytes: 90_000)` declared and satisfied. all 8 exports verified in
  node: `webui_input_ptr`/`webui_frame_ptr`/`webui_frame_len` +
  `webui_render_region` + `webui_on_event` + `webui_take_ops` +
  `webui_state_save`/`webui_state_restore`.

## decisions recorded (wave 2)

1. **take_ops serves batches but never splits a record.** a batch is whole
   records back-to-back; the engine drains until 0. multi-record batches
   happen when several events queue before a drain.
2. **on_event queues; the engine drains.** `webui_on_event`'s return value
   stays the frame pointer (wave-1 compat); op delivery is exclusively via the
   `webui_take_ops` drain loop.
3. **element ids are a contract.** `probe-counter`/`probe-list`/
   `probe-item-kN` are the ids both the mount html and the reduce ops use —
   one source of truth in `ProbeIslandIDs`.
4. **event→action mapping is decoder-side, not engine-side.** the engine
   delivers the raw `{type,key,data}` v1 payload; the island owns the mapping
   (and it is natively tested), so lane E's routing stays shape-only.
5. **`String` literal matching in island code** goes through
   `unicodeScalars.elementsEqual` (the ValidateIsland discipline) so the
   embedded runtime never needs canonical-equivalence normalization.

## handoffs (wave 2)

- **to lane E:** the take_ops drain contract + the probe event vocabulary are
  in `continuum-notes/c-to-e.md` (the engine's decoder/patcher implements
  against that table; reference drain loop included).
- **to lane B:** the probe's `IslandBudget` pins (200,000/90,000) are live and
  the artifact satisfies them — the budget plugin can keep its pin sweep.
- **to lane D:** the hand-written `WebUIIslandCore.ProbeIsland` is the
  hand-written-equivalent fixture for `@HotView` adapters; the fixed ABI names
  (`webui_take_ops` etc.) are the runtime entry points, distinct from the
  macro's `<name>_encode`/`<name>_decode` stubs (those can wrap the codec on
  emission).

## wave-3 queue (lane c)

kernels (t4.1/t4.2) + parity suite; t3.4 input types (`KeyEvent`/
`ModifierSet`/`Selection`/`ClipboardPayload`/`UndoStack`); `ContinuumDescriptor`
home decision for lane D's expansion (suggested: WebUISharedCore).

---

# lane-c docs fragment — WAVE 3 (final build wave: t4.1 kernels · t4.2 parity · t3.4 input types)

for orchestrator folding at i3. sources of truth:
`Sources/WebUISharedCore/Kernels/` (aec186a, 43be694), `webui_run_corpus` +
`KernelParity` + `designer/probes/c-parity.mjs` (4301d4f, 43be694),
`Sources/WebUISharedCore/{KeyEvent,Selection,ClipboardPayload,UndoStack}.swift`
(8bbd275).

## what landed

- **t4.1 shared kernels** in `Sources/WebUISharedCore/Kernels/` — pure,
  generic, foundation-free, scalar-clean (each a value type or a pure static
  function with a narrow predicate/comparator protocol):
  `Normalizer`/`Lexer` (normalize+lex), `NumberAggregator` + `Aggregate`
  (sum/min/max/avg/count), `KeyedSorter.stableSorted` (STABLE keyed sort —
  stdlib sorted is not), `Filter` (predicate handles + paginate),
  `NumberFormat.integer/grouped/fixed/percent` (hand-rolled, no Foundation),
  `CivilDate` (Hinnant's civil algorithms, no Foundation). 28 native tests pin
  exact outputs.
- **t4.2 parity suite — EQUAL HASHES = the gate.** one frozen corpus
  (`KernelCorpus`, 25 named cases over every kernel + the t3.4 primitives)
  runs the SAME Swift natively and inside the probe island's wasm; the island
  gains the `webui_run_corpus` export (serves `KernelParity.resultsJSON()` —
  FNV-1a of each canonical result); the native suite asserts the frozen golden
  table and writes `.build/webui-kernel-corpus-native.json`;
  `designer/probes/c-parity.mjs` compares sets: **25/25 hashes equal**.
- **the parity probe caught a real portability bug.** `Int` is 32-bit on
  wasm32, so `format.int` (Int.min/max) hashed differently until
  `NumberFormat.integer/grouped` went `Int64`-explicit — `Int64` bindings at
  every corpus call site to keep the canonical strings width-stable. recorded
  as decision 1 below.
- **t3.4 input types** in `WebUISharedCore` — `Key` (closed enum, frozen wire
  vocabulary via `identifier`/`init(identifier:)`, the same names E's
  `{type,key,data}` v1 carries: "ArrowUp"…), `ModifierSet` (OptionSet,
  shift/control/option/command/capsLock/function/numLock),
  `KeyEvent`, `Selection` (anchor/focus, clamp-at-0), `ClipboardPayload`
  (text + tsv interchange), `UndoStack<Action>` (generic, pure). 25 native
  tests; the corpus links them into wasm and hashes them (parity green).

## budget + artifact (the deliberate re-pin; enforcement handoff)

- probe island `WebUIProbeIsland.wasm` — measured wave-2: **173,846 B / 80,620
  gzip** · after t4.2: **218,632 / 95,248** · after t3.4 (input cases linked):
  **231,984 / 99,360**. the declared `IslandBudget` was re-pinned
  deliberately to **240,000 / 105,000** (~3.4% raw headroom) in
  `ProbeIsland.budget`.
- **enforcement gap (handoff to B/orchestrator at i3):** the budget plugin
  enforces the probe via the GLOBAL `islandCeiling = 200_000`
  (`WebUIBudgetPlugin`, B's file) because `ContinuumManifest.json` only
  carries pins from `@HotView` markers (WebUI sources) — the hand-written
  probe's declared budget is NOT yet emitted into the manifest. `plugin budget`
  currently flags `WebUIProbeIsland.wasm: 218632 > 200000` (231,984 after
  t3.4). the fix is integration-side: either emit the probe's declared pin
  into the manifest (extend `WebUIContinuumTool.islandPins` to scan
  hand-written `ContinuumIsland.budget` — those declarations live in
  `Sources/WebUIIslandCore/` + `Sources/WebUIProbeIsland/`) or raise the
  global island ceiling to ≥ 240,000. the DECLARED pin stays the source of
  truth either way.

## decisions recorded

1. **Int-width stability is a kernel API contract.** any public kernel taking
   `Int` would behave differently on wasm32; formatting entry points are
   `Int64`-explicit and the corpus never lets a width-sensitive value sneak
   through (grep `format.int`). documented in FormatNumber.swift.
2. **canonical corpus strings never interpolate raw Doubles** — doubles pass
   through `NumberFormat.fixed` (my formatter, placement-identical), never
   `String(Double)` whose digit generation may differ in the embedded stdlib.
3. **hash = FNV-1a 64-bit over the canonical result's UTF-8.** determinism is
   the goal, not collision resistance. both sides compute bit-identical
   hashes from bit-identical strings via pure integer math.
4. **`webui_run_corpus()` takes no input** (the corpus is compile-time-frozen
   in WebUISharedCore) and writes `KernelParity.resultsJSON()` to the frame
   buffer — an ordered `cases` array (order is part of the contract).
5. **`ContinuumDescriptor` stays in WebUI** (adjudication, no action — host-
   side metadata, no wasm consumer yet).

## handoffs

- **to B/orchestrator:** the budget enforcement gap above (probe pin emission
  or global-ceiling bump); the declared pin is 240,000/105,000, artifact
  231,984/99,360.
- **to D:** the t3.4 shapes + the parity gate recipe are in `c-to-d.md`.
- **to E:** `webui_run_corpus` is a NEW probe export (additive — the ABI is
  unchanged; c-ops regression 15/15) — updated contract in `c-to-e.md`.
