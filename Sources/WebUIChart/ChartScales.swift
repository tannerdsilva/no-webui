import Foundation
import WebUICore

// MARK: - Scale

/// A resolved numeric axis: maps data values to viewBox units.
/// The range may be reversed (a vertical axis maps "up" to lower y),
/// so it is stored as explicit start/end positions, not a `ClosedRange`.
struct ChartLinearScale {
	let domain: ClosedRange<Double>
	let rangeStart: Double
	let rangeEnd: Double
	let inverted: Bool
	var flipped: Bool { inverted }

	init(domain: ClosedRange<Double>, rangeStart: Double, rangeEnd: Double, inverted: Bool = false) {
		let lo = min(domain.lowerBound, domain.upperBound)
		let hi = max(domain.lowerBound, domain.upperBound)
		self.domain = lo...hi
		self.rangeStart = rangeStart
		self.rangeEnd = rangeEnd
		self.inverted = inverted
	}

	var span: Double { domain.upperBound - domain.lowerBound }
	var rangeSpan: Double { rangeEnd - rangeStart }

	func position(_ value: Double) -> Double {
		guard span > 0 else { return (rangeStart + rangeEnd) / 2 }
		let t = (value - domain.lowerBound) / span
		let clamped = min(max(t, 0), 1)
		return rangeStart + clamped * rangeSpan
	}

	/// Inverse: map a position back to a value.
	func value(at position: Double) -> Double {
		guard rangeSpan != 0 else { return domain.lowerBound }
		let t = (position - rangeStart) / rangeSpan
		return domain.lowerBound + min(max(t, 0), 1) * span
	}
}

/// A resolved categorical axis: maps categories to band slots.
///
/// The plot is divided into equal steps of `step` = width / (1 + 2·outer +
/// (n−1)·inner); each category occupies `step`, and its mark fills
/// `step · (1 − inner)` of it, centered in the step. `inner`/`outer` are
/// fractions of a step (d3 `scaleBand` convention).
struct ChartBandedScale {
	let categories: [String]
	let rangeStart: Double
	let rangeEnd: Double
	let paddingInner: Double
	let paddingOuter: Double

	var bandCount: Int { categories.count }
	/// d3 `scaleBand` step: width / (n − inner + 2·outer), so the marks plus
	/// padding fill the range exactly.
	var step: Double {
		let span = rangeEnd - rangeStart
		guard bandCount > 0 else { return span }
		let denom = Double(bandCount) - paddingInner + 2 * paddingOuter
		guard denom > 0 else { return span }
		return span / denom
	}
	/// The mark width for a category (the centered portion of its step).
	var bandWidth: Double { step * (1 - paddingInner) }

	var index: [String: Int] {
		var m = [String: Int]()
		for (i, c) in categories.enumerated() { m[c] = i }
		return m
	}
	/// The left edge of the category's mark (d3 `scaleBand` placement:
	/// outer padding at the ends, inner padding between marks).
	func position(of category: String) -> Double {
		let i = index[category] ?? 0
		return rangeStart + step * paddingOuter + Double(i) * step
	}
	/// The center of the category's mark (axis labels, gridlines, line points).
	func center(of category: String) -> Double {
		position(of: category) + bandWidth / 2
	}
}

// MARK: - Nice numbers & ticks

enum ChartTicks {
	/// Heckbert's nice-number rounding.
	static func nice(_ x: Double, round: Bool) -> Double {
		guard x.isFinite, x > 0 else { return 1 }
		let exp = floor(log10(x))
		let f = x / pow(10, exp)
		let nf: Double
		if round {
			nf = f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10))
		} else {
			nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10))
		}
		return nf * pow(10, exp)
	}

	/// Produce ~`count` "nice" tick values spanning [lo,hi] (inclusive).
	static func ticks(min lo: Double, max hi: Double, count: Int = 5) -> [Double] {
		guard lo.isFinite, hi.isFinite, lo < hi else {
			return [lo].filter { $0.isFinite }
		}
		let range = nice(hi - lo, round: false)
		let spacing = nice(range / Double(max(count - 1, 1)), round: true)
		let niceMin = floor(lo / spacing) * spacing
		let niceMax = ceil(hi / spacing) * spacing
		var ticks = [Double]()
		var v = niceMin
		var guard_ = 0
		while v <= niceMax + spacing * 0.5, guard_ < 1000 {
			ticks.append(round(v * 1000) / 1000)
			v += spacing
			guard_ += 1
		}
		return ticks
	}
}

// MARK: - Value formatting

/// Formats a numeric tick or data value into a label, honoring an
/// `AxisLabelFormat`.
enum ChartValueFormat {
	static func format(_ value: Double, _ style: AxisLabelFormat) -> String {
		switch style {
		case .hidden:
			return ""
		case .integer:
			return trim(formatNumber(value, decimals: 0))
		case .decimal(let d):
			return trim(String(format: "%.\(d)f", value))
		case .percent:
			// Swift Charts treats 0…1 as fractions.
			return trim(String(format: "%.0f%%", value * 100))
		case .currency(let code):
			return "\(htmlEscape(code)) " + trim(formatNumber(value, decimals: 0))
		case .numberCompact:
			return compact(value)
		case .automatic:
			return automatic(value)
		case .dateShort, .dateMonthYear, .dateWeekday:
			return format(Date(timeIntervalSinceReferenceDate: value), style)
		}
	}

	static func automatic(_ value: Double) -> String {
		if abs(value) >= 1_000_000 { return compact(value) }
		if value.rounded() == value && abs(value) < 1e15 {
			return trim(String(format: "%.0f", value))
		}
		return trim(formatNumber(value, decimals: 2))
	}

	static func compact(_ value: Double) -> String {
		let absValue = abs(value)
		let suffix: String
		let scaled: Double
		if absValue >= 1_000_000_000 { suffix = "B"; scaled = value / 1_000_000_000 }
		else if absValue >= 1_000_000 { suffix = "M"; scaled = value / 1_000_000 }
		else if absValue >= 1_000 { suffix = "k"; scaled = value / 1_000 }
		else { return automatic(value) }
		return trim(String(format: "%.1f", scaled)) + suffix
	}

	static func formatNumber(_ value: Double, decimals: Int) -> String {
		String(format: "%.\(decimals)f", value)
	}

	static func trim(_ s: String) -> String {
		var out = s
		if out.contains(".") {
			while out.hasSuffix("0") { out.removeLast() }
			if out.hasSuffix(".") { out.removeLast() }
		}
		return out
	}

	static func format(_ date: Date, _ style: AxisLabelFormat) -> String {
		let df = DateFormatter()
		df.locale = Locale(identifier: "en_US_POSIX")
		df.timeZone = TimeZone(identifier: "UTC")
		switch style {
		case .dateWeekday: df.dateFormat = "EEE"
		case .dateMonthYear: df.dateFormat = "MMM yyyy"
		default: df.dateFormat = "MMM d"
		}
		return df.string(from: date)
	}
}
