// MARK: - DesignToken as a coding key

/// `[DesignToken: String]` is a theme palette, and the natural JSON for it is an object
/// keyed by token name — `{"color-bg": "#fff"}`. Swift only produces that shape for keys
/// that are `CodingKeyRepresentable`; a bare `RawRepresentable<String>` enum encodes as a
/// flat array of alternating keys and values instead, which is both larger and unreadable
/// in a diff. This conformance is what makes a shipped catalog legible.
/// A token encodes as its **css name** (`"color-bg"`), which is what the stylesheet uses and
/// what a hand-written theme file would say. The conformance is explicit rather than
/// synthesized because `DesignToken` is generated into another file, and synthesis is only
/// available in the declaring file.
///
/// An unknown name **throws** rather than being dropped. A catalog that names a token this
/// build does not have is either a typo or a version skew, and silently discarding that
/// theme value would render as a missing colour with no diagnostic anywhere.
extension DesignToken: Codable {
	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let raw = try container.decode(String.self)
		guard let token = DesignToken(rawValue: raw) else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "unknown design token '\(raw)' — is the catalog from a newer build?"
			)
		}
		self = token
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}
}

extension DesignToken: CodingKeyRepresentable {
	public var codingKey: any CodingKey { TokenCodingKey(stringValue: rawValue) }
	public init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }
}

private struct TokenCodingKey: CodingKey {
	let stringValue: String
	var intValue: Int? { nil }
	init(stringValue: String) { self.stringValue = stringValue }
	init?(intValue: Int) { nil }
}
