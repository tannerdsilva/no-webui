// MARK: - KernelCorpus (t4.2)
//
// ONE shared calculation corpus, deliberately frozen: a named list of cases,
// each running a t4.1 kernel over fixed inputs and producing a canonical
// result STRING. the corpus lives in WebUISharedCore, so it compiles into the
// native test binary AND the probe island's wasm — the same Swift source on
// both placements. KernelParity turns each result into an FNV-1a hash and the
// parity suite (native test + designer/probes/c-parity.mjs) requires the two
// hash sets to be equal: EQUAL HASHES = the t4.2 gate.
//
// determinism rules for case results (what makes parity meaningful):
//   - integers interpolate via `\(Int)` — identical everywhere;
//   - doubles are never interpolated raw; they pass through
//     NumberFormat.fixed (my hand-rolled formatter — identical everywhere), or
//     are integers exactly;
//   - joins use the literal "|" separator; no dictionary iteration anywhere
//     (order would be placement-dependent), arrays only.
//
// adding a case: append to `all` (never reorder/rename existing cases — the
// native golden table + the node probe freeze the exact set, so a rename is a
// deliberate corpus change caught by the suite).

/// one frozen corpus case: `name` is the stable identifier, `run` the
/// canonical result string on both placements.
public struct KernelCorpusCase: Sendable {
	public let name: String
	public let run: @Sendable () -> String

	public init(name: String, run: @escaping @Sendable () -> String) {
		self.name = name
		self.run = run
	}
}

public enum KernelCorpus {
	/// a fixed record type the sort/aggregate cases share.
	public struct Row: Sendable {
		public let id: Int
		public let key: Int
		public let value: Double
		public init(id: Int, key: Int, value: Double) {
			self.id = id
			self.key = key
			self.value = value
		}
	}

	/// join a list of result fragments with the canonical "|".
	private static func join(_ fragments: [String]) -> String {
		fragments.joined(separator: "|")
	}

	private static func fixedList(_ values: [Double]) -> String {
		join(values.map { NumberFormat.fixed($0, fractionDigits: 6) })
	}

	/// every case, in stable order. order is part of the contract.
	public static let all: [KernelCorpusCase] = [
		// ── normalize ────────────────────────────────────────────────
		KernelCorpusCase(name: "normalize.trim") {
			let n = Normalizer(trim: true, collapseWhitespace: false, foldASCII: false)
			return join(["  a\t b \n", "   ", "plain"].map { n.normalize($0) })
		},
		KernelCorpusCase(name: "normalize.collapse") {
			let n = Normalizer(trim: false, collapseWhitespace: true, foldASCII: false)
			return join(["  a  b  ", "x\n\n\ny", "  "].map { n.normalize($0) })
		},
		KernelCorpusCase(name: "normalize.basic") {
			let n = Normalizer.basic
			return join(["  Hello   World  ", "ÄbC\t dÉf ", ""].map { n.normalize($0) })
		},
		// ── lex ──────────────────────────────────────────────────────
		KernelCorpusCase(name: "lex.words") {
			join(Lexer.words(in: "Hello, world!  x-9y  n/a"))
		},
		KernelCorpusCase(name: "lex.custom") {
			let digitsOnly: (Unicode.Scalar) -> Bool = { $0.value >= 0x30 && $0.value <= 0x39 }
			return join(Lexer.tokens(in: "a1b22c3..0040", isToken: digitsOnly))
		},
		// ── aggregate ────────────────────────────────────────────────
		KernelCorpusCase(name: "aggregate.array") {
			let values: [Double] = [3.5, -1, 2.25, 0, 7, -0.125]
			return join([
				NumberFormat.fixed(Aggregate.sum(values), fractionDigits: 6),
				NumberFormat.fixed(Aggregate.min(values) ?? 0, fractionDigits: 6),
				NumberFormat.fixed(Aggregate.max(values) ?? 0, fractionDigits: 6),
				NumberFormat.fixed(Aggregate.average(values) ?? 0, fractionDigits: 6),
				NumberFormat.integer(Int64(Aggregate.count(values))),
			])
		},
		KernelCorpusCase(name: "aggregate.empty") {
			join([
				NumberFormat.fixed(Aggregate.min([]) ?? 0, fractionDigits: 6),
				NumberFormat.fixed(Aggregate.max([]) ?? 0, fractionDigits: 6),
				NumberFormat.fixed(Aggregate.average([]) ?? 0, fractionDigits: 6),
				NumberFormat.fixed(Aggregate.sum([]), fractionDigits: 6),
				NumberFormat.integer(Int64(Aggregate.count([]))),
			])
		},
		KernelCorpusCase(name: "aggregate.incremental") {
			var acc = NumberAggregator()
			acc.add(3.5)
			acc.add(-1)
			acc.add(contentsOf: [2.25, 0, 7, -0.125])
			return join([
				NumberFormat.integer(Int64(acc.count)),
				NumberFormat.fixed(acc.sum, fractionDigits: 6),
				NumberFormat.fixed(acc.min ?? 0, fractionDigits: 6),
				NumberFormat.fixed(acc.max ?? 0, fractionDigits: 6),
				NumberFormat.fixed(acc.average ?? 0, fractionDigits: 6),
			])
		},
		// ── sort (stable, keyed) ─────────────────────────────────────
		KernelCorpusCase(name: "sort.stable") {
			let rows = [
				Row(id: 0, key: 2, value: 1), Row(id: 1, key: 1, value: 2),
				Row(id: 2, key: 2, value: 3), Row(id: 3, key: 2, value: 4),
				Row(id: 4, key: 0, value: 5), Row(id: 5, key: 1, value: 6),
			]
			let sorted = KeyedSorter.stableSorted(rows, key: { $0.key }, by: <)
			return join(sorted.map { "\($0.id):\($0.key)" })
		},
		KernelCorpusCase(name: "sort.large") {
			var keys: [Int] = []
			for i in 0..<40 { keys.append(i % 2 == 0 ? 1 : 0) }
			let sorted = KeyedSorter.stableSorted(keys, by: <)
			return join([String(sorted.prefix(20).reduce(0, +)), String(sorted.suffix(20).reduce(0, +))])
		},
		// ── filter ───────────────────────────────────────────────────
		KernelCorpusCase(name: "filter.basic") {
			let input = [1, 2, 3, 4, 5, 6, 8, 9, 10, 12]
			let evens: (Int) -> Bool = { $0 % 2 == 0 }
			return join([
				Filter.filter(input, evens).map { NumberFormat.integer(Int64($0)) }.joined(separator: ","),
				NumberFormat.integer(Int64(Filter.count(input, evens))),
			])
		},
		KernelCorpusCase(name: "filter.page") {
			let input = [1, 2, 3, 4, 5, 6, 8, 9, 10, 12]
			let evens: (Int) -> Bool = { $0 % 2 == 0 }
			let windows = [
				Filter.paginate(input, evens, offset: 0, limit: 2),
				Filter.paginate(input, evens, offset: 1, limit: 2),
				Filter.paginate(input, evens, offset: 3, limit: 3),
				Filter.paginate(input, evens, offset: 99, limit: 2),
				Filter.paginate(input, evens, offset: -2, limit: 4),
			]
			return join(windows.map { $0.map { NumberFormat.integer(Int64($0)) }.joined(separator: ",") })
		},
		// ── format: number ───────────────────────────────────────────
		KernelCorpusCase(name: "format.int") {
			// Int64 throughout: Int is 32-bit on wasm32, and the corpus must
			// hash the SAME canonical string on every placement (the parity
			// probe caught this on its first run).
			join([Int64(0), 12345, -42, Int64.min, Int64.max].map(NumberFormat.integer))
		},
		KernelCorpusCase(name: "format.grouped") {
			// `grouped` has a defaulted separator param — it is arity 2, so it
			// cannot ride a `.map(NumberFormat.grouped)` function reference.
			join([Int64(0), 999, 1000, 1234567, -987654321, 1_000_000_000].map { NumberFormat.grouped($0) })
		},
		KernelCorpusCase(name: "format.fixed") {
			join([
				NumberFormat.fixed(3.14159, fractionDigits: 2),
				NumberFormat.fixed(2.5, fractionDigits: 0),
				NumberFormat.fixed(0.125, fractionDigits: 3),
				NumberFormat.fixed(1.015, fractionDigits: 2),
				NumberFormat.fixed(-0.004, fractionDigits: 2),
				NumberFormat.fixed(1234567.891, fractionDigits: 2),
				NumberFormat.fixed(0, fractionDigits: 2),
			])
		},
		KernelCorpusCase(name: "format.percent") {
			join([
				NumberFormat.percent(0.125, fractionDigits: 1),
				NumberFormat.percent(1, fractionDigits: 0),
				NumberFormat.percent(0.005, fractionDigits: 2),
				NumberFormat.percent(-0.25, fractionDigits: 0),
			])
		},
		// ── format: date ─────────────────────────────────────────────
		KernelCorpusCase(name: "date.iso") {
			let dates = [20729, 0, 10957, 19782, -25567, -1, 19729]
			return join(dates.map { CivilDate(daysSinceEpoch: $0).iso8601() })
		},
		KernelCorpusCase(name: "date.weekday") {
			let dates = [20729, 0, 10957, -25567, -1, 19782]
			return join(dates.map { NumberFormat.integer(Int64(CivilDate(daysSinceEpoch: $0).weekdayIndex)) })
		},
		KernelCorpusCase(name: "date.long") {
			let date = CivilDate(year: 2026, month: 10, day: 3)!
			return join([date.longForm(), date.shortForm(), date.monthName, date.weekdayName])
		},
		KernelCorpusCase(name: "date.roundtrip") {
			// a sampled span crossing the epoch and the leap cycle; each
			// fragment is "days:y/m/d" proving civil_from_days == days_from_civil.
			var fragments: [String] = []
			for days in stride(from: -25567, through: 47846, by: 677) {
				let date = CivilDate(daysSinceEpoch: days)
				fragments.append("\(days):\(date.iso8601())")
			}
			return join(fragments)
		},
	]
}
