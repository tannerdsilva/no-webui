import Foundation
import WebUICore

// MARK: - Plottable data

/// The kinds of data a chart axis or mark dimension can hold.
///
/// Mirrors Swift Charts' `Plottable`. A plotted value is always a labelled
/// plottable (`.value("Sales", 42)`) so the axis knows both the human name
/// (for annotations/legends) and the value (for scaling).
public enum Plottable: Sendable, Hashable {
	case number(Double)
	case date(Date)
	case category(String)

	/// The kind of scale this value implies.
	public var scaleKind: ChartScaleKind {
		switch self {
		case .number: return .linear
		case .date: return .date
		case .category: return .categorical
		}
	}

	/// A normalized numeric position used for ordering and (for numbers)
	/// linear scaling. Categories are ordered by first appearance and mapped
	/// to their band index by the layout, so this is `nil` for them.
	public var numericValue: Double? {
		switch self {
		case .number(let v): return v
		case .date(let d): return d.timeIntervalSinceReferenceDate
		case .category: return nil
		}
	}
}

/// A labelled plottable — the argument every mark position takes.
///
/// Use the `.value(_:_:)` static factory: `x: .value("Month", "Jan")`,
/// `y: .value("Sales", 42)`, `y: .value("Day", date)`.
public struct PlottableValue: Sendable, Hashable {
	public let label: String
	public let value: Plottable

	public init(label: String, value: Plottable) {
		self.label = label
		self.value = value
	}

	public static func value(_ label: String, _ number: some BinaryFloatingPoint) -> PlottableValue {
		PlottableValue(label: label, value: .number(Double(number)))
	}
	public static func value(_ label: String, _ number: some BinaryInteger) -> PlottableValue {
		PlottableValue(label: label, value: .number(Double(exactly: number) ?? 0))
	}
	public static func value(_ label: String, _ date: Date) -> PlottableValue {
		PlottableValue(label: label, value: .date(date))
	}
	public static func value(_ label: String, _ category: String) -> PlottableValue {
		PlottableValue(label: label, value: .category(category))
	}
}

/// The scale family a plottable implies.
public enum ChartScaleKind: Sendable, Hashable {
	case linear
	case date
	case categorical
}

// MARK: - Scale configuration

/// An explicit (or automatic) scale type, mirroring `chartXScale`/`chartYScale`.
///
/// A `nil` domain means "infer from the data"; a non-nil domain pins the
/// scale (e.g. `barChartYScale(.linear(domain: 0...100))`).
public enum ChartScaleType: Sendable, Hashable {
	case automatic
	case linear(domain: ClosedRange<Double>?)
	case date(domain: ClosedRange<Date>?)
	case categorical(domain: [String]?)
	case normalized
}

extension ChartScaleType {
	public static var linear: ChartScaleType { .linear(domain: nil) }
	public static var date: ChartScaleType { .date(domain: nil) }
	public static var categorical: ChartScaleType { .categorical(domain: nil) }

	/// Resolve the requested scale against the actual data kind.
	public func kind(for plottable: Plottable) -> ChartScaleKind {
		switch self {
		case .automatic:
			return plottable.scaleKind
		case .linear(domain: _):
			return .linear
		case .date(domain: _):
			return .date
		case .categorical(domain: _):
			return .categorical
		case .normalized:
			return .linear
		}
	}
}

// MARK: - Axis

/// Where an axis sits on the chart.
public enum AxisPosition: Sendable, Hashable {
	case automatic
	case leading
	case trailing
	case top
	case bottom

	/// The side a *linear* (vertical value) axis labels sit on by default.
	public var isVerticalSide: Bool {
		switch self {
		case .leading, .trailing: return true
		case .top, .bottom, .automatic: return false
		}
	}
}

/// How numeric axis values are rendered as labels.
public enum AxisLabelFormat: Sendable, Hashable {
	case automatic
	case integer
	case decimal(Int)
	case percent
	case currency(String)
	case numberCompact
	case dateShort
	case dateMonthYear
	case dateWeekday
	case hidden
}

/// A configured axis, mirroring `chartXAxis`/`chartYAxis` + `AxisMarks`.
public struct AxisConfig: Sendable {
	public var position: AxisPosition
	public var labelFormat: AxisLabelFormat
	public var showsGrid: Bool
	public var showsTicks: Bool
	public var showsAxisLabel: Bool
	/// Explicit tick positions (values on the linear/date scale). When nil the
	/// layout computes ~5 "nice" ticks.
	public var explicitValues: [Double]?
	/// Optional human label for the whole axis (e.g. "Units sold").
	public var axisLabel: String?

	public init(
		position: AxisPosition = .automatic,
		labelFormat: AxisLabelFormat = .automatic,
		showsGrid: Bool = true,
		showsTicks: Bool = true,
		showsAxisLabel: Bool = false,
		explicitValues: [Double]? = nil,
		axisLabel: String? = nil
	) {
		self.position = position
		self.labelFormat = labelFormat
		self.showsGrid = showsGrid
		self.showsTicks = showsTicks
		self.showsAxisLabel = showsAxisLabel
		self.explicitValues = explicitValues
		self.axisLabel = axisLabel
	}

	public static let automatic = AxisConfig()
}

// MARK: - Legend

public enum LegendPosition: Sendable, Hashable {
	case automatic
	case top
	case bottom
	case leading
	case trailing
	case hidden
}

public struct LegendConfig: Sendable {
	public var position: LegendPosition
	public var showsLabels: Bool

	public init(position: LegendPosition = .automatic, showsLabels: Bool = true) {
		self.position = position
		self.showsLabels = showsLabels
	}
	public static let automatic = LegendConfig()
}

// MARK: - Selection & scrolling

public enum ChartAxis: Sendable, Hashable {
	case x
	case y
}

public struct SelectionConfig: Sendable {
	public var axis: ChartAxis
	/// The currently-selected value (server-driven; nil = none selected).
	public var value: Plottable?

	public init(axis: ChartAxis, value: Plottable?) {
		self.axis = axis
		self.value = value
	}
}

public struct ChartScrollAxes: OptionSet, Sendable, Hashable {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }
	public static let x = ChartScrollAxes(rawValue: 1 << 0)
	public static let y = ChartScrollAxes(rawValue: 1 << 1)
	public static let none = ChartScrollAxes([])
	public static let horizontal = x
	public static let vertical = y
	public static let both = ChartScrollAxes([.x, .y])
}

// MARK: - Mark geometry options

public enum ChartSymbolShape: Sendable, Hashable {
	case circle
	case square
	case triangle
	case diamond
	case cross
	case asterisk
	case none
}

public enum InterpolationMethod: Sendable, Hashable {
	case linear
	case catmullRom
	case monotone
	case cardinal(Double)
	case stepStart
	case stepEnd
}

public enum MarkStackingMethod: Sendable, Hashable {
	case normal
	case centered
	case unstacked
}

public enum MarkDimension: Sendable, Hashable {
	/// A proportion of the band (0…1) — how wide a bar is within its band.
	case ratio(Double)
	/// A fixed point width in viewBox units.
	case fixed(Double)
	/// Fit the band with a gap (default bar width).
	case automatic
}

// MARK: - Color

/// How a mark is colored.
public enum ChartColor: Sendable, Hashable {
	/// Use the automatic categorical palette (series index → `--color-chart-N`).
	case auto
	/// An explicit color. Either a CSS variable reference such as
	/// `"var(--color-danger)"` or a literal hex such as `"#6366f1"`.
	case explicit(String)
}

/// Mark stroke styling (dashes), mirroring `.lineStyle`.
public struct ChartLineStyle: Sendable, Hashable {
	public var width: Double
	public var dash: [Double]

	public init(width: Double = 2, dash: [Double] = []) {
		self.width = width
		self.dash = dash
	}
	public static let `default` = ChartLineStyle()
}

/// A mark's visual style.
public struct MarkStyle: Sendable, Hashable {
	public var color: ChartColor
	public var opacity: Double
	public var lineStyle: ChartLineStyle?
	public var foregroundScaleIndex: Int?   // resolved categorical slot (set by layout)

	public init(color: ChartColor = .auto, opacity: Double = 1, lineStyle: ChartLineStyle? = nil) {
		self.color = color
		self.opacity = opacity
		self.lineStyle = lineStyle
		self.foregroundScaleIndex = nil
	}
}

// MARK: - Annotation

public enum AnnotationPosition: Sendable, Hashable {
	case automatic
	case top
	case bottom
	case leading
	case trailing
	case overlay
}

public struct ChartAnnotation: Sendable {
	public var text: String
	public var position: AnnotationPosition

	public init(text: String, position: AnnotationPosition = .automatic) {
		self.text = text
		self.position = position
	}
}

// MARK: - Mark spec

/// The geometry + intent a single mark contributes to a chart, in *data*
/// space. The `Chart` layout converts these to pixel space and emits SVG.
public struct MarkSpec: Sendable {
	public var kind: MarkKind
	public var x: PlottableValue?
	public var y: PlottableValue?
	/// Range/band marks (area between two values, or a rule spanning a band).
	public var yStart: PlottableValue?
	public var yEnd: PlottableValue?
	/// Horizontal extent for band marks (RectangleMark cells).
	public var xStart: PlottableValue?
	public var xEnd: PlottableValue?
	/// Polar marks (SectorMark): the angle value.
	public var angle: PlottableValue?
	public var angleStart: PlottableValue?
	public var angleEnd: PlottableValue?
	/// Series grouping key (from `.foregroundStyle(by:)`).
	public var series: String?
	/// A human value for the legend / default annotation (e.g. "42").
	public var displayValue: String?
	public var symbol: ChartSymbolShape
	public var interpolation: InterpolationMethod
	public var cornerRadius: Double
	public var stacking: MarkStackingMethod
	public var barDimension: MarkDimension
	public var innerRadiusRatio: Double?   // SectorMark donut hole (0…1)
	public var angularInset: Double?       // SectorMark gap between sectors
	public var style: MarkStyle
	public var annotation: ChartAnnotation?
	/// Whether this mark should draw a point on top of a line/area.
	public var showsPoint: Bool
	/// Heatmap cell intensity in 0…1 (nil = solid fill).
	public var intensity: Double?

	public init(
		kind: MarkKind,
		x: PlottableValue? = nil,
		y: PlottableValue? = nil,
		yStart: PlottableValue? = nil,
		yEnd: PlottableValue? = nil,
		xStart: PlottableValue? = nil,
		xEnd: PlottableValue? = nil,
		angle: PlottableValue? = nil,
		angleStart: PlottableValue? = nil,
		angleEnd: PlottableValue? = nil,
		series: String? = nil,
		displayValue: String? = nil,
		symbol: ChartSymbolShape = .circle,
		interpolation: InterpolationMethod = .linear,
		cornerRadius: Double = 0,
		stacking: MarkStackingMethod = .normal,
		barDimension: MarkDimension = .automatic,
		innerRadiusRatio: Double? = nil,
		angularInset: Double? = nil,
		style: MarkStyle = MarkStyle(),
		annotation: ChartAnnotation? = nil,
		showsPoint: Bool = false,
		intensity: Double? = nil
	) {
		self.kind = kind
		self.x = x
		self.y = y
		self.yStart = yStart
		self.yEnd = yEnd
		self.xStart = xStart
		self.xEnd = xEnd
		self.angle = angle
		self.angleStart = angleStart
		self.angleEnd = angleEnd
		self.series = series
		self.displayValue = displayValue
		self.symbol = symbol
		self.interpolation = interpolation
		self.cornerRadius = cornerRadius
		self.stacking = stacking
		self.barDimension = barDimension
		self.innerRadiusRatio = innerRadiusRatio
		self.angularInset = angularInset
		self.style = style
		self.annotation = annotation
		self.showsPoint = showsPoint
		self.intensity = intensity
	}
}

/// The category of a mark.
public enum MarkKind: Sendable, Hashable {
	case bar
	case line
	case area
	case point
	case rectangle
	case rule
	case sector
}

// MARK: - Chart configuration

/// the handler attached via `.onSelectMark(_:)`: receives the chart's root
/// element (`me`) and the selected mark's category string, returns the
/// fragments to send.
public typealias ChartSelectHandler = @Sendable (ElementRef, String) async -> [FragmentUpdate]

/// The full configuration of a `Chart`, accumulated by the `chart*` modifiers.
public struct ChartConfig: Sendable {
	public var xScale: ChartScaleType
	public var yScale: ChartScaleType
	/// Override the linear y-domain (e.g. start bars at a non-zero baseline).
	public var yDomain: ClosedRange<Double>?
	/// Override the linear x-domain.
	public var xDomain: ClosedRange<Double>?
	public var xAxis: AxisConfig
	public var yAxis: AxisConfig
	public var legend: LegendConfig
	/// Ordered series → color mapping. When a series name is present, its
	/// index in `foregroundDomain` selects the palette slot.
	public var foregroundDomain: [String]
	public var foregroundRange: [ChartColor]
	public var selection: SelectionConfig?
	/// mark click handler; `nil` renders marks statically (no routing).
	/// wired per-mark under stable ids, so fragment re-renders keep routing.
	public var onSelectMark: ChartSelectHandler?
	public var scrollAxes: ChartScrollAxes
	/// Number of categorical x-units visible in a scrollable chart (0 = all).
	public var visibleDomain: Int
	/// Plot height in viewBox units (the layout derives width from the
	/// container's aspect ratio; the SVG uses `viewBox` + `width:100%`).
	public var height: Int
	/// Aspect ratio of the viewBox (width = height * aspectRatio).
	public var aspectRatio: Double
	/// A short human summary for `aria-label` when none is provided.
	public var accessLabel: String?
	/// An optional title rendered above the plot.
	public var title: String?
	/// Inner radius for a polar chart (0 = pie). Per-mark overrides win.
	public var innerRadius: Double?
	/// Angular inset for a polar chart. Per-mark overrides win.
	public var angularInset: Double?
	/// Whether to render a data-driven table for screen readers.
	public var showsAccessibilityTable: Bool

	public init() {
		self.xScale = .automatic
		self.yScale = .automatic
		self.yDomain = nil
		self.xDomain = nil
		self.xAxis = .automatic
		self.yAxis = .automatic
		self.legend = .automatic
		self.foregroundDomain = []
		self.foregroundRange = []
		self.selection = nil
		self.onSelectMark = nil
		self.scrollAxes = .none
		self.visibleDomain = 0
		self.height = 320
		self.aspectRatio = 2.0
		self.accessLabel = nil
		self.title = nil
		self.innerRadius = nil
		self.angularInset = nil
		self.showsAccessibilityTable = true
	}
}
