import Foundation
import Testing
import WebUI
@testable import WebUIChart

// MARK: - helpers (named distinct from SmokeTests' `count(_:_:)`)

/// occurrences of a substring
func occ(_ haystack: String, _ needle: String) -> Int {
	haystack.components(separatedBy: needle).count - 1
}

/// first capture group of `regex` in `haystack`, or nil
func capture(_ regex: String, in haystack: String) -> String? {
	guard let r = try? NSRegularExpression(pattern: regex) else { return nil }
	guard let m = r.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)),
	      m.numberOfRanges > 1 else { return nil }
	return Range(m.range(at: 1), in: haystack).map { String(haystack[$0]) }
}

// MARK: - Scales

@Suite struct ChartScaleTests {
	@Test func linearScaleMapsDomainToRange() {
		let s = ChartLinearScale(domain: 0...100, rangeStart: 0, rangeEnd: 400)
		#expect(abs(s.position(0) - 0) < 0.001)
		#expect(abs(s.position(50) - 200) < 0.001)
		#expect(abs(s.position(100) - 400) < 0.001)
	}

	@Test func linearScaleClampsOutOfRange() {
		let s = ChartLinearScale(domain: 0...10, rangeStart: 0, rangeEnd: 100)
		#expect(abs(s.position(-5) - 0) < 0.001)
		#expect(abs(s.position(99) - 100) < 0.001)
	}

	@Test func linearScaleInverseRoundTrips() {
		let s = ChartLinearScale(domain: 0...10, rangeStart: 0, rangeEnd: 100)
		#expect(abs(s.value(at: s.position(7.25)) - 7.25) < 0.001)
	}

	@Test func linearScaleHandlesDegenerateDomain() {
		let s = ChartLinearScale(domain: 5...5, rangeStart: 0, rangeEnd: 100)
		#expect(abs(s.position(5) - 50) < 0.001)
	}

	@Test func bandedScaleFillsPlotExactly() {
		// d3 scaleBand: step = width / (n − inner + 2·outer)
		let b = ChartBandedScale(categories: ["Jan", "Feb", "Mar"],
		                         rangeStart: 0, rangeEnd: 600,
		                         paddingInner: 0.25, paddingOuter: 0.05)
		let step = 600.0 / (3 - 0.25 + 2 * 0.05)   // 210.526…
		let band = step * (1 - 0.25)               // 157.894…
		#expect(abs(b.position(of: "Jan") - step * 0.05) < 0.001)
		#expect(abs(b.position(of: "Mar") + band - (600 - step * 0.05)) < 0.001)  // ends at width − outer
		#expect(abs(b.bandWidth - band) < 0.001)
		#expect(abs(b.center(of: "Feb") - 300) < 0.001)  // middle band centered
	}

	@Test func ticksAreNiceAndBounded() {
		let t = ChartTicks.ticks(min: 0, max: 12, count: 5)
		#expect(t.count >= 3)
		#expect(t.first! >= 0)
		#expect(t.last! > 12)  // nice overshoot (filtered by the renderer)
		for v in t { #expect(v.truncatingRemainder(dividingBy: 1) == 0) }
	}

	@Test func fmtIsStableAndSafe() {
		#expect(ChartGeometry.fmt(44) == "44")
		#expect(ChartGeometry.fmt(1.05) == "1.05")
		#expect(ChartGeometry.fmt(-0.001) == "0")
		#expect(ChartGeometry.fmt(3.14159) == "3.14")
	}

	@Test func valueFormats() {
		#expect(ChartValueFormat.format(12.0, .integer) == "12")
		#expect(ChartValueFormat.format(12.3456, .decimal(2)) == "12.35")
		#expect(ChartValueFormat.format(0.42, .percent) == "42%")
		#expect(ChartValueFormat.format(2_500_000, .numberCompact) == "2.5M")
		#expect(ChartValueFormat.format(1_234, .numberCompact) == "1.2k")
		#expect(ChartValueFormat.format(123_456_789, .numberCompact) == "123.5M")
		#expect(ChartValueFormat.format(7, .hidden) == "")
		#expect(ChartValueFormat.format(300, .currency("USD")) == "USD 300")
	}
}

// MARK: - Geometry

@Suite struct ChartGeometryTests {
	@Test func linearPathIsStraight() {
		let d = ChartGeometry.linePath(points: [(px: 0, py: 10), (px: 50, py: 20), (px: 100, py: 0)], interpolation: .linear)
		#expect(d.hasPrefix("M0,10"))
		#expect(d.hasSuffix(" L100,0"))
	}

	@Test func stepStartJumpsVerticallyFirst() {
		let d = ChartGeometry.linePath(points: [(px: 0, py: 10), (px: 50, py: 20)], interpolation: .stepStart)
		#expect(d == "M0,10 L0,20 L50,20")
	}

	@Test func stepEndJumpsVerticallyLast() {
		let d = ChartGeometry.linePath(points: [(px: 0, py: 10), (px: 50, py: 20)], interpolation: .stepEnd)
		#expect(d == "M0,10 L50,10 L50,20")
	}

	@Test func smoothInterpolationsUseCubicsAndPassThroughPoints() {
		let pts = [(px: 0.0, py: 10.0), (px: 40, py: 30), (px: 80, py: 5), (px: 120, py: 40)]
		for m in [InterpolationMethod.catmullRom, .monotone, .cardinal(0.5)] {
			let d = ChartGeometry.linePath(points: pts, interpolation: m)
			#expect(d.hasPrefix("M0,10"))
			#expect(d.hasSuffix("120,40"))
			#expect(d.contains(" C"))
		}
	}

	@Test func monotoneCurveDoesNotOvershoot() {
		// steep then flat: a monotone cubic must not leave the y band
		let pts = [(px: 0.0, py: 0.0), (px: 1, py: 100), (px: 2, py: 101), (px: 3, py: 101)]
		let d = ChartGeometry.linePath(points: pts, interpolation: .monotone)
		for seg in d.split(separator: " ") where seg.hasPrefix("C") {
			let nums = seg.dropFirst().split(separator: ",").flatMap { s2 in s2.split(separator: " ").map { Double($0) ?? 0 } }
			for y in nums where y.isNaN == false {
				#expect(y >= -0.001 && y <= 101.001)
			}
		}
	}

	@Test func pieSectorCoversRightSweep() {
		// 40% = 144° from 12 o'clock clockwise ends at 144° (past 3 o'clock)
		let d = ChartGeometry.sectorPath(centerX: 0, centerY: 0, innerRadius: 0, outerRadius: 100, startAngle: 0, endAngle: 144)
		#expect(d.hasPrefix("M0,0 L0,-100"))
		#expect(d.contains("A100,100 0 0 1"))
		#expect(d.hasSuffix("Z"))
	}

	@Test func donutSectorUsesAnnularArcs() {
		let d = ChartGeometry.sectorPath(centerX: 0, centerY: 0, innerRadius: 60, outerRadius: 100, startAngle: 0, endAngle: 90)
		#expect(d.contains("A100,100 0 0 1"))
		#expect(d.contains("A60,60 0 0 0"))
		#expect(d.hasSuffix("Z"))
	}

	@Test func largeArcFlagForSweepOver180() {
		let d = ChartGeometry.sectorPath(centerX: 0, centerY: 0, innerRadius: 0, outerRadius: 100, startAngle: 0, endAngle: 270)
		#expect(d.contains("A100,100 0 1 1"))
	}
}

// MARK: - Bar charts

@Suite struct ChartBarTests {
	@Test func emptyChartRendersEmptyState() {
		let html = Chart([]).render()
		#expect(html.contains("chart--empty"))
		#expect(html.contains("No data"))
		#expect(!html.contains("<svg"))
	}

	@Test func categoricalBarsUseBandPlacement() {
		let chart = Chart {
			ForEach([("Jan", 5.0), ("Feb", 9.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
			}
		}
		let out = chart.render()
		#expect(out.contains("chart__bar"))
		#expect(occ(out, "<rect") == 2)
		// two bars, both inside the plot (viewBox 0 0 640 320, plot x 44…624)
		for g in out.components(separatedBy: "<g") where g.contains("chart__bar") {
			let x = Double(capture("x=\"([0-9.]+)\"", in: g)!)!
			let w = Double(capture("width=\"([0-9.]+)\"", in: g)!)!
			#expect(x >= 44 && x + w <= 624 + 0.01)
		}
		// taller bar is taller
		let heights = out.components(separatedBy: "<g")
			.filter { $0.contains("chart__bar") }
			.compactMap { capture("height=\"([0-9.]+)\"", in: $0).map(Double.init) }
		#expect(heights.count == 2)
		#expect(heights[1]! > heights[0]!)  // Feb (9) > Jan (5)
	}

	@Test func seriesGetPaletteSlotsAndLegend() {
		let c2 = Chart {
			ForEach([("A", 10.0), ("A", 20.0), ("B", 5.0), ("B", 15.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle(by: d.0).stacking(.unstacked)
			}
		}
		let out = c2.render()
		#expect(out.contains("chart__c1"))
		#expect(out.contains("chart__c2"))
		#expect(out.contains("chart__legend"))
		#expect(out.contains("chart__swatch"))
	}

	@Test func hiddenLegendOmitsLegend() {
		let chart = Chart {
			ForEach([("A", 1.0), ("B", 2.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle(by: d.0)
			}
		}
		.chartLegend(position: .hidden)
		#expect(!chart.render().contains("chart__legend"))
	}

	@Test func stackedBarsSumPerCategory() {
		let chart = Chart {
			ForEach([("Jan", "A", 12.0), ("Jan", "B", 8.0), ("Feb", "A", 20.0), ("Feb", "B", 15.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.2)).foregroundStyle(by: d.1)
			}
		}
		.chartYScale(.linear(domain: 0...40))
		let out = chart.render()
		#expect(occ(out, "chart__bar") >= 4)
		#expect(occ(out, "<title>") >= 4)
		// the Feb "B" segment (20…35) sits directly on the Feb "A" segment (0…20):
		// A.top == B.bottom, no overlap, no gap.
		let groups = out.components(separatedBy: "<g").filter { $0.contains("chart__bar") }
			.map { s in
				let y = Double(capture("y=\"([0-9.]+)\"", in: s)!)!
				let h = Double(capture("height=\"([0-9.]+)\"", in: s)!)!
				let title = capture("<title>([^<]*)</title>", in: s) ?? ""
				return (y: y, h: h, title: title)
			}
		let febA = groups.first { $0.title.hasPrefix("A") && $0.title.hasSuffix("20") }!
		let febB = groups.first { $0.title.hasPrefix("B") && $0.title.hasSuffix("15") }!
		#expect(abs(febA.y - (febB.y + febB.h)) < 0.01)
	}

	@Test func negativeBarsExtendBelowBaseline() {
		let chart = Chart {
			ForEach([("Q1", -5.0), ("Q2", 8.0), ("Q3", 3.0)]) { d in
				BarMark(x: .value("Q", d.0), y: .value("V", d.1))
			}
		}
		let out = chart.render()
		#expect(occ(out, "<rect") == 3)
	}

	@Test func barsPinYDomainFromZero() {
		let chart = Chart {
			ForEach([("A", 9.0), ("B", 1.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
			}
		}
		.chartYScale(.linear(domain: 0...10))
		let out = chart.render()
		// domain 0…10 maps to y 280 (bottom) … 20 (top):
		// value 9 → 280 − 0.9·260 = 46, value 1 → 280 − 0.1·260 = 254
		let barRects = out.components(separatedBy: "<g").filter { $0.contains("chart__bar") }
		let ys = barRects.compactMap { capture("y=\"([0-9.]+)\"", in: $0).map(Double.init) }
		#expect(ys.count == 2)
		#expect(abs(ys[0]! - 46) < 1)
		#expect(abs(ys[1]! - 254) < 1)
		#expect(ys[0]! < ys[1]!)  // bigger value → higher (smaller y)
	}
}

// MARK: - Line / area / point

@Suite struct ChartLineTests {
	@Test func forEachWithNestedGroupsResolvesAllMarks() {
		// regression: ForEach.resolvedMarks used to drop Groups, so a
		// ForEach { Group { Area; Line; Point } } rendered an empty chart
		let data = [(1.0, 5.0), (2.0, 9.0)]
		let chart = Chart {
			ForEach(data) { p in
				Group {
					AreaMark(x: .value("X", p.0), y: .value("Y", p.1)).foregroundStyle(by: "s")
					LineMark(x: .value("X", p.0), y: .value("Y", p.1)).foregroundStyle(by: "s")
					PointMark(x: .value("X", p.0), y: .value("Y", p.1)).foregroundStyle(by: "s")
				}
			}
		}
		let out = chart.render()
		#expect(out.contains("chart__area"))
		#expect(out.contains("chart__line"))
		#expect(occ(out, "chart__point") >= 2)
	}

	@Test func lineChartRendersPathAndPoints() {
		let ys: [Double] = [3, 8, 5, 11]
		var marks: [ChartMark] = []
		for (i, y) in ys.enumerated() {
			let x = Double(i + 1)
			marks.append(LineMark(x: .value("X", x), y: .value("Y", y)).foregroundStyle(by: "s").makeMark())
			marks.append(PointMark(x: .value("X", x), y: .value("Y", y)).foregroundStyle(by: "s").makeMark())
		}
		let chart = Chart(marks)
			.chartXScale(.linear(domain: 0...5))
			.chartYScale(.linear(domain: 0...12))
		let out = chart.render()
		#expect(out.contains("chart__line"))
		#expect(out.contains("<path"))
		#expect(occ(out, "chart__point") >= 4)
	}

	@Test func singlePointLineIsSafe() {
		let out = Chart {
			LineMark(x: .value("X", 1), y: .value("Y", 5))
		}
		.chartXScale(.linear(domain: 0...4))
		.chartYScale(.linear(domain: 0...12))
		.render()
		#expect(out.contains("chart__line"))
	}

	@Test func areaFillsToBaseline() {
		let chart = Chart {
			ForEach([1.0, 2.0, 3.0]) { x in
				AreaMark(x: .value("X", x), y: .value("Y", x * 2))
			}
		}
		.chartXScale(.linear(domain: 0...4))
		.chartYScale(.linear(domain: 0...8))
		let out = chart.render()
		#expect(out.contains("chart__area"))
		#expect(out.contains("Z\""))  // closed path
	}

	@Test func lineInterpolationAppearsInPath() {
		let c = Chart {
			ForEach([(1.0, 2.0), (2.0, 9.0), (3.0, 4.0)]) { d in
				LineMark(x: .value("X", d.0), y: .value("Y", d.1)).interpolation(.catmullRom)
			}
		}
		#expect(c.render().contains(" C"))
		let s = Chart {
			ForEach([(1.0, 2.0), (2.0, 9.0), (3.0, 4.0)]) { d in
				LineMark(x: .value("X", d.0), y: .value("Y", d.1)).interpolation(.stepEnd)
			}
		}
		let d = capture("d=\"([^\"]+)\"", in: s.render())!
		// stepEnd (data units → viewBox): horizontal to the next x, then a
		// vertical jump AT that x: x domain 1…3 → x=2 sits at viewBox 334
		#expect(d.range(of: "L334,280 L334,") != nil)
	}

	@Test func lineStyleDashesAndWidth() {
		let c = Chart {
			ForEach([(1.0, 2.0), (2.0, 9.0)]) { d in
				LineMark(x: .value("X", d.0), y: .value("Y", d.1)).lineStyle(ChartLineStyle(width: 3, dash: [4, 2]))
			}
		}
		let out = c.render()
		#expect(out.contains("stroke-width=\"3\""))
		#expect(out.contains("stroke-dasharray=\"4 2\""))
	}

	@Test func pointSymbolsRenderDistinctShapes() {
		let c = Chart {
			Group {
				PointMark(x: .value("X", 1), y: .value("Y", 5), symbol: .square)
				PointMark(x: .value("X", 2), y: .value("Y", 6), symbol: .diamond)
				PointMark(x: .value("X", 3), y: .value("Y", 7), symbol: .triangle)
				PointMark(x: .value("X", 4), y: .value("Y", 8), symbol: .cross)
				PointMark(x: .value("X", 5), y: .value("Y", 9), symbol: .circle)
			}
		}
		.chartXScale(.linear(domain: 0...6))
		let out = c.render()
		#expect(out.contains("<rect"))
		#expect(occ(out, "<polygon") >= 2)
		#expect(out.contains("<circle"))
	}
}

// MARK: - Pie / donut

@Suite struct ChartPieTests {
	private var pieMarks: [ChartMark] {
		[
			ChartMark(spec: MarkSpec(kind: .sector, angle: .value("V", 40), series: "X")),
			ChartMark(spec: MarkSpec(kind: .sector, angle: .value("V", 35), series: "Y")),
			ChartMark(spec: MarkSpec(kind: .sector, angle: .value("V", 25), series: "Z")),
		]
	}

	@Test func pieRendersThreeSectorsFromTwelveOClock() {
		let out = Chart(pieMarks).render()
		#expect(out.contains("chart--pie"))
		#expect(occ(out, "chart__sector") >= 3)
		// the first sector's outer arc starts at 12 o'clock (top of the circle):
		// center (320,160), outer radius 148 → top point (320,12)
		#expect(out.contains("L320,12"))
		#expect(out.contains("X: 40%"))
		#expect(out.contains("Y: 35%"))
		#expect(out.contains("Z: 25%"))
	}

	@Test func donutRendersAnnulusAndCenterTotal() {
		let donut = pieMarks.map { m -> ChartMark in
			var s = m.spec
			s.innerRadiusRatio = 0.62
			return ChartMark(spec: s)
		}
		let out = Chart(donut).render()
		#expect(out.contains("chart__donut-center"))
		#expect(out.contains("100"))
		#expect(out.contains("Total"))
		#expect(out.contains("A91.76,91.76 0 0 0") || out.contains("A91.76,91.76"))  // inner arc radius 148*0.62
	}

	@Test func sectorSelectionHighlightsTheMark() {
		let out = Chart(pieMarks).chartSelection(axis: .x, value: .category("Y")).render()
		#expect(out.contains("chart__mark--selected"))
		#expect(occ(out, "chart__mark--selected") == 1)
	}

	@Test func zeroTotalPieIsSafe() {
		let out = Chart([ChartMark(spec: MarkSpec(kind: .sector, angle: .value("V", 0), series: "X"))]).render()
		#expect(out.contains("chart--pie"))
		#expect(!out.contains("chart__sector"))
	}

	@Test func singleSectorPieIsFullCircle() {
		let out = Chart([ChartMark(spec: MarkSpec(kind: .sector, angle: .value("V", 10), series: "Only"))]).render()
		#expect(out.contains("chart__sector"))
	}
}

// MARK: - Rules / rectangles

@Suite struct ChartRuleRectTests {
	@Test func horizontalRuleAtExactPosition() {
		let c = Chart {
			Group {
				LineMark(x: .value("X", 1), y: .value("Y", 5))
				LineMark(x: .value("X", 4), y: .value("Y", 9))
				RuleMark(y: .value("Avg", 7))
			}
		}
		.chartXScale(.linear(domain: 0...6))
		.chartYScale(.linear(domain: 0...10))
		let out = c.render()
		#expect(out.contains("chart__rule"))
		#expect(occ(out, "chart__rule--v") == 0)
	}

	@Test func verticalRuleAtExactPosition() {
		let c = Chart {
			Group {
				LineMark(x: .value("X", 1), y: .value("Y", 5))
				RuleMark(x: .value("Mid", 3))
			}
		}
		.chartXScale(.linear(domain: 0...6))
		.chartYScale(.linear(domain: 0...10))
		let out = c.render()
		#expect(out.contains("chart__rule--v"))
	}

	@Test func heatmapCellsTileThePlot() {
		var marks: [ChartMark] = []
		for r in 0..<3 {
			for col in 0..<4 {
				marks.append(RectangleMark(
					xStart: .value("C", Double(col)),
					xEnd: .value("C", Double(col + 1)),
					yStart: .value("R", Double(r)),
					yEnd: .value("R", Double(r + 1))).makeMark())
			}
		}
		let c = Chart(marks)
			.chartXScale(.linear(domain: 0...4))
			.chartYScale(.linear(domain: 0...3))
		let out = c.render()
		#expect(occ(out, "chart__rect") >= 12)
		// every cell rect sits inside the plot
		for g in out.components(separatedBy: "<g") where g.contains("chart__rect") {
			let x = Double(capture("x=\"([0-9.]+)\"", in: g)!)!
			let y = Double(capture("y=\"([0-9.]+)\"", in: g)!)!
			let w = Double(capture("width=\"([0-9.]+)\"", in: g)!)!
			let h = Double(capture("height=\"([0-9.]+)\"", in: g)!)!
			#expect(x >= 44 && x + w <= 624.01)
			#expect(y >= 20 && y + h <= 280.01)
		}
	}

	@Test func heatmapIntensityDrivesFillOpacity() {
		let marks = [
			RectangleMark(xStart: .value("C", 0.0), xEnd: .value("C", 1.0),
			             yStart: .value("R", 0.0), yEnd: .value("R", 1.0),
			             value: 0.25).makeMark(),
			RectangleMark(xStart: .value("C", 1.0), xEnd: .value("C", 2.0),
			             yStart: .value("R", 0.0), yEnd: .value("R", 1.0),
			             value: 1.0).makeMark(),
			RectangleMark(xStart: .value("C", 2.0), xEnd: .value("C", 3.0),
			             yStart: .value("R", 0.0), yEnd: .value("R", 1.0)).makeMark(),
		]
		let out = Chart(marks).render()
		#expect(out.contains("fill-opacity: 0.25"))
		#expect(out.contains("fill-opacity: 1"))
		// the valueless cell stays solid (no inline fill-opacity)
		let cells = out.components(separatedBy: "<g class=\"chart__mark").dropFirst().filter { $0.contains("chart__rect") }
		#expect(cells.count == 3)
		#expect(cells.filter { $0.contains("fill-opacity") }.count == 2)
	}
}

// MARK: - Axes / labels / annotation

@Suite struct ChartAxisTests {
	@Test func axisLabelsFollowFormat() {
		let c = Chart {
			ForEach([("A", 0.5), ("B", 0.75)]) { d in
				BarMark(x: .value("M", d.0), y: .value("Share", d.1))
			}
		}
		.chartYScale(.linear(domain: 0...1))
		.chartYAxis(AxisConfig(labelFormat: .percent))
		let out = c.render()
		#expect(out.contains("0%"))
		#expect(out.contains("20%"))
		#expect(out.contains("100%"))
	}

	@Test func explicitTickValues() {
		let c = Chart {
			ForEach([(1.0, 2.0), (2.0, 8.0)]) { d in
				LineMark(x: .value("X", d.0), y: .value("Y", d.1))
			}
		}
		.chartXScale(.linear(domain: 0...4))
		.chartXAxis(AxisConfig(explicitValues: [0, 1, 2, 3, 4]))
		let out = c.render()
		#expect(out.contains(">0<"))
		#expect(out.contains(">4<"))
	}

	@Test func ticksOutsideDomainAreDropped() {
		let c = Chart {
			ForEach([(1.0, 2.0), (2.0, 8.0), (3.0, 4.0)]) { d in
				LineMark(x: .value("X", d.0), y: .value("Y", d.1))
			}
		}
		.chartXScale(.linear(domain: 0.5...3.5))
		let out = c.render()
		// collect the x-axis tick label texts
		var labels = [String]()
		var search: Substring = out[...]
		while let r = search.range(of: "axis-label--x\" x=\"") {
			let tail = search[search.index(after: r.upperBound)...]
			if let gt = tail.range(of: ">"), let end = tail[gt.upperBound...].range(of: "<") {
				labels.append(String(tail[gt.upperBound..<end.lowerBound]))
			}
			search = tail
		}
		#expect(labels.contains("1"))
		#expect(labels.contains("2"))
		#expect(labels.contains("3"))
		#expect(!labels.contains("0"))  // 0 < 0.5 → dropped, not clamped to the edge
		#expect(!labels.contains("4"))  // 4 > 3.5 → dropped
	}

	@Test func axisTitlesRender() {
		let c = Chart {
			ForEach([("A", 1.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
			}
		}
		.chartXAxis(AxisConfig(showsAxisLabel: true, axisLabel: "Month"))
		.chartYAxis(AxisConfig(showsAxisLabel: true, axisLabel: "Units"))
		let out = c.render()
		#expect(out.contains("chart__axis-title"))
		#expect(out.contains("Month"))
		#expect(out.contains("Units"))
	}

	@Test func annotationRendersWithEscapedText() {
		let c = Chart {
			ForEach([("A", 1.0), ("B", 2.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
					.annotation(d.0 == "A" ? "<i>1</i>" : "2")
			}
		}
		let out = c.render()
		#expect(out.contains("chart__annotation"))
		#expect(out.contains("&lt;i&gt;1&lt;/i&gt;"))
		#expect(!out.contains("<i>1</i>"))
	}

	@Test func hiddenFormatOmitsLabels() {
		let c = Chart {
			ForEach([(1.0, 2.0), (2.0, 8.0)]) { d in
				LineMark(x: .value("X", d.0), y: .value("Y", d.1))
			}
		}
		.chartXScale(.linear(domain: 0...4))
		.chartXAxis(AxisConfig(labelFormat: .hidden))
		let out = c.render()
		#expect(!out.contains("chart__axis-label--x"))  // x labels suppressed
		#expect(out.contains("chart__axis-label\""))     // y labels still render
	}
}

// MARK: - Interactivity / accessibility / security

@Suite struct ChartInteractionTests {
	@Test func interactiveChartExposesStableTargetIds() {
		let c = Chart {
			ForEach([("Jan", 5.0), ("Feb", 9.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle(by: "s")
			}
		}
		.chartID("sales")
		let out = c.render()
		#expect(out.contains("id=\"sales\""))
		#expect(out.contains("id=\"sales-mark-Jan-s\""))
		#expect(out.contains("id=\"sales-mark-Feb-s\""))
	}

	@Test func nonInteractiveChartHasNoTargetIds() {
		let out = Chart {
			ForEach([("Jan", 5.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
			}
		}
		.render()
		#expect(!out.contains("-mark-"))
	}

	@Test func selectionIndicatorRendersOnAxis() {
		let c = Chart {
			ForEach([("Jan", 5.0), ("Feb", 9.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
			}
		}
		.chartSelection(axis: .x, value: .category("Feb"))
		#expect(c.render().contains("chart__selection"))
	}

	@Test func ariaLabelAndTitle() {
		let c = Chart {
			ForEach([("A", 1.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1))
			}
		}
		.chartTitle("Title")
		.chartAccessibilityLabel("Custom accessible name")
		let out = c.render()
		#expect(out.contains("aria-label=\"Custom accessible name\""))
		#expect(out.contains("chart__title"))
		#expect(out.contains("Title"))
	}

	@Test func accessibilityTableCarriesData() {
		let c2 = Chart {
			ForEach([("A", 12.0), ("B", 7.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle(by: "s")
			}
		}
		let out = c2.render()
		#expect(out.contains("chart__sr"))
		#expect(out.contains("12"))
		#expect(out.contains("7"))
	}

	@Test func xssPayloadIsEscapedEverywhere() {
		let payload = "<img src=x onerror=alert(1)>"
		let c = Chart {
			ForEach([(payload, 5.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle(by: payload)
			}
		}
		.chartTitle(payload)
		.chartAccessibilityLabel(payload)
		.chartID("x-" + payload)
		let out = c.render()
		#expect(!out.contains("<img"))                    // no raw tag
		#expect(out.contains("&lt;img"))                   // payload is escaped
		#expect(!out.contains("alert(1)\">"))              // the `>` is neutralized: the
		// escaped value cannot terminate the attribute early
	}

	@Test func emptyStateEscapesAccessibilityLabel() {
		// probe-verified: the empty-state figure previously interpolated a
		// caller aria-label raw into `aria-label="..."`, emitting
		// `<figure ... aria-label="x" onload="alert(1)">`.
		let payload = "x\" onload=\"alert(1)"
		let out = Chart([]).chartAccessibilityLabel(payload).render()
		#expect(!out.contains("onload=\"alert(1)\""))
		#expect(out.contains("aria-label=\"x&quot; onload=&quot;alert(1)\""))
	}

	@Test func explicitColorEmitsInlineVar() {
		let c = Chart {
			ForEach([("A", 1.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle("var(--color-danger)")
			}
		}
		#expect(c.render().contains("--chart-mark-color:var(--color-danger)"))
	}

	@Test func opacityEmitsPresentationAttribute() {
		let c = Chart {
			ForEach([("A", 1.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).opacity(0.5)
			}
		}
		#expect(c.render().contains("opacity=\"0.5\""))
	}

	@Test func renderingIsDeterministic() {
		let c = Chart {
			ForEach([("A", 1.0), ("B", 2.0)]) { d in
				BarMark(x: .value("M", d.0), y: .value("V", d.1)).foregroundStyle(by: "s")
			}
		}
		#expect(c.render() == c.render())
	}
}
