// MARK: - Key / ModifierSet / KeyEvent (t3.4, input parity primitives)
//
// the desktop-grade keyboard vocabulary — closed enums, wasm-visible, pure
// logic. lives in the zero-dep leaf so the island cores and the host surfaces
// agree on one shape. scalar-clean: literal comparison goes through
// `unicodeScalars.elementsEqual` (the ProbeIsland discipline), and `Key`
// never touches `Character` — printable keys carry a single-scalar String.
//
// placement note: `Key.identifier` is the canonical wire string — the same
// vocabulary lane E's `{type,key,data}` v1 events carry ("ArrowUp" etc.), so
// an engine→island key arrives as a String and round-trips through `Key`.
// parse never traps: unknown strings become `.unknown` (the island's
// decodeEvent already reduces unknown keys to `.noop`).

/// a keyboard key. closed vocabulary for everything the engine delivers; the
/// associated values carry the width-variant keys (function row, printable).
public enum Key: Sendable, Hashable, Equatable {
	case enter
	case tab
	case escape
	case backspace
	case delete
	case arrowUp
	case arrowDown
	case arrowLeft
	case arrowRight
	case home
	case end
	case pageUp
	case pageDown
	case space
	/// the function row, f1…f24. index outside 1…24 maps to `.unknown` on parse.
	case function(Int)
	/// one printable key as a single-unicode-scalar string (never a grapheme
	/// cluster — `Character` construction is embedded-unavailable).
	case printable(String)
	/// anything the vocabulary does not name (the never-trapping fallback).
	case unknown
}

/// keyboard modifiers as a bit set. `OptionSet` is stdlib arithmetic — pure,
/// scalar-clean, and placement-identical, so it rides the parity corpus.
public struct ModifierSet: OptionSet, Sendable, Hashable {
	public let rawValue: UInt16

	public init(rawValue: UInt16) {
		self.rawValue = rawValue
	}

	public static let shift = ModifierSet(rawValue: 1 << 0)
	public static let control = ModifierSet(rawValue: 1 << 1)
	/// the ⌥ (alt) key on this platform.
	public static let option = ModifierSet(rawValue: 1 << 2)
	/// the ⌘ (meta) key on this platform.
	public static let command = ModifierSet(rawValue: 1 << 3)
	public static let capsLock = ModifierSet(rawValue: 1 << 4)
	/// the fn key.
	public static let function = ModifierSet(rawValue: 1 << 5)
	public static let numLock = ModifierSet(rawValue: 1 << 6)
}

/// one key-down/key-up/repeat event as the engine delivers it.
public struct KeyEvent: Sendable, Equatable {
	public let key: Key
	public let modifiers: ModifierSet
	/// true when this is an OS auto-repeat, not a fresh press.
	public let isRepeat: Bool

	public init(key: Key, modifiers: ModifierSet, isRepeat: Bool = false) {
		self.key = key
		self.modifiers = modifiers
		self.isRepeat = isRepeat
	}
}

// MARK: - the wire vocabulary (Key ↔ identifier)

extension Key {
	/// the canonical wire string for this key — what `{type,key,data}` v1
	/// events carry and what the engine's composition forwarding forwards.
	/// frozen; parse must accept exactly these and nothing else.
	public var identifier: String {
		switch self {
		case .enter: return "Enter"
		case .tab: return "Tab"
		case .escape: return "Escape"
		case .backspace: return "Backspace"
		case .delete: return "Delete"
		case .arrowUp: return "ArrowUp"
		case .arrowDown: return "ArrowDown"
		case .arrowLeft: return "ArrowLeft"
		case .arrowRight: return "ArrowRight"
		case .home: return "Home"
		case .end: return "End"
		case .pageUp: return "PageUp"
		case .pageDown: return "PageDown"
		case .space: return "Space"
		case .function(let n): return "F\(n)"
		case .printable(let scalar): return scalar
		case .unknown: return "Unknown"
		}
	}

	/// parse a wire identifier into a `Key`. never traps: unmatched input is
	/// `.unknown`. the set mirrors `identifier` exactly (a round-trip invariant
	/// pinned in KernelTests + the parity corpus).
	public init(identifier: String) {
		switch (identifier) {
		case "Enter": self = .enter
		case "Tab": self = .tab
		case "Escape": self = .escape
		case "Backspace": self = .backspace
		case "Delete": self = .delete
		case "ArrowUp": self = .arrowUp
		case "ArrowDown": self = .arrowDown
		case "ArrowLeft": self = .arrowLeft
		case "ArrowRight": self = .arrowRight
		case "Home": self = .home
		case "End": self = .end
		case "PageUp": self = .pageUp
		case "PageDown": self = .pageDown
		case "Space": self = .space
		default:
			// function row: "F<n>" with 1…24.
			if let n = Self.parseFunctionRow(identifier) {
				self = .function(n)
			} else if identifier.unicodeScalars.count == 1, !identifier.unicodeScalars.isEmpty {
				self = .printable(identifier)
			} else {
				self = .unknown
			}
		}
	}

	/// "F<n>" → n (1…24 only); nil otherwise.
	private static func parseFunctionRow(_ text: String) -> Int? {
		let scalars = text.unicodeScalars
		guard scalars.count >= 2, scalars.first?.value == 0x46 else { return nil } // 'F'
		var n = 0
		for scalar in scalars.dropFirst() {
			let v = scalar.value
			guard v >= 0x30, v <= 0x39 else { return nil }
			n = n * 10 + Int(v - 0x30)
		}
		return (n >= 1 && n <= 24) ? n : nil
	}

	/// the printable scalar this key carries, when it has one (single-scalar
	/// printable only — `.space` and named keys return nil).
	public var printableScalar: Unicode.Scalar? {
		if case .printable(let text) = self, let first = text.unicodeScalars.first {
			return first
		}
		return nil
	}
}

// MARK: - Codable (host/full-stdlib surface only)

#if !hasFeature(Embedded)
extension Key: Codable {}
extension ModifierSet: Codable {}
extension KeyEvent: Codable {}
#endif
