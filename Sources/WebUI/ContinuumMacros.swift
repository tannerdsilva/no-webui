import Foundation
import WebUICore

// MARK: - continuum macros (@HotView / @HotClass)
//
// declaration placement is load-bearing (DESKTOP_GRADE §5 t3.1): macro
// *declarations* are inert syntax — the implementation is a separate, host-only
// compiler-plugin target (`WebUIContinuumMacros`) that must never enter a
// wasm-compiled dependency chain (swift-syntax does not cross-build). the
// view-side runtime vocabulary this surface generates against lives in
// `ContinuumHot.swift`; the descriptor + server path in `ContinuumSurface.swift`.

/// the hot-view attribute: one declaration, two placements.
///
///     @HotView("feed", imports: [ClockCapability.self],
///              budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096))
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
///   the author's `reduce`; `State`/`Action` alias the view's; `imports`/`budget`
///   carry the declared values; `_continuumEncode`/`_continuumDecode` carry the
///   island-side codec entry points;
/// - `@_expose(wasm, …)` shims — the t2.3 export names (`<name>_encode`/`<name>_decode`)
///   on *global* functions (`@_expose` forbids non-global placement — verified);
/// - `extension Feed: ContinuumServerPath` — the server adapter.
///
/// the import/budget parameters type-check at the use site: `imports:` takes
/// `HostCapability` types (`[ClockCapability.self]` — never wire strings) and
/// `budget:` an `IslandBudget`. both stay optional (additive): name-only
/// `@HotView("feed")` keeps working. `budget:` is TIGHTENING-ONLY (DX-3,
/// CONTINUUM_DX §2.3): non-empty `imports:` auto-defaults the budget from the
/// measured pin the build writes — the older imports-require-budget rule is
/// retired — and a DECLARED pin is a positive ceiling (a `maxBytes: 0`
/// declaration is the auto spelling and must be omitted, not written).
///
/// diagnostics refuse (never `fatalError`): a non-struct target; a missing or
/// malformed name; a duplicate registry marker; a declaration without
/// `State`/`Action`; a body not declared `@HotBuilder`; wire-string imports;
/// and a `budget:` that is not a positive literal tightening pin.
@attached(extension, conformances: ContinuumServerPath, names: arbitrary)
@attached(peer, names: prefixed(_continuumEncode), prefixed(_continuumDecode))
public macro HotView(
	_ name: String,
	imports: [any HostCapability.Type] = [],
	budget: IslandBudget? = nil
) = #externalMacro(module: "WebUIContinuumMacros", type: "HotViewMacro")

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