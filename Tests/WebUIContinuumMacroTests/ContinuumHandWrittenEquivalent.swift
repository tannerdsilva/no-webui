import WebUI
import WebUIIslandCore

// MARK: - the hand-written equivalent (anti-shackle rule 3)
//
// `HandCounter` mirrors `MacroCounter` exactly — the same state/action types,
// the same body built as explicit `HotTree` values (no `@HotBuilder`), the same
// `reduce` — and `HandCounterIsland` + the descriptor + the server conformance
// hand-write what `@HotView` generates. `ContinuumFixtureTests` proves the two
// generations produce identical html + ops for the same state.

struct HandCounter: HotView {
	typealias State = CounterState
	typealias Action = CounterAction

	/// the hand-built tree: the same structure the builder produces, verbatim.
	func render(state: State) -> HotTree {
		HotTree.container(id: "counter", tag: "div", className: "counter", children: [
			.text(id: "counter-label", content: state.label),
			.spacer,
			state.count > 0 ? .text(id: "counter-count", content: "count: \(state.count)") : .empty,
		])
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

extension HandCounter: ContinuumServerPath {
	static let continuumDescriptor = ContinuumDescriptor(
		name: "counter",
		grants: [ClockCapability.self],
		budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096),
		className: "counter counter__label"
	)
}

struct HandCounterIsland: ContinuumIsland {
	typealias State = HandCounter.State
	typealias Action = HandCounter.Action
	static var name: String { "counter" }
	static var imports: [any HostCapability.Type] { [ClockCapability.self] }
	static var budget: IslandBudget { IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096) }

	// DX-9 (CONTINUUM_DX §2.9): the hand-written mirror of the macro-emitted
	// element-id vocabulary (the ProbeIslandIDs pattern, hand-kept). the
	// equivalence suite diffs it against `MacroCounter.MacroCounterIsland
	// .elementIDs`.
	static let elementIDs: Set<ElementID> = [
		ElementID("counter"),
		ElementID("counter-count"),
		ElementID("counter-label"),
	]

	static func reduce(state: inout State, action: Action) -> [HotEffect] {
		HandCounter.reduce(state: &state, action: action)
	}

	// the hand-written codec entries (the macro emits the same bodies): the
	// W3 swap — read the BOUND runtime instance through lane C's accessors
	// (`IslandRuntime<HandCounterIsland>.encodedState()` / `.decodePendingOps()`).
	// on host builds nothing is ever bound, so both report the drained
	// contract ([] / no effects) — exactly the macro generation's reading.
	static func _continuumEncode() -> [UInt8] {
		IslandRuntime<HandCounterIsland>.encodedState()
	}

	static func _continuumDecode() -> [HotEffect] {
		IslandRuntime<HandCounterIsland>.decodePendingOps()
	}
}

// MARK: - the same author-supplied surface path as the macro fixture (W3 swap) —
//
// `IslandRuntime<HandCounterIsland>` requires `I: IslandRuntimeSurface`; the
// hand-written island supplies the four hooks mirroring `MacroCounterIsland`'s
// (anti-shackle: the two generations carry the SAME surface + bodies, so the
// runtime-accessor spell compiles for both and they agree on the drained
// contract).
extension HandCounterIsland: IslandRuntimeSurface {
	static func decodeEvent(json: String) -> CounterAction {
		MacroCounter.MacroCounterIsland.decodeEvent(json: json)
	}

	static func regionHTML(state: CounterState, renderCount: Int, eventCount: Int) -> String {
		MacroCounter.MacroCounterIsland.regionHTML(state: state, renderCount: renderCount, eventCount: eventCount)
	}

	static func stateToJSON(state: CounterState, renderCount: Int, eventCount: Int) -> JSONValue {
		MacroCounter.MacroCounterIsland.stateToJSON(state: state, renderCount: renderCount, eventCount: eventCount)
	}

	static func stateFromJSON(_ json: String) -> (state: CounterState, renderCount: Int, eventCount: Int)? {
		MacroCounter.MacroCounterIsland.stateFromJSON(json)
	}
}
