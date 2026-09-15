import Testing
import WebUICore

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
}
