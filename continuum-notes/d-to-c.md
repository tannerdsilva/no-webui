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

## descriptor `className` source

`@HotView` reads a sibling `@HotClass(...)` attribute on the same declaration and
joins its classes (space-separated) into `className`; with no sibling it emits
`""`. lane B's inventory (from `@HotClass`'s `continuumClasses`, t1.3) and the
descriptor agree by construction when both macros sit on one type.
