import Foundation
import Testing
@testable import WebUIContinuumTool

// MARK: - the token-debt axis of the audit (MACRO_DX G3 / G6c)
//
// the colour axis is nearly done (appendix E §2): the framework's 313 literal
// colours are ~90% test fixtures and the consumer's live in its ThemeCatalog —
// what remains is REPORTED here, in the three value metrics a token migration
// would move: literal #hex colours, var(--) references, and inline style=
// strings. the demo tree's own counts ride the probe (`g-styling.mjs`).

@Suite("markup-debt audit: the token axis (colours, var(--), inline styles)")
struct TokenDebtTests {

	@Test("a planted fixture reports the token values")
	func plantedCounts() {
		let source = """
		let a = "#FF8800"
		let b = "var(--color-primary-500)"
		let c = "var(--space-8)"
		let d = "style=\\"color: #1a1a1a;\\""
		"""
		let m = markupDebtMetrics(in: source)
		#expect(m.literalColors == 2, "got \(m.literalColors)")
		#expect(m.varRefs == 2, "got \(m.varRefs)")
		#expect(m.inlineStyles == 1, "got \(m.inlineStyles)")
	}

	@Test("a clean file reports zeros across the token axis")
	func cleanFileIsZero() {
		let m = markupDebtMetrics(in: "let x = 1\nlet y = computedValue()\n")
		#expect(m.literalColors == 0)
		#expect(m.varRefs == 0)
		#expect(m.inlineStyles == 0)
		#expect(m.rawTags == 0)
		#expect(m.classLiterals == 0)
	}

	@Test("swift keywords that start with # never count as colours")
	func swiftKeywordsNotColours() {
		let source = "#expect(x == 1)\n#if DEBUG\n#warning(\"tag\")\n#endif"
		let m = markupDebtMetrics(in: source)
		#expect(m.literalColors == 0, "got \(m.literalColors)")
		#expect(m.rawTags == 0, "got \(m.rawTags)")
	}

	@Test("only hex colours count — rgba/other forms are out of the metric")
	func onlyHexCounts() {
		let source = """
		let a = "rgb(255, 0, 0)"
		let b = "hsl(120, 50%, 50%)"
		let c = "#0f0"
		let d = "#00ff00cc"
		"""
		let m = markupDebtMetrics(in: source)
		#expect(m.literalColors == 2, "3-digit + 8-digit hex only: got \(m.literalColors)")
	}

	@Test("baseline comparison sees the token axis independently")
	func tokenAxisComparison() {
		let before = MarkupDebtMetrics(rawTags: 20, classLiterals: 10, inlineStyles: 5, literalColors: 4, varRefs: 3)
		let after = MarkupDebtMetrics(rawTags: 20, classLiterals: 10, inlineStyles: 5, literalColors: 6, varRefs: 3)
		#expect(after.grown(over: before) == ["colors 4 -> 6"], "only the grown metric is named")
	}
}
