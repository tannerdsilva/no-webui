import Foundation
import WebUI

// MARK: - ChartMark

/// A styled, modifiable mark. Every `*Mark` initializer returns one, and the
/// `.foregroundStyle(by:)` / `.symbol` / `.interpolation` / `.annotation` /
/// `.lineStyle` / `.cornerRadius` / `.stacking` modifiers decorate it — the
/// same composition style as Swift Charts.
///
/// A mark is an *intent* (data-space geometry + styling). The `Chart`
/// converts the collection of marks to pixel space and emits inline SVG.
public struct ChartMark: Sendable {
	public var spec: MarkSpec
	/// Per-mark override for a categorical x position (used when `x` is a
	/// number but the caller wants a band, e.g. date bars).
	public var categoricalX: String?

	public init(spec: MarkSpec) {
		self.spec = spec
		self.categoricalX = nil
	}

	// MARK: Styling

	public func foregroundStyle(_ color: ChartColor) -> ChartMark {
		var m = self
		m.spec.style.color = color
		return m
	}

	/// Assign the mark to a categorical series and color it from the
	/// chart's foreground scale (the `.foregroundStyle(by:)` analogue).
	public func foregroundStyle(by series: String) -> ChartMark {
		var m = self
		m.spec.series = series
		return m
	}

	public func symbol(_ shape: ChartSymbolShape) -> ChartMark {
		var m = self
		m.spec.symbol = shape
		return m
	}

	public func interpolation(_ method: InterpolationMethod) -> ChartMark {
		var m = self
		m.spec.interpolation = method
		return m
	}

	public func lineStyle(_ style: ChartLineStyle) -> ChartMark {
		var m = self
		m.spec.style.lineStyle = style
		return m
	}

	public func cornerRadius(_ radius: Double) -> ChartMark {
		var m = self
		m.spec.cornerRadius = radius
		return m
	}

	public func opacity(_ value: Double) -> ChartMark {
		var m = self
		m.spec.style.opacity = value
		return m
	}

	public func stacking(_ method: MarkStackingMethod) -> ChartMark {
		var m = self
		m.spec.stacking = method
		return m
	}

	/// Annotate this mark with a value label (e.g. the y value above a bar).
	public func annotation(_ text: String, position: AnnotationPosition = .automatic) -> ChartMark {
		var m = self
		m.spec.annotation = ChartAnnotation(text: text, position: position)
		return m
	}
}

// MARK: - BarMark

/// Bars, mirroring Swift Charts `BarMark`.
///
/// Use the x/y forms for a standard bar chart. Pass a `width:` for explicit
/// bar width; `.stacking` and `.foregroundStyle(by:)` (via the returned
/// `ChartMark`) control grouping/stacking and per-series color.
public struct BarMark: ChartContent {
	public let x: PlottableValue
	public let y: PlottableValue
	public let width: MarkDimension?

	public init(x: PlottableValue, y: PlottableValue, width: MarkDimension? = nil) {
		self.x = x
		self.y = y
		self.width = width
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(
			kind: .bar,
			x: x, y: y,
			barDimension: width ?? .automatic
		))
	}
}

// MARK: - LineMark

/// Connected line segments, mirroring `LineMark`.
public struct LineMark: ChartContent {
	public let x: PlottableValue
	public let y: PlottableValue

	public init(x: PlottableValue, y: PlottableValue) {
		self.x = x
		self.y = y
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(kind: .line, x: x, y: y))
	}
}

// MARK: - AreaMark

/// Filled regions, mirroring `AreaMark`. Supports a single `y` (fill to
/// baseline) or a `yStart`/`yEnd` band.
public struct AreaMark: ChartContent {
	public let x: PlottableValue
	public let y: PlottableValue?
	public let yStart: PlottableValue?
	public let yEnd: PlottableValue?

	public init(x: PlottableValue, y: PlottableValue) {
		self.x = x; self.y = y; self.yStart = nil; self.yEnd = nil
	}

	public init(x: PlottableValue, yStart: PlottableValue, yEnd: PlottableValue) {
		self.x = x; self.y = nil; self.yStart = yStart; self.yEnd = yEnd
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(kind: .area, x: x, y: y, yStart: yStart, yEnd: yEnd))
	}
}

// MARK: - PointMark

/// Scatter points, mirroring `PointMark`.
public struct PointMark: ChartContent {
	public let x: PlottableValue
	public let y: PlottableValue
	public let symbol: ChartSymbolShape

	public init(x: PlottableValue, y: PlottableValue, symbol: ChartSymbolShape = .circle) {
		self.x = x; self.y = y; self.symbol = symbol
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(kind: .point, x: x, y: y, symbol: symbol))
	}
}

// MARK: - RectangleMark

/// Rectangles — the basis of a heatmap, mirroring `RectangleMark`.
/// `xStart/xEnd` + `yStart/yEnd` define the cell in data space.
public struct RectangleMark: ChartContent {
	public let xStart: PlottableValue
	public let xEnd: PlottableValue
	public let yStart: PlottableValue
	public let yEnd: PlottableValue
	/// Heat intensity in 0…1 (drives `fill-opacity`).
	public let value: Double?

	public init(xStart: PlottableValue, xEnd: PlottableValue, yStart: PlottableValue, yEnd: PlottableValue, value: Double? = nil) {
		self.xStart = xStart; self.xEnd = xEnd
		self.yStart = yStart; self.yEnd = yEnd
		self.value = value
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(
			kind: .rectangle,
			yStart: yStart,
			yEnd: yEnd,
			xStart: xStart,
			xEnd: xEnd,
			intensity: value
		))
	}
}

// MARK: - RuleMark

/// A reference line, mirroring `RuleMark`. A single-valued `y:` makes a
/// horizontal rule; `x:` a vertical one.
public struct RuleMark: ChartContent {
	public let x: PlottableValue?
	public let y: PlottableValue?

	public init(y: PlottableValue) {
		self.x = nil; self.y = y
	}
	public init(x: PlottableValue) {
		self.x = x; self.y = nil
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(kind: .rule, x: x, y: y))
	}
}

// MARK: - SectorMark

/// A pie/donut sector, mirroring `SectorMark`. `angle` is the magnitude; the
/// donut hole comes from the chart's `.innerRadius` or the mark's
/// `.donutHole` / per-mark ratio. `angularInset` opens a gap between sectors.
public struct SectorMark: ChartContent {
	public let angle: PlottableValue
	/// Optional category label shown in the legend.
	public let category: String?
	public let innerRadiusRatio: Double?
	public let angularInset: Double?

	public init(
		angle: PlottableValue,
		category: String? = nil,
		innerRadiusRatio: Double? = nil,
		angularInset: Double? = nil
	) {
		self.angle = angle
		self.category = category
		self.innerRadiusRatio = innerRadiusRatio
		self.angularInset = angularInset
	}

	public func makeMark() -> ChartMark {
		ChartMark(spec: MarkSpec(
			kind: .sector,
			angle: angle,
			series: category,
			displayValue: category,
			innerRadiusRatio: innerRadiusRatio,
			angularInset: angularInset
		))
	}
}

// MARK: - ChartContent

/// A mark the `Chart` can render. Initializers for the concrete `*Mark`
/// structs return `ChartContent` so `ForEach(data) { Mark(...) }` composes,
/// and the shared mark modifiers are available directly on any mark —
/// mirroring how Swift Charts lets you write `BarMark(…).foregroundStyle(by:)`.
///
/// A mark is not a standalone page view: `render()` is empty. It only has
/// meaning inside a `Chart`.
public protocol ChartContent: View {
	func makeMark() -> ChartMark
}

extension ChartContent {
	/// Marks render nothing outside a `Chart` — they are resolved into the
	/// chart's SVG by the `Chart` itself.
	public func render() -> String { "" }

	/// An explicit color for this mark: a CSS variable reference such as
	/// `"var(--color-danger)"` or a literal hex such as `"#6366f1"`.
	/// (The `foregroundStyle` analogue.)
	public func foregroundStyle(_ color: String) -> ChartMark {
		mutate { $0.spec.style.color = .explicit(color) }
	}

	/// Assign the mark to a categorical series and color it from the
	/// chart's foreground scale (the `.foregroundStyle(by:)` analogue).
	public func foregroundStyle(by series: String) -> ChartMark {
		mutate { $0.spec.series = series }
	}

	public func symbol(_ shape: ChartSymbolShape) -> ChartMark {
		mutate { $0.spec.symbol = shape }
	}

	public func interpolation(_ method: InterpolationMethod) -> ChartMark {
		mutate { $0.spec.interpolation = method }
	}

	public func lineStyle(_ style: ChartLineStyle) -> ChartMark {
		mutate { $0.spec.style.lineStyle = style }
	}

	public func cornerRadius(_ radius: Double) -> ChartMark {
		mutate { $0.spec.cornerRadius = radius }
	}

	public func opacity(_ value: Double) -> ChartMark {
		mutate { $0.spec.style.opacity = value }
	}

	public func stacking(_ method: MarkStackingMethod) -> ChartMark {
		mutate { $0.spec.stacking = method }
	}

	/// Annotate this mark with a value label (e.g. the y value above a bar).
	public func annotation(_ text: String, position: AnnotationPosition = .automatic) -> ChartMark {
		mutate { $0.spec.annotation = ChartAnnotation(text: text, position: position) }
	}

	/// Draw a point symbol on top of this mark's line/area position.
	public func symbolPoint(_ show: Bool = true) -> ChartMark {
		mutate { $0.spec.showsPoint = show }
	}

	private func mutate(_ body: (inout ChartMark) -> Void) -> ChartMark {
		var m = makeMark()
		body(&m)
		return m
	}
}
