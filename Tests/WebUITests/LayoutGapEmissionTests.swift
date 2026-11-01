import Testing
import WebUI

// the stack gap contract.
//
// `VStack`/`HStack` used to emit `class="vstack spacing-N align-…"`, where the
// `gap` came from `.spacing-N` rules that `LayoutStyles.complete` generates for
// exactly nine values (0, 2, 4, 8, 12, 16, 20, 24, 32). every call site happens
// to use one of those nine today, so nothing was broken — but the parameter is
// an `Int`, and a value outside the generated set rendered a class with no rule
// and no diagnostic. `Grid` already emitted its gap inline, which is total over
// any `Int`; these tests pin the stacks to the same shape.

extension WebUITestRoot {
	@Suite("Layout gap emission", .serialized)
	struct LayoutGapEmissionTests {

		@Test("vstack carries its gap inline and emits no spacing class")
		func vstackGapIsInline() {
			let html = VStack(spacing: 12) { Text("a") }.markup.html
			#expect(html.contains("style=\"gap:12px;\""), "expected an inline gap, got: \(html)")
			#expect(!html.contains("spacing-"), "a spacing class survived: \(html)")
		}

		@Test("hstack carries its gap inline and emits no spacing class")
		func hstackGapIsInline() {
			let html = HStack(spacing: 8) { Text("a") }.markup.html
			#expect(html.contains("style=\"gap:8px;\""), "expected an inline gap, got: \(html)")
			#expect(!html.contains("spacing-"), "a spacing class survived: \(html)")
		}

		@Test("a gap outside the old generated set still emits a usable declaration")
		func gapOutsideTheGeneratedSet() {
			// 10px had no `.spacing-10` rule under the class-based emission. the
			// inline gap is total over Int, so the declaration now always applies.
			let html = VStack(spacing: 10) { Text("a") }.markup.html
			#expect(html.contains("gap:10px;"), "expected gap:10px, got: \(html)")
		}

		@Test("the alignment class the stack still emits has a rule behind it")
		func alignmentClassSurvives() {
			// the gap moved inline; the alignment class did not, and must not: its
			// rules are `.align-flex-start|center|flex-end` from LayoutStyles.complete.
			let html = VStack(alignment: .trailing, spacing: 4) { Text("a") }.markup.html
			#expect(html.contains("align-flex-end"), "expected align-flex-end, got: \(html)")
		}
	}
}
