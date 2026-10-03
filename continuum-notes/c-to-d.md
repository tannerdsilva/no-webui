# lane-c → lane-d: the seam vocabulary the macro adapters compile against

lane D owns `@HotView`/`@HotClass`/`@HotBuilder` + the generated adapters.
everything below is landed on `task/c-islands` (commit 7283904) in
`Sources/WebUISharedCore/Continuum.swift`, shapes per DESKTOP_GRADE §1.3.3–1.3.5.
compile against these exactly.

## the types

```swift
public struct ElementID: Sendable, Hashable, Codable, ExpressibleByStringLiteral { public let raw: String ... }
public struct AttributeName: Sendable, Hashable, Codable, ExpressibleByStringLiteral { public let raw: String ... }
public enum HotOp: Sendable, Equatable { case text(ElementID, String); case attr(ElementID, AttributeName, String); case insert(parent: ElementID, before: ElementID?, html: String); case remove(ElementID); case move(ElementID, before: ElementID?) }
public protocol HostCapability: Sendable { static var wireName: String { get } }
// six structs: FrameSchedule("frame_schedule") InputSubscription("input_subscribe") SurfaceAcquisition("surface_acquire") StatePersistence("state_persist") ClockCapability("clock") LogCapability("log")
public enum HotEffect: Sendable { case ops([HotOp]); case save; case log(String) }
public struct IslandBudget: Sendable, Equatable { public let maxBytes: Int; public let maxGzipBytes: Int?; public init(maxBytes: Int, maxGzipBytes: Int? = nil) }
public protocol ContinuumIsland: Sendable { associatedtype State: HotState; associatedtype Action: HotAction; static var name: String { get }; static var imports: [any HostCapability.Type] { get }; static var budget: IslandBudget { get }; static func reduce(state: inout State, action: Action) -> [HotEffect] }
```

## the codable gate — read this before generating any `Codable` conformance

`Codable` is `@_unavailableInEmbedded` in the embedded wasm sdk
(verified: `Swift.Codable:2:18: 'Codable' has been explicitly marked
unavailable here`). the seam types declare Codable on the **host surface
only**:

```swift
#if !hasFeature(Embedded)
extension ElementID: Codable {}
extension AttributeName: Codable {}
public protocol HotState: Codable, Sendable, Equatable {}
public protocol HotAction: Codable, Sendable {}
#else
public protocol HotState: Sendable, Equatable {}
public protocol HotAction: Sendable {}
#endif
```

consequence for D: the macro-generated `reduce`/adapter code inside the island
target must NOT synthesize `Codable` for `State`/`Action`, and must not route
state through `JSONEncoder`/`Decoder`. the island path serializes with
`JSONValue.parse`/`serialize` + `HotOpCodec`. `ContinuumIsland.reduce` is pure
and placement-free — it runs in wasm and in native tests (parity by
construction), so D's adapter can (and should) reference `reduce` directly.

## hand-written-equivalent rule

per §9, one hand-written `ContinuumIsland` conformance must live in tests
proving the macro expansion is equal to hand-written code. the probe island
(`Sources/WebUIProbeIsland/main.swift`, t2.5 skeleton) is the wasm proof; a
test-side conformance is up to D's expansion tests.

## placements reminder (never compile to wasm)

`HotView`/`HotPrimitive`/the macro *declarations* belong in `WebUI` (host
only); the macro *implementation* in a host-only target; swift-syntax must
never enter a wasm-compiled dependency chain.
