# lane d → lane c — handoff (the emitted-name contract)

the @HotView expansion (ships in lane d's branch, `task/d-surface`) references the
continuum vocabulary **by name only**; wave 1 never compiles it. for integration
(i1/i2) the generated text must type-check against lane C's `Continuum.swift`
(`Sources/WebUISharedCore/`, per the load-bearing placement table). the names lane
C must declare, and the exact spelling the expansion uses:

## types the expansion references (must resolve where the macro is used)

| name | expansion uses it as | expected home | plan § |
|---|---|---|---|
| `ContinuumServerPath` | protocol in `extension Feed: ContinuumServerPath` | **lane d / WebUI** — already shipped as a wave-1 marker in `ContinuumMacros.swift`; wave-2 requirements live there. do NOT declare in WebUISharedCore (placement table keeps view-side in WebUI). | 1.4 / t3.1 |
| `ContinuumDescriptor` | struct init `ContinuumDescriptor(name:grants:budget:className:)` | **open decision** — suggestion: WebUISharedCore (seam, scalar-clean; the t2.3 codec + registry read it) | t3.1 "value" |
| `ContinuumIsland` | protocol for the nested adapter struct | WebUISharedCore | 1.3.5 |
| `HotState` | `typealias State` constraint | WebUISharedCore | 1.3.5 |
| `HotAction` | `typealias Action` constraint | WebUISharedCore | 1.3.5 |
| `HotEffect` | `reduce` return | WebUISharedCore | 1.3.5 |
| `HostCapability` | `static var imports: [any HostCapability.Type]` element | WebUISharedCore | 1.3.4 |
| `IslandBudget` | `IslandBudget(maxBytes:maxGzipBytes:)` | WebUISharedCore | 1.3.5 |

## forwarding shape the adapter expects

- the author's view declares `typealias State` / `typealias Action` and a
  `static func reduce(state: inout State, action: Action) -> [HotEffect]` — the
  generated `FeedIsland.reduce` forwards verbatim:
  `Feed.reduce(state: &state, action: action)`.
- `ContinuumIsland` requirements the adapter satisfies: `name`, `imports`,
  `budget`, `reduce(state:inout:action:) -> [HotEffect]`, plus `State`/`Action`
  associated types. if your `ContinuumIsland` gains a requirement this wave-1
  cone doesn't emit, flag it — a default implementation keeps the expansion valid.

## t2.3 codec / export-table reconcile (island exports)

the expansion emits two `@_expose(wasm, …)` stubs with **deterministic names**:

- `@_expose(wasm, "<name>_encode")  static func _continuumEncode() -> [UInt8]`
- `@_expose(wasm, "<name>_decode")  static func _continuumDecode() -> [HotEffect]`

`<name>` = the island name passed to `@HotView`. these names + the record table
are lane C's ABI; when the codec lands (t2.3), either (a) the stubs get real
bodies in lane C/wave 2, or (b) the macro emission is adjusted to the final
signature — flag the change in the integration diff review. the reduce loop the
runtime calls is the adapter's `reduce`; the stubs are the frame-buffer entry
points the island exports.

## W1/CONTINUUM_DX resolution** (recorded in d-docs.md): W2 takes option (a) —
D's macro swaps ONLY the stub bodies to delegate to your DX-1 slice:
`_continuumEncode()` → `IslandRuntime<<Type>Island>.encodedState()` (state →
`HotOpCodec` frame bytes) and `_continuumDecode()` → `HotOpCodec.decode(...)`
of the pending op batch. the generated shims will chase your merged
`IslandRuntime.swift` at W2 start, so the exact signatures are yours to land
first (DX-1, this wave).

## lane-d → lane-c · W2 delta (d-surface2) — the codec accessors you need to land

your merged `IslandRuntime.swift` has everything EXCEPT the two statics the
codec-entry delegation needs. the macro (this branch) now emits HotOpCodec-
backed drained-batch bodies and pins them; they swap verbatim to your accessors
the moment both are true:

1. **`IslandRuntime<I>` gains same-module statics** (or extensions — NFA with
   the internal box):
   - `encodedState() -> [UInt8]` — the bound instance's `core.stateSave()`
     bytes (`IslandRuntimeBridge<I>.box`), a fresh-core snapshot or `[]` when
     nothing is bound (native/host builds);
   - `decodePendingOps() -> [HotEffect]` — the bound instance's pending
     records, each record decoded via `HotOpCodec.decode` into `.ops([…])`.
2. **the consumer graph must see `WebUIIslandCore`**: the acceptance/template
   App target and any `@HotView` consumer currently depend on WebUI products
   only; until `WebUIIslandCore` is exposed there, generated code cannot name
   `IslandRuntime` at all.
3. if the enum's `I: IslandRuntimeSurface` constraint must relax so a
   `ContinuumIsland`-only generated adapter can name `IslandRuntime<FeedIsland>`
   (for `encodedState()` without the four hooks), land the statics against the
   `canImport`-free public surface accordingly — flag it back; the emission is
   isolated to two bodies and swaps in one patch (d-docs W2 implementation
   record).

## descriptor `className` source

`@HotView` reads a sibling `@HotClass(...)` attribute on the same declaration and
joins its classes (space-separated) into `className`; with no sibling it emits
`""`. lane B's inventory (from `@HotClass`'s `continuumClasses`, t1.3) and the
descriptor agree by construction when both macros sit on one type.


## lane-d → lane-c · W3 delta (d-surface2, CONTINUUM_DX wave 3) — the swap is teed up; your accessors are the gate

the two W3-d units are on the tree (`6db5c0b` DX-11b ComponentOps, `4712ba9`
DX-9 emission); the codec swap-in is the last D item and it waits on you. at
every fetch so far `task/c-islands` was still `3381e89` — nothing new since
the i2 tip. when you land:

1. **the accessors** — `IslandRuntime<I>.encodedState() -> [UInt8]` (bound
   instance `stateSave()` bytes; `[]` when nothing is bound / native hosts,
   so the untethered emission stays honest) and
   `IslandRuntime<I>.decodePendingOps() -> [HotEffect]`. the emission swaps
   these two bodies VERBATIM:
   - `_continuumEncode() -> [UInt8]` → `IslandRuntime<<Type>Island>.encodedState()`
   - `_continuumDecode() -> [HotEffect]` → `IslandRuntime<<Type>Island>.decodePendingOps()`
   one self-contained patch; the string expansion suite + the compiled
   fixture re-assert it.
2. **the seam shape** — the generated adapter is `ContinuumIsland`-only; if
   the statics stay constrained `I: IslandRuntimeSurface`, `IslandRuntime
   <FeedIsland>` does not type-check for any generated (or name-only) adapter
   in the fixture. see the W2 delta's item 3: either land them against the
   relaxed surface (e.g. defaults / a `ContinuumIsland`-nameable entry) or
   give the swap a surface-conforming path — flag the shape back and D fits
   the emission to it.
3. **consumer-graph exposure** — the compiled fixture (Tests/
   WebUIContinuumMacroTests, imports WebUI only) must be able to NAME
   `IslandRuntime`; neither WebUI nor WebUIDesignSystem re-exports
   `WebUIIslandCore` today. if you don't expose it yourself, D will add
   `WebUIIslandCore` to the macro-test target (additive) — but the acceptance
   template's App target still needs the exposure for the §0.3 lone-@HotView
   path, which is yours.
4. until then **the HotOpCodec record-v1 plane stays the compiled-fixture
   proof** (`codecRoundTrip`: encode→decode byte-exact on a real op); the
   swap replaces it with the runtime-accessor path and the fixture asserts
   parity between the two spellings before the record plane retires.

## lane-d → lane-c · W3 delta — RESOLVED (the swap landed, d-surface2 `9d298fa`)

your `0bd15f1` accessors merged as the integration head `8e79172`; the swap
went verbatim into the emission (`IslandRuntime<<Type>Island>.encodedState()`
/ `.decodePendingOps()`), and all three owed items are closed from the D side:

1. **elementIDs emission** — merged via `4712ba9`; the string suite pins the
   diff point and your `MacroVocabularyFixtureTests` stays green under
   `-DCONTINUUM_ID_CHECK`.
2. **consumer-graph exposure** — `WebUIContinuumMacroTests` gains
   `WebUIIslandCore` (additive) so the swapped bodies name `IslandRuntime` in
   the compiled fixture. the acceptance template's App target exposure (the
   §0.3 lone-@HotView compile) is handed to E/B in d-to-e/d-docs.
3. **spelling reality** — constraint kept; the swap takes your sanctioned
   surface-conforming path: the fixture + hand-written equivalent carry the
   author-supplied `IslandRuntimeSurface` conformance (template-feed shape),
   proving the spell against a surface-conforming island.

parity: `codecRoundTrip` asserts `IslandRuntime<...>.encodedState()` ==
`(try? HotOpCodec.encodeBatch([])) ?? []` (drained surface), macro body ==
accessor, and the hand-written equivalent carries the SAME bodies.
