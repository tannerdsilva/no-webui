# lane-c → lane-d: wave-3 handoff — input types (t3.4) + kernels (t4.1) + corpus (t4.2)

landed on `task/c-islands` (lane-c wave 3) in `Sources/WebUISharedCore/`
(KeyEvent.swift, Selection.swift, ClipboardPayload.swift, UndoStack.swift) and
`Sources/WebUISharedCore/Kernels/` (t4.1 + KernelCorpus/KernelParity). lane D
consumes the t3.4 types for its delivery/modifiers half this wave — compile
against these shapes exactly.

## the t3.4 types (all in WebUISharedCore, wasm-visible, scalar-clean)

### KeyEvent.swift

```swift
public enum Key: Sendable, Hashable, Equatable {
    case enter, tab, escape, backspace, delete
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case home, end, pageUp, pageDown
    case space
    case function(Int)         // f1…f24
    case printable(String)     // one unicode scalar, as a string
    case unknown               // anything the vocabulary does not name
}

public struct ModifierSet: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16)
    public static let shift, control, option, command, capsLock, function, numLock
    // (apple names: option/command are the ⌥ and ⌘ on this platform)
}

public struct KeyEvent: Sendable, Equatable {
    public let key: Key
    public let modifiers: ModifierSet
    public let isRepeat: Bool
    public init(key: Key, modifiers: ModifierSet, isRepeat: Bool = false)
}
```

wire bridge for E's `{type,key,data}` v1 and D's engine-side composition
forwarding — `Key(identifier:)` / `Key.identifier` canonical strings
(parse failure → `.unknown`; the set is frozen in c-to-d).

### Selection.swift

```swift
public struct Selection: Sendable, Equatable {
    public var anchor: Int       // the press-side leaf index
    public var focus: Int        // the drag-side leaf index
    public init(anchor: Int, focus: Int)

    public var start: Int        // min(anchor, focus)
    public var end: Int          // max(anchor, focus)
    public var range: Range<Int> // start..<end (empty when collapsed)
    public var isEmpty: Bool     // anchor == focus
    public mutating func collapse(at index: Int)
    public func extending(to index: Int) -> Selection
    public func shifted(by delta: Int) -> Selection   // clamps at 0 (never negative)
    public func union(_ other: Selection) -> Selection
}
```

leaf indices are character/run positions, not utf8 byte offsets. an index below
0 is treated as 0 by the clamping ops.

### ClipboardPayload.swift

```swift
public struct ClipboardPayload: Sendable, Equatable {
    public var text: String          // the textual form
    public var tsv: String?          // tab-delimited interchange form
    public init(text: String, tsv: String? = nil)

    public static func tsv(rows: [[String]]) -> String   // cells joined with \t, rows with \n
    public func tsvRows() -> [[String]]                  // inverse; splits only on \t / \n
    public var hasTabularData: Bool
}
```

grids and editors share this interchange: write a table as
`ClipboardPayload(text: <paste-form>, tsv: ClipboardPayload.tsv(rows:))`, read
it back with `tsvRows()`. cells with embedded tab/newline are the caller's
problem (documented; the split is naive on purpose — deterministic parity).

### UndoStack.swift

```swift
public struct UndoStack<Action>: Sendable {
    public private(set) var undoLimit: Int
    public init(undoLimit: Int = 100)          // 0 = unlimited
    public mutating func push(_ action: Action)
    @discardableResult public mutating func undo() -> Action?
    @discardableResult public mutating func redo() -> Action?
    public var canUndo: Bool
    public var canRedo: Bool
    public var undoCount: Int
    public var redoCount: Int
    public mutating func clear()
}
```

pure and placement-free — natively tested (Tests/WebUISharedCoreTests/
InputTypesTests) and linked into the probe island's wasm via the parity corpus
(its `undo.stack` case exists in KernelCorpus). push clears the redo lane.
`Action` is unconstrained (any Sendable value).

## t4.1 kernel surface (if D's viewport/components need them)

`Sources/WebUISharedCore/Kernels/`:
- `Normalizer` (value type; trim/collapse/ASCII-fold recipe) + `Lexer` (predicate-handle tokenizer: `tokens(in:isToken:)`, `words(in:)`)
- `NumberAggregator` (incremental sum/min/max/avg/count) + `Aggregate` (array form)
- `KeyedSorter.stableSorted(_:key:by:)` — STABLE keyed sort (stdlib sorted is not)
- `Filter.filter/count/paginate(_:_:offset:limit:)` — include-predicate + windowing
- `NumberFormat.integer/grouped/fixed/percent` — deterministic, hand-rolled
  (fixed does NOT print what a decimal eye expects for binary-non-representables —
  it is placement-deterministic by design; pinned in KernelTests)
- `CivilDate` (proleptic Gregorian y/m/d; `iso8601()/longForm()/shortForm()`; epoch-day mapping)

## the parity gate (t4.2) — D may re-run it

`swift test` (writes `.build/webui-kernel-corpus-native.json`) + `node designer/probes/c-parity.mjs`
against the probe wasm artifact. EQUAL HASHES = the gate. adding a corpus case
is deliberate: freeze new goldens in `KernelParityGoldenTests`.

## ContinuumDescriptor — host-side for now

adjudicated 2026-10-03: `ContinuumDescriptor` STAYS in WebUI this wave (host-side
metadata; no wasm consumer yet). recorded in the sidecar; no action from D.
---

# lane-c → lane-d: CONTINUUM_DX W2 addendum — the DX-9 interface (W3 emission)

settled this wave (implemented + tested in `Sources/WebUIIslandCore/`). W3's
macro work compiles against these exact shapes.

## what the macro emits (per @HotView adapter)

- **literal vocabulary** — the `elementIDs` requirement (get-only):
  ```swift
  public static var elementIDs: Set<ElementID> { [ElementID("btn-x"), …] }
  ```
  collect every LITERAL `id:` / `ElementID` literal in the render body
  (over-collection is permissive-safe: the dev check ignores ids the island
  never emits; a missed literal is the only bug class). `ElementID` is
  `Hashable` with `raw: String` (WebUISharedCore) — Set membership is
  raw-keyed.
- **dynamic families** — override
  `public static func isKnownElementID(_ id: ElementID) -> Bool` and accept
  the runtime-derived families (`ElementID("t-\(key)")` rows etc.). the
  default implementation is `elementIDs.contains(id)`.
- the requirements + defaults exist ONLY under `-DCONTINUUM_ID_CHECK` (`#if`
  in the protocol + a gated extension). emitting `elementIDs` unconditionally
  is fine — production builds just carry an unused member; gating is the
  island's choice (the probe gates its overrides to keep the production
  artifact trace-free).

## enforcement semantics (what the check does with the vocabulary)

- every op emitted via `webui_on_event` must target a known id
  (`IslandIDCheck.target(of:)`: insert → parent; text/attr/remove/move → the
  element; `before` anchors are NOT checked).
- unknown → frame-buffer diagnostic naming the id + trap (`fatalError`).
- empty vocabulary = fail-closed (an island declaring nothing traps on any
  op). adapters with only dynamic ids MUST override `isKnownElementID`.
- run: `swift test -Xswiftc -DCONTINUUM_ID_CHECK` (native). check-mode wasm
  needs the manual cross-build (c-docs recipe — the plugin has no `-D`
  passthrough yet).

## the equivalence fixture (W3)

`ProbeIslandIDs.isKnown(_:)` (always compiled) is the hand-written fallback to
diff the macro-emitted vocabulary against — it accepts the probe's literals +
the `probe-item-` family. keep the diff in the equivalent-fixture test
(d-docs §DX-9), not in production code.

---

# lane-c → lane-d: CONTINUUM_DX W3 addendum — the codec accessors are live

_committed `task/c-islands` (W3, `0bd15f1`). the d-to-c W2-delta swap-in
surface is landed; D's generated bodies can chase it exactly._

## the exact spell (swap to these two statics, verbatim)

- `_continuumEncode() -> [UInt8]` → `IslandRuntime<<Type>Island>.encodedState()`
  — the bound instance's retained-state snapshot bytes (`core.stateSave()`,
  the exact `webui_state_save` payload / `restoreIslandRegionState` path);
  `[]` when nothing is bound (host builds / an island whose main never ran
  `run()`).
- `_continuumDecode() -> [HotEffect]` →
  `IslandRuntime<<Type>Island>.decodePendingOps()` — the bound instance's
  currently-pending records decoded back into `.ops([…])` effects. reads,
  never drains (`webui_take_ops` stays the only queue consumer — a decode
  accessor cannot double-apply).

## what D must still land for the swap to compile + run

1. **the `elementIDs` emission is NOT on origin yet** (checked at 3381e89 —
   `WebUIContinuumMacro.swift` has no `elementIDs`). runtime fixture proving
   the documented spell end-to-end is in
   `Tests/WebUIIslandCoreTests/MacroVocabularyFixtureTests.swift` (diff vs
   `ProbeIslandIDs`, gated `-DCONTINUUM_ID_CHECK`). when D's emission merges,
   re-point the string suite at it (the diff point).
2. **the consumer-graph exposure** (WebUIIslandCore visible to `@HotView`
   targets) — D/B's package work; without it the generated code cannot name
   `IslandRuntime` at all.
3. **spelling reality:** `IslandRuntime` keeps `I: IslandRuntimeSurface`
   (NOT relaxed — judged byte-risky for the size-exact probe anchor, and the
   d-to-c point-3 option was conservatively declined). D's generated adapter
   is `ContinuumIsland`-only today, so `IslandRuntime<<Type>Island>` only
   type-checks once the adapter satisfies the surface (or the enum constraint
   is adjudicated at integration under a deliberate re-anchor). the probe +
   validate + templates' hand-written `FeedIsland` all conform, so the spell
   is proven against surface-conforming islands now.