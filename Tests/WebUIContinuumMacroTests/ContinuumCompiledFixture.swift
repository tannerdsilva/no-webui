import WebUI

// MARK: - the compiled end-to-end fixture
//
// these types are expanded by the REAL compiler through the external macro
// plugin (not the in-process expansion harness), so the generated adapter is
// genuinely type-checked against the merged vocabulary (`Continuum.swift` in
// WebUISharedCore, surfaced through `WebUI`'s re-export chain): an unknown
// member or a drift in the seam types is a compile error here, and the runtime
// tests in `ContinuumFixtureTests.swift` exercise the generated witness against
// the hand-written equivalent.

/// the fixture state — a label and a counter, the feed item's shape in miniature.
struct CounterState: HotState, Equatable {
	var label: String
	var count: Int
}

/// the fixture action set. `setLabel` carries an effect (the control-plane
/// `log`) so the adapter's effect forwarding is observable.
enum CounterAction: HotAction {
	case setLabel(String)
	case increment
	case decrement
}

@HotView("counter", imports: [ClockCapability.self], budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096))
@HotClass("counter", "counter__label")
struct MacroCounter: HotView {
	typealias State = CounterState
	typealias Action = CounterAction

	@HotBuilder func render(state: State) -> HotTree {
		Hot.Container(id: "counter", tag: "div", className: "counter") {
			Hot.Text(id: "counter-label", state.label)
			Hot.Spacer()
			if state.count > 0 {
				Hot.Text(id: "counter-count", "count: \(state.count)")
			}
		}
	}

	static func reduce(state: inout State, action: Action) -> [HotEffect] {
		switch action {
		case .setLabel(let label):
			state.label = label
			return [.log("label: \(label)")]
		case .increment:
			state.count += 1
			return []
		case .decrement:
			state.count -= 1
			return []
		}
	}
}