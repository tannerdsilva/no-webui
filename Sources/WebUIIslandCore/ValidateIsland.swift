import WebUISharedCore

// MARK: - Validate capability island
//
// the same swift validation logic the server/authority runs
// (`ClientFieldValidator`), compiled into a small standalone wasm module
// (next architecture d3). the engine lazily fetches the artifact when a page
// declares the `validate` capability, calls `webui_render_region` /
// `webui_validate`, and applies the result locally — no round trip.
//
// CONTINUUM_DX DX-2: this file is the LOGIC HOME and the concrete island type
// for the shared runtime slice (`WebUIIslandCore/IslandRuntime.swift`). the
// wasm executable's `Main.swift` is a slim shim (`webui_island_bind` +
// the `webui_validate` extra export); this type provides the
// `IslandRuntimeSurface` conformance the runtime parameterizes over. the d3
// rule-evaluator funcs (`decodeRules` / `evaluate` / `regionHTML(argsJSON:)`)
// are unchanged and stay the natively-tested logic home.

// MARK: - the validate island's retained state

/// the validate island's retained state: the args payload (`{"value", rules}`)
/// the mount envelope carried. the region html is derived from it (the mount
/// args are folded in via `consumeMountEnvelope`, the runtime's additive mount
/// hook), so a remount/restore re-renders the same verdict without a fresh
/// `webui_validate` round trip.
public struct ValidateState: HotState {
	public var argsJSON: String

	public init() {
		argsJSON = ""
	}

	public init(argsJSON: String) {
		self.argsJSON = argsJSON
	}
}

#if !hasFeature(Embedded)
extension ValidateState: Codable {}
#endif

/// the runtime's empty-state refinement: validate constructs a fresh empty
/// state on instantiation (the reactor needs one before any mount).
extension ValidateState: IslandEmptyState {}

// MARK: - the validate island's action space

/// validate is a pure rule evaluator, not an op-emitting reducer: the
/// standard event path (`webui_on_event`) has no vocabulary, so every action
/// reduces to `.noop` and the op stream stays empty (the d3 output is the
/// region html / the `webui_validate` verdict, never a DOM delta).
public enum ValidateAction: HotAction, Equatable {
	case noop
}

#if !hasFeature(Embedded)
extension ValidateAction: Codable {}
#endif

// MARK: - the concrete island (ContinuumIsland + IslandRuntimeSurface)

/// decode a rules array from js object form:
/// `{"rules":[{"rule":"required"},{"rule":"minLength","arg":3},{"rule":"email"}]}`
/// returns nil on malformed input (the caller degrades to server-authoritative).
public enum ValidateIsland: ContinuumIsland, IslandRuntimeSurface {
	public typealias State = ValidateState
	public typealias Action = ValidateAction

	public static var name: String { "validate" }

	// the validate capability imports no host functions (the hand-written main
	// declared none; the engine's mount is input-buffer-only).
	public static var imports: [any HostCapability.Type] { [] }

	public static var budget: IslandBudget {
		// deliberately conservative: the runtime slice + slim main move the
		// artifact within the kB tier (was 164,447 stripped pre-conversion);
		// measured post-conversion in c-docs.md.
		IslandBudget(maxBytes: 200_000, maxGzipBytes: 90_000)
	}

	// MARK: reduce (inert — validate emits no ops)

	/// every action is a no-op: the d3 surface has no DOM-delta vocabulary.
	public static func reduce(state: inout ValidateState, action: ValidateAction) -> [HotEffect] {
		_ = (state, action)
		return []
	}

	// MARK: IslandRuntimeSurface hooks

	/// the standard event path has no vocabulary for a rule evaluator — any
	/// engine-dispatched event reduces to `.noop` (drain stays empty).
	public static func decodeEvent(json: String) -> ValidateAction {
		_ = json
		return .noop
	}

	/// the region html for the retained args payload — delegates to the d3
	/// logic home, so the mounted bytes are identical to the hand-written
	/// `regionHTML(argsJSON:)` for the same args.
	public static func regionHTML(state: ValidateState, renderCount: Int, eventCount: Int) -> String {
		_ = (renderCount, eventCount)
		return regionHTML(argsJSON: state.argsJSON)
	}

	/// the full retained snapshot — the args payload plus the reactor counters
	/// — so a region replace (`webui_state_save` / `webui_state_restore`)
	/// re-renders the same verdict.
	public static func stateToJSON(state: ValidateState, renderCount: Int, eventCount: Int) -> JSONValue {
		.object([
			"validate": .object([
				"args": .string(state.argsJSON),
			]),
			"renderCount": .number(Double(renderCount)),
			"eventCount": .number(Double(eventCount)),
		])
	}

	/// rebuilds the retained state from a `webui_state_restore` payload.
	/// malformed snapshots return nil (the caller keeps the live state).
	public static func stateFromJSON(_ json: String) -> (state: ValidateState, renderCount: Int, eventCount: Int)? {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root,
		      case .object(let validateDict)? = dict["validate"],
		      case .string(let args)? = validateDict["args"] else {
			return nil
		}
		var state = ValidateState()
		state.argsJSON = args
		var renderCount = 0
		var eventCount = 0
		if case .number(let n)? = dict["renderCount"] { renderCount = Int(n) }
		if case .number(let n)? = dict["eventCount"] { eventCount = Int(n) }
		return (state, renderCount, eventCount)
	}

	// MARK: the additive mount hook (DX-2, documented)

	/// the runtime's additive mount hook: `webui_render_region` hands the
	/// decoded `{name, args}` envelope here before rendering, so an
	/// args-derived island can fold it into its retained state. mirrors the
	/// hand-written main's envelope unwrap byte-for-byte: a mount envelope with
	/// an `args` key retains the serialized args; anything else retains the raw
	/// json (the caller degraded to server-authoritative on malformed mounts).
	public static func consumeMountEnvelope(_ envelopeJSON: String, state: inout ValidateState) {
		if let root = try? JSONValue.parse(envelopeJSON),
		   case .object(let dict) = root,
		   let argsValue = dict["args"] {
			state.argsJSON = argsValue.serialize()
		} else {
			state.argsJSON = envelopeJSON
		}
	}

	// MARK: the webui_validate input→output contract

	/// the response payload `webui_validate` writes: `{"ok":<bool>,
	/// "message":"<escaped>"}`. byte-identical to the hand-written main's
	/// inline template (the input→output contract is frozen).
	public static func validationResponse(json: String) -> String {
		let result = evaluate(json: json)
		return "{\"ok\":\(result.ok),\"message\":\"\(JSONValue.escapeString(result.message))\"}"
	}

	// MARK: - d3 rule-evaluator logic home (unchanged)

	/// decode a rules array from js object form:
	/// `{"rules":[{"rule":"required"},{"rule":"minLength","arg":3},{"rule":"email"}]}`
	/// returns nil on malformed input (the caller degrades to server-authoritative).
	public static func decodeRules(json: String) -> [ClientValidationRule]? {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root,
		      case .array(let entries)? = dict["rules"] else { return nil }
		var rules: [ClientValidationRule] = []
		for entry in entries {
			guard case .object(let obj) = entry,
			      case .string(let kind)? = obj["rule"] else { return nil }
			let kindScalars = Array(kind.unicodeScalars)
			func matches(_ literal: String) -> Bool {
				kindScalars.elementsEqual(literal.unicodeScalars)
			}
			if matches("required") {
				rules.append(.required)
			} else if matches("minLength") {
				guard let arg = intArgument(obj["arg"]) else { return nil }
				rules.append(.minLength(arg))
			} else if matches("maxLength") {
				guard let arg = intArgument(obj["arg"]) else { return nil }
				rules.append(.maxLength(arg))
			} else if matches("email") {
				rules.append(.email)
			} else if matches("contains") {
				guard case .string(let needle)? = obj["arg"] else { return nil }
				rules.append(.contains(needle))
			} else {
				return nil
			}
		}
		return rules
	}

	/// evaluate `{"value": "...", "rules":[...]}`; returns the first failing
	/// rule's message (or `("", true)` when every rule passes).
	public static func evaluate(json: String) -> (ok: Bool, message: String) {
		guard let root = try? JSONValue.parse(json),
		      case .object(let dict) = root else {
			return (false, "invalid request")
		}
		let value: String
		if case .string(let v)? = dict["value"] {
			value = v
		} else {
			value = ""
		}
		guard let rules = rules(from: dict["rules"]) else {
			return (false, "unknown rules")
		}
		let validator = ClientFieldValidator(rules: rules)
		if let message = validator.validate(value) {
			return (false, message)
		}
		return (true, "")
	}

	/// the region html emitted for a `data-webui-args` json payload — stamped
	/// with `role="status"` so the live result is announced.
	public static func regionHTML(argsJSON: String) -> String {
		let result = evaluate(json: argsJSON)
		let stateClass = result.ok ? "island--ok" : "island--error"
		let text = result.ok ? "valid" : (result.message.isEmpty ? "not valid" : result.message)
		return "<div class=\"island island--validate \(stateClass)\" role=\"status\">"
			+ "<span class=\"island__dot\"></span>"
			+ "<span class=\"island__msg\">\(htmlEscape(text))</span>"
			+ "</div>"
	}

	private static func rules(from value: JSONValue?) -> [ClientValidationRule]? {
		guard let value else { return [] }
		let json = value.serialize()
		return decodeRules(json: "{\"rules\":\(json)}")
	}

	private static func intArgument(_ value: JSONValue?) -> Int? {
		if case .number(let n)? = value { return Int(n) }
		if case .string(let s)? = value { return Int(s) }
		return nil
	}
}
