import Testing
@testable import WebUI

// the attribute-merge contract behind `injectAttributes`. this is the spec the
// render-buffer work (`.hermes/plans/2026-09-28_123131-render-buffer-v2.md`) must
// reproduce byte-for-byte when the machinery moves to the shared leaf, so the
// cases are written as explicit input -> output pairs rather than as prose.
//
// the duplicate cases below are the regression: `firstIndex` used to hold
// positions in the pre-compaction array, so a target key whose first occurrence
// followed a dropped duplicate indexed past the end and trapped.

@Suite("attribute merge")
struct AttributeMergeTests {

	// MARK: - the regression (was: Index out of range)

	@Test("a duplicate before the merged key no longer indexes past the end")
	func duplicateBeforeTarget() {
		// `class` appears twice (the second is dropped), so `style`'s first
		// occurrence sits after a tombstone.
		let out = injectAttributes(into: "<div class=\"a\" class=\"b\" style=\"x:1\">t</div>", "style=\"y:2\"")
		#expect(out == "<div class=\"a\" style=\"x:1; y:2\">t</div>")
	}

	@Test("two duplicated keys before the merged key")
	func twoDuplicatesBeforeTarget() {
		let out = injectAttributes(
			into: "<div class=\"a\" id=\"i\" class=\"b\" id=\"j\" style=\"x:1\">t</div>",
			"style=\"y:2\""
		)
		#expect(out == "<div class=\"a\" id=\"i\" style=\"x:1; y:2\">t</div>")
	}

	@Test("a duplicated key hit directly by a non-style incoming value")
	func duplicateKeyNonStyleIncoming() {
		let out = injectAttributes(into: "<div class=\"a\" class=\"b\" style=\"x:1\">t</div>", "class=\"c\"")
		#expect(out == "<div class=\"c\" style=\"x:1\">t</div>")
	}

	@Test("a duplicate after the merged key keeps the earlier position")
	func duplicateAfterTarget() {
		let out = injectAttributes(into: "<div style=\"x:1\" class=\"a\" class=\"b\">t</div>", "style=\"y:2\"")
		#expect(out == "<div style=\"x:1; y:2\" class=\"a\">t</div>")
	}

	// MARK: - the documented merge semantics

	@Test("chained styles append declarations instead of shipping a dead second attribute")
	func chainedStylesAppend() {
		let once = injectAttributes(into: "<div style=\"color:red\">t</div>", "style=\"padding:4px\"")
		#expect(once == "<div style=\"color:red; padding:4px\">t</div>")
		let twice = injectAttributes(into: once, "style=\"margin:0\"")
		#expect(twice == "<div style=\"color:red; padding:4px; margin:0\">t</div>")
	}

	@Test("a non-style incoming value replaces the earlier one (later intent wins)")
	func nonStyleIncomingReplaces() {
		let out = injectAttributes(into: "<div id=\"old\" class=\"card\">t</div>", "id=\"new\"")
		#expect(out == "<div id=\"new\" class=\"card\">t</div>")
	}

	@Test("an empty incoming style leaves the existing declaration list untouched")
	func emptyIncomingStyleIsIgnored() {
		let out = injectAttributes(into: "<div style=\"color:red\">t</div>", "style=\"\"")
		#expect(out == "<div style=\"color:red\">t</div>")
	}

	@Test("incoming attributes append in order after the existing ones")
	func incomingAppendOrder() {
		let out = injectAttributes(into: "<div class=\"card\">t</div>", "data-component-id=\"c1\" data-event=\"click\"")
		#expect(out == "<div class=\"card\" data-component-id=\"c1\" data-event=\"click\">t</div>")
	}

	// MARK: - the three tag shapes

	@Test("content with no tag is wrapped in a span carrying the attributes")
	func noTagWrapsInSpan() {
		let out = injectAttributes(into: "just text", "class=\"x\"")
		#expect(out == "<span class=\"x\">just text</span>")
	}

	@Test("a comment or doctype first leaves the html untouched")
	func commentAndDoctypeAreLeftAlone() {
		#expect(injectAttributes(into: "<!-- c -->text", "class=\"x\"") == "<!-- c -->text")
		#expect(injectAttributes(into: "<!doctype html><p>t</p>", "class=\"x\"") == "<!doctype html><p>t</p>")
		#expect(injectAttributes(into: "<?xml version=\"1.0\"?>t", "class=\"x\"") == "<?xml version=\"1.0\"?>t")
	}

	@Test("a self-closing root tag keeps its slash")
	func selfClosingTag() {
		let out = injectAttributes(into: "<img src=\"a.png\"/>", "class=\"x\"")
		#expect(out == "<img src=\"a.png\" class=\"x\"/>")
	}

	@Test("a quote inside an attribute value does not end the tag scan")
	func quotedAngleBracket() {
		let out = injectAttributes(into: "<div title=\"a>b\" class=\"card\">t</div>", "id=\"i\"")
		#expect(out == "<div title=\"a>b\" class=\"card\" id=\"i\">t</div>")
	}
}