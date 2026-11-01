import Testing
import WebUI

// the edge-spacing contract.
//
// `margin(_ all: Int)` was the only typed spacing door, so a single-edge margin
// had no typed spelling and fell back to `.attribute("style", "margin-top:12px")`.
// these tests pin two things: the token spelling (`var(--space-N)`, never px)
// and the fold — a chain of edge modifiers lands as declarations in ONE `style`
// attribute, in call order, never as two attributes (the browser drops the
// later one, so a second attribute is a silently missing margin).

extension WebUITestRoot {
	@Suite("edge spacing", .serialized)
	struct EdgeSpacingTests {

		// MARK: - one token, one property

		@Test("a token margin is one declaration in token spelling")
		func tokenMargin() {
			let html = Div { Text("x") }.margin(.three).markup.html
			#expect(html == "<div style=\"margin: var(--space-3);\">x</div>", "got: \(html)")
		}

		@Test("a single-edge margin names the side")
		func edgeMargin() {
			let html = Div { Text("x") }.margin(.top, .three).markup.html
			#expect(html == "<div style=\"margin-top: var(--space-3);\">x</div>", "got: \(html)")
		}

		@Test("a single-edge padding names the side")
		func edgePadding() {
			let html = Div { Text("x") }.padding(.left, .two).markup.html
			#expect(html == "<div style=\"padding-left: var(--space-2);\">x</div>", "got: \(html)")
		}

		// MARK: - the fold

		@Test("a chain folds into one style attribute, in call order")
		func chainFoldsIntoOneStyle() throws {
			let html = Div { Text("x") }
				.margin(.top, .three)
				.margin(.bottom, .one)
				.markup.html
			#expect(styleAttributeCount(html) == 1, "expected exactly one style attribute, got: \(html)")
			#expect(
				html == "<div style=\"margin-top: var(--space-3); margin-bottom: var(--space-1);\">x</div>",
				"got: \(html)"
			)
			// order is call order, spelled out: the outer modifier contributes its
			// declaration first, so a fold that appended in contribution order would
			// read bottom then top.
			let top = try #require(html.range(of: "margin-top"))
			let bottom = try #require(html.range(of: "margin-bottom"))
			#expect(top.lowerBound < bottom.lowerBound, "declarations out of call order: \(html)")
		}

		@Test("the axis overload composes two declarations on that axis")
		func axisComposesTwoDeclarations() {
			let horizontal = Div { Text("x") }.margin(.horizontal, .two).markup.html
			#expect(
				horizontal == "<div style=\"margin-left: var(--space-2); margin-right: var(--space-2);\">x</div>",
				"got: \(horizontal)"
			)
			#expect(styleAttributeCount(horizontal) == 1, "expected one style attribute, got: \(horizontal)")
			let vertical = Div { Text("x") }.margin(.vertical, .two).markup.html
			#expect(
				vertical == "<div style=\"margin-top: var(--space-2); margin-bottom: var(--space-2);\">x</div>",
				"got: \(vertical)"
			)
			#expect(styleAttributeCount(vertical) == 1, "expected one style attribute, got: \(vertical)")
		}

		@Test("the two-value shorthand puts vertical first")
		func twoValueShorthand() {
			let html = Div { Text("x") }.margin(horizontal: .two, vertical: .one).markup.html
			#expect(html == "<div style=\"margin: var(--space-1) var(--space-2);\">x</div>", "got: \(html)")
		}

		@Test("the zero the Int overload already took still resolves")
		func intZeroIsUnambiguous() {
			// `margin(.zero)` reports "ambiguous use of 'zero'" the moment a
			// `SpaceToken.zero` exists next to `margin(_ all: Int)` — `Int` has a
			// `zero` of its own. the fix was to not add that case, so this pins the
			// absence: the px overload still takes a literal zero and nothing
			// competes for the spelling.
			let html = Div { Text("x") }.margin(0).markup.html
			#expect(html == "<div style=\"margin: 0px;\">x</div>", "got: \(html)")
		}

		// MARK: - coexistence

		@Test("a class the element already emits survives the added style")
		func classSurvives() {
			// `Div(class:)` emits its own attribute, the shape a component's class
			// has: the contributed style must join that element, not replace it or
			// arrive as a second style.
			let html = Div(class: "card") { Text("x") }.margin(.two).markup.html
			#expect(html.contains("class=\"card\""), "class lost: \(html)")
			#expect(styleAttributeCount(html) == 1, "expected exactly one style attribute, got: \(html)")
			#expect(html.contains("margin: var(--space-2);"), "margin missing: \(html)")
		}
	}

}

// how many `style="` occurrences the markup carries. the count is the assertion:
// two of them is the defect these tests exist for, whatever their bytes.
private func styleAttributeCount(_ html: String) -> Int {
	html.components(separatedBy: "style=\"").count - 1
}
