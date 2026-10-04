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
