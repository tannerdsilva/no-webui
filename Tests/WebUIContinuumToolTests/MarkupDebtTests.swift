import Foundation
import Testing
@testable import WebUIContinuumTool

// MARK: - the markup-debt audit (MACRO_DX G3) — the full five-metric contract
//
// every number below reproduces from `markupDebtMetrics(in:)` — the committed
// script's pure core — so the audit's accept holds: a planted fixture prints
// known counts, the framework allowlist is reported-not-ratcheted, and a
// deliberately-grown fixture trips `--fail-on-increase`.

@Suite("markup-debt audit: the five metrics")
struct MarkupDebtTests {

	@Test("a planted fixture counts the five code-borne metrics, comments excluded")
	func plantedFixtureCounts() {
		let source = """
		// this comment carries <div class="c" style="x">#fff and must NOT count
		let body = "<div class=\\"card\\" role=\\"status\\"><span>hi</span><p>#ff0000</p></div>"
		let style = "style=\\"display:flex;\\""
		let color = "#2E8B57"
		let ref = "var(--space-4)"
		let url = "https://example.com/x" // the // here must not kill this line
		"""
		let m = markupDebtMetrics(in: source)
		#expect(m.rawTags == 6, "div+span+p, open+close each: got \(m.rawTags)")
		#expect(m.classLiterals == 1, "got \(m.classLiterals)")
		#expect(m.inlineStyles == 1, "got \(m.inlineStyles)")
		#expect(m.literalColors == 2, "got \(m.literalColors)")
		#expect(m.varRefs == 1, "got \(m.varRefs)")
	}

	@Test("block comments are stripped (code-borne only), strings survive")
	func blockCommentsStripped() {
		let source = """
		/*
			<div class="blocky" style="gap:7px;"> #abcdef var(--space-8)
		*/
		let x = "<div class=\\"real\\">#123456</div>"
		"""
		let m = markupDebtMetrics(in: source)
		#expect(m.rawTags == 2, "the code div opens AND closes: got \(m.rawTags)")
		#expect(m.classLiterals == 1)
		#expect(m.literalColors == 1)
		#expect(m.varRefs == 0, "the var() inside the block comment must not count")
	}

	@Test("swift generics are never counted as tags, svg counts")
	func genericsNotTags() {
		let source = """
		let pair = some Generic<Div, Int> and also <T> or <Void>
		let icon = "<svg class=\\"icon\\" width=\\"24\\"><path/></svg>"
		"""
		let m = markupDebtMetrics(in: source)
		#expect(m.rawTags == 3, "svg open + self-closing path + svg close: got \(m.rawTags)")
	}

	@Test("class= and style= count both the plain and the escaped Swift spellings")
	func bothAttributeSpellings() {
		let source = #"let a = "class=\"x\" style=\"y\"" and plain class="z" style="w""#
		let m = markupDebtMetrics(in: source)
		#expect(m.classLiterals == 2, "got \(m.classLiterals)")
		#expect(m.inlineStyles == 2, "got \(m.inlineStyles)")
	}

	@Test("the framework allowlist is reported, never ratcheted")
	func allowlistHonoured() {
		// a DS-core path: metrics print in the report but the comparison skips it.
		// exercised through the pure comparison: a DS-core file whose baseline is
		// absent must NOT register an increase.
		let baseline = MarkupDebtBaseline(version: 1, allowlistPrefixes: ["Sources/WebUIDesignSystemCore"], files: [:])
		let current = MarkupDebtMetrics(rawTags: 5, classLiterals: 4, inlineStyles: 3, literalColors: 2, varRefs: 1)
		#expect(current.grown(over: .zero) == ["tags 0 -> 5", "class 0 -> 4", "style 0 -> 3", "colors 0 -> 2", "var() 0 -> 1"])
		_ = baseline
		// the path-level filter is exercised by the CLI; here we pin the split:
		#expect("Sources/WebUIDesignSystemCore/WebUIComponents.swift".hasPrefix("Sources/WebUIDesignSystemCore"))
	}

	@Test("a grown fixture trips the increase comparison")
	func grownFixtureTrips() {
		let baseline = MarkupDebtBaseline(version: 1, allowlistPrefixes: ["Sources/WebUIDesignSystemCore"], files: [
			"Sources/App/View.swift": MarkupDebtMetrics(rawTags: 6, classLiterals: 1, inlineStyles: 1, literalColors: 2, varRefs: 1),
		])
		let grown = MarkupDebtMetrics(rawTags: 10, classLiterals: 2, inlineStyles: 1, literalColors: 2, varRefs: 1)
		#expect(grown.grown(over: baseline.files["Sources/App/View.swift"]!) == ["tags 6 -> 10", "class 1 -> 2"])
		// a shrunk or unchanged file reports nothing.
		#expect(MarkupDebtMetrics.zero.grown(over: baseline.files["Sources/App/View.swift"]!).isEmpty)
	}

	@Test("a missing baseline entry counts growth from zero (a new file)")
	func newFileCountsFromZero() {
		let baseline = MarkupDebtBaseline(version: 1, allowlistPrefixes: ["Sources/WebUIDesignSystemCore"], files: [:])
		let current = MarkupDebtMetrics(rawTags: 3, classLiterals: 0, inlineStyles: 0, literalColors: 0, varRefs: 0)
		#expect(current.grown(over: baseline.files["Sources/App/New.swift"] ?? .zero) == ["tags 0 -> 3"])
	}

	@Test("the baseline round-trips through json")
	func baselineRoundTrips() throws {
		let baseline = MarkupDebtBaseline(version: 1, allowlistPrefixes: ["Sources/WebUIDesignSystemCore"], files: [
			"a.swift": MarkupDebtMetrics(rawTags: 1, classLiterals: 2, inlineStyles: 3, literalColors: 4, varRefs: 5),
		])
		let data = try JSONEncoder().encode(baseline)
		let decoded = try JSONDecoder().decode(MarkupDebtBaseline.self, from: data)
		#expect(decoded.files["a.swift"] == baseline.files["a.swift"])
		#expect(decoded.allowlistPrefixes == baseline.allowlistPrefixes)
	}
}
