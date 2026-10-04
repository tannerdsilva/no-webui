import Testing
import WebUI
import WebUICore
import WebUIDesignSystem

// MARK: - t3.4 delivery tests (.lease(.echo, echoTo:) + input-parity modifiers)
//
// the wave-2 contract held firm: a hint WITHOUT a delivery target changes no
// bytes (pinned); the t3.4 wiring adds the *delivery* forms — an echo target
// emits the engine's `data-webui-echo` contract, and the input-parity
// modifiers emit the engine's forwarding descriptors. all additive.

@Suite("t3.4 delivery — echo + parity")
struct LeaseDeliveryTests {
	@Test("a bare .lease hint stays byte-identical (wave-2 pin, unchanged)")
	func bareHintStillInert() {
		let bare = Text("x").render()
		#expect(Text("x").lease(.echo).render() == bare)
		#expect(Text("x").lease(.viewport).render() == bare)
		// and no echo attribute leaks through either
		#expect(!Text("x").lease(.echo).render().contains("data-webui-echo"))
	}

	@Test(".lease(.echo, echoTo:) emits the engine's echo contract attribute")
	func echoDelivery() {
		// on an element-bearing region, the attribute merges into the root tag
		let region = Div { Text("a") }.lease(.echo, echoTo: "preview")
		let html = region.render()
		#expect(html.contains("<div data-webui-echo=\"preview\">"))
		// the wave-2 surface above this: only the delivery form emits bytes
		#expect(Div { Text("a") }.lease(.echo).render() == "<div>a</div>")
	}

	@Test("the echo target is html-escaped")
	func echoTargetEscaped() {
		let html = Div { Text("x") }.lease(.echo, echoTo: "a\"b<&").render()
		#expect(html.contains("data-webui-echo=\"a&quot;b&lt;&amp;\""))
	}

	@Test("echo + a parity descriptor compose (the brief's call shape)")
	func echoComposesWithParity() {
		let html = Div { Text("x") }
			.lease(.echo, echoTo: "preview")
			.inputParity(.key, .composition)
			.render()
		#expect(html.contains("data-webui-echo=\"preview\""))
		#expect(html.contains("data-webui-input='[\"key\",\"composition\"]'"))
	}

	@Test("the input-parity descriptor is canonical-ordered and closed")
	func parityDescriptor() {
		let mod = InputParityModifier([.composition, .key, .undo])
		// canonical order (the enum's declared order), not call order
		#expect(mod.descriptor == "data-webui-input='[\"key\",\"undo\",\"composition\"]'")
		#expect(InputParity.allCases.map(\.wireName) == ["key", "selection", "clipboard", "undo", "composition"])
	}

	@Test("an empty parity set emits nothing")
	func emptyParityInert() {
		let bare = Div { Text("x") }.render()
		#expect(Div { Text("x") }.inputParity().render() == bare)
	}

	@Test("compositionForwarded marks the input for ime forwarding")
	func compositionForwarding() {
		let html = Div { Text("x") }.compositionForwarded().render()
		#expect(html.contains("data-webui-composition=\"\""))
	}

	@Test("onKeyEvent opens the key channel and carries the typed handler")
	func keyEventDelivery() {
		let view = Div { Text("x") }.onKeyEvent { _ in }
		let html = view.render()
		#expect(html.contains("data-webui-input='[\"key\"]'"))
		// the handler is carried in the type (the .lease pattern) — the scan
		// reads it; here we prove it round-trips the modifier's type.
		#expect(view is ModifiedView<Div, KeyEventDeliveryModifier>)
		// the typed grammar is closed + equatable, and composes with parity
		let event = ParityKeyEvent(key: .arrowUp, modifiers: [.shift, .option])
		#expect(event.modifiers.contains(.shift))
		#expect(event.modifiers.contains(.option))
		#expect(event == ParityKeyEvent(key: .arrowUp, modifiers: [.shift, .option]))
	}
}
