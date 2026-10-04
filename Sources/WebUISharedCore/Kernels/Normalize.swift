// MARK: - Normalizer / Lexer (t4.1, shared kernels)
//
// normalize + lex, the first kernel pair of the d4 shared-kernel surface.
// pure, generic, foundation-free — scalar-clean like every file in this
// leaf: both walk `unicodeScalars`, never `Character` grapheme clusters, so
// the embedded wasm runtime (which omits the grapheme-break tables) links
// them without touching the normalization symbols.
//
// case folding is deliberately ASCII-only. the embedded runtime does not
// carry the full unicode case-mapping tables, so a byte-for-byte
// deterministic fold across native ↔ island is only guaranteed for the
// ASCII range; non-ASCII letters pass through untouched (documented, not
// guessed — see the parity corpus note in KernelParity).

/// value type that rewrites a string for comparison/lookup: optional
/// whitespace trim, whitespace-run collapsing, and ASCII case folding.
/// the three switches are independent and default to on (`static let
/// basic`), so a hot path declares the exact recipe it wants.
public struct Normalizer: Sendable, Equatable {
	/// trim leading/trailing whitespace (space/tab/lf/cr).
	public var trim: Bool
	/// collapse any run of whitespace inside the string to a single space.
	public var collapseWhitespace: Bool
	/// ASCII case folding: `A…Z` → `a…z`. non-ASCII letters pass through.
	public var foldASCII: Bool

	public init(trim: Bool = true, collapseWhitespace: Bool = true, foldASCII: Bool = true) {
		self.trim = trim
		self.collapseWhitespace = collapseWhitespace
		self.foldASCII = foldASCII
	}

	/// the all-on recipe — the default hot path.
	public static let basic = Normalizer()

	/// the whitespace scalar set: space, tab, line feed, carriage return.
	public static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
		scalar.value == 0x20 || scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
	}

	/// the canonical form of `input` under this recipe.
	public func normalize(_ input: String) -> String {
		let scalars = input.unicodeScalars
		if scalars.isEmpty { return "" }

		// leading trim decision needs the first non-ws index.
		var start = scalars.startIndex
		if trim {
			while start < scalars.endIndex, Self.isWhitespace(scalars[start]) {
				start = scalars.index(after: start)
			}
			if start == scalars.endIndex { return "" }
		}

		var out = ""
		out.reserveCapacity(input.utf8.count)
		var index = start
		var pendingSpace = false
		while index < scalars.endIndex {
			let scalar = scalars[index]
			if Self.isWhitespace(scalar) {
				if collapseWhitespace {
					// a run collapses to one space; a trailing run is dropped
					// only when trim is on (the trim pass below).
					pendingSpace = true
				} else {
					out.unicodeScalars.append(scalar)
				}
				index = scalars.index(after: index)
				continue
			}
			if pendingSpace {
				out.unicodeScalars.append(" ")
				pendingSpace = false
			}
			out.unicodeScalars.append(foldASCII ? Self.fold(scalar) : scalar)
			index = scalars.index(after: index)
		}
		// a collapsed trailing run emits only when trim is off (mid-string only);
		// a trailing whitespace scalar run is stripped when trim is on, and a
		// collapsed pending run is emitted when trim is off. one tail, three
		// recipe outcomes — each pinned in KernelTests.
		if pendingSpace, !trim {
			out.unicodeScalars.append(" ")
		}
		if trim {
			while let last = out.unicodeScalars.last, Self.isWhitespace(last) {
				out.unicodeScalars.removeLast()
			}
		}
		return out
	}

	private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
		let v = scalar.value
		if v >= 0x41 && v <= 0x5A, let folded = Unicode.Scalar(v + 0x20) {
			return folded
		}
		return scalar
	}
}

/// the lex half: tokenizes a string by a caller-supplied membership
/// predicate over scalars. a pure static function with a narrow protocol —
/// the predicate handle is the only extension point, so token rules stay
/// explicit at the call site (and stay scalar-clean by construction).
public enum Lexer {
	/// split `input` into maximal runs of `isToken` scalars, in order.
	/// separators are any scalar outside the token set; runs are joined
	/// members, so "a--b" tokenizes as ["a", "b"] (no empty tokens).
	public static func tokens(in input: String, isToken: (Unicode.Scalar) -> Bool) -> [String] {
		var result: [String] = []
		var current = ""
		for scalar in input.unicodeScalars {
			if isToken(scalar) {
				current.unicodeScalars.append(scalar)
			} else if !current.isEmpty {
				result.append(current)
				current = ""
			}
		}
		if !current.isEmpty { result.append(current) }
		return result
	}

	/// ASCII alphanumeric + `_` + `-` — the default word token set.
	public static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
		let v = scalar.value
		return (v >= 0x30 && v <= 0x39)      // 0-9
			|| (v >= 0x41 && v <= 0x5A)      // A-Z
			|| (v >= 0x61 && v <= 0x7A)      // a-z
			|| v == 0x5F || v == 0x2D        // _ -
	}

	/// word tokens — the common default for the `isToken` handle.
	public static func words(in input: String) -> [String] {
		tokens(in: input, isToken: isWordScalar)
	}
}
