import Foundation
import WebUICore

// MARK: - Chart

/// A chart: renders a collection of marks (built with the same `ForEach` +
/// mark composition style as Swift Charts) to a single self-contained inline
/// `<svg>` inside a `.chart` figure. The server owns all state (selection,
/// scroll, series) — the view is a pure function of its marks + config.
///
/// ```swift
/// Chart {
///     ForEach(sales) { d in
///         BarMark(x: .value("Month", d.month), y: .value("Sales", d.amount))
///             .foregroundStyle(by: d.product)
///     }
/// }
/// .chartYScale(.linear(domain: 0...120))
/// .chartLegend(position: .bottom)
/// .chartXSelection(value: .category("March"))
/// ```
public struct Chart: View {
	public let marks: [ChartMark]
	public let config: ChartConfig
	/// Stable id for the outermost element (required for interactive
	/// selection/scroll — mirrors the table's stable-anchor pattern).
	public let id: String?
	/// Accessible name for the whole chart.
	public let ariaLabel: String?

	public init(@ViewBuilder content: () -> [any View]) {
		self.marks = content().flatMap { Chart.resolve($0) }
		self.config = ChartConfig()
		self.id = nil
		self.ariaLabel = nil
	}

	public init(_ marks: [ChartMark], config: ChartConfig = ChartConfig(), id: String? = nil, ariaLabel: String? = nil) {
		self.marks = marks
		self.config = config
		self.id = id
		self.ariaLabel = ariaLabel
	}

	public func render() -> String {
		ChartRenderer(marks: marks, config: config, id: id, ariaLabel: ariaLabel).render()
	}

	/// Extract marks from a view in the chart builder: a styled mark, a raw
	/// mark, a `ForEach` of marks, or a `Group` of those.
	static func resolve(_ view: any View) -> [ChartMark] {
		if let iterable = view as? ChartIterableMark {
			return iterable.resolvedMarks
		}
		if let group = view as? Group {
			return group.children.flatMap { resolve($0) }
		}
		if let mark = view as? ChartContent {
			return [mark.makeMark()]
		}
		return []
	}
}

// MARK: - Chart* modifiers (Swift Charts parity)

extension Chart {
	/// Override the x scale (mirrors `chartXScale`).
	public func chartXScale(_ scale: ChartScaleType) -> Chart {
		var c = config; c.xScale = scale; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Override the y scale.
	public func chartYScale(_ scale: ChartScaleType) -> Chart {
		var c = config; c.yScale = scale; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Pin the linear y-domain (e.g. bars from zero, or a fixed range).
	public func chartYDomain(_ range: ClosedRange<Double>) -> Chart {
		var c = config; c.yDomain = range; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Pin the linear x-domain.
	public func chartXDomain(_ range: ClosedRange<Double>) -> Chart {
		var c = config; c.xDomain = range; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Configure the x axis (mirrors `chartXAxis`).
	public func chartXAxis(_ axis: AxisConfig) -> Chart {
		var c = config; c.xAxis = axis; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Configure the y axis.
	public func chartYAxis(_ axis: AxisConfig) -> Chart {
		var c = config; c.yAxis = axis; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Configure the legend.
	public func chartLegend(position: LegendPosition = .automatic, showsLabels: Bool = true) -> Chart {
		var c = config; c.legend = LegendConfig(position: position, showsLabels: showsLabels)
		return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Map series names to colors (mirrors `chartForegroundStyleScale`).
	public func chartForegroundStyleScale(domain: [String], range: [ChartColor]) -> Chart {
		var c = config; c.foregroundDomain = domain; c.foregroundRange = range
		return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Enable + set the current selection (mirrors `chartXSelection(value:)` /
	/// `chartYSelection(value:)`). Server-driven: pass the selected value.
	public func chartSelection(axis: ChartAxis, value: Plottable?) -> Chart {
		var c = config; c.selection = SelectionConfig(axis: axis, value: value)
		return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Select an x value (mirrors `chartXSelection(value:)`).
	public func chartXSelection(value: Plottable?) -> Chart {
		chartSelection(axis: .x, value: value)
	}
	/// Select a y value (mirrors `chartYSelection(value:)`).
	public func chartYSelection(value: Plottable?) -> Chart {
		chartSelection(axis: .y, value: value)
	}
	/// Polar inner-radius ratio 0…1 (mirrors `SectorMark`'s donut hole).
	/// Per-mark `.innerRadius` wins when present.
	public func chartInnerRadius(_ ratio: Double?) -> Chart {
		var c = config; c.innerRadius = ratio; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Gap (degrees) between polar sectors.
	public func chartAngularInset(_ degrees: Double?) -> Chart {
		var c = config; c.angularInset = degrees; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Enable scrolling on the given axes (mirrors `chartScrollableAxes`).
	public func chartScrollableAxes(_ axes: ChartScrollAxes) -> Chart {
		var c = config; c.scrollAxes = axes; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// How many x-units are visible in a horizontal scroll (mirrors
	/// `chartXVisibleDomain`).
	public func chartXVisibleDomain(_ count: Int) -> Chart {
		var c = config; c.visibleDomain = count; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// Plot height in viewBox units.
	public func chartHeight(_ height: Int) -> Chart {
		var c = config; c.height = height; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// A title rendered above the plot.
	public func chartTitle(_ title: String) -> Chart {
		var c = config; c.title = title; return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
	/// An accessible label (overrides any inferred one).
	public func chartAccessibilityLabel(_ label: String) -> Chart {
		return Chart(marks, config: config, id: id, ariaLabel: label)
	}
	/// A stable id for interactive selection/scroll.
	public func chartID(_ id: String) -> Chart {
		return Chart(marks, config: config, id: id, ariaLabel: ariaLabel)
	}

	/// Attach a mark-click handler. `me` references the chart root element
	/// (the `<figure>` carrying `chartID`); the second argument is the clicked
	/// mark's category string (the bar's x-category, or the sector's
	/// series/angle label). the component wires each mark as a routed
	/// component under stable ids, so re-rendered figures keep routing.
	public func onSelectMark(_ handler: @escaping ChartSelectHandler) -> Chart {
		var c = config
		c.onSelectMark = handler
		return Chart(marks, config: c, id: id, ariaLabel: ariaLabel)
	}
}

// MARK: - Mark resolution bridge

/// A view that can produce chart marks (implemented by `ForEach`).
public protocol ChartIterableMark: View {
	var resolvedMarks: [ChartMark] { get }
}

extension ForEach: ChartIterableMark {
	public var resolvedMarks: [ChartMark] {
		data.flatMap { el -> [ChartMark] in
			content(el).flatMap { Chart.resolve($0) }
		}
	}
}

// MARK: - Mark View conformances

/// A styled mark renders nothing on its own — it only has meaning inside a
/// `Chart`. (Matches how a `ChartMark` is not a standalone SwiftUI view.)
extension ChartMark: View, ChartContent {
	public func render() -> String { "" }
	public func makeMark() -> ChartMark { self }
}
