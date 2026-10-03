import Foundation
import Testing
import WebUI
@testable import WebUIChart

// p5  radar, radial, css-only tips, area gradients, negative values.

/// every capture of `group` across all matches of `regex`
func allCaptures(_ regex: String, in haystack: String, group: Int = 1) -> [String] {
	guard let r = try? NSRegularExpression(pattern: regex) else { return [] }
	return r.matches(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)).compactMap { m in
		guard group < m.numberOfRanges else { return nil }
		return Range(m.range(at: group), in: haystack).map { String(haystack[$0]) }
	}
}

@Suite struct ChartP5Tests {

	// MARK: t5  negative values

	@Test func negativeValuesRenderSymmetricBarsAroundZero() {
		let marks = [
			BarMark(x: .value("month", "up"), y: .value("change", 30)).makeMark(),
			BarMark(x: .value("month", "down"), y: .value("change", -30)).makeMark(),
		]
		let html = Chart(marks, id: "neg").render()
		let heights = allCaptures(#"chart__bar"[^>]*height="([0-9.]+)""#, in: html).compactMap(Double.init)
		#expect(heights.count == 2, "expected one bar per datum, got \(heights)")
		if heights.count == 2 {
			#expect(abs(heights[0] - heights[1]) < 0.75,
				"bars of +30 and -30 must be the same height around zero: \(heights)")
		}
		let negativeTicks = allCaptures(#">(-[0-9]+(?:\.[0-9]+)?)<"#, in: html)
		#expect(!negativeTicks.isEmpty, "a negative datum must put a negative tick on the y axis")
	}

	@Test func negativeValuesStayBelowAProportionalPositiveBar() {
		let marks = [
			BarMark(x: .value("m", "a"), y: .value("v", 10)).makeMark(),
			BarMark(x: .value("m", "b"), y: .value("v", -40)).makeMark(),
		]
		let html = Chart(marks, id: "neg2").render()
		let heights = allCaptures(#"chart__bar"[^>]*height="([0-9.]+)""#, in: html).compactMap(Double.init)
		#expect(heights.count == 2)
		if heights.count == 2 {
			#expect(heights[1] > heights[0], "the larger magnitude must be the taller bar: \(heights)")
		}
	}

	// MARK: t1  radar

	@Test func radarRendersRingsSpokesAndOnePolygonPerSeries() {
		let marks = [
			RadarMark([("speed", 8), ("reliability", 6), ("cost", 4), ("support", 7)], series: "eu").makeMark(),
			RadarMark([("speed", 5), ("reliability", 9), ("cost", 7), ("support", 3)], series: "us").makeMark(),
		]
		let html = Chart(marks, id: "radar").render()
		#expect(html.contains("figure class=\"chart chart--radar\""))
		#expect(occ(html, "<polygon class=\"chart__mark chart__radar ") == 2, "one polygon per series")
		#expect(occ(html, "chart__grid-ring") == 4, "four grid rings")
		#expect(occ(html, "chart__grid-line") == 4, "one spoke per axis")
		#expect(occ(html, "chart__radar-vertex") == 8, "a vertex per series per axis")
		for axis in ["speed", "reliability", "cost", "support"] {
			#expect(html.contains(">\(axis)<"), "axis label \(axis) must be present")
		}
		#expect(!html.contains("<script"), "no script in chart output")
	}

	@Test func radarNeedsThreeAxes() {
		let html = Chart([RadarMark([("a", 1), ("b", 2)], series: "s").makeMark()], id: "thin").render()
		#expect(html.contains("chart--radar"))
		#expect(!html.contains("chart__radar\""), "a two-axis radar draws no polygon")
	}

	// MARK: t2  radial

	@Test func radialRendersAStrokedArcRingWithCenterValue() {
		let html = Chart([RadialMark(value: 72, of: 100, series: "cpu").makeMark()], id: "gauge").render()
		#expect(html.contains("figure class=\"chart chart--radial\""))
		#expect(occ(html, "chart__radial-track") == 1, "one track per ring")
		#expect(occ(html, "<circle class=\"chart__mark chart__radial ") == 1, "one value arc")
		#expect(html.contains("stroke-dasharray="), "the arc is a dash offset, not a wedge")
		#expect(!html.contains("<path"), "radial must not draw a filled sector path")
		#expect(html.contains(">72%<"), "the center label is the percentage")
	}

	@Test func radialClampsOverAndUnderOneHundredPercent() {
		let over = Chart([RadialMark(value: 250, of: 100).makeMark()], id: "over").render()
		let under = Chart([RadialMark(value: -5, of: 100).makeMark()], id: "under").render()
		#expect(over.contains(">100%<"), "a value over the total clamps to a full ring")
		#expect(under.contains(">0%<"), "a negative value clamps to an empty ring")
	}

	// MARK: t4  area gradients

	@Test func areaGradientEmitsScopedDefsAndIsReferenced() {
		let gradient = ChartGradient([.explicit("var(--color-chart-2)"), .explicit("transparent")])
		let mark = AreaMark(x: .value("x", 1), y: .value("y", 10)).makeMark().areaGradient(gradient)
		let html = Chart([mark], id: "area-a").render()
		#expect(html.contains("<defs><linearGradient id=\"chart-grad-"))
		#expect(html.contains("fill=\"url(#chart-grad-"), "the area path references its gradient")
		#expect(html.contains("stop-color:var(--color-chart-2)"))
		let defsCount = occ(html, "<linearGradient")
		#expect(defsCount == 1)
	}

	@Test func gradientIdsDoNotCollideAcrossCharts() {
		func rendered(_ token: String, id: String) -> String {
			Chart([AreaMark(x: .value("x", 1), y: .value("y", 10)).makeMark()
				.areaGradient(ChartGradient([.explicit(token), .explicit("transparent")]))], id: id).render()
		}
		let a = rendered("var(--color-chart-2)", id: "one")
		let b = rendered("var(--color-chart-4)", id: "two")
		let idA = allCaptures(#"fill="url\(#(chart-grad-[0-9a-f]+)\)""#, in: a).first
		let idB = allCaptures(#"fill="url\(#(chart-grad-[0-9a-f]+)\)""#, in: b).first
		#expect(idA != nil)
		#expect(idB != nil)
		#expect(idA != idB, "two charts with different gradients must not share an id: \(idA ?? "-") vs \(idB ?? "-")")
	}

	@Test func gradientIdsAreDeterministicAcrossRenders() {
		func rendered() -> String {
			Chart([AreaMark(x: .value("x", 1), y: .value("y", 10)).makeMark()
				.areaGradient(ChartGradient.fade(.explicit("var(--color-chart-3)")))], id: "same").render()
		}
		#expect(rendered() == rendered(), "render must be byte-identical for the same input")
	}

	@Test func flatAreaIsUnchangedWithoutAGradient() {
		let html = Chart([AreaMark(x: .value("x", 1), y: .value("y", 10)).makeMark()], id: "flat").render()
		#expect(html.contains("class=\"chart__mark chart__area chart__c1\""), "the default flat fill is preserved")
		#expect(!html.contains("<defs>"), "no defs without a gradient")
	}

	@Test func gradientStopColorsAreFiltered() {
		let gradient = ChartGradient([.explicit("red;}\u{22}><script>alert(1)</script>")])
		let html = Chart([AreaMark(x: .value("x", 1), y: .value("y", 10)).makeMark()
			.areaGradient(gradient)], id: "inject").render()
		#expect(!html.contains("<script"), "an explicit color must not be able to inject markup")
		let stopValue = allCaptures(#"style="stop-color:([^"]*)""#, in: html).first ?? ""
		#expect(!stopValue.contains(";") && !stopValue.contains("<"), "a style value must not carry css or markup: \(stopValue)")
	}

	// MARK: t3  css-only tips

	@Test func barsCarryAnAdjacentHoverTip() {
		let marks = [
			BarMark(x: .value("m", "a"), y: .value("v", 5)).makeMark(),
			BarMark(x: .value("m", "b"), y: .value("v", 8)).makeMark(),
		]
		let html = Chart(marks, id: "tips").render()
		#expect(occ(html, "class=\"chart__tip\"") == 2, "one tip per bar")
		// the css contract is *adjacency*: the tip is the mark's next sibling, so
		// the pair renders as `.../><g class="chart__tip"`. instead of a regex
		// over the whole document, count that exact junction.
		let junctions = occ(html, "/><g class=\"chart__tip\"")
		#expect(junctions == 2, "every tip must be its mark's adjacent sibling (found \(junctions))")
		#expect(occ(html, "aria-hidden=\"true\"") >= 2, "tips are decorative for screen readers")
	}

	@Test func tipTextIsEscapedAndNoScriptLeaks() {
		let mark = BarMark(x: .value("m", "a"), y: .value("v", 5)).makeMark()
			.tooltip("<b>bold</b> & \"quoted\"")
		let html = Chart([mark], id: "tiptext").render()
		#expect(html.contains("&lt;b&gt;"), "markup in a tip is escaped")
		#expect(!html.contains("<b>bold</b>"))
		#expect(!html.contains("<script"))
	}

	@Test func pointsAndSectorsCarryTipsToo() {
		let points = Chart([PointMark(x: .value("x", 1), y: .value("y", 3)).makeMark()], id: "pts").render()
		#expect(occ(points, "class=\"chart__tip\"") == 1, "a point gets a tip")
		let sectors = Chart([SectorMark(angle: .value("share", 30), innerRadiusRatio: 0.0).makeMark()],
			id: "pie").render()
		#expect(occ(sectors, "class=\"chart__tip\"") == 1, "a sector gets a tip")
	}
}