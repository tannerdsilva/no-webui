// MARK: - Aggregate (t4.1, shared kernels)
//
// sum / min / max / avg / count over doubles, in two placements: an
// incremental value type (`NumberAggregator`, the hot-path form — one pass,
// constant memory) and a pure array API (`Aggregate`, the one-shot form).
// foundation-free and scalar-clean; the only math is IEEE double arithmetic,
// which is bit-identical across the native and embedded wasm runtimes, so the
// parity corpus can hash these results deterministically (KernelParity).

/// constant-memory accumulator: feed `Double`s one at a time, then read the
/// five summary values. `min`/`max`/`average` are nil on an empty feed;
/// `sum` and `count` are well-defined for zero elements.
public struct NumberAggregator: Sendable, Equatable {
	/// number of values fed so far.
	public private(set) var count: Int
	/// running total.
	public private(set) var sum: Double
	/// smallest value seen, or nil before the first add.
	public private(set) var min: Double?
	/// largest value seen, or nil before the first add.
	public private(set) var max: Double?

	public init() {
		count = 0
		sum = 0
		min = nil
		max = nil
	}

	public var isEmpty: Bool { count == 0 }

	/// mean of the fed values, nil on an empty feed.
	public var average: Double? { count == 0 ? nil : sum / Double(count) }

	public mutating func add(_ value: Double) {
		count += 1
		sum += value
		if let m = min { if value < m { min = value } } else { min = value }
		if let m = max { if value > m { max = value } } else { max = value }
	}

	/// feed a whole sequence in one call.
	public mutating func add<S: Sequence>(contentsOf values: S) where S.Element == Double {
		for value in values { add(value) }
	}
}

/// one-shot array API for the same five summary operations. min/max/average
/// return nil on an empty array; sum/count mirror the aggregator exactly.
public enum Aggregate {
	public static func sum(_ values: [Double]) -> Double {
		var total: Double = 0
		for value in values { total += value }
		return total
	}

	public static func min(_ values: [Double]) -> Double? {
		guard var best = values.first else { return nil }
		for value in values.dropFirst() where value < best { best = value }
		return best
	}

	public static func max(_ values: [Double]) -> Double? {
		guard var best = values.first else { return nil }
		for value in values.dropFirst() where value > best { best = value }
		return best
	}

	public static func average(_ values: [Double]) -> Double? {
		guard !values.isEmpty else { return nil }
		return sum(values) / Double(values.count)
	}

	public static func count(_ values: [Double]) -> Int { values.count }
}
