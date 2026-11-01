// MARK: - ActionPart

/// one reversible payload slot in an action identity.
///
/// a slot is written **literally** when its text is already url-safe
/// (`[a-z0-9-]+`) and **escaped** otherwise, so a wire id stays readable
/// wherever readability costs nothing:
///
///     storage~edit~conn-1            // both slots literal
///     storage~edit~@Y29ubi8xKzI      // the id needed escaping
///     storage~edit~.                 // the empty value
///
/// the alphabet is what makes the two forms unambiguous: `@` and `.` are
/// outside `[a-z0-9-]`, and ``ActionKey/separator`` is `~`, so a segment's
/// first character decides its kind with no extra flag on the wire.
public struct ActionPart: Sendable, Hashable, CustomStringConvertible {
	/// the sentinel an empty value writes. `.` is outside the literal alphabet
	/// and outside the escaped one, so it reads back as `""` and cannot collide.
	fileprivate static let emptySentinel = "."

	/// the marker an escaped value carries. `@` is outside the literal
	/// alphabet, so a literal can never be mistaken for an escaped value.
	fileprivate static let escapedMarker: Character = "@"

	/// the wire text of this slot: literal, `@`+base64url, or `.`.
	public let encoded: String

	public init(_ value: String) {
		if value.isEmpty {
			self.encoded = Self.emptySentinel
		} else if value.allSatisfy(Self.isLiteral) {
			self.encoded = value
		} else {
			self.encoded = String(Self.escapedMarker) + Base64.encodeURL(Array(value.utf8))
		}
	}

	/// the decode door, for ``ActionKey/init?(wireID:)`` only: it takes a
	/// segment already split off the wire, never a hand-encoded value.
	fileprivate init(encoded: String) {
		self.encoded = encoded
	}

	/// whether one character may appear in a literal slot.
	private static func isLiteral(_ c: Character) -> Bool {
		guard let a = c.asciiValue else { return false }
		return (a >= 97 && a <= 122) || (a >= 48 && a <= 57) || a == 45   // a-z 0-9 -
	}

	/// the value, or `nil` when the segment is neither literal, sentinel, nor
	/// valid escaped utf8.
	public var decoded: String? {
		if encoded == Self.emptySentinel { return "" }
		if let first = encoded.first, first == Self.escapedMarker {
			let body = String(encoded.dropFirst())
			guard let bytes = Base64.decodeURL(body) else { return nil }
			return String(validating: bytes, as: UTF8.self)
		}
		guard !encoded.isEmpty, encoded.allSatisfy(Self.isLiteral) else { return nil }
		return encoded
	}

	public var description: String { encoded }
}

// MARK: - ActionKey

/// the wire identity of one action: a family plus its ordered slots.
///
/// both halves of the wire come from this one value — the view side emits
/// ``wireID`` and the router splits the same string — so the attribute and the
/// handler cannot disagree about what a control means.
public struct ActionKey: Sendable, Hashable, CustomStringConvertible {
	/// `~` is outside the base64url alphabet and outside every family name.
	public static let separator: Character = "~"

	/// `[a-z0-9-]+`, never contains ``separator``.
	public let family: String
	public let parts: [ActionPart]

	public init(_ family: String, _ parts: [ActionPart] = []) {
		self.family = family
		self.parts = parts
	}

	/// `family` alone when there are no slots, `family~slot~slot` otherwise.
	///
	/// a payload-free id is byte-identical to the id a page spells by hand
	/// today (`storage-edit`), which is what lets exact-id dispatch keep
	/// routing every existing control unchanged.
	public var wireID: String {
		guard !parts.isEmpty else { return family }
		var out = family
		for part in parts {
			out.append(Self.separator)
			out.append(part.encoded)
		}
		return out
	}

	/// the total inverse of ``wireID`` over every frame the framework can mint.
	///
	/// `nil` is reserved for a frame the client could not have produced — an
	/// empty string, an empty family, an empty slot — and the router drops one
	/// at the existing `.debug` funnel rather than guessing at it.
	public init?(wireID: String) {
		guard !wireID.isEmpty else { return nil }
		let segments = wireID.split(separator: Self.separator, omittingEmptySubsequences: false)
		guard let head = segments.first, !head.isEmpty else { return nil }
		// `head` can never contain the separator: the split consumed every one,
		// so the family this returns is `[a-z0-9-]+` by construction. an id whose
		// family was spelled with a `~` is indistinguishable from one whose first
		// slot was — a family is spelled at the declaration, and this side only
		// ever reads an exact split.
		var parts: [ActionPart] = []
		parts.reserveCapacity(segments.count - 1)
		for segment in segments.dropFirst() {
			guard !segment.isEmpty else { return nil }
			parts.append(ActionPart(encoded: String(segment)))
		}
		self.init(String(head), parts)
	}

	public var description: String { wireID }
}

// MARK: - Action

/// the wire identity of one control kind, decodable into a typed value.
///
/// a family names the control kind and registers once; the first slot names the
/// verb and the rest is the payload, so one exhaustive `switch` in the handler
/// covers every verb the family will ever carry.
public protocol Action: Sendable, Hashable {
	/// the family the router registers under; `[a-z0-9-]+`.
	static var family: String { get }
	/// the slots that distinguish one instance from another. default: none.
	var parts: [ActionPart] { get }
	/// decode the frame that named this family, or `nil` when this type does not
	/// model it. `event` carries the form payload for a submit-borne action.
	init?(key: ActionKey, event: EventData)
}

extension Action {
	/// this action's wire identity.
	public var key: ActionKey { ActionKey(Self.family, parts) }

	/// payload-free families say nothing.
	public var parts: [ActionPart] { [] }
}
