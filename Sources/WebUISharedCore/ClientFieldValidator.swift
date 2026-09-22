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
			return Self.trimmed(value).isEmpty ? "this field is required" : nil
		case .minLength(let minimum):
			return value.unicodeScalars.count < minimum ? "at least \(minimum) characters" : nil
		case .maxLength(let maximum):
			return value.unicodeScalars.count > maximum ? "at most \(maximum) characters" : nil
		case .email:
			return isPlausibleEmail(value) ? nil : "enter a valid email address"
		case .contains(let needle):
			return Self.contains(value, needle) ? nil : "must contain \"\(needle)\""
		}
	}

	/// a deliberate structural check — one `@`, no ascii whitespace, a dot
	/// after the `@`, and a non-empty local part. no regex, wasm-clean, and
	/// scalar-level (the embedded stdlib omits grapheme-break tables).
	public static func isPlausibleEmail(_ value: String) -> Bool {
		let scalars = Array(Self.trimmed(value).unicodeScalars)
		guard let at = scalars.firstIndex(where: { $0.value == 0x40 }) else { return false }
		let local = scalars[..<at]
		let domain = scalars[scalars.index(after: at)...]
		guard !local.isEmpty, !domain.isEmpty else { return false }
		guard domain.contains(where: { $0.value == 0x2E }) else { return false }
		return !scalars.contains(where: { Self.isWhitespaceOrNewline($0) })
	}

	/// `.whitespacesAndNewlines` membership, hand-rolled — the wasm build has
	/// no Foundation, and these are exactly the scalars that set contains
	/// (verified against the macOS set: tab..CR, space, NEL, nbsp, ogham
	/// space, en..hair + zero-width space, line/paragraph sep, narrow nbsp,
	/// math space, ideographic space).
	private static func isWhitespaceOrNewline(_ scalar: Unicode.Scalar) -> Bool {
		switch scalar.value {
		case 0x09...0x0D, 0x20, 0x85, 0xA0,
		     0x1680, 0x2000...0x200B, 0x2028...0x2029, 0x202F, 0x205F, 0x3000:
			return true
		default:
			return false
		}
	}

	/// `trimmingCharacters(in: .whitespacesAndNewlines)`, hand-rolled at the
	/// scalar level — Foundation trims by scalar membership, so a CRLF
	/// grapheme (one Character, two scalars) must still trim whole.
	private static func trimmed(_ value: String) -> String {
		let scalars = Array(value.unicodeScalars)
		var start = 0
		var end = scalars.count
		while start < end, isWhitespaceOrNewline(scalars[start]) { start += 1 }
		while end > start, isWhitespaceOrNewline(scalars[end - 1]) { end -= 1 }
		if start == 0, end == scalars.count { return value }
		return String(String.UnicodeScalarView(scalars[start..<end]))
	}

	/// substring membership without `firstRange(of:)`/`contains(_:)` — the
	/// embedded stdlib drops the range-returning String API entirely. scalar
	/// comparison (single-source parity holds: the same code runs on host).
	private static func contains(_ value: String, _ needle: String) -> Bool {
		if needle.unicodeScalars.isEmpty { return true }
		let h = Array(value.unicodeScalars)
		let n = Array(needle.unicodeScalars)
		if n.count > h.count { return false }
		var i = 0
		while i <= h.count - n.count {
			var j = 0
			while j < n.count, h[i + j] == n[j] { j += 1 }
			if j == n.count { return true }
			i += 1
		}
		return false
	}
}
