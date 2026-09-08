import Foundation
import WebUI

// MARK: - ChartRenderer

/// Lays out a collection of marks into pixel space and emits a single,
/// self-contained inline `<svg>` chart. The renderer is a pure function of
/// `marks` + `config`: it performs no I/O and holds no state, so re-rendering
/// the same input produces byte-identical output (deterministic + testable).
struct ChartRenderer {
	let marks: [ChartMark]
	let config: ChartConfig
	let id: String?
	let ariaLabel: String?

	/// Convenience: the resolved interactive id prefix (nil = non-interactive).
	private var markIdPrefix: String? { safeId.map { "\($0)-mark" } }

	/// HTML5 ids may not contain spaces — sanitize before emitting.
	private var safeId: String? { id.map { $0.replacingOccurrences(of: " ", with: "") } }

	func render() -> String {
		guard !marks.isEmpty else {
			return emptyState
		}
		let hasPolar = marks.contains { $0.spec.kind == .sector }
		return hasPolar ? renderPolar() : renderCartesian()
	}

	// MARK: Layout metrics

	private struct Metrics {
		var width: Int
		var height: Int
		var marginLeft: Int
		var marginRight: Int
		var marginTop: Int
		var marginBottom: Int
		var plotLeft: Int
		var plotRight: Int
		var plotTop: Int
		var plotBottom: Int
		var plotWidth: Int
		var plotHeight: Int
	}

	private func metrics() -> Metrics {
		let h = max(120, config.height)
		let w = Int((Double(h) * config.aspectRatio).rounded())
		let ml = config.yAxis.showsAxisLabel ? 56 : (needsYAxisLabels ? 44 : 16)
		let mr: Int
		if config.legend.position == .trailing { mr = 108 }
		else { mr = 16 }
		let mt: Int
		switch config.legend.position {
		case .top: mt = config.title == nil ? 44 : 64
		default: mt = config.title == nil ? 20 : 44
		}
		let mb = (config.xAxis.showsAxisLabel || needsXAxisLabels) ? 40 : 16
		let plotLeft = ml
		let plotRight = w - mr
		let plotTop = mt
		let plotBottom = h - mb
		return Metrics(width: w, height: h, marginLeft: ml, marginRight: mr, marginTop: mt,
		               marginBottom: mb, plotLeft: plotLeft, plotRight: plotRight, plotTop: plotTop,
		               plotBottom: plotBottom, plotWidth: max(1, plotRight - plotLeft),
		               plotHeight: max(1, plotBottom - plotTop))
	}

	private var needsYAxisLabels: Bool { config.yAxis.showsGrid || config.yAxis.showsTicks || config.yAxis.showsAxisLabel }
	private var needsXAxisLabels: Bool { config.xAxis.showsGrid || config.xAxis.showsTicks || config.xAxis.showsAxisLabel }

	// MARK: Series & color

	private var seriesOrder: [String] {
		var order = [String]()
		var seen = Set<String>()
		for m in marks {
			let s = m.spec.series ?? "(default)"
			if !seen.contains(s) { seen.insert(s); order.append(s) }
		}
		return order.isEmpty ? ["(default)"] : order
	}

	private var seriesColorIndex: [String: Int] {
		var m = [String: Int]()
		for (i, s) in seriesOrder.enumerated() { m[s] = i % 8 }
		return m
	}

	/// The color class for a mark's series (`.chart__c1` … `.chart__c8`).
	private func colorClass(_ mark: ChartMark) -> String {
		if case .explicit = mark.spec.style.color { return "chart__mark" }
		let series = mark.spec.series ?? seriesOrder[0]
		return "chart__c\((seriesColorIndex[series] ?? 0) + 1)"
	}

	/// An inline `--chart-mark-color` override for explicit colors.
	private func explicitColorStyle(_ mark: ChartMark) -> String {
		if case .explicit(let c) = mark.spec.style.color {
			return " style=\"--chart-mark-color:\(htmlEscape(c))\""
		}
		return ""
	}

	/// An SVG `opacity` presentation attribute for non-opaque marks.
	private func opacityAttr(_ mark: ChartMark) -> String {
		mark.spec.style.opacity == 1 ? "" : " opacity=\"\(fmt(mark.spec.style.opacity))\""
	}

	// MARK: Figure / empty state

	private var emptyState: String {
		let label = htmlEscape(ariaLabel ?? config.accessLabel ?? "Chart")
		var html = "<figure class=\"chart chart--empty\""
		if let safeId { html += " id=\"\(htmlEscape(safeId))\"" }
		html += " role=\"img\" aria-label=\"\(label)\">"
		html += "<figcaption class=\"chart__empty\"><span class=\"chart__empty-title\">No data</span>"
		html += "<span class=\"chart__empty-message\">Add points to display a chart.</span></figcaption>"
		html += "</figure>"
		return html
	}

	private func ariaDescription() -> String {
		ariaLabel ?? config.accessLabel ?? "Chart with \(marks.count) marks"
	}

	// MARK: Polar (pie / donut)

	private func renderPolar() -> String {
		let m = metrics()
		let label = htmlEscape(ariaDescription())
		var html = "<figure class=\"chart chart--pie\""
		if let safeId { html += " id=\"\(htmlEscape(safeId))\"" }
		html += " role=\"img\" aria-label=\"\(label)\">"
		if let title = config.title { html += "<figcaption class=\"chart__title\">\(htmlEscape(title))</figcaption>" }

		// total
		let sectors = marks.filter { $0.spec.kind == .sector }
		let total = sectors.reduce(0.0) { $0 + ($1.spec.angle?.value.numericValue ?? 0) }
		guard total > 0 else {
			html += "<svg class=\"chart__svg\" viewBox=\"0 0 \(m.width) \(m.height)\"></svg>"
			html += "</figure>"
			return html
		}

		let cx = Double(m.width) / 2
		let cy = Double(m.height) / 2
		let outerR = Double(min(m.width, m.height)) / 2 - 12
		let holeRatio = sectors.first?.spec.innerRadiusRatio ?? config.innerRadius ?? 0
		let innerR = outerR * holeRatio
		let gap = sectors.first?.spec.angularInset ?? config.angularInset ?? 0

		html += "<svg class=\"chart__svg\" viewBox=\"0 0 \(m.width) \(m.height)\" role=\"presentation\">"
		var startAngle = 0.0  // 0° = 12 o'clock, clockwise (geometry convention)
		let selectedValue = config.selection?.value
		for (i, sector) in sectors.enumerated() {
			let value = sector.spec.angle?.value.numericValue ?? 0
			let sweep = (value / total) * 360.0
			let a0 = startAngle + gap / 2
			let a1 = startAngle + sweep - gap / 2
			let path = ChartGeometry.sectorPath(centerX: cx, centerY: cy, innerRadius: innerR,
			                                    outerRadius: outerR, startAngle: a0, endAngle: a1)
			let color = colorClass(sector)
			let isSelected = sectorMatchesSelection(sector, selectedValue)
			let cls = "chart__mark \(color) chart__sector" + (isSelected ? " chart__mark--selected" : "")
			var attrs = " class=\"\(cls)\"" + explicitColorStyle(sector)
			if let mid = markIdPrefix { attrs += " id=\"\(htmlEscape("\(mid)-\(i)"))\"" }
			let sectorLabel = sector.spec.series ?? sector.spec.angle?.label ?? "Sector"
			if let handler = config.onSelectMark, let mid = markIdPrefix {
				let me = ElementRef.stable(safeId ?? "chart")
				attrs += controlAttributes(
					id: "\(mid)-\(i)",
					handler: { event in await handler(me, sectorLabel) }
				)
			}
			let pct = Int((value / total * 100).rounded())
			html += "<g\(attrs)><title>\(htmlEscape(sectorLabel)): \(pct)%</title><path d=\"\(path)\"/></g>"
			startAngle += sweep
		}
		html += "</svg>"

		if holeRatio > 0 {
			html += "<figcaption class=\"chart__donut-center\">"
			html += "<span class=\"chart__donut-value\">\(Int(total.rounded()))</span>"
			html += "<span class=\"chart__donut-label\">Total</span></figcaption>"
		}

		if config.legend.position != .hidden && sectors.count > 1 {
			html += legend(sectors: sectors, position: config.legend.position)
		}
		if config.showsAccessibilityTable {
			html += accessibilityTable(sectors: sectors, total: total)
		}
		html += "</figure>"
		return html
	}

	private func sectorMatchesSelection(_ sector: ChartMark, _ value: Plottable?) -> Bool {
		guard let value else { return false }
		if case .category(let vc) = value { return sector.spec.series == vc }
		if case .number(let vn) = value { return abs((sector.spec.angle?.value.numericValue ?? 0) - vn) < 0.001 }
		return false
	}

	// MARK: Cartesian

	private func renderCartesian() -> String {
		let m = metrics()
		let label = htmlEscape(ariaDescription())
		let xIsCategorical = isCategoricalX
		let xBands = xAxisCategories
		let (yLo, yHi) = yDomain

		let xLinear = linearXScale(m, domain: xDomainOrFallback(m), inverted: false)
		let xBanded = xBandedScale(m)
		let yDomainFinal = config.yDomain ?? explicitDomain(config.yScale) ?? yLo...yHi
		let yScale = ChartLinearScale(domain: yDomainFinal, rangeStart: Double(m.plotBottom), rangeEnd: Double(m.plotTop), inverted: true)  // inverted: up = high

		var html = "<figure class=\"chart\""
		if let safeId { html += " id=\"\(htmlEscape(safeId))\"" }
		html += " role=\"img\" aria-label=\"\(label)\">"
		if let title = config.title { html += "<figcaption class=\"chart__title\">\(htmlEscape(title))</figcaption>" }

		html += "<div class=\"chart__plot\">"
		html += "<svg class=\"chart__svg\" viewBox=\"0 0 \(m.width) \(m.height)\" role=\"presentation\">"

		// gridlines + axis ticks (behind marks)
		html += renderGrid(m: m, yScale: yScale, xLinear: xLinear, xBanded: xBanded, xIsCategorical: xIsCategorical, xBands: xBands)

		// marks
		html += renderMarks(m: m, yScale: yScale, xLinear: xLinear, xBanded: xBanded, xIsCategorical: xIsCategorical, xBands: xBands)

		// selection indicator
		if let sel = config.selection {
			html += renderSelection(m: m, sel: sel, xLinear: xLinear, xBanded: xBanded, xIsCategorical: xIsCategorical, yScale: yScale)
		}

		// axis labels (front)
		html += renderAxisLabels(m: m, yScale: yScale, xLinear: xLinear, xBanded: xBanded, xIsCategorical: xIsCategorical, xBands: xBands)

		html += "</svg></div>"

		// legend
		if config.legend.position != .hidden {
			html += legendForCartesian(position: config.legend.position)
		}

		if config.showsAccessibilityTable {
			html += accessibilityTableCartesian()
		}

		html += "</figure>"
		return html
	}

	// MARK: Domain helpers

	private var isCategoricalX: Bool {
		guard let first = marks.first(where: { $0.spec.x != nil })?.spec.x else { return false }
		if case .category = first.value { return true }
		// honor an explicit categorical scale
		if case .categorical = config.xScale { return true }
		return false
	}

	private var xAxisCategories: [String] {
		if case .categorical(let domain?) = config.xScale { return domain }
		var order = [String]()
		var seen = Set<String>()
		for mark in marks {
			guard let x = mark.spec.x, case .category(let c) = x.value else { continue }
			if !seen.contains(c) { seen.insert(c); order.append(c) }
		}
		return order.isEmpty ? [""] : order
	}

	private var xDomain: ClosedRange<Double>? {
		var vals = [Double]()
		for mark in marks {
			if let x = mark.spec.x, let v = x.value.numericValue { vals.append(v) }
			if let xs = mark.spec.xStart?.value.numericValue { vals.append(xs) }
			if let xe = mark.spec.xEnd?.value.numericValue { vals.append(xe) }
		}
		guard let lo = vals.min(), let hi = vals.max() else { return nil }
		return lo...hi
	}

	/// The resolved linear x domain: explicit `chartXDomain` → the scale's
	/// pinned domain (`.chartXScale(.linear(domain:))`) → inferred from data.
	private func xDomainOrFallback(_ m: Metrics) -> ClosedRange<Double> {
		config.xDomain ?? explicitDomain(config.xScale) ?? xDomain ?? 0...1
	}

	/// The domain pinned by a scale type, if any (`nil` = infer from data).
	private func explicitDomain(_ scale: ChartScaleType) -> ClosedRange<Double>? {
		switch scale {
		case .linear(let d?): return d
		case .date(let d?):
			return d.lowerBound.timeIntervalSinceReferenceDate...d.upperBound.timeIntervalSinceReferenceDate
		case .automatic, .categorical, .normalized,
			 .linear(nil), .date(nil):
			return nil
		}
	}

	/// A resolved categorical x scale, when the x-axis is categorical.
	private func xBandedScale(_ m: Metrics) -> ChartBandedScale? {
		guard isCategoricalX else { return nil }
		return bandedScale(m, categories: xAxisCategories)
	}

	private var yDomain: (Double, Double) {
		var vals = [Double]()
		let hasBars = marks.contains { $0.spec.kind == .bar }
		// stacked bars: the stack top must fit, so sum per category;
		// unstacked bars keep their individual values.
		if hasBars {
			var sums = [String: Double]()
			for mark in marks where mark.spec.kind == .bar {
				let v = mark.spec.y?.value.numericValue ?? 0
				switch mark.spec.stacking {
				case .normal, .centered:
					sums[categoryKey(mark.spec.x?.value) ?? "0", default: 0] += v
				default:
					vals.append(v)
				}
			}
			vals.append(contentsOf: sums.values)
		}
		for mark in marks where mark.spec.kind != .bar {
			if let v = mark.spec.y?.value.numericValue { vals.append(v) }
			if let ys = mark.spec.yStart?.value.numericValue { vals.append(ys) }
			if let ye = mark.spec.yEnd?.value.numericValue { vals.append(ye) }
		}
		guard let lo0 = vals.min(), let hi0 = vals.max() else { return (0, 1) }
		let lo = hasBars ? min(lo0, 0) : lo0
		if hasBars { return (lo, hi0) }
		let span = hi0 - lo
		let headroom = span > 0 ? span * 0.08 : 1
		return (lo, hi0 + headroom)
	}

	// MARK: Scales (build)

	private func bandedScale(_ m: Metrics, categories: [String]) -> ChartBandedScale {
		ChartBandedScale(categories: categories,
		                 rangeStart: Double(m.plotLeft), rangeEnd: Double(m.plotRight),
		                 paddingInner: 0.25, paddingOuter: 0.05)
	}

	private func linearXScale(_ m: Metrics, domain: ClosedRange<Double>, inverted: Bool) -> ChartLinearScale {
		ChartLinearScale(domain: domain, rangeStart: Double(m.plotLeft), rangeEnd: Double(m.plotRight), inverted: inverted)
	}

	// MARK: Grid + axis

	private func renderGrid(m: Metrics, yScale: ChartLinearScale, xLinear: ChartLinearScale, xBanded: ChartBandedScale?, xIsCategorical: Bool, xBands: [String]) -> String {
		var out = ""
		// horizontal gridlines from y ticks
		if config.yAxis.showsGrid {
			for v in yTicks(yScale) {
				let y = Int(yScale.position(v).rounded())
				guard y >= m.plotTop, y <= m.plotBottom else { continue }
				out += "<line class=\"chart__grid\" x1=\"\(m.plotLeft)\" y1=\"\(y)\" x2=\"\(m.plotRight)\" y2=\"\(y)\"/>"
			}
		}
		// vertical gridlines (categorical: at band centers; numeric: at x ticks)
		if config.xAxis.showsGrid {
			if xIsCategorical, let banded = xBanded {
				for c in xBands {
					let x = Int(banded.center(of: c).rounded())
					out += "<line class=\"chart__grid chart__grid--v\" x1=\"\(x)\" y1=\"\(m.plotTop)\" x2=\"\(x)\" y2=\"\(m.plotBottom)\"/>"
				}
			} else {
				for v in xTicks(xLinear) {
					let x = Int(xLinear.position(v).rounded())
					out += "<line class=\"chart__grid chart__grid--v\" x1=\"\(x)\" y1=\"\(m.plotTop)\" x2=\"\(x)\" y2=\"\(m.plotBottom)\"/>"
				}
			}
		}
		// baseline
		out += "<line class=\"chart__baseline\" x1=\"\(m.plotLeft)\" y1=\"\(m.plotBottom)\" x2=\"\(m.plotRight)\" y2=\"\(m.plotBottom)\"/>"
		return out
	}

	private func yTicks(_ scale: ChartLinearScale) -> [Double] {
		if let explicit = config.yAxis.explicitValues { return explicit }
		return inDomain(ChartTicks.ticks(min: scale.domain.lowerBound, max: scale.domain.upperBound, count: 5),
		                domain: scale.domain)
	}
	private func xTicks(_ scale: ChartLinearScale) -> [Double] {
		if let explicit = config.xAxis.explicitValues { return explicit }
		return inDomain(ChartTicks.ticks(min: scale.domain.lowerBound, max: scale.domain.upperBound, count: 6),
		                domain: scale.domain)
	}

	/// Drops ticks that fall outside the resolved domain (the nice-number
	/// algorithm may overshoot; a clamped-outside tick would mislabel the
	/// plot edge).
	private func inDomain(_ ticks: [Double], domain: ClosedRange<Double>) -> [Double] {
		ticks.filter { $0 >= domain.lowerBound - 0.0001 && $0 <= domain.upperBound + 0.0001 }
	}

	private func renderAxisLabels(m: Metrics, yScale: ChartLinearScale, xLinear: ChartLinearScale, xBanded: ChartBandedScale?, xIsCategorical: Bool, xBands: [String]) -> String {
		var out = ""
		// y labels
		if config.yAxis.showsTicks || config.yAxis.showsAxisLabel {
			for v in yTicks(yScale) {
				let y = Int(yScale.position(v).rounded())
				guard y >= m.plotTop - 1, y <= m.plotBottom + 1 else { continue }
				let text = ChartValueFormat.format(v, config.yAxis.labelFormat)
				if text.isEmpty { continue }
				out += "<text class=\"chart__axis-label\" x=\"\(m.plotLeft - 6)\" y=\"\(y + 3)\" text-anchor=\"end\">\(htmlEscape(text))</text>"
			}
		}
		// x labels
		if xIsCategorical, let banded = xBanded {
			if config.xAxis.showsTicks || config.xAxis.showsAxisLabel {
				for c in xBands where c != "" {
					let x = Int(banded.center(of: c).rounded())
					out += "<text class=\"chart__axis-label chart__axis-label--x\" x=\"\(x)\" y=\"\(m.plotBottom + 16)\" text-anchor=\"middle\">\(htmlEscape(c))</text>"
				}
			}
		} else {
			for v in xTicks(xLinear) {
				let x = Int(xLinear.position(v).rounded())
				guard x >= m.plotLeft - 1, x <= m.plotRight + 1 else { continue }
				let text = ChartValueFormat.format(v, config.xAxis.labelFormat)
				if text.isEmpty { continue }
				out += "<text class=\"chart__axis-label chart__axis-label--x\" x=\"\(x)\" y=\"\(m.plotBottom + 16)\" text-anchor=\"middle\">\(htmlEscape(text))</text>"
			}
		}
		// axis titles
		if config.yAxis.showsAxisLabel, let lbl = config.yAxis.axisLabel {
			out += "<text class=\"chart__axis-title\" x=\"14\" y=\"\(m.plotTop - 6)\" text-anchor=\"start\">\(htmlEscape(lbl))</text>"
		}
		if config.xAxis.showsAxisLabel, let lbl = config.xAxis.axisLabel {
			out += "<text class=\"chart__axis-title\" x=\"\(m.plotRight)\" y=\"\(m.height - 4)\" text-anchor=\"end\">\(htmlEscape(lbl))</text>"
		}
		return out
	}

	private var xPlottableKind: Plottable {
		for m in marks { if let x = m.spec.x { return x.value } }
		return .number(0)
	}

	// MARK: Marks

	private func renderMarks(m: Metrics, yScale: ChartLinearScale, xLinear: ChartLinearScale, xBanded: ChartBandedScale?, xIsCategorical: Bool, xBands: [String]) -> String {
		var out = ""
		if xIsCategorical, let banded = xBanded {
			out += renderBarMarks(m: m, yScale: yScale, banded: banded, xBands: xBands)
			out += renderLineAreaPoint(m: m, yScale: yScale, xLinear: xLinear, xBanded: banded, xBands: xBands)
		} else {
			out += renderRectMarks(m: m, yScale: yScale, xLinear: xLinear)
			out += renderRuleMarks(m: m, yScale: yScale)
			out += renderLineAreaPoint(m: m, yScale: yScale, xLinear: xLinear, xBanded: nil, xBands: [])
			out += renderBarMarksLinear(m: m, yScale: yScale, xLinear: xLinear)
		}
		return out
	}

	private func yPos(_ value: Double, _ yScale: ChartLinearScale) -> Double { yScale.position(value) }

	// grouped / stacked bars for a categorical (banded) x-axis.
	private func renderBarMarks(m: Metrics, yScale: ChartLinearScale, banded: ChartBandedScale, xBands: [String]) -> String {
		var out = ""
		let bars = marks.filter { $0.spec.kind == .bar }
		guard !bars.isEmpty else { return out }
		let stacking = bars.first?.spec.stacking ?? .normal
		let series = seriesOrder
		let zeroY = yScale.position(0)
		// per-category series count (grouped bars subdivide the band by it)
		var perCatCount = [String: Int]()
		for bar in bars {
			if let c = categoryKey(bar.spec.x?.value) { perCatCount[c, default: 0] += 1 }
		}

		// group bars per category
		var byCategory = [String: [(seriesIndex: Int, value: Double, mark: ChartMark)]]()
		for bar in bars {
			guard let cat = bar.spec.x?.value as? Plottable, case .category(let c) = cat else { continue }
			let sIndex = bar.spec.series.map { series.firstIndex(of: $0) ?? 0 } ?? 0
			byCategory[c, default: []].append((sIndex, bar.spec.y?.value.numericValue ?? 0, bar))
		}

		for c in xBands where !(byCategory[c]?.isEmpty ?? true) {
			let group = byCategory[c]!
			let bandX = banded.position(of: c)
			let bandW = banded.bandWidth
			switch stacking {
			case .unstacked:
				let n = max(1, perCatCount[c] ?? group.count)
				let sub = bandW / Double(n)
				for item in group {
					let x = bandX + Double(item.seriesIndex) * sub
					out += barRect(x: x, w: sub, value: item.value, mark: item.mark, yScale: yScale, zeroY: zeroY)
				}
			case .normal:
				var cum = 0.0
				for item in group {
					let start = cum
					cum += item.value
					let yTop = yScale.position(cum)
					let yBot = yScale.position(start)
					out += barRect(x: bandX, w: bandW, topY: yTop, botY: yBot, value: item.value, mark: item.mark)
				}
			case .centered:
				let total = group.reduce(0) { $0 + $1.value }
				var cum = -total / 2
				for item in group {
					let start = cum
					cum += item.value
					let yTop = yScale.position(cum)
					let yBot = yScale.position(start)
					out += barRect(x: bandX, w: bandW, topY: yTop, botY: yBot, value: item.value, mark: item.mark)
				}
			}
		}
		return out
	}

	private func barRect(x: Double, w: Double, value: Double, mark: ChartMark, yScale: ChartLinearScale, zeroY: Double) -> String {
		let yTop = yScale.position(value)
		let top = min(yTop, zeroY)
		let h = abs(zeroY - yTop)
		return barRect(x: x, w: w, topY: top, botY: top + h, value: value, mark: mark)
	}

	private func barRect(x: Double, w: Double, topY: Double, botY: Double, value: Double, mark: ChartMark) -> String {
		let rx = min(mark.spec.cornerRadius, w / 2)
		var out = ""
		let cls = "chart__mark \(colorClass(mark)) chart__bar"
		var attrs = " class=\"\(cls)\"" + explicitColorStyle(mark)
		if let mid = markIdPrefix {
			// stable id derived from category + series for interactivity.
			// put it on the <rect> — that is the painted element a click
			// targets, so the runtime reports it as targetId.
			let cat = categoryKey(mark.spec.x?.value) ?? "?"
			let series = mark.spec.series ?? "s"
			attrs += " id=\"\(htmlEscape("\(mid)-\(cat)-\(series)"))\""
			if let handler = config.onSelectMark {
				let me = ElementRef.stable(safeId ?? "chart")
				attrs += controlAttributes(
					id: "\(mid)-\(cat)-\(series)",
					handler: { event in await handler(me, cat) }
				)
			}
		}
		let title = markTitle(mark, value: value)
		out += "<g\(opacityAttr(mark))>\(title)<rect\(attrs) x=\"\(fmt(x))\" y=\"\(fmt(topY))\" width=\"\(fmt(max(0, w)))\" height=\"\(fmt(max(0, botY - topY)))\" rx=\"\(fmt(rx))\"/></g>"
		if let ann = mark.spec.annotation {
			out += annotation(ann, x: x + w / 2, y: topY, yScale: ChartLinearScale(domain: 0...1, rangeStart: 0, rangeEnd: 1), position: .top)
		}
		return out
	}

	// bars on a linear x-axis (e.g. a single numeric bar or date bars).
	private func renderBarMarksLinear(m: Metrics, yScale: ChartLinearScale, xLinear: ChartLinearScale) -> String {
		var out = ""
		for (i, bar) in marks.filter({ $0.spec.kind == .bar }).enumerated() {
			guard let xv = bar.spec.x?.value.numericValue else { continue }
			let x = xLinear.position(xv)
			let w = barWidth(bar, xLinear)
			let zeroY = yScale.position(0)
			out += barRect(x: x - w / 2, w: w, value: bar.spec.y?.value.numericValue ?? 0, mark: bar, yScale: yScale, zeroY: zeroY)
			_ = i
		}
		return out
	}

	private func barWidth(_ bar: ChartMark, _ xLinear: ChartLinearScale) -> Double {
		switch bar.spec.barDimension {
		case .fixed(let f): return f
		case .ratio(let r): return xLinear.span * r
		case .automatic: return min(24, xLinear.span * 0.1)
		}
	}

	// lines / areas / points, per series.
	private func renderLineAreaPoint(m: Metrics, yScale: ChartLinearScale, xLinear: ChartLinearScale, xBanded: ChartBandedScale?, xBands: [String]) -> String {
		var out = ""
		let relevant = marks.filter { $0.spec.kind == .line || $0.spec.kind == .area || $0.spec.kind == .point }
		guard !relevant.isEmpty else { return out }
		let series = seriesOrder
		for s in series {
			var pts: [(x: Double, y: Double, mark: ChartMark)] = []
			for mark in relevant where (mark.spec.series ?? series[0]) == s {
				let x: Double
				if let cat = mark.spec.x?.value, case .category(let c) = cat, let banded = xBanded {
					x = banded.center(of: c)
				} else if let num = mark.spec.x?.value.numericValue {
					x = xLinear.position(num)
				} else {
					x = Double(m.plotLeft)
				}
				let y = yScale.position(mark.spec.y?.value.numericValue ?? 0)
				pts.append((x, y, mark))
			}
			pts.sort { $0.x < $1.x }
			guard !pts.isEmpty else { continue }
			// area first (behind line)
			if relevant.contains(where: { $0.spec.kind == .area && ($0.spec.series ?? series[0]) == s }) {
				out += areaPath(pts: pts, yScale: yScale, series: s, interpolation: relevant.first(where: { $0.spec.kind == .area })?.spec.interpolation ?? .linear)
			}
			if relevant.contains(where: { $0.spec.kind == .line && ($0.spec.series ?? series[0]) == s }) {
				out += linePath(pts: pts, series: s, interpolation: relevant.first(where: { $0.spec.kind == .line })?.spec.interpolation ?? .linear, lineStyle: relevant.first(where: { $0.spec.kind == .line })?.spec.style.lineStyle)
			}
			for p in pts {
				if p.mark.spec.kind == .point || p.mark.spec.showsPoint {
					out += pointSVG(x: p.x, y: p.y, mark: p.mark)
				}
			}
		}
		return out
	}

	private func linePath(pts: [(x: Double, y: Double, mark: ChartMark)], series: String, interpolation: InterpolationMethod, lineStyle: ChartLineStyle?) -> String {
		let d = ChartGeometry.linePath(points: pts.map { (px: $0.x, py: $0.y) }, interpolation: interpolation)
		let width = lineStyle?.width ?? 2
		let dash = lineStyle?.dash ?? []
		let dashAttr = dash.isEmpty ? "" : " stroke-dasharray=\"\(dash.map { fmt($0) }.joined(separator: " "))\""
		let cls = "chart__mark chart__line \(colorClass(ChartMark(spec: MarkSpec(kind: .line, series: series))))"
		let opacity = pts.first.map { opacityAttr($0.mark) } ?? ""
		return "<path class=\"\(cls)\" d=\"\(d)\" stroke-width=\"\(fmt(width))\"\(dashAttr)\(opacity)/>"
	}

	private func areaPath(pts: [(x: Double, y: Double, mark: ChartMark)], yScale: ChartLinearScale, series: String, interpolation: InterpolationMethod) -> String {
		guard let first = pts.first, let last = pts.last else { return "" }
		let lineD = ChartGeometry.linePath(points: pts.map { (px: $0.x, py: $0.y) }, interpolation: interpolation)
		let zeroY = yScale.position(0)
		let d = "\(lineD) L\(fmt(last.x)),\(fmt(zeroY)) L\(fmt(first.x)),\(fmt(zeroY)) Z"
		let cls = "chart__mark chart__area \(colorClass(ChartMark(spec: MarkSpec(kind: .area, series: series))))"
		let opacity = pts.first.map { opacityAttr($0.mark) } ?? ""
		return "<path class=\"\(cls)\" d=\"\(d)\"\(opacity)/>"
	}

	private func pointSVG(x: Double, y: Double, mark: ChartMark) -> String {
		let cls = "chart__mark \(colorClass(mark)) chart__point"
		var attrs = " class=\"\(cls)\"" + explicitColorStyle(mark)
		let r = 3.5
		switch mark.spec.symbol {
		case .circle:
			if let mid = markIdPrefix { attrs += " id=\"\(htmlEscape("\(mid)-pt"))\"" }
			let title = markTitle(mark)
			return "<g\(attrs)\(opacityAttr(mark))>\(title)<circle cx=\"\(fmt(x))\" cy=\"\(fmt(y))\" r=\"\(r)\"/></g>"
		default:
			let path = ChartGeometry.symbolPath(shape: mark.spec.symbol, x: x, y: y, size: 4)
			return "<g\(attrs)\(opacityAttr(mark))>\(path)</g>"
		}
	}

	// rectangles (heatmap cells).
	private func renderRectMarks(m: Metrics, yScale: ChartLinearScale, xLinear: ChartLinearScale) -> String {
		var out = ""
		for mark in marks where mark.spec.kind == .rectangle {
			let x0 = mark.spec.xStart?.value.numericValue ?? mark.spec.x?.value.numericValue ?? 0
			let x1 = mark.spec.xEnd?.value.numericValue ?? (x0 + 1)
			let y0 = mark.spec.yStart?.value.numericValue ?? 0
			let y1 = mark.spec.yEnd?.value.numericValue ?? (y0 + 1)
			let left = xLinear.position(x0)
			let right = xLinear.position(x1)
			let top = yScale.position(max(y0, y1))
			let bottom = yScale.position(min(y0, y1))
			let cls = "chart__mark \(colorClass(mark)) chart__rect"
			var rectAttrs = ""
			if let intensity = mark.spec.intensity {
				let clamped = min(max(intensity, 0.05), 1)
				rectAttrs += " style=\"fill-opacity: \(fmt(clamped))\""
			}
			out += "<g class=\"\(cls)\"\(explicitColorStyle(mark))\(opacityAttr(mark))>\(markTitle(mark))<rect x=\"\(fmt(left))\" y=\"\(fmt(top))\" width=\"\(fmt(max(0, right - left)))\" height=\"\(fmt(max(0, bottom - top)))\"\(rectAttrs)/></g>"
		}
		return out
	}

	// rules.
	private func renderRuleMarks(m: Metrics, yScale: ChartLinearScale) -> String {
		var out = ""
		for mark in marks where mark.spec.kind == .rule {
			if let y = mark.spec.y?.value.numericValue {
				let y0 = Int(yScale.position(y).rounded())
				let cls = "chart__mark \(colorClass(mark)) chart__rule"
				out += "<line class=\"\(cls)\" x1=\"\(m.plotLeft)\" y1=\"\(y0)\" x2=\"\(m.plotRight)\" y2=\"\(y0)\"/>"
				if let ann = mark.spec.annotation {
					out += annotation(ann, x: Double(m.plotRight) - 4, y: Double(y0) - 6, yScale: yScale, position: .top)
				}
			} else if let x = mark.spec.x?.value.numericValue {
				let x0 = Int(xLinearPosition(m, x).rounded())
				let cls = "chart__mark \(colorClass(mark)) chart__rule chart__rule--v"
				out += "<line class=\"\(cls)\" x1=\"\(x0)\" y1=\"\(m.plotTop)\" x2=\"\(x0)\" y2=\"\(m.plotBottom)\"/>"
			}
		}
		return out
	}

	private func xLinearPosition(_ m: Metrics, _ x: Double) -> Double {
		let lin = ChartLinearScale(domain: xDomain ?? 0...1, rangeStart: Double(m.plotLeft), rangeEnd: Double(m.plotRight))
		return lin.position(x)
	}

	/// A stable string key for a category value (for derived mark ids).
	private func categoryKey(_ v: Plottable?) -> String? {
		guard let v else { return nil }
		switch v {
		case .category(let c): return c
		case .number(let n): return fmt(n)
		case .date(let d): return String(Int(d.timeIntervalSinceReferenceDate))
		}
	}

	// MARK: Selection

	private func renderSelection(m: Metrics, sel: SelectionConfig, xLinear: ChartLinearScale, xBanded: ChartBandedScale?, xIsCategorical: Bool, yScale: ChartLinearScale) -> String {
		guard let value = sel.value else { return "" }
		var out = ""
		if sel.axis == .x {
			let x: Double
			if xIsCategorical, let banded = xBanded, case .category(let c) = value {
				x = banded.center(of: c)
			} else if case .number(let n) = value {
				x = xLinear.position(n)
			} else { return "" }
			out += "<line class=\"chart__selection\" x1=\"\(Int(x.rounded()))\" y1=\"\(m.plotTop)\" x2=\"\(Int(x.rounded()))\" y2=\"\(m.plotBottom)\"/>"
		} else if case .number(let n) = value {
			let y = Int(yScale.position(n).rounded())
			out += "<line class=\"chart__selection\" x1=\"\(m.plotLeft)\" y1=\"\(y)\" x2=\"\(m.plotRight)\" y2=\"\(y)\"/>"
		}
		return out
	}

	// MARK: Annotation / title

	private func annotation(_ ann: ChartAnnotation, x: Double, y: Double, yScale: ChartLinearScale, position: AnnotationPosition) -> String {
		let dy: Double
		switch position {
		case .top, .automatic, .leading: dy = -6
		case .bottom, .trailing, .overlay: dy = 12
		}
		return "<text class=\"chart__annotation\" x=\"\(fmt(x))\" y=\"\(fmt(y + dy))\" text-anchor=\"middle\">\(htmlEscape(ann.text))</text>"
	}

	private func markTitle(_ mark: ChartMark, value: Double? = nil) -> String {
		let label = mark.spec.displayValue ?? mark.spec.series ?? mark.spec.x?.label ?? "Mark"
		let valueStr = value.map { " \(ChartValueFormat.format($0, .automatic))" } ?? (mark.spec.displayValue.map { " \($0)" } ?? "")
		return "<title>\(htmlEscape(label + valueStr))</title>"
	}

	// MARK: Legend

	private func legend(sectors: [ChartMark], position: LegendPosition) -> String {
		var out = "<figcaption class=\"chart__legend chart__legend--\(legendSide(position))\">"
		for (i, sector) in sectors.enumerated() {
			let name = sector.spec.series ?? sector.spec.angle?.label ?? "Sector \(i + 1)"
			out += "<span class=\"chart__legend-item\"><span class=\"chart__swatch chart__c\((seriesColorIndex[name] ?? 0) + 1)\"></span>\(htmlEscape(name))</span>"
		}
		out += "</figcaption>"
		return out
	}

	private func legendForCartesian(position: LegendPosition) -> String {
		let series = seriesOrder.filter { $0 != "(default)" }
		guard series.count > 0 else { return "" }
		var out = "<figcaption class=\"chart__legend chart__legend--\(legendSide(position))\">"
		for s in series {
			out += "<span class=\"chart__legend-item\"><span class=\"chart__swatch chart__c\((seriesColorIndex[s] ?? 0) + 1)\"></span>\(htmlEscape(s))</span>"
		}
		out += "</figcaption>"
		return out
	}

	private func legendSide(_ p: LegendPosition) -> String {
		switch p {
		case .top: return "top"
		case .bottom, .automatic: return "bottom"
		case .leading: return "left"
		case .trailing: return "right"
		case .hidden: return "none"
		}
	}

	// MARK: Accessibility table

	private func accessibilityTable(sectors: [ChartMark], total: Double) -> String {
		var out = "<table class=\"chart__sr\" role=\"presentation\"><caption>Sector values</caption><tbody>"
		for sector in sectors {
			let name = sector.spec.series ?? sector.spec.angle?.label ?? "Sector"
			let v = sector.spec.angle?.value.numericValue ?? 0
			out += "<tr><th scope=\"row\">\(htmlEscape(name))</th><td>\(Int((v / total * 100).rounded()))%</td></tr>"
		}
		out += "</tbody></table>"
		return out
	}

	private func accessibilityTableCartesian() -> String {
		// include the default (unstyled) series so the table never goes empty
		var out = "<table class=\"chart__sr\" role=\"presentation\"><caption>Series values</caption><tbody>"
		for s in seriesOrder {
			let name = s == "(default)" ? "Series" : s
			var values = [String]()
			for mark in marks where (mark.spec.series ?? "(default)") == s {
				if let v = mark.spec.y?.value.numericValue {
					values.append(ChartValueFormat.format(v, .automatic))
				}
			}
			guard !values.isEmpty else { continue }
			out += "<tr><th scope=\"row\">\(htmlEscape(name))</th><td>\(values.joined(separator: ", "))</td></tr>"
		}
		out += "</tbody></table>"
		return out
	}

	// MARK: Formatting

	/// Format a viewBox coordinate: up to 2 decimals, trailing zeros
	/// stripped. Never corrupts internal zeros (1.05 stays 1.05).
	private func fmt(_ v: Double) -> String {
		ChartGeometry.fmt(v)
	}
}
