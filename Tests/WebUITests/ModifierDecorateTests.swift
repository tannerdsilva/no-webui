import Testing
import WebUI
import WebUISharedCore

// the S2 contract (`.hermes/plans/2026-09-28_123131-render-buffer-v2.md` §2.3, §3 S2):
// migrated modifiers contribute through the buffer's pending slot, and content
// that opens no element is settled through the string-path rules instead.
//
// two of the plan's S2 items are pinned here as DEFERRED decisions rather than
// migrations, because moving them would change bytes:
//
//   - the auto-minting event modifiers (`EventHandlerModifier`,
//     `OptimisticClickModifier`): their attribute needs an id minted AFTER the
//     content renders — the string path mints in post-order, and tests across
//     the suite pin `c0`/`c1` — while contributing after the content would
//     invert the attribute order of a mixed chain like `.padding(4).onClick(…)`.
//   - `AnyViewModifier` (a `(String) -> String` eraser: the buffer route is
//     structurally unavailable) and `IconSizeModifier` (it rewrites a class
//     token inside an existing attribute; the merge model replaces whole keys,
//     not tokens).

@Suite("modifier decorate")
struct ModifierDecorateTests {

	// MARK: the three §2.3 behaviours, through migrated modifiers

	@Test("a contribution lands in the first tag of buffer-native content")
	func contributionLandsInElement() {
		#expect(Div { Text("x") }.id("i").render() == "<div id=\"i\">x</div>")
		#expect(Div { Text("x") }.id("i").class("c").render() == "<div id=\"i\" class=\"c\">x</div>")
	}

	@Test("a contribution lands in the first tag of string-rendered content")
	func contributionLandsInStringContent() {
		#expect(Raw("<p>t</p>").attribute("data-x", "1").render() == "<p data-x=\"1\">t</p>")
		#expect(Div { Raw("<p>t</p>") }.class("c").render() == "<div class=\"c\"><p>t</p></div>")
	}

	@Test("content with no tag is wrapped in a span carrying the contribution")
	func noTagWrapsInSpan() {
		#expect(Text("just text").class("x").render() == "<span class=\"x\">just text</span>")
		#expect(Text("just text").attribute("id", "i").render() == "<span id=\"i\">just text</span>")
	}

	@Test("a declaration or closing tag first leaves the content untouched")
	func declarationFirstLeavesContentAlone() {
		#expect(Raw("<!-- c -->text").class("x").render() == "<!-- c -->text")
		#expect(Raw("<!doctype html><p>t</p>").class("x").render() == "<!doctype html><p>t</p>")
		#expect(Raw("</div>tail").class("x").render() == "</div>tail")
	}

	// MARK: chained contributions

	@Test("chained styles fold into one declaration list inside the span")
	func chainedStylesFoldInSpan() {
		// two style contributions must not ship as two style attributes: the
		// string path created the span with the first, then merged the second
		// into it. the buffer folds them in the same pass.
		let html = Text("Hello").foregroundColor("red").backgroundColor("blue").render()
		#expect(html == "<span style=\"color: red; background-color: blue;\">Hello</span>")
	}

	@Test("chained styles keep declaration order, innermost first")
	func chainedStylesKeepOrder() {
		let html = Text("Box").padding(8).margin(2).foregroundColor("red").render()
		#expect(html == "<span style=\"padding: 8px; margin: 2px; color: red;\">Box</span>")
	}

	@Test("chained contributions keep their order inside an element's tag")
	func chainedStylesInsideElement() {
		let html = Div { Text("x") }.padding(8).margin(2).render()
		#expect(html == "<div style=\"padding: 8px; margin: 2px;\">x</div>")
	}

	// MARK: the preamble wart — bug-compatibility, pinned on purpose

	@Test("the preamble wart keeps the string path's bytes")
	func preambleWartPreserved() {
		// the string path sliced the tag from the content start, so a preamble
		// of two or more name-ish characters parses as a bogus tag name and
		// mangles the output. this migration's contract is byte-identity, so the
		// buffer reproduces it; a fix must therefore be one deliberate decision
		// covering both paths at once.
		#expect(Raw("hi<div></div>").class("x").render() == "<i <div class=\"x\"></div>")
		#expect(Raw("hello world <div></div>").class("x").render() == "<ello world <div class=\"x\"></div>")
		// a one-character preamble falls into the legacy append, which is right
		#expect(Raw("a<div></div>").class("x").render() == "a<div class=\"x\"></div>")
	}

	// MARK: apply and decorate agree

	private func bufferOutput<M: ViewModifier>(_ modifier: M, over content: some View) -> String {
		var buffer = HTMLBuffer()
		modifier.decorate(content, into: &buffer)
		return buffer.finish()
	}

	@Test("a migrated modifier's string path and buffer path agree")
	func applyDecorateParity() {
		let style = InlineStyle(.padding, "4px")
		#expect(bufferOutput(style, over: Div { Text("x") }) == style.apply(to: Div { Text("x") }.render()))
		#expect(bufferOutput(style, over: Text("t")) == style.apply(to: Text("t").render()))
		let attribute = HTMLAttribute("data-x", "1")
		#expect(bufferOutput(attribute, over: Div { Text("x") }) == attribute.apply(to: Div { Text("x") }.render()))
		#expect(bufferOutput(attribute, over: Text("t")) == attribute.apply(to: Text("t").render()))
	}

	// MARK: composition and no-ops

	@Test("a noop modifier contributes nothing")
	func noopContributesNothing() {
		#expect(ModifiedView(content: Div { Text("x") }, modifier: NoopModifier()).render() == "<div>x</div>")
	}

	@Test("andThen composes in the same order on both paths")
	func composedOrder() {
		let composed = InlineStyle(.padding, "4px").andThen(HTMLAttribute("id", "i"))
		let expected = "<span style=\"padding: 4px;\" id=\"i\">t</span>"
		#expect(composed.apply(to: Text("t").render()) == expected)
		#expect(ModifiedView(content: Text("t"), modifier: composed).render() == expected)
	}

	// MARK: the deferred families, pinned

	@Test("the string-rewriting icon size modifier keeps its bytes")
	func iconSizeStaysStringPath() {
		let content = Raw("<svg class=\"icon icon--md\"></svg>")
		let html = ModifiedView(content: content, modifier: IconSizeModifier(size: .large)).render()
		#expect(html == "<svg class=\"icon icon--lg\"></svg>")
	}

	@Test("the eraser keeps the string path and agrees with the direct modifier")
	func eraserKeepsStringPath() {
		let direct = ModifiedView(content: Text("t"), modifier: InlineStyle(.padding, "4px")).render()
		let erased = ModifiedView(content: Text("t"), modifier: AnyViewModifier(InlineStyle(.padding, "4px"))).render()
		#expect(erased == direct)
		#expect(erased == "<span style=\"padding: 4px;\">t</span>")
	}

	private func renderIn<R: View>(_ router: EventRouter, _ build: () -> R) -> String {
		let ctx = RenderContext(router: router)
		return RenderContext.$current.withValue(ctx) { build().render() }
	}

	@Test("an auto-minting modifier still mints after its content renders (inner first)")
	func eventModifierMintsPostOrder() {
		let router = EventRouter()
		let handler: EventHandler = { _ in [] }
		let html = renderIn(router) {
			Div { Span { Text("x") }.onClick(perform: handler) }.onClick(perform: handler)
		}
		// inner mints c0, outer mints c1 — the string path's post-order. a
		// buffer migration that minted before rendering the content would
		// renumber every page that has nested minting.
		#expect(html.contains("<div data-component-id=\"c1\" data-event=\"click\">"))
		#expect(html.contains("<span data-component-id=\"c0\" data-event=\"click\">"))
		#expect(router.handlerCount == 2)
	}

	@Test("a mixed chain keeps the string path's attribute order")
	func mixedChainKeepsOrder() {
		let router = EventRouter()
		let handler: EventHandler = { _ in [] }
		let html = renderIn(router) {
			Div { Text("x") }.onClick(id: "s1", perform: handler).padding(4)
		}
		#expect(html == "<div data-component-id=\"s1\" data-event=\"click\" style=\"padding: 4px;\">x</div>")
	}

	@Test("a stable-id modifier outside a render context passes the content through")
	func stableIDWithoutContext() {
		#expect(Div { Text("x") }.onClick(id: "s1", perform: { _ in [] }).render() == "<div>x</div>")
	}
}