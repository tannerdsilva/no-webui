import Testing
import WebUI
import WebUISharedCore

// the S1 contract for the render buffer (`.hermes/plans/2026-09-28_123131-render-buffer-v2.md` §3).
//
// two things are pinned here:
//
// 1. **the dispatch mechanism.** `render(into:)` and `decorate(_:into:)` must be
//    protocol *requirements*. as plain extension methods they resolve
//    statically, so every `any View` / generic call would silently run the
//    fallback and a migrated view's override would never execute — the whole
//    migration would measure zero and S2's stop/go gate would read that as a
//    dead end. the probes below fail if the requirement is ever "simplified"
//    into an extension method.
// 2. **byte-identity.** the migrated containers must produce exactly the bytes
//    the string path produced, including the literal newlines the old
//    multi-line literals carried.

@Suite("render into buffer")
struct RenderIntoBufferTests {

	// MARK: - dispatch probes
	//
	// the probes deliberately render *different* bytes from `render(into:)` and
	// `render()`, so a test can tell which one ran. real views must keep the two
	// identical — that is what the container pins below check.

	private struct BufferOverride: View {
		func render() -> String { "from string" }
		func render(into buffer: inout HTMLBuffer) { buffer.append("from buffer") }
	}

	private struct StringOnly: View {
		func render() -> String { "from string" }
	}

	private func renderGenerically<V: View>(_ view: V) -> String {
		var buffer = HTMLBuffer()
		view.render(into: &buffer)
		return buffer.finish()
	}

	private func renderExistentially(_ view: any View) -> String {
		var buffer = HTMLBuffer()
		view.render(into: &buffer)
		return buffer.finish()
	}

	@Test("a view's render(into:) override wins through a generic call")
	func dispatchThroughGeneric() {
		#expect(renderGenerically(BufferOverride()) == "from buffer")
	}

	@Test("a view's render(into:) override wins through an existential call")
	func dispatchThroughExistential() {
		#expect(renderExistentially(BufferOverride()) == "from buffer")
	}

	@Test("a view that implements only render() falls back, both ways")
	func renderFallback() {
		#expect(renderGenerically(StringOnly()) == "from string")
		#expect(renderExistentially(StringOnly()) == "from string")
		// and through a migrated container's child loop
		#expect(Div { StringOnly() }.render() == "<div>from string</div>")
	}

	@Test("a migrated view's render() is exactly the buffer roundtrip")
	func renderIsTheRoundtrip() {
		let view = Grid { Div { Text("x") } }
		var buffer = HTMLBuffer()
		view.render(into: &buffer)
		#expect(buffer.finish() == view.render())
	}

	private struct ModifierOverride: ViewModifier {
		func apply(to html: String) -> String { "from string(\(html))" }
		func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
			buffer.append("from buffer")
		}
	}

	private func decorateGenerically<M: ViewModifier>(_ modifier: M, around content: Text) -> String {
		var buffer = HTMLBuffer()
		modifier.decorate(content, into: &buffer)
		return buffer.finish()
	}

	@Test("a modifier's decorate override wins through ModifiedView")
	func modifierDispatchThroughModifiedView() {
		#expect(ModifiedView(content: Text("x"), modifier: ModifierOverride()).render() == "from buffer")
	}

	@Test("a modifier's decorate override wins through a generic call")
	func modifierDispatchThroughGeneric() {
		#expect(decorateGenerically(ModifierOverride(), around: Text("x")) == "from buffer")
	}

	@Test("an unmigrated modifier applies to the content's string render")
	func modifierFallback() {
		// the S1 fallback re-parses the content's html; S2 replaces this path
		// for the migrated modifier set, and this pin flips with it
		#expect(Div { Text("x") }.padding(4).render() == "<div style=\"padding: 4px;\">x</div>")
	}

	// MARK: - container byte-identity

	@Test("div and span frame their own element")
	func divAndSpan() {
		#expect(Div { Text("in") }.render() == "<div>in</div>")
		#expect(Div(id: "d", class: "c") { Text("in") }.render() == "<div id=\"d\" class=\"c\">in</div>")
		#expect(Span(class: "s") { Text("x") }.render() == "<span class=\"s\">x</span>")
	}

	@Test("section, the list family, and ForEach frame like the string path")
	func sectionListsAndForEach() {
		#expect(Section(id: "s", class: "sec") { Text("x") }.render() == "<section id=\"s\" class=\"sec\">x</section>")
		#expect(UnorderedList { Text("a"); Text("b") }.render() == "<ul><li>a</li><li>b</li></ul>")
		#expect(OrderedList(class: "ol") { Text("a") }.render() == "<ol class=\"ol\"><li>a</li></ol>")
		#expect(ForEach([1, 2, 3]) { Text("\($0)") }.render() == "123")
	}

	@Test("the stacks keep the literal newlines the string path emitted")
	func stackNewlines() {
		#expect(VStack { Text("a"); Text("b") }.render()
			== "<div class=\"vstack spacing-8 align-flex-start\">\nab\n</div>")
		#expect(HStack { Text("a") }.render()
			== "<div class=\"hstack spacing-8 align-center\">\na\n</div>")
		#expect(ZStack { Text("z") }.render()
			== "<div class=\"zstack\" style=\"display:grid;place-items:center center;\">\nz\n</div>")
		#expect(Grid { Text("g") }.render()
			== "<div class=\"grid\" style=\"display:grid;grid-template-columns:repeat(2, 1fr);gap:16px;\">\ng\n</div>")
	}

	@Test("an empty stack keeps its literal newlines")
	func emptyStack() {
		#expect(VStack { }.render() == "<div class=\"vstack spacing-8 align-flex-start\">\n\n</div>")
	}

	@Test("nested containers share one buffer and keep their bytes")
	func nestedContainers() {
		let view = VStack { Div { Text("x") }; Span { Text("y") } }
		#expect(view.render()
			== "<div class=\"vstack spacing-8 align-flex-start\">\n<div>x</div><span>y</span>\n</div>")
	}

	@Test("a migrated view renders the same bytes on every call")
	func deterministic() {
		let view = VStack { Div(id: "i") { Text("x") } }
		#expect(view.render() == view.render())
	}

	@Test("a contribution drains into the container's own element")
	func contributionDrainsIntoContainer() {
		var buffer = HTMLBuffer()
		buffer.addAttribute("class=\"c\"")
		Div { Text("x") }.render(into: &buffer)
		#expect(buffer.finish() == "<div class=\"c\">x</div>")
		#expect(!buffer.hasPendingAttributes)
	}

	@Test("a container reaches its children through any View")
	func containerDispatchesToChildren() {
		#expect(Div { BufferOverride() }.render() == "<div>from buffer</div>")
		#expect(VStack { BufferOverride() }.render()
			== "<div class=\"vstack spacing-8 align-flex-start\">\nfrom buffer\n</div>")
	}

	@Test("an element with no contribution keeps its own attribute text byte-for-byte")
	func verbatimBaseAttributes() {
		var buffer = HTMLBuffer()
		// a raw quote in attribute text can only arrive through unescaped
		// caller input (`GridColumns.custom` is the one such path). the old
		// string path concatenated it as-is; the buffer must not "fix" it
		// into different bytes. the merge round trip runs only when a
		// contribution exists.
		buffer.beginElement("div", " data-x=\"a\"b\"")
		buffer.endOpenTag()
		buffer.endElement()
		#expect(buffer.finish() == "<div data-x=\"a\"b\"></div>")
	}

	@Test("render(into:) appends into an existing buffer")
	func appendsIntoExistingBuffer() {
		var buffer = HTMLBuffer()
		buffer.append("<!-- pre -->")
		Grid { Text("g") }.render(into: &buffer)
		#expect(buffer.finish()
			== "<!-- pre --><div class=\"grid\" style=\"display:grid;grid-template-columns:repeat(2, 1fr);gap:16px;\">\ng\n</div>")
	}
}