// MARK: - CivilDate + DateFormat (t4.1, shared kernels)
//
// hand-rolled civil calendar — no Foundation, no `Date`, no `Calendar`, no
// timezone. `CivilDate` is a proleptic-Gregorian y/m/d value with a pure
// integer days-since-epoch mapping (Howard Hinnant's `days_from_civil` /
// `civil_from_days`, the same algorithms date libraries use), so native and
// embedded wasm compute identical values from identical integer math — the
// t4.2 parity corpus hashes them.
//
// floor division matters: Swift's `/` truncates toward zero, but the civil
// algorithms require flooring division to stay correct for dates before
// 1970 (negative epoch). `flooredDiv`/`flooredMod` are the only places that
// read those semantics; every other quotient in the algorithms is
// non-negative. round-trip verified over 1600-01-01…2400-12-31 (zero
// mismatches, see KernelTests).

/// a calendar date in the proleptic Gregorian calendar (year 1 and later,
/// extended indefinitely on both sides of 1970).
public struct CivilDate: Sendable, Equatable, Hashable, Comparable {
	public let year: Int
	/// 1…12.
	public let month: Int
	/// 1…31 (validated against the month length at construction).
	public let day: Int

	/// validates the triple against the proleptic Gregorian calendar and
	/// returns nil when it is not a real date (2/29 on a non-leap year,
	/// month 13, day 0).
	public init?(year: Int, month: Int, day: Int) {
		guard month >= 1 && month <= 12, day >= 1 else { return nil }
		guard day <= Self.daysInMonth(year: year, month: month) else { return nil }
		self.year = year
		self.month = month
		self.day = day
	}

	/// the date `days` days after (or before) 1970-01-01.
	public init(daysSinceEpoch days: Int) {
		let (y, m, d) = Self.civilFromDays(days)
		year = y
		month = m
		day = d
	}

	/// the number of days since 1970-01-01 (negative for earlier dates).
	public var daysSinceEpoch: Int {
		Self.daysFromCivil(year, month, day)
	}

	/// 0 = sunday … 6 = saturday for this date.
	public var weekdayIndex: Int {
		Self.flooredMod(daysSinceEpoch + 4, 7)
	}

	/// "Sunday"…"Saturday".
	public var weekdayName: String { Self.weekdayNames[weekdayIndex] }

	/// "January"…"December".
	public var monthName: String { Self.monthNames[month - 1] }

	/// ISO-8601 calendar form: "2026-10-03" (zero-padded, no time).
	public func iso8601() -> String {
		"\(Self.padField(year, width: 4))-\(Self.padField(month, width: 2))-\(Self.padField(day, width: 2))"
	}

	/// long form: "October 3, 2026".
	public func longForm() -> String {
		"\(monthName) \(NumberFormat.integer(day)), \(NumberFormat.integer(year))"
	}

	/// "Sat, Oct 3, 2026" — the compact row form.
	public func shortForm() -> String {
		"\(Self.weekdayShortNames[weekdayIndex]), \(Self.monthShortNames[month - 1]) \(NumberFormat.integer(day)), \(NumberFormat.integer(year))"
	}

	public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
		lhs.daysSinceEpoch < rhs.daysSinceEpoch
	}

	/// zero-pad a non-negative field to `width` digits ("7" → "007").
	/// scalar-clean: builds through `unicodeScalars`, no Character math.
	private static func padField(_ value: Int, width: Int) -> String {
		let digits = NumberFormat.integer(value)
		if digits.unicodeScalars.count >= width { return digits }
		var out = ""
		out.reserveCapacity(width)
		for _ in 0..<(width - digits.unicodeScalars.count) {
			out.unicodeScalars.append("0")
		}
		return out + digits
	}

	// MARK: civil algorithms (Hinnant)

	/// days in a month (0 for an invalid month) — `isLeapYear` handles 2/29.
	private static func daysInMonth(year: Int, month: Int) -> Int {
		switch month {
		case 1, 3, 5, 7, 8, 10, 12: return 31
		case 4, 6, 9, 11: return 30
		case 2: return isLeapYear(year) ? 29 : 28
		default: return 0
		}
	}

	public static func isLeapYear(_ year: Int) -> Bool {
		(year % 4 == 0 && year % 100 != 0) || year % 400 == 0
	}

	/// days since 1970-01-01 of a validated y/m/d.
	public static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
		let yy = m <= 2 ? y - 1 : y
		let era = flooredDiv(yy, 400)
		let yoe = yy - era * 400                                 // [0, 399]
		let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1 // [0, 365]
		let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
		return era * 146097 + doe - 719468
	}

	/// the inverse of `daysFromCivil`.
	public static func civilFromDays(_ z: Int) -> (year: Int, month: Int, day: Int) {
		let z2 = z + 719468
		let era = flooredDiv(z2, 146097)
		let doe = z2 - era * 146097                               // [0, 146096]
		let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
		let y = yoe + era * 400
		let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
		let mp = (5 * doy + 2) / 153
		let d = doy - (153 * mp + 2) / 5 + 1
		let m = mp < 10 ? mp + 3 : mp - 9
		return (m <= 2 ? y + 1 : y, m, d)
	}

	/// floor division — truncates toward −∞, unlike Swift's `/`.
	private static func flooredDiv(_ a: Int, _ b: Int) -> Int {
		let q = a / b
		return (a % b != 0) && ((a < 0) != (b < 0)) ? q - 1 : q
	}

	/// floored modulo — the result carries the sign of `b` (positive here).
	private static func flooredMod(_ a: Int, _ b: Int) -> Int {
		let r = a % b
		return r < 0 ? r + b : r
	}

	private static let weekdayNames = [
		"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
	]
	private static let weekdayShortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	private static let monthNames = [
		"January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	]
	private static let monthShortNames = [
		"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
	]
}
