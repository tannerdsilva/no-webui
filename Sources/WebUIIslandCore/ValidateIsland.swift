import WebUICore
import WebUIClientRuntime

// MARK: - Validate capability island
//
// the same swift validation logic the server/authority runs
// (`ClientFieldValidator`), compiled into a small standalone wasm module
// (next architecture d3). the engine lazily fetches the artifact when a page
// declares the `validate` capability, calls `webui_render_region` /
// `webui_validate`, and applies the result locally — no round trip.

public enum ValidateIsland {

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
			switch kind {
			case "required":
				rules.append(.required)
			case "minLength":
				guard let arg = intArgument(obj["arg"]) else { return nil }
				rules.append(.minLength(arg))
			case "maxLength":
				guard let arg = intArgument(obj["arg"]) else { return nil }
				rules.append(.maxLength(arg))
			case "email":
				rules.append(.email)
			case "contains":
				guard case .string(let needle)? = obj["arg"] else { return nil }
				rules.append(.contains(needle))
			default:
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
