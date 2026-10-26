import Testing
import WebUI
import WebUISharedCore

// the modifier contract (`.hermes/plans/2026-09-28_123131-render-buffer-v2.md` §2.3, §3 S2):
// `decorate(_:into:)` is the ONE requirement — a modifier contributes through
// the buffer's pending slot and settles it at the element the content opened —
// and `apply(to:)` is derived from it, so a modifier has one implementation and
// both doors run that implementation. the census tests at the bottom assert the
// two doors agree byte-for-byte for every conformer the framework ships.
//
// content that opens no element (a bare string) is settled through the
// string-path rules instead: the `<span>` wrap, or the drop when the content
// opens with a comment/doctype/closing tag.

@Suite("modifier decorate")
struct ModifierDecorateTests {

	// MARK: the three §2.3 behaviours, through migrated modifiers

	@Test("a contribution lands in the first tag of buffer-native content")
	func contributionLandsInElement() {
		#expect(Div { Text("x") }.id("i").markup.html == "<div id=\"i\">x</div>")
		#expect(Div { Text("x") }.id("i").class("c").markup.html == "<div id=\"i\" class=\"c\">x</div>")
	}

	@Test("a contribution lands in the first tag of string-rendered content")
	func contributionLandsInStringContent() {
		#expect(Raw("<p>t</p>").attribute("data-x", "1").markup.html == "<p data-x=\"1\">t</p>")
		#expect(Div { Raw("<p>t</p>") }.class("c").markup.html == "<div class=\"c\"><p>t</p></div>")
	}

	@Test("content with no tag is wrapped in a span carrying the contribution")
	func noTagWrapsInSpan() {
		#expect(Text("just text").class("x").markup.html == "<span class=\"x\">just text</span>")
		#expect(Text("just text").attribute("id", "i").markup.html == "<span id=\"i\">just text</span>")
	}

	@Test("a declaration or closing tag first leaves the content untouched")
	func declarationFirstLeavesContentAlone() {
		#expect(Raw("<!-- c -->text").class("x").markup.html == "<!-- c -->text")
		#expect(Raw("<!doctype html><p>t</p>").class("x").markup.html == "<!doctype html><p>t</p>")
		#expect(Raw("</div>tail").class("x").markup.html == "</div>tail")
	}

	// MARK: chained contributions

	@Test("chained styles fold into one declaration list inside the span")
	func chainedStylesFoldInSpan() {
		// two style contributions must not ship as two style attributes: the
		// string path created the span with the first, then merged the second
		// into it. the buffer folds them in the same pass.
		let html = Text("Hello").foregroundColor("red").backgroundColor("blue").markup.html
		#expect(html == "<span style=\"color: red; background-color: blue;\">Hello</span>")
	}

	@Test("chained styles keep declaration order, innermost first")
	func chainedStylesKeepOrder() {
		let html = Text("Box").padding(8).margin(2).foregroundColor("red").markup.html
		#expect(html == "<span style=\"padding: 8px; margin: 2px; color: red;\">Box</span>")
	}

	@Test("chained contributions keep their order inside an element's tag")
	func chainedStylesInsideElement() {
		let html = Div { Text("x") }.padding(8).margin(2).markup.html
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
		#expect(Raw("hi<div></div>").class("x").markup.html == "<i <div class=\"x\"></div>")
		#expect(Raw("hello world <div></div>").class("x").markup.html == "<ello world <div class=\"x\"></div>")
		// a one-character preamble falls into the legacy append, which is right
		#expect(Raw("a<div></div>").class("x").markup.html == "a<div class=\"x\"></div>")
	}

	// MARK: the doors — every conformer, both content shapes

	/// both doors of one modifier, each rendered in its own fresh render context
	/// so the minting modifiers start from `c0` on both sides and the ids are
	/// comparable.
	private func bothDoors(
		_ modifier: any ViewModifier,
		over content: some View
	) -> (buffered: String, string: String) {
		let buffered = inFreshContext {
			var buffer = HTMLBuffer()
			modifier.decorate(content, into: &buffer)
			return buffer.finish()
		}
		let string = inFreshContext {
			modifier.apply(to: content.markup.html)
		}
		return (buffered, string)
	}

	private func inFreshContext<R>(_ body: () -> R) -> R {
		RenderContext.$current.withValue(RenderContext(router: EventRouter()), operation: body)
	}

	/// the census: one entry per `ViewModifier` conformer in the framework.
	/// adding a conformer without adding it here is what the "every" in the two
	/// test names below means to prevent.
	private func conformers() -> [(name: String, modifier: any ViewModifier)] {
		let handler: EventHandler = { _ in [] }
		return [
			("InlineStyle", InlineStyle(.padding, "4px")),
			("HTMLAttribute", HTMLAttribute("data-x", "1")),
			("AttributeContribution", AttributeContribution("data-y=\"2\"")),
			("AttributeContribution.empty", AttributeContribution("")),
			("NoopModifier", NoopModifier()),
			("ComposedModifier", ComposedModifier(
				first: InlineStyle(.padding, "4px"),
				second: HTMLAttribute("id", "i")
			)),
			("AnyViewModifier", AnyViewModifier(InlineStyle(.padding, "4px"))),
			("AnyViewModifier.noop", AnyViewModifier(NoopModifier())),
			("StableIDEventHandlerModifier", StableIDEventHandlerModifier(
				componentID: "s1",
				event: .click,
				handler: handler
			)),
			("EventHandlerModifier", EventHandlerModifier(event: .click, handler: handler)),
			("OptimisticClickModifier", OptimisticClickModifier(
				prediction: [FragmentUpdate(id: "a", html: "<b>1</b>")],
				handler: handler
			)),
			("IconSizeModifier.large", IconSizeModifier(size: .large)),
			("IconSizeModifier.slot", IconSizeModifier(size: .slot)),
		]
	}

	@Test("every modifier's string door and buffered door agree over element content")
	func everyConformerAgreesOverElement() {
		for conformer in conformers() {
			let doors = bothDoors(conformer.modifier, over: Div { Text("x") })
			#expect(
				doors.buffered == doors.string,
				"\(conformer.name): buffered \(doors.buffered) != string \(doors.string)"
			)
		}
	}

	@Test("every modifier's string door and buffered door agree over bare text")
	func everyConformerAgreesOverText() {
		for conformer in conformers() {
			let doors = bothDoors(conformer.modifier, over: Text("t"))
			#expect(
				doors.buffered == doors.string,
				"\(conformer.name): buffered \(doors.buffered) != string \(doors.string)"
			)
		}
	}

	@Test("an element modifier still writes the string path's bytes on both doors")
	func elementModifierBytes() {
		let style = InlineStyle(.padding, "4px")
		#expect(bothDoors(style, over: Div { Text("x") }).buffered == "<div style=\"padding: 4px;\">x</div>")
		#expect(bothDoors(style, over: Text("t")).buffered == "<span style=\"padding: 4px;\">t</span>")
		let attribute = HTMLAttribute("data-x", "1")
		#expect(bothDoors(attribute, over: Div { Text("x") }).buffered == "<div data-x=\"1\">x</div>")
		#expect(bothDoors(attribute, over: Text("t")).buffered == "<span data-x=\"1\">t</span>")
	}

	@Test("the auto-minting click modifier emits its routing pair on both doors")
	func eventHandlerBytes() {
		let handler: EventHandler = { _ in [] }
		let element = bothDoors(EventHandlerModifier(event: .click, handler: handler), over: Div { Text("x") })
		#expect(element.buffered == "<div data-component-id=\"c0\" data-event=\"click\">x</div>")
		#expect(element.string == element.buffered)
		let text = bothDoors(EventHandlerModifier(event: .submit, handler: handler), over: Text("t"))
		#expect(text.buffered == "<span data-component-id=\"c0\" data-event=\"submit\">t</span>")
		#expect(text.string == text.buffered)
	}

	@Test("the optimistic modifier emits data-event and the escaped prediction on both doors")
	func optimisticBytes() {
		let handler: EventHandler = { _ in [] }
		let modifier = OptimisticClickModifier(
			prediction: [FragmentUpdate(id: "a", html: "<b>1</b>")],
			handler: handler
		)
		let element = bothDoors(modifier, over: Div { Text("x") })
		#expect(element.buffered == element.string)
		#expect(element.buffered.hasPrefix("<div data-component-id=\"c0\" data-event=\"click\" data-optimistic=\"["))
		#expect(element.buffered.contains("&quot;html&quot;:&quot;&lt;b&gt;1&lt;/b&gt;&quot;"))
		#expect(element.buffered.contains("&quot;id&quot;:&quot;a&quot;"))
		#expect(element.buffered.hasSuffix("\">x</div>"))
	}

	// MARK: the minted id is the registered id AND the emitted id

	private final class ClickCounter: @unchecked Sendable {
		var clicks = 0
	}

	@Test("the id an auto-minting modifier emits is the id it registered")
	func mintedIDIsRegisteredAndEmitted() async {
		let counter = ClickCounter()
		let router = EventRouter()
		let html = RenderContext.$current.withValue(RenderContext(router: router)) {
			Div { Text("x") }.onClick { _ in counter.clicks += 1; return [] }.markup.html
		}
		// the one id on the element is the one the router answers to
		guard let start = html.range(of: "data-component-id=\"")?.upperBound,
		      let end = html[start...].firstIndex(of: "\"") else {
			Issue.record("no component id emitted: \(html)")
			return
		}
		let emitted = String(html[start..<end])
		#expect(router.handlerCount == 1)
		_ = await router.handle(EventData(component: ComponentID(emitted), event: "click", data: [:]))
		#expect(counter.clicks == 1, "handler registered under \(emitted) did not answer that id")
	}

	// MARK: composition and no-ops

	@Test("a noop modifier contributes nothing")
	func noopContributesNothing() {
		#expect(ModifiedView(content: Div { Text("x") }, modifier: NoopModifier()).markup.html == "<div>x</div>")
	}

	@Test("andThen composes in the same order on both paths")
	func composedOrder() {
		let composed = InlineStyle(.padding, "4px").andThen(HTMLAttribute("id", "i"))
		let expected = "<span style=\"padding: 4px;\" id=\"i\">t</span>"
		#expect(composed.apply(to: Text("t").markup.html) == expected)
		#expect(ModifiedView(content: Text("t"), modifier: composed).markup.html == expected)
	}

	// MARK: the token-rewriting and erasing conformers

	@Test("the class-rewriting icon size modifier is byte-identical on both doors")
	func iconSizeRetargetsBytes() {
		let content = Raw("<svg class=\"icon icon--md\" viewBox=\"0 0 24 24\" width=\"20\" height=\"20\" fill=\"none\"></svg>")
		let modifier = IconSizeModifier(size: .large)
		let expected = "<svg class=\"icon icon--lg\" viewBox=\"0 0 24 24\" width=\"1.25em\" height=\"1.25em\" fill=\"none\"></svg>"
		#expect(bothDoors(modifier, over: content).buffered == expected)
		#expect(bothDoors(modifier, over: content).string == expected)
		#expect(ModifiedView(content: content, modifier: IconSizeModifier(size: .slot)).markup.html
			== "<svg class=\"icon\" viewBox=\"0 0 24 24\" fill=\"none\"></svg>")
	}

	@Test("the eraser keeps the string path and agrees with the direct modifier")
	func eraserKeepsStringPath() {
		let direct = ModifiedView(content: Text("t"), modifier: InlineStyle(.padding, "4px")).markup.html
		let erased = ModifiedView(content: Text("t"), modifier: AnyViewModifier(InlineStyle(.padding, "4px"))).markup.html
		#expect(erased == direct)
		#expect(erased == "<span style=\"padding: 4px;\">t</span>")
	}

	private func renderIn<R: View>(_ router: EventRouter, _ build: () -> R) -> String {
		let ctx = RenderContext(router: router)
		return RenderContext.$current.withValue(ctx) { build().markup.html }
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
		#expect(Div { Text("x") }.onClick(id: "s1", perform: { _ in [] }).markup.html == "<div>x</div>")
	}
}
