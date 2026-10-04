import WebUI

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

	static func reduce(state: inout State, action: Action) -> [HotEffect] {
		HandCounter.reduce(state: &state, action: action)
	}

	// the hand-written codec entries (the macro emits the same bodies): the
	// drained-batch contract — the runtime slice owns retained state per wasm
	// instance, so the untethered surface reports an empty pending batch on the
	// record-v1 plane (HotOpCodec.encodeBatch of nothing / decode of the empty
	// record stream = truncatedRecord → no effects). the record loop is proven
	// real by ContinuumFixtureTests.codecRoundTrip.
	static func _continuumEncode() -> [UInt8] {
		(try? HotOpCodec.encodeBatch([])) ?? []
	}

	static func _continuumDecode() -> [HotEffect] {
		guard let op = try? HotOpCodec.decode([]) else { return [] }
		return [.ops([op])]
	}
}