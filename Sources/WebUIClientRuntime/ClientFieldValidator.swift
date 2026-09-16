import Foundation

// p5-t2: client-side form validation — the same validation runs in wasm
// (near-zero latency, field-level feedback) while the server re-validates on
// authority. checks are pure swift (no NSRegularExpression on wasm): manual
// character iteration, like the framework's escaping code.

/// a validation rule (declarative, both hosts).
public enum ClientValidationRule: Sendable, Equatable {
	case required
	case minLength(Int)
	case maxLength(Int)
	case email
	case contains(String)

	var key: String {
		switch self {
		case .required: return "required"
		case .minLength: return "minLength"
		case .maxLength: return "maxLength"
		case .email: return "email"
		case .contains: return "contains"
		}
	}
}

/// runs rules against a value; returns the FIRST failing message or nil.
public struct ClientFieldValidator: Sendable {
	public let rules: [ClientValidationRule]

	public init(rules: [ClientValidationRule]) {
		self.rules = rules
	}

	public func validate(_ value: String) -> String? {
		for rule in rules {
			if let message = Self.failure(rule, value: value) {
				return message
			}
		}
		return nil
	}

	public static func failure(_ rule: ClientValidationRule, value: String) -> String? {
		switch rule {
		case .required:
			return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this field is required" : nil
		case .minLength(let minimum):
			return value.count < minimum ? "at least \(minimum) characters" : nil
		case .maxLength(let maximum):
			return value.count > maximum ? "at most \(maximum) characters" : nil
		case .email:
			return isPlausibleEmail(value) ? nil : "enter a valid email address"
		case .contains(let needle):
			return value.contains(needle) ? nil : "must contain \"\(needle)\""
		}
	}

	/// a deliberately structural check — one `@`, no ascii whitespace, a dot
	/// after the `@`, and a non-empty local part. no regex, wasm-clean.
	public static func isPlausibleEmail(_ value: String) -> Bool {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let at = trimmed.firstIndex(of: "@") else { return false }
		let local = trimmed[..<at]
		let domain = trimmed[trimmed.index(after: at)...]
		guard !local.isEmpty, !domain.isEmpty else { return false }
		guard domain.contains(".") else { return false }
		return !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
	}
}
