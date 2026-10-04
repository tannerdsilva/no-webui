// MARK: - Selection (t3.4, input parity primitives)
//
// an anchor/focus selection over leaf positions (character/run indices, not
// utf8 byte offsets) — the shape grids and editors share: press at `anchor`,
// drag to `focus`, read `start…end`. pure value semantics, wasm-visible,
// scalar-clean. all index math clamps at 0 (never a negative position) and
// never traps; a selection over an empty document-is D's job to keep in range.

public struct Selection: Sendable, Equatable {
	/// the press-side index.
	public var anchor: Int
	/// the drag-side index.
	public var focus: Int

	/// clamps both indices at 0.
	public init(anchor: Int, focus: Int) {
		self.anchor = max(anchor, 0)
		self.focus = max(focus, 0)
	}

	/// the lower of anchor/focus.
	public var start: Int { min(anchor, focus) }

	/// the upper of anchor/focus.
	public var end: Int { max(anchor, focus) }

	/// the half-open covered range (empty when collapsed).
	public var range: Range<Int> { start..<end }

	/// number of covered positions (0 when collapsed).
	public var length: Int { end - start }

	/// a collapsed caret (anchor == focus).
	public var isEmpty: Bool { anchor == focus }

	/// collapse to a caret at `index` (clamped at 0).
	public mutating func collapse(at index: Int) {
		let clamped = max(index, 0)
		anchor = clamped
		focus = clamped
	}

	/// a copy extended to `index` — the press side stays, the drag side moves.
	public func extending(to index: Int) -> Selection {
		Selection(anchor: anchor, focus: max(index, 0))
	}

	/// a copy with both indices shifted by `delta` (clamped at 0).
	public func shifted(by delta: Int) -> Selection {
		Selection(anchor: anchor + delta, focus: focus + delta)
	}

	/// the smallest selection covering both (anchor of the earlier, focus of
	/// the later).
	public func union(_ other: Selection) -> Selection {
		let newStart = min(start, other.start)
		let newEnd = max(end, other.end)
		return Selection(anchor: newStart, focus: newEnd)
	}

	/// ordered form of the same selection — anchor = start, focus = end.
	public var normalized: Selection {
		Selection(anchor: min(anchor, focus), focus: max(anchor, focus))
	}
}

// MARK: - Codable (host/full-stdlib surface only)

#if !hasFeature(Embedded)
extension Selection: Codable {}
#endif
