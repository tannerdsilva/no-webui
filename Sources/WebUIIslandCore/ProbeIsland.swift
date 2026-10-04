import WebUISharedCore

// MARK: - the stateful probe island (DESKTOP_GRADE t2.5, wave 2)
//
// the wave-1 skeleton becomes real: a typed `ContinuumIsland` — a counter plus
// a small keyed list — whose `reduce` is pure and placement-free (runs inside
// wasm in production and in native unit tests), whose events decode from the
// engine's `{type, key, data}` v1 payload, and whose state round-trips through
// JSONValue for `webui_state_save` / `webui_state_restore`.
//
// scalar-clean for the embedded wasm runtime, like everything in this target:
// no Foundation, no `Character(...)` by-value construction, no
// `String(decoding:as:)`; literal comparisons go through `unicodeScalars`
// equality so canonical-equivalence normalization tables are never required
// (the same discipline `ValidateIsland` uses for its rule-kind literals).

/// one entry in the probe's keyed list. keys are assigned by `reduce`
/// (`"k0"`, `"k1"`, …) so the region's element ids stay stable across events.
public struct ProbeListItem: Equatable, Sendable {
	public var key: String
	public var value: String

	public init(key: String, value: String) {
		self.key = key
		self.value = value
	}
}

/// the probe's typed state: a counter plus a small keyed list.
public struct ProbeState: HotState {
	public var counter = 0
	public var items: [ProbeListItem] = []
	/// the next `"k<n>"` key to assign — survives serialization so a remount
	/// never reuses a key.
	public var nextItemKey = 0

	public init() {}
}

#if !hasFeature(Embedded)
extension ProbeState: Codable {}
extension ProbeListItem: Codable {}
#endif

/// the probe's typed actions. mapped from the engine's `{type, key, data}` v1
/// payload by `ProbeIsland.decodeEvent`; reduced to ops by `ProbeIsland.reduce`.
public enum ProbeAction: HotAction, Equatable {
	case increment(Int)
	case decrement(Int)
	case addItem(String)
	case clear
	case noop
}

#if !hasFeature(Embedded)
extension ProbeAction: Codable {}
#endif

/// the element ids the probe's render and reduce agree on — the ops emitted by
/// `reduce` patch exactly the ids `regionHTML` stamps.
public enum ProbeIslandIDs {
	public static let counter = "probe-counter"
	public static let list = "probe-list"
	public static func item(_ key: String) -> String { "probe-item-\(key)" }
}

/// the typed probe island — a hand-written `ContinuumIsland` (the "one
/// hand-written equivalent" rule, §9) and the wasm executable's logic core.
public enum ProbeIsland: ContinuumIsland {
	public typealias State = ProbeState
	public typealias Action = ProbeAction

	public static var name: String { "probe" }
	public static var imports: [any HostCapability.Type] {
		[InputSubscription.self, StatePersistence.self]
	}
	public static var budget: IslandBudget {
		// wave-3 (t4.2): the parity corpus + webui_run_corpus export grew the
		// artifact to 218,611 B raw / 95,215 B gzip — the deliberate re-pin
		// (was 200,000/90,000 at i2). numbers + reasoning in c-docs.md.
		IslandBudget(maxBytes: 240_000, maxGzipBytes: 105_000)
	}

	// MARK: pure reduce

	/// the pure reducer: applies the action to the (inout) state and returns the
	/// steady-state ops the engine must apply. no effects other than ops in the
	/// probe's wave-2 surface — `.save`/`.log` arrive with d5's backend.
	public static func reduceOps(state: inout ProbeState, action: ProbeAction) -> [HotOp] {
		var ops: [HotOp] = []
		switch action {
		case .increment(let delta):
			state.counter += delta
			ops.append(.text(ElementID(ProbeIslandIDs.counter), "\(state.counter)"))
		case .decrement(let delta):
			state.counter -= delta
			ops.append(.text(ElementID(ProbeIslandIDs.counter), "\(state.counter)"))
		case .addItem(let value):
			let key = "k\(state.nextItemKey)"
			state.nextItemKey += 1
			// insert html is sanitized once at the boundary (trust table §t2.3);
			// the value itself is escaped here so the mounted row is well-formed
			// even before the boundary sees it.
			let row = "<li id=\"\(ProbeIslandIDs.item(key))\" class=\"island__item\">\(htmlEscape(value))</li>"
			state.items.append(ProbeListItem(key: key, value: value))
			ops.append(.insert(parent: ElementID(ProbeIslandIDs.list), before: nil, html: row))
		case .clear:
			for item in state.items {
				ops.append(.remove(ElementID(ProbeIslandIDs.item(item.key))))
			}
			state.items.removeAll()
		case .noop:
			break
		}
		return ops
	}

	/// the `ContinuumIsland` requirement — pure, placement-free.
	public static func reduce(state: inout ProbeState, action: ProbeAction) -> [HotEffect] {
		let ops = reduceOps(state: &state, action: action)
		return ops.isEmpty ? [] : [.ops(ops)]
	}

	// MARK: events in

	/// decodes the engine's `{type, key, data}` v1 payload (t2.2) into a typed
	/// action. unknown or malformed payloads reduce to `.noop` — the island
	/// emits nothing and the engine's drain sees an empty stream.
	///
	/// recognized vocabulary (documented in c-docs.md / c-to-e.md):
	/// - `key` ArrowUp → increment(1) · ArrowDown → decrement(1)
	/// - `click` `probe-inc` → increment(1) · `probe-dec` → decrement(1) ·
	///   `probe-clear` → clear
	/// - `input` `probe-field` with a non-empty `data.value` → addItem(value)
	public static func decodeEvent(json: String) -> ProbeAction {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root,
		      case .string(let type)? = dict["type"] else {
			return .noop
		}
		let key: String?
		if case .string(let k)? = dict["key"] { key = k } else { key = nil }
		let data = dict["data"]

		if scalarEquals(type, "key") {
			guard let key else { return .noop }
			if scalarEquals(key, "ArrowUp") { return .increment(1) }
			if scalarEquals(key, "ArrowDown") { return .decrement(1) }
			return .noop
		}
		if scalarEquals(type, "click") {
			guard let key else { return .noop }
			if scalarEquals(key, "probe-inc") { return .increment(1) }
			if scalarEquals(key, "probe-dec") { return .decrement(1) }
			if scalarEquals(key, "probe-clear") { return .clear }
			return .noop
		}
		if scalarEquals(type, "input") {
			guard let key, scalarEquals(key, "probe-field") else { return .noop }
			if case .object(let d)? = data,
			   case .string(let value)? = d["value"],
			   !value.isEmpty {
				return .addItem(value)
			}
			return .noop
		}
		return .noop
	}

	// MARK: state channel

	/// the full retained snapshot — typed probe state plus the reactor's render
	/// and event counters — as a JSONValue. the counter and the keyed list
	/// survive a region remount (the RETAINED_OPEN precedent, generalized).
	public static func stateToJSON(state: ProbeState, renderCount: Int, eventCount: Int) -> JSONValue {
		var items: [JSONValue] = []
		items.reserveCapacity(state.items.count)
		for item in state.items {
			items.append(.object([
				"key": .string(item.key),
				"value": .string(item.value),
			]))
		}
		return .object([
			"probe": .object([
				"counter": .number(Double(state.counter)),
				"nextItemKey": .number(Double(state.nextItemKey)),
				"items": .array(items),
			]),
			"renderCount": .number(Double(renderCount)),
			"eventCount": .number(Double(eventCount)),
		])
	}

	/// builds the retained state back from a `webui_state_restore` payload.
	/// malformed snapshots return nil (the caller keeps the live state — a
	/// restore must never wipe progress on a bad byte stream).
	public static func stateFromJSON(_ json: String) -> (state: ProbeState, renderCount: Int, eventCount: Int)? {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root,
		      case .object(let probeDict)? = dict["probe"] else {
			return nil
		}
		var state = ProbeState()
		if case .number(let n)? = probeDict["counter"] { state.counter = Int(n) }
		if case .number(let n)? = probeDict["nextItemKey"] { state.nextItemKey = Int(n) }
		if case .array(let entries)? = probeDict["items"] {
			for entry in entries {
				guard case .object(let item) = entry,
				      case .string(let key)? = item["key"],
				      case .string(let value)? = item["value"] else { continue }
				state.items.append(ProbeListItem(key: key, value: value))
			}
		}
		var renderCount = 0
		var eventCount = 0
		if case .number(let n)? = dict["renderCount"] { renderCount = Int(n) }
		if case .number(let n)? = dict["eventCount"] { eventCount = Int(n) }
		return (state, renderCount, eventCount)
	}

	// MARK: mount html

	/// the region html for the current state. element ids are the ones
	/// `reduceOps` targets, so a mount + subsequent op stream stay consistent:
	/// the engine mounts this html, then applies only the delta ops.
	public static func regionHTML(state: ProbeState, renderCount: Int, eventCount: Int) -> String {
		var html = "<div class=\"island island--probe\" data-island-state=\"mounted\""
		html += " data-island-renders=\"\(renderCount)\" data-island-events=\"\(eventCount)\">"
		html += "<div class=\"island__row\">"
		html += "<button type=\"button\" id=\"probe-dec\" data-probe-action=\"dec\" aria-label=\"decrement\">−</button>"
		html += "<output id=\"\(ProbeIslandIDs.counter)\" class=\"island__counter\">\(state.counter)</output>"
		html += "<button type=\"button\" id=\"probe-inc\" data-probe-action=\"inc\" aria-label=\"increment\">+</button>"
		html += "<button type=\"button\" id=\"probe-clear\" data-probe-action=\"clear\">clear</button>"
		html += "</div>"
		html += "<input id=\"probe-field\" class=\"island__field\" data-island-input=\"probe-field\""
		html += " placeholder=\"add item…\" autocomplete=\"off\">"
		html += "<ul id=\"\(ProbeIslandIDs.list)\" class=\"island__list\">"
		for item in state.items {
			html += "<li id=\"\(ProbeIslandIDs.item(item.key))\" class=\"island__item\">\(htmlEscape(item.value))</li>"
		}
		html += "</ul>"
		html += "</div>"
		return html
	}

	// MARK: scalar-clean literal comparison

	/// canonical-equivalence-normalization-free equality against a compile-time
	/// literal — the comparison discipline every embedded-compiled literal
	/// match uses (mirrors `ValidateIsland`'s rule-kind matching).
	private static func scalarEquals(_ value: String, _ literal: String) -> Bool {
		value.unicodeScalars.elementsEqual(literal.unicodeScalars)
	}
}

// MARK: - the DX-1 runtime conformance (CONTINUUM_DX §2.1)
//
// ProbeIsland stays the "one hand-written equivalent" fixture; the runtime
// slice (`IslandRuntime.swift`) parameterizes over this surface. every hook
// (decodeEvent / regionHTML / stateToJSON / stateFromJSON) already exists as
// ProbeIsland's hand-written static func with EXACTLY the required signature —
// this conformance is the entire Delta-1 conversion, and the behavior is
// proven against the recorded probe fixtures by (a) the native runtime
// behavior-equivalence test and (b) c-ops.mjs 15/15 + c-parity 25/25 on the
// converted wasm artifact.
extension ProbeState: IslandEmptyState {}

extension ProbeIsland: IslandRuntimeSurface {}
