// MARK: - Filter (t4.1, shared kernels)
//
// predicate-handle filtering — the narrow protocol is the
// `(T) -> Bool` predicate, the same shape `sorted`'s comparator uses, so a
// call site can pass stored or closure predicates interchangeably. the
// pagination variant is the windowing form grids/tables use: it walks only
// the included elements and slices the page out of them (offset/limit are
// counts of INCLUDED elements, not of the raw input).
//
// foundation-free and scalar-clean.

public enum Filter {

	/// `elements` in order, keeping only the elements for which
	/// `isIncluded` returns true.
	public static func filter<T>(_ elements: [T], _ isIncluded: (T) -> Bool) -> [T] {
		var out: [T] = []
		out.reserveCapacity(elements.count)
		for element in elements where isIncluded(element) {
			out.append(element)
		}
		return out
	}

	/// number of included elements without materializing the filtered array —
	/// the cheap census form.
	public static func count<T>(_ elements: [T], _ isIncluded: (T) -> Bool) -> Int {
		var n = 0
		for element in elements where isIncluded(element) {
			n += 1
		}
		return n
	}

	/// the `offset..<offset+limit` window of the included elements. a limit of
	/// nil (or ≤ 0) means "to the end". offset clamps to the available count,
	/// so negative or oversized pagination never traps: this is a view, not a
	/// range you must pre-validate.
	public static func paginate<T>(_ elements: [T], _ isIncluded: (T) -> Bool, offset: Int, limit: Int?) -> [T] {
		var start = max(offset, 0)
		var out: [T] = []
		if let limit, limit <= 0 { return out }
		var remaining = limit ?? Int.max
		for element in elements {
			guard isIncluded(element) else { continue }
			if start > 0 {
				start -= 1
				continue
			}
			guard remaining > 0 else { break }
			out.append(element)
			remaining -= 1
		}
		return out
	}
}
