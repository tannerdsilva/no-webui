import Testing
import WebUI

// the csp delta sheet (trajectory w§3.7): client-mode pages add
// `'wasm-unsafe-eval'` to a still-`'self'` policy; server-mode produces the
// nonce-only policy unchanged. the smoke server's client-demo probe page
// carries the exact csp shape below. `'unsafe-inline'` legitimately appears
// in `style-src` on both modes — the meaningful pin is the `script-src`
// directive, which must never carry it.
struct ClientCSPTests {
	private static let clientCSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"

	private static func renderDocument(csp: String? = nil, head: String = "") -> String {
		HTMLDocument(
			title: "t",
			body: "<div id=\"app\">x</div>",
			head: head,
			includeRuntime: false,
			contentSecurityPolicy: csp
		).render()
	}

	private static func scriptSrc(_ html: String) -> String {
		guard let r = html.range(of: "script-src ") else { return "" }
		if let end = html[r.upperBound...].firstIndex(of: ";") {
			return String(html[r.upperBound ..< end])
		}
		return String(html[r.upperBound...])
	}

	@Test("prod script-src is nonce-only: no unsafe-inline, no wasm-unsafe-eval")
	func prodScriptSrcNonceOnly() {
		let html = Self.renderDocument()
		let src = Self.scriptSrc(html)
		#expect(src.contains("'nonce-"))
		#expect(!src.contains("'unsafe-inline'"))
		#expect(!src.contains("'unsafe-eval'"))
		#expect(!src.contains("'wasm-unsafe-eval'"))
	}

	@Test("client-mode script-src is self + wasm-unsafe-eval, still no unsafe-inline")
	func clientScriptSrcCarriesWasmUnsafeEval() {
		let html = Self.renderDocument(csp: Self.clientCSP)
		let src = Self.scriptSrc(html)
		#expect(src.contains("'self'"))
		#expect(src.contains("'wasm-unsafe-eval'"))
		#expect(!src.contains("'unsafe-inline'"))
		#expect(!src.contains("'nonce-"))
		#expect(!src.contains("'unsafe-eval'"))
	}

	@Test("the client probe page links external scripts and embeds no runtime")
	func clientProbeLinksExternalScripts() {
		let head = "<script src=\"/__assets/webui-client.js\"></script>\n<script src=\"/__assets/client-demo-boot.js\"></script>"
		let html = Self.renderDocument(csp: Self.clientCSP, head: head)
		#expect(html.contains("webui-client.js"))
		#expect(html.contains("client-demo-boot.js"))
		#expect(!html.contains("WebUIRuntime.init"))
		#expect(Self.scriptSrc(html).contains("'wasm-unsafe-eval'"))
	}
}
