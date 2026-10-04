// MARK: - KeyedSorter (t4.1, shared kernels)
//
// a STABLE, KEYED sort. the stdlib `sorted(by:)` is an unstable introsort —
// equal keys may be reordered relative to each other, which breaks the
// "records keep their insertion order when keys tie" contract hot paths rely
// on (e.g. sort a table by column without losing row order). this kernel is a
// top-down merge sort: merging equal elements keeps the left half's element
// first, so stability is guaranteed by construction and the comparator is the
// narrow protocol — a pure `(Key, Key) -> Bool`, the same shape the stdlib
// uses, evaluated only when two keys differ (equal keys short-circuit to keep
// order and never call the comparator).
//
// foundation-free and scalar-clean: no Unicode work at all.

public enum KeyedSorter {

	/// returns `elements` sorted stably by `key`, ordered by
	/// `areInIncreasingOrder`. elements with equal keys keep their relative
	/// order (the left/earlier element stays first).
	public static func stableSorted<T, Key>(
		_ elements: [T],
		key: (T) -> Key,
		by areInIncreasingOrder: (Key, Key) -> Bool
	) -> [T] {
		if elements.count < 2 { return elements }
		return Self.mergeSort(elements, key: key, areInIncreasingOrder: areInIncreasingOrder)
	}

	/// convenience: the whole element serves as its key.
	public static func stableSorted<T>(
		_ elements: [T],
		by areInIncreasingOrder: (T, T) -> Bool
	) -> [T] {
		stableSorted(elements, key: { $0 }, by: areInIncreasingOrder)
	}

	// MARK: top-down merge sort (stable)

	private static func mergeSort<T, Key>(
		_ elements: [T],
		key: (T) -> Key,
		areInIncreasingOrder: (Key, Key) -> Bool
	) -> [T] {
		let n = elements.count
		// insertion sort for tiny spans keeps the rust/cache profile of
		// deeply-nested small sorts down; it is stable, so the result is
		// identical to a pure merge.
		if n < 16 {
			var local = elements
			for i in 1..<n {
				var j = i
				while j > 0, areInIncreasingOrder(key(local[j]), key(local[j - 1])) {
					local.swapAt(j, j - 1)
					j -= 1
				}
			}
			return local
		}
		let mid = n / 2
		let left = mergeSort(Array(elements[0..<mid]), key: key, areInIncreasingOrder: areInIncreasingOrder)
		let right = mergeSort(Array(elements[mid..<n]), key: key, areInIncreasingOrder: areInIncreasingOrder)
		return Self.merge(left, right, key: key, areInIncreasingOrder: areInIncreasingOrder)
	}

	private static func merge<T, Key>(
		_ left: [T], _ right: [T],
		key: (T) -> Key,
		areInIncreasingOrder: (Key, Key) -> Bool
	) -> [T] {
		var out: [T] = []
		out.reserveCapacity(left.count + right.count)
		var li = 0, ri = 0
		while li < left.count, ri < right.count {
			// strict `<` on keys: equal keys take the LEFT element, so the
			// original relative order is preserved. the comparator is never
			// consulted for ties.
			if areInIncreasingOrder(key(right[ri]), key(left[li])) {
				out.append(right[ri])
				ri += 1
			} else {
				out.append(left[li])
				li += 1
			}
		}
		out.append(contentsOf: left[li...])
		out.append(contentsOf: right[ri...])
		return out
	}
}
