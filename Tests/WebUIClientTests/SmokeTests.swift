import Testing
import WebUICore
import WebUISmokeShared

// pure-logic specs for the client render core. these run in the host suite;
// the wasm side of the cross-host gate is `WebUIClient --verify-render` under
// WasmKit, byte-diffed against ssr in P1-T1 (render() is identical on both
// hosts by construction — one source).
struct SmokeTests {
	@Test("the render core produces a text node")
	func coreRenders() {
		#expect(Text("hello wasm").render() == "hello wasm")
	}

	@Test("primitives compose without host dependencies")
	func primitivesCompose() {
		let html = Div(class: "box") { Text("x") }.render()
		#expect(html.contains("<div class=\"box\">"))
		#expect(html.contains("x"))
		#expect(html.hasSuffix("</div>"))
	}

	@Test("the hydration view renders its baseline markup")
	func hydrationViewBaseline() {
		let html = HydrationView().render()
		#expect(html.contains("id=\"counter-value\""))
		#expect(html.contains(">3<"))
		#expect(html.contains("<svg"))
		#expect(html.contains("<table>"))
		#expect(html.contains("type=\"text\""))
	}
}
