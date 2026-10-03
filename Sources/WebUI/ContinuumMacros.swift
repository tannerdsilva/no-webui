import Foundation

/// a view that can serve its state server-side: the server renders `render(state:)`
/// html and routes actions through the router. `@HotView` generates conformance;
/// hand-writing it stays possible and tested (the hand-written-equivalent rule).
/// wave-1 ships the marker only — the render/routing requirements land in wave 2
/// alongside the view-side protocols, and the macro's generated `extension Feed:
/// ContinuumServerPath` compiles against them unchanged.
public protocol ContinuumServerPath {}

// MARK: - continuum macros (@HotView / @HotClass)
//
// declaration placement is load-bearing (DESKTOP_GRADE §5 t3.1): macro
// *declarations* are inert syntax — the implementation is a separate, host-only
// compiler-plugin target (`WebUIContinuumMacros`) that must never enter a
// wasm-compiled dependency chain (swift-syntax does not cross-build). the view-side
// runtime protocols this surface generates conformance for (`HotView`/`HotPrimitive`/
// `HotTree`) land in wave 2; the generated members reference them by name only and
// are exercised by string-based expansion tests until then.

/// the hot-view attribute: one declaration, two placements.
///
///     @HotView("feed")
///     struct Feed: HotView {
///         typealias State = FeedState
///         typealias Action = FeedAction
///         @HotBuilder func render(state: State) -> HotTree { … }
///         static func reduce(state: inout State, action: Action) -> [HotEffect] { … }
///     }
///
/// generated (expansion tests assert each by name; the plan's §5 t3.1 member table):
///
/// - `static let continuumDescriptor` — name/grants/budget/class, greppable;
/// - `struct FeedIsland: ContinuumIsland` — the island adapter; `reduce` forwards to
///   the author's `reduce`; `State`/`Action` alias the view's;
/// - `@_expose(wasm, …)` codec shims — the t2.3 export names;
/// - `extension Feed: ContinuumServerPath` — the server adapter.
///
/// wave-1 signature is name-only (`@HotView("feed")`); the `imports:`/`budget:`
/// parameters arrive in wave 2 alongside the view-side protocols. a sibling
/// `@HotClass(…)` on the same declaration feeds the descriptor's class vocabulary.
///
/// generated members reference the seam vocabulary (`ContinuumIsland`,
/// `HostCapability`, `IslandBudget`, `HotEffect`, `ContinuumDescriptor`,
/// `ContinuumServerPath`) by name; the macro adds no runtime work the declaration
/// does not state.
@attached(extension, conformances: ContinuumServerPath, names: arbitrary)
public macro HotView(_ name: String) =
	#externalMacro(module: "WebUIContinuumMacros", type: "HotViewMacro")

/// the class-vocabulary attribute: declares a component's class names once.
///
///     @HotClass("feed-item", "feed-item__meta")
///     struct FeedItem: View { … }
///
/// generated: `static let continuumClasses: [String]` — the inventory the registry
/// scan and the attr lint (DESKTOP_GRADE §1.5) read. additive only: a hand-written
/// `static let continuumClasses` is the no-macro path and stays valid.
@attached(member, names: named(continuumClasses))
public macro HotClass(_ classes: String...) =
	#externalMacro(module: "WebUIContinuumMacros", type: "HotClassMacro")
