import WebUICore

// MARK: - p5 marks: radar, radial, gradients, tips

/// A radar (spider) mark: one closed polygon per series over a shared set of
/// axes, mirroring the shadcn radar-chart family. Every series must supply the
/// same axis labels in the same order.
///
/// ```swift
/// Chart {
///     RadarMark([("speed", 8), ("reliability", 6), ("cost", 4)], series: "region")
///         .foregroundStyle(.auto)
/// }
/// ```
public struct RadarMark: ChartContent {
	/// Axis label → value pairs, in clockwise order from 12 o'clock.
	public let values: [(label: String, value: Double)]
	public let series: String?

	public init(_ values: [(label: String, value: Double)], series: String? = nil) {
		self.values = values
		self.series = series
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(kind: .radar, series: series, radarValues: values))
	}
}

/// A radial (gauge) mark: a stroked arc on a ring, distinct from a sector —
/// `.radial` draws an *arc*, `.sector` a *filled wedge*. The plan's t2.
///
/// ```swift
/// Chart {
///     RadialMark(value: 72, of: 100, series: "cpu")
/// }
/// ```
public struct RadialMark: ChartContent {
	public let value: Double
	public let total: Double
	public let series: String?

	public init(value: Double, of total: Double = 100, series: String? = nil) {
		self.value = value
		self.total = total
		self.series = series
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(
			kind: .radial,
			y: .value("value", value),
			series: series,
			radialTotal: total
		))
	}
}

// MARK: - Gradients

/// A fill gradient for area marks (t4). Colors are `ChartColor` tokens, so the
/// definition can only reference design-system variables — never free-form
/// input — and the emitted `<linearGradient>` id is derived from the gradient's
/// own contents, which makes it stable across renders *and* collision-free when
/// several charts share a page.
public struct ChartGradient: Sendable, Hashable {
	public var colors: [ChartColor]

	public init(_ colors: [ChartColor]) {
		self.colors = colors.isEmpty ? [.auto] : colors
	}

	/// A two-stop fade of one token: opaque at the top, transparent at the base.
	public static func fade(_ color: ChartColor = .auto) -> ChartGradient {
		ChartGradient([color, .explicit("transparent")])
	}

	/// The stable, content-derived id scope for this gradient definition.
	func scopedId(series: String) -> String {
		var key = ""
		for c in colors {
			switch c {
			case .auto: key += "auto|"
			case .explicit(let value): key += value + "|"
			}
		}
		return "chart-grad-" + ChartGradient.fnv1a(key + series)
	}

	/// The CSS value for a stop color. `explicit` strings are filtered to a safe
	/// charset (these land in a `style` attribute), so a caller cannot inject
	/// arbitrary css into the emitted document.
	func cssColor(_ color: ChartColor) -> String {
		switch color {
		case .auto: return "var(--color-chart-1)"
		case .explicit(let value):
			let safe = value.filter { c in
				c.isLetter || c.isNumber || "-.,()#% ".contains(c)
			}
			return safe.isEmpty ? "var(--color-chart-1)" : safe
		}
	}

	/// FNV-1a/32 — deterministic, dependency-free (the chart target stays
	/// Foundation-free and must render byte-identically for the same input).
	static func fnv1a(_ s: String) -> String {
		var hash: UInt32 = 2166136261
		for byte in s.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 16777619
		}
		let digits = "0123456789abcdef"
		var out = ""
		var shift = 28
		while shift >= 0 {
			let nibble = Int((hash >> UInt32(shift)) & 0xF)
			out.append(Array(digits)[nibble])
			shift -= 4
		}
		return out
	}
}

// MARK: - p5 mark modifiers

extension ChartMark {
	/// Fill an area mark with a gradient instead of a flat token color.
	public func areaGradient(_ gradient: ChartGradient) -> ChartMark {
		var m = self
		m.spec.gradient = gradient
		return m
	}

	/// Explicit tooltip text (the css-only tip). Falls back to the mark's
	/// display value / y value when omitted.
	public func tooltip(_ text: String) -> ChartMark {
		var m = self
		m.spec.tooltip = text
		return m
	}
}