import Testing
import WebUICore

// the attribute vocabulary's contract.
//
// every test here asserts the two things that made the string spellings
// dangerous: that the emitted attribute is exactly what the engine/handler
// reads, and that a `when: false` case emits NOTHING rather than an empty
// attribute.

@Suite("attribute vocabulary")
struct AttributeVocabularyTests {

	private func markup(_ view: some View) -> String { view.markup.html }

	// MARK: aria

	@Test("several aria attributes land on one element")
	func ariaMultiple() {
		let html = markup(Div(class: "f") { Text("x") }
			.aria([.invalid(true), .describedby("err-1")]))
		#expect(html.contains("aria-invalid=\"true\""), "got: \(html)")
		#expect(html.contains("aria-describedby=\"err-1\""), "got: \(html)")
	}

	@Test("aria is conditional without a Group")
	func ariaConditional() {
		let off = markup(Div { Text("x") }.aria([.invalid(true)], when: false))
		#expect(!off.contains("aria-invalid"), "absent, not empty: \(off)")
		#expect(off.contains("<div>"), "the element still renders: \(off)")
	}

	@Test("the single-attribute aria modifier still works")
	func ariaSingleUnchanged() {
		// the pre-existing spelling must not be broken by the array form.
		#expect(markup(Div { Text("x") }.aria(.label("Filter"))).contains("aria-label=\"Filter\""))
	}

	// MARK: data-*

	@Test("data adds its own prefix")
	func dataPrefix() {
		let html = markup(Div { Text("x") }.data("scroll-key", "main"))
		#expect(html.contains("data-scroll-key=\"main\""), "got: \(html)")
		#expect(!html.contains("data-data-"), "the prefix is not doubled: \(html)")
	}

	@Test("data accepts a name that already carries the prefix")
	func dataIdempotentPrefix() {
		let html = markup(Div { Text("x") }.data("data-follow", ""))
		#expect(html.contains("data-follow=\"\""), "got: \(html)")
		#expect(!html.contains("data-data-follow"))
	}

	// MARK: presence attributes

	@Test("a presence attribute is bare, not empty-valued")
	func presenceBare() {
		let html = markup(Div { Text("x") }.flag(.hidden))
		#expect(html.contains(" hidden"), "got: \(html)")
		#expect(!html.contains("hidden=\"\""), "bare, not `hidden=\"\"`: \(html)")
	}

	@Test("a false presence attribute is absent entirely")
	func presenceAbsent() {
		let html = markup(Input(field: "a").flag(.readonly, when: false))
		#expect(!html.contains("readonly"), "got: \(html)")
	}

	@Test("every presence attribute has a valid html name")
	func presenceVocabulary() {
		for attribute in PresenceAttribute.allCases {
			#expect(attribute.rawValue == attribute.rawValue.lowercased())
			#expect(!attribute.rawValue.isEmpty)
		}
	}

	// MARK: wiring

	@Test("wire emits the id and event the client matches on")
	func wireAttributes() {
		let html = markup(Div { Text("x") }.wire("tool-list"))
		#expect(html.contains("data-component-id=\"tool-list\""), "got: \(html)")
		#expect(html.contains("data-event=\"click\""), "got: \(html)")
	}

	@Test("wire takes any event in the deck's vocabulary")
	func wireEvent() {
		let html = markup(Input(field: "q").wire("tool-search", on: .input))
		#expect(html.contains("data-event=\"input\""), "got: \(html)")
	}

	@Test("two wires on nested elements do not collide")
	func nestedWires() {
		let html = markup(
			Div { Div { Text("x") }.wire("inner") }.wire("outer")
		)
		#expect(html.contains("data-component-id=\"outer\""))
		#expect(html.contains("data-component-id=\"inner\""))
		#expect(html.components(separatedBy: "data-component-id").count == 3, "one each: \(html)")
	}

	// MARK: engine key

	@Test("webuiKey emits the attribute the engine reads")
	func engineKey() {
		let html = markup(Div { Text("x") }.webuiKey("row-7"))
		#expect(html.contains("data-webui-key=\"row-7\""), "got: \(html)")
	}

	// MARK: css variables

	@Test("a custom property rides one style attribute with its unit")
	func cssVarLength() {
		let html = markup(Div { Text("x") }.cssVar("--ws-depth", .number(3)).cssVar("--ws-extra", .length(4)))
		#expect(html.components(separatedBy: "style=\"").count == 2, "one style attribute: \(html)")
		#expect(html.contains("--ws-depth: 3;"), "got: \(html)")
		#expect(html.contains("--ws-extra: 4px;"), "got: \(html)")
	}

	@Test("a colour rides as data")
	func cssVarColor() {
		let html = markup(Div { Text("x") }.cssVar("--accent", .color("#ff8800")))
		#expect(html.contains("--accent: #ff8800;"), "got: \(html)")
	}

	// MARK: trusted markup

	@Test("trusted markup renders unescaped and names its source")
	func trustedMarkup() {
		let view = TrustedMarkup("<b>bold</b>", from: .markdown)
		#expect(markup(view) == "<b>bold</b>")
		#expect(TrustedSource.plugin("katex").label == "plugin:katex")
	}

	// MARK: class audit

	@Test("a typo'd class is reported, a declared one is not")
	func auditUndeclared() {
		let missing = ClassNameAudit.undeclared(
			used: ["card", "card__titl"],
			declared: ["card", "card__title"]
		)
		#expect(missing == ["card__titl"], "got: \(missing)")
	}

	@Test("declared-but-unused is a separate report from used-but-undeclared")
	func auditUnused() {
		let unused = ClassNameAudit.unused(declared: ["a", "b", "c"], used: ["a"])
		#expect(unused == ["b", "c"], "got: \(unused)")
	}

	@Test("a variable can be conditional")
	func cssVarConditional() {
		let off = markup(Div { Text("x") }.cssVar("--ws-depth", .number(3), when: false))
		#expect(!off.contains("--ws-depth: 3"), "no declaration when false: \(off)")
	}

	@Test("an identified view wires under its own stable id")
	func identifiedWire() {
		struct Row: View, Identified {
			var stableID: String? { "row-7" }
			func render(into buffer: inout HTMLBuffer) {
				buffer.beginElement("div", " class=\"row\""); buffer.endOpenTag()
				buffer.appendEscaped("x"); buffer.endElement()
			}
		}
		let html = markup(Row().wire())
		#expect(html.contains("data-component-id=\"row-7\""), "got: \(html)")
		#expect(html.contains("data-event=\"click\""), "got: \(html)")
	}

	// MARK: element authoring

	@Test("element emits tag, class and content")
	func elementBasics() {
		let html = markup(Element(.section, class: "card", id: "s1") { Text("hi") })
		#expect(html == "<section id=\"s1\" class=\"card\">hi</section>", "got: \(html)")
	}

	@Test("element nests and preserves order")
	func elementNesting() {
		let html = markup(Element(.ul) { Element(.li) { Text("a") }; Element(.li) { Text("b") } })
		#expect(html == "<ul><li>a</li><li>b</li></ul>", "got: \(html)")
	}
}