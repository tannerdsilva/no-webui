import Testing
import WebUISharedCore

// MARK: - t4.1 kernel unit tests (native)
//
// the native half of the `reduce is pure and placement-free` discipline: every
// kernel below compiles into the same module that the embedded wasm build
// links (WebUISharedCore), so these tests ARE the logic the island runs. the
// exact expected strings here are the same values the t4.2 parity corpus
// freezes as hashes (Tests/WebUISharedCoreTests/KernelParityTests).

// MARK: normalize / lex

@Suite("normalize")
struct NormalizeSuite {
	@Test("basic defaults: trim + collapse + ASCII fold")
	func basicRecipe() {
		let n = Normalizer.basic
		#expect(n.normalize("  Hello   World  ") == "hello world")
		#expect(n.normalize("\tOdd\t  Casing\n") == "odd casing")
		#expect(n.normalize("   ") == "")
		#expect(n.normalize("") == "")
	}

	@Test("collapse off keeps interior whitespace scalars")
	func noCollapse() {
		let n = Normalizer(trim: true, collapseWhitespace: false, foldASCII: true)
		#expect(n.normalize("  a\t b \n") == "a\t b")
	}

	@Test("trim off preserves the frame, collapse collapses runs")
	func noTrim() {
		let n = Normalizer(trim: false, collapseWhitespace: true, foldASCII: false)
		#expect(n.normalize("  a  b  ") == " a b ")
		#expect(n.normalize("   ") == " ")
	}

	@Test("fold is ASCII-only; non-ASCII passes through")
	func foldScope() {
		let n = Normalizer(trim: true, collapseWhitespace: false, foldASCII: true)
		#expect(n.normalize("ÄbC dÉf") == "Äbc dÉf")
	}

	@Test("multiline newlines are part of the whitespace set")
	func newlines() {
		let n = Normalizer(trim: true, collapseWhitespace: true, foldASCII: true)
		#expect(n.normalize("a\n\n\nb\r\nc") == "a b c")
	}
}

@Suite("lex")
struct LexSuite {
	@Test("default word tokens: ascii alnum plus _ -")
	func words() {
		#expect(Lexer.words(in: "Hello, world!  x-9y") == ["Hello", "world", "x-9y"])
		#expect(Lexer.words(in: "  leading and trailing  ") == ["leading", "and", "trailing"])
		#expect(Lexer.words(in: "") == [])
	}

	@Test("custom token predicate")
	func customPredicate() {
		let digitsOnly: (Unicode.Scalar) -> Bool = { $0.value >= 0x30 && $0.value <= 0x39 }
		#expect(Lexer.tokens(in: "a1b22c3", isToken: digitsOnly) == ["1", "22", "3"])
		#expect(Lexer.tokens(in: "----", isToken: digitsOnly) == [])
	}
}

// MARK: aggregate

@Suite("aggregate")
struct AggregateSuite {
	@Test("array summary ops")
	func arrayOps() {
		let values: [Double] = [3.5, -1, 2.25, 0, 7]
		#expect(Aggregate.sum(values) == 11.75)
		#expect(Aggregate.min(values) == -1)
		#expect(Aggregate.max(values) == 7)
		#expect(Aggregate.average(values) == 2.35)
		#expect(Aggregate.count(values) == 5)
	}

	@Test("empty arrays: min/max/avg nil, sum 0, count 0")
	func empty() {
		#expect(Aggregate.min([]) == nil)
		#expect(Aggregate.max([]) == nil)
		#expect(Aggregate.average([]) == nil)
		#expect(Aggregate.sum([]) == 0)
		#expect(Aggregate.count([]) == 0)
	}

	@Test("the incremental aggregator matches the array form")
	func incremental() {
		var acc = NumberAggregator()
		#expect(acc.isEmpty)
		#expect(acc.average == nil)
		acc.add(3.5)
		acc.add(-1)
		acc.add(contentsOf: [2.25, 0, 7])
		#expect(acc.count == 5)
		#expect(acc.sum == 11.75)
		#expect(acc.min == -1)
		#expect(acc.max == 7)
		#expect(acc.average == 2.35)
		#expect(!acc.isEmpty)
	}
}

// MARK: sort (stable, keyed)

@Suite("sort")
struct SortSuite {
	@Test("keys order, ties keep insertion order")
	func stableTies() {
		struct Row: Equatable { let id: Int; let key: Int }
		let rows = [
			Row(id: 0, key: 2), Row(id: 1, key: 1), Row(id: 2, key: 2),
			Row(id: 3, key: 2), Row(id: 4, key: 0), Row(id: 5, key: 1),
		]
		let sorted = KeyedSorter.stableSorted(rows, key: { $0.key }, by: <)
		let ids = sorted.map { $0.id }
		// key 0: [4] · key 1: [1,5] · key 2: [0,2,3] — each tie keeps order.
		#expect(ids == [4, 1, 5, 0, 2, 3])
	}

	@Test("stability holds across the insertion-sort threshold (16) with many ties")
	func stableLarge() {
		// 40 elements, only two distinct keys — a stability-stress shape.
		var keys: [Int] = []
		for i in 0..<40 { keys.append(i % 2 == 0 ? 1 : 0) }
		let sorted = KeyedSorter.stableSorted(keys, by: <)
		// all 0s first (in original order), then all 1s (in original order).
		#expect(Array(sorted.prefix(20)) == [Int](repeating: 0, count: 20))
		#expect(Array(sorted.suffix(20)) == [Int](repeating: 1, count: 20))
	}

	@Test("whole-element comparator + degenerate sizes")
	func degenerate() {
		#expect(KeyedSorter.stableSorted([3, 1, 2]) { $0 < $1 } == [1, 2, 3])
		#expect(KeyedSorter.stableSorted([] as [Int], by: <) == [])
		#expect(KeyedSorter.stableSorted([7] as [Int], by: <) == [7])
	}

	@Test("already-sorted input is untouched (merge preserves order)")
	func alreadySorted() {
		#expect(KeyedSorter.stableSorted([1, 2, 3, 4, 5], by: <) == [1, 2, 3, 4, 5])
	}
}

// MARK: filter

@Suite("filter")
struct FilterSuite {
	@Test("predicate filter retains order")
	func basic() {
		#expect(Filter.filter([1, 2, 3, 4, 5, 6], { $0 % 2 == 0 }) == [2, 4, 6])
	}

	@Test("count is the cheap census")
	func census() {
		#expect(Filter.count([1, 2, 3, 4, 5, 6], { $0 % 2 == 0 }) == 3)
		#expect(Filter.count([], { _ in true }) == 0)
	}

	@Test("paginate windows over INCLUDED elements")
	func paginate() {
		let evens: (Int) -> Bool = { $0 % 2 == 0 }
		let input = [1, 2, 3, 4, 5, 6, 8, 9, 10, 12]
		#expect(Filter.paginate(input, evens, offset: 0, limit: 2) == [2, 4])
		#expect(Filter.paginate(input, evens, offset: 1, limit: 2) == [4, 6])
		#expect(Filter.paginate(input, evens, offset: 3, limit: 2) == [8, 10])
		#expect(Filter.paginate(input, evens, offset: 0, limit: 0) == [])
		#expect(Filter.paginate(input, evens, offset: 0, limit: nil) == [2, 4, 6, 8, 10, 12])
		#expect(Filter.paginate(input, evens, offset: 99, limit: 5) == [])
		#expect(Filter.paginate(input, evens, offset: -3, limit: 1) == [2])
	}
}

// MARK: format — number

@Suite("format.number")
struct FormatNumberSuite {
	@Test("integer renders base-10, signs, extremes")
	func integer() {
		#expect(NumberFormat.integer(0) == "0")
		#expect(NumberFormat.integer(12345) == "12345")
		#expect(NumberFormat.integer(-42) == "-42")
		#expect(NumberFormat.integer(Int64.min) == "-9223372036854775808")
		#expect(NumberFormat.integer(Int64.max) == "9223372036854775807")
	}

	@Test("grouped inserts every three digits from the right")
	func grouped() {
		#expect(NumberFormat.grouped(0) == "0")
		#expect(NumberFormat.grouped(999) == "999")
		#expect(NumberFormat.grouped(1000) == "1,000")
		#expect(NumberFormat.grouped(1234567) == "1,234,567")
		#expect(NumberFormat.grouped(-987654321) == "-987,654,321")
	}

	@Test("fixed is deterministic IEEE-arithmetic rounding (pinned digits)")
	func fixed() {
		#expect(NumberFormat.fixed(3.14159, fractionDigits: 2) == "3.14")
		#expect(NumberFormat.fixed(3.14159, fractionDigits: 0) == "3")
		#expect(NumberFormat.fixed(-0.5, fractionDigits: 1) == "-0.5")
		#expect(NumberFormat.fixed(2.5, fractionDigits: 0) == "3")       // half away from zero
		#expect(NumberFormat.fixed(2.4, fractionDigits: 0) == "2")
		#expect(NumberFormat.fixed(0.125, fractionDigits: 2) == "0.13")
		#expect(NumberFormat.fixed(0.125, fractionDigits: 3) == "0.125") // exact at 3 places
		#expect(NumberFormat.fixed(0.001, fractionDigits: 2) == "0.00")
		#expect(NumberFormat.fixed(1234567.891, fractionDigits: 2) == "1234567.89")
		#expect(NumberFormat.fixed(-0.004, fractionDigits: 2) == "-0.00")
		// 1.015 is not representable in binary64: 1.01499999…, so binary
		// rounding gives "1.01". the kernel's contract is deterministic
		// placement parity (t4.2), pinned here deliberately.
		#expect(NumberFormat.fixed(1.015, fractionDigits: 2) == "1.01")
		#expect(NumberFormat.fixed(-1.015, fractionDigits: 2) == "-1.01")
		#expect(NumberFormat.fixed(0, fractionDigits: 2) == "0.00")
	}

	@Test("percent scales by 100 and appends the sign")
	func percent() {
		#expect(NumberFormat.percent(0.125, fractionDigits: 1) == "12.5%")
		#expect(NumberFormat.percent(1, fractionDigits: 0) == "100%")
		#expect(NumberFormat.percent(0.005, fractionDigits: 2) == "0.50%")
		#expect(NumberFormat.percent(-0.25, fractionDigits: 0) == "-25%")
	}
}

// MARK: format — date

@Suite("format.date")
struct FormatDateSuite {
	@Test("the epoch anchors")
	func anchors() {
		#expect(CivilDate(year: 1970, month: 1, day: 1)?.daysSinceEpoch == 0)
		#expect(CivilDate(year: 2000, month: 1, day: 1)?.daysSinceEpoch == 10957)
		#expect(CivilDate(year: 1900, month: 1, day: 1)?.daysSinceEpoch == -25567)
		#expect(CivilDate(year: 1969, month: 12, day: 31)?.daysSinceEpoch == -1)
		#expect(CivilDate(year: 2024, month: 2, day: 29)?.daysSinceEpoch == 19782)
		#expect(CivilDate(year: 2026, month: 10, day: 3)?.daysSinceEpoch == 20729)
	}

	@Test("weekday: 0=sunday…6=saturday")
	func weekday() {
		#expect(CivilDate(year: 1970, month: 1, day: 1)!.weekdayIndex == 4) // thursday
		#expect(CivilDate(year: 2000, month: 1, day: 1)!.weekdayIndex == 6) // saturday
		#expect(CivilDate(year: 1900, month: 1, day: 1)!.weekdayIndex == 1) // monday
		#expect(CivilDate(year: 2026, month: 10, day: 3)!.weekdayIndex == 6) // saturday
		#expect(CivilDate(year: 2026, month: 10, day: 3)!.weekdayName == "Saturday")
	}

	@Test("day→date→day round-trips across 1900…2100 (floor-division honesty)")
	func roundTrip() {
		let from = CivilDate.daysFromCivil(1900, 1, 1)
		let to = CivilDate.daysFromCivil(2100, 12, 31)
		for days in from...to {
			let date = CivilDate(daysSinceEpoch: days)
			#expect(date.daysSinceEpoch == days)
		}
	}

	@Test("validation rejects impossible dates")
	func validation() {
		#expect(CivilDate(year: 2023, month: 2, day: 29) == nil)
		#expect(CivilDate(year: 2024, month: 2, day: 30) == nil)
		#expect(CivilDate(year: 2026, month: 13, day: 1) == nil)
		#expect(CivilDate(year: 2026, month: 0, day: 1) == nil)
		#expect(CivilDate(year: 2026, month: 4, day: 31) == nil) // april has 30 days
		#expect(CivilDate(year: 2026, month: 10, day: 3) != nil)
	}

	@Test("leap years")
	func leap() {
		#expect(CivilDate.isLeapYear(2024))
		#expect(CivilDate.isLeapYear(2000))
		#expect(!CivilDate.isLeapYear(2023))
		#expect(!CivilDate.isLeapYear(1900))
	}

	@Test("the three renderers")
	func renderers() {
		let date = CivilDate(year: 2026, month: 10, day: 3)!
		#expect(date.iso8601() == "2026-10-03")
		#expect(date.longForm() == "October 3, 2026")
		#expect(date.shortForm() == "Sat, Oct 3, 2026")
		let early = CivilDate(daysSinceEpoch: 0)
		#expect(early.iso8601() == "1970-01-01")
		#expect(early.monthName == "January")
	}

	@Test("comparison is by epoch day")
	func comparable() {
		#expect(CivilDate(year: 2026, month: 1, day: 1)! < CivilDate(year: 2026, month: 1, day: 2)!)
		#expect(CivilDate(year: 2025, month: 12, day: 31)! < CivilDate(year: 2026, month: 1, day: 1)!)
	}
}
