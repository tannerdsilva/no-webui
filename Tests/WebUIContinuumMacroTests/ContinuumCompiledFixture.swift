import WebUI
import WebUIIslandCore

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

/// the empty-state refinement the runtime surface requires — the author
/// declares `init()` (a fresh counter, the ProbeIsland/FeedState pattern).
extension CounterState: IslandEmptyState {
	init() { self.init(label: "", count: 0) }
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

// MARK: - the swap's surface-conforming path (CONTINUUM_DX W3 · c-to-d.md
// addendum item 3)
//
// the generated `_continuumEncode`/`_continuumDecode` bodies now read the BOUND
// runtime instance through `IslandRuntime<MacroCounter.MacroCounterIsland>
// .encodedState()` / `.decodePendingOps()` (d-to-c.md W3). lane C judged the
// `I: IslandRuntimeSurface` constraint NOT relaxable (byte-risky for the
// size-exact probe anchor), so the spell only type-checks once the adapter
// satisfies the surface — and the macro cannot synthesize the four hooks for
// an arbitrary author state. the FIXTURE therefore supplies them, exactly the
// template-feed shape (a wasm-bound generated island needs the AUTHOR's
// surface conformance; the acceptance template's hand-written FeedIsland is
// the real-world instance of this path).
extension MacroCounter.MacroCounterIsland: IslandRuntimeSurface {
	// MARK: events in — `{type, key, data}` v1, probe-shaped

	static func decodeEvent(json: String) -> CounterAction {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root,
		      case .string(let type)? = dict["type"],
		      scalarEquals(type, "click"),
		      case .string(let key)? = dict["key"] else {
			return .increment // an unexercised control-plane default (see below)
		}
		if scalarEquals(key, "counter-increment") { return .increment }
		if scalarEquals(key, "counter-decrement") { return .decrement }
		return .increment
	}

	// MARK: mount html — same shape the @HotBuilder tree renders

	static func regionHTML(state: CounterState, renderCount: Int, eventCount: Int) -> String {
		var html = "<div id=\"counter\" class=\"counter\" data-island-state=\"mounted\""
		html += " data-island-renders=\"\(renderCount)\" data-island-events=\"\(eventCount)\">"
		html += "<span id=\"counter-label\">\(htmlEscape(state.label))</span>"
		html += "<div class=\"spacer\" style=\"flex:1\"></div>"
		if state.count > 0 {
			html += "<span id=\"counter-count\">count: \(state.count)</span>"
		}
		html += "</div>"
		return html
	}

	// MARK: state channel — full retained snapshot (label + counter + counters)

	static func stateToJSON(state: CounterState, renderCount: Int, eventCount: Int) -> JSONValue {
		.object([
			"counter": .object([
				"label": .string(state.label),
				"count": .number(Double(state.count)),
			]),
			"renderCount": .number(Double(renderCount)),
			"eventCount": .number(Double(eventCount)),
		])
	}

	static func stateFromJSON(_ json: String) -> (state: CounterState, renderCount: Int, eventCount: Int)? {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root,
		      case .object(let counter)? = dict["counter"] else {
			return nil
		}
		var state = CounterState()
		if case .string(let label)? = counter["label"] { state.label = label }
		if case .number(let n)? = counter["count"] { state.count = Int(n) }
		var renderCount = 0
		var eventCount = 0
		if case .number(let n)? = dict["renderCount"] { renderCount = Int(n) }
		if case .number(let n)? = dict["eventCount"] { eventCount = Int(n) }
		return (state, renderCount, eventCount)
	}

	// MARK: scalar-clean literal comparison (the ProbeIsland discipline)

	static func scalarEquals(_ value: String, _ literal: String) -> Bool {
		value.unicodeScalars.elementsEqual(literal.unicodeScalars)
	}

	static func htmlEscape(_ value: String) -> String {
		var out = ""
		for scalar in value.unicodeScalars {
			switch scalar {
			case "<": out += "&lt;"
			case ">": out += "&gt;"
			case "&": out += "&amp;"
			case "\"": out += "&quot;"
			default: out.unicodeScalars.append(scalar)
			}
		}
		return out
	}
}
