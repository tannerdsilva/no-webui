// MARK: - ClipboardPayload (t3.4, input parity primitives)
//
// the tab-delimited interchange grids and editors share: a plain `text` form
// plus an optional `tsv` (tab-separated values) form. pure, wasm-visible,
// scalar-clean. the tsv ↔ rows split is deliberately naive (a cell containing
// a literal tab/newline is the caller's problem — escaping would make the
// round-trip non-invertible); the parity corpus pins the exact semantics.

public struct ClipboardPayload: Sendable, Equatable {
	/// the plain-text paste form.
	public var text: String
	/// the tabular interchange form, when the payload carries a table.
	public var tsv: String?

	public init(text: String, tsv: String? = nil) {
		self.text = text
		self.tsv = tsv
	}

	/// true when a tabular form is attached.
	public var hasTabularData: Bool { tsv != nil }

	/// a payload that prefers the tabular form's lines as its text (the
	/// common "paste a spreadsheet selection" shape).
	public init(tsv: String) {
		self.init(text: tsv, tsv: tsv)
	}

	// MARK: tsv ↔ rows

	/// cells joined with tabs, rows with newlines: `[["a","b"],["c","d"]]`
	/// → "a\tb\nc\td". deterministic — the exact inverse of `rows(fromTSV:)`.
	public static func tsv(rows: [[String]]) -> String {
		rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
	}

	/// split a tsv into rows then cells. naive on purpose: every "\n" starts a
	/// row, every "\t" splits a cell, no escapes. an empty payload yields one
	/// row with one empty cell.
	public static func rows(fromTSV text: String) -> [[String]] {
		splitByScalar(text, 0x0A).map { row in
			splitByScalar(row, 0x09)
		}
	}

	/// `rows(fromTSV:)` over the attached tsv (or a single empty cell when no
	/// tabular form is present).
	public func tsvRows() -> [[String]] {
		Self.rows(fromTSV: tsv ?? "")
	}

	// MARK: scalar-clean split

	/// split a string on one scalar. implemented on `unicodeScalars` so the
	/// embedded runtime (no grapheme-break tables) links it — `String.split`
	/// is Character-view and out of bounds there.
	private static func splitByScalar(_ text: String, _ separator: UInt32) -> [String] {
		var parts: [String] = []
		var current = ""
		for scalar in text.unicodeScalars {
			if scalar.value == separator {
				parts.append(current)
				current = ""
			} else {
				current.unicodeScalars.append(scalar)
			}
		}
		parts.append(current)
		return parts
	}
}

// MARK: - Codable (host/full-stdlib surface only)

#if !hasFeature(Embedded)
extension ClipboardPayload: Codable {}
#endif
