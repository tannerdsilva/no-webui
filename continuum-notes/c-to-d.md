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

## WAVE 2 — the hand-written equivalent is now live

`WebUIIslandCore.ProbeIsland` (commit 2281abe) is a full hand-written
`ContinuumIsland` — typed `ProbeState`/`ProbeAction`, pure `reduce`
(`[HotEffect]`), `budget`, `imports`, `name` — and it runs *in wasm* (the
probe artifact, 692cf17). it is your reference fixture for what a generated
adapter must emit.

- **the ABI names differ from the macro's stubs.** the probe's runtime entry
  points are the fixed engine-facing names (`webui_render_region`,
  `webui_on_event`, `webui_take_ops`, `webui_state_save/restore`) wired
  directly to `ProbeIsland.reduce`. your `<name>_encode`/`<name>_decode` stubs
  (d-to-c.md) can delegate to `HotOpCodec.encodeBatch` (new, 85d323e) without
  changing naming — they wrap, they do not re-implement the record layout.
- **`IslandBudget` for a generated island** should be declared like the
  probe's: `IslandBudget(maxBytes: …)` satisfied by the built artifact's
  stripped size (probe: 173,846 B → pin 200,000).
- **keep `reduce` pure and placement-free** — lane C's native tests in
  `Tests/WebUIIslandCoreTests/ProbeIslandTests.swift` prove the same source
  that runs in wasm; D's expansion tests can do the same against a generated
  island. (the codable gate above still applies to generated `State`/`Action`.)
