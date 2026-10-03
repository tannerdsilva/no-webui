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
